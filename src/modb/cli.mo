## Standalone schema-less `modb` CLI (`inspect`, `verify`, `dump`, `audit`, `worlds`, `fts`, `vec`,
## `policy`, `proposals`, `feeds`, `matviews`, `taint`, `erasures`, `sync`, `backup`, `export`, `restore`, `compact`, `diff`). Works on any
## `.modb` database file safely using advisory `flock` coordination and read-only `ReadFiles`.
module Modb.Cli
expose run_cli,
run_cli_with,
main
use Json
use Modb{Store}
use Modb.Claims
use Modb.Erasure
use Modb.Errors{wrap_io}
use Modb.Export{PortableSnapshot}
use Modb.Feeds
use Modb.Fts
use Modb.Grants
use Modb.Ledger{SchemaState, genesis_hash, meta_bucket}
use Modb.Matview
use Modb.Pager{from_file}
use Modb.Policy
use Modb.Proposals
use Modb.Sync{SealedEnvelope, SyncDelta}
use Modb.Table
use Modb.Taint
use Modb.Tree{KeyDiff}
use Modb.Vec
use Modb.Views
use Modb.World

fn print_usage(console: Console) : Unit
  console.print(
    [
      "modb - pure-Mo CoW B+Tree & accountable agent database CLI",
      "",
      "Usage:",
      "  modb inspect <db.modb> [--json]",
      "  modb verify <db.modb> [--fast [N]] [--json]",
      "  modb dump <db.modb> <bucket> [--limit N] [--json]",
      "  modb audit <db.modb> [--limit N] [--principal P] [--action A] [--json]",
      "  modb worlds <db.modb> [--json]",
      "  modb fts <db.modb> [prefix] [query...] [--scope S] [--prefix] [--limit N] [--json]",
      "  modb vec <db.modb> [prefix] [--json]",
      "  modb policy <db.modb> [--json]",
      "  modb proposals <db.modb> [--status pending|approved|rejected|withdrawn] [--json]",
      "  modb feeds <db.modb> [--json]",
      "  modb feeds <db.modb> poll <feed_id> [--limit N] [--json]",
      "  modb matviews <db.modb> [list|refresh <name>|rebuild <name>|query <name>] [--min-k N] [--json]",
      "  modb taint <db.modb> [--json]",
      "  modb erasures <db.modb> [--json]",
      "  modb sync <db.modb> init-peer <peer_id> [--include-internal] [--from-empty] [--json]",
      "  modb sync <db.modb> peers [--json]",
      "  modb sync <db.modb> base-snapshot <peer_id> <out.json> [--encrypt] [--key-file <p>|--key-env <V>] [--key-id <id>] [--aad <t>]",
      "  modb sync <db.modb> export <peer_id> <out.json> [--encrypt] [--key-file <p>|--key-env <V>] [--key-id <id>] [--aad <t>] [--json]",
      "  modb sync <db.modb> ack <peer_id> --seq <N> --hash <hex> [--json]",
      "  modb sync <db.modb> apply <delta.json> [--decrypt] [--key-file <p>|--key-env <V>] [--aad <t>] [--json]",
      "  modb sync <db.modb> remove-peer <peer_id>",
      "  modb sync <dst.modb> restore --base <snap.json> [<delta1.json> ...] [--decrypt] [--key-file <p>|--key-env <V>] [--aad <t>] [--json]",
      "  modb backup <src.modb> <dst.modb> [--include-internal]",
      "  modb export <src.modb> <out.json> [--include-internal]",
      "  modb restore <in.json> <dst.modb>",
      "  modb compact <db.modb> [--include-internal]",
      "  modb diff <a.modb> <b.modb> [--include-internal] [--json]",
      "  modb diff <db.modb> --pin <pin_id> [--include-internal] [--json]"
    ].join("\n")
  )
end

struct ParsedFlags
  positional: List(Text)
  json?: Bool
  include_internal?: Bool
  fast?: Bool
  fast_window: Int
  limit_opt: Option(Int)
  min_k_opt: Option(Int)
  principal_opt: Option(Text)
  action_opt: Option(Text)
  pin_opt: Option(Text)
  scope_opt: Option(Text)
  status_opt: Option(Text)
  prefix?: Bool
  key_file_opt: Option(Text)
  key_env_opt: Option(Text)
  keyring_file_opt: Option(Text)
  keyring_env_opt: Option(Text)
  key_id_opt: Option(Text)
  aad_opt: Option(Text)
  encrypt?: Bool
  decrypt?: Bool
  from_empty?: Bool
  base_opt: Option(Text)
  seq_opt: Option(Int)
  hash_opt: Option(Text)
end

fn parse_flags(rest: List(Text)) : Result(ParsedFlags, Text)
  var pos = []
  var json? = false
  var include_internal? = false
  var fast? = false
  var fast_window = 100
  var limit_opt = None
  var min_k_opt = None
  var principal_opt = None
  var action_opt = None
  var pin_opt = None
  var scope_opt = None
  var status_opt = None
  var prefix? = false
  var key_file_opt = None
  var key_env_opt = None
  var keyring_file_opt = None
  var keyring_env_opt = None
  var key_id_opt = None
  var aad_opt = None
  var encrypt? = false
  var decrypt? = false
  var from_empty? = false
  var base_opt = None
  var seq_opt = None
  var hash_opt = None
  var i = 0
  while i < rest.size
    tok = rest.get(i) or ""
    if tok == "--json"
      json? = true
      i += 1
    else if tok == "--include-internal"
      include_internal? = true
      i += 1
    else if tok == "--encrypt"
      encrypt? = true
      i += 1
    else if tok == "--decrypt"
      decrypt? = true
      i += 1
    else if tok == "--from-empty"
      from_empty? = true
      i += 1
    else if tok == "--fast"
      fast? = true
      case rest.get(i + 1)
        Some(nxt) if not nxt.starts_with?("--"):
          case nxt.to_int
            Some(n) if n > 0:
              fast_window = n
              i += 2
            Some(_): return Error("--fast window must be a positive integer")
            None: i += 1
          end
        Some(_) | None: i += 1
      end
    else if tok == "--limit"
      val = try rest.get(i + 1).or_fail("--limit requires a value")
      n = try val.to_int.or_fail("invalid --limit integer: #{val}")
      limit_opt = Some(n)
      i += 2
    else if tok == "--min-k"
      val = try rest.get(i + 1).or_fail("--min-k requires a value")
      n = try val.to_int.or_fail("invalid --min-k integer: #{val}")
      min_k_opt = Some(n)
      i += 2
    else if tok == "--seq"
      val = try rest.get(i + 1).or_fail("--seq requires a value")
      n = try val.to_int.or_fail("invalid --seq integer: #{val}")
      seq_opt = Some(n)
      i += 2
    else if tok == "--principal"
      val = try rest.get(i + 1).or_fail("--principal requires a value")
      principal_opt = Some(val)
      i += 2
    else if tok == "--action"
      val = try rest.get(i + 1).or_fail("--action requires a value")
      action_opt = Some(val)
      i += 2
    else if tok == "--pin"
      val = try rest.get(i + 1).or_fail("--pin requires a value")
      pin_opt = Some(val)
      i += 2
    else if tok == "--scope"
      val = try rest.get(i + 1).or_fail("--scope requires a value")
      scope_opt = Some(val)
      i += 2
    else if tok == "--status"
      val = try rest.get(i + 1).or_fail("--status requires a value")
      status_opt = Some(val)
      i += 2
    else if tok == "--prefix"
      prefix? = true
      i += 1
    else if tok == "--key-file"
      val = try rest.get(i + 1).or_fail("--key-file requires a value")
      key_file_opt = Some(val)
      i += 2
    else if tok == "--key-env"
      val = try rest.get(i + 1).or_fail("--key-env requires a value")
      key_env_opt = Some(val)
      i += 2
    else if tok == "--keyring-file"
      val = try rest.get(i + 1).or_fail("--keyring-file requires a value")
      keyring_file_opt = Some(val)
      i += 2
    else if tok == "--keyring-env"
      val = try rest.get(i + 1).or_fail("--keyring-env requires a value")
      keyring_env_opt = Some(val)
      i += 2
    else if tok == "--key-id"
      val = try rest.get(i + 1).or_fail("--key-id requires a value")
      key_id_opt = Some(val)
      i += 2
    else if tok == "--aad"
      val = try rest.get(i + 1).or_fail("--aad requires a value")
      aad_opt = Some(val)
      i += 2
    else if tok == "--base"
      val = try rest.get(i + 1).or_fail("--base requires a value")
      base_opt = Some(val)
      i += 2
    else if tok == "--hash"
      val = try rest.get(i + 1).or_fail("--hash requires a value")
      hash_opt = Some(val)
      i += 2
    else if tok.starts_with?("--")
      return Error("unknown flag: #{tok}")
    else
      pos = pos.append(tok)
      i += 1
    end
  end
  Ok(
    ParsedFlags(
      positional: pos,
      json?: json?,
      include_internal?: include_internal?,
      fast?: fast?,
      fast_window: fast_window,
      limit_opt: limit_opt,
      min_k_opt: min_k_opt,
      principal_opt: principal_opt,
      action_opt: action_opt,
      pin_opt: pin_opt,
      scope_opt: scope_opt,
      status_opt: status_opt,
      prefix?: prefix?,
      key_file_opt: key_file_opt,
      key_env_opt: key_env_opt,
      keyring_file_opt: keyring_file_opt,
      keyring_env_opt: keyring_env_opt,
      key_id_opt: key_id_opt,
      aad_opt: aad_opt,
      encrypt?: encrypt?,
      decrypt?: decrypt?,
      from_empty?: from_empty?,
      base_opt: base_opt,
      seq_opt: seq_opt,
      hash_opt: hash_opt
    )
  )
end

fn decode_printable_text(raw: Bytes) : Option(Text)
  case raw.decode_utf8
    None: None
    Some(s):
      for c in s.chars
        if c < ' ' and c != '\t' and c != '\n' and c != '\r'
          return None
        end
      end
      Some(s)
  end
end

fn format_bytes_preview(raw: Bytes) : Text
  case decode_printable_text(raw)
    Some(s):
      if s.chars.size > 160
        "#{Text.from_chars(s.chars.take(160))}... (#{raw.size}B)"
      else
        s
      end
    None:
      hex = raw.to_hex
      if hex.chars.size > 64
        "0x#{Text.from_chars(hex.chars.take(64))}... (#{raw.size}B)"
      else
        "0x#{hex}"
      end
  end
end

fn fail_msg(console: Console, msg: Text) : Int
  console.error("error: #{msg}")
  1
end

fn build_repacked_store(
  files: Files,
  dst_path: Text,
  snap: PortableSnapshot
) : Result((Store, Int), Text)
  decoded0 = try Export.decode_snapshot_buckets(snap).map_error(fn(e) Export.to_text(e) end)
  has_meta? = decoded0.any?(fn(p) p.0 == meta_bucket end)
  decoded = if not snap.include_internal and snap.schema_version > 0 and not has_meta?
    st = SchemaState(version: snap.schema_version, next_audit_seq: 1, last_audit_hash: genesis_hash)
    decoded0.append((meta_bucket, [(Table.encode_text_key("state"), Json.encode(st).bytes)]))
  else
    decoded0
  end
  fh = try wrap_io(files.open(dst_path)).map_error(fn(e) e.to_text end)
  store = try Modb.build_from_buckets(from_file(fh), snap.source_txid, decoded).map_error(fn(e)
    e.to_text
  end)
  _vrep = try Modb.verify(store).map_error(fn(e) e.to_text end)
  _arep = try Ledger.verify_audit_store(store).map_error(fn(e) Ledger.to_text(e) end)
  var entry_cnt = 0
  for b in decoded
    entry_cnt += b.1.size
  end
  Ok((store, entry_cnt))
end

fn cmd_inspect(console: Console, files: Files, clock: Clock, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(console, "usage: modb inspect <db.modb> [--json]")
  end
  now = clock.now
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      st_opt = try Ledger.meta_state_store(store).map_error(fn(e) Ledger.to_text(e) end)
      pins = try Modb.list_pins(store).map_error(fn(e) e.to_text end)
      bnames = try Modb.buckets(store).map_error(fn(e) e.to_text end)
      var b_counts = []
      var total_entries = 0
      for b in bnames
        c = try Modb.count_bucket(store, b).map_error(fn(e) e.to_text end)
        b_counts = b_counts.append((b, c))
        total_entries += c
      end
      grants = try Grants.list_all(store).map_error(fn(e) Grants.to_text(e) end)
      claims = try Claims.list_active(store, now).map_error(fn(e) Claims.to_text(e) end)
      worlds = try World.list_worlds(store).map_error(fn(e) World.to_text(e) end)
      w_open = worlds.filter(fn(w) w.status is World.Open end).size
      w_metrics = try World.metrics(store).map_error(fn(e) World.to_text(e) end)
      w_telem = try World.telemetry(store).map_error(fn(e) World.to_text(e) end)
      clearances = try Policy.list_clearances(store).map_error(fn(e) Policy.to_text(e) end)
      gov_props = try Proposals.list_proposals(store, None).map_error(fn(e)
        Proposals.to_text(e)
      end)
      feeds = try Feeds.list_feeds(store).map_error(fn(e) Feeds.to_text(e) end)
      taint_sessions = try Taint.list_sessions(store).map_error(fn(e) Taint.to_text(e) end)
      erasure_receipts = try Erasure.list_erasure_receipts(store).map_error(fn(e)
        Erasure.to_text(e)
      end)
      schema_ver = case st_opt
        Some(s): s.version
        None: 0
      end
      audit_cnt = case st_opt
        Some(s): s.next_audit_seq - 1
        None: 0
      end
      tail_hash = case st_opt
        Some(s): s.last_audit_hash
        None: genesis_hash
      end
      Ok((
        Modb.txid(store),
        Modb.page_count(store),
        Modb.free_page_count(store),
        schema_ver,
        audit_cnt,
        tail_hash,
        pins.size,
        grants.size,
        claims.size,
        worlds.size,
        w_open,
        w_metrics,
        w_telem,
        clearances.size,
        gov_props.size,
        feeds.size,
        taint_sessions.size,
        erasure_receipts.size,
        b_counts,
        total_entries
      ))
    end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok((
      txid_v,
      pages,
      free_pages,
      schema_ver,
      audit_cnt,
      tail_hash,
      pin_cnt,
      grant_cnt,
      claim_cnt,
      world_cnt,
      w_open,
      wm,
      wt,
      clr_cnt,
      prop_cnt,
      feed_cnt,
      taint_cnt,
      erasure_cnt,
      b_counts,
      total_entries
    )):
      if f.json?
        buckets_json = Json.Array(
          b_counts.map(fn(p)
            Json.Object({"bucket": Json.String(p.0), "entries": Json.int(p.1)})
          end)
        )
        out = Json.Object({
          "path": Json.String(path),
          "txid": Json.int(txid_v),
          "schema_version": Json.int(schema_ver),
          "page_count": Json.int(pages),
          "free_page_count": Json.int(free_pages),
          "audit_entries": Json.int(audit_cnt),
          "tail_hash": Json.String(tail_hash),
          "pins": Json.int(pin_cnt),
          "grants": Json.int(grant_cnt),
          "active_claims": Json.int(claim_cnt),
          "worlds_total": Json.int(world_cnt),
          "worlds_open": Json.int(w_open),
          "world_metrics": wm.to_json,
          "world_telemetry": wt.to_json,
          "clearances": Json.int(clr_cnt),
          "gov_proposals": Json.int(prop_cnt),
          "feeds": Json.int(feed_cnt),
          "taint_sessions": Json.int(taint_cnt),
          "erasure_receipts": Json.int(erasure_cnt),
          "total_entries": Json.int(total_entries),
          "buckets": buckets_json
        })
        console.print(Json.encode(out))
      else
        console.print(
          "db=#{path} txid=#{txid_v} schema=v#{schema_ver} pages=#{pages} free=#{free_pages} entries=#{total_entries} audit=#{audit_cnt} tail=#{tail_hash}"
        )
        console.print(
          "pins=#{pin_cnt} grants=#{grant_cnt} claims=#{claim_cnt} worlds=#{world_cnt} (open=#{w_open}) landed=#{wm
            .total_landed} key_skips=#{wt.key_level_reads_skipped} child_landed=#{wt
            .child_worlds_landed} clearances=#{clr_cnt} proposals=#{prop_cnt} feeds=#{feed_cnt} taint_sessions=#{taint_cnt} erasures=#{erasure_cnt}"
        )
        for (b, c) in b_counts
          console.print("  bucket #{b}: #{c} entries")
        end
      end
      0
  end
end

fn cmd_verify(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(console, "usage: modb verify <db.modb> [--fast [N]] [--json]")
  end
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      srep = if f.fast?
        try Modb.verify_light(store).map_error(fn(e) e.to_text end)
      else
        try Modb.verify(store).map_error(fn(e) e.to_text end)
      end
      arep = if f.fast?
        try Ledger.verify_audit_window_store(store, f.fast_window).map_error(fn(e)
          Ledger.to_text(e)
        end)
      else
        try Ledger.verify_audit_store(store).map_error(fn(e) Ledger.to_text(e) end)
      end
      Ok((srep, arep, Modb.free_page_count(store)))
    end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok((srep, arep, free_cnt)):
      mode = if f.fast?: "fast(#{f.fast_window})" else: "full"
      if f.json?
        out = Json.Object({
          "ok?": Json.Boolean(true),
          "mode": Json.String(mode),
          "txid": Json.int(srep.txid),
          "schema_version": Json.int(arep.schema_version),
          "page_count": Json.int(srep.page_count),
          "free_page_count": Json.int(free_cnt),
          "bucket_count": Json.int(srep.bucket_count),
          "audit_entries": Json.int(arep.entry_count),
          "last_seq": Json.int(arep.last_seq),
          "tail_hash": Json.String(arep.last_hash)
        })
        console.print(Json.encode(out))
      else
        console.print(
          "MoDB verify ok=true mode=#{mode} txid=#{srep.txid} schema=v#{arep.schema_version} pages=#{srep
            .page_count} free=#{free_cnt} buckets=#{srep.bucket_count} audit=#{arep
            .entry_count} tail=#{arep.last_hash}"
        )
      end
      0
  end
end

fn cmd_dump(console: Console, files: Files, f: ParsedFlags) : Int
  if f.positional.size < 2
    return fail_msg(console, "usage: modb dump <db.modb> <bucket> [--limit N] [--json]")
  end
  path = (f.positional.get(0) or "").trim
  bucket = (f.positional.get(1) or "").trim
  lim = f.limit_opt or 50
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store) Modb.scan(store, bucket, None, None, lim).map_error(fn(e) e.to_text end) end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok(rows):
      if f.json?
        arr = Json.Array(
          rows.map(fn(p)
            kt = case decode_printable_text(p.0)
              Some(s): Json.String(s)
              None: Json.Null
            end
            vt = case decode_printable_text(p.1)
              Some(s): Json.String(s)
              None: Json.Null
            end
            Json.Object({
              "key_hex": Json.String(p.0.to_hex),
              "key_text": kt,
              "value_hex": Json.String(p.1.to_hex),
              "value_text": vt
            })
          end)
        )
        console.print(Json.encode(arr))
      else
        console.print("bucket=#{bucket} rows=#{rows.size}")
        for (k, v) in rows
          console.print("  #{format_bytes_preview(k)} => #{format_bytes_preview(v)}")
        end
      end
      0
  end
end

fn cmd_audit(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(
      console,
      "usage: modb audit <db.modb> [--limit N] [--principal P] [--action A] [--json]"
    )
  end
  lim = f.limit_opt or 20
  filtered? = f.principal_opt is Some(_) or f.action_opt is Some(_)
  fetch_lim = if filtered?: 0 else: lim
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      entries = try Ledger.audit_tail_store(store, fetch_lim).map_error(fn(e) Ledger.to_text(e) end)
      matching = entries.filter(fn(e)
        ok_p = case f.principal_opt
          Some(p): e.principal == p
          None: true
        end
        ok_a = case f.action_opt
          Some(a): e.action == a
          None: true
        end
        ok_p and ok_a
      end)
      if lim > 0 and matching.size > lim
        Ok(matching.drop(matching.size - lim))
      else
        Ok(matching)
      end
    end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok(entries):
      if f.json?
        console.print(Json.encode(entries))
      else
        console.print("audit_entries=#{entries.size}")
        for e in entries
          console.print(
            "  ##{e.seq} tx=#{e.txid} #{e.principal} #{e.action} reason=\"#{e.reason}\" hash=#{e
              .entry_hash}"
          )
        end
      end
      0
  end
end

fn world_status_text(st: World.WorldStatus) : Text
  case st
    World.Open: "open"
    World.Landed(commit_txid: tx): if tx == 0: "merged_into_parent" else: "landed(tx=#{tx})"
    World.Rejected(reason: r): "rejected(#{r})"
    World.Dropped: "dropped"
  end
end

fn cmd_worlds(console: Console, files: Files, clock: Clock, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(console, "usage: modb worlds <db.modb> [--json]")
  end
  now = clock.now
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      wm = try World.metrics(store).map_error(fn(e) World.to_text(e) end)
      wt = try World.telemetry(store).map_error(fn(e) World.to_text(e) end)
      ws = try World.list_worlds(store).map_error(fn(e) World.to_text(e) end)
      tks = try World.list_priority_tickets(store, now).map_error(fn(e) World.to_text(e) end)
      var links = {}
      for w in ws
        if (try World.get_world_link(store, w.id).map_error(fn(e) World.to_text(e) end)) is Some(
          lnk
        )
          links = links.set(w.id, lnk)
        end
      end
      Ok((wm, wt, ws, tks, links))
    end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok((wm, wt, ws, tks, links)):
      if f.json?
        out = Json.Object({
          "metrics": wm.to_json,
          "telemetry": wt.to_json,
          "priority_tickets": tks.to_json,
          "worlds": ws.to_json
        })
        console.print(Json.encode(out))
      else
        console.print(
          "LandingMetrics landed=#{wm.total_landed} reads_verified=#{wm.total_reads_verified} reads_skipped=#{wm
            .total_reads_skipped} stale=#{wm.stale_read_rejections} invariant=#{wm
            .invariant_rejections} needless_send_backs=#{wm.needless_send_backs}"
        )
        console.print(
          "WorldTelemetry key_skipped=#{wt.key_level_reads_skipped} bucket_skipped=#{wt
            .bucket_level_reads_skipped} child_landed=#{wt.child_worlds_landed} tickets=#{wt
            .fairness_tickets_issued} deferrals=#{wt.fairness_deferrals} rescued=#{wt
            .starved_worlds_rescued} active_tickets=#{tks.size}"
        )
        for w in ws
          child_note = case links.get(w.id)
            Some(lnk): " [child of #{lnk.parent_world_id}, watermark=#{lnk.parent_step_watermark}]"
            None: ""
          end
          console.print(
            "  #{w.id} status=#{world_status_text(w.status)} principal=#{w.principal} grant=#{w
              .grant_id} base_tx=#{w.base_txid} steps=#{w.steps.size}#{child_note}"
          )
        end
      end
      0
  end
end

fn cmd_backup(console: Console, files: Files, clock: Clock, f: ParsedFlags) : Int
  if f.positional.size < 2
    return fail_msg(console, "usage: modb backup <src.modb> <dst.modb> [--include-internal]")
  end
  src_path = (f.positional.get(0) or "").trim
  dst_path = (f.positional.get(1) or "").trim
  if files.exists?(dst_path)
    return fail_msg(console, "destination already exists: #{dst_path}")
  end
  now = clock.now
  snap = case Modb.with_shared_lock(
    files.read_only,
    src_path,
    fn(e) e.to_text end,
    fn(store)
      Export.export_store(store, f.include_internal?, now).map_error(fn(e)
        Export.to_text(e)
      end)
    end
  )
    Ok(s): s
    Error(msg): return fail_msg(console, msg)
  end
  tmp_path = "#{dst_path}.backup.tmp"
  _rm0 = files.remove(tmp_path)
  (st_bak, entries) = case build_repacked_store(files, tmp_path, snap)
    Ok(p): p
    Error(msg):
      _rm1 = files.remove(tmp_path)
      return fail_msg(console, msg)
  end
  pages = Modb.page_count(st_bak)
  free_pages = Modb.free_page_count(st_bak)
  case files.rename(tmp_path, dst_path)
    Ok(Unit):
      console.print(
        "MoDB backup ok src=#{src_path} dst=#{dst_path} txid=#{snap.source_txid} schema=v#{snap
          .schema_version} entries=#{entries} pages=#{pages} free=#{free_pages} sha256=#{snap.sha256}"
      )
      0
    Error(fe):
      _rm2 = files.remove(tmp_path)
      fail_msg(console, fe.to_text)
  end
end

fn cmd_export(console: Console, files: Files, clock: Clock, f: ParsedFlags) : Int
  if f.positional.size < 2
    return fail_msg(console, "usage: modb export <src.modb> <out.json> [--include-internal]")
  end
  src_path = (f.positional.get(0) or "").trim
  out_path = (f.positional.get(1) or "").trim
  if files.exists?(out_path)
    return fail_msg(console, "output file already exists: #{out_path}")
  end
  now = clock.now
  snap = case Modb.with_shared_lock(
    files.read_only,
    src_path,
    fn(e) e.to_text end,
    fn(store)
      Export.export_store(store, f.include_internal?, now).map_error(fn(e)
        Export.to_text(e)
      end)
    end
  )
    Ok(s): s
    Error(msg): return fail_msg(console, msg)
  end
  raw = Export.encode_snapshot_json(snap)
  case files.write_text(out_path, raw)
    Ok(Unit):
      console.print(
        "MoDB export ok src=#{src_path} out=#{out_path} txid=#{snap.source_txid} buckets=#{snap
          .bucket_count} entries=#{snap.entry_count} sha256=#{snap.sha256}"
      )
      0
    Error(fe): fail_msg(console, fe.to_text)
  end
end

fn cmd_restore(console: Console, files: Files, f: ParsedFlags) : Int
  if f.positional.size < 2
    return fail_msg(console, "usage: modb restore <in.json> <dst.modb>")
  end
  in_path = (f.positional.get(0) or "").trim
  dst_path = (f.positional.get(1) or "").trim
  if files.exists?(dst_path)
    return fail_msg(console, "destination already exists: #{dst_path}")
  end
  raw = case files.read_only.read_text(in_path)
    Ok(s): s
    Error(fe): return fail_msg(console, fe.to_text)
  end
  snap = case Json.decode[PortableSnapshot](raw)
    Ok(s): s
    Error(je): return fail_msg(console, "invalid snapshot JSON: #{je}")
  end
  tmp_path = "#{dst_path}.restore.tmp"
  _rm0 = files.remove(tmp_path)
  (st_restored, entries) = case build_repacked_store(files, tmp_path, snap)
    Ok(p): p
    Error(msg):
      _rm1 = files.remove(tmp_path)
      return fail_msg(console, msg)
  end
  pages = Modb.page_count(st_restored)
  case files.rename(tmp_path, dst_path)
    Ok(Unit):
      console.print(
        "MoDB restore ok src=#{in_path} dst=#{dst_path} txid=#{snap.source_txid} schema=v#{snap
          .schema_version} entries=#{entries} pages=#{pages} sha256=#{snap.sha256}"
      )
      0
    Error(fe):
      _rm2 = files.remove(tmp_path)
      fail_msg(console, fe.to_text)
  end
end

fn cmd_compact(console: Console, files: Files, clock: Clock, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(console, "usage: modb compact <db.modb> [--include-internal]")
  end
  if not files.read_only.exists?(path)
    return fail_msg(console, "database file does not exist: #{path}")
  end
  now = clock.now
  lock_res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      before_pages = Modb.page_count(store)
      before_free = Modb.free_page_count(store)
      snap = try Export.export_store(store, f.include_internal?, now).map_error(fn(e)
        Export.to_text(e)
      end)
      Ok((before_pages, before_free, snap))
    end
  )
  case lock_res
    Error(msg): fail_msg(console, msg)
    Ok((before_pages, before_free, snap)):
      tmp_path = "#{path}.compact.tmp"
      _rm0 = files.remove(tmp_path)
      (st_new, entries) = case build_repacked_store(files, tmp_path, snap)
        Ok(p): p
        Error(msg):
          _rm1 = files.remove(tmp_path)
          return fail_msg(console, msg)
      end
      after_pages = Modb.page_count(st_new)
      after_free = Modb.free_page_count(st_new)
      case files.rename(tmp_path, path)
        Ok(Unit):
          console.print(
            "MoDB compact ok path=#{path} pages=#{before_pages}->#{after_pages} free=#{before_free}->#{after_free} entries=#{entries} sha256=#{snap
              .sha256}"
          )
          0
        Error(fe):
          _rm2 = files.remove(tmp_path)
          fail_msg(console, fe.to_text)
      end
  end
end

struct BucketDiffCount
  bucket: Text
  added: Int
  removed: Int
  modified: Int
end

fn count_key_diffs(bucket: Text, kdiffs: List(KeyDiff)) : BucketDiffCount
  var a = 0
  var r = 0
  var m = 0
  for kd in kdiffs
    case kd
      Added(key: _, value: _): a += 1
      Removed(key: _, value: _): r += 1
      Modified(key: _, old_value: _, new_value: _): m += 1
    end
  end
  BucketDiffCount(bucket: bucket, added: a, removed: r, modified: m)
end

fn diff_sorted_kv(a_rows: List((Bytes, Bytes)), b_rows: List((Bytes, Bytes))) : (Int, Int, Int)
  var i = 0
  var j = 0
  var added = 0
  var removed = 0
  var modified = 0
  while i < a_rows.size and j < b_rows.size
    (ka, va) = a_rows.get(i) or stop "diff a row"
    (kb, vb) = b_rows.get(j) or stop "diff b row"
    if ka == kb
      if va != vb
        modified += 1
      end
      i += 1
      j += 1
    else if ka < kb
      removed += 1
      i += 1
    else
      added += 1
      j += 1
    end
  end
  removed += a_rows.size - i
  added += b_rows.size - j
  (added, removed, modified)
end

fn cmd_diff_pin(
  console: Console,
  files: Files,
  f: ParsedFlags,
  path: Text,
  pin_id: Text
) : Int
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      pin = try (try Modb.get_pin(store, pin_id).map_error(fn(e) e.to_text end)).or_fail(
        "unknown pin '#{pin_id}'"
      )
      (diffs, stats) = try Modb.diff_roots_with_stats(
        store,
        pin.catalog_root,
        Modb.catalog_root(store)
      ).map_error(fn(e) e.to_text end)
      var items = []
      for bd in diffs
        if f.include_internal? or not bd.bucket.starts_with?("_modb_")
          items = items.append(count_key_diffs(bd.bucket, bd.changes))
        end
      end
      Ok((pin.txid, Modb.txid(store), items, stats))
    end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok((pin_tx, live_tx, items, stats)):
      if f.json?
        out = Json.Object({
          "mode": Json.String("pin"),
          "pin_id": Json.String(pin_id),
          "pin_txid": Json.int(pin_tx),
          "live_txid": Json.int(live_tx),
          "pages_read": Json.int(stats.pages_read),
          "subtrees_skipped": Json.int(stats.subtrees_skipped),
          "diffs": items.to_json
        })
        console.print(Json.encode(out))
      else
        console.print(
          "diff pin=#{pin_id} (tx #{pin_tx} -> #{live_tx}) buckets_changed=#{items.size} pages_read=#{stats
            .pages_read} subtrees_skipped=#{stats.subtrees_skipped}"
        )
        for d in items
          console.print("  #{d.bucket}: +#{d.added} / ~#{d.modified} / -#{d.removed}")
        end
      end
      0
  end
end

fn load_bucket_map_ro(
  files: Files,
  path: Text,
  include_internal?: Bool
) : Result((Int, Map(Text, List((Bytes, Bytes)))), Text)
  Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      names = try Modb.buckets(store).map_error(fn(e) e.to_text end)
      var m = {}
      for b in names
        if include_internal? or not b.starts_with?("_modb_")
          rows = try Modb.scan(store, b, None, None, 0).map_error(fn(e) e.to_text end)
          m = m.set(b, rows)
        end
      end
      Ok((Modb.txid(store), m))
    end
  )
end

fn cmd_diff(console: Console, files: Files, f: ParsedFlags) : Int
  case f.pin_opt
    Some(pin_id):
      path = case f.positional.first
        Some(p) if not p.trim.empty?: p.trim
        Some(_) | None: return fail_msg(
          console,
          "usage: modb diff <db.modb> --pin <pin_id> [--include-internal] [--json]"
        )
      end
      return cmd_diff_pin(console, files, f, path, pin_id)
    None: Unit
  end
  if f.positional.size < 2
    return fail_msg(
      console,
      "usage: modb diff <a.modb> <b.modb> [--include-internal] [--json]"
    )
  end
  path_a = (f.positional.get(0) or "").trim
  path_b = (f.positional.get(1) or "").trim
  (tx_a, map_a) = case load_bucket_map_ro(files, path_a, f.include_internal?)
    Ok(p): p
    Error(msg): return fail_msg(console, msg)
  end
  (tx_b, map_b) = case load_bucket_map_ro(files, path_b, f.include_internal?)
    Ok(p): p
    Error(msg): return fail_msg(console, msg)
  end
  var seen = Set.empty
  var items = []
  for b in map_a.keys
    seen = seen.add(b)
    ra = map_a.get(b) or []
    rb = map_b.get(b) or []
    (ad, rm, md) = diff_sorted_kv(ra, rb)
    if ad + rm + md > 0
      items = items.append(BucketDiffCount(bucket: b, added: ad, removed: rm, modified: md))
    end
  end
  for b in map_b.keys
    if not seen.has?(b)
      rb = map_b.get(b) or []
      if not rb.empty?
        items = items.append(
          BucketDiffCount(bucket: b, added: rb.size, removed: 0, modified: 0)
        )
      end
    end
  end
  if f.json?
    out = Json.Object({
      "mode": Json.String("files"),
      "a": Json.String(path_a),
      "b": Json.String(path_b),
      "txid_a": Json.int(tx_a),
      "txid_b": Json.int(tx_b),
      "diffs": items.to_json
    })
    console.print(Json.encode(out))
  else
    console.print("diff #{path_a} (tx #{tx_a}) -> #{path_b} (tx #{tx_b}) buckets=#{items.size}")
    for d in items
      console.print("  #{d.bucket}: +#{d.added} / ~#{d.modified} / -#{d.removed}")
    end
  end
  0
end

struct NamedFtsStats
  prefix: Text
  stats: Fts.FtsStats
end

struct NamedVecStats
  prefix: Text
  stats: Vec.VecStats
end

fn trim_bucket_suffix(name: Text, suffix: Text) : Text
  cs = name.chars
  sc = suffix.chars
  if cs.size >= sc.size: Text.from_chars(cs.take(cs.size - sc.size)) else: name
end

fn cmd_fts(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(
      console,
      "usage: modb fts <db.modb> [prefix] [query...] [--scope S] [--prefix] [--limit N] [--json]"
    )
  end
  if f.positional.size <= 2
    pfx_filter = f.positional.get(1).map(fn(s) s.trim end)
    res = Modb.with_shared_lock(
      files.read_only,
      path,
      fn(e) e.to_text end,
      fn(store)
        bnames = try Modb.buckets(store).map_error(fn(e) e.to_text end)
        var out = []
        for b in bnames
          if b.ends_with?("_fts_meta")
            pfx = trim_bucket_suffix(b, "_fts_meta")
            matches? = case pfx_filter
              Some(req): pfx == req
              None: true
            end
            if matches?
              st = try Fts.stats(store, Fts.index(pfx)).map_error(fn(e) Fts.to_text(e) end)
              out = out.append(NamedFtsStats(prefix: pfx, stats: st))
            end
          end
        end
        case pfx_filter
          Some(req) if out.empty?:
            st = try Fts.stats(store, Fts.index(req)).map_error(fn(e) Fts.to_text(e) end)
            if st.doc_count > 0
              out = out.append(NamedFtsStats(prefix: req, stats: st))
            end
          Some(_) | None: Unit
        end
        Ok(out)
      end
    )
    return case res
      Error(msg): fail_msg(console, msg)
      Ok(items):
        if f.json?
          console.print(Json.encode(items.to_json))
        else if items.empty?
          console.print("fts indexes=0")
        else
          console.print("fts indexes=#{items.size}")
          for it in items
            console.print(
              "  prefix=#{it.prefix} docs=#{it.stats.doc_count} tokens=#{it.stats.total_tokens} weighted_len=#{it
                .stats.total_weighted_len}"
            )
          end
        end
        0
    end
  end

  pfx = (f.positional.get(1) or "").trim
  query = f.positional.drop(2).join(" ")
  cap = f.limit_opt or 10
  opts = Fts.SearchOptions(limit: cap, prefix_last_term?: f.prefix?, required_scope: f.scope_opt)
  qres = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      Fts.search(store, Fts.index(pfx), query, opts).map_error(fn(e) Fts.to_text(e) end)
    end
  )
  case qres
    Error(msg): fail_msg(console, msg)
    Ok(hits):
      if f.json?
        console.print(
          Json.encode(
            Json.Object({
              "prefix": Json.String(pfx),
              "query": Json.String(query),
              "hits": hits.to_json
            })
          )
        )
      else
        console.print("fts prefix=#{pfx} query=\"#{query}\" hits=#{hits.size}")
        for (i, h) in hits.enumerate
          console.print(
            "  [#{i + 1}] #{h.doc_id} (scope=#{h.scope}) score=#{h.score} terms=#{h.matched_terms.join(
              ","
            )} fields=#{h.matched_fields.join(",")}"
          )
        end
      end
      0
  end
end

fn cmd_vec(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(console, "usage: modb vec <db.modb> [prefix] [--json]")
  end
  pfx_filter = f.positional.get(1).map(fn(s) s.trim end)
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      bnames = try Modb.buckets(store).map_error(fn(e) e.to_text end)
      var out = []
      for b in bnames
        if b.ends_with?("_vec_meta")
          pfx = trim_bucket_suffix(b, "_vec_meta")
          matches? = case pfx_filter
            Some(req): pfx == req
            None: true
          end
          if matches?
            tbl = Table.text_key[Vec.VecStats](b)
            case try Table.get(store, tbl, "stats").map_error(fn(e) e.to_text end)
              Some(st): out = out.append(NamedVecStats(prefix: pfx, stats: st))
              None: Unit
            end
          end
        end
      end
      Ok(out)
    end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok(items):
      if f.json?
        console.print(Json.encode(items.to_json))
      else if items.empty?
        console.print("vec indexes=0")
      else
        console.print("vec indexes=#{items.size}")
        for it in items
          console.print(
            "  prefix=#{it.prefix} docs=#{it.stats.doc_count} dims=#{it.stats.dimensions} metric=#{it
              .stats.metric} encoding=#{it.stats.encoding} bytes=#{it.stats.total_bytes}"
          )
        end
      end
      0
  end
end

fn cmd_policy(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(console, "usage: modb policy <db.modb> [--json]")
  end
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store)
      clearances = try Policy.list_clearances(store).map_error(fn(e) Policy.to_text(e) end)
      dviews = try Proposals.list_dynamic_views(store).map_error(fn(e) Proposals.to_text(e) end)
      drels = try Proposals.list_dynamic_releases(store).map_error(fn(e) Proposals.to_text(e) end)
      dinvs = try Proposals.list_dynamic_invariants(store).map_error(fn(e) Proposals.to_text(e) end)
      Ok((clearances, dviews, drels, dinvs))
    end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok((clearances, dviews, drels, dinvs)):
      if f.json?
        out = Json.Object({
          "clearances": clearances.to_json,
          "dynamic_views": dviews.to_json,
          "dynamic_releases": drels.to_json,
          "dynamic_invariants": dinvs.to_json
        })
        console.print(Json.encode(out))
      else
        console.print(
          "clearances=#{clearances.size} dynamic_views=#{dviews.size} dynamic_releases=#{drels
            .size} dynamic_invariants=#{dinvs.size}"
        )
        for c in clearances
          console.print(
            "  grant=#{c.grant_id} clearance=#{Policy.sensitivity_to_text(c.max_sensitivity)} by=#{c
              .granted_by} reason=#{c.reason}"
          )
        end
        for dv in dviews
          console.print("  dynamic_view=#{dv.name} narrows=#{dv.base_view} fields=#{dv.fields.join(",")}")
        end
        for dr in drels
          console.print(
            "  dynamic_release=#{dr.release_name} #{Policy.sensitivity_to_text(dr.input_sensitivity)}->#{Policy
              .sensitivity_to_text(dr.output_sensitivity)} k>=#{dr.min_group_size}"
          )
        end
        for di in dinvs
          console.print("  dynamic_invariant=#{di.name} bucket=#{di.bucket}")
        end
      end
      0
  end
end

fn parse_proposal_status_flag(s_opt: Option(Text)) : Result(Option(Proposals.ProposalStatus), Text)
  case s_opt
    None: Ok(None)
    Some(raw):
      norm = Text.from_chars(raw.trim.chars.map(fn(c) c.ascii_lowercase end))
      if norm == "pending"
        Ok(Some(Proposals.Pending))
      else if norm == "approved"
        Ok(Some(Proposals.Approved))
      else if norm == "rejected"
        Ok(Some(Proposals.Rejected))
      else if norm == "withdrawn"
        Ok(Some(Proposals.Withdrawn))
      else
        Error("unknown proposal status '#{raw}' (expected pending|approved|rejected|withdrawn)")
      end
  end
end

fn cmd_proposals(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(
      console,
      "usage: modb proposals <db.modb> [--status pending|approved|rejected|withdrawn] [--json]"
    )
  end
  st_opt = case parse_proposal_status_flag(f.status_opt)
    Ok(s): s
    Error(msg): return fail_msg(console, msg)
  end
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store) Proposals.list_proposals(store, st_opt).map_error(fn(e) Proposals.to_text(e) end) end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok(props):
      if f.json?
        console.print(Json.encode(props.to_json))
      else
        console.print("governance_proposals=#{props.size}")
        for p in props
          st_txt = case p.status
            Proposals.Pending: "pending"
            Proposals.Approved: "approved"
            Proposals.Rejected: "rejected"
            Proposals.Withdrawn: "withdrawn"
          end
          console.print(
            "  #{p.id} status=#{st_txt} risk=#{p.diff.risk_level} widens=#{p.diff.widens_access} by=#{p
              .proposer} | #{p.diff.summary}"
          )
        end
      end
      0
  end
end

fn cmd_feeds(console: Console, files: Files, clock: Clock, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(
      console,
      "usage: modb feeds <db.modb> [--json] | modb feeds <db.modb> poll <feed_id> [--limit N] [--json]"
    )
  end
  if f.positional.size >= 2
    sub = (f.positional.get(1) or "").trim
    if sub != "poll" or f.positional.size < 3
      return fail_msg(
        console,
        "usage: modb feeds <db.modb> poll <feed_id> [--limit N] [--json]"
      )
    end
    feed_id = (f.positional.get(2) or "").trim
    lim = f.limit_opt or 100
    now = clock.now
    qres = Modb.with_shared_lock(
      files.read_only,
      path,
      fn(e) e.to_text end,
      fn(store)
        Feeds.poll_feed(store, Policy.policy(), feed_id, true, lim, now).map_error(fn(e)
          Feeds.to_text(e)
        end)
      end
    )
    return case qres
      Error(msg): fail_msg(console, msg)
      Ok(batch):
        if f.json?
          console.print(Json.encode(batch.to_json))
        else
          console.print(
            "feed=#{batch.feed_id} from_tx=#{batch.from_txid} to_tx=#{batch.to_txid} events=#{batch
              .events.size} truncated=#{batch.truncated} pages_read=#{batch.pages_read} subtrees_skipped=#{batch
              .subtrees_skipped}"
          )
          for ev in batch.events
            kshow = ev.key_text or ev.key_hex
            op_txt = case ev.op
              Feeds.OpAdded: "added"
              Feeds.OpModified: "modified"
              Feeds.OpRemoved: "removed"
            end
            console.print("  [#{op_txt}] #{ev.bucket}:#{kshow}")
          end
        end
        0
    end
  end

  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store) Feeds.list_feeds(store).map_error(fn(e) Feeds.to_text(e) end) end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok(subs):
      if f.json?
        console.print(Json.encode(subs.to_json))
      else
        console.print("feeds=#{subs.size}")
        for s in subs
          bs = if s.buckets.empty?: "*" else: s.buckets.join(",")
          console.print(
            "  #{s.id} principal=#{s.principal} cursor_tx=#{s.cursor_txid} delivered=#{s
              .events_delivered} buckets=[#{bs}] pin=#{s.pin_id}"
          )
        end
      end
      0
  end
end

fn cmd_taint(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(console, "usage: modb taint <db.modb> [--json]")
  end
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store) Taint.list_sessions(store).map_error(fn(e) Taint.to_text(e) end) end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok(sessions):
      if f.json?
        console.print(Json.encode(sessions.to_json))
      else
        console.print("taint_sessions=#{sessions.size}")
        for s in sessions
          srcs = if s.untrusted_sources.empty?: "-" else: s.untrusted_sources.join(",")
          console.print(
            "  #{s.id} principal=#{s.principal} tainted=#{s.untrusted_tainted} max_read=#{Policy
              .sensitivity_to_text(s.max_sensitivity_read)} blocked=#{s.blocked_attempts} sources=[#{srcs}]"
          )
        end
      end
      0
  end
end

fn cmd_matviews(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(
      console,
      "usage: modb matviews <db.modb> [list|refresh <name>|rebuild <name>|query <name>] [--min-k N] [--json]"
    )
  end
  sub = (f.positional.get(1) or "list").trim
  if sub == "list"
    res = Modb.with_shared_lock(
      files.read_only,
      path,
      fn(e) e.to_text end,
      fn(store) Matview.list_matviews(store).map_error(fn(e) Matview.to_text(e) end) end
    )
    return case res
      Error(msg): fail_msg(console, msg)
      Ok(mvs):
        if f.json?
          console.print(Json.encode(mvs.to_json))
        else
          console.print("matviews=#{mvs.size}")
          for mv in mvs
            console.print(
              "  #{mv.def.name} src=#{mv.def.source_bucket} group_by=#{mv.def.group_by} groups=#{mv
                .group_count} rows=#{mv.source_rows_seen} tx=#{mv.last_txid} rebuilds=#{mv.rebuilds} inc=#{mv
                .incremental_refreshes}"
            )
          end
        end
        0
    end
  else if sub == "refresh" or sub == "rebuild"
    mv_name = (f.positional.get(2) or "").trim
    if mv_name.empty?
      return fail_msg(console, "usage: modb matviews <db.modb> #{sub} <name> [--json]")
    end
    res = Modb.with_exclusive_lock(
      files,
      path,
      fn(e) e.to_text end,
      fn(store)
        r = if sub == "refresh"
          Matview.refresh_matview(store, mv_name)
        else
          Matview.rebuild_matview(store, mv_name)
        end
        case r
          Ok((_next, rep)): Ok(rep)
          Error(e): Error(Matview.to_text(e))
        end
      end
    )
    return case res
      Error(msg): fail_msg(console, msg)
      Ok(rep):
        if f.json?
          console.print(Json.encode(rep.to_json))
        else
          console.print(
            "matview=#{rep.name} strategy=#{rep.strategy} diffs=#{rep.diffs_applied} touched=#{rep
              .groups_touched} recomputes=#{rep.group_recomputes} groups=#{rep.group_count} tx=#{rep
              .last_txid}"
          )
        end
        0
    end
  else if sub == "query"
    mv_name = (f.positional.get(2) or "").trim
    if mv_name.empty?
      return fail_msg(console, "usage: modb matviews <db.modb> query <name> [--min-k N] [--json]")
    end
    res = Modb.with_shared_lock(
      files.read_only,
      path,
      fn(e) e.to_text end,
      fn(store)
        Matview.query_matview(store, mv_name, f.min_k_opt).map_error(fn(e) Matview.to_text(e) end)
      end
    )
    return case res
      Error(msg): fail_msg(console, msg)
      Ok(q):
        if f.json?
          console.print(Json.encode(q.to_json))
        else
          console.print(
            "matview=#{q.name} tx=#{q.last_txid} returned=#{q.returned_groups}/#{q.total_groups} suppressed=#{q
              .suppressed_groups}"
          )
          for row in q.rows
            console.print("  #{Json.encode(row)}")
          end
        end
        0
    end
  end
  fail_msg(
    console,
    "unknown matviews subcommand '#{sub}' (use list | refresh | rebuild | query)"
  )
end

fn cmd_erasures(console: Console, files: Files, f: ParsedFlags) : Int
  path = case f.positional.first
    Some(p) if not p.trim.empty?: p.trim
    Some(_) | None: return fail_msg(console, "usage: modb erasures <db.modb> [--json]")
  end
  res = Modb.with_shared_lock(
    files.read_only,
    path,
    fn(e) e.to_text end,
    fn(store) Erasure.list_erasure_receipts(store).map_error(fn(e) Erasure.to_text(e) end) end
  )
  case res
    Error(msg): fail_msg(console, msg)
    Ok(receipts):
      if f.json?
        console.print(Json.encode(receipts.to_json))
      else
        console.print("erasure_receipts=#{receipts.size}")
        for r in receipts
          console.print(
            "  #{r.id} subject_sha=#{Text.from_chars(r.subject_id_sha256.chars.take(12))} key_shredded=#{r
              .key_shredded?} rows=#{r.rows_deleted} audit_redacted=#{r.audit_entries_redacted} compacted=#{r
              .compacted?} by=#{r.erased_by}"
          )
        end
      end
      0
  end
end

fn decode_sync_key_bytes(raw: Bytes) : Result(Bytes, Text)
  case raw.decode_utf8
    Some(s):
      trimmed = s.trim
      if trimmed.byte_count == 64
        case Bytes.from_hex(trimmed)
          Some(kb) if kb.size == 32: return Ok(kb)
          Some(_) | None: Unit
        end
      end
      if trimmed.starts_with?("b64:")
        b64 = trimmed.drop_prefix("b64:") or ""
        case Bytes.from_base64url(b64)
          Some(kb) if kb.size == 32: return Ok(kb)
          Some(_) | None: Unit
        end
      end
    None: Unit
  end
  return Ok(raw) if raw.size == 32
  Error(
    "encryption key must be 32 raw bytes, 64 hex chars, or b64:<base64url> decoding to 32 bytes"
  )
end

fn load_sync_key(rf: ReadFiles, env_opt: Option(Env), f: ParsedFlags) : Result(Bytes, Text)
  case f.key_file_opt
    Some(kpath):
      raw = try rf.read_bytes(kpath).map_error(fn(e) e.to_text end)
      decode_sync_key_bytes(raw)
    None:
      env = try env_opt.or_fail("no Env capability available to read encryption key env var")
      env_var = case f.key_env_opt
        Some(v) if not v.trim.empty?: v.trim
        Some(_) | None: "MODB_BACKUP_KEY_HEX"
      end
      raw_txt = try env.get(env_var).or_fail(
        "encryption requested but neither --key-file nor #{env_var} is set"
      )
      decode_sync_key_bytes(raw_txt.bytes)
  end
end

fn has_key_flag?(f: ParsedFlags) : Bool
  f.key_file_opt is Some(_) or f.key_env_opt is Some(_) or f.keyring_file_opt is Some(_) or
    f.keyring_env_opt is Some(_)
end

fn resolve_sync_key_id(f: ParsedFlags, env_opt: Option(Env)) : Text
  case f.key_id_opt
    Some(id) if not id.trim.empty?: id.trim
    Some(_) | None:
      case env_opt
        Some(env):
          case env.get("MODB_BACKUP_KEY_ID")
            Some(id) if not id.trim.empty?: id.trim
            Some(_) | None: "default"
          end
        None: "default"
      end
  end
end

fn load_sync_keyring_opt(rf: ReadFiles, env_opt: Option(Env), f: ParsedFlags) : Result(
  Option(Map(Text, Bytes)),
  Text
)
  kr_opt = case f.keyring_file_opt
    Some(kpath):
      raw = try rf.read_text(kpath).map_error(fn(e) e.to_text end)
      kr = try Sync.parse_keyring_text(raw).map_error(fn(se) Sync.to_text(se) end)
      Some(kr)
    None:
      case f.keyring_env_opt
        Some(ev):
          env = try env_opt.or_fail("no Env capability available to read keyring env var")
          raw = try env.get(ev).or_fail("keyring env var '#{ev}' is not set")
          kr = try Sync.parse_keyring_text(raw).map_error(fn(se) Sync.to_text(se) end)
          Some(kr)
        None:
          if f.key_file_opt is Some(_) or f.key_env_opt is Some(_)
            None
          else
            case env_opt
              Some(env):
                case env.get("MODB_BACKUP_KEYRING")
                  Some(raw) if not raw.trim.empty?:
                    kr = try Sync.parse_keyring_text(raw).map_error(fn(se) Sync.to_text(se) end)
                    Some(kr)
                  Some(_) | None: None
                end
              None: None
            end
          end
      end
  end
  case (kr_opt, env_opt)
    (Some(kr), Some(env)):
      kid = resolve_sync_key_id(f, Some(env))
      if kr.get(kid) is None
        case env.get("MODB_BACKUP_KEY_HEX")
          Some(hex_raw) if not hex_raw.trim.empty?:
            case decode_sync_key_bytes(hex_raw.trim.bytes)
              Ok(kb): return Ok(Some(kr.set(kid, kb)))
              Error(_): Unit
            end
          Some(_) | None: Unit
        end
      end
      Ok(Some(kr))
    (Some(kr), None): Ok(Some(kr))
    (None, _): Ok(None)
  end
end

fn cmd_sync(
  console: Console,
  files: Files,
  clock: Clock,
  env_opt: Option(Env),
  srng_opt: Option(SecureRandom),
  f: ParsedFlags
) : Int
  p0 = (f.positional.get(0) or "").trim
  p1 = (f.positional.get(1) or "").trim
  if p0 == "restore" or p1 == "restore"
    dst_path = if p0 == "restore": p1 else: p0
    if dst_path.empty?
      return fail_msg(
        console,
        "usage: modb sync <dst.modb> restore --base <snap.json> [<delta1.json> ...] [--decrypt] [--key-file <p>|--key-env <V>] [--aad <t>]"
      )
    end
    base_path = case f.base_opt
      Some(b) if not b.trim.empty?: b.trim
      Some(_) | None: return fail_msg(console, "--base <snap.json> is required for sync restore")
    end
    base_raw = case files.read_only.read_text(base_path)
      Ok(s): s
      Error(fe): return fail_msg(console, fe.to_text)
    end
    use_dec? = f.decrypt? or has_key_flag?(f) or base_raw.contains?("\"ciphertext_b64\"")
    aad = f.aad_opt or ""
    delta_paths = f.positional.drop(2)
    rep = if use_dec?
      kr_opt = case load_sync_keyring_opt(files.read_only, env_opt, f)
        Ok(k): k
        Error(msg): return fail_msg(console, msg)
      end
      sealed_base = case Json.decode[SealedEnvelope](base_raw)
        Ok(e): e
        Error(je): return fail_msg(console, "invalid sealed base snapshot JSON: #{je}")
      end
      var sealed_deltas = []
      for dpath in delta_paths
        draw = case files.read_only.read_text(dpath)
          Ok(s): s
          Error(fe): return fail_msg(console, fe.to_text)
        end
        senv = case Json.decode[SealedEnvelope](draw)
          Ok(e): e
          Error(je): return fail_msg(console, "invalid sealed delta '#{dpath}': #{je}")
        end
        sealed_deltas = sealed_deltas.append(senv)
      end
      case kr_opt
        Some(kr):
          case Sync.restore_sealed_chain_with_keyring(files, dst_path, sealed_base, sealed_deltas, kr, aad)
            Ok(r): r
            Error(se): return fail_msg(console, Sync.to_text(se))
          end
        None:
          key = case load_sync_key(files.read_only, env_opt, f)
            Ok(k): k
            Error(msg): return fail_msg(console, msg)
          end
          case Sync.restore_sealed_chain(files, dst_path, sealed_base, sealed_deltas, key, aad)
            Ok(r): r
            Error(se): return fail_msg(console, Sync.to_text(se))
          end
      end
    else
      base_snap = case Json.decode[PortableSnapshot](base_raw)
        Ok(s): s
        Error(je): return fail_msg(console, "invalid base snapshot JSON: #{je}")
      end
      var deltas = []
      for dpath in delta_paths
        draw = case files.read_only.read_text(dpath)
          Ok(s): s
          Error(fe): return fail_msg(console, fe.to_text)
        end
        d = case Json.decode[SyncDelta](draw)
          Ok(v): v
          Error(je): return fail_msg(console, "invalid delta JSON '#{dpath}': #{je}")
        end
        deltas = deltas.append(d)
      end
      case Sync.restore_chain(files, dst_path, base_snap, deltas)
        Ok(r): r
        Error(se): return fail_msg(console, Sync.to_text(se))
      end
    end
    if f.json?
      console.print(Json.encode(rep.to_json))
    else
      console.print(
        "MoDB sync restore ok dst=#{rep.dst_path} base_tx=#{rep.base_txid} final_tx=#{rep
          .final_txid} deltas=#{rep.deltas_applied} puts=#{rep.puts_applied} dels=#{rep
          .deletes_applied} pages=#{rep.page_count}"
      )
    end
    return 0
  end

  if p0.empty? or p1.empty?
    return fail_msg(
      console,
      "usage: modb sync <db.modb> <init-peer|peers|base-snapshot|export|ack|apply|remove-peer|restore> ..."
    )
  end
  now = clock.now
  if p1 == "peers"
    return case Sync.list_peers_locked(files.read_only, p0)
      Error(se): fail_msg(console, Sync.to_text(se))
      Ok(peers):
        if f.json?
          console.print(Json.encode(peers.to_json))
        else if peers.empty?
          console.print("sync peers=0")
        else
          console.print("sync peers=#{peers.size}")
          for p in peers
            pend = case p.pending_seq
              Some(ps): " pending=#{ps}"
              None: ""
            end
            console.print(
              "  #{p.peer_id} acked_seq=#{p.acked_seq} acked_tx=#{p.acked_txid} internal=#{p
                .include_internal?}#{pend}"
            )
          end
        end
        0
    end
  else if p1 == "init-peer"
    peer_id = (f.positional.get(2) or "").trim
    if peer_id.empty?
      return fail_msg(
        console,
        "usage: modb sync <db.modb> init-peer <peer_id> [--include-internal] [--from-empty] [--json]"
      )
    end
    return case Sync.init_peer_locked(files, p0, peer_id, f.include_internal?, f.from_empty?, now)
      Error(se): fail_msg(console, Sync.to_text(se))
      Ok(peer):
        if f.json?
          console.print(Json.encode(peer.to_json))
        else
          console.print(
            "MoDB sync init-peer ok peer=#{peer.peer_id} acked_tx=#{peer.acked_txid} internal=#{peer
              .include_internal?} from_empty=#{peer.from_empty?}"
          )
        end
        0
    end
  else if p1 == "base-snapshot"
    peer_id = (f.positional.get(2) or "").trim
    out_path = (f.positional.get(3) or "").trim
    if peer_id.empty? or out_path.empty?
      return fail_msg(
        console,
        "usage: modb sync <db.modb> base-snapshot <peer_id> <out.json> [--encrypt] [--key-file <p>|--key-env <V>]"
      )
    end
    snap = case Sync.export_peer_base_snapshot_locked(files.read_only, p0, peer_id, now)
      Ok(s): s
      Error(se): return fail_msg(console, Sync.to_text(se))
    end
    payload = if f.encrypt?
      key = case load_sync_key(files.read_only, env_opt, f)
        Ok(k): k
        Error(msg): return fail_msg(console, msg)
      end
      srng = case srng_opt
        Some(r): r
        None: return fail_msg(console, "no SecureRandom capability available for encryption")
      end
      key_id = resolve_sync_key_id(f, env_opt)
      aad = f.aad_opt or ""
      senv = case Sync.seal_snapshot(srng, key, key_id, aad, snap, now)
        Ok(e): e
        Error(se): return fail_msg(console, Sync.to_text(se))
      end
      Sync.encode_sealed_json(senv)
    else
      Export.encode_snapshot_json(snap)
    end
    return case files.write_text(out_path, payload)
      Error(fe): fail_msg(console, fe.to_text)
      Ok(Unit):
        if f.json?
          console.print(
            Json.encode(
              Json.Object({
                "ok": Json.Boolean(true),
                "peer_id": Json.String(peer_id),
                "out": Json.String(out_path),
                "encrypted": Json.Boolean(f.encrypt?),
                "txid": Json.int(snap.source_txid),
                "entries": Json.int(snap.entry_count)
              })
            )
          )
        else
          console.print(
            "MoDB sync base-snapshot ok peer=#{peer_id} out=#{out_path} encrypted=#{f.encrypt?} tx=#{snap
              .source_txid} entries=#{snap.entry_count}"
          )
        end
        0
    end
  else if p1 == "export"
    peer_id = (f.positional.get(2) or "").trim
    out_path = (f.positional.get(3) or "").trim
    if peer_id.empty? or out_path.empty?
      return fail_msg(
        console,
        "usage: modb sync <db.modb> export <peer_id> <out.json> [--encrypt] [--key-file <p>|--key-env <V>]"
      )
    end
    delta = case Sync.export_delta_locked(files, p0, peer_id, now)
      Ok(d): d
      Error(se): return fail_msg(console, Sync.to_text(se))
    end
    payload = if f.encrypt?
      key = case load_sync_key(files.read_only, env_opt, f)
        Ok(k): k
        Error(msg): return fail_msg(console, msg)
      end
      srng = case srng_opt
        Some(r): r
        None: return fail_msg(console, "no SecureRandom capability available for encryption")
      end
      key_id = resolve_sync_key_id(f, env_opt)
      aad = f.aad_opt or ""
      senv = case Sync.seal_delta(srng, key, key_id, aad, delta, now)
        Ok(e): e
        Error(se): return fail_msg(console, Sync.to_text(se))
      end
      Sync.encode_sealed_json(senv)
    else
      Sync.encode_delta_json(delta)
    end
    return case files.write_text(out_path, payload)
      Error(fe): fail_msg(console, fe.to_text)
      Ok(Unit):
        if f.json?
          console.print(
            Json.encode(
              Json.Object({
                "ok": Json.Boolean(true),
                "peer_id": Json.String(peer_id),
                "seq": Json.int(delta.seq),
                "delta_hash": Json.String(delta.delta_hash),
                "ops": Json.int(delta.op_count),
                "out": Json.String(out_path),
                "encrypted": Json.Boolean(f.encrypt?)
              })
            )
          )
        else
          console.print(
            "MoDB sync export ok peer=#{peer_id} seq=#{delta.seq} ops=#{delta.op_count} encrypted=#{f
              .encrypt?} hash=#{delta.delta_hash}"
          )
        end
        0
    end
  else if p1 == "ack"
    peer_id = (f.positional.get(2) or "").trim
    seq = case f.seq_opt
      Some(n): n
      None: return fail_msg(console, "usage: modb sync <db.modb> ack <peer_id> --seq <N> --hash <hex>")
    end
    dhash = case f.hash_opt
      Some(h) if not h.trim.empty?: h.trim
      Some(_) | None: return fail_msg(
        console,
        "usage: modb sync <db.modb> ack <peer_id> --seq <N> --hash <hex>"
      )
    end
    if peer_id.empty?
      return fail_msg(console, "usage: modb sync <db.modb> ack <peer_id> --seq <N> --hash <hex>")
    end
    return case Sync.ack_peer_locked(files, p0, peer_id, seq, dhash, now)
      Error(se): fail_msg(console, Sync.to_text(se))
      Ok(peer):
        if f.json?
          console.print(Json.encode(peer.to_json))
        else
          console.print("MoDB sync ack ok peer=#{peer.peer_id} acked_seq=#{peer.acked_seq}")
        end
        0
    end
  else if p1 == "apply"
    dpath = (f.positional.get(2) or "").trim
    if dpath.empty?
      return fail_msg(
        console,
        "usage: modb sync <db.modb> apply <delta.json> [--decrypt] [--key-file <p>|--key-env <V>] [--aad <t>]"
      )
    end
    draw = case files.read_only.read_text(dpath)
      Ok(s): s
      Error(fe): return fail_msg(console, fe.to_text)
    end
    use_dec? = f.decrypt? or has_key_flag?(f) or draw.contains?("\"ciphertext_b64\"")
    delta = if use_dec?
      kr_opt = case load_sync_keyring_opt(files.read_only, env_opt, f)
        Ok(k): k
        Error(msg): return fail_msg(console, msg)
      end
      aad = f.aad_opt or ""
      senv = case Json.decode[SealedEnvelope](draw)
        Ok(e): e
        Error(je): return fail_msg(console, "invalid sealed delta JSON: #{je}")
      end
      case kr_opt
        Some(kr):
          case Sync.open_delta_with_keyring(kr, aad, senv)
            Ok(d): d
            Error(se): return fail_msg(console, Sync.to_text(se))
          end
        None:
          key = case load_sync_key(files.read_only, env_opt, f)
            Ok(k): k
            Error(msg): return fail_msg(console, msg)
          end
          case Sync.open_delta(key, aad, senv)
            Ok(d): d
            Error(se): return fail_msg(console, Sync.to_text(se))
          end
      end
    else
      case Json.decode[SyncDelta](draw)
        Ok(d): d
        Error(je): return fail_msg(console, "invalid delta JSON: #{je}")
      end
    end
    return case Sync.apply_delta_tracked_locked(files, p0, delta, now)
      Error(se): fail_msg(console, Sync.to_text(se))
      Ok(rep):
        if f.json?
          console.print(Json.encode(rep.to_json))
        else
          console.print(
            "MoDB sync apply ok peer=#{rep.peer_id} seq=#{rep.seq} puts=#{rep.puts_applied} dels=#{rep
              .deletes_applied} tx=#{rep.after_txid}"
          )
        end
        0
    end
  else if p1 == "remove-peer"
    peer_id = (f.positional.get(2) or "").trim
    if peer_id.empty?
      return fail_msg(console, "usage: modb sync <db.modb> remove-peer <peer_id>")
    end
    return case Sync.remove_peer_locked(files, p0, peer_id)
      Error(se): fail_msg(console, Sync.to_text(se))
      Ok(Unit):
        console.print("MoDB sync remove-peer ok peer=#{peer_id}")
        0
    end
  end
  fail_msg(
    console,
    "unknown sync subcommand '#{p1}' (use init-peer|peers|base-snapshot|export|ack|apply|remove-peer|restore)"
  )
end

## Runs the standalone `modb` CLI with explicit `argv`, `Console`, `Files`, `Clock`, `Env`, and `SecureRandom`.
fn run_cli_with_opts(
  argv: List(Text),
  console: Console,
  files: Files,
  clock: Clock,
  env_opt: Option(Env),
  srng_opt: Option(SecureRandom)
) : Int
  head = (argv.first or "").trim
  if head.empty? or head == "help" or head == "--help" or head == "-h"
    print_usage(console)
    return 0
  end
  f = case parse_flags(argv.drop(1))
    Ok(parsed): parsed
    Error(msg): return fail_msg(console, msg)
  end
  return cmd_inspect(console, files, clock, f) if head == "inspect"
  return cmd_verify(console, files, f) if head == "verify"
  return cmd_dump(console, files, f) if head == "dump"
  return cmd_audit(console, files, f) if head == "audit"
  return cmd_worlds(console, files, clock, f) if head == "worlds"
  return cmd_fts(console, files, f) if head == "fts"
  return cmd_vec(console, files, f) if head == "vec"
  return cmd_policy(console, files, f) if head == "policy"
  return cmd_proposals(console, files, f) if head == "proposals"
  return cmd_feeds(console, files, clock, f) if head == "feeds"
  return cmd_matviews(console, files, f) if head == "matviews"
  return cmd_taint(console, files, f) if head == "taint"
  return cmd_erasures(console, files, f) if head == "erasures"
  return cmd_sync(console, files, clock, env_opt, srng_opt, f) if head == "sync"
  return cmd_backup(console, files, clock, f) if head == "backup"
  return cmd_export(console, files, clock, f) if head == "export"
  return cmd_restore(console, files, f) if head == "restore"
  return cmd_compact(console, files, clock, f) if head == "compact"
  return cmd_diff(console, files, f) if head == "diff"
  console.error("unknown command: #{head}")
  print_usage(console)
  2
end

## Runs the standalone `modb` CLI with explicit `argv`, `Console`, `Files`, `Clock`, `Env`, and `SecureRandom`.
fn run_cli_with(
  argv: List(Text),
  console: Console,
  files: Files,
  clock: Clock,
  env: Env,
  srng: SecureRandom
) : Int
  run_cli_with_opts(argv, console, files, clock, Some(env), Some(srng))
end

## Runs the standalone `modb` CLI without `Env`/`SecureRandom` (non-encrypted subcommands).
fn run_cli(argv: List(Text), console: Console, files: Files, clock: Clock) : Int
  run_cli_with_opts(argv, console, files, clock, None, None)
end

fn main(
  args: Args,
  console: Console,
  files: Files,
  clock: Clock,
  env: Env,
  srng: SecureRandom
) : Int
  run_cli_with(args.list, console, files, clock, env, srng)
end

struct NoteRec
  body: Text
end

test "Modb.Cli: inspect, verify --fast, dump, audit, worlds, backup, export/restore, compact, diff"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T02:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  tbl = Table.text_key[NoteRec]("notes")
  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "init", fn(tx) Table.put(tx, tbl, "n1", NoteRec(body: "alpha")) end)
  )
  assert Ledger.open(files, "app.modb", sc, t0) is Ok(db0)
  meta = Ledger.WriteMeta(principal: "user:ada", action: "save", reason: "add beta", at: t0)
  assert Ledger.write(db0, meta, "put n2", Json.Null, fn(tx)
    Table.put(tx, tbl, "n2", NoteRec(body: "beta"))
  end) is
    Ok(db1)
  assert Modb.pin_root(Ledger.store(db1), "snap-v1") is Ok((st2, _pin))
  db2 = Ledger.update_store(db1, st2)
  assert Ledger.write(db2, meta, "put n3", Json.Null, fn(tx)
    Table.put(tx, tbl, "n3", NoteRec(body: "gamma"))
  end) is
    Ok(db3)
  assert Ledger.record_verify_checkpoint(db3, t0) is Ok((_db4, _cp))

  c_help = Console.fake()
  assert run_cli(["help"], c_help, files, clock) == 0
  assert (c_help.printed.first or "").contains?("Usage:")

  c_ins = Console.fake()
  assert run_cli(["inspect", "app.modb", "--json"], c_ins, files, clock) == 0
  assert (c_ins.printed.first or "").contains?("\"bucket\":\"notes\"")

  c_ver = Console.fake()
  assert run_cli(["verify", "app.modb"], c_ver, files, clock) == 0
  assert (c_ver.printed.first or "").contains?("MoDB verify ok=true mode=full")

  c_vf = Console.fake()
  assert run_cli(["verify", "app.modb", "--fast", "10"], c_vf, files, clock) == 0
  assert (c_vf.printed.first or "").contains?("mode=fast(10)")

  c_dump = Console.fake()
  assert run_cli(["dump", "app.modb", "notes"], c_dump, files, clock) == 0
  assert c_dump.printed.join("\n").contains?("beta")

  c_aud = Console.fake()
  assert run_cli(["audit", "app.modb", "--principal", "user:ada"], c_aud, files, clock) == 0
  assert c_aud.printed.join("\n").contains?("add beta")

  c_wr = Console.fake()
  assert run_cli(["worlds", "app.modb"], c_wr, files, clock) == 0
  assert (c_wr.printed.first or "").contains?("LandingMetrics")

  c_diff_pin = Console.fake()
  assert run_cli(["diff", "app.modb", "--pin", "snap-v1"], c_diff_pin, files, clock) == 0
  assert c_diff_pin.printed.join("\n").contains?("notes: +1 / ~0 / -0")

  c_bak = Console.fake()
  assert run_cli(["backup", "app.modb", "app-bak.modb"], c_bak, files, clock) == 0
  assert (c_bak.printed.first or "").contains?("MoDB backup ok")
  assert run_cli(["verify", "app-bak.modb"], Console.fake(), files, clock) == 0
  ## Refuses overwrite
  assert run_cli(["backup", "app.modb", "app-bak.modb"], Console.fake(), files, clock) == 1

  c_exp = Console.fake()
  assert run_cli(["export", "app.modb", "app.snap.json"], c_exp, files, clock) == 0
  c_res = Console.fake()
  assert run_cli(["restore", "app.snap.json", "app-res.modb"], c_res, files, clock) == 0
  assert run_cli(["verify", "app-res.modb"], Console.fake(), files, clock) == 0

  c_cmp = Console.fake()
  assert run_cli(["compact", "app.modb"], c_cmp, files, clock) == 0
  assert (c_cmp.printed.first or "").contains?("MoDB compact ok") and
    (c_cmp.printed.first or "").contains?("->0 entries=")

  c_diff_files = Console.fake()
  assert run_cli(["diff", "app.modb", "app-bak.modb"], c_diff_files, files, clock) == 0
  assert c_diff_files.printed.join("\n").contains?("buckets=0")

  ## Index FTS + Vec and inspect/query via `modb fts` and `modb vec`
  f_idx = Fts.index("notes")
  v_idx = Vec.index("notes", 4)
  assert Modb.open(files, "app.modb") is Ok(s_fts0)
  assert Fts.index_document(
    s_fts0,
    f_idx,
    Fts.DocumentInput(
      doc_id: "n1",
      scope: "ops",
      fields: [Fts.FieldInput(name: "body", text: "alpha failover runbook", weight: 2)]
    )
  ) is
    Ok(s_fts1)
  assert Vec.put_vector(
    s_fts1,
    v_idx,
    Vec.VectorInput(doc_id: "n1", scope: "ops", values: [1.0, 0.0, 0.0, 0.0])
  ) is
    Ok(_)

  c_fts_ls = Console.fake()
  assert run_cli(["fts", "app.modb"], c_fts_ls, files, clock) == 0
  assert c_fts_ls.printed.join("\n").contains?("prefix=notes docs=1")

  c_fts_q = Console.fake()
  assert run_cli(["fts", "app.modb", "notes", "failov", "--prefix", "--scope", "ops"], c_fts_q, files, clock) ==
    0
  assert c_fts_q.printed.join("\n").contains?("n1")

  c_vec_ls = Console.fake()
  assert run_cli(["vec", "app.modb", "--json"], c_vec_ls, files, clock) == 0
  assert c_vec_ls.printed.join("\n").contains?("\"dimensions\":4")

  ## Milestone 12 CLI: clearances (`modb policy`), governance proposals (`modb proposals`), and feeds (`modb feeds`)
  assert Ledger.open(files, "app.modb", sc, t0) is Ok(db_g0)
  t_exp = Time.parse("2026-11-26T12:00:00Z") or stop "t_exp"
  assert Grants.issue_root(
    db_g0,
    meta,
    Grants.GrantSpec(
      id: "g-cli",
      principal: "agent:cli",
      allowed_actions: ["save"],
      max_calls: 10,
      expires_at: t_exp
    )
  ) is
    Ok((db_g1, _))
  assert Policy.set_clearance(db_g1, Policy.policy(), meta, "g-cli", Policy.Confidential, t0) is
    Ok((db_g2, _))
  assert Proposals.submit_proposal(
    db_g2,
    Views.catalog(),
    Policy.policy(),
    "p-cli-inv",
    Proposals.ProposeInvariant(
      spec: Proposals.DynamicInvariantSpec(
        name: "note_body_req",
        description: "non-empty body",
        bucket: "notes",
        rule: Proposals.FieldNonEmpty(field: "body")
      )
    ),
    "agent:cli",
    Some("g-cli"),
    "cli proposal",
    t0
  ) is
    Ok((db_g3, _))
  assert Feeds.subscribe(
    db_g3,
    Feeds.FeedSpec(
      id: "f-cli",
      principal: "agent:cli",
      grant_id: Some("g-cli"),
      buckets: ["notes"],
      include_internal: false,
      from_beginning: false
    ),
    "cli feed",
    t0
  ) is
    Ok((db_g4, _))
  assert Ledger.write(db_g4, meta, "put n4", Json.Null, fn(tx)
    Table.put(tx, tbl, "n4", NoteRec(body: "delta"))
  end) is
    Ok(_)

  c_pol = Console.fake()
  assert run_cli(["policy", "app.modb"], c_pol, files, clock) == 0
  assert c_pol.printed.join("\n").contains?("g-cli") and
    c_pol.printed.join("\n").contains?("confidential")

  c_prp = Console.fake()
  assert run_cli(["proposals", "app.modb", "--status", "pending"], c_prp, files, clock) == 0
  assert c_prp.printed.join("\n").contains?("p-cli-inv")

  c_fds = Console.fake()
  assert run_cli(["feeds", "app.modb"], c_fds, files, clock) == 0
  assert c_fds.printed.join("\n").contains?("f-cli")

  c_fdp = Console.fake()
  assert run_cli(["feeds", "app.modb", "poll", "f-cli"], c_fdp, files, clock) == 0
  assert c_fdp.printed.join("\n").contains?("events=1") and
    c_fdp.printed.join("\n").contains?("notes:n4")

  ## Milestone 13 CLI: `modb taint` and `modb erasures` + `inspect` counts
  assert Taint.ensure_session_locked(
    files,
    "app.modb",
    sc,
    "s-cli-1",
    "agent:cli",
    Some("g-cli"),
    t0
  ) is
    Ok(_)
  assert Taint.record_untrusted_read_locked(files, "app.modb", sc, "s-cli-1", "web:ticket", t0) is
    Ok(_)
  assert Erasure.erase_subject_locked(
    files,
    "app.modb",
    sc,
    Erasure.erasure_request("rcpt-cli-1", "cli-user"),
    "admin:cli",
    true,
    "cli gdpr test",
    t0
  ) is
    Ok(_)

  c_tnt = Console.fake()
  assert run_cli(["taint", "app.modb"], c_tnt, files, clock) == 0
  assert c_tnt.printed.join("\n").contains?("taint_sessions=1") and
    c_tnt.printed.join("\n").contains?("s-cli-1") and
    c_tnt.printed.join("\n").contains?("tainted=true")

  c_ers = Console.fake()
  assert run_cli(["erasures", "app.modb"], c_ers, files, clock) == 0
  assert c_ers.printed.join("\n").contains?("erasure_receipts=1") and
    c_ers.printed.join("\n").contains?("rcpt-cli-1")

  c_insp13 = Console.fake()
  assert run_cli(["inspect", "app.modb", "--json"], c_insp13, files, clock) == 0
  assert c_insp13.printed.join("\n").contains?("\"taint_sessions\":1") and
    c_insp13.printed.join("\n").contains?("\"erasure_receipts\":1")

  ## Milestone 15 CLI: `modb matviews list | refresh | query`
  mv_def = Matview.MatViewDef(
    name: "notes_by_body",
    description: "CLI notes rollup",
    source_bucket: "notes",
    group_by: "body",
    aggregates: [Matview.MatAggSpec(alias: "cnt", op: Matview.MatCount)]
  )
  assert Modb.with_exclusive_lock(
    files,
    "app.modb",
    fn(e) e.to_text end,
    fn(st)
      case Matview.define_matview(st, mv_def)
        Ok((_st2, meta2)): Ok(meta2)
        Error(e): Error(Matview.to_text(e))
      end
    end
  ) is
    Ok(_)
  c_mvl = Console.fake()
  assert run_cli(["matviews", "app.modb", "list", "--json"], c_mvl, files, clock) == 0
  assert c_mvl.printed.join("\n").contains?("notes_by_body")

  c_mvr = Console.fake()
  assert run_cli(["matviews", "app.modb", "refresh", "notes_by_body", "--json"], c_mvr, files, clock) ==
    0
  assert c_mvr.printed.join("\n").contains?("notes_by_body")

  c_mvq = Console.fake()
  assert run_cli(["matviews", "app.modb", "query", "notes_by_body", "--json"], c_mvq, files, clock) ==
    0
  assert c_mvq.printed.join("\n").contains?("\"returned_groups\":")

  ## Milestone 16 CLI: encrypted & plain `modb sync` lifecycle + restore
  env_key = Env.of({
    "TEST_SYNC_KEY": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
  })
  srng = SecureRandom.seeded(42)

  c_si = Console.fake()
  assert run_cli_with(["sync", "app.modb", "init-peer", "cli-bak", "--include-internal", "--json"], c_si, files, clock, env_key, srng) ==
    0
  assert c_si.printed.join("\n").contains?("\"peer_id\":\"cli-bak\"")

  c_sp = Console.fake()
  assert run_cli_with(["sync", "app.modb", "peers", "--json"], c_sp, files, clock, env_key, srng) ==
    0
  assert c_sp.printed.join("\n").contains?("cli-bak")

  c_sb = Console.fake()
  assert run_cli_with(
    [
      "sync",
      "app.modb",
      "base-snapshot",
      "cli-bak",
      "cli-base.enc.json",
      "--encrypt",
      "--key-env",
      "TEST_SYNC_KEY",
      "--aad",
      "cli-aad",
      "--json"
    ],
    c_sb,
    files,
    clock,
    env_key,
    srng
  ) == 0
  assert c_sb.printed.join("\n").contains?("\"encrypted\":true")

  assert Ledger.open(files, "app.modb", sc, t0) is Ok(db_s1)
  assert Ledger.write(db_s1, meta, "put n5", Json.Null, fn(tx)
    Table.put(tx, tbl, "n5", NoteRec(body: "epsilon"))
  end) is
    Ok(_)

  c_se = Console.fake()
  assert run_cli_with(
    [
      "sync",
      "app.modb",
      "export",
      "cli-bak",
      "cli-d1.enc.json",
      "--encrypt",
      "--key-env",
      "TEST_SYNC_KEY",
      "--aad",
      "cli-aad",
      "--json"
    ],
    c_se,
    files,
    clock,
    env_key,
    srng
  ) == 0
  se_txt = c_se.printed.join("\n")
  assert Json.decode[Json](se_txt) is Ok(se_json)
  dhash = se_json.text_at("delta_hash") or ""
  assert not dhash.empty?

  c_sa = Console.fake()
  assert run_cli_with(
    ["sync", "app.modb", "ack", "cli-bak", "--seq", "1", "--hash", dhash, "--json"],
    c_sa,
    files,
    clock,
    env_key,
    srng
  ) == 0
  assert c_sa.printed.join("\n").contains?("\"acked_seq\":1")

  c_sr = Console.fake()
  assert run_cli_with(
    [
      "sync",
      "app-sync-restored.modb",
      "restore",
      "--base",
      "cli-base.enc.json",
      "cli-d1.enc.json",
      "--decrypt",
      "--key-env",
      "TEST_SYNC_KEY",
      "--aad",
      "cli-aad",
      "--json"
    ],
    c_sr,
    files,
    clock,
    env_key,
    srng
  ) == 0
  assert c_sr.printed.join("\n").contains?("\"deltas_applied\":1")
  assert run_cli(["verify", "app-sync-restored.modb"], Console.fake(), files, clock) == 0

  assert run_cli_with(["sync", "app.modb", "remove-peer", "cli-bak"], Console.fake(), files, clock, env_key, srng) ==
    0
end
