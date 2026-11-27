## MoDB Milestone 17 (`v0.9.0`): Continuous HTTP Pull-Replica Sync Client (`Modb.Pull`).
##
## Consumes HTTP `/<peer_id>/snapshot`, `/<peer_id>/export`, and `/<peer_id>/ack` endpoints
## (compatible with both AgentWorkbench `/sync/peers` and Motet `/v1/modb/sync/peers`):
## - Automatically bootstraps a missing `<replica.modb>` via `/snapshot` (plus mid-stream cursor
##   seeding when `/sync/peers` reports `acked_seq > 0`) and verifies the imported CoW B+Tree.
## - Verifies & decrypts (optional AES-256-GCM keyring/key + AAD, failing closed against
##   downgrade/tampering) hash-chained deltas and commits locally before posting `/ack`.
## - Auto-recovers from lost-ack crashes (`ChainMismatch` with `actual_seq == expected_seq - 1`
##   and matching local `replica:<peer_id>` cursor).
module Modb.Pull
expose PullError(..), PullConfig(..), PullCycleReport(..), to_text, pull_once, pull_loop
use Crypto
use Http
use Json
use Modb
use Modb.Export{PortableSnapshot}
use Modb.Sync{SealedEnvelope, SyncDelta, SyncPeer}

## Every failure raised by `Modb.Pull`.
enum PullError
  SyncFailure(Sync.SyncError)
  ExportFailure(Export.ExportError)
  HttpFailed(url: Text, status: Int, detail: Text)
  NetworkFailed(url: Text, detail: Text)
  DecodeFailed(context: Text, detail: Text)
  InvalidConfig(reason: Text)
  IoFailure(detail: Text)
end

## Formats a `PullError` cleanly without leaking bearer tokens or key bytes.
fn to_text(err: PullError) : Text
  case err
    SyncFailure(e): Sync.to_text(e)
    ExportFailure(e): Export.to_text(e)
    HttpFailed(url: u, status: st, detail: d):
      suffix = if d.trim.empty?: "" else: ": #{d.trim}"
      "HTTP #{st} from #{u}#{suffix}"
    NetworkFailed(url: u, detail: d): "network error calling #{u}: #{d}"
    DecodeFailed(context: c, detail: d): "decode failure (#{c}): #{d}"
    InvalidConfig(reason: r): "invalid pull config: #{r}"
    IoFailure(detail: d): "io failure: #{d}"
  end
end

## Configuration for pulling snapshots & incremental hash-chained deltas from a peer HTTP endpoint.
struct PullConfig
  base_url: Text
  peer_id: Text
  replica_path: Text
  bearer_token: Option(Text)
  decrypt?: Bool
  key: Option(Bytes)
  keyring: Option(Map(Text, Bytes))
  key_id: Option(Text)
  aad: Text
  timeout_seconds: Int
end

## Structured summary returned by one `pull_once` cycle (usable cleanly as JSON).
struct PullCycleReport
  peer_id: Text
  bootstrapped?: Bool
  base_txid: Int
  delta_seq: Int
  puts_applied: Int
  deletes_applied: Int
  after_txid: Int
  delta_hash: Text
  acked?: Bool
end

fn strip_trailing_slashes(raw: Text) : Text
  var s = raw.trim
  while (not s.empty?) and s.ends_with?("/")
    cs = s.chars
    s = Text.from_chars(cs.take(cs.size - 1))
  end
  s
end

fn parse_allowed_hosts(base_url: Text) : Result((Text, List(Text)), PullError)
  clean = strip_trailing_slashes(base_url)
  (scheme, rest) = if clean.starts_with?("https://")
    ("https", clean.drop_prefix("https://") or "")
  else if clean.starts_with?("http://")
    ("http", clean.drop_prefix("http://") or "")
  else
    return Error(InvalidConfig(reason: "base_url must start with http:// or https://"))
  end
  host_part = (rest.split("/").first or "").trim
  if host_part.empty?
    return Error(InvalidConfig(reason: "base_url missing host"))
  end
  hosts = if host_part.contains?(":")
    [host_part]
  else
    def_port = if scheme == "https": 443 else: 80
    [host_part, "#{host_part}:#{def_port}"]
  end
  Ok((clean, hosts))
end

fn validate_config(cfg: PullConfig) : Result((Text, List(Text)), PullError)
  if cfg.peer_id.trim.empty?
    return Error(InvalidConfig(reason: "peer_id cannot be empty"))
  end
  if cfg.replica_path.trim.empty?
    return Error(InvalidConfig(reason: "replica_path cannot be empty"))
  end
  if cfg.decrypt? and (cfg.key is None) and (cfg.keyring is None)
    return Error(
      InvalidConfig(reason: "decryption requested but neither key nor keyring is configured")
    )
  end
  parse_allowed_hosts(cfg.base_url)
end

fn apply_pull_headers(req: Http.Request, cfg: PullConfig) : Http.Request
  var r = req.header("Accept", "application/json")
  case cfg.bearer_token
    Some(tok) if not tok.trim.empty?:
      t = tok.trim
      hdr = if t.starts_with?("Bearer ") or t.starts_with?("bearer "): t else: "Bearer #{t}"
      r = r.header("Authorization", hdr)
    Some(_) | None: Unit
  end
  secs = if cfg.timeout_seconds > 0: cfg.timeout_seconds else: 30
  r.within(secs.seconds)
end

fn append_encrypt_queries(req: Http.Request, cfg: PullConfig) : Http.Request
  return req if not cfg.decrypt?
  var r = req.query("encrypt", "true")
  case cfg.key_id
    Some(kid) if not kid.trim.empty?: r = r.query("key_id", kid.trim)
    Some(_) | None: Unit
  end
  if not cfg.aad.empty?
    r = r.query("aad", cfg.aad)
  end
  r
end

fn send_http(net: Network, url: Text, req: Http.Request) : Result(Http.Response, PullError)
  resp = try req.send(net).map_error(fn(e) NetworkFailed(url: url, detail: e.to_text) end)
  if not resp.ok?
    detail = (resp.text or "").trim
    return Error(HttpFailed(url: url, status: resp.status, detail: detail))
  end
  Ok(resp)
end

fn decode_snapshot_payload(raw_txt: Text, cfg: PullConfig) : Result(PortableSnapshot, PullError)
  if cfg.decrypt?
    senv = case Json.decode[SealedEnvelope](raw_txt)
      Ok(e): e
      Error(je): return Error(DecodeFailed(context: "sealed snapshot envelope", detail: je.to_text))
    end
    case cfg.keyring
      Some(kr): Sync.open_snapshot_with_keyring(kr, cfg.aad, senv).map_error(
        fn(e) SyncFailure(e) end
      )
      None:
        key = try cfg.key.or_fail(InvalidConfig(reason: "missing decryption key"))
        Sync.open_snapshot(key, cfg.aad, senv).map_error(fn(e) SyncFailure(e) end)
    end
  else
    case Json.decode[PortableSnapshot](raw_txt)
      Ok(s):
        _ = try Export.verify_snapshot(s).map_error(fn(e) ExportFailure(e) end)
        Ok(s)
      Error(je): Error(DecodeFailed(context: "portable snapshot", detail: je.to_text))
    end
  end
end

fn decode_delta_payload(raw_txt: Text, cfg: PullConfig) : Result(SyncDelta, PullError)
  if cfg.decrypt?
    senv = case Json.decode[SealedEnvelope](raw_txt)
      Ok(e): e
      Error(je): return Error(DecodeFailed(context: "sealed delta envelope", detail: je.to_text))
    end
    case cfg.keyring
      Some(kr): Sync.open_delta_with_keyring(kr, cfg.aad, senv).map_error(fn(e) SyncFailure(e) end)
      None:
        key = try cfg.key.or_fail(InvalidConfig(reason: "missing decryption key"))
        Sync.open_delta(key, cfg.aad, senv).map_error(fn(e) SyncFailure(e) end)
    end
  else
    case Json.decode[SyncDelta](raw_txt)
      Ok(d):
        _ = try Sync.verify_delta(d).map_error(fn(e) SyncFailure(e) end)
        Ok(d)
      Error(je): Error(DecodeFailed(context: "sync delta", detail: je.to_text))
    end
  end
end

fn probe_server_peer(net: Network, base: Text, cfg: PullConfig) : Option(SyncPeer)
  req = apply_pull_headers(Http.get(base), cfg)
  case req.send(net)
    Ok(resp) if resp.ok?:
      txt = resp.text or ""
      case Json.decode[List(SyncPeer)](txt)
        Ok(peers):
          for p in peers
            if p.peer_id == cfg.peer_id.trim
              return Some(p)
            end
          end
          None
        Error(_): None
      end
    Ok(_) | Error(_): None
  end
end

fn post_ack_request(net: Network, base: Text, cfg: PullConfig, seq: Int, delta_hash: Text) : Result(
  Unit,
  PullError
)
  ack_url = "#{base}/#{cfg.peer_id.trim}/ack"
  body = Json.Object({"seq": Json.int(seq), "delta_hash": Json.String(delta_hash)})
  req = apply_pull_headers(Http.post(ack_url), cfg).json(body)
  _resp = try send_http(net, ack_url, req)
  Ok(Unit)
end

fn fetch_and_decode_delta(net: Network, base: Text, cfg: PullConfig) : Result(SyncDelta, PullError)
  exp_url = "#{base}/#{cfg.peer_id.trim}/export"
  req = apply_pull_headers(append_encrypt_queries(Http.post(exp_url), cfg), cfg)
  resp = try send_http(net, exp_url, req)
  txt = resp.text or ""
  decode_delta_payload(txt, cfg)
end

fn bootstrap_replica(files: Files, net: Network, clock: Clock, base: Text, cfg: PullConfig) : Result(
  Int,
  PullError
)
  peer_meta_opt = probe_server_peer(net, base, cfg)
  snap_url = "#{base}/#{cfg.peer_id.trim}/snapshot"
  req = apply_pull_headers(append_encrypt_queries(Http.post(snap_url), cfg), cfg)
  resp = try send_http(net, snap_url, req)
  snap = try decode_snapshot_payload(resp.text or "", cfg)

  tmp_path = "#{cfg.replica_path}.pull-boot.tmp"
  _rm0 = files.remove(tmp_path)
  st = case Export.import_file(files, tmp_path, snap)
    Ok(s): s
    Error(ee):
      _rm1 = files.remove(tmp_path)
      return Error(ExportFailure(ee))
  end
  case Modb.verify(st)
    Ok(_): Unit
    Error(me):
      _rm2 = files.remove(tmp_path)
      return Error(SyncFailure(Sync.StorageFailure(me)))
  end
  case files.rename(tmp_path, cfg.replica_path)
    Ok(Unit): Unit
    Error(fe):
      _rm3 = files.remove(tmp_path)
      return Error(IoFailure(detail: fe.to_text))
  end

  case peer_meta_opt
    Some(sp) if sp.acked_seq > 0: _ = try Sync.seed_replica_cursor_locked(
      files,
      cfg.replica_path,
      cfg.peer_id.trim,
      sp.acked_seq,
      sp.acked_txid,
      sp.acked_hash,
      sp.include_internal?,
      sp.from_empty?,
      clock.now
    ).map_error(fn(e) SyncFailure(e) end)
    Some(_) | None: Unit
  end
  Ok(snap.source_txid)
end

## Executes one crash-safe pull cycle:
## 1. Bootstraps `<replica.modb>` via `/snapshot` if missing;
## 2. Fetches & verifies `/export` delta (decrypting + verifying SHA-256 chain);
## 3. Commits durably via `Sync.apply_delta_tracked_locked` (auto-healing lost prior `/ack`);
## 4. Posts `/ack` ONLY after local durable commit succeeds.
fn pull_once(files: Files, network: Network, clock: Clock, cfg: PullConfig) : Result(
  PullCycleReport,
  PullError
)
  (base, hosts) = try validate_config(cfg)
  pinned = network.allow_hosts(hosts)
  pid = cfg.peer_id.trim

  var bootstrapped? = false
  var base_txid = 0
  if not files.read_only.exists?(cfg.replica_path)
    base_txid = try bootstrap_replica(files, pinned, clock, base, cfg)
    bootstrapped? = true
  end

  delta0 = try fetch_and_decode_delta(pinned, base, cfg)
  rep = case Sync.apply_delta_tracked_locked(files, cfg.replica_path, delta0, clock.now)
    Ok(r): r
    Error(
      Sync.ChainMismatch(
        expected_seq: es,
        actual_seq: acs,
        expected_prev_hash: _,
        actual_prev_hash: _
      )
    ) if acs == es - 1:
      cur = try Sync.get_replica_cursor_locked(files.read_only, cfg.replica_path, pid).map_error(
        fn(e) SyncFailure(e) end
      )
      case cur
        Some(local_peer) if local_peer.acked_seq == acs:
          ## Previous pull committed locally then crashed/failed before /ack succeeded: heal /ack and retry.
          _ack_old = try post_ack_request(
            pinned,
            base,
            cfg,
            local_peer.acked_seq,
            local_peer.acked_hash
          )
          delta_retry = try fetch_and_decode_delta(pinned, base, cfg)
          try Sync.apply_delta_tracked_locked(files, cfg.replica_path, delta_retry, clock.now)
            .map_error(fn(e) SyncFailure(e) end)
        Some(_) | None: return Error(
          SyncFailure(
            Sync.ChainMismatch(
              expected_seq: es,
              actual_seq: acs,
              expected_prev_hash: delta0.prev_hash,
              actual_prev_hash: delta0.prev_hash
            )
          )
        )
      end
    Error(se): return Error(SyncFailure(se))
  end

  _ = try post_ack_request(pinned, base, cfg, rep.seq, rep.delta_hash)
  Ok(
    PullCycleReport(
      peer_id: rep.peer_id,
      bootstrapped?: bootstrapped?,
      base_txid: base_txid,
      delta_seq: rep.seq,
      puts_applied: rep.puts_applied,
      deletes_applied: rep.deletes_applied,
      after_txid: rep.after_txid,
      delta_hash: rep.delta_hash,
      acked?: true
    )
  )
end

## Continuous pull loop sleeping `interval_secs` between cycles (optional `max_cycles_opt` for bounded runs).
fn pull_loop(
  files: Files,
  network: Network,
  clock: Clock,
  console: Console,
  cfg: PullConfig,
  interval_secs: Int,
  max_cycles_opt: Option(Int),
  json?: Bool
) : Int
  wait_secs = if interval_secs > 0: interval_secs else: 5
  var cycle = 0
  while true
    case max_cycles_opt
      Some(cap) if cycle >= cap: return 0
      Some(_) | None: Unit
    end
    cycle += 1
    case pull_once(files, network, clock, cfg)
      Ok(rep):
        if json?
          console.print(Json.encode(rep.to_json))
        else
          console.print(
            "MoDB sync pull ok peer=#{rep.peer_id} boot=#{rep.bootstrapped?} seq=#{rep.delta_seq} puts=#{rep
              .puts_applied} dels=#{rep.deletes_applied} tx=#{rep.after_txid} acked=#{rep.acked?}"
          )
        end
      Error(pe): console.error("pull cycle #{cycle} error: #{to_text(pe)}")
    end
    case max_cycles_opt
      Some(cap) if cycle >= cap: return 0
      Some(_) | None: Unit
    end
    clock.sleep(wait_secs.seconds)
  end
  0
end

test "Modb.Pull: plain & encrypted keyring pull, lost-ack auto-recovery, and fail-closed checks"
  t0 = Time.parse("2026-11-26T22:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  srng = SecureRandom.seeded(77)

  # Build primary on separate in-memory Files and generate snapshot + 2 deltas
  src_files = Files.in_memory({})
  assert Modb.open(src_files, "primary.modb") is Ok(p0)
  tx0 = Modb.begin_write(p0)
  assert Modb.tx_put(tx0, "items", "a".bytes, "1".bytes) is Ok(tx0b)
  assert Modb.commit(tx0b) is Ok(p1)
  assert Sync.init_peer(p1, "r1", false, false, t0) is Ok((p2, peer0))
  assert Sync.export_peer_base_snapshot(p2, "r1", t0) is Ok(snap0)

  # Primary writes item b -> Delta 1
  tx1 = Modb.begin_write(p2)
  assert Modb.tx_put(tx1, "items", "b".bytes, "2".bytes) is Ok(tx1b)
  assert Modb.commit(tx1b) is Ok(p3)
  assert Sync.export_delta(p3, "r1", t0) is Ok((p4, d1))
  assert Sync.ack_peer(p4, "r1", d1.seq, d1.delta_hash, t0) is Ok((p5, _))

  # Primary writes item c -> Delta 2
  tx2 = Modb.begin_write(p5)
  assert Modb.tx_put(tx2, "items", "c".bytes, "3".bytes) is Ok(tx2b)
  assert Modb.commit(tx2b) is Ok(p6)
  assert Sync.export_delta(p6, "r1", t0) is Ok((_p7, d2))

  # Test 1: Plain pull + Lost-ack crash recovery (Cycle 1 ack fails 500 -> Cycle 2 auto-heals & fetches d2!)
  snap_json = Export.encode_snapshot_json(snap0)
  d1_json = Sync.encode_delta_json(d1)
  d2_json = Sync.encode_delta_json(d2)
  peers_list_json = Json.encode([peer0].to_json)

  net_heal = Network.fake_scripted([
    (
      "GET",
      "http://127.0.0.1:8099/sync/peers",
      [Network.Respond(response: Http.reply(200, peers_list_json))]
    ),
    (
      "POST",
      "http://127.0.0.1:8099/sync/peers/r1/snapshot",
      [Network.Respond(response: Http.reply(200, snap_json))]
    ),
    (
      "POST",
      "http://127.0.0.1:8099/sync/peers/r1/export",
      [
        Network.Respond(response: Http.reply(200, d1_json)),
        Network.Respond(response: Http.reply(200, d1_json)),
        Network.Respond(response: Http.reply(200, d2_json))
      ]
    ),
    (
      "POST",
      "http://127.0.0.1:8099/sync/peers/r1/ack",
      [
        Network.Respond(response: Http.reply(500, "simulated crash before ack")),
        Network.Respond(response: Http.reply(200, "{\"ok\":true}")),
        Network.Respond(response: Http.reply(200, "{\"ok\":true}"))
      ]
    )
  ])

  dst_files = Files.in_memory({})
  cfg_plain = PullConfig(
    base_url: "http://127.0.0.1:8099/sync/peers",
    peer_id: "r1",
    replica_path: "replica.modb",
    bearer_token: Some("tok-admin"),
    decrypt?: false,
    key: None,
    keyring: None,
    key_id: None,
    aad: "",
    timeout_seconds: 10
  )
  # Cycle 1 commits snap0 + d1 locally then hits simulated HTTP 500 on /ack
  assert pull_once(dst_files, net_heal, clock, cfg_plain) is
    Error(HttpFailed(url: _, status: 500, detail: _))
  # Cycle 2 receives stale d1 again -> detects local cursor seq=1 -> heals /ack(1) -> pulls & acks d2!
  assert pull_once(dst_files, net_heal, clock, cfg_plain) is Ok(rep2)
  assert (not rep2.bootstrapped?) and rep2.delta_seq == 2 and rep2.acked?

  assert Modb.open_read_only(dst_files.read_only, "replica.modb") is Ok(rep_st)
  assert Modb.get(rep_st, "items", "a".bytes) == Ok(Some("1".bytes))
  assert Modb.get(rep_st, "items", "b".bytes) == Ok(Some("2".bytes))
  assert Modb.get(rep_st, "items", "c".bytes) == Ok(Some("3".bytes))
  assert Modb.verify(rep_st) is Ok(_)

  # Test 2: Encrypted keyring-rotated pull (k1 snapshot -> k2 delta)
  k1 = Crypto.sha256("pull-key-1".bytes)
  k2 = Crypto.sha256("pull-key-2".bytes)
  kr = {"k1": k1, "k2": k2}
  assert Sync.seal_snapshot(srng, k1, "k1", "modb:rep", snap0, t0) is Ok(esnap)
  assert Sync.seal_delta(srng, k2, "k2", "modb:rep", d1, t0) is Ok(ed1)

  net_enc = Network.fake_scripted([
    (
      "GET",
      "http://127.0.0.1:8099/sync/peers",
      [Network.Respond(response: Http.reply(200, peers_list_json))]
    ),
    (
      "POST",
      "http://127.0.0.1:8099/sync/peers/r1/snapshot",
      [Network.Respond(response: Http.reply(200, Sync.encode_sealed_json(esnap)))]
    ),
    (
      "POST",
      "http://127.0.0.1:8099/sync/peers/r1/export",
      [Network.Respond(response: Http.reply(200, Sync.encode_sealed_json(ed1)))]
    ),
    (
      "POST",
      "http://127.0.0.1:8099/sync/peers/r1/ack",
      [Network.Respond(response: Http.reply(200, "{\"ok\":true}"))]
    )
  ])
  enc_files = Files.in_memory({})
  cfg_enc = PullConfig(
    base_url: "http://127.0.0.1:8099/sync/peers",
    peer_id: "r1",
    replica_path: "replica-enc.modb",
    bearer_token: None,
    decrypt?: true,
    key: None,
    keyring: Some(kr),
    key_id: Some("k2"),
    aad: "modb:rep",
    timeout_seconds: 10
  )
  assert pull_once(enc_files, net_enc, clock, cfg_enc) is Ok(rep_enc)
  assert rep_enc.bootstrapped? and rep_enc.delta_seq == 1 and rep_enc.acked?
  assert Modb.open_read_only(enc_files.read_only, "replica-enc.modb") is Ok(enc_st)
  assert Modb.get(enc_st, "items", "b".bytes) == Ok(Some("2".bytes))

  # Test 3: Wrong key / tampered ciphertext fails closed and NEVER sends /ack!
  bad_files = Files.in_memory({})
  net_bad = Network.fake_scripted([
    (
      "GET",
      "http://127.0.0.1:8099/sync/peers",
      [Network.Respond(response: Http.reply(200, peers_list_json))]
    ),
    (
      "POST",
      "http://127.0.0.1:8099/sync/peers/r1/snapshot",
      [Network.Respond(response: Http.reply(200, Sync.encode_sealed_json(esnap)))]
    ),
    (
      "POST",
      "http://127.0.0.1:8099/sync/peers/r1/export",
      [Network.Respond(response: Http.reply(200, Sync.encode_sealed_json(ed1)))]
    )
  ])
  cfg_bad = PullConfig(
    base_url: "http://127.0.0.1:8099/sync/peers",
    peer_id: "r1",
    replica_path: "bad.modb",
    bearer_token: None,
    decrypt?: true,
    key: None,
    keyring: Some({"k1": k1}),
    key_id: None,
    aad: "modb:rep",
    timeout_seconds: 10
  )
  assert pull_once(bad_files, net_bad, clock, cfg_bad) is
    Error(SyncFailure(Sync.KeyNotFound(key_id: "k2")))
  # Bootstrap occurred, delta 1 failed key lookup -> /ack MUST NOT have been called!
  calls = Network.recorded_calls(net_bad)
  assert not calls.any?(fn(c) c.url.contains?("/ack") end)
end
