## MoDB Portable Export & Import (`design.md` §4 & §7 Q6):
## Layout-independent canonical JSON snapshot format with per-bucket + top-level SHA-256
## integrity verification, enabling format evolution, compaction, and cross-file migration
## with zero dependency on page size, page IDs, freelist layout, or pinned page pointers.
module Modb.Export
expose export_format_version,
ExportError(..),
PortableEntry(..),
PortableBucket(..),
PortableSnapshot(..),
to_text,
compute_snapshot_digest,
export_at_root,
export_store,
export_db,
export_locked,
verify_snapshot,
decode_snapshot_buckets,
import_disk,
import_file,
import_db
use Crypto
use Json
use Modb{Store, pins_bucket}
use Modb.Errors{ModbError, wrap_io}
use Modb.Ledger{Db, LedgerError, Schema, SchemaState, meta_bucket}
use Modb.Pager{BlockStore, disk_page_count, from_file}
use Modb.Table

## Current canonical portable snapshot format version.
export_format_version = 1

## Every failure returned by `Modb.Export` operations.
enum ExportError
  StorageFailure(ModbError)
  LedgerFailure(LedgerError)
  UnsupportedFormat(found: Int, supported: Int)
  InvalidEncoding(bucket: Text, detail: Text)
  ChecksumMismatch(expected: Text, actual: Text)
  TargetNotEmpty(path: Text)
end

## Formats an `ExportError` as a human-readable message.
fn to_text(err: ExportError) : Text
  case err
    StorageFailure(e): e.to_text
    LedgerFailure(e): e.to_text
    UnsupportedFormat(found: f, supported: s): "unsupported export format v#{f} (supported v#{s})"
    InvalidEncoding(bucket: b, detail: d): "invalid portable encoding in bucket '#{b}': #{d}"
    ChecksumMismatch(expected: exp, actual: act): "portable snapshot checksum mismatch: expected #{exp}, got #{act}"
    TargetNotEmpty(path: p): "import target '#{p}' already exists or is non-empty"
  end
end

## One lossless hex-encoded `(key, value)` entry inside a portable bucket.
struct PortableEntry
  key_hex: Text
  value_hex: Text
end

## One logically exported bucket with entries in deterministic ascending key order.
struct PortableBucket
  name: Text
  entries: List(PortableEntry)
end

## Complete layout-independent portable database snapshot protected by a canonical SHA-256 digest.
struct PortableSnapshot
  format_version: Int
  source_txid: Int
  schema_version: Int
  include_internal: Bool
  exported_at: Time
  bucket_count: Int
  entry_count: Int
  buckets: List(PortableBucket)
  sha256: Text
end

fn len_prefixed(b: Bytes) : Bytes
  Bytes.join([Bytes.from_u32_be(b.size), b])
end

fn hash_bucket(bucket: PortableBucket) : Bytes
  var parts = [
    "MODB-EXPORT-BUCKET-V1".bytes,
    len_prefixed(bucket.name.bytes),
    Bytes.from_i64_be(bucket.entries.size)
  ]
  for e in bucket.entries
    parts = parts.append(len_prefixed(e.key_hex.bytes)).append(len_prefixed(e.value_hex.bytes))
  end
  Crypto.sha256(Bytes.join(parts))
end

## Computes the canonical SHA-256 digest covering every field, bucket, and entry of `snap`
## (excluding `snap.sha256` itself).
fn compute_snapshot_digest(
  format_version: Int,
  source_txid: Int,
  schema_version: Int,
  include_internal: Bool,
  exported_at: Time,
  buckets: List(PortableBucket)
) : Text
  flag_byte = if include_internal: Bytes.from_i64_be(1) else: Bytes.from_i64_be(0)
  var parts = [
    "MODB-EXPORT-V1".bytes,
    Bytes.from_i64_be(format_version),
    Bytes.from_i64_be(source_txid),
    Bytes.from_i64_be(schema_version),
    flag_byte,
    len_prefixed(Json.encode(exported_at).bytes),
    Bytes.from_i64_be(buckets.size)
  ]
  for b in buckets
    parts = parts.append(len_prefixed(b.name.bytes)).append(hash_bucket(b))
  end
  Crypto.sha256(Bytes.join(parts)).to_hex
end

fn read_schema_version_at_root(store: Store, cat_root: Int) : Result(Int, ExportError)
  raw_opt = try Modb.get_at_root(store, cat_root, meta_bucket, "state".bytes).map_error(fn(e)
    StorageFailure(e)
  end)
  case raw_opt
    None: Ok(0)
    Some(raw):
      case Json.decode[SchemaState](raw)
        Ok(st): Ok(st.version)
        Error(_): Ok(0)
      end
  end
end

## Exports a layout-independent `PortableSnapshot` from an explicit committed or pinned `cat_root`.
## Layout-dependent `_modb_pins` is always excluded; other `_modb_*` internal buckets are included
## iff `include_internal` is `true`.
fn export_at_root(store: Store, cat_root: Int, source_txid: Int, include_internal: Bool, now: Time) : Result(
  PortableSnapshot,
  ExportError
)
  all_names = try Modb.buckets_at_root(store, cat_root).map_error(fn(e) StorageFailure(e) end)
  sc_ver = try read_schema_version_at_root(store, cat_root)
  var exported_buckets = []
  var total_entries = 0
  for bname in all_names
    skip? = bname == pins_bucket or (not include_internal and bname.starts_with?("_modb_"))
    if not skip?
      rows = try Modb.scan_at_root(store, cat_root, bname, None, None, 0).map_error(fn(e)
        StorageFailure(e)
      end)
      var entries = []
      for (k, v) in rows
        entries = entries.append(PortableEntry(key_hex: k.to_hex, value_hex: v.to_hex))
      end
      total_entries += entries.size
      exported_buckets = exported_buckets.append(PortableBucket(name: bname, entries: entries))
    end
  end
  digest = compute_snapshot_digest(
    export_format_version,
    source_txid,
    sc_ver,
    include_internal,
    now,
    exported_buckets
  )
  Ok(
    PortableSnapshot(
      format_version: export_format_version,
      source_txid: source_txid,
      schema_version: sc_ver,
      include_internal: include_internal,
      exported_at: now,
      bucket_count: exported_buckets.size,
      entry_count: total_entries,
      buckets: exported_buckets,
      sha256: digest
    )
  )
end

## Exports the current committed state of `store` into a layout-independent `PortableSnapshot`.
fn export_store(store: Store, include_internal: Bool, now: Time) : Result(
  PortableSnapshot,
  ExportError
)
  export_at_root(store, Modb.catalog_root(store), Modb.txid(store), include_internal, now)
end

## Exports the current committed state of ledger-backed `db`.
fn export_db(db: Db, include_internal: Bool, now: Time) : Result(PortableSnapshot, ExportError)
  export_store(Ledger.store(db), include_internal, now)
end

## Lock-coordinated read-only export over `ReadFiles` + advisory shared `flock`.
fn export_locked(rf: ReadFiles, path: Text, sc: Schema, include_internal: Bool, now: Time) : Result(
  PortableSnapshot,
  ExportError
)
  Ledger.read_locked(
    rf,
    path,
    sc,
    fn(le) LedgerFailure(le) end,
    fn(db) export_db(db, include_internal, now) end
  )
end

## Validates a `PortableSnapshot`'s format version, SHA-256 digest, bucket/entry counts,
## bucket restrictions, and strict hex encoding, returning decoded `(bucket, rows)` pairs.
fn decode_snapshot_buckets(snap: PortableSnapshot) : Result(
  List((Text, List((Bytes, Bytes)))),
  ExportError
)
  if snap.format_version != export_format_version
    return Error(UnsupportedFormat(found: snap.format_version, supported: export_format_version))
  end
  expected = compute_snapshot_digest(
    snap.format_version,
    snap.source_txid,
    snap.schema_version,
    snap.include_internal,
    snap.exported_at,
    snap.buckets
  )
  if snap.sha256 != expected
    return Error(ChecksumMismatch(expected: expected, actual: snap.sha256))
  end
  if snap.bucket_count != snap.buckets.size
    return Error(
      InvalidEncoding(
        bucket: "*",
        detail: "bucket_count #{snap.bucket_count} != actual #{snap.buckets.size}"
      )
    )
  end
  var decoded_buckets = []
  var total_entries = 0
  var seen_buckets = Set.empty
  for b in snap.buckets
    if b.name.trim.empty?
      return Error(InvalidEncoding(bucket: b.name, detail: "empty bucket name"))
    end
    if b.name == pins_bucket
      return Error(
        InvalidEncoding(bucket: b.name, detail: "layout-dependent #{pins_bucket} is forbidden")
      )
    end
    if seen_buckets.has?(b.name)
      return Error(InvalidEncoding(bucket: b.name, detail: "duplicate bucket in snapshot"))
    end
    seen_buckets = seen_buckets.add(b.name)
    var rows = []
    for e in b.entries
      kb = try Bytes.from_hex(e.key_hex).or_fail(
        InvalidEncoding(bucket: b.name, detail: "invalid key hex '#{e.key_hex}'")
      )
      vb = try Bytes.from_hex(e.value_hex).or_fail(
        InvalidEncoding(bucket: b.name, detail: "invalid value hex")
      )
      rows = rows.append((kb, vb))
    end
    total_entries += rows.size
    decoded_buckets = decoded_buckets.append((b.name, rows))
  end
  if snap.entry_count != total_entries
    return Error(
      InvalidEncoding(
        bucket: "*",
        detail: "entry_count #{snap.entry_count} != actual #{total_entries}"
      )
    )
  end
  Ok(decoded_buckets)
end

## Verifies a `PortableSnapshot` without importing it.
fn verify_snapshot(snap: PortableSnapshot) : Result(Unit, ExportError)
  _ = try decode_snapshot_buckets(snap)
  Ok(Unit)
end

## Imports a verified `PortableSnapshot` into an empty `BlockStore`, producing a freshly compacted
## B+Tree store that passes full `Modb.verify`.
fn import_disk(disk: BlockStore, snap: PortableSnapshot) : Result(Store, ExportError)
  existing = try disk_page_count(disk).map_error(fn(e) StorageFailure(e) end)
  if existing != 0
    return Error(TargetNotEmpty(path: "<blockstore>"))
  end
  decoded = try decode_snapshot_buckets(snap)
  store = try Modb.build_from_buckets(disk, snap.source_txid, decoded).map_error(fn(e)
    StorageFailure(e)
  end)
  _ = try Modb.verify(store).map_error(fn(e) StorageFailure(e) end)
  Ok(store)
end

## Imports a verified `PortableSnapshot` into a brand-new file at `path` (refuses to overwrite).
fn import_file(files: Files, path: Text, snap: PortableSnapshot) : Result(Store, ExportError)
  if files.exists?(path)
    return Error(TargetNotEmpty(path: path))
  end
  decoded = try decode_snapshot_buckets(snap)
  fh = try wrap_io(files.open(path)).map_error(fn(e) StorageFailure(e) end)
  store = try Modb.build_from_buckets(from_file(fh), snap.source_txid, decoded).map_error(fn(e)
    StorageFailure(e)
  end)
  _ = try Modb.verify(store).map_error(fn(e) StorageFailure(e) end)
  Ok(store)
end

## Imports a verified `PortableSnapshot` into a brand-new ledger-backed database file at `path`,
## opens it with `sc`, and runs full `Ledger.verify_all` (storage + audit hash chain + invariants).
fn import_db(files: Files, path: Text, sc: Schema, snap: PortableSnapshot, now: Time) : Result(
  Db,
  ExportError
)
  _ = try import_file(files, path, snap)
  db = try Ledger.open(files, path, sc, now).map_error(fn(le) LedgerFailure(le) end)
  _ = try Ledger.verify_all(db).map_error(fn(le) LedgerFailure(le) end)
  Ok(db)
end

struct NoteRow
  body: Text
end

test "Modb.Export unit: portable round-trip, compaction, tamper detection, and pinned-root export"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T12:00:00Z") or stop "t0"
  notes = Table.int_key[NoteRow]("notes")
  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "seed note 1", fn(tx) Table.put(tx, notes, 1, NoteRow(body: "hello")) end)
  )

  assert Ledger.open(files, "src.modb", sc, t0) is Ok(db0)
  meta = Ledger.WriteMeta(principal: "admin:ada", action: "put_note", reason: "init", at: t0)
  var db = db0
  for i in 2..25
    assert Ledger.write(
      db,
      meta,
      "add #{i}",
      i.to_json,
      fn(tx) Table.put(tx, notes, i, NoteRow(body: "note-#{i}")) end
    ) is
      Ok(next)
    db = next
  end

  ## Pin historical state before deleting notes 10..20
  assert Modb.pin_root(Ledger.store(db), "hist-pin") is Ok((s_pinned, pin))
  db = Ledger.update_store(db, s_pinned)

  for i in 10..20
    assert Ledger.write(db, meta, "del #{i}", i.to_json, fn(tx) Table.delete(tx, notes, i) end) is
      Ok(next)
    db = next
  end

  ## Export current full DB (includes audit ledger, excludes layout-dependent _modb_pins)
  assert export_db(db, true, t0) is Ok(snap)
  assert snap.format_version == 1
  assert snap.schema_version == 1
  assert snap.source_txid == Ledger.txid(db)
  for b in snap.buckets
    assert b.name != pins_bucket
  end

  ## JSON round-trip + tamper detection
  encoded = Json.encode(snap)
  assert Json.decode_strict[PortableSnapshot](encoded) == Ok(snap)
  var tampered = snap
  tampered.source_txid += 1
  assert verify_snapshot(tampered) is Error(ChecksumMismatch(expected: _, actual: _))

  ## Import into brand-new compacted file + verify full audit chain & zero fragmentation
  assert import_db(files, "dst.modb", sc, snap, t0) is Ok(db_imp)
  assert Ledger.txid(db_imp) == Ledger.txid(db)
  assert Ledger.audit_count(db_imp) == Ledger.audit_count(db)
  assert Modb.free_page_count(Ledger.store(db_imp)) == 0
  assert Modb.page_count(Ledger.store(db_imp)) <= Modb.page_count(Ledger.store(db))
  assert Table.all(Ledger.store(db_imp), notes) == Table.all(Ledger.store(db), notes)
  assert Ledger.verify_all(db_imp) is Ok(_)

  ## Exporting historical pinned root recovers all 24 notes before deletes!
  assert export_at_root(Ledger.store(db), pin.catalog_root, pin.txid, false, t0) is Ok(hist_snap)
  assert import_file(files, "hist.modb", hist_snap) is Ok(hist_store)
  assert Table.count(hist_store, notes) == Ok(24)

  ## Refuses overwriting existing target path
  assert import_file(files, "dst.modb", snap) is Error(TargetNotEmpty(path: "dst.modb"))
end
