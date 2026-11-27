## MoDB Milestone 16 (`v0.8.0`): Signed Hash-Chained Incremental Sync Replication & Encrypted Off-Host Backup (`Modb.Sync`).
##
## Features:
## - Durable sync peer cursor registry in `_modb_sync_peers` paired with a two-phase persistent root pin
##   protocol (`sync:<peer_id>` acknowledged root + `sync_pending:<peer_id>` exported target root) so
##   retries before `ack_peer` are safe and concurrent writes between `export_delta` and `ack_peer` are
##   never lost or double-exported.
## - Structural O(diff) delta extraction via `Modb.diff_roots` filtering `_modb_pins` and `_modb_sync_peers`,
##   bound by canonical domain-separated SHA-256 `payload_hash` and chained `delta_hash`.
## - Monotonic hash-chain verification + single-`WriteTx` atomic replica apply using `Modb.commit_at_least`
##   to preserve Ledger `entry.txid <= store_txid` invariants across batched commits.
## - Authenticated AES-256-GCM off-host envelopes (`SealedEnvelope` via `Crypto.seal`/`Crypto.open` +
##   12-byte CSPRNG nonces + domain-separated metadata AAD) and full `restore_chain` / `restore_sealed_chain`.
module Modb.Sync
expose sync_peers_bucket,
sync_format_version,
sealed_format_version,
genesis_hash,
SyncError(..),
SyncPeer(..),
SyncOp(..),
SyncBucketDelta(..),
SyncDelta(..),
SyncApplyReport(..),
SealedEnvelope(..),
RestoreChainReport(..),
to_text,
encode_delta_json,
encode_sealed_json,
init_peer,
get_peer,
list_peers,
remove_peer,
export_peer_base_snapshot,
export_delta,
ack_peer,
verify_delta,
apply_delta,
apply_delta_tracked,
seal_bytes,
open_bytes,
seal_delta,
open_delta,
seal_snapshot,
open_snapshot,
parse_keyring_text,
open_bytes_with_keyring,
open_delta_with_keyring,
open_snapshot_with_keyring,
restore_chain,
restore_sealed_chain,
restore_sealed_chain_with_keyring,
init_peer_locked,
get_peer_locked,
list_peers_locked,
export_peer_base_snapshot_locked,
export_delta_locked,
ack_peer_locked,
apply_delta_locked,
apply_delta_tracked_locked,
remove_peer_locked,
get_replica_cursor,
get_replica_cursor_locked,
seed_replica_cursor_locked
use Crypto
use Json
use Modb{Store, pins_bucket}
use Modb.Errors{ModbError, wrap_io}
use Modb.Export
use Modb.Table{Table, TableError}
use Modb.Tree{KeyDiff}

## Reserved internal bucket persisting replication & off-host backup peer cursors.
sync_peers_bucket = "_modb_sync_peers"

sync_format_version = 1
sealed_format_version = 1
genesis_hash = "0000000000000000000000000000000000000000000000000000000000000000"

## Every failure raised by `Modb.Sync`.
enum SyncError
  StorageFailure(ModbError)
  TableFailure(TableError)
  ExportFailure(Export.ExportError)
  InvalidPeerId(peer_id: Text)
  PeerAlreadyExists(peer_id: Text)
  UnknownPeer(peer_id: Text)
  PinMissing(pin_id: Text)
  AckMismatch(reason: Text)
  InvalidDelta(reason: Text)
  ChainMismatch(
    expected_seq: Int,
    actual_seq: Int,
    expected_prev_hash: Text,
    actual_prev_hash: Text
  )
  InvalidKeyLength(expected: Int, got: Int)
  InvalidEnvelope(reason: Text)
  KeyNotFound(key_id: Text)
  DecryptionFailed
  TargetExists(path: Text)
end

## Formats any `SyncError` into an operator-friendly message (never leaking key material).
fn to_text(err: SyncError) : Text
  case err
    StorageFailure(e): e.to_text
    TableFailure(e): e.to_text
    ExportFailure(e): e.to_text
    InvalidPeerId(peer_id: p): "invalid sync peer id '#{p}'"
    PeerAlreadyExists(peer_id: p): "sync peer '#{p}' already exists"
    UnknownPeer(peer_id: p): "unknown sync peer '#{p}'"
    PinMissing(pin_id: p): "missing persistent sync pin '#{p}'"
    AckMismatch(reason: r): "sync ack mismatch: #{r}"
    InvalidDelta(reason: r): "invalid sync delta: #{r}"
    ChainMismatch(expected_seq: es, actual_seq: acs, expected_prev_hash: eh, actual_prev_hash: ah): "sync hash-chain mismatch: expected seq=#{es} prev=#{eh}, got seq=#{acs} prev=#{ah}"
    InvalidKeyLength(expected: exp, got: g): "invalid encryption key length: expected #{exp} bytes, got #{g}"
    InvalidEnvelope(reason: r): "invalid sealed envelope: #{r}"
    KeyNotFound(key_id: kid): "backup keyring has no key for key_id '#{kid}'"
    DecryptionFailed: "sealed envelope decryption failed (wrong key, AAD, or tampered ciphertext)"
    TargetExists(path: p): "restore destination already exists: #{p}"
  end
end

## Persistent sync peer cursor stored in `_modb_sync_peers`.
struct SyncPeer
  peer_id: Text
  include_internal?: Bool
  from_empty?: Bool
  acked_seq: Int
  acked_txid: Int
  acked_hash: Text
  pending_seq: Option(Int)
  pending_txid: Option(Int)
  pending_hash: Option(Text)
  created_at: Time
  updated_at: Time
end

## One deterministic put or delete operation within a bucket delta.
struct SyncOp
  op: Text
  key_hex: Text
  value_hex: Text
end

## All sorted operations for one bucket in a `SyncDelta`.
struct SyncBucketDelta
  bucket: Text
  ops: List(SyncOp)
end

## Self-verifying incremental CoW delta bound by canonical SHA-256 `payload_hash` and chained `delta_hash`.
struct SyncDelta
  format_version: Int
  peer_id: Text
  seq: Int
  prev_hash: Text
  from_txid: Int
  target_txid: Int
  include_internal?: Bool
  created_at: Time
  bucket_count: Int
  op_count: Int
  buckets: List(SyncBucketDelta)
  payload_hash: Text
  delta_hash: Text
end

## Summary returned by `apply_delta` / `apply_delta_tracked`.
struct SyncApplyReport
  peer_id: Text
  seq: Int
  puts_applied: Int
  deletes_applied: Int
  before_txid: Int
  after_txid: Int
  delta_hash: Text
end

## Authenticated AES-256-GCM off-host envelope holding an encrypted snapshot or delta JSON payload.
struct SealedEnvelope
  format_version: Int
  kind: Text
  alg: Text
  key_id: Text
  aad: Text
  nonce_b64: Text
  ciphertext_b64: Text
  sealed_at: Time
end

## Summary returned after rebuilding and verifying a database from a base snapshot and delta chain.
struct RestoreChainReport
  dst_path: Text
  base_txid: Int
  final_txid: Int
  deltas_applied: Int
  puts_applied: Int
  deletes_applied: Int
  page_count: Int
  free_page_count: Int
  last_delta_hash: Text
end

fn peers_table() : Table(Text, SyncPeer)
  Table.text_key[SyncPeer](sync_peers_bucket)
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, SyncError)
  res.map_error(fn(e) StorageFailure(e) end)
end

fn wrap_table(res: Result(T, TableError)) : Result(T, SyncError)
  res.map_error(fn(e) TableFailure(e) end)
end

fn wrap_export(res: Result(T, Export.ExportError)) : Result(T, SyncError)
  res.map_error(fn(e) ExportFailure(e) end)
end

fn pin_id(pid: Text) : Text
  "sync:#{pid}"
end

fn pending_pin_id(pid: Text) : Text
  "sync_pending:#{pid}"
end

fn replica_cursor_key(pid: Text) : Text
  "replica:#{pid}"
end

fn valid_peer_char?(c: Char) : Bool
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or
    c == '.' or
    c == '_' or
    c == '-'
end

fn validate_peer_id(raw: Text) : Result(Text, SyncError)
  clean = raw.trim
  cs = clean.chars
  if cs.empty? or
    cs.size > 64 or
    clean.starts_with?("replica:") or
    not cs.all?(fn(c) valid_peer_char?(c) end)
    return Error(InvalidPeerId(peer_id: raw))
  end
  Ok(clean)
end

fn is_sync_internal_excluded?(bname: Text, include_internal?: Bool) : Bool
  bname == pins_bucket or
    bname == sync_peers_bucket or (not include_internal? and bname.starts_with?("_modb_"))
end

fn len_prefixed(b: Bytes) : Bytes
  Bytes.join([Bytes.from_u32_be(b.size), b])
end

fn compute_payload_hash(buckets: List(SyncBucketDelta)) : Text
  var parts = ["MODB-SYNC-PAYLOAD-V1".bytes, Bytes.from_u32_be(buckets.size)]
  for b in buckets
    parts = parts.append(len_prefixed(b.bucket.bytes)).append(Bytes.from_u32_be(b.ops.size))
    for o in b.ops
      parts = parts.append(len_prefixed(o.op.bytes)).append(len_prefixed(o.key_hex.bytes)).append(
        len_prefixed(o.value_hex.bytes)
      )
    end
  end
  Crypto.sha256(Bytes.join(parts)).to_hex
end

fn compute_delta_hash(
  format_version: Int,
  peer_id: Text,
  seq: Int,
  prev_hash: Text,
  from_txid: Int,
  target_txid: Int,
  include_internal?: Bool,
  created_at: Time,
  bucket_count: Int,
  op_count: Int,
  payload_hash: Text
) : Text
  flag_b = if include_internal?: Bytes.from_i64_be(1) else: Bytes.from_i64_be(0)
  parts = [
    "MODB-SYNC-DELTA-V1".bytes,
    Bytes.from_i64_be(format_version),
    len_prefixed(peer_id.bytes),
    Bytes.from_i64_be(seq),
    len_prefixed(prev_hash.bytes),
    Bytes.from_i64_be(from_txid),
    Bytes.from_i64_be(target_txid),
    flag_b,
    len_prefixed(Json.encode(created_at).bytes),
    Bytes.from_i64_be(bucket_count),
    Bytes.from_i64_be(op_count),
    len_prefixed(payload_hash.bytes)
  ]
  Crypto.sha256(Bytes.join(parts)).to_hex
end

## Fast canonical JSON encoder for `SyncDelta` avoiding per-character hex escaping overhead.
fn encode_delta_json(delta: SyncDelta) : Text
  var b_strs = []
  for b in delta.buckets
    var op_strs = []
    for o in b.ops
      op_strs = op_strs.append(
        "{\"op\":\"#{o.op}\",\"key_hex\":\"#{o.key_hex}\",\"value_hex\":\"#{o.value_hex}\"}"
      )
    end
    bname_json = Json.encode(b.bucket)
    b_strs = b_strs.append("{\"bucket\":#{bname_json},\"ops\":[#{op_strs.join(",")}]}")
  end
  inc_str = if delta.include_internal?: "true" else: "false"
  pid_json = Json.encode(delta.peer_id)
  ts_json = Json.encode(delta.created_at)
  "{\"format_version\":#{delta.format_version},\"peer_id\":#{pid_json},\"seq\":#{delta.seq},\"prev_hash\":\"#{delta
    .prev_hash}\",\"from_txid\":#{delta.from_txid},\"target_txid\":#{delta.target_txid},\"include_internal?\":#{inc_str},\"created_at\":#{ts_json},\"bucket_count\":#{delta
    .bucket_count},\"op_count\":#{delta.op_count},\"buckets\":[#{b_strs.join(",")}],\"payload_hash\":\"#{delta
    .payload_hash}\",\"delta_hash\":\"#{delta.delta_hash}\"}"
end

## Fast JSON encoder for `SealedEnvelope`.
fn encode_sealed_json(env: SealedEnvelope) : Text
  Json.encode(env.to_json)
end

## Looks up one peer by `peer_id`.
fn get_peer(store: Store, peer_id: Text) : Result(Option(SyncPeer), SyncError)
  pid = try validate_peer_id(peer_id)
  wrap_table(Table.get(store, peers_table(), pid))
end

## Lists all registered sync peers (excludes internal replica cursor records).
fn list_peers(store: Store) : Result(List(SyncPeer), SyncError)
  rows = try wrap_table(Table.all(store, peers_table()))
  Ok(rows.filter(fn(p) not p.0.starts_with?("replica:") end).map(fn(p) p.1 end))
end

## Initializes a persistent sync peer baseline at the current committed root (`sync:<peer_id>`).
fn init_peer(store: Store, peer_id: Text, include_internal?: Bool, from_empty?: Bool, now: Time) : Result(
  (Store, SyncPeer),
  SyncError
)
  pid = try validate_peer_id(peer_id)
  case try get_peer(store, pid)
    Some(_): return Error(PeerAlreadyExists(peer_id: pid))
    None: Unit
  end
  tx = Modb.begin_write(store)
  (t1, base_pin) = try wrap_modb(Modb.tx_pin_base_root(tx, pin_id(pid)))
  base_tx = if from_empty?: 0 else: base_pin.txid
  peer = SyncPeer(
    peer_id: pid,
    include_internal?: include_internal?,
    from_empty?: from_empty?,
    acked_seq: 0,
    acked_txid: base_tx,
    acked_hash: genesis_hash,
    pending_seq: None,
    pending_txid: None,
    pending_hash: None,
    created_at: now,
    updated_at: now
  )
  t2 = try wrap_table(Table.put(t1, peers_table(), pid, peer))
  next_store = try wrap_modb(Modb.commit(t2))
  Ok((next_store, peer))
end

## Unpins both acknowledged and pending roots for `peer_id` and removes its registry row.
fn remove_peer(store: Store, peer_id: Text) : Result(Store, SyncError)
  pid = try validate_peer_id(peer_id)
  _existing = try (try wrap_table(Table.get(store, peers_table(), pid))).or_fail(
    UnknownPeer(peer_id: pid)
  )
  var tx = Modb.begin_write(store)
  if (try wrap_modb(Modb.get_pin(store, pending_pin_id(pid)))) is Some(_)
    tx = try wrap_modb(Modb.tx_unpin_root(tx, pending_pin_id(pid)))
  end
  if (try wrap_modb(Modb.get_pin(store, pin_id(pid)))) is Some(_)
    tx = try wrap_modb(Modb.tx_unpin_root(tx, pin_id(pid)))
  end
  t1 = try wrap_table(Table.delete(tx, peers_table(), pid))
  wrap_modb(Modb.commit(t1))
end

## Exports a layout-independent `PortableSnapshot` matching `peer_id`'s acknowledged root
## (`sync:<peer_id>`), omitting `_modb_pins` and `_modb_sync_peers`.
## When `peer.from_empty?` and `peer.acked_seq == 0`, returns an empty base snapshot (`source_txid: 1`).
fn export_peer_base_snapshot(store: Store, peer_id: Text, now: Time) : Result(
  Export.PortableSnapshot,
  SyncError
)
  pid = try validate_peer_id(peer_id)
  peer = try (try get_peer(store, pid)).or_fail(UnknownPeer(peer_id: pid))
  if peer.from_empty? and peer.acked_seq == 0
    digest = Export.compute_snapshot_digest(1, 1, 0, peer.include_internal?, now, [])
    return Ok(
      Export.PortableSnapshot(
        format_version: 1,
        source_txid: 1,
        schema_version: 0,
        include_internal: peer.include_internal?,
        exported_at: now,
        bucket_count: 0,
        entry_count: 0,
        buckets: [],
        sha256: digest
      )
    )
  end
  pin = try (try wrap_modb(Modb.get_pin(store, pin_id(pid)))).or_fail(
    PinMissing(pin_id: pin_id(pid))
  )
  (snap, _skipped) = try wrap_export(
    Export.export_filtered_at_root(
      store,
      pin.catalog_root,
      pin.txid,
      peer.include_internal?,
      fn(b) not is_sync_internal_excluded?(b, peer.include_internal?) end,
      now
    )
  )
  Ok(snap)
end

fn diff_changes_to_ops(changes: List(KeyDiff)) : List(SyncOp)
  var ops = []
  for kd in changes
    case kd
      Added(key: k, value: v): ops = ops.append(
        SyncOp(op: "put", key_hex: k.to_hex, value_hex: v.to_hex)
      )
      Removed(key: k, value: _): ops = ops.append(
        SyncOp(op: "del", key_hex: k.to_hex, value_hex: "")
      )
      Modified(key: k, old_value: _, new_value: nv): ops = ops.append(
        SyncOp(op: "put", key_hex: k.to_hex, value_hex: nv.to_hex)
      )
    end
  end
  ops
end

## Exports the next hash-chained incremental `SyncDelta` for `peer_id` since its acknowledged root,
## and atomically records a pending root pin (`sync_pending:<peer_id>`) at the exact exported root.
## Re-running `export_delta` before `ack_peer` is retry-safe and includes any newer commits.
fn export_delta(store: Store, peer_id: Text, now: Time) : Result((Store, SyncDelta), SyncError)
  pid = try validate_peer_id(peer_id)
  peer = try (try get_peer(store, pid)).or_fail(UnknownPeer(peer_id: pid))
  base_pin = try (try wrap_modb(Modb.get_pin(store, pin_id(pid)))).or_fail(
    PinMissing(pin_id: pin_id(pid))
  )
  from_root = if peer.from_empty? and peer.acked_seq == 0: 0 else: base_pin.catalog_root
  from_txid = if peer.from_empty? and peer.acked_seq == 0: 0 else: base_pin.txid
  target_root = Modb.catalog_root(store)
  target_txid = Modb.txid(store)

  raw_diffs = try wrap_modb(Modb.diff_roots(store, from_root, target_root))
  var bucket_deltas = []
  var total_ops = 0
  for bd in raw_diffs
    if not is_sync_internal_excluded?(bd.bucket, peer.include_internal?)
      ops = diff_changes_to_ops(bd.changes)
      if not ops.empty?
        total_ops += ops.size
        bucket_deltas = bucket_deltas.append(SyncBucketDelta(bucket: bd.bucket, ops: ops))
      end
    end
  end

  next_seq = peer.acked_seq + 1
  prev_hash = peer.acked_hash
  p_hash = compute_payload_hash(bucket_deltas)
  d_hash = compute_delta_hash(
    sync_format_version,
    pid,
    next_seq,
    prev_hash,
    from_txid,
    target_txid,
    peer.include_internal?,
    now,
    bucket_deltas.size,
    total_ops,
    p_hash
  )
  delta = SyncDelta(
    format_version: sync_format_version,
    peer_id: pid,
    seq: next_seq,
    prev_hash: prev_hash,
    from_txid: from_txid,
    target_txid: target_txid,
    include_internal?: peer.include_internal?,
    created_at: now,
    bucket_count: bucket_deltas.size,
    op_count: total_ops,
    buckets: bucket_deltas,
    payload_hash: p_hash,
    delta_hash: d_hash
  )

  var tx = Modb.begin_write(store)
  if (try wrap_modb(Modb.get_pin(store, pending_pin_id(pid)))) is Some(_)
    tx = try wrap_modb(Modb.tx_unpin_root(tx, pending_pin_id(pid)))
  end
  (t1, _pend_pin) = try wrap_modb(Modb.tx_pin_base_root(tx, pending_pin_id(pid)))
  updated_peer = SyncPeer(
    peer_id: peer.peer_id,
    include_internal?: peer.include_internal?,
    from_empty?: peer.from_empty?,
    acked_seq: peer.acked_seq,
    acked_txid: peer.acked_txid,
    acked_hash: peer.acked_hash,
    pending_seq: Some(next_seq),
    pending_txid: Some(target_txid),
    pending_hash: Some(d_hash),
    created_at: peer.created_at,
    updated_at: now
  )
  t2 = try wrap_table(Table.put(t1, peers_table(), pid, updated_peer))
  next_store = try wrap_modb(Modb.commit(t2))
  Ok((next_store, delta))
end

## Acknowledges delivery of `(seq, delta_hash)` for `peer_id` and atomically advances
## `sync:<peer_id>` to `sync_pending:<peer_id>` inside a single `WriteTx`.
## Concurrent writes committed after `export_delta` are excluded from the acked pin and captured
## cleanly in `seq + 1`.
fn ack_peer(store: Store, peer_id: Text, seq: Int, delta_hash: Text, now: Time) : Result(
  (Store, SyncPeer),
  SyncError
)
  pid = try validate_peer_id(peer_id)
  peer = try (try get_peer(store, pid)).or_fail(UnknownPeer(peer_id: pid))
  case (peer.pending_seq, peer.pending_txid, peer.pending_hash)
    (Some(pseq), Some(ptx), Some(phash)):
      if pseq != seq or phash != delta_hash
        return Error(
          AckMismatch(
            reason: "expected pending seq=#{pseq} hash=#{phash}, got seq=#{seq} hash=#{delta_hash}"
          )
        )
      end
      _pend = try (try wrap_modb(Modb.get_pin(store, pending_pin_id(pid)))).or_fail(
        PinMissing(pin_id: pending_pin_id(pid))
      )
      var tx = Modb.begin_write(store)
      if (try wrap_modb(Modb.get_pin(store, pin_id(pid)))) is Some(_)
        tx = try wrap_modb(Modb.tx_unpin_root(tx, pin_id(pid)))
      end
      (t1, _promoted) = try wrap_modb(
        Modb.tx_pin_existing_root(tx, pin_id(pid), pending_pin_id(pid))
      )
      t2 = try wrap_modb(Modb.tx_unpin_root(t1, pending_pin_id(pid)))
      updated = SyncPeer(
        peer_id: peer.peer_id,
        include_internal?: peer.include_internal?,
        from_empty?: peer.from_empty?,
        acked_seq: seq,
        acked_txid: ptx,
        acked_hash: delta_hash,
        pending_seq: None,
        pending_txid: None,
        pending_hash: None,
        created_at: peer.created_at,
        updated_at: now
      )
      t3 = try wrap_table(Table.put(t2, peers_table(), pid, updated))
      next_store = try wrap_modb(Modb.commit(t3))
      Ok((next_store, updated))
    _: Error(AckMismatch(reason: "peer '#{pid}' has no pending delta to acknowledge"))
  end
end

enum DecodedSyncOp
  PutOp(key: Bytes, value: Bytes)
  DelOp(key: Bytes)
end

fn verify_and_decode_delta(delta: SyncDelta) : Result(
  (List((Text, List(DecodedSyncOp))), Int, Int),
  SyncError
)
  if delta.format_version != sync_format_version
    return Error(
      InvalidDelta(
        reason: "unsupported delta format_version=#{delta.format_version} (expected #{sync_format_version})"
      )
    )
  end
  _ = try validate_peer_id(delta.peer_id)
  if delta.seq < 1
    return Error(InvalidDelta(reason: "delta seq must be >= 1 (got #{delta.seq})"))
  end
  if delta.bucket_count != delta.buckets.size
    return Error(
      InvalidDelta(reason: "bucket_count #{delta.bucket_count} != actual #{delta.buckets.size}")
    )
  end
  exp_payload = compute_payload_hash(delta.buckets)
  if delta.payload_hash != exp_payload
    return Error(
      InvalidDelta(
        reason: "payload_hash mismatch: expected #{exp_payload}, got #{delta.payload_hash}"
      )
    )
  end
  exp_delta = compute_delta_hash(
    delta.format_version,
    delta.peer_id,
    delta.seq,
    delta.prev_hash,
    delta.from_txid,
    delta.target_txid,
    delta.include_internal?,
    delta.created_at,
    delta.bucket_count,
    delta.op_count,
    delta.payload_hash
  )
  if delta.delta_hash != exp_delta
    return Error(
      InvalidDelta(reason: "delta_hash mismatch: expected #{exp_delta}, got #{delta.delta_hash}")
    )
  end
  var decoded_buckets = []
  var total_ops = 0
  var puts = 0
  var dels = 0
  var prev_bname = ""
  var has_prev_bucket? = false
  for b in delta.buckets
    if b.bucket.trim.empty?
      return Error(InvalidDelta(reason: "empty bucket name in delta"))
    end
    if b.bucket == pins_bucket or b.bucket == sync_peers_bucket
      return Error(InvalidDelta(reason: "forbidden internal bucket '#{b.bucket}' in delta"))
    end
    if has_prev_bucket? and b.bucket <= prev_bname
      return Error(InvalidDelta(reason: "unsorted or duplicate bucket '#{b.bucket}' in delta"))
    end
    prev_bname = b.bucket
    has_prev_bucket? = true
    var ops = []
    var prev_k = "".bytes
    var has_prev_k? = false
    for o in b.ops
      k = try Bytes.from_hex(o.key_hex).or_fail(
        InvalidDelta(reason: "invalid key hex '#{o.key_hex}' in bucket '#{b.bucket}'")
      )
      if k.to_hex != o.key_hex
        return Error(InvalidDelta(reason: "non-canonical hex key in bucket '#{b.bucket}'"))
      end
      if has_prev_k? and k <= prev_k
        return Error(
          InvalidDelta(reason: "unsorted or duplicate key '#{o.key_hex}' in bucket '#{b.bucket}'")
        )
      end
      prev_k = k
      has_prev_k? = true
      if o.op == "put"
        v = try Bytes.from_hex(o.value_hex).or_fail(
          InvalidDelta(reason: "invalid value hex in bucket '#{b.bucket}'")
        )
        if v.to_hex != o.value_hex
          return Error(InvalidDelta(reason: "non-canonical hex value in bucket '#{b.bucket}'"))
        end
        ops = ops.append(PutOp(key: k, value: v))
        puts += 1
      else if o.op == "del"
        if not o.value_hex.empty?
          return Error(InvalidDelta(reason: "delete op must carry empty value_hex"))
        end
        ops = ops.append(DelOp(key: k))
        dels += 1
      else
        return Error(InvalidDelta(reason: "unsupported delta op '#{o.op}'"))
      end
      total_ops += 1
    end
    decoded_buckets = decoded_buckets.append((b.bucket, ops))
  end
  if delta.op_count != total_ops
    return Error(InvalidDelta(reason: "op_count #{delta.op_count} != actual #{total_ops}"))
  end
  Ok((decoded_buckets, puts, dels))
end

## Verifies structural canonical ordering, hex integrity, `payload_hash`, and `delta_hash` of `delta`.
fn verify_delta(delta: SyncDelta) : Result(Unit, SyncError)
  _ = try verify_and_decode_delta(delta)
  Ok(Unit)
end

fn check_chain_expectation(
  delta: SyncDelta,
  expected_seq_opt: Option(Int),
  expected_prev_hash_opt: Option(Text)
) : Result(Unit, SyncError)
  exp_seq = expected_seq_opt or delta.seq
  exp_hash = expected_prev_hash_opt or delta.prev_hash
  if delta.seq != exp_seq or delta.prev_hash != exp_hash
    return Error(
      ChainMismatch(
        expected_seq: exp_seq,
        actual_seq: delta.seq,
        expected_prev_hash: exp_hash,
        actual_prev_hash: delta.prev_hash
      )
    )
  end
  Ok(Unit)
end

## Verifies and atomically applies `delta` onto `store` inside one `WriteTx`, enforcing optional
## expected sequence and hash-chain predecessors. Uses `Modb.commit_at_least(tx, delta.target_txid)`
## so replicated audit entries/checkpoints never violate `txid <= store_txid`.
fn apply_delta(
  store: Store,
  delta: SyncDelta,
  expected_seq_opt: Option(Int),
  expected_prev_hash_opt: Option(Text)
) : Result((Store, SyncApplyReport), SyncError)
  try check_chain_expectation(delta, expected_seq_opt, expected_prev_hash_opt)
  (decoded_buckets, puts, dels) = try verify_and_decode_delta(delta)
  before_txid = Modb.txid(store)
  var tx = Modb.begin_write(store)
  for (bname, ops) in decoded_buckets
    for dop in ops
      case dop
        PutOp(key: k, value: v): tx = try wrap_modb(Modb.tx_put(tx, bname, k, v))
        DelOp(key: k): tx = try wrap_modb(Modb.tx_delete(tx, bname, k))
      end
    end
  end
  next_store = try wrap_modb(Modb.commit_at_least(tx, delta.target_txid))
  after_txid = Modb.txid(next_store)
  Ok((
    next_store,
    SyncApplyReport(
      peer_id: delta.peer_id,
      seq: delta.seq,
      puts_applied: puts,
      deletes_applied: dels,
      before_txid: before_txid,
      after_txid: after_txid,
      delta_hash: delta.delta_hash
    )
  ))
end

## Stateful replica apply tracking `replica:<peer_id>` in `_modb_sync_peers`, rejecting sequence
## gaps, forks, and duplicate delta replays in a single atomic transaction.
fn apply_delta_tracked(store: Store, delta: SyncDelta, now: Time) : Result(
  (Store, SyncApplyReport),
  SyncError
)
  pid = try validate_peer_id(delta.peer_id)
  rkey = replica_cursor_key(pid)
  cur_opt = try wrap_table(Table.get(store, peers_table(), rkey))
  (exp_seq, exp_prev_hash, created_at) = case cur_opt
    Some(rec): (rec.acked_seq + 1, rec.acked_hash, rec.created_at)
    None: (1, genesis_hash, now)
  end
  try check_chain_expectation(delta, Some(exp_seq), Some(exp_prev_hash))
  (decoded_buckets, puts, dels) = try verify_and_decode_delta(delta)
  before_txid = Modb.txid(store)
  var tx = Modb.begin_write(store)
  for (bname, ops) in decoded_buckets
    for dop in ops
      case dop
        PutOp(key: k, value: v): tx = try wrap_modb(Modb.tx_put(tx, bname, k, v))
        DelOp(key: k): tx = try wrap_modb(Modb.tx_delete(tx, bname, k))
      end
    end
  end
  next_cursor = SyncPeer(
    peer_id: pid,
    include_internal?: delta.include_internal?,
    from_empty?: delta.from_txid == 0,
    acked_seq: delta.seq,
    acked_txid: delta.target_txid,
    acked_hash: delta.delta_hash,
    pending_seq: None,
    pending_txid: None,
    pending_hash: None,
    created_at: created_at,
    updated_at: now
  )
  tx_cur = try wrap_table(Table.put(tx, peers_table(), rkey, next_cursor))
  next_store = try wrap_modb(Modb.commit_at_least(tx_cur, delta.target_txid))
  Ok((
    next_store,
    SyncApplyReport(
      peer_id: pid,
      seq: delta.seq,
      puts_applied: puts,
      deletes_applied: dels,
      before_txid: before_txid,
      after_txid: Modb.txid(next_store),
      delta_hash: delta.delta_hash
    )
  ))
end

fn envelope_aad_bytes(fmt: Int, kind: Text, alg: Text, key_id: Text, aad: Text) : Bytes
  "MODB-SEALED-V1|#{fmt}|#{kind}|#{alg}|#{key_id}|#{aad}".bytes
end

fn validate_key_32(key: Bytes) : Result(Bytes, SyncError)
  if key.size != 32
    return Error(InvalidKeyLength(expected: 32, got: key.size))
  end
  Ok(key)
end

## Encrypts and authenticates raw `plaintext` bytes using AES-256-GCM under a 32-byte `key` with
## a fresh 12-byte CSPRNG nonce and domain-separated envelope metadata AAD.
fn seal_bytes(
  srng: SecureRandom,
  key: Bytes,
  kind: Text,
  key_id: Text,
  aad: Text,
  plaintext: Bytes,
  now: Time
) : Result(SealedEnvelope, SyncError)
  k = try validate_key_32(key)
  clean_kind = kind.trim
  if clean_kind.empty?
    return Error(InvalidEnvelope(reason: "envelope kind cannot be empty"))
  end
  alg = "AES-256-GCM"
  nonce = srng.bytes(12)
  aad_bytes = envelope_aad_bytes(sealed_format_version, clean_kind, alg, key_id, aad)
  ct = case Crypto.seal(k, nonce, plaintext, aad_bytes)
    Ok(b): b
    Error(Crypto.InvalidKeyLength(expected: e, got: g)): return Error(
      InvalidKeyLength(expected: e, got: g)
    )
    Error(_): return Error(DecryptionFailed)
  end
  Ok(
    SealedEnvelope(
      format_version: sealed_format_version,
      kind: clean_kind,
      alg: alg,
      key_id: key_id,
      aad: aad,
      nonce_b64: nonce.to_base64url,
      ciphertext_b64: ct.to_base64url,
      sealed_at: now
    )
  )
end

## Verifies and decrypts `env` using `key`, `expected_kind`, and `expected_aad`.
fn open_bytes(key: Bytes, expected_kind: Text, expected_aad: Text, env: SealedEnvelope) : Result(
  Bytes,
  SyncError
)
  k = try validate_key_32(key)
  if env.format_version != sealed_format_version
    return Error(
      InvalidEnvelope(reason: "unsupported envelope format_version=#{env.format_version}")
    )
  end
  if env.alg != "AES-256-GCM"
    return Error(InvalidEnvelope(reason: "unsupported cipher '#{env.alg}'"))
  end
  if env.kind != expected_kind
    return Error(
      InvalidEnvelope(reason: "envelope kind '#{env.kind}' != expected '#{expected_kind}'")
    )
  end
  if env.aad != expected_aad
    return Error(DecryptionFailed)
  end
  nonce = try Bytes.from_base64url(env.nonce_b64).or_fail(
    InvalidEnvelope(reason: "corrupt envelope nonce_b64")
  )
  ct = try Bytes.from_base64url(env.ciphertext_b64).or_fail(
    InvalidEnvelope(reason: "corrupt envelope ciphertext_b64")
  )
  aad_bytes = envelope_aad_bytes(env.format_version, env.kind, env.alg, env.key_id, expected_aad)
  case Crypto.open(k, nonce, ct, aad_bytes)
    Ok(pt): Ok(pt)
    Error(Crypto.InvalidKeyLength(expected: e, got: g)): Error(
      InvalidKeyLength(expected: e, got: g)
    )
    Error(_): Error(DecryptionFailed)
  end
end

## Encrypts a `SyncDelta` into a `SealedEnvelope(kind: "delta")` using AES-256-GCM.
fn seal_delta(srng: SecureRandom, key: Bytes, key_id: Text, aad: Text, delta: SyncDelta, now: Time) : Result(
  SealedEnvelope,
  SyncError
)
  _ = try verify_delta(delta)
  raw = encode_delta_json(delta).bytes
  seal_bytes(srng, key, "delta", key_id, aad, raw, now)
end

## Decrypts, decodes, and hash-verifies a `SyncDelta` from `env`.
fn open_delta(key: Bytes, expected_aad: Text, env: SealedEnvelope) : Result(SyncDelta, SyncError)
  pt = try open_bytes(key, "delta", expected_aad, env)
  raw = try pt.decode_utf8.or_fail(
    InvalidEnvelope(reason: "decrypted delta payload is not valid UTF-8")
  )
  delta = case Json.decode[SyncDelta](raw)
    Ok(d): d
    Error(je): return Error(InvalidDelta(reason: "malformed decrypted delta JSON: #{je}"))
  end
  _ = try verify_delta(delta)
  Ok(delta)
end

## Encrypts a `PortableSnapshot` into a `SealedEnvelope(kind: "snapshot")` using AES-256-GCM.
fn seal_snapshot(
  srng: SecureRandom,
  key: Bytes,
  key_id: Text,
  aad: Text,
  snap: Export.PortableSnapshot,
  now: Time
) : Result(SealedEnvelope, SyncError)
  _ = try wrap_export(Export.verify_snapshot(snap))
  raw = Export.encode_snapshot_json(snap).bytes
  seal_bytes(srng, key, "snapshot", key_id, aad, raw, now)
end

## Decrypts, decodes, and SHA-256-verifies a `PortableSnapshot` from `env`.
fn open_snapshot(key: Bytes, expected_aad: Text, env: SealedEnvelope) : Result(
  Export.PortableSnapshot,
  SyncError
)
  pt = try open_bytes(key, "snapshot", expected_aad, env)
  raw = try pt.decode_utf8.or_fail(
    InvalidEnvelope(reason: "decrypted snapshot payload is not valid UTF-8")
  )
  snap = case Json.decode[Export.PortableSnapshot](raw)
    Ok(s): s
    Error(je): return Error(InvalidEnvelope(reason: "malformed decrypted snapshot JSON: #{je}"))
  end
  _ = try wrap_export(Export.verify_snapshot(snap))
  Ok(snap)
end

fn decode_key_32_text(raw: Text) : Result(Bytes, SyncError)
  t = raw.trim
  if t.byte_count == 64
    case Bytes.from_hex(t)
      Some(kb) if kb.size == 32: return Ok(kb)
      Some(_) | None: Unit
    end
  end
  if t.starts_with?("b64:")
    b64 = t.drop_prefix("b64:") or ""
    case Bytes.from_base64url(b64)
      Some(kb) if kb.size == 32: return Ok(kb)
      Some(_) | None: Unit
    end
  end
  validate_key_32(t.bytes)
end

## Parses a backup keyring in JSON (`{"k1":"<64-hex>"}`) or `k1=<64-hex>,k2=<64-hex>` form.
## Supports key rotation across generations/deltas without weakening single-key validation.
fn parse_keyring_text(raw: Text) : Result(Map(Text, Bytes), SyncError)
  t = raw.trim
  if t.empty?
    return Error(InvalidEnvelope(reason: "empty backup keyring"))
  end
  var out = {}
  if t.starts_with?("{")
    entries = case Json.decode[Map(Text, Text)](t.bytes)
      Ok(m): m
      Error(_): return Error(InvalidEnvelope(reason: "malformed JSON backup keyring"))
    end
    for (kid, sec) in entries
      clean_id = kid.trim
      if clean_id.empty?
        return Error(InvalidEnvelope(reason: "keyring contains empty key_id"))
      end
      kb = try decode_key_32_text(sec)
      out = out.set(clean_id, kb)
    end
  else
    normalized = t.replace("\r", "\n").replace(";", "\n").replace(",", "\n")
    for part in normalized.split("\n")
      line = part.trim
      if not line.empty?
        pieces = line.split("=")
        if pieces.size < 2
          return Error(InvalidEnvelope(reason: "keyring entry must have key_id=key format"))
        end
        clean_id = (pieces.first or "").trim
        if clean_id.empty?
          return Error(InvalidEnvelope(reason: "keyring entry has empty key_id"))
        end
        sec = pieces.drop(1).join("=")
        kb = try decode_key_32_text(sec)
        out = out.set(clean_id, kb)
      end
    end
  end
  if out.empty?
    return Error(InvalidEnvelope(reason: "empty backup keyring"))
  end
  Ok(out)
end

## Decrypts `env` by selecting the key matching `env.key_id` from `keys`.
fn open_bytes_with_keyring(
  keys: Map(Text, Bytes),
  expected_kind: Text,
  expected_aad: Text,
  env: SealedEnvelope
) : Result(Bytes, SyncError)
  k = try keys.get(env.key_id).or_fail(KeyNotFound(key_id: env.key_id))
  open_bytes(k, expected_kind, expected_aad, env)
end

## Decrypts, decodes, and hash-verifies a `SyncDelta` using `keys[env.key_id]`.
fn open_delta_with_keyring(keys: Map(Text, Bytes), expected_aad: Text, env: SealedEnvelope) : Result(
  SyncDelta,
  SyncError
)
  pt = try open_bytes_with_keyring(keys, "delta", expected_aad, env)
  raw = try pt.decode_utf8.or_fail(
    InvalidEnvelope(reason: "decrypted delta payload is not valid UTF-8")
  )
  delta = case Json.decode[SyncDelta](raw)
    Ok(d): d
    Error(je): return Error(InvalidDelta(reason: "malformed decrypted delta JSON: #{je}"))
  end
  _ = try verify_delta(delta)
  Ok(delta)
end

## Decrypts, decodes, and SHA-256-verifies a `PortableSnapshot` using `keys[env.key_id]`.
fn open_snapshot_with_keyring(keys: Map(Text, Bytes), expected_aad: Text, env: SealedEnvelope) : Result(
  Export.PortableSnapshot,
  SyncError
)
  pt = try open_bytes_with_keyring(keys, "snapshot", expected_aad, env)
  raw = try pt.decode_utf8.or_fail(
    InvalidEnvelope(reason: "decrypted snapshot payload is not valid UTF-8")
  )
  snap = case Json.decode[Export.PortableSnapshot](raw)
    Ok(s): s
    Error(je): return Error(InvalidEnvelope(reason: "malformed decrypted snapshot JSON: #{je}"))
  end
  _ = try wrap_export(Export.verify_snapshot(snap))
  Ok(snap)
end

## Builds and verifies a fresh MoDB file at `dst_path` from `base_snap` followed by an ordered,
## hash-chained list of `deltas` (`seq = 1..N`, `prev_hash` starting at `genesis_hash`).
## Uses temporary staging + `Modb.verify` + atomic rename, and cleans up on any error.
fn restore_chain(
  files: Files,
  dst_path: Text,
  base_snap: Export.PortableSnapshot,
  deltas: List(SyncDelta)
) : Result(RestoreChainReport, SyncError)
  if files.exists?(dst_path)
    return Error(TargetExists(path: dst_path))
  end
  tmp_path = "#{dst_path}.sync-restore.tmp"
  _rm0 = files.remove(tmp_path)
  var store = case wrap_export(Export.import_file(files, tmp_path, base_snap))
    Ok(s): s
    Error(e):
      _rm1 = files.remove(tmp_path)
      return Error(e)
  end
  var expected_seq = 1
  var expected_hash = genesis_hash
  var total_puts = 0
  var total_dels = 0
  for delta in deltas
    case apply_delta(store, delta, Some(expected_seq), Some(expected_hash))
      Ok((next_st, rep)):
        store = next_st
        expected_seq += 1
        expected_hash = delta.delta_hash
        total_puts += rep.puts_applied
        total_dels += rep.deletes_applied
      Error(e):
        _rm2 = files.remove(tmp_path)
        return Error(e)
    end
  end
  case wrap_modb(Modb.verify(store))
    Ok(_): Unit
    Error(e):
      _rm3 = files.remove(tmp_path)
      return Error(e)
  end
  pages = Modb.page_count(store)
  free_pages = Modb.free_page_count(store)
  final_tx = Modb.txid(store)
  case wrap_io(files.rename(tmp_path, dst_path)).map_error(fn(e) StorageFailure(e) end)
    Ok(Unit): Unit
    Error(e):
      _rm4 = files.remove(tmp_path)
      return Error(e)
  end
  Ok(
    RestoreChainReport(
      dst_path: dst_path,
      base_txid: base_snap.source_txid,
      final_txid: final_tx,
      deltas_applied: deltas.size,
      puts_applied: total_puts,
      deletes_applied: total_dels,
      page_count: pages,
      free_page_count: free_pages,
      last_delta_hash: expected_hash
    )
  )
end

## Decrypts, verifies, and restores a database from AES-256-GCM sealed off-host backups.
fn restore_sealed_chain(
  files: Files,
  dst_path: Text,
  sealed_base: SealedEnvelope,
  sealed_deltas: List(SealedEnvelope),
  key: Bytes,
  expected_aad: Text
) : Result(RestoreChainReport, SyncError)
  base_snap = try open_snapshot(key, expected_aad, sealed_base)
  var deltas = []
  for env in sealed_deltas
    d = try open_delta(key, expected_aad, env)
    deltas = deltas.append(d)
  end
  restore_chain(files, dst_path, base_snap, deltas)
end

## Decrypts, verifies, and restores a database across key-rotated envelopes selected by `env.key_id`.
fn restore_sealed_chain_with_keyring(
  files: Files,
  dst_path: Text,
  sealed_base: SealedEnvelope,
  sealed_deltas: List(SealedEnvelope),
  keys: Map(Text, Bytes),
  expected_aad: Text
) : Result(RestoreChainReport, SyncError)
  base_snap = try open_snapshot_with_keyring(keys, expected_aad, sealed_base)
  var deltas = []
  for env in sealed_deltas
    d = try open_delta_with_keyring(keys, expected_aad, env)
    deltas = deltas.append(d)
  end
  restore_chain(files, dst_path, base_snap, deltas)
end

## Lock-coordinated wrappers for multi-worker `mo serve` and CLI use.
fn init_peer_locked(
  files: Files,
  path: Text,
  peer_id: Text,
  include_internal?: Bool,
  from_empty?: Bool,
  now: Time
) : Result(SyncPeer, SyncError)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(e) StorageFailure(e) end,
    fn(st)
      (_next, peer) = try init_peer(st, peer_id, include_internal?, from_empty?, now)
      Ok(peer)
    end
  )
end

fn get_peer_locked(rf: ReadFiles, path: Text, peer_id: Text) : Result(Option(SyncPeer), SyncError)
  Modb.with_shared_lock(rf, path, fn(e) StorageFailure(e) end, fn(st) get_peer(st, peer_id) end)
end

fn list_peers_locked(rf: ReadFiles, path: Text) : Result(List(SyncPeer), SyncError)
  Modb.with_shared_lock(rf, path, fn(e) StorageFailure(e) end, fn(st) list_peers(st) end)
end

fn export_peer_base_snapshot_locked(rf: ReadFiles, path: Text, peer_id: Text, now: Time) : Result(
  Export.PortableSnapshot,
  SyncError
)
  Modb.with_shared_lock(
    rf,
    path,
    fn(e) StorageFailure(e) end,
    fn(st) export_peer_base_snapshot(st, peer_id, now) end
  )
end

fn export_delta_locked(files: Files, path: Text, peer_id: Text, now: Time) : Result(
  SyncDelta,
  SyncError
)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(e) StorageFailure(e) end,
    fn(st)
      (_next, delta) = try export_delta(st, peer_id, now)
      Ok(delta)
    end
  )
end

fn ack_peer_locked(files: Files, path: Text, peer_id: Text, seq: Int, delta_hash: Text, now: Time) : Result(
  SyncPeer,
  SyncError
)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(e) StorageFailure(e) end,
    fn(st)
      (_next, peer) = try ack_peer(st, peer_id, seq, delta_hash, now)
      Ok(peer)
    end
  )
end

fn apply_delta_locked(
  files: Files,
  path: Text,
  delta: SyncDelta,
  expected_seq_opt: Option(Int),
  expected_prev_hash_opt: Option(Text)
) : Result(SyncApplyReport, SyncError)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(e) StorageFailure(e) end,
    fn(st)
      (_next, rep) = try apply_delta(st, delta, expected_seq_opt, expected_prev_hash_opt)
      Ok(rep)
    end
  )
end

fn apply_delta_tracked_locked(files: Files, path: Text, delta: SyncDelta, now: Time) : Result(
  SyncApplyReport,
  SyncError
)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(e) StorageFailure(e) end,
    fn(st)
      (_next, rep) = try apply_delta_tracked(st, delta, now)
      Ok(rep)
    end
  )
end

fn remove_peer_locked(files: Files, path: Text, peer_id: Text) : Result(Unit, SyncError)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(e) StorageFailure(e) end,
    fn(st)
      _next = try remove_peer(st, peer_id)
      Ok(Unit)
    end
  )
end

## Reads a tracked replica pull cursor (`replica:<peer_id>`) from `store`.
fn get_replica_cursor(store: Store, peer_id: Text) : Result(Option(SyncPeer), SyncError)
  pid = try validate_peer_id(peer_id)
  wrap_table(Table.get(store, peers_table(), replica_cursor_key(pid)))
end

## Lock-coordinated read of `replica:<peer_id>` cursor on `path`.
fn get_replica_cursor_locked(rf: ReadFiles, path: Text, peer_id: Text) : Result(
  Option(SyncPeer),
  SyncError
)
  Modb.with_shared_lock(
    rf,
    path,
    fn(e) StorageFailure(e) end,
    fn(st) get_replica_cursor(st, peer_id) end
  )
end

## Seeds `replica:<peer_id>` cursor at `(acked_seq, acked_txid, acked_hash)` after bootstrapping
## a replica from a mid-stream snapshot whose primary peer already has `acked_seq > 0`.
fn seed_replica_cursor_locked(
  files: Files,
  path: Text,
  peer_id: Text,
  acked_seq: Int,
  acked_txid: Int,
  acked_hash: Text,
  include_internal?: Bool,
  from_empty?: Bool,
  now: Time
) : Result(SyncPeer, SyncError)
  pid = try validate_peer_id(peer_id)
  if acked_seq <= 0
    return Error(InvalidDelta(reason: "seed_replica_cursor requires acked_seq > 0"))
  end
  clean_hash = acked_hash.trim
  if clean_hash.empty?
    return Error(InvalidDelta(reason: "seed_replica_cursor requires non-empty acked_hash"))
  end
  rkey = replica_cursor_key(pid)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(e) StorageFailure(e) end,
    fn(st)
      if (try wrap_table(Table.get(st, peers_table(), rkey))) is Some(_)
        return Error(PeerAlreadyExists(peer_id: rkey))
      end
      rec = SyncPeer(
        peer_id: pid,
        include_internal?: include_internal?,
        from_empty?: from_empty?,
        acked_seq: acked_seq,
        acked_txid: acked_txid,
        acked_hash: clean_hash,
        pending_seq: None,
        pending_txid: None,
        pending_hash: None,
        created_at: now,
        updated_at: now
      )
      tx = Modb.begin_write(st)
      tx1 = try wrap_table(Table.put(tx, peers_table(), rkey, rec))
      target_tx = if acked_txid > Modb.txid(st): acked_txid else: Modb.txid(st)
      _committed = try wrap_modb(Modb.commit_at_least(tx1, target_tx))
      Ok(rec)
    end
  )
end

test "Modb.Sync unit tests: peer pin lifecycle, JSON roundtrip, AEAD tamper checks"
  files = Files.in_memory({})
  now = Time.parse("2026-11-26T22:00:00Z") or stop "time"
  srng = SecureRandom.seeded(99)
  key = Crypto.sha256("test-sync-master-key".bytes)

  assert Modb.open(files, "primary.modb") is Ok(s0)
  tx0 = Modb.begin_write(s0)
  assert Modb.tx_put(tx0, "items", "k1".bytes, "v1".bytes) is Ok(tx0b)
  assert Modb.commit(tx0b) is Ok(s1)

  ## Init peer and export base snapshot
  assert init_peer(s1, "replica-1", false, false, now) is Ok((s2, p0))
  assert p0.acked_seq == 0
  assert p0.acked_hash == genesis_hash
  assert export_peer_base_snapshot(s2, "replica-1", now) is Ok(snap)
  assert snap.bucket_count == 1
  assert snap.entry_count == 1

  ## Write k2, export delta 1, verify fast JSON roundtrip
  tx1 = Modb.begin_write(s2)
  assert Modb.tx_put(tx1, "items", "k2".bytes, "v2".bytes) is Ok(tx1b)
  assert Modb.tx_put(tx1b, "_modb_audit", "secret".bytes, "ignored".bytes) is Ok(tx1c)
  assert Modb.commit(tx1c) is Ok(s3)

  assert export_delta(s3, "replica-1", now) is Ok((s4, d1))
  assert d1.seq == 1
  assert d1.prev_hash == genesis_hash
  assert d1.bucket_count == 1
  assert d1.op_count == 1
  assert Json.decode[SyncDelta](encode_delta_json(d1)) is Ok(d1_dec)
  assert d1_dec == d1

  ## Ack with wrong hash fails cleanly, then valid ack succeeds
  assert ack_peer(s4, "replica-1", 1, "badhash", now) is Error(AckMismatch(reason: _))
  assert ack_peer(s4, "replica-1", 1, d1.delta_hash, now) is Ok((s5, p1))
  assert p1.acked_seq == 1
  assert p1.acked_hash == d1.delta_hash
  assert p1.pending_seq == None
  assert Modb.get_pin(s5, "sync_pending:replica-1") is Ok(None)

  ## Seal & open snapshot and delta; verify wrong AAD & bad key length fail
  assert seal_snapshot(srng, key, "k1", "modb:prod", snap, now) is Ok(env_snap)
  assert seal_delta(srng, key, "k1", "modb:prod", d1, now) is Ok(env_delta)
  assert not Json.encode(env_delta.to_json).contains?(d1.delta_hash)
  assert open_snapshot(key, "modb:prod", env_snap) is Ok(snap_dec)
  assert snap_dec == snap
  assert open_delta(key, "modb:prod", env_delta) is Ok(d1_env_dec)
  assert d1_env_dec == d1
  assert open_delta(key, "modb:staging", env_delta) is Error(DecryptionFailed)
  assert open_delta("short".bytes, "modb:prod", env_delta) is
    Error(InvalidKeyLength(expected: 32, got: 5))
  assert open_snapshot(key, "modb:prod", env_delta) is Error(InvalidEnvelope(reason: _))

  ## Keyring rotation test
  assert parse_keyring_text("k1=#{key.to_hex}") is Ok(kr_single)
  assert open_snapshot_with_keyring(kr_single, "modb:prod", env_snap) is Ok(snap_kr)
  assert snap_kr == snap
  assert open_snapshot_with_keyring({}, "modb:prod", env_snap) is Error(KeyNotFound(key_id: "k1"))

  ## Restore chain builds verified replica
  assert restore_chain(files, "restored.modb", snap, [d1]) is Ok(rep)
  assert rep.deltas_applied == 1
  assert rep.puts_applied == 1
  assert Modb.open_read_only(files.read_only, "restored.modb") is Ok(restored)
  assert Modb.get(restored, "items", "k1".bytes) == Ok(Some("v1".bytes))
  assert Modb.get(restored, "items", "k2".bytes) == Ok(Some("v2".bytes))
  assert Modb.verify(s5) is Ok(ver)
  assert ver.txid == Modb.txid(s5)

  ## Remove peer unpins both pins cleanly
  assert remove_peer(s5, "replica-1") is Ok(s6)
  assert get_peer(s6, "replica-1") is Ok(None)
  assert Modb.get_pin(s6, "sync:replica-1") is Ok(None)
end
