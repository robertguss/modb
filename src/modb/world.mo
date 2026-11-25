## MoDB Layer 4: Speculative Multi-Agent Worlds, In-Place Answer-Hash Read Validation,
## Per-Call Invariant Enforcement, and Whole-or-Nothing Replay Landing.
##
## Directly implements Robert's decided rules from `design.md` (§6–§7) and `models/README.md`
## (`Replay.tla` Answers 1 & 3 + needless send-back telemetry, `Worlds.tla` Option 3).
module Modb.World
expose WorldError(..),
QueryDef(..),
ActionDef(..),
Catalog(..),
WorldStep(..),
WorldStatus(..),
WorldRecord(..),
LandingMetrics(..),
LandOptions(..),
LandResult(..),
BucketDiffSummary(..),
worlds_bucket,
world_metrics_bucket,
to_text,
catalog,
with_query,
with_action,
strict_land_options,
empty_metrics,
worlds_table,
get_world,
list_worlds,
metrics,
open_world,
world_query,
world_call,
world_diff,
land_world,
land_world_with_options,
land_world_and_crash,
drop_world,
expire_worlds,
open_world_locked,
world_query_locked,
world_call_locked,
world_diff_locked,
land_world_locked,
drop_world_locked
use Crypto
use Json
use Modb{Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Grants
use Modb.Ledger{Db, LedgerError, Schema, WriteMeta}
use Modb.Pager{BlockStore}
use Modb.Replay
use Modb.Table{Table, TableError}
use Modb.Tree{KeyDiff}

## Reserved internal buckets for speculative worlds and landing telemetry.
worlds_bucket = "_modb_worlds"
world_metrics_bucket = "_modb_world_metrics"
sendback_bucket = "_modb_world_sendbacks"

## Every failure returned by `Modb.World` operations.
enum WorldError
  LedgerFailure(LedgerError)
  GrantFailure(Grants.GrantError)
  WorldNotFound(id: Text)
  WorldAlreadyExists(id: Text)
  WorldNotOpen(id: Text, status: Text)
  WorldExpired(id: Text)
  UnknownQuery(name: Text)
  UnknownAction(name: Text)
  QueryFailed(query: Text, detail: Text)
  ActionRejected(action: Text, detail: Text)
  StaleRead(query: Text, args: Json, expected: Json, actual: Json)
  InvariantRejected(name: Text, detail: Text)
end

## Formats a `WorldError` as a human-readable diagnostic.
fn to_text(err: WorldError) : Text
  case err
    LedgerFailure(e): e.to_text
    GrantFailure(e): e.to_text
    WorldNotFound(id: id): "world '#{id}' not found"
    WorldAlreadyExists(id: id): "world '#{id}' already exists"
    WorldNotOpen(id: id, status: s): "world '#{id}' is not open (status: #{s})"
    WorldExpired(id: id): "world '#{id}' has expired"
    UnknownQuery(name: n): "unknown query '#{n}'"
    UnknownAction(name: n): "unknown action '#{n}'"
    QueryFailed(query: q, detail: d): "query '#{q}' failed: #{d}"
    ActionRejected(action: a, detail: d): "action '#{a}' rejected: #{d}"
    StaleRead(query: q, args: _, expected: _, actual: _): "stale read during landing for query '#{q}'"
    InvariantRejected(name: n, detail: d): "invariant '#{n}' violated: #{d}"
  end
end

## Application-registered read query executed on either a World's speculative `WriteTx`
## or the main-line replay `WriteTx` during landing.
struct QueryDef
  name: Text
  run: fn(WriteTx, Json) : Result(Json, Text)
end

## Application-registered approved write action executed inside a World and replayed at landing.
struct ActionDef
  name: Text
  run: fn(WriteTx, Json) : Result((WriteTx, Json), Text)
end

## Registry of approved queries and write actions available to Worlds.
struct Catalog
  queries: Map(Text, QueryDef)
  actions: Map(Text, ActionDef)
end

## One recorded step in a World's exact interleaved read + write history.
enum WorldStep
  ReadStep(query: Text, args: Json, answer_hash: Text, answer: Json)
  CallStep(action: Text, args: Json, reason: Text)
end

## Lifecycle status of a persisted World.
enum WorldStatus
  Open
  Landed(commit_txid: Int)
  Rejected(reason: Text)
  Dropped
end

## Persisted speculative workspace anchored to a pinned `base_pin_id` (`catalog_root`).
struct WorldRecord
  id: Text
  grant_id: Text
  principal: Text
  base_txid: Int
  base_pin_id: Text
  steps: List(WorldStep)
  status: WorldStatus
  created_at: Time
  expires_at: Time
end

## Persistent telemetry tracking landings, rejections, and needless send-backs
## (`design-ideas.md`: "count needless send-backs before choosing a finer read rule").
struct LandingMetrics
  total_landed: Int
  stale_read_rejections: Int
  invariant_rejections: Int
  action_rejections: Int
  grant_rejections: Int
  needless_send_backs: Int
end

## Stashed call-list hash from a principal's last stale-read send-back to detect needless retries.
struct SendBackMemory
  calls_hash: Text
end

## Protocol toggles for landing verification (defaults to Robert's strict decided protocol;
## non-strict modes exist strictly for TLA+ negative-control verification).
struct LandOptions
  validate_reads: Bool
  check_invariants_per_call: Bool
end

## Result returned when a World lands cleanly onto the main line.
struct LandResult
  world_id: Text
  commit_txid: Int
  calls_replayed: Int
  reads_verified: Int
  replies: List(Json)
  grant_chain: List(Text)
end

## JSON-friendly summary of one bucket's structural CoW diff.
struct BucketDiffSummary
  bucket: Text
  added: Int
  removed: Int
  modified: Int
end

struct LandAuditPayload
  world_id: Text
  base_txid: Int
  grant_id: Text
  grant_chain: List(Text)
  calls_replayed: Int
  reads_verified: Int
end

## Creates an empty query/action `Catalog`.
fn catalog() : Catalog
  Catalog(queries: {}, actions: {})
end

## Registers a named read query in `cat`.
fn with_query(cat: Catalog, name: Text, run: fn(WriteTx, Json) : Result(Json, Text)) : Catalog
  var next = cat
  next.queries = next.queries.set(name, QueryDef(name: name, run: run))
  next
end

## Registers a named approved write action in `cat`.
fn with_action(cat: Catalog, name: Text, run: fn(WriteTx, Json) : Result((WriteTx, Json), Text)) : Catalog
  var next = cat
  next.actions = next.actions.set(name, ActionDef(name: name, run: run))
  next
end

## Default strict landing policy: in-place answer-hash read validation AND per-call invariant checks.
fn strict_land_options() : LandOptions
  LandOptions(validate_reads: true, check_invariants_per_call: true)
end

## Zeroed initial landing metrics.
fn empty_metrics() : LandingMetrics
  LandingMetrics(
    total_landed: 0,
    stale_read_rejections: 0,
    invariant_rejections: 0,
    action_rejections: 0,
    grant_rejections: 0,
    needless_send_backs: 0
  )
end

## Typed table descriptor for `_modb_worlds`.
fn worlds_table() : Table(Text, WorldRecord)
  Table.text_key[WorldRecord](worlds_bucket)
end

fn metrics_table() : Table(Text, LandingMetrics)
  Table.text_key[LandingMetrics](world_metrics_bucket)
end

fn sendback_table() : Table(Text, SendBackMemory)
  Table.text_key[SendBackMemory](sendback_bucket)
end

fn wrap_table(res: Result(T, TableError)) : Result(T, WorldError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, WorldError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(Table.Storage(e))) end)
end

fn status_label(st: WorldStatus) : Text
  case st
    Open: "open"
    Landed(commit_txid: t): "landed(txid=#{t})"
    Rejected(reason: r): "rejected(#{r})"
    Dropped: "dropped"
  end
end

fn hash_json(val: Json) : Text
  Crypto.sha256(Json.encode(val).bytes).to_hex
end

fn hash_call_steps(steps: List(WorldStep)) : Text
  var parts = ["MODB-WORLD-CALLS-V1".bytes]
  for step in steps
    case step
      ReadStep(query: _, args: _, answer_hash: _, answer: _): Unit
      CallStep(action: act, args: args, reason: _): parts = parts.append(act.bytes).append(
        ":".bytes
      ).append(Json.encode(args).bytes).append("\n".bytes)
    end
  end
  Crypto.sha256(Bytes.join(parts)).to_hex
end

fn count_calls(steps: List(WorldStep)) : Int
  var n = 0
  for s in steps
    case s
      CallStep(action: _, args: _, reason: _): n += 1
      ReadStep(query: _, args: _, answer_hash: _, answer: _): Unit
    end
  end
  n
end

fn pin_name_for(world_id: Text) : Text
  "world:#{world_id}"
end

## Looks up a persisted World by ID.
fn get_world(store: Store, world_id: Text) : Result(Option(WorldRecord), WorldError)
  wrap_table(Table.get(store, worlds_table(), world_id))
end

## Lists all persisted Worlds.
fn list_worlds(store: Store) : Result(List(WorldRecord), WorldError)
  rows = try wrap_table(Table.all(store, worlds_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Returns cumulative landing and send-back metrics.
fn metrics(store: Store) : Result(LandingMetrics, WorldError)
  opt = try wrap_table(Table.get(store, metrics_table(), "global"))
  Ok(opt or empty_metrics())
end

fn load_open_world(store: Store, world_id: Text, now: Time) : Result(WorldRecord, WorldError)
  w_opt = try get_world(store, world_id)
  w = try w_opt.or_fail(WorldNotFound(id: world_id))
  case w.status
    Open: Unit
    Landed(commit_txid: _) | Rejected(reason: _) | Dropped: return Error(
      WorldNotOpen(id: world_id, status: status_label(w.status))
    )
  end
  if now > w.expires_at
    return Error(WorldExpired(id: world_id))
  end
  Ok(w)
end

## Reconstructs a World's isolated speculative `WriteTx` rooted at its pinned `base_catalog_root`,
## replaying the World's own recorded `CallStep`s in memory (zero disk writes).
fn build_speculative_tx(db: Db, cat: Catalog, world: WorldRecord) : Result(
  (WriteTx, Int),
  WorldError
)
  pin_opt = try wrap_modb(Modb.get_pin(Ledger.store(db), world.base_pin_id))
  pin = try pin_opt.or_fail(
    LedgerFailure(
      Ledger.AuditCorrupt(reason: "missing base pin '#{world.base_pin_id}' for world '#{world.id}'")
    )
  )
  var spec_tx = Modb.begin_write_from_root(Ledger.store(db), pin.catalog_root)
  for step in world.steps
    case step
      ReadStep(query: _, args: _, answer_hash: _, answer: _): Unit
      CallStep(action: act_name, args: args, reason: _):
        adef = try cat.actions.get(act_name).or_fail(UnknownAction(name: act_name))
        (next_tx, _reply) = try adef.run(spec_tx, args).map_error(fn(d)
          ActionRejected(action: act_name, detail: d)
        end)
        spec_tx = next_tx
    end
  end
  Ok((spec_tx, pin.catalog_root))
end

fn check_invariants_world(sc: Schema, tx: WriteTx) : Result(Unit, WorldError)
  case Ledger.check_invariants(sc, tx)
    Ok(_): Ok(Unit)
    Error(Ledger.InvariantViolation(name: n, detail: d)): Error(
      InvariantRejected(name: n, detail: d)
    )
    Error(other): Error(LedgerFailure(other))
  end
end

## Opens a new O(1) speculative World anchored to the current committed `catalog_root`.
## Pins `catalog_root` persistently in Layer 1 so the World survives requests and crashes.
fn open_world(db: Db, world_id: Text, grant_id: Text, now: Time, expires_at: Time) : Result(
  (Db, WorldRecord),
  WorldError
)
  if world_id.trim.empty?
    return Error(
      LedgerFailure(
        Ledger.TableFailure(Table.Storage(InvalidArgument(reason: "world_id cannot be empty")))
      )
    )
  end
  if expires_at <= now
    return Error(WorldExpired(id: world_id))
  end
  if (try get_world(Ledger.store(db), world_id)) is Some(_)
    return Error(WorldAlreadyExists(id: world_id))
  end

  tx0 = Modb.begin_write(Ledger.store(db))
  grant = try Grants.tx_verify_active(tx0, grant_id, now).map_error(fn(e) GrantFailure(e) end)
  pin_id = pin_name_for(world_id)
  (tx1, pin) = try wrap_modb(Modb.tx_pin_base_root(tx0, pin_id))
  world = WorldRecord(
    id: world_id,
    grant_id: grant_id,
    principal: grant.principal,
    base_txid: pin.txid,
    base_pin_id: pin_id,
    steps: [],
    status: Open,
    created_at: now,
    expires_at: expires_at
  )
  tx2 = try wrap_table(Table.put(tx1, worlds_table(), world_id, world))
  committed = try wrap_modb(Modb.commit(tx2))
  Ok((Ledger.update_store(db, committed), world))
end

## Executes a registered read query inside `world_id` (seeing `base_pin` plus the World's own
## prior calls) and records `(query, args, answer_hash, answer)` for landing validation.
fn world_query(db: Db, cat: Catalog, world_id: Text, query_name: Text, args: Json, now: Time) : Result(
  (Db, Json),
  WorldError
)
  world = try load_open_world(Ledger.store(db), world_id, now)
  check_tx = Modb.begin_write(Ledger.store(db))
  _ = try Grants.tx_verify_active(check_tx, world.grant_id, now).map_error(fn(e)
    GrantFailure(e)
  end)
  qdef = try cat.queries.get(query_name).or_fail(UnknownQuery(name: query_name))
  (spec_tx, _base_root) = try build_speculative_tx(db, cat, world)
  answer = try qdef.run(spec_tx, args).map_error(
    fn(d) QueryFailed(query: query_name, detail: d) end
  )
  step = ReadStep(query: query_name, args: args, answer_hash: hash_json(answer), answer: answer)

  var updated = world
  updated.steps = updated.steps.append(step)
  tx0 = Modb.begin_write(Ledger.store(db))
  tx1 = try wrap_table(Table.put(tx0, worlds_table(), world_id, updated))
  committed = try wrap_modb(Modb.commit(tx1))
  Ok((Ledger.update_store(db, committed), answer))
end

## Executes an approved write action speculatively inside `world_id` without touching the main line:
## verifies grant permission (without consuming main-line budget yet), runs the action, checks ALL
## schema invariants immediately, and appends `CallStep` to the World's trace.
fn world_call(
  db: Db,
  cat: Catalog,
  world_id: Text,
  action_name: Text,
  args: Json,
  reason: Text,
  now: Time
) : Result((Db, Json), WorldError)
  world = try load_open_world(Ledger.store(db), world_id, now)
  if db.schema.require_reason and reason.trim.empty?
    return Error(LedgerFailure(Ledger.InvalidMeta(reason: "reason is required by schema policy")))
  end
  check_tx = Modb.begin_write(Ledger.store(db))
  grant = try Grants.tx_verify_active(check_tx, world.grant_id, now).map_error(fn(e)
    GrantFailure(e)
  end)
  ## Pre-check that the grant permits `action_name` and has enough call budget for calls staged so far.
  var allowed? = false
  for a in grant.allowed_actions
    if a == action_name
      allowed? = true
    end
  end
  if not allowed?
    return Error(GrantFailure(Grants.ActionDenied(id: grant.id, action: action_name)))
  end
  if grant.used_calls + count_calls(world.steps) >= grant.max_calls
    return Error(
      GrantFailure(
        Grants.BudgetExhausted(id: grant.id, ancestor_id: grant.id, max_calls: grant.max_calls)
      )
    )
  end

  adef = try cat.actions.get(action_name).or_fail(UnknownAction(name: action_name))
  (spec_tx, _base_root) = try build_speculative_tx(db, cat, world)
  (spec_tx2, reply) = try adef.run(spec_tx, args).map_error(fn(d)
    ActionRejected(action: action_name, detail: d)
  end)
  try check_invariants_world(db.schema, spec_tx2)

  var updated = world
  updated.steps = updated.steps.append(CallStep(action: action_name, args: args, reason: reason))
  tx0 = Modb.begin_write(Ledger.store(db))
  tx1 = try wrap_table(Table.put(tx0, worlds_table(), world_id, updated))
  committed = try wrap_modb(Modb.commit(tx1))
  Ok((Ledger.update_store(db, committed), reply))
end

## Computes the structural CoW diff between `world_id`'s pinned base root and its speculative state
## (filtering internal `_modb_*` buckets).
fn world_diff(db: Db, cat: Catalog, world_id: Text) : Result(List(BucketDiffSummary), WorldError)
  w_opt = try get_world(Ledger.store(db), world_id)
  world = try w_opt.or_fail(WorldNotFound(id: world_id))
  (spec_tx, base_root) = try build_speculative_tx(db, cat, world)
  bdiffs = try wrap_modb(Modb.diff_tx_from_root(spec_tx, base_root))
  var out = []
  for bd in bdiffs
    if not bd.bucket.starts_with?("_modb_")
      var a = 0
      var r = 0
      var m = 0
      for ch in bd.changes
        case ch
          Added(key: _, value: _): a += 1
          Removed(key: _, value: _): r += 1
          Modified(key: _, old_value: _, new_value: _): m += 1
        end
      end
      out = out.append(BucketDiffSummary(bucket: bd.bucket, added: a, removed: r, modified: m))
    end
  end
  Ok(out)
end

fn record_rejection_and_unpin(db: Db, world: WorldRecord, err: WorldError) : Db
  tx0 = Modb.begin_write(Ledger.store(db))
  cur_m = case Table.tx_get(tx0, metrics_table(), "global")
    Ok(Some(m)): m
    Ok(None) | Error(_): empty_metrics()
  end
  var next_m = cur_m
  var stash_stale = false
  case err
    StaleRead(query: _, args: _, expected: _, actual: _):
      next_m.stale_read_rejections += 1
      stash_stale = true
    InvariantRejected(name: _, detail: _): next_m.invariant_rejections += 1
    ActionRejected(action: _, detail: _): next_m.action_rejections += 1
    GrantFailure(_): next_m.grant_rejections += 1
    LedgerFailure(_) | WorldNotFound(id: _) | WorldAlreadyExists(id: _) | WorldNotOpen(
      id: _,
      status: _
    ) | WorldExpired(id: _) | UnknownQuery(name: _) | UnknownAction(name: _) | QueryFailed(
      query: _,
      detail: _
    ): Unit
  end
  var rejected_w = world
  rejected_w.status = Rejected(reason: err.to_text)
  t1 = case Table.put(tx0, worlds_table(), world.id, rejected_w)
    Ok(t): t
    Error(_): return db
  end
  t2 = case Table.put(t1, metrics_table(), "global", next_m)
    Ok(t): t
    Error(_): return db
  end
  t3 = if stash_stale
    case Table.put(
      t2,
      sendback_table(),
      world.principal,
      SendBackMemory(calls_hash: hash_call_steps(world.steps))
    )
      Ok(t): t
      Error(_): t2
    end
  else
    t2
  end
  t4 = case Modb.tx_unpin_root(t3, world.base_pin_id)
    Ok(t): t
    Error(_): t3
  end
  case Modb.commit(t4)
    Ok(committed): Ledger.update_store(db, committed)
    Error(_): db
  end
end

fn replay_world_in_tx(
  tx0: WriteTx,
  sc: Schema,
  cat: Catalog,
  world: WorldRecord,
  schema_ver: Int,
  audit_seq: Int,
  commit_txid: Int,
  now: Time,
  opts: LandOptions
) : Result((WriteTx, LandResult), WorldError)
  grant0 = try Grants.tx_verify_active(tx0, world.grant_id, now).map_error(fn(e)
    GrantFailure(e)
  end)
  var cur_tx = tx0
  var replies = []
  var calls_replayed = 0
  var reads_verified = 0
  var final_chain = grant0.chain

  for step in world.steps
    case step
      ReadStep(query: qname, args: qargs, answer_hash: expected_hash, answer: expected_answer):
        if opts.validate_reads
          qdef = try cat.queries.get(qname).or_fail(UnknownQuery(name: qname))
          actual = try qdef.run(cur_tx, qargs).map_error(fn(d)
            QueryFailed(query: qname, detail: d)
          end)
          if hash_json(actual) != expected_hash
            return Error(
              StaleRead(query: qname, args: qargs, expected: expected_answer, actual: actual)
            )
          end
          reads_verified += 1
        end
      CallStep(action: act_name, args: act_args, reason: step_reason):
        (tx_auth, granted) = try Grants.tx_authorize(cur_tx, world.grant_id, act_name, now)
          .map_error(fn(e) GrantFailure(e) end)
        final_chain = granted.chain
        adef = try cat.actions.get(act_name).or_fail(UnknownAction(name: act_name))
        (tx_after, reply) = try adef.run(tx_auth, act_args).map_error(fn(d)
          ActionRejected(action: act_name, detail: d)
        end)
        if opts.check_invariants_per_call
          try check_invariants_world(sc, tx_after)
        end
        (tx_rec, _crec) = try wrap_table(
          Replay.tx_record_call(
            tx_after,
            schema_ver,
            Some(audit_seq),
            world.principal,
            Some(world.grant_id),
            granted.chain,
            Some(world.id),
            act_name,
            act_args,
            step_reason,
            now,
            Replay.OrigOk(reply: reply)
          )
        )
        cur_tx = tx_rec
        replies = replies.append(reply)
        calls_replayed += 1
    end
  end

  ## Update metrics (detecting needless send-backs when an agent's next world lands identical calls)
  cur_m = (try wrap_table(Table.tx_get(cur_tx, metrics_table(), "global"))) or empty_metrics()
  var next_m = cur_m
  next_m.total_landed += 1
  this_calls_hash = hash_call_steps(world.steps)
  case try wrap_table(Table.tx_get(cur_tx, sendback_table(), world.principal))
    Some(mem):
      if mem.calls_hash == this_calls_hash
        next_m.needless_send_backs += 1
      end
      cur_tx = try wrap_table(Table.delete(cur_tx, sendback_table(), world.principal))
    None: Unit
  end
  cur_tx = try wrap_table(Table.put(cur_tx, metrics_table(), "global", next_m))

  ## Mark world Landed and unpin its base catalog_root atomically in the same commit
  var landed_w = world
  landed_w.status = Landed(commit_txid: commit_txid)
  cur_tx = try wrap_table(Table.put(cur_tx, worlds_table(), world.id, landed_w))
  cur_tx = try wrap_modb(Modb.tx_unpin_root(cur_tx, world.base_pin_id))

  Ok((
    cur_tx,
    LandResult(
      world_id: world.id,
      commit_txid: commit_txid,
      calls_replayed: calls_replayed,
      reads_verified: reads_verified,
      replies: replies,
      grant_chain: final_chain
    )
  ))
end

fn map_ledger_err_world(le: LedgerError) : WorldError
  case le
    Ledger.InvariantViolation(name: n, detail: d): InvariantRejected(name: n, detail: d)
    Ledger.TableFailure(_) | Ledger.InvalidMeta(reason: _) | Ledger.SchemaTooNew(
      found: _,
      supported: _
    ) | Ledger.InvalidMigration(reason: _) | Ledger.AuditCorrupt(reason: _): LedgerFailure(le)
  end
end

## Lands `world_id` whole or not at all under `opts`, recording rejections and send-back telemetry.
fn land_world_with_options(
  db: Db,
  cat: Catalog,
  world_id: Text,
  reason: Text,
  now: Time,
  opts: LandOptions
) : Result((Db, LandResult), (Db, WorldError))
  world = case load_open_world(Ledger.store(db), world_id, now)
    Ok(w): w
    Error(e): return Error((db, e))
  end

  sc = db.schema
  schema_ver = db.state.version
  audit_seq = db.state.next_audit_seq
  expected_txid = Ledger.txid(db) + 1
  meta = WriteMeta(principal: world.principal, action: "land_world", reason: reason, at: now)
  payload = LandAuditPayload(
    world_id: world.id,
    base_txid: world.base_txid,
    grant_id: world.grant_id,
    grant_chain: [world.principal],
    calls_replayed: count_calls(world.steps),
    reads_verified: world.steps.size - count_calls(world.steps)
  ).to_json
  summary = "land world '#{world.id}' (base_txid=#{world.base_txid}, grant=#{world.grant_id})"

  case Ledger.transact(
    db,
    meta,
    summary,
    payload,
    map_ledger_err_world,
    fn(tx) replay_world_in_tx(tx, sc, cat, world, schema_ver, audit_seq, expected_txid, now, opts) end
  )
    Ok((next_db, res)): Ok((next_db, res))
    Error(err):
      db_recorded = record_rejection_and_unpin(db, world, err)
      Error((db_recorded, err))
  end
end

## Lands `world_id` whole or not at all using Robert's strict decided protocol
## (`validate_reads: true`, `check_invariants_per_call: true`).
fn land_world(db: Db, cat: Catalog, world_id: Text, reason: Text, now: Time) : Result(
  (Db, LandResult),
  (Db, WorldError)
)
  land_world_with_options(db, cat, world_id, reason, now, strict_land_options())
end

## Runs a real strict `land_world` commit up to a simulated power-cut boundary (`phase == 1` or `2`)
## for deterministic crash-fault testing.
fn land_world_and_crash(
  db: Db,
  cat: Catalog,
  world_id: Text,
  reason: Text,
  now: Time,
  phase: Int,
  rng: Random
) : Result(BlockStore, WorldError)
  world = try load_open_world(Ledger.store(db), world_id, now)
  sc = db.schema
  schema_ver = db.state.version
  audit_seq = db.state.next_audit_seq
  expected_txid = Ledger.txid(db) + 1
  meta = WriteMeta(principal: world.principal, action: "land_world", reason: reason, at: now)
  payload = LandAuditPayload(
    world_id: world.id,
    base_txid: world.base_txid,
    grant_id: world.grant_id,
    grant_chain: [world.principal],
    calls_replayed: count_calls(world.steps),
    reads_verified: world.steps.size - count_calls(world.steps)
  ).to_json
  summary = "land world '#{world.id}' (base_txid=#{world.base_txid}, grant=#{world.grant_id})"

  ## Replay into WriteTx first to ensure valid before crash boundary
  pre_tx = Modb.begin_write(Ledger.store(db))
  (_checked_tx, _res) = try replay_world_in_tx(
    pre_tx,
    sc,
    cat,
    world,
    schema_ver,
    audit_seq,
    expected_txid,
    now,
    strict_land_options()
  )

  Ledger.write_and_crash(
    db,
    meta,
    summary,
    payload,
    phase,
    rng,
    fn(tx)
      case replay_world_in_tx(
        tx,
        sc,
        cat,
        world,
        schema_ver,
        audit_seq,
        expected_txid,
        now,
        strict_land_options()
      )
        Ok((t1, _r)): Ok(t1)
        Error(e): Error(Table.Storage(TxAborted(reason: e.to_text)))
      end
    end
  ).map_error(fn(le) LedgerFailure(le) end)
end

## Abandons an open World in O(1), unpinning its base root so deferred pages reclaim immediately.
fn drop_world(db: Db, world_id: Text) : Result(Db, WorldError)
  w_opt = try get_world(Ledger.store(db), world_id)
  world = try w_opt.or_fail(WorldNotFound(id: world_id))
  case world.status
    Open: Unit
    Landed(commit_txid: _) | Rejected(reason: _) | Dropped: return Error(
      WorldNotOpen(id: world_id, status: status_label(world.status))
    )
  end
  var dropped = world
  dropped.status = Dropped
  tx0 = Modb.begin_write(Ledger.store(db))
  tx1 = try wrap_table(Table.put(tx0, worlds_table(), world_id, dropped))
  tx2 = try wrap_modb(Modb.tx_unpin_root(tx1, world.base_pin_id))
  committed = try wrap_modb(Modb.commit(tx2))
  Ok(Ledger.update_store(db, committed))
end

## Sweeps and drops all open Worlds whose `expires_at < now`, unpinning their base roots.
fn expire_worlds(db: Db, now: Time) : Result((Db, Int), WorldError)
  all_ws = try list_worlds(Ledger.store(db))
  var expired_ws = []
  for w in all_ws
    case w.status
      Open:
        if now > w.expires_at
          expired_ws = expired_ws.append(w)
        end
      Landed(commit_txid: _) | Rejected(reason: _) | Dropped: Unit
    end
  end
  return Ok((db, 0)) if expired_ws.empty?
  var cur_tx = Modb.begin_write(Ledger.store(db))
  for w in expired_ws
    var dropped = w
    dropped.status = Dropped
    cur_tx = try wrap_table(Table.put(cur_tx, worlds_table(), w.id, dropped))
    cur_tx = try wrap_modb(Modb.tx_unpin_root(cur_tx, w.base_pin_id))
  end
  committed = try wrap_modb(Modb.commit(cur_tx))
  Ok((Ledger.update_store(db, committed), expired_ws.size))
end

## Lock-coordinated `open_world` for multi-worker HTTP servers.
fn open_world_locked(
  files: Files,
  path: Text,
  sc: Schema,
  world_id: Text,
  grant_id: Text,
  now: Time,
  expires_at: Time
) : Result(WorldRecord, WorldError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      (_next, w) = try open_world(db, world_id, grant_id, now, expires_at)
      Ok(w)
    end
  )
end

## Lock-coordinated `world_query` for multi-worker HTTP servers.
fn world_query_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Catalog,
  world_id: Text,
  query_name: Text,
  args: Json,
  now: Time
) : Result(Json, WorldError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      (_next, ans) = try world_query(db, cat, world_id, query_name, args, now)
      Ok(ans)
    end
  )
end

## Lock-coordinated `world_call` for multi-worker HTTP servers.
fn world_call_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Catalog,
  world_id: Text,
  action_name: Text,
  args: Json,
  reason: Text,
  now: Time
) : Result(Json, WorldError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      (_next, reply) = try world_call(db, cat, world_id, action_name, args, reason, now)
      Ok(reply)
    end
  )
end

## Read-only lock-coordinated `world_diff` over `ReadFiles` + shared `flock`.
fn world_diff_locked(rf: ReadFiles, path: Text, sc: Schema, cat: Catalog, world_id: Text) : Result(
  List(BucketDiffSummary),
  WorldError
)
  Ledger.read_locked(
    rf,
    path,
    sc,
    fn(le) LedgerFailure(le) end,
    fn(db) world_diff(db, cat, world_id) end
  )
end

## Lock-coordinated `land_world` for multi-worker HTTP servers.
fn land_world_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Catalog,
  world_id: Text,
  reason: Text,
  now: Time
) : Result(LandResult, WorldError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      case land_world(db, cat, world_id, reason, now)
        Ok((_next, res)): Ok(res)
        Error((_db_rec, err)): Error(err)
      end
    end
  )
end

## Lock-coordinated `drop_world` for multi-worker HTTP servers.
fn drop_world_locked(files: Files, path: Text, sc: Schema, world_id: Text, now: Time) : Result(
  Unit,
  WorldError
)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      _ = try drop_world(db, world_id)
      Ok(Unit)
    end
  )
end

struct BoxRow
  val: Int
end

test "Modb.World unit: open, speculative query/call/diff, clean landing, and drop"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  boxes = Table.text_key[BoxRow]("boxes")

  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "seed box x=10", fn(tx) Table.put(tx, boxes, "x", BoxRow(val: 10)) end)
  ).with_invariant(
    Ledger.row_invariant(
      "non_negative",
      boxes,
      fn(k, row) if row.val < 0: Some("box '#{k}' < 0") else: None end
    )
  )

  cat = catalog().with_query(
    "get_x",
    fn(tx, _args)
      case Table.tx_get(tx, boxes, "x")
        Ok(Some(r)): Ok(r.val.to_json)
        Ok(None): Ok(0.to_json)
        Error(e): Error(e.to_text)
      end
    end
  ).with_action(
    "add_x",
    fn(tx, args)
      delta = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      cur = case Table.tx_get(tx, boxes, "x")
        Ok(Some(r)): r.val
        Ok(None): 0
        Error(e): return Error(e.to_text)
      end
      next_v = cur + delta
      t_next = try Table.put(tx, boxes, "x", BoxRow(val: next_v)).map_error(fn(e) e.to_text end)
      Ok((t_next, next_v.to_json))
    end
  )

  assert Ledger.open(files, "world-unit.modb", sc, t0) is Ok(db0)
  admin_meta = WriteMeta(principal: "admin:ada", action: "issue", reason: "init", at: t0)
  assert Grants.issue_root(
    db0,
    admin_meta,
    Grants.GrantSpec(
      id: "g1",
      principal: "agent:a",
      allowed_actions: ["add_x"],
      max_calls: 5,
      expires_at: t1
    )
  ) is
    Ok((db1, _))

  assert open_world(db1, "w1", "g1", t0, t1) is Ok((db2, _))
  assert world_query(db2, cat, "w1", "get_x", Json.Null, t0) is Ok((db3, ans0))
  assert ans0 == 10.to_json
  assert world_call(db3, cat, "w1", "add_x", 5.to_json, "bump", t0) is Ok((db4, rep1))
  assert rep1 == 15.to_json
  ## Main line is still 10 while world sees 15!
  assert Table.get(Ledger.store(db4), boxes, "x") == Ok(Some(BoxRow(val: 10)))
  assert world_query(db4, cat, "w1", "get_x", Json.Null, t0) is Ok((db5, ans1))
  assert ans1 == 15.to_json
  assert world_diff(db5, cat, "w1") ==
    Ok([BucketDiffSummary(bucket: "boxes", added: 0, removed: 0, modified: 1)])

  ## Landing commits atomically, unpins base root, and updates main line to 15
  assert land_world(db5, cat, "w1", "apply bump", t0) is Ok((db6, lres))
  assert lres.calls_replayed == 1 and lres.reads_verified == 2
  assert Table.get(Ledger.store(db6), boxes, "x") == Ok(Some(BoxRow(val: 15)))
  assert Modb.list_pins(Ledger.store(db6)) == Ok([])
  assert Ledger.verify_all(db6) is Ok(_)
end
