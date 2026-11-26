## MoDB Layer 4: Speculative Multi-Agent Worlds, In-Place Answer-Hash Read Validation,
## Per-Call Invariant Enforcement, and Whole-or-Nothing Replay Landing.
##
## Directly implements Robert's decided rules from `design.md` (§6–§7) and `models/README.md`
## (`Replay.tla` Answers 1 & 3 + needless send-back telemetry, `Worlds.tla` Option 3).
module Modb.World
expose WorldError(..),
ReadScope(..),
QueryDef(..),
ActionDef(..),
Catalog(..),
WorldStep(..),
WorldStatus(..),
WorldRecord(..),
WorldLink(..),
LandingMetrics(..),
WorldTelemetry(..),
PrincipalStarvation(..),
PriorityTicket(..),
LandOptions(..),
LandResult(..),
ChildLandResult(..),
LandOutcome(..),
BucketDiffSummary(..),
worlds_bucket,
world_metrics_bucket,
world_links_bucket,
world_attrs_bucket,
world_telemetry_bucket,
world_fairness_bucket,
to_text,
catalog,
with_query,
with_scoped_query,
with_key_scoped_query,
with_keys_scoped_query,
with_range_scoped_query,
with_dynamic_scoped_query,
with_action,
strict_land_options,
empty_metrics,
empty_telemetry,
worlds_table,
get_world,
list_worlds,
get_world_link,
list_child_worlds,
metrics,
telemetry,
starvation_count,
list_priority_tickets,
open_world,
open_child_world,
world_query,
world_call,
world_diff,
land_world,
land_world_with_options,
land_world_fair,
land_child_world,
claim_priority,
land_world_and_crash,
drop_world,
expire_worlds,
open_world_locked,
open_child_world_locked,
world_query_locked,
world_call_locked,
world_diff_locked,
land_world_locked,
land_world_fair_locked,
land_child_world_locked,
claim_priority_locked,
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
world_links_bucket = "_modb_world_links"
world_attrs_bucket = "_modb_world_attrs"
world_telemetry_bucket = "_modb_world_telemetry"
world_fairness_bucket = "_modb_world_fairness"

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

## Fine-grained read dependency descriptor returned by dynamic scope resolvers for `O(diff)`
## key-set and half-open range `[start_key, end_key)` read-validation skipping.
enum ReadScope
  BucketScope(buckets: List(Text))
  KeysScope(bucket: Text, keys: List(Bytes))
  RangeScope(bucket: Text, start_key: Option(Bytes), end_key: Option(Bytes))
  MultiScope(scopes: List(ReadScope))
end

## Application-registered read query executed on either a World's speculative `WriteTx`
## or the main-line replay `WriteTx` during landing.
## When `read_buckets` is non-empty, landing skips re-executing this query when none of
## `read_buckets` changed; when `resolve_scope` is present, landing checks `O(diff)` key/range
## overlap via `Modb.diff_bucket_roots` before falling back to re-execution.
struct QueryDef
  name: Text
  read_buckets: List(Text)
  resolve_scope: Option(fn(Json) : Result(ReadScope, Text))
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
  total_reads_verified: Int
  total_reads_skipped: Int
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
  reads_skipped: Int
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

## Additive Milestone 10 counters stored separately in `_modb_world_telemetry`.
struct WorldTelemetry
  key_level_reads_skipped: Int
  bucket_level_reads_skipped: Int
  child_worlds_landed: Int
  fairness_tickets_issued: Int
  fairness_deferrals: Int
  starved_worlds_rescued: Int
end

## Parent/child fork linkage stored in `_modb_world_links` keyed by `child_world_id`.
struct WorldLink
  child_world_id: Text
  parent_world_id: Text
  parent_step_watermark: Int
  merged_into_parent?: Bool
end

struct StepAttribution
  start_idx: Int
  end_idx: Int
  world_id: Text
  grant_id: Text
  principal: Text
end

struct StepAttributionList
  entries: List(StepAttribution)
end

## Result returned when a nested Child World merges atomically into its Parent World.
struct ChildLandResult
  child_world_id: Text
  parent_world_id: Text
  calls_merged: Int
  reads_verified: Int
  reads_skipped: Int
  replies: List(Json)
  grant_chain: List(Text)
end

## Per-principal consecutive `StaleRead` counter stored under `"starve:<principal>"`.
struct PrincipalStarvation
  principal: Text
  consecutive_stale: Int
  last_stale_at: Time
end

## Short-TTL priority ticket stored under `"ticket:<world_id>"` in `_modb_world_fairness`.
struct PriorityTicket
  world_id: Text
  principal: Text
  buckets: List(Text)
  granted_at: Time
  expires_at: Time
end

enum FairnessRecord
  StarvationRec(PrincipalStarvation)
  TicketRec(PriorityTicket)
end

## Outcome of fairness-aware landing via `land_world_fair`.
enum LandOutcome
  LandedOk(result: LandResult)
  DeferredByFairness(ticket: PriorityTicket, retry_after: Time)
end

enum SkipKind
  SkipNone
  SkipBucket
  SkipKeyLevel
end

## Creates an empty query/action `Catalog`.
fn catalog() : Catalog
  Catalog(queries: {}, actions: {})
end

## Registers a named read query in `cat` (conservatively depends on all data buckets).
fn with_query(cat: Catalog, name: Text, run: fn(WriteTx, Json) : Result(Json, Text)) : Catalog
  var next = cat
  next.queries = next.queries.set(
    name,
    QueryDef(name: name, read_buckets: [], resolve_scope: None, run: run)
  )
  next
end

## Registers a named read query in `cat` with its exact `read_buckets` dependency set,
## enabling O(1) CoW-diff read-validation skipping during World landing when none of
## `read_buckets` changed on the main line (`design.md` §6: "Asking again costs what changed").
fn with_scoped_query(
  cat: Catalog,
  name: Text,
  read_buckets: List(Text),
  run: fn(WriteTx, Json) : Result(Json, Text)
) : Catalog
  var next = cat
  next.queries = next.queries.set(
    name,
    QueryDef(name: name, read_buckets: read_buckets, resolve_scope: None, run: run)
  )
  next
end

## Registers a single-key scoped query enabling `O(diff)` key-level read skipping within a bucket.
fn with_key_scoped_query(
  cat: Catalog,
  name: Text,
  bucket: Text,
  key_for_args: fn(Json) : Result(Bytes, Text),
  run: fn(WriteTx, Json) : Result(Json, Text)
) : Catalog
  var next = cat
  next.queries = next.queries.set(
    name,
    QueryDef(
      name: name,
      read_buckets: [bucket],
      resolve_scope: Some(fn(args)
        k = try key_for_args(args)
        Ok(KeysScope(bucket: bucket, keys: [k]))
      end),
      run: run
    )
  )
  next
end

## Registers a multi-key scoped query enabling `O(diff)` key-set read skipping within a bucket.
fn with_keys_scoped_query(
  cat: Catalog,
  name: Text,
  bucket: Text,
  keys_for_args: fn(Json) : Result(List(Bytes), Text),
  run: fn(WriteTx, Json) : Result(Json, Text)
) : Catalog
  var next = cat
  next.queries = next.queries.set(
    name,
    QueryDef(
      name: name,
      read_buckets: [bucket],
      resolve_scope: Some(fn(args)
        ks = try keys_for_args(args)
        Ok(KeysScope(bucket: bucket, keys: ks))
      end),
      run: run
    )
  )
  next
end

## Registers a half-open range `[start_key, end_key)` scoped query for `O(diff)` range skipping.
fn with_range_scoped_query(
  cat: Catalog,
  name: Text,
  bucket: Text,
  range_for_args: fn(Json) : Result((Option(Bytes), Option(Bytes)), Text),
  run: fn(WriteTx, Json) : Result(Json, Text)
) : Catalog
  var next = cat
  next.queries = next.queries.set(
    name,
    QueryDef(
      name: name,
      read_buckets: [bucket],
      resolve_scope: Some(fn(args)
        r = try range_for_args(args)
        Ok(RangeScope(bucket: bucket, start_key: r.0, end_key: r.1))
      end),
      run: run
    )
  )
  next
end

## Registers a general dynamically-scoped query returning an arbitrary `ReadScope`.
fn with_dynamic_scoped_query(
  cat: Catalog,
  name: Text,
  read_buckets: List(Text),
  resolve_scope: fn(Json) : Result(ReadScope, Text),
  run: fn(WriteTx, Json) : Result(Json, Text)
) : Catalog
  var next = cat
  next.queries = next.queries.set(
    name,
    QueryDef(name: name, read_buckets: read_buckets, resolve_scope: Some(resolve_scope), run: run)
  )
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
    needless_send_backs: 0,
    total_reads_verified: 0,
    total_reads_skipped: 0
  )
end

## Zeroed Milestone 10 extended telemetry.
fn empty_telemetry() : WorldTelemetry
  WorldTelemetry(
    key_level_reads_skipped: 0,
    bucket_level_reads_skipped: 0,
    child_worlds_landed: 0,
    fairness_tickets_issued: 0,
    fairness_deferrals: 0,
    starved_worlds_rescued: 0
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

fn world_links_table() : Table(Text, WorldLink)
  Table.text_key[WorldLink](world_links_bucket)
end

fn world_attrs_table() : Table(Text, StepAttributionList)
  Table.text_key[StepAttributionList](world_attrs_bucket)
end

fn world_telemetry_table() : Table(Text, WorldTelemetry)
  Table.text_key[WorldTelemetry](world_telemetry_bucket)
end

fn world_fairness_table() : Table(Text, FairnessRecord)
  Table.text_key[FairnessRecord](world_fairness_bucket)
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

## Returns cumulative Milestone 10 key-level skip, child-world, and fairness telemetry.
fn telemetry(store: Store) : Result(WorldTelemetry, WorldError)
  opt = try wrap_table(Table.get(store, world_telemetry_table(), "global"))
  Ok(opt or empty_telemetry())
end

## Looks up a Child World's parent link record (if `world_id` is or was a Child World).
fn get_world_link(store: Store, world_id: Text) : Result(Option(WorldLink), WorldError)
  wrap_table(Table.get(store, world_links_table(), world_id))
end

## Lists all child Worlds forked from `parent_world_id`.
fn list_child_worlds(store: Store, parent_world_id: Text) : Result(List(WorldRecord), WorldError)
  link_rows = try wrap_table(Table.all(store, world_links_table()))
  var out = []
  for (_cid, lnk) in link_rows
    if lnk.parent_world_id == parent_world_id
      if (try get_world(store, lnk.child_world_id)) is Some(w)
        out = out.append(w)
      end
    end
  end
  Ok(out)
end

## Returns the consecutive `StaleRead` rejection count recorded for `principal`.
fn starvation_count(store: Store, principal: Text) : Result(Int, WorldError)
  case try wrap_table(Table.get(store, world_fairness_table(), "starve:#{principal}"))
    Some(StarvationRec(s)): Ok(s.consecutive_stale)
    Some(TicketRec(_)) | None: Ok(0)
  end
end

## Lists active (unexpired) fairness `PriorityTicket`s at `now`.
fn list_priority_tickets(store: Store, now: Time) : Result(List(PriorityTicket), WorldError)
  rows = try wrap_table(Table.all(store, world_fairness_table()))
  var out = []
  for (_k, rec) in rows
    case rec
      TicketRec(t) if now <= t.expires_at: out = out.append(t)
      TicketRec(_) | StarvationRec(_): Unit
    end
  end
  Ok(out)
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

fn steps_prefix(steps: List(WorldStep), max_steps_opt: Option(Int)) : List(WorldStep)
  case max_steps_opt
    Some(n) if n <= 0: []
    Some(n) if n < steps.size: steps.take(n)
    Some(_) | None: steps
  end
end

## Reconstructs a World's isolated speculative `WriteTx` at `max_steps_opt` (`None` = all steps),
## recursively applying any unmerged Parent World chain down to the shared pinned root.
fn build_speculative_tx_at(
  db: Db,
  cat: Catalog,
  world: WorldRecord,
  max_steps_opt: Option(Int),
  depth: Int
) : Result((WriteTx, Int), WorldError)
  if depth > 16
    return Error(
      LedgerFailure(Ledger.AuditCorrupt(reason: "world parent chain depth exceeded at '#{world.id}'"))
    )
  end
  store = Ledger.store(db)
  pin_opt = try wrap_modb(Modb.get_pin(store, world.base_pin_id))
  pin = try pin_opt.or_fail(
    LedgerFailure(
      Ledger.AuditCorrupt(reason: "missing base pin '#{world.base_pin_id}' for world '#{world.id}'")
    )
  )
  var spec_tx = case try get_world_link(store, world.id)
    Some(lnk) if not lnk.merged_into_parent?:
      p_opt = try get_world(store, lnk.parent_world_id)
      parent_w = try p_opt.or_fail(WorldNotFound(id: lnk.parent_world_id))
      (ptx, _proot) = try build_speculative_tx_at(
        db,
        cat,
        parent_w,
        Some(lnk.parent_step_watermark),
        depth + 1
      )
      ptx
    Some(_) | None: Modb.begin_write_from_root(store, pin.catalog_root)
  end
  for step in steps_prefix(world.steps, max_steps_opt)
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

## Reconstructs a World's full isolated speculative `WriteTx` (zero disk writes).
fn build_speculative_tx(db: Db, cat: Catalog, world: WorldRecord) : Result(
  (WriteTx, Int),
  WorldError
)
  build_speculative_tx_at(db, cat, world, None, 0)
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

## Opens a Nested Child World forked from an open `parent_world_id` at its current step
## watermark under an attenuated `child_grant_id` (`<= parent.grant_id` and `expires_at <= parent`).
fn open_child_world(
  db: Db,
  parent_world_id: Text,
  child_world_id: Text,
  child_grant_id: Text,
  now: Time,
  expires_at: Time
) : Result((Db, WorldRecord), WorldError)
  if child_world_id.trim.empty?
    return Error(
      LedgerFailure(
        Ledger.TableFailure(Table.Storage(InvalidArgument(reason: "child_world_id cannot be empty")))
      )
    )
  end
  parent_w = try load_open_world(Ledger.store(db), parent_world_id, now)
  if expires_at <= now
    return Error(WorldExpired(id: child_world_id))
  end
  if expires_at > parent_w.expires_at
    return Error(
      GrantFailure(
        Grants.WideningDenied(
          field: "expires_at",
          detail: "child world expires_at exceeds parent '#{parent_world_id}'"
        )
      )
    )
  end
  if (try get_world(Ledger.store(db), child_world_id)) is Some(_)
    return Error(WorldAlreadyExists(id: child_world_id))
  end

  tx0 = Modb.begin_write(Ledger.store(db))
  _pg = try Grants.tx_verify_active(tx0, parent_w.grant_id, now).map_error(fn(e) GrantFailure(e) end)
  cg = try Grants.tx_verify_active(tx0, child_grant_id, now).map_error(fn(e) GrantFailure(e) end)
  is_sub? = try Grants.tx_check_descendant_or_same(tx0, parent_w.grant_id, child_grant_id)
    .map_error(fn(e) GrantFailure(e) end)
  if not is_sub?
    return Error(
      GrantFailure(
        Grants.WideningDenied(
          field: "parent_grant",
          detail: "grant '#{child_grant_id}' is not attenuated from parent grant '#{parent_w
            .grant_id}'"
        )
      )
    )
  end

  pin_id = pin_name_for(child_world_id)
  (tx1, pin) = try wrap_modb(Modb.tx_pin_existing_root(tx0, pin_id, parent_w.base_pin_id))
  child_w = WorldRecord(
    id: child_world_id,
    grant_id: child_grant_id,
    principal: cg.principal,
    base_txid: pin.txid,
    base_pin_id: pin_id,
    steps: [],
    status: Open,
    created_at: now,
    expires_at: expires_at
  )
  link = WorldLink(
    child_world_id: child_world_id,
    parent_world_id: parent_world_id,
    parent_step_watermark: parent_w.steps.size,
    merged_into_parent?: false
  )
  tx2 = try wrap_table(Table.put(tx1, worlds_table(), child_world_id, child_w))
  tx3 = try wrap_table(Table.put(tx2, world_links_table(), child_world_id, link))
  committed = try wrap_modb(Modb.commit(tx3))
  Ok((Ledger.update_store(db, committed), child_w))
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

## Computes the structural CoW diff for `world_id` (filtering internal `_modb_*` buckets).
## For an unmerged Nested Child World, isolates the diff relative to its Parent World fork point.
fn world_diff(db: Db, cat: Catalog, world_id: Text) : Result(List(BucketDiffSummary), WorldError)
  store = Ledger.store(db)
  w_opt = try get_world(store, world_id)
  world = try w_opt.or_fail(WorldNotFound(id: world_id))
  bdiffs = case try get_world_link(store, world_id)
    Some(lnk) if not lnk.merged_into_parent?:
      parent_opt = try get_world(store, lnk.parent_world_id)
      parent_w = try parent_opt.or_fail(WorldNotFound(id: lnk.parent_world_id))
      (parent_tx, _pr) = try build_speculative_tx_at(
        db,
        cat,
        parent_w,
        Some(lnk.parent_step_watermark),
        0
      )
      (child_tx, _cr) = try build_speculative_tx_at(db, cat, world, None, 0)
      try wrap_modb(Modb.diff_txs(parent_tx, child_tx))
    Some(_) | None:
      (spec_tx, base_root) = try build_speculative_tx(db, cat, world)
      try wrap_modb(Modb.diff_tx_from_root(spec_tx, base_root))
  end
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

fn release_ticket_tx(tx: WriteTx, world_id: Text) : WriteTx
  case Table.tx_get(tx, world_fairness_table(), "ticket:#{world_id}")
    Ok(Some(TicketRec(_))):
      case Table.delete(tx, world_fairness_table(), "ticket:#{world_id}")
        Ok(next): next
        Error(_): tx
      end
    Ok(Some(StarvationRec(_))) | Ok(None) | Error(_): tx
  end
end

fn cascade_close_descendants_tx(
  tx0: WriteTx,
  root_world_id: Text,
  open_status: WorldStatus,
  merged_status: WorldStatus
) : WriteTx
  links = case Table.tx_scan(tx0, world_links_table(), None, None, 0)
    Ok(rows): rows.map(fn(p) p.1 end)
    Error(_): []
  end
  var cur_tx = tx0
  var queue = [root_world_id]
  var seen = Set.empty.add(root_world_id)
  var idx = 0
  while idx < queue.size
    pid = queue.get(idx) or stop "cascade world idx"
    idx += 1
    for lnk in links
      if lnk.parent_world_id == pid and not seen.has?(lnk.child_world_id)
        seen = seen.add(lnk.child_world_id)
        queue = queue.append(lnk.child_world_id)
        cur_tx = release_ticket_tx(cur_tx, lnk.child_world_id)
        case Table.tx_get(cur_tx, worlds_table(), lnk.child_world_id)
          Ok(Some(cw)):
            var next_cw = cw
            case cw.status
              Open:
                next_cw.status = open_status
                cur_tx = case Table.put(cur_tx, worlds_table(), cw.id, next_cw)
                  Ok(t): t
                  Error(_): cur_tx
                end
                cur_tx = case Modb.tx_unpin_root(cur_tx, cw.base_pin_id)
                  Ok(t): t
                  Error(_): cur_tx
                end
              Landed(commit_txid: ctx) if ctx == 0:
                next_cw.status = merged_status
                cur_tx = case Table.put(cur_tx, worlds_table(), cw.id, next_cw)
                  Ok(t): t
                  Error(_): cur_tx
                end
              Landed(commit_txid: _) | Rejected(reason: _) | Dropped: Unit
            end
          Ok(None) | Error(_): Unit
        end
      end
    end
  end
  cur_tx
end

fn record_rejection_and_unpin(db: Db, world: WorldRecord, err: WorldError, now: Time) : Db
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
    var t3_a = case Table.put(
      t2,
      sendback_table(),
      world.principal,
      SendBackMemory(calls_hash: hash_call_steps(world.steps))
    )
      Ok(t): t
      Error(_): t2
    end
    prev_starve = case Table.tx_get(t3_a, world_fairness_table(), "starve:#{world.principal}")
      Ok(Some(StarvationRec(s))): s.consecutive_stale
      Ok(Some(TicketRec(_))) | Ok(None) | Error(_): 0
    end
    case Table.put(
      t3_a,
      world_fairness_table(),
      "starve:#{world.principal}",
      StarvationRec(
        PrincipalStarvation(
          principal: world.principal,
          consecutive_stale: prev_starve + 1,
          last_stale_at: now
        )
      )
    )
      Ok(t): t
      Error(_): t3_a
    end
  else
    t2
  end
  t3_rel = release_ticket_tx(t3, world.id)
  t4 = case Modb.tx_unpin_root(t3_rel, world.base_pin_id)
    Ok(t): t
    Error(_): t3_rel
  end
  cascade_st = Rejected(reason: "ancestor world '#{world.id}' rejected: #{err.to_text}")
  t5 = cascade_close_descendants_tx(t4, world.id, cascade_st, cascade_st)
  case Modb.commit(t5)
    Ok(committed): Ledger.update_store(db, committed)
    Error(_): db
  end
end

fn is_world_bookkeeping_bucket?(bucket: Text) : Bool
  bucket == worlds_bucket or
    bucket == world_metrics_bucket or
    bucket == sendback_bucket or
    bucket == world_links_bucket or
    bucket == world_attrs_bucket or
    bucket == world_telemetry_bucket or
    bucket == world_fairness_bucket or
    bucket == Modb.pins_bucket or
    bucket == "_modb_read_log" or
    bucket == "_modb_read_meta"
end

## Computes the set of non-world-bookkeeping buckets whose B+Tree root page IDs changed on the
## main line between `world.base_pin_id` and `store`'s current `catalog_root` (O(catalog diff)).
fn compute_ext_changed_buckets(store: Store, world: WorldRecord) : Result(Set(Text), WorldError)
  pin_opt = try wrap_modb(Modb.get_pin(store, world.base_pin_id))
  pin = try pin_opt.or_fail(
    LedgerFailure(
      Ledger.AuditCorrupt(reason: "missing base pin '#{world.base_pin_id}' for world '#{world.id}'")
    )
  )
  all_changed = try wrap_modb(
    Modb.changed_buckets_between_roots(store, pin.catalog_root, Modb.catalog_root(store))
  )
  var ext = Set.empty
  for b in all_changed
    if not is_world_bookkeeping_bucket?(b)
      ext = ext.add(b)
    end
  end
  Ok(ext)
end

fn collect_scope_buckets(scope: ReadScope, acc: Set(Text)) : Set(Text)
  case scope
    BucketScope(buckets: bs):
      var cur = acc
      for b in bs
        cur = cur.add(b)
      end
      cur
    KeysScope(bucket: b, keys: _): acc.add(b)
    RangeScope(bucket: b, start_key: _, end_key: _): acc.add(b)
    MultiScope(scopes: ss):
      var cur = acc
      for sub in ss
        cur = collect_scope_buckets(sub, cur)
      end
      cur
  end
end

## For any bucket in `ext_changed` queried via a key- or range-scoped `QueryDef`, computes the
## exact set of changed keys between `world.base_pin_id` and live `catalog_root` via O(diff) B+Tree
## node diff (`Modb.diff_bucket_roots`).
fn compute_ext_changed_keys(
  store: Store,
  world: WorldRecord,
  cat: Catalog,
  ext_changed: Set(Text)
) : Result(Map(Text, Set(Bytes)), WorldError)
  return Ok({}) if ext_changed.empty?
  var needed = Set.empty
  for step in world.steps
    case step
      CallStep(action: _, args: _, reason: _): Unit
      ReadStep(query: qname, args: qargs, answer_hash: _, answer: _):
        case cat.queries.get(qname)
          Some(qdef):
            case qdef.resolve_scope
              Some(resolver):
                for b in qdef.read_buckets
                  if ext_changed.has?(b)
                    needed = needed.add(b)
                  end
                end
                case resolver(qargs)
                  Ok(scope):
                    for sb in collect_scope_buckets(scope, Set.empty).to_list
                      if ext_changed.has?(sb)
                        needed = needed.add(sb)
                      end
                    end
                  Error(_): Unit
                end
              None: Unit
            end
          None: Unit
        end
    end
  end
  return Ok({}) if needed.empty?
  pin_opt = try wrap_modb(Modb.get_pin(store, world.base_pin_id))
  pin = try pin_opt.or_fail(
    LedgerFailure(
      Ledger.AuditCorrupt(reason: "missing base pin '#{world.base_pin_id}' for world '#{world.id}'")
    )
  )
  live_root = Modb.catalog_root(store)
  var key_map = {}
  for b in needed.to_list
    kdiffs = try wrap_modb(Modb.diff_bucket_roots(store, pin.catalog_root, live_root, b))
    var kset = Set.empty
    for kd in kdiffs
      case kd
        Added(key: k, value: _) | Removed(key: k, value: _) | Modified(
          key: k,
          old_value: _,
          new_value: _
        ): kset = kset.add(k)
      end
    end
    key_map = key_map.set(b, kset)
  end
  Ok(key_map)
end

## Sound O(1) CoW-diff read-skip check:
## - If `ext_changed` is empty (zero external data drift since `open_world`), every deterministic
##   query yields the identical answer on `cur_tx` as on `spec_tx`.
## - Otherwise, a scoped query (`not qdef.read_buckets.empty?`) may skip re-execution iff none of
##   its declared `read_buckets` changed externally AND (if prior `CallStep`s ran in this World)
##   none of `read_buckets` was dirtied inside `cur_tx`.
fn can_skip_read_validation?(
  qdef: QueryDef,
  ext_changed: Set(Text),
  cur_tx: WriteTx,
  calls_replayed: Int
) : Bool
  return true if ext_changed.empty?
  return false if qdef.read_buckets.empty?
  for b in qdef.read_buckets
    return false if ext_changed.has?(b)
    if calls_replayed > 0 and Modb.tx_bucket_dirty?(cur_tx, b)
      return false
    end
  end
  true
end

fn classify_scope_skip(
  scope: ReadScope,
  ext_changed: Set(Text),
  ext_changed_keys: Map(Text, Set(Bytes)),
  cur_tx: WriteTx,
  calls_replayed: Int
) : (Bool, Bool)
  case scope
    BucketScope(buckets: bs):
      return (false, false) if bs.empty?
      for b in bs
        return (false, false) if ext_changed.has?(b)
        return (false, false) if calls_replayed > 0 and Modb.tx_bucket_dirty?(cur_tx, b)
      end
      (true, false)
    KeysScope(bucket: b, keys: ks):
      return (false, false) if calls_replayed > 0 and Modb.tx_bucket_dirty?(cur_tx, b)
      return (true, false) if not ext_changed.has?(b)
      case ext_changed_keys.get(b)
        None: (false, false)
        Some(kset):
          for k in ks
            return (false, false) if kset.has?(k)
          end
          (true, true)
      end
    RangeScope(bucket: b, start_key: start_opt, end_key: end_opt):
      return (false, false) if calls_replayed > 0 and Modb.tx_bucket_dirty?(cur_tx, b)
      return (true, false) if not ext_changed.has?(b)
      case ext_changed_keys.get(b)
        None: (false, false)
        Some(kset):
          for ck in kset.to_list
            after_start = case start_opt
              Some(sk): ck >= sk
              None: true
            end
            before_end = case end_opt
              Some(ek): ck < ek
              None: true
            end
            return (false, false) if after_start and before_end
          end
          (true, true)
      end
    MultiScope(scopes: ss):
      var used_key = false
      for sub in ss
        (ok, uk) = classify_scope_skip(sub, ext_changed, ext_changed_keys, cur_tx, calls_replayed)
        return (false, false) if not ok
        if uk
          used_key = true
        end
      end
      (true, used_key)
  end
end

fn classify_read_skip(
  qdef: QueryDef,
  qargs: Json,
  ext_changed: Set(Text),
  ext_changed_keys: Map(Text, Set(Bytes)),
  cur_tx: WriteTx,
  calls_replayed: Int
) : SkipKind
  return SkipBucket if ext_changed.empty?
  case qdef.resolve_scope
    Some(resolver):
      case resolver(qargs)
        Error(_): SkipNone
        Ok(scope):
          (ok, uk) = classify_scope_skip(scope, ext_changed, ext_changed_keys, cur_tx, calls_replayed)
          if not ok
            SkipNone
          else if uk
            SkipKeyLevel
          else
            SkipBucket
          end
      end
    None:
      if can_skip_read_validation?(qdef, ext_changed, cur_tx, calls_replayed)
        SkipBucket
      else
        SkipNone
      end
  end
end

fn find_step_attr(attrs: List(StepAttribution), idx: Int) : Option(StepAttribution)
  for a in attrs
    if idx >= a.start_idx and idx < a.end_idx
      return Some(a)
    end
  end
  None
end

fn check_open_unmerged_child(store: Store, parent_world_id: Text) : Result(Bool, WorldError)
  rows = try wrap_table(Table.all(store, world_links_table()))
  for (_cid, lnk) in rows
    if lnk.parent_world_id == parent_world_id and not lnk.merged_into_parent?
      if (try get_world(store, lnk.child_world_id)) is Some(cw)
        if cw.status is Open
          return Ok(true)
        end
      end
    end
  end
  Ok(false)
end

fn replay_world_in_tx(
  tx0: WriteTx,
  sc: Schema,
  cat: Catalog,
  world: WorldRecord,
  ext_changed: Set(Text),
  ext_changed_keys: Map(Text, Set(Bytes)),
  attrs: List(StepAttribution),
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
  var reads_skipped = 0
  var bucket_skipped = 0
  var key_skipped = 0
  var final_chain = grant0.chain

  for idx in 0..world.steps.size
    step = world.steps.get(idx) or stop "world step index"
    case step
      ReadStep(query: qname, args: qargs, answer_hash: expected_hash, answer: expected_answer):
        if opts.validate_reads
          qdef = try cat.queries.get(qname).or_fail(UnknownQuery(name: qname))
          case classify_read_skip(qdef, qargs, ext_changed, ext_changed_keys, cur_tx, calls_replayed)
            SkipBucket:
              reads_verified += 1
              reads_skipped += 1
              bucket_skipped += 1
            SkipKeyLevel:
              reads_verified += 1
              reads_skipped += 1
              key_skipped += 1
            SkipNone:
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
        end
      CallStep(action: act_name, args: act_args, reason: step_reason):
        (eff_world_id, eff_grant_id, eff_principal) = case find_step_attr(attrs, idx)
          Some(a): (a.world_id, a.grant_id, a.principal)
          None: (world.id, world.grant_id, world.principal)
        end
        (tx_auth, granted) = try Grants.tx_authorize(cur_tx, eff_grant_id, act_name, now)
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
            eff_principal,
            Some(eff_grant_id),
            granted.chain,
            Some(eff_world_id),
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
  next_m.total_reads_verified += reads_verified
  next_m.total_reads_skipped += reads_skipped
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

  ## Clear principal starvation counter and any priority ticket owned by this World
  case try wrap_table(Table.tx_get(cur_tx, world_fairness_table(), "starve:#{world.principal}"))
    Some(_): cur_tx = try wrap_table(
      Table.delete(cur_tx, world_fairness_table(), "starve:#{world.principal}")
    )
    None: Unit
  end
  var rescued = 0
  case try wrap_table(Table.tx_get(cur_tx, world_fairness_table(), "ticket:#{world.id}"))
    Some(TicketRec(_)):
      cur_tx = try wrap_table(Table.delete(cur_tx, world_fairness_table(), "ticket:#{world.id}"))
      rescued = 1
    Some(StarvationRec(_)) | None: Unit
  end

  ## Update Milestone 10 extended telemetry
  cur_t = (try wrap_table(Table.tx_get(cur_tx, world_telemetry_table(), "global"))) or
    empty_telemetry()
  var next_t = cur_t
  next_t.key_level_reads_skipped += key_skipped
  next_t.bucket_level_reads_skipped += bucket_skipped
  next_t.starved_worlds_rescued += rescued
  cur_tx = try wrap_table(Table.put(cur_tx, world_telemetry_table(), "global", next_t))

  ## Update any merged descendant child Worlds' final commit_txid
  cur_tx = cascade_close_descendants_tx(
    cur_tx,
    world.id,
    Landed(commit_txid: commit_txid),
    Landed(commit_txid: commit_txid)
  )

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
      reads_skipped: reads_skipped,
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
  store = Ledger.store(db)
  world = case load_open_world(store, world_id, now)
    Ok(w): w
    Error(e): return Error((db, e))
  end
  case get_world_link(store, world_id)
    Ok(Some(lnk)) if not lnk.merged_into_parent?:
      return Error((
        db,
        WorldNotOpen(id: world_id, status: "child_of(#{lnk.parent_world_id}): use land_child_world")
      ))
    Ok(_): Unit
    Error(e): return Error((db, e))
  end
  case check_open_unmerged_child(store, world_id)
    Ok(true): return Error((db, WorldNotOpen(id: world_id, status: "has_open_children")))
    Ok(false): Unit
    Error(e): return Error((db, e))
  end
  ext_changed = case compute_ext_changed_buckets(store, world)
    Ok(s): s
    Error(e): return Error((db, e))
  end
  ext_changed_keys = case compute_ext_changed_keys(store, world, cat, ext_changed)
    Ok(km): km
    Error(e): return Error((db, e))
  end
  attrs = case Table.get(store, world_attrs_table(), world_id)
    Ok(Some(al)): al.entries
    Ok(None): []
    Error(te): return Error((db, LedgerFailure(Ledger.TableFailure(te))))
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
    fn(tx)
      replay_world_in_tx(
        tx,
        sc,
        cat,
        world,
        ext_changed,
        ext_changed_keys,
        attrs,
        schema_ver,
        audit_seq,
        expected_txid,
        now,
        opts
      )
    end
  )
    Ok((next_db, res)): Ok((next_db, res))
    Error(err):
      db_recorded = record_rejection_and_unpin(db, world, err, now)
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

## Grants a short-TTL (`1..60s`) priority fairness ticket to `world_id` once its principal has
## suffered at least `min_stale_threshold` consecutive `StaleRead` rejections.
fn claim_priority(
  db: Db,
  world_id: Text,
  buckets: List(Text),
  min_stale_threshold: Int,
  hold_seconds: Int,
  now: Time
) : Result((Db, PriorityTicket), WorldError)
  if hold_seconds <= 0 or hold_seconds > 60
    return Error(
      ActionRejected(action: "claim_priority", detail: "hold_seconds must be within 1..60")
    )
  end
  var clean_buckets = []
  for b in buckets
    bt = b.trim
    if not bt.empty? and not clean_buckets.contains?(bt)
      clean_buckets = clean_buckets.append(bt)
    end
  end
  if clean_buckets.empty?
    return Error(ActionRejected(action: "claim_priority", detail: "buckets cannot be empty"))
  end
  store = Ledger.store(db)
  world = try load_open_world(store, world_id, now)
  scount = try starvation_count(store, world.principal)
  threshold = if min_stale_threshold > 0: min_stale_threshold else: 1
  if scount < threshold
    return Error(
      ActionRejected(
        action: "claim_priority",
        detail: "principal '#{world.principal}' stale count #{scount} < threshold #{threshold}"
      )
    )
  end
  ticket = PriorityTicket(
    world_id: world.id,
    principal: world.principal,
    buckets: clean_buckets,
    granted_at: now,
    expires_at: now + hold_seconds.seconds
  )
  meta = WriteMeta(
    principal: world.principal,
    action: "claim_priority",
    reason: "priority fairness ticket for #{world.id}",
    at: now
  )
  Ledger.transact(
    db,
    meta,
    "claim fairness ticket for '#{world.id}'",
    ticket.to_json,
    map_ledger_err_world,
    fn(tx)
      t1 = try wrap_table(
        Table.put(tx, world_fairness_table(), "ticket:#{world.id}", TicketRec(ticket))
      )
      cur_t = (try wrap_table(Table.tx_get(t1, world_telemetry_table(), "global"))) or
        empty_telemetry()
      var next_t = cur_t
      next_t.fairness_tickets_issued += 1
      t2 = try wrap_table(Table.put(t1, world_telemetry_table(), "global", next_t))
      Ok((t2, ticket))
    end
  )
end

## Fairness-aware World landing: if another open World holds an active `PriorityTicket` on a
## bucket modified by `world_id`, leaves `world_id` Open/pinned and returns `DeferredByFairness`.
fn land_world_fair(
  db: Db,
  cat: Catalog,
  world_id: Text,
  reason: Text,
  now: Time
) : Result((Db, LandOutcome), (Db, WorldError))
  store = Ledger.store(db)
  world = case load_open_world(store, world_id, now)
    Ok(w): w
    Error(e): return Error((db, e))
  end
  tickets = case list_priority_tickets(store, now)
    Ok(ts): ts.filter(fn(t) t.world_id != world_id end)
    Error(e): return Error((db, e))
  end
  if not tickets.empty? and count_calls(world.steps) > 0
    diffs = case world_diff(db, cat, world_id)
      Ok(ds): ds
      Error(e): return Error((db, e))
    end
    for t in tickets
      if diffs.any?(fn(d) t.buckets.contains?(d.bucket) end)
        meta = WriteMeta(
          principal: world.principal,
          action: "fairness_defer",
          reason: "deferred '#{world_id}' for priority ticket '#{t.world_id}'",
          at: now
        )
        db_next = case Ledger.transact(
          db,
          meta,
          "fairness deferral for '#{world_id}'",
          t.to_json,
          map_ledger_err_world,
          fn(tx)
            cur_t = (try wrap_table(Table.tx_get(tx, world_telemetry_table(), "global"))) or
              empty_telemetry()
            var next_t = cur_t
            next_t.fairness_deferrals += 1
            tx1 = try wrap_table(Table.put(tx, world_telemetry_table(), "global", next_t))
            Ok((tx1, Unit))
          end
        )
          Ok((nd, _)): nd
          Error(_): db
        end
        return Ok((db_next, DeferredByFairness(ticket: t, retry_after: t.expires_at)))
      end
    end
  end
  case land_world(db, cat, world_id, reason, now)
    Ok((next_db, res)): Ok((next_db, LandedOk(result: res)))
    Error((db_rec, err)): Error((db_rec, err))
  end
end

fn build_child_changed_keys(
  tx: WriteTx,
  ext_buckets: Set(Text)
) : Map(Text, Set(Bytes))
  var out = {}
  for b in ext_buckets.to_list
    if not Modb.tx_bucket_deleted?(tx, b)
      var kset = Set.empty
      for k in Modb.tx_touched_puts(tx, b)
        kset = kset.add(k)
      end
      for k in Modb.tx_touched_deletes(tx, b)
        kset = kset.add(k)
      end
      out = out.set(b, kset)
    end
  end
  out
end

fn merge_step_attributions(
  parent_base_off: Int,
  child_w: WorldRecord,
  child_attrs: List(StepAttribution),
  existing_parent_attrs: List(StepAttribution)
) : List(StepAttribution)
  var out = existing_parent_attrs
  var i = 0
  while i < child_w.steps.size
    case find_step_attr(child_attrs, i)
      Some(ga):
        out = out.append(
          StepAttribution(
            start_idx: parent_base_off + ga.start_idx,
            end_idx: parent_base_off + ga.end_idx,
            world_id: ga.world_id,
            grant_id: ga.grant_id,
            principal: ga.principal
          )
        )
        i = ga.end_idx
      None:
        run_start = i
        while i < child_w.steps.size and find_step_attr(child_attrs, i) is None
          i += 1
        end
        out = out.append(
          StepAttribution(
            start_idx: parent_base_off + run_start,
            end_idx: parent_base_off + i,
            world_id: child_w.id,
            grant_id: child_w.grant_id,
            principal: child_w.principal
          )
        )
    end
  end
  out
end

## Validates and atomically merges an open Nested Child World into its still-open Parent World,
## preserving `StepAttribution` so final parent landing enforces child grant revocation, budgets,
## and `Replay.ExcludeGrant` / `Replay.ExcludeWorld` lineage.
fn land_child_world(
  db: Db,
  cat: Catalog,
  child_world_id: Text,
  reason: Text,
  now: Time
) : Result((Db, ChildLandResult), (Db, WorldError))
  store = Ledger.store(db)
  child_w = case load_open_world(store, child_world_id, now)
    Ok(w): w
    Error(e): return Error((db, e))
  end
  lnk = case get_world_link(store, child_world_id)
    Ok(Some(l)) if not l.merged_into_parent?: l
    Ok(Some(_)) | Ok(None): return Error((
      db,
      WorldNotOpen(id: child_world_id, status: "not_unmerged_child")
    ))
    Error(e): return Error((db, e))
  end
  case check_open_unmerged_child(store, child_world_id)
    Ok(true): return Error((db, WorldNotOpen(id: child_world_id, status: "has_open_children")))
    Ok(false): Unit
    Error(e): return Error((db, e))
  end
  parent_w = case load_open_world(store, lnk.parent_world_id, now)
    Ok(w): w
    Error(e): return Error((db, e))
  end
  if db.schema.require_reason and reason.trim.empty?
    return Error((
      db,
      LedgerFailure(Ledger.InvalidMeta(reason: "reason is required by schema policy"))
    ))
  end

  parent_attrs = case Table.get(store, world_attrs_table(), parent_w.id)
    Ok(Some(al)): al.entries
    Ok(None): []
    Error(te): return Error((db, LedgerFailure(Ledger.TableFailure(te))))
  end
  child_attrs = case Table.get(store, world_attrs_table(), child_w.id)
    Ok(Some(al)): al.entries
    Ok(None): []
    Error(te): return Error((db, LedgerFailure(Ledger.TableFailure(te))))
  end

  ## Check grants + cumulative unlanded parent/child call budgets without mutating committed state
  var scratch_g = Modb.begin_write(store)
  pg = case Grants.tx_verify_active(scratch_g, parent_w.grant_id, now)
    Ok(g): g
    Error(ge):
      err = GrantFailure(ge)
      return Error((record_rejection_and_unpin(db, child_w, err, now), err))
  end
  _cg = case Grants.tx_verify_active(scratch_g, child_w.grant_id, now)
    Ok(g): g
    Error(ge):
      err = GrantFailure(ge)
      return Error((record_rejection_and_unpin(db, child_w, err, now), err))
  end
  for pidx in 0..parent_w.steps.size
    ps = parent_w.steps.get(pidx) or stop "parent step idx"
    case ps
      ReadStep(query: _, args: _, answer_hash: _, answer: _): Unit
      CallStep(action: act_name, args: _, reason: _):
        egid = case find_step_attr(parent_attrs, pidx)
          Some(a): a.grant_id
          None: parent_w.grant_id
        end
        case Grants.tx_authorize(scratch_g, egid, act_name, now)
          Ok((next_sg, _)): scratch_g = next_sg
          Error(ge):
            err = GrantFailure(ge)
            return Error((record_rejection_and_unpin(db, child_w, err, now), err))
        end
    end
  end

  ## Replay Parent post-fork steps with write-tracking to compute exact Parent changes since fork
  p_fork_tx = case build_speculative_tx_at(db, cat, parent_w, Some(lnk.parent_step_watermark), 0)
    Ok((t, _)): t
    Error(e): return Error((record_rejection_and_unpin(db, child_w, e, now), e))
  end
  var p_now_tx = Modb.tx_clear_touched(p_fork_tx)
  for ps in parent_w.steps.drop(lnk.parent_step_watermark)
    case ps
      ReadStep(query: _, args: _, answer_hash: _, answer: _): Unit
      CallStep(action: act_name, args: act_args, reason: _):
        adef = case cat.actions.get(act_name)
          Some(a): a
          None:
            err = UnknownAction(name: act_name)
            return Error((record_rejection_and_unpin(db, child_w, err, now), err))
        end
        case adef.run(p_now_tx, act_args)
          Ok((next_ptx, _)): p_now_tx = next_ptx
          Error(d):
            err = ActionRejected(action: act_name, detail: d)
            return Error((record_rejection_and_unpin(db, child_w, err, now), err))
        end
    end
  end
  var parent_ext_buckets = Set.empty
  for b in Modb.tx_touched_buckets(p_now_tx)
    if not is_world_bookkeeping_bucket?(b)
      parent_ext_buckets = parent_ext_buckets.add(b)
    end
  end
  parent_ext_keys = build_child_changed_keys(p_now_tx, parent_ext_buckets)

  ## Validate child reads (with O(diff) key/range skipping) and replay child calls onto Parent tx
  var cur_tx = p_now_tx
  var replies = []
  var calls_merged = 0
  var reads_verified = 0
  var reads_skipped = 0
  var bucket_skipped = 0
  var key_skipped = 0
  var final_chain = pg.chain

  for cidx in 0..child_w.steps.size
    step = child_w.steps.get(cidx) or stop "child step idx"
    case step
      ReadStep(query: qname, args: qargs, answer_hash: expected_hash, answer: expected_answer):
        qdef = case cat.queries.get(qname)
          Some(qd): qd
          None:
            err = UnknownQuery(name: qname)
            return Error((record_rejection_and_unpin(db, child_w, err, now), err))
        end
        case classify_read_skip(
          qdef,
          qargs,
          parent_ext_buckets,
          parent_ext_keys,
          cur_tx,
          calls_merged
        )
          SkipBucket:
            reads_verified += 1
            reads_skipped += 1
            bucket_skipped += 1
          SkipKeyLevel:
            reads_verified += 1
            reads_skipped += 1
            key_skipped += 1
          SkipNone:
            actual = case qdef.run(cur_tx, qargs)
              Ok(a): a
              Error(d):
                err = QueryFailed(query: qname, detail: d)
                return Error((record_rejection_and_unpin(db, child_w, err, now), err))
            end
            if hash_json(actual) != expected_hash
              err = StaleRead(
                query: qname,
                args: qargs,
                expected: expected_answer,
                actual: actual
              )
              return Error((record_rejection_and_unpin(db, child_w, err, now), err))
            end
            reads_verified += 1
        end
      CallStep(action: act_name, args: act_args, reason: _):
        eff_gid = case find_step_attr(child_attrs, cidx)
          Some(a): a.grant_id
          None: child_w.grant_id
        end
        case Grants.tx_authorize(scratch_g, eff_gid, act_name, now)
          Ok((next_sg, g)):
            scratch_g = next_sg
            final_chain = g.chain
          Error(ge):
            err = GrantFailure(ge)
            return Error((record_rejection_and_unpin(db, child_w, err, now), err))
        end
        adef = case cat.actions.get(act_name)
          Some(a): a
          None:
            err = UnknownAction(name: act_name)
            return Error((record_rejection_and_unpin(db, child_w, err, now), err))
        end
        (next_tx, reply) = case adef.run(cur_tx, act_args)
          Ok(p): p
          Error(d):
            err = ActionRejected(action: act_name, detail: d)
            return Error((record_rejection_and_unpin(db, child_w, err, now), err))
        end
        case check_invariants_world(db.schema, next_tx)
          Ok(Unit): Unit
          Error(e): return Error((record_rejection_and_unpin(db, child_w, e, now), e))
        end
        cur_tx = next_tx
        replies = replies.append(reply)
        calls_merged += 1
    end
  end

  ## Persist atomic child merge into Parent World + step attribution + telemetry + unpin
  meta = WriteMeta(
    principal: child_w.principal,
    action: "land_child_world",
    reason: reason,
    at: now
  )
  payload = Json.Object({
    "child_world_id": Json.String(child_w.id),
    "parent_world_id": Json.String(parent_w.id),
    "calls_merged": Json.int(calls_merged),
    "reads_verified": Json.int(reads_verified),
    "reads_skipped": Json.int(reads_skipped)
  })
  summary = "merge child world '#{child_w.id}' into parent '#{parent_w.id}'"
  case Ledger.transact(
    db,
    meta,
    summary,
    payload,
    map_ledger_err_world,
    fn(tx)
      base_off = parent_w.steps.size
      var next_parent = parent_w
      next_parent.steps = next_parent.steps.concat(child_w.steps)
      merged_attrs = merge_step_attributions(base_off, child_w, child_attrs, parent_attrs)
      var next_lnk = lnk
      next_lnk.merged_into_parent? = true
      var done_child = child_w
      done_child.status = Landed(commit_txid: 0)

      t1 = try wrap_table(Table.put(tx, worlds_table(), parent_w.id, next_parent))
      t2 = try wrap_table(Table.put(t1, worlds_table(), child_w.id, done_child))
      t3 = try wrap_table(Table.put(t2, world_links_table(), child_w.id, next_lnk))
      t4 = if merged_attrs.empty?
        t3
      else
        try wrap_table(
          Table.put(t3, world_attrs_table(), parent_w.id, StepAttributionList(entries: merged_attrs))
        )
      end

      cur_m = (try wrap_table(Table.tx_get(t4, metrics_table(), "global"))) or empty_metrics()
      var next_m = cur_m
      next_m.total_reads_verified += reads_verified
      next_m.total_reads_skipped += reads_skipped
      t5 = try wrap_table(Table.put(t4, metrics_table(), "global", next_m))

      cur_t = (try wrap_table(Table.tx_get(t5, world_telemetry_table(), "global"))) or
        empty_telemetry()
      var next_t = cur_t
      next_t.child_worlds_landed += 1
      next_t.key_level_reads_skipped += key_skipped
      next_t.bucket_level_reads_skipped += bucket_skipped
      t6 = try wrap_table(Table.put(t5, world_telemetry_table(), "global", next_t))

      t7 = release_ticket_tx(t6, child_w.id)
      t8 = try wrap_modb(Modb.tx_unpin_root(t7, child_w.base_pin_id))

      Ok((
        t8,
        ChildLandResult(
          child_world_id: child_w.id,
          parent_world_id: parent_w.id,
          calls_merged: calls_merged,
          reads_verified: reads_verified,
          reads_skipped: reads_skipped,
          replies: replies,
          grant_chain: final_chain
        )
      ))
    end
  )
    Ok((next_db, res)): Ok((next_db, res))
    Error(err): Error((record_rejection_and_unpin(db, child_w, err, now), err))
  end
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
  store = Ledger.store(db)
  world = try load_open_world(store, world_id, now)
  ext_changed = try compute_ext_changed_buckets(store, world)
  ext_changed_keys = try compute_ext_changed_keys(store, world, cat, ext_changed)
  attrs = case Table.get(store, world_attrs_table(), world_id)
    Ok(Some(al)): al.entries
    Ok(None): []
    Error(te): return Error(LedgerFailure(Ledger.TableFailure(te)))
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

  ## Replay into WriteTx first to ensure valid before crash boundary
  pre_tx = Modb.begin_write(store)
  (_checked_tx, _res) = try replay_world_in_tx(
    pre_tx,
    sc,
    cat,
    world,
    ext_changed,
    ext_changed_keys,
    attrs,
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
        ext_changed,
        ext_changed_keys,
        attrs,
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

## Abandons an open World (and any open descendant Child Worlds) in O(1), unpinning base roots.
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
  tx2 = release_ticket_tx(tx1, world_id)
  tx3 = try wrap_modb(Modb.tx_unpin_root(tx2, world.base_pin_id))
  tx4 = cascade_close_descendants_tx(tx3, world_id, Dropped, Dropped)
  committed = try wrap_modb(Modb.commit(tx4))
  Ok(Ledger.update_store(db, committed))
end

## Sweeps and drops all open Worlds whose `expires_at < now`, cascading to children and unpinning.
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
    case try wrap_table(Table.tx_get(cur_tx, worlds_table(), w.id))
      Some(latest_w) if latest_w.status is Open:
        var dropped = latest_w
        dropped.status = Dropped
        cur_tx = try wrap_table(Table.put(cur_tx, worlds_table(), latest_w.id, dropped))
        cur_tx = release_ticket_tx(cur_tx, latest_w.id)
        cur_tx = try wrap_modb(Modb.tx_unpin_root(cur_tx, latest_w.base_pin_id))
        cur_tx = cascade_close_descendants_tx(cur_tx, latest_w.id, Dropped, Dropped)
      Some(_) | None: Unit
    end
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

## Lock-coordinated `open_child_world` for multi-worker HTTP servers.
fn open_child_world_locked(
  files: Files,
  path: Text,
  sc: Schema,
  parent_world_id: Text,
  child_world_id: Text,
  child_grant_id: Text,
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
      (_next, w) = try open_child_world(
        db,
        parent_world_id,
        child_world_id,
        child_grant_id,
        now,
        expires_at
      )
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

## Lock-coordinated `land_world_fair` for multi-worker HTTP servers.
fn land_world_fair_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Catalog,
  world_id: Text,
  reason: Text,
  now: Time
) : Result(LandOutcome, WorldError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      case land_world_fair(db, cat, world_id, reason, now)
        Ok((_next, res)): Ok(res)
        Error((_db_rec, err)): Error(err)
      end
    end
  )
end

## Lock-coordinated `land_child_world` for multi-worker HTTP servers.
fn land_child_world_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Catalog,
  child_world_id: Text,
  reason: Text,
  now: Time
) : Result(ChildLandResult, WorldError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      case land_child_world(db, cat, child_world_id, reason, now)
        Ok((_next, res)): Ok(res)
        Error((_db_rec, err)): Error(err)
      end
    end
  )
end

## Lock-coordinated `claim_priority` for multi-worker HTTP servers.
fn claim_priority_locked(
  files: Files,
  path: Text,
  sc: Schema,
  world_id: Text,
  buckets: List(Text),
  min_stale_threshold: Int,
  hold_seconds: Int,
  now: Time
) : Result(PriorityTicket, WorldError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      (_next, ticket) = try claim_priority(
        db,
        world_id,
        buckets,
        min_stale_threshold,
        hold_seconds,
        now
      )
      Ok(ticket)
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
