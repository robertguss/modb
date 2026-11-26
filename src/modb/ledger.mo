## MoDB Layer 3: Accountable tamper-evident audit log, commit-time invariant checks,
## and atomic schema migrations built in pure Mo on top of `Modb` and `Modb.Table`.
module Modb.Ledger
expose LedgerError(..),
WriteMeta(..),
AuditEntry(..),
SchemaState(..),
Migration(..),
Invariant(..),
Schema(..),
AuditReport(..),
FullReport(..),
VerifyCheckpoint(..),
Db(..),
to_text,
genesis_hash,
meta_bucket,
audit_bucket,
audit_by_principal_bucket,
audit_by_action_bucket,
checkpoint_bucket,
meta_table,
audit_table,
checkpoint_table,
compute_entry_hash,
schema,
with_migration,
with_invariant,
with_require_reason,
migration,
invariant,
row_invariant,
open,
open_read_only,
open_file,
open_file_read_only,
open_disk,
init_locked,
locked,
read_locked,
write_locked,
transact_locked,
store,
update_store,
check_invariants,
schema_version,
txid,
audit_count,
write,
transact,
write_and_crash,
snapshot,
release_snapshot,
audit_get,
audit_since,
audit_tail,
audit_tail_store,
audit_range,
audit_by_principal,
audit_by_action,
snapshot_audit_tail,
meta_state_store,
latest_checkpoint,
record_verify_checkpoint,
verify_audit,
verify_audit_store,
verify_audit_window,
verify_audit_window_store,
verify_invariants,
verify_all,
verify_fast
use Crypto
use Json
use Modb{Snapshot, Store, VerifyReport, WriteTx}
use Modb.Errors{ModbError}
use Modb.Pager{BlockStore}
use Modb.Table{Index, Table, TableError}

## Initial `prev_hash` for audit sequence #1 (64 hex zeros).
genesis_hash = "0000000000000000000000000000000000000000000000000000000000000000"

## Reserved internal MoDB Layer 3 bucket names.
meta_bucket = "_modb_meta"
audit_bucket = "_modb_audit"
audit_by_principal_bucket = "_modb_audit_by_principal"
audit_by_action_bucket = "_modb_audit_by_action"

## Every failure returned by `Modb.Ledger` operations.
enum LedgerError
  TableFailure(TableError)
  InvalidMeta(reason: Text)
  InvariantViolation(name: Text, detail: Text)
  SchemaTooNew(found: Int, supported: Int)
  InvalidMigration(reason: Text)
  AuditCorrupt(reason: Text)
end

## Formats a `LedgerError` as a human-readable message.
fn to_text(err: LedgerError) : Text
  case err
    TableFailure(e): e.to_text
    InvalidMeta(reason: r): "invalid write metadata: #{r}"
    InvariantViolation(name: n, detail: d): "invariant '#{n}' violated: #{d}"
    SchemaTooNew(found: f, supported: s): "database schema v#{f} is newer than supported v#{s}"
    InvalidMigration(reason: r): "invalid schema migration: #{r}"
    AuditCorrupt(reason: r): "audit ledger corrupt: #{r}"
  end
end

## Caller-supplied accountability metadata attached to every ledger write.
struct WriteMeta
  principal: Text
  action: Text
  reason: Text
  at: Time
end

## Immutable tamper-evident audit entry committed atomically alongside each write.
struct AuditEntry
  seq: Int
  txid: Int
  schema_version: Int
  principal: Text
  action: Text
  reason: Text
  at: Time
  summary: Text
  payload: Json
  prev_hash: Text
  entry_hash: Text
end

## Persisted schema and audit-chain head state stored in `_modb_meta`.
struct SchemaState
  version: Int
  next_audit_seq: Int
  last_audit_hash: Text
end

## Structured payload written into `_modb_audit` when a schema migration executes.
struct MigrationAuditPayload
  from_version: Int
  to_version: Int
  description: Text
end

## One versioned, atomic schema upgrade step from `version - 1` to `version`.
struct Migration
  version: Int
  description: Text
  apply: fn(WriteTx) : Result(WriteTx, TableError)
end

## Commit-time invariant checked over uncommitted `WriteTx` state before `Modb.commit`.
## Returning `Ok(None)` passes; `Ok(Some(detail))` aborts and rolls back the transaction.
struct Invariant
  name: Text
  check: fn(WriteTx) : Result(Option(Text), TableError)
end

## Declarative database schema: target version, ordered migrations, invariants, and policy.
struct Schema
  target_version: Int
  migrations: List(Migration)
  invariants: List(Invariant)
  require_reason: Bool
end

## Result of `verify_audit`.
struct AuditReport
  entry_count: Int
  schema_version: Int
  last_seq: Int
  last_hash: Text
end

## Combined structural + audit-chain + invariant verification summary.
struct FullReport
  storage: VerifyReport
  audit: AuditReport
  invariants_checked: Int
end

## Persisted verification checkpoint recording the last fully verified audit sequence & hash.
struct VerifyCheckpoint
  seq: Int
  txid: Int
  audit_hash: Text
  verified_at: Time
end

checkpoint_bucket = "_modb_checkpoints"

## Open ledger-backed MoDB handle combining the CoW B+Tree store with schema & audit state.
struct Db
  store: Store
  schema: Schema
  state: SchemaState
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, LedgerError)
  res.map_error(fn(e) TableFailure(Table.Storage(e)) end)
end

fn meta_table() : Table(Text, SchemaState)
  Table.text_key[SchemaState]("_modb_meta")
end

fn audit_by_principal_index() : Index(Int, AuditEntry, Text)
  Table.text_index[Int, AuditEntry]("_modb_audit_by_principal", fn(e) e.principal end)
end

fn audit_by_action_index() : Index(Int, AuditEntry, Text)
  Table.text_index[Int, AuditEntry]("_modb_audit_by_action", fn(e) e.action end)
end

fn audit_table() : Table(Int, AuditEntry)
  Table.int_key[AuditEntry]("_modb_audit").with_index(audit_by_principal_index()).with_index(
    audit_by_action_index()
  )
end

fn checkpoint_table() : Table(Text, VerifyCheckpoint)
  Table.text_key[VerifyCheckpoint](checkpoint_bucket)
end

## Returns the latest full-verification checkpoint recorded in `_modb_checkpoints`, if any.
fn latest_checkpoint(db: Db) : Result(Option(VerifyCheckpoint), LedgerError)
  Ok(try Table.get(db.store, checkpoint_table(), "latest"))
end

fn initial_schema_state() : SchemaState
  SchemaState(version: 0, next_audit_seq: 1, last_audit_hash: genesis_hash)
end

fn len_prefixed(b: Bytes) : Bytes
  Bytes.join([Bytes.from_u32_be(b.size), b])
end

## Canonical SHA-256 hash over every field of an `AuditEntry` (excluding `entry_hash` itself).
fn compute_entry_hash(
  seq: Int,
  commit_txid: Int,
  ver: Int,
  principal: Text,
  action: Text,
  reason: Text,
  at: Time,
  summary: Text,
  payload: Json,
  prev_hash: Text
) : Text
  parts = [
    "MODB-AUDIT-V1".bytes,
    Bytes.from_i64_be(seq),
    Bytes.from_i64_be(commit_txid),
    Bytes.from_i64_be(ver),
    len_prefixed(principal.bytes),
    len_prefixed(action.bytes),
    len_prefixed(reason.bytes),
    len_prefixed(Json.encode(at).bytes),
    len_prefixed(summary.bytes),
    len_prefixed(Json.encode(payload).bytes),
    len_prefixed(prev_hash.bytes)
  ]
  Crypto.sha256(Bytes.join(parts)).to_hex
end

## Starts a new `Schema` targeting `target_version` (`>= 0`).
fn schema(target_version: Int) : Schema
  Schema(target_version: target_version, migrations: [], invariants: [], require_reason: false)
end

## Configures whether every write must supply a non-empty `WriteMeta.reason`.
fn with_require_reason(sc: Schema, required?: Bool) : Schema
  var next = sc
  next.require_reason = required?
  next
end

## Declares one atomic migration step targeting `version`.
fn migration(version: Int, description: Text, apply: fn(WriteTx) : Result(WriteTx, TableError)) : Migration
  Migration(version: version, description: description, apply: apply)
end

## Attaches a migration step to `sc`.
fn with_migration(sc: Schema, m: Migration) : Schema
  var next = sc
  next.migrations = next.migrations.append(m)
  next
end

## Declares a general commit-time invariant checked over uncommitted `WriteTx` state.
fn invariant(name: Text, check: fn(WriteTx) : Result(Option(Text), TableError)) : Invariant
  Invariant(name: name, check: check)
end

## Declares a per-row commit-time invariant over all rows of `tbl`.
## On tracked write transactions (`Modb.begin_write_tracked`), evaluates ONLY rows written in `tx`
## (O(touched) instead of O(N)); on untracked checks (`verify_invariants`, migrations), scans all rows.
fn row_invariant(name: Text, tbl: Table(K, V), predicate: fn(K, V) : Option(Text)) : Invariant
  Invariant(
    name: name,
    check: fn(tx)
      if Modb.tx_is_tracked?(tx) and not Modb.tx_bucket_deleted?(tx, tbl.bucket)
        touched = Modb.tx_touched_puts(tx, tbl.bucket)
        for kb in touched
          case try Modb.tx_get(tx, tbl.bucket, kb).map_error(fn(e) Table.Storage(e) end)
            Some(vb):
              k = try tbl.key_codec.decode(kb)
              v = try tbl.decode_value(vb).map_error(fn(e) Table.DecodeValue(e) end)
              case predicate(k, v)
                Some(detail): return Ok(Some(detail))
                None: Unit
              end
            None: Unit
          end
        end
        return Ok(None)
      end
      rows = try Table.tx_scan(tx, tbl, None, None, 0)
      for (k, v) in rows
        case predicate(k, v)
          Some(detail): return Ok(Some(detail))
          None: Unit
        end
      end
      Ok(None)
    end
  )
end

## Attaches a commit-time invariant to `sc`.
fn with_invariant(sc: Schema, inv: Invariant) : Schema
  var next = sc
  next.invariants = next.invariants.append(inv)
  next
end

fn validate_schema_definition(sc: Schema) : Result(Unit, LedgerError)
  if sc.target_version < 0
    return Error(InvalidMigration(reason: "target_version must be >= 0, got #{sc.target_version}"))
  end
  var seen = Set.empty
  for m in sc.migrations
    if m.version < 1 or m.version > sc.target_version
      return Error(
        InvalidMigration(reason: "migration version #{m.version} outside 1..#{sc.target_version}")
      )
    end
    if seen.has?(m.version)
      return Error(InvalidMigration(reason: "duplicate migration for version #{m.version}"))
    end
    seen = seen.add(m.version)
  end
  for inv in sc.invariants
    if inv.name.trim.empty?
      return Error(InvalidMigration(reason: "invariant name cannot be empty"))
    end
  end
  Ok(Unit)
end

fn find_migration(sc: Schema, version: Int) : Result(Migration, LedgerError)
  for m in sc.migrations
    return Ok(m) if m.version == version
  end
  Error(InvalidMigration(reason: "missing migration for version #{version}"))
end

## Evaluates every invariant declared in `sc` against an uncommitted `WriteTx`.
fn check_invariants(sc: Schema, tx: WriteTx) : Result(Unit, LedgerError)
  check_all_invariants(sc.invariants, tx)
end

fn check_all_invariants(invariants: List(Invariant), tx: WriteTx) : Result(Unit, LedgerError)
  for inv in invariants
    case try inv.check(tx)
      Some(detail): return Error(InvariantViolation(name: inv.name, detail: detail))
      None: Unit
    end
  end
  Ok(Unit)
end

fn append_audit_entry(
  tx: WriteTx,
  state: SchemaState,
  commit_txid: Int,
  meta: WriteMeta,
  summary: Text,
  payload: Json
) : Result((WriteTx, SchemaState), LedgerError)
  seq = state.next_audit_seq
  prev = state.last_audit_hash
  hash = compute_entry_hash(
    seq,
    commit_txid,
    state.version,
    meta.principal,
    meta.action,
    meta.reason,
    meta.at,
    summary,
    payload,
    prev
  )
  entry = AuditEntry(
    seq: seq,
    txid: commit_txid,
    schema_version: state.version,
    principal: meta.principal,
    action: meta.action,
    reason: meta.reason,
    at: meta.at,
    summary: summary,
    payload: payload,
    prev_hash: prev,
    entry_hash: hash
  )
  next_state = SchemaState(version: state.version, next_audit_seq: seq + 1, last_audit_hash: hash)
  t1 = try Table.put(tx, audit_table(), seq, entry)
  t2 = try Table.put(t1, meta_table(), "state", next_state)
  Ok((t2, next_state))
end

fn validate_write_meta(sc: Schema, meta: WriteMeta) : Result(Unit, LedgerError)
  if meta.principal.trim.empty?
    return Error(InvalidMeta(reason: "principal cannot be empty"))
  end
  if meta.action.trim.empty?
    return Error(InvalidMeta(reason: "action cannot be empty"))
  end
  if sc.require_reason and meta.reason.trim.empty?
    return Error(InvalidMeta(reason: "reason is required by schema policy"))
  end
  Ok(Unit)
end

fn open_store_with_schema(base_store: Store, sc: Schema, now: Time) : Result(Db, LedgerError)
  try validate_schema_definition(sc)
  stored = (try Table.get(base_store, meta_table(), "state")) or initial_schema_state()
  if stored.version > sc.target_version
    return Error(SchemaTooNew(found: stored.version, supported: sc.target_version))
  end
  if stored.version == sc.target_version
    return Ok(Db(store: base_store, schema: sc, state: stored))
  end

  ## Collect all required migrations before starting the transaction.
  var pending = []
  var v = stored.version + 1
  while v <= sc.target_version
    m = try find_migration(sc, v)
    pending = pending.append(m)
    v += 1
  end

  expected_txid = Modb.txid(base_store) + 1
  var cur_tx = Modb.begin_write(base_store)
  var cur_state = stored
  for m in pending
    cur_tx = try m.apply(cur_tx)
    var stepped = cur_state
    stepped.version = m.version
    mig_meta = WriteMeta(
      principal: "system:migration",
      action: "migrate",
      reason: "schema upgrade to v#{m.version}",
      at: now
    )
    mig_summary = "v#{m.version - 1} -> v#{m.version}: #{m.description}"
    mig_payload = MigrationAuditPayload(
      from_version: m.version - 1,
      to_version: m.version,
      description: m.description
    ).to_json
    (t_next, s_next) = try append_audit_entry(
      cur_tx,
      stepped,
      expected_txid,
      mig_meta,
      mig_summary,
      mig_payload
    )
    cur_tx = t_next
    cur_state = s_next
  end

  try check_all_invariants(sc.invariants, cur_tx)
  committed = try wrap_modb(Modb.commit(cur_tx))
  if Modb.txid(committed) != expected_txid
    return Error(
      AuditCorrupt(
        reason: "migration txid mismatch: expected #{expected_txid}, got #{Modb.txid(committed)}"
      )
    )
  end
  Ok(Db(store: committed, schema: sc, state: cur_state))
end

## Opens (or initializes and atomically migrates) a ledger-backed MoDB file.
fn open(files: Files, path: Text, sc: Schema, now: Time) : Result(Db, LedgerError)
  s = try wrap_modb(Modb.open(files, path))
  open_store_with_schema(s, sc, now)
end

fn open_store_read_only(base_store: Store, sc: Schema) : Result(Db, LedgerError)
  try validate_schema_definition(sc)
  stored = (try Table.get(base_store, meta_table(), "state")) or initial_schema_state()
  if stored.version > sc.target_version
    return Error(SchemaTooNew(found: stored.version, supported: sc.target_version))
  end
  if stored.version < sc.target_version
    return Error(
      InvalidMigration(
        reason: "database schema v#{stored.version} is older than required v#{sc.target_version}; open writable to migrate"
      )
    )
  end
  Ok(Db(store: base_store, schema: sc, state: stored))
end

## Opens an existing ledger-backed MoDB file read-only via `ReadFiles` (never writes or migrates).
fn open_read_only(rf: ReadFiles, path: Text, sc: Schema) : Result(Db, LedgerError)
  s = try wrap_modb(Modb.open_read_only(rf, path))
  open_store_read_only(s, sc)
end

## Opens a ledger-backed MoDB database on an already-open `Files.File` handle.
fn open_file(file: Files.File, sc: Schema, now: Time) : Result(Db, LedgerError)
  s = try wrap_modb(Modb.open_file(file))
  open_store_with_schema(s, sc, now)
end

## Opens an already-open read-only `Files.File` handle as a `Modb.Ledger.Db`.
fn open_file_read_only(file: Files.File, sc: Schema) : Result(Db, LedgerError)
  s = try wrap_modb(Modb.open_file_read_only(file))
  open_store_read_only(s, sc)
end

## Opens a ledger-backed MoDB database on any `BlockStore` (real file or crash simulator).
fn open_disk(disk: BlockStore, sc: Schema, now: Time) : Result(Db, LedgerError)
  s = try wrap_modb(Modb.open_disk(disk))
  open_store_with_schema(s, sc, now)
end

## Acquires an exclusive advisory lock on `path`, initializes and atomically migrates the
## database to `sc.target_version` if needed, releases the lock, and returns `(txid, state)`.
fn init_locked(files: Files, path: Text, sc: Schema, now: Time) : Result(
  (Int, SchemaState),
  LedgerError
)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(me) TableFailure(Table.Storage(me)) end,
    fn(s)
      db = try open_store_with_schema(s, sc, now)
      Ok((txid(db), db.state))
    end
  )
end

## Acquires an exclusive advisory lock on `path` via `Files`, opens or migrates the database,
## runs `work(db)` while holding the lock, and always releases the lock.
fn locked(
  files: Files,
  path: Text,
  sc: Schema,
  now: Time,
  wrap_error: fn(LedgerError) : E,
  work: fn(Db) : Result(R, E)
) : Result(R, E)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(me) wrap_error(TableFailure(Table.Storage(me))) end,
    fn(s)
      db = try open_store_with_schema(s, sc, now).map_error(wrap_error)
      work(db)
    end
  )
end

## Acquires a shared advisory lock on `path` via `ReadFiles`, opens a fresh committed read-only
## ledger handle, executes `work(db)`, and always releases the lock.
fn read_locked(
  rf: ReadFiles,
  path: Text,
  sc: Schema,
  wrap_error: fn(LedgerError) : E,
  work: fn(Db) : Result(R, E)
) : Result(R, E)
  Modb.with_shared_lock(
    rf,
    path,
    fn(me) wrap_error(TableFailure(Table.Storage(me))) end,
    fn(s)
      db = try open_store_read_only(s, sc).map_error(wrap_error)
      work(db)
    end
  )
end

## Acquires an exclusive advisory lock on `path` via `Files`, reloads the latest committed state
## (initializing/migrating if needed), runs an accountable write transaction, commits atomically,
## and always releases the lock.
fn write_locked(
  files: Files,
  path: Text,
  sc: Schema,
  meta: WriteMeta,
  summary: Text,
  payload: Json,
  work: fn(WriteTx) : Result(WriteTx, TableError)
) : Result(SchemaState, LedgerError)
  try validate_write_meta(sc, meta)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(me) TableFailure(Table.Storage(me)) end,
    fn(s)
      db = try open_store_with_schema(s, sc, meta.at)
      next = try write(db, meta, summary, payload, work)
      Ok(next.state)
    end
  )
end

## Acquires an exclusive advisory lock on `path` via `Files`, reloads the latest committed state
## (initializing/migrating if needed), runs a domain transaction returning `R`, commits atomically,
## and always releases the lock.
fn transact_locked(
  files: Files,
  path: Text,
  sc: Schema,
  meta: WriteMeta,
  summary: Text,
  payload: Json,
  wrap_error: fn(LedgerError) : E,
  work: fn(WriteTx) : Result((WriteTx, R), E)
) : Result(R, E)
  try validate_write_meta(sc, meta).map_error(wrap_error)
  Modb.with_exclusive_lock(
    files,
    path,
    fn(me) wrap_error(TableFailure(Table.Storage(me))) end,
    fn(s)
      db = try open_store_with_schema(s, sc, meta.at).map_error(wrap_error)
      (_next, out) = try transact(db, meta, summary, payload, wrap_error, work)
      Ok(out)
    end
  )
end

## Exposes the underlying `Modb.Store` for typed `Modb.Table` read queries.
fn store(db: Db) : Store
  db.store
end

## Replaces `db.store` after an internal metadata commit (`_modb_pins` / `_modb_worlds`)
## while preserving `db.schema` and `db.state`.
fn update_store(db: Db, next_store: Store) : Db
  Db(store: next_store, schema: db.schema, state: db.state)
end

## Current persisted schema version.
fn schema_version(db: Db) : Int
  db.state.version
end

## Current committed `Modb` transaction ID.
fn txid(db: Db) : Int
  Modb.txid(db.store)
end

## Total number of committed audit entries.
fn audit_count(db: Db) : Int
  db.state.next_audit_seq - 1
end

## Runs an accountable write transaction:
## 1. Validates `meta` against schema policy.
## 2. Executes `work(tx)`.
## 3. Verifies every schema `Invariant` on uncommitted `tx` state.
## 4. Appends a hash-chained `AuditEntry` and updates `_modb_meta` in the same `WriteTx`.
## 5. Commits atomically via `Modb.commit` (rolling back completely on any error).
fn write(
  db: Db,
  meta: WriteMeta,
  summary: Text,
  payload: Json,
  work: fn(WriteTx) : Result(WriteTx, TableError)
) : Result(Db, LedgerError)
  try validate_write_meta(db.schema, meta)
  expected_txid = Modb.txid(db.store) + 1
  tx0 = Modb.begin_write_tracked(db.store)
  tx1 = try work(tx0)
  try check_all_invariants(db.schema.invariants, tx1)
  (tx2, next_state) = try append_audit_entry(tx1, db.state, expected_txid, meta, summary, payload)
  committed = try wrap_modb(Modb.commit(tx2))
  if Modb.txid(committed) != expected_txid
    return Error(
      AuditCorrupt(
        reason: "commit txid mismatch: expected #{expected_txid}, got #{Modb.txid(committed)}"
      )
    )
  end
  Ok(Db(store: committed, schema: db.schema, state: next_state))
end

## Accountable write transaction returning domain result `R` and lifting `LedgerError` into `E`.
fn transact(
  db: Db,
  meta: WriteMeta,
  summary: Text,
  payload: Json,
  wrap_error: fn(LedgerError) : E,
  work: fn(WriteTx) : Result((WriteTx, R), E)
) : Result((Db, R), E)
  try validate_write_meta(db.schema, meta).map_error(wrap_error)
  expected_txid = Modb.txid(db.store) + 1
  tx0 = Modb.begin_write_tracked(db.store)
  (tx1, out) = try work(tx0)
  try check_all_invariants(db.schema.invariants, tx1).map_error(wrap_error)
  (tx2, next_state) = try append_audit_entry(tx1, db.state, expected_txid, meta, summary, payload)
    .map_error(wrap_error)
  committed = try wrap_modb(Modb.commit(tx2)).map_error(wrap_error)
  if Modb.txid(committed) != expected_txid
    return Error(
      wrap_error(
        AuditCorrupt(
          reason: "commit txid mismatch: expected #{expected_txid}, got #{Modb.txid(committed)}"
        )
      )
    )
  end
  Ok((Db(store: committed, schema: db.schema, state: next_state), out))
end

## Runs an accountable write up to a simulated power-cut boundary (`phase == 1` before data sync,
## `phase == 2` after data sync & meta write, before meta sync) for deterministic crash testing.
fn write_and_crash(
  db: Db,
  meta: WriteMeta,
  summary: Text,
  payload: Json,
  phase: Int,
  rng: Random,
  work: fn(WriteTx) : Result(WriteTx, TableError)
) : Result(BlockStore, LedgerError)
  try validate_write_meta(db.schema, meta)
  expected_txid = Modb.txid(db.store) + 1
  tx0 = Modb.begin_write_tracked(db.store)
  tx1 = try work(tx0)
  try check_all_invariants(db.schema.invariants, tx1)
  (tx2, _next_state) = try append_audit_entry(tx1, db.state, expected_txid, meta, summary, payload)
  wrap_modb(Modb.commit_and_crash(tx2, phase, rng))
end

## Pins an O(1) immutable read snapshot of both business tables and the audit ledger.
fn snapshot(db: Db) : (Db, Snapshot)
  (next_store, snap) = Modb.snapshot(db.store)
  (Db(store: next_store, schema: db.schema, state: db.state), snap)
end

## Releases a previously pinned snapshot.
fn release_snapshot(db: Db, snap: Snapshot) : Result(Db, LedgerError)
  next_store = try wrap_modb(Modb.release_snapshot(db.store, snap))
  Ok(Db(store: next_store, schema: db.schema, state: db.state))
end

## Looks up a single audit entry by exact sequence number (`1`-based).
fn audit_get(db: Db, seq: Int) : Result(Option(AuditEntry), LedgerError)
  Ok(try Table.get(db.store, audit_table(), seq))
end

## Returns audit entries with `seq > after_seq` in ascending sequence order (`limit <= 0` = all).
fn audit_since(db: Db, after_seq: Int, limit: Int) : Result(List(AuditEntry), LedgerError)
  start_seq = if after_seq < 0: 1 else: after_seq + 1
  rows = try Table.scan(db.store, audit_table(), Some(start_seq), None, limit)
  Ok(rows.map(fn(p) p.1 end))
end

## Returns audit entries in half-open sequence range `[start_seq, end_seq)`.
fn audit_range(db: Db, start_seq: Int, end_seq: Int) : Result(List(AuditEntry), LedgerError)
  rows = try Table.range(db.store, audit_table(), start_seq, end_seq)
  Ok(rows.map(fn(p) p.1 end))
end

## Schema-less lookup of `_modb_meta["state"]` on any committed `Store`.
fn meta_state_store(store: Store) : Result(Option(SchemaState), LedgerError)
  Ok(try Table.get(store, meta_table(), "state"))
end

## Schema-less tail scan of the most recent `limit` audit entries on any committed `Store`.
fn audit_tail_store(store: Store, limit: Int) : Result(List(AuditEntry), LedgerError)
  total = case try meta_state_store(store)
    Some(st): st.next_audit_seq - 1
    None: try wrap_modb(Modb.count_bucket(store, audit_bucket))
  end
  return Ok([]) if total <= 0
  if limit <= 0 or limit >= total
    rows = try Table.all(store, audit_table())
    Ok(rows.map(fn(p) p.1 end))
  else
    start_seq = total - limit + 1
    rows = try Table.scan(store, audit_table(), Some(start_seq), None, limit)
    Ok(rows.map(fn(p) p.1 end))
  end
end

## Returns the most recent `limit` audit entries in ascending sequence order (`limit <= 0` = all).
fn audit_tail(db: Db, limit: Int) : Result(List(AuditEntry), LedgerError)
  audit_tail_store(db.store, limit)
end

## Indexed lookup of all audit entries written by `principal` (in sequence order).
fn audit_by_principal(db: Db, principal: Text) : Result(List(AuditEntry), LedgerError)
  rows = try Table.lookup(db.store, audit_table(), audit_by_principal_index(), principal)
  Ok(rows.map(fn(p) p.1 end))
end

## Indexed lookup of all audit entries matching `action` (in sequence order).
fn audit_by_action(db: Db, action: Text) : Result(List(AuditEntry), LedgerError)
  rows = try Table.lookup(db.store, audit_table(), audit_by_action_index(), action)
  Ok(rows.map(fn(p) p.1 end))
end

## Reads the most recent `limit` audit entries visible in pinned `snap`.
fn snapshot_audit_tail(db: Db, snap: Snapshot, limit: Int) : Result(List(AuditEntry), LedgerError)
  rows = try Table.snapshot_all(db.store, snap, audit_table())
  entries = rows.map(fn(p) p.1 end)
  if limit <= 0 or limit >= entries.size
    Ok(entries)
  else
    Ok(entries.drop(entries.size - limit))
  end
end

## Schema-less complete verification of `_modb_audit`, `_modb_meta`, and secondary audit indexes
## on any committed `Store` (used by both `verify_audit` and the standalone `modb` CLI).
fn verify_audit_store(store: Store) : Result(AuditReport, LedgerError)
  stored_opt = try Table.get(store, meta_table(), "state")
  rows = try Table.all(store, audit_table())
  principal_cnt = try wrap_modb(Modb.count_bucket(store, audit_by_principal_bucket))
  action_cnt = try wrap_modb(Modb.count_bucket(store, audit_by_action_bucket))

  if principal_cnt != rows.size
    return Error(
      AuditCorrupt(
        reason: "principal audit index count #{principal_cnt} != audit entry count #{rows.size}"
      )
    )
  end
  if action_cnt != rows.size
    return Error(
      AuditCorrupt(
        reason: "action audit index count #{action_cnt} != audit entry count #{rows.size}"
      )
    )
  end

  cp_opt = try Table.get(store, checkpoint_table(), "latest")
  stored = case stored_opt
    Some(st): st
    None:
      if not rows.empty?
        return Error(AuditCorrupt(reason: "audit entries exist without _modb_meta state"))
      end
      if cp_opt is Some(_)
        return Error(AuditCorrupt(reason: "verify checkpoint exists without _modb_meta state"))
      end
      return Ok(
        AuditReport(entry_count: 0, schema_version: 0, last_seq: 0, last_hash: genesis_hash)
      )
  end

  var expected_seq = 1
  var prev = genesis_hash
  var last_txid = 0
  store_txid = Modb.txid(store)
  var cp_matched = false

  for (key_seq, entry) in rows
    if key_seq != expected_seq or entry.seq != expected_seq
      return Error(
        AuditCorrupt(
          reason: "sequence gap/mismatch at key=#{key_seq}, entry.seq=#{entry.seq} (expected #{expected_seq})"
        )
      )
    end
    if entry.txid < 2 or entry.txid < last_txid or entry.txid > store_txid
      return Error(
        AuditCorrupt(
          reason: "invalid txid #{entry.txid} at seq #{entry.seq} (last=#{last_txid}, store=#{store_txid})"
        )
      )
    end
    if entry.prev_hash != prev
      return Error(
        AuditCorrupt(reason: "hash chain broken at seq #{entry.seq}: prev_hash mismatch")
      )
    end
    recomputed = compute_entry_hash(
      entry.seq,
      entry.txid,
      entry.schema_version,
      entry.principal,
      entry.action,
      entry.reason,
      entry.at,
      entry.summary,
      entry.payload,
      entry.prev_hash
    )
    if entry.entry_hash != recomputed
      return Error(
        AuditCorrupt(reason: "tampered audit entry at seq #{entry.seq}: entry_hash mismatch")
      )
    end
    if cp_opt is Some(cp) and entry.seq == cp.seq
      if cp.audit_hash != entry.entry_hash
        return Error(
          AuditCorrupt(reason: "tampered verify checkpoint hash at seq #{cp.seq}")
        )
      end
      cp_matched = true
    end
    prev = entry.entry_hash
    last_txid = entry.txid
    expected_seq += 1
  end

  if stored.next_audit_seq != expected_seq
    return Error(
      AuditCorrupt(
        reason: "meta next_audit_seq=#{stored.next_audit_seq} != expected #{expected_seq}"
      )
    )
  end
  if stored.last_audit_hash != prev
    return Error(AuditCorrupt(reason: "meta last_audit_hash disagrees with audit chain head"))
  end
  if cp_opt is Some(cp)
    valid_zero = cp.seq == 0 and cp.audit_hash == genesis_hash
    if (not valid_zero and (cp.seq < 1 or cp.seq >= expected_seq or not cp_matched)) or
      cp.txid < 2 or
      cp.txid > store_txid
      return Error(AuditCorrupt(reason: "tampered verify checkpoint seq=#{cp.seq}"))
    end
  end

  Ok(
    AuditReport(
      entry_count: rows.size,
      schema_version: stored.version,
      last_seq: rows.size,
      last_hash: prev
    )
  )
end

## Verifies complete tamper-evidence of `_modb_audit`, `_modb_meta`, and secondary audit indexes.
fn verify_audit(db: Db) : Result(AuditReport, LedgerError)
  verify_audit_store(db.store)
end

## Evaluates every invariant declared in `db.schema` against committed state (read-only).
fn verify_invariants(db: Db) : Result(Unit, LedgerError)
  tx = Modb.begin_write(db.store)
  check_all_invariants(db.schema.invariants, tx)
end

## Runs full end-to-end verification: B+Tree storage integrity, tamper-evident audit chain,
## and all commit-time schema invariants.
fn verify_all(db: Db) : Result(FullReport, LedgerError)
  storage_rep = try wrap_modb(Modb.verify(db.store))
  audit_rep = try verify_audit(db)
  try verify_invariants(db)
  Ok(
    FullReport(
      storage: storage_rep,
      audit: audit_rep,
      invariants_checked: db.schema.invariants.size
    )
  )
end

## Runs full genesis-to-tip `verify_all` and persists a verified checkpoint in `_modb_checkpoints`
## so subsequent `verify_fast` checks only hash-verify audit entries appended after this checkpoint.
fn record_verify_checkpoint(db: Db, at: Time) : Result((Db, VerifyCheckpoint), LedgerError)
  rep = try verify_all(db)
  cp = VerifyCheckpoint(
    seq: rep.audit.last_seq,
    txid: Modb.txid(db.store) + 1,
    audit_hash: rep.audit.last_hash,
    verified_at: at
  )
  tx0 = Modb.begin_write(db.store)
  tx1 = try Table.put(tx0, checkpoint_table(), "latest", cp)
  committed = try wrap_modb(Modb.commit(tx1))
  Ok((Db(store: committed, schema: db.schema, state: db.state), cp))
end

fn verify_audit_entries_range(
  rows: List((Int, AuditEntry)),
  start_seq: Int,
  expected_count: Int,
  initial_prev: Option(Text),
  expected_final_hash: Text,
  store_txid: Int
) : Result(Unit, LedgerError)
  if rows.size != expected_count
    return Error(
      AuditCorrupt(
        reason: "audit range count #{rows.size} != expected #{expected_count} from seq #{start_seq}"
      )
    )
  end
  var expected_seq = start_seq
  var prev_opt = initial_prev
  var last_txid = 0
  for (key_seq, entry) in rows
    if key_seq != expected_seq or entry.seq != expected_seq
      return Error(
        AuditCorrupt(
          reason: "sequence gap/mismatch at key=#{key_seq}, entry.seq=#{entry.seq} (expected #{expected_seq})"
        )
      )
    end
    if entry.txid < 2 or entry.txid < last_txid or entry.txid > store_txid
      return Error(
        AuditCorrupt(
          reason: "invalid txid #{entry.txid} at seq #{entry.seq} (last=#{last_txid}, store=#{store_txid})"
        )
      )
    end
    if prev_opt is Some(expected_prev) and entry.prev_hash != expected_prev
      return Error(
        AuditCorrupt(reason: "hash chain broken at seq #{entry.seq}: prev_hash mismatch")
      )
    end
    recomputed = compute_entry_hash(
      entry.seq,
      entry.txid,
      entry.schema_version,
      entry.principal,
      entry.action,
      entry.reason,
      entry.at,
      entry.summary,
      entry.payload,
      entry.prev_hash
    )
    if entry.entry_hash != recomputed
      return Error(
        AuditCorrupt(reason: "tampered audit entry at seq #{entry.seq}: entry_hash mismatch")
      )
    end
    prev_opt = Some(entry.entry_hash)
    last_txid = entry.txid
    expected_seq += 1
  end
  final_hash = prev_opt or ""
  if final_hash != expected_final_hash
    return Error(AuditCorrupt(reason: "meta last_audit_hash disagrees with audit chain head"))
  end
  Ok(Unit)
end

## Schema-less windowed / checkpoint-anchored audit verification (`O(entries since checkpoint)` or
## `max_entries`), verifying exact row counts on `_modb_audit` and both secondary indexes without
## scanning old rows.
fn verify_audit_window_store(store: Store, max_entries: Int) : Result(AuditReport, LedgerError)
  stored_opt = try Table.get(store, meta_table(), "state")
  audit_cnt = try wrap_modb(Modb.count_bucket(store, audit_bucket))
  principal_cnt = try wrap_modb(Modb.count_bucket(store, audit_by_principal_bucket))
  action_cnt = try wrap_modb(Modb.count_bucket(store, audit_by_action_bucket))

  if principal_cnt != audit_cnt
    return Error(
      AuditCorrupt(
        reason: "principal audit index count #{principal_cnt} != audit entry count #{audit_cnt}"
      )
    )
  end
  if action_cnt != audit_cnt
    return Error(
      AuditCorrupt(
        reason: "action audit index count #{action_cnt} != audit entry count #{audit_cnt}"
      )
    )
  end

  stored = case stored_opt
    Some(st): st
    None:
      if audit_cnt != 0
        return Error(AuditCorrupt(reason: "audit entries exist without _modb_meta state"))
      end
      return Ok(
        AuditReport(entry_count: 0, schema_version: 0, last_seq: 0, last_hash: genesis_hash)
      )
  end

  total = stored.next_audit_seq - 1
  if total < 0 or audit_cnt != total
    return Error(
      AuditCorrupt(
        reason: "meta next_audit_seq=#{stored.next_audit_seq} disagrees with audit count #{audit_cnt}"
      )
    )
  end
  if total == 0
    if stored.last_audit_hash != genesis_hash
      return Error(AuditCorrupt(reason: "meta last_audit_hash disagrees with empty audit chain"))
    end
    return Ok(
      AuditReport(entry_count: 0, schema_version: stored.version, last_seq: 0, last_hash: genesis_hash)
    )
  end
  if max_entries <= 0 or total <= max_entries
    return verify_audit_store(store)
  end

  store_txid = Modb.txid(store)
  cp_opt = try Table.get(store, checkpoint_table(), "latest")
  case cp_opt
    Some(cp) if cp.seq > 0 and cp.seq <= total and total - cp.seq <= max_entries and cp.txid >= 2 and
      cp.txid <= store_txid:
      if cp.seq == total
        tail_entry = try (try Table.get(store, audit_table(), total)).or_fail(
          AuditCorrupt(reason: "missing tail audit entry ##{total}")
        )
        if tail_entry.entry_hash != cp.audit_hash or tail_entry.txid < 2 or
          tail_entry.txid > store_txid
          return Error(AuditCorrupt(reason: "audit tail ##{total} disagrees with checkpoint"))
        end
        try verify_audit_entries_range(
          [(total, tail_entry)],
          total,
          1,
          None,
          stored.last_audit_hash,
          store_txid
        )
      else
        tail_rows = try Table.scan(store, audit_table(), Some(cp.seq + 1), None, max_entries + 1)
        try verify_audit_entries_range(
          tail_rows,
          cp.seq + 1,
          total - cp.seq,
          Some(cp.audit_hash),
          stored.last_audit_hash,
          store_txid
        )
      end
    Some(_) | None:
      start_seq = total - max_entries + 1
      win_rows = try Table.scan(store, audit_table(), Some(start_seq), None, max_entries + 1)
      try verify_audit_entries_range(
        win_rows,
        start_seq,
        max_entries,
        None,
        stored.last_audit_hash,
        store_txid
      )
  end

  Ok(
    AuditReport(
      entry_count: total,
      schema_version: stored.version,
      last_seq: total,
      last_hash: stored.last_audit_hash
    )
  )
end

## Windowed / checkpoint-anchored audit verification (`O(entries since checkpoint)` or `max_entries`).
## Verifies exact row counts on `_modb_audit` and both secondary indexes without scanning old rows.
fn verify_audit_window(db: Db, max_entries: Int) : Result(AuditReport, LedgerError)
  verify_audit_window_store(db.store, max_entries)
end

## Fast bounded health check for latency-constrained HTTP endpoints: checks catalog + bucket root
## headers (`Modb.verify_light`), checkpoint-anchored/windowed audit hash chain, and invariants.
fn verify_fast(db: Db, max_audit_entries: Int) : Result(FullReport, LedgerError)
  storage_rep = try wrap_modb(Modb.verify_light(db.store))
  audit_rep = try verify_audit_window(db, max_audit_entries)
  try verify_invariants(db)
  Ok(
    FullReport(
      storage: storage_rep,
      audit: audit_rep,
      invariants_checked: db.schema.invariants.size
    )
  )
end

struct CounterRow
  value: Int
end

test "Modb.Ledger unit: migrations, accountable writes, invariants, and hash-chain verification"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T03:00:00Z") or stop "t0"
  counters = Table.text_key[CounterRow]("counters")

  sc = schema(1).with_require_reason(true).with_migration(
    migration(
      1,
      "seed initial counter",
      fn(tx) Table.put(tx, counters, "main", CounterRow(value: 10)) end
    )
  ).with_invariant(
    row_invariant(
      "counter_non_negative",
      counters,
      fn(k, row) if row.value < 0: Some("counter '#{k}' < 0") else: None end
    )
  )

  assert open(files, "ledger-unit.modb", sc, t0) is Ok(db0)
  assert schema_version(db0) == 1
  assert audit_count(db0) == 1
  assert Table.get(store(db0), counters, "main") == Ok(Some(CounterRow(value: 10)))

  ## Missing reason is rejected cleanly without touching state or audit log
  bad_meta = WriteMeta(principal: "ada", action: "set_counter", reason: "   ", at: t0)
  assert write(
    db0,
    bad_meta,
    "set main=5",
    Json.Null,
    fn(tx) Table.put(tx, counters, "main", CounterRow(value: 5)) end
  ) is
    Error(InvalidMeta(reason: _))

  ## Violating invariant rolls back both data and audit entry
  good_meta = WriteMeta(principal: "ada", action: "set_counter", reason: "ticket #42", at: t0)
  assert write(
    db0,
    good_meta,
    "set main=-1",
    Json.Null,
    fn(tx) Table.put(tx, counters, "main", CounterRow(value: -1)) end
  ) is
    Error(InvariantViolation(name: "counter_non_negative", detail: _))
  assert audit_count(db0) == 1
  assert Table.get(store(db0), counters, "main") == Ok(Some(CounterRow(value: 10)))

  ## Valid write commits atomically with hash-chained audit entry
  assert write(
    db0,
    good_meta,
    "set main=25",
    CounterRow(value: 25).to_json,
    fn(tx) Table.put(tx, counters, "main", CounterRow(value: 25)) end
  ) is
    Ok(db1)
  assert audit_count(db1) == 2
  assert verify_all(db1) is Ok(rep)
  assert rep.audit.entry_count == 2
  assert rep.invariants_checked == 1
end

test "Modb.Ledger locked read_only/write_locked/transact_locked helpers"
  files = Files.in_memory({})
  ro = files.read_only
  t0 = Time.parse("2026-11-25T04:00:00Z") or stop "t0"
  counters = Table.text_key[CounterRow]("counters")

  sc = schema(1).with_require_reason(true).with_migration(
    migration(1, "seed counter", fn(tx) Table.put(tx, counters, "main", CounterRow(value: 100)) end)
  ).with_invariant(
    row_invariant(
      "counter_non_negative",
      counters,
      fn(k, row) if row.value < 0: Some("counter '#{k}' < 0") else: None end
    )
  )

  ## Read-only open before init fails with NotFound
  assert read_locked(ro, "locked-ledger.modb", sc, fn(e) e end, fn(db) Ok(audit_count(db)) end) is
    Error(TableFailure(Table.Storage(Io(NotFound(path: _)))))

  ## Idempotent exclusive init + migration
  assert init_locked(files, "locked-ledger.modb", sc, t0) is Ok((tx1, st1))
  assert tx1 == 2 and st1.version == 1 and st1.next_audit_seq == 2
  assert init_locked(files, "locked-ledger.modb", sc, t0) is Ok((tx2, st2))
  assert tx2 == 2 and st2.next_audit_seq == 2

  ## Exclusive locked write + rollback on invariant violation releases lock cleanly
  meta = WriteMeta(principal: "agent:bot", action: "dec", reason: "step-1", at: t0)
  assert write_locked(
    files,
    "locked-ledger.modb",
    sc,
    meta,
    "invalid -5",
    Json.Null,
    fn(tx) Table.put(tx, counters, "main", CounterRow(value: -5)) end
  ) is
    Error(InvariantViolation(name: "counter_non_negative", detail: _))

  ## Subsequent transact_locked succeeds cleanly after rolled-back write released lock
  assert transact_locked(
    files,
    "locked-ledger.modb",
    sc,
    meta,
    "decrement by 15",
    Json.Null,
    fn(e) e end,
    fn(tx)
      cur = (try Table.tx_get(tx, counters, "main").map_error(fn(e) TableFailure(e) end)) or
        CounterRow(value: 0)
      next = CounterRow(value: cur.value - 15)
      t1 = try Table.put(tx, counters, "main", next).map_error(fn(e) TableFailure(e) end)
      Ok((t1, next.value))
    end
  ) ==
    Ok(85)

  ## Concurrent-safe read_locked over ReadFiles sees committed value and passes verify_all
  assert read_locked(
    ro,
    "locked-ledger.modb",
    sc,
    fn(e) e end,
    fn(db)
      rep = try verify_all(db)
      row = try Table.get(store(db), counters, "main")
      Ok((rep.audit.entry_count, row))
    end
  ) ==
    Ok((2, Some(CounterRow(value: 85))))
end

test "Modb.Ledger checkpointed and windowed verify_fast detects post-checkpoint and checkpoint tampering"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T05:00:00Z") or stop "t0"
  counters = Table.text_key[CounterRow]("counters")
  sc = schema(1).with_require_reason(true).with_migration(
    migration(1, "seed counter", fn(tx) Table.put(tx, counters, "main", CounterRow(value: 0)) end)
  )

  assert open(files, "cp.modb", sc, t0) is Ok(db0)
  meta = WriteMeta(principal: "ada", action: "inc", reason: "step", at: t0)
  var db = db0
  for i in 1..15
    assert write(
      db,
      meta,
      "set #{i}",
      i.to_json,
      fn(tx) Table.put(tx, counters, "main", CounterRow(value: i)) end
    ) is
      Ok(next)
    db = next
  end

  ## Record checkpoint at seq 15 (1 migration + 14 writes in 1..15)
  assert record_verify_checkpoint(db, t0) is Ok((db_cp, cp))
  assert cp.seq == 15
  assert latest_checkpoint(db_cp) == Ok(Some(cp))
  assert verify_fast(db_cp, 8) is Ok(fast0)
  assert fast0.audit.entry_count == 15 and fast0.audit.last_hash == cp.audit_hash

  ## Append 4 more entries within window (16..20 -> total 19) and verify_fast passes anchored to cp
  var db_more = db_cp
  for i in 16..20
    assert write(
      db_more,
      meta,
      "set #{i}",
      i.to_json,
      fn(tx) Table.put(tx, counters, "main", CounterRow(value: i)) end
    ) is
      Ok(next)
    db_more = next
  end
  assert verify_fast(db_more, 8) is Ok(fast1)
  assert fast1.audit.entry_count == 19
  assert verify_all(db_more) is Ok(_)

  ## Sliding window mode when total - cp.seq > max_entries also passes cleanly
  assert verify_fast(db_more, 2) is Ok(fast_win)
  assert fast_win.audit.entry_count == 19

  ## Tampering with a post-checkpoint audit entry is caught by verify_fast
  assert Table.get(store(db_more), audit_table(), 18) is Ok(Some(e18))
  var bad_e18 = e18
  bad_e18.summary = "forged"
  tx_tamper = Modb.begin_write(store(db_more))
  assert Table.put(tx_tamper, audit_table(), 18, bad_e18) is Ok(tx_t1)
  assert Modb.commit(tx_t1) is Ok(bad_s)
  bad_db = update_store(db_more, bad_s)
  assert verify_fast(bad_db, 8) is Error(AuditCorrupt(reason: _))

  ## Tampering with _modb_checkpoints is caught by full verify_all
  var bad_cp = cp
  bad_cp.audit_hash = "deadbeef"
  tx_cp = Modb.begin_write(store(db_more))
  assert Table.put(tx_cp, checkpoint_table(), "latest", bad_cp) is Ok(tx_cp1)
  assert Modb.commit(tx_cp1) is Ok(bad_cp_s)
  bad_cp_db = update_store(db_more, bad_cp_s)
  assert verify_all(bad_cp_db) is Error(AuditCorrupt(reason: _))
end
