## MoDB Milestone 4: Upgrade-Aware History Replay, Selective Undo, Bug-Fix Replay,
## and Proposal-First History Adoption (`design.md` §4–§5 & §7 Decision 3, Experiment 18).
##
## Every replayable call records its exact order, schema version, caller, grant lineage,
## action, arguments, arrival time, and original outcome (accepted reply or refusal).
## Replays execute completely offline on an isolated in-memory store through historical
## migrations, yielding a structured `ReplayProposal` listing every diverged/refused/newly
## accepted call and exact row diffs for explicit human/Admin acceptance.
module Modb.Replay
expose replay_calls_bucket,
replay_by_principal_bucket,
replay_meta_bucket,
replay_proposals_bucket,
replay_baseline_bucket,
replay_baseline_pin_id,
ReplayError(..),
OriginalOutcome(..),
CallRecord(..),
ReplayBaseline(..),
KeyDelta(..),
BucketDelta(..),
ReplayAction(..),
ReplayCatalog(..),
ReplayFilter(..),
CallOutcome(..),
BucketRowDiff(..),
ReplaySummary(..),
ProposalStatus(..),
ReplayProposal(..),
to_text,
catalog,
with_action,
with_timed_action,
with_versioned_action,
with_versioned_timed_action,
with_override_action,
with_override_timed_action,
with_override_for_version,
with_version_invariants,
get_baseline,
pin_baseline,
pin_baseline_locked,
tx_record_call,
record_refused,
execute,
execute_recording_refusals,
list_calls,
list_calls_tail,
calls_by_principal,
call_count,
get_proposal,
list_proposals,
preview_replay,
simulate_replay,
accept_proposal,
accept_proposal_and_crash,
discard_proposal,
simulate_replay_locked,
get_proposal_locked,
list_proposals_locked,
accept_proposal_locked,
discard_proposal_locked,
compact_with_baseline,
compact_with_baseline_default
use Json
use Modb{Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Export{PortableSnapshot}
use Modb.Grants
use Modb.Ledger{Db, Invariant, LedgerError, Migration, Schema, WriteMeta}
use Modb.Pager{BlockStore, sim_empty}
use Modb.Table{Index, Table, TableError}
use Modb.Tree{KeyDiff}

## Reserved internal buckets for replayable call history, baseline pin, and proposals.
replay_calls_bucket = "_modb_replay_calls"
replay_by_principal_bucket = "_modb_replay_by_principal"
replay_meta_bucket = "_modb_replay_meta"
replay_proposals_bucket = "_modb_replay_proposals"
replay_baseline_bucket = "_modb_replay_baseline"
replay_baseline_pin_id = "_modb_replay_baseline"

## Every failure returned by `Modb.Replay` operations.
enum ReplayError
  LedgerFailure(LedgerError)
  ExportFailure(Export.ExportError)
  GrantFailure(Grants.GrantError)
  ProposalNotFound(id: Text)
  ProposalAlreadyExists(id: Text)
  ProposalNotPending(id: Text, status: Text)
  ProposalStale(
    id: Text,
    expected_audit_seq: Int,
    actual_audit_seq: Int,
    expected_call_seq: Int,
    actual_call_seq: Int
  )
  UnknownReplayAction(action: Text, schema_version: Int)
  MissingReplayMigration(version: Int)
  ReplayActionRejected(action: Text, detail: Text)
  ReplayFailed(detail: Text)
end

## Formats a `ReplayError` as a human-readable diagnostic.
fn to_text(err: ReplayError) : Text
  case err
    LedgerFailure(e): e.to_text
    ExportFailure(e): e.to_text
    GrantFailure(e): e.to_text
    ProposalNotFound(id: id): "replay proposal '#{id}' not found"
    ProposalAlreadyExists(id: id): "replay proposal '#{id}' already exists"
    ProposalNotPending(id: id, status: s): "replay proposal '#{id}' is not pending (status: #{s})"
    ProposalStale(
      id: id,
      expected_audit_seq: ea,
      actual_audit_seq: aa,
      expected_call_seq: ec,
      actual_call_seq: ac
    ): "replay proposal '#{id}' is stale (audit #{ea} -> #{aa}, calls #{ec} -> #{ac}); re-simulate"
    UnknownReplayAction(action: a, schema_version: v): "no replay handler registered for action '#{a}' at schema v#{v}"
    MissingReplayMigration(version: v): "missing schema migration for version v#{v} during replay"
    ReplayActionRejected(action: a, detail: d): "action '#{a}' rejected: #{d}"
    ReplayFailed(detail: d): "replay failed: #{d}"
  end
end

## Original execution outcome recorded when a call first ran on the live database.
enum OriginalOutcome
  OrigOk(reply: Json)
  OrigRefused(error: Text)
end

## Immutable replayable call record persisted atomically with each action (or refusal).
struct CallRecord
  seq: Int
  audit_seq: Option(Int)
  schema_version: Int
  principal: Text
  grant_id: Option(Text)
  grant_chain: List(Text)
  world_id: Option(Text)
  action: Text
  args: Json
  reason: Text
  at: Time
  outcome: OriginalOutcome
end

struct ReplayMeta
  next_call_seq: Int
end

## Versioned or overridden replay action handler receiving uncommitted `WriteTx`, `args`, and call `at`.
struct ReplayAction
  run: fn(WriteTx, Json, Time) : Result((WriteTx, Json), Text)
end

## Registry of current, historical-version, and bug-fix override action handlers for replay.
struct ReplayCatalog
  actions: Map(Text, ReplayAction)
  versioned_actions: Map(Text, ReplayAction)
  overrides: Map(Text, ReplayAction)
  version_overrides: Map(Text, ReplayAction)
  version_invariants: Map(Int, List(Invariant))
end

## Filter selecting which historical calls to omit or truncate when simulating an alternate history.
enum ReplayFilter
  ReplayAll
  ExcludePrincipal(principal: Text)
  ExcludeGrant(grant_id: Text)
  ExcludeSeqs(seqs: List(Int))
  ExcludeWorld(world_id: Text)
  StopBeforeSeq(seq: Int)
end

## Per-call divergence result comparing original history against the simulated alternate history.
enum CallOutcome
  Excluded(seq: Int, action: Text, principal: Text)
  Unchanged(seq: Int, action: Text, principal: Text)
  ReplyChanged(seq: Int, action: Text, principal: Text, old_reply: Json, new_reply: Json)
  NowRefused(seq: Int, action: Text, principal: Text, old_reply: Json, new_error: Text)
  NowInvariantBlocked(
    seq: Int,
    action: Text,
    principal: Text,
    old_reply: Json,
    invariant: Text,
    detail: Text
  )
  StillRefused(seq: Int, action: Text, principal: Text, old_error: Text, new_error: Text)
  NowAccepted(seq: Int, action: Text, principal: Text, old_error: Text, new_reply: Json)
end

## Row-level diff summary for one user bucket (`live -> proposed`).
struct BucketRowDiff
  bucket: Text
  added: Int
  removed: Int
  modified: Int
end

## Aggregate divergence counters for a simulated replay run.
struct ReplaySummary
  total_calls: Int
  excluded: Int
  unchanged: Int
  reply_changed: Int
  now_refused: Int
  now_invariant_blocked: Int
  still_refused: Int
  now_accepted: Int
  migrations_run: List(Int)
end

## Lifecycle status of a persisted `ReplayProposal`.
enum ProposalStatus
  Pending
  Accepted(commit_txid: Int, accepted_by: Text, accepted_at: Time)
  Discarded(discarded_by: Text, discarded_at: Time)
end

## CoW-pinned starting baseline used after compaction/import so delta replay preserves prior state.
struct ReplayBaseline
  pin_id: Text
  schema_version: Int
  txid: Int
  pinned_at: Time
end

## One hex-encoded key upsert (`Some`) or deletion (`None`) in a delta-based `ReplayProposal`.
struct KeyDelta
  key_hex: Text
  value_hex: Option(Text)
end

## Compact per-bucket row delta (`live -> proposed`) produced by O(diff) CoW baseline replay.
struct BucketDelta
  bucket: Text
  ops: List(KeyDelta)
end

## Structured candidate history produced by offline replay for human/Admin review before acceptance.
struct ReplayProposal
  id: Text
  description: Text
  filter: ReplayFilter
  base_live_txid: Int
  base_audit_seq: Int
  base_call_seq: Int
  target_schema_version: Int
  created_by: Text
  created_at: Time
  status: ProposalStatus
  summary: ReplaySummary
  outcomes: List(CallOutcome)
  bucket_diffs: List(BucketRowDiff)
  proposed_state: PortableSnapshot
  proposed_delta: Option(List(BucketDelta))
end

struct AcceptProposalAuditPayload
  proposal_id: Text
  description: Text
  filter: ReplayFilter
  base_audit_seq: Int
  base_call_seq: Int
  summary: ReplaySummary
  bucket_diffs: List(BucketRowDiff)
end

fn version_key(ver: Int, action: Text) : Text
  "v#{ver}:#{action}"
end

## Creates an empty `ReplayCatalog`.
fn catalog() : ReplayCatalog
  ReplayCatalog(
    actions: {},
    versioned_actions: {},
    overrides: {},
    version_overrides: {},
    version_invariants: {}
  )
end

## Registers a default (timeless) action handler used whenever no versioned handler or override applies.
fn with_action(
  rc: ReplayCatalog,
  name: Text,
  run: fn(WriteTx, Json) : Result((WriteTx, Json), Text)
) : ReplayCatalog
  var next = rc
  next.actions = next.actions.set(name, ReplayAction(run: fn(tx, args, _at) run(tx, args) end))
  next
end

## Registers a default time-aware action handler receiving the call's recorded `at: Time`.
fn with_timed_action(
  rc: ReplayCatalog,
  name: Text,
  run: fn(WriteTx, Json, Time) : Result((WriteTx, Json), Text)
) : ReplayCatalog
  var next = rc
  next.actions = next.actions.set(name, ReplayAction(run: run))
  next
end

## Registers the exact historical code for `name` at `schema_version`.
fn with_versioned_action(
  rc: ReplayCatalog,
  schema_version: Int,
  name: Text,
  run: fn(WriteTx, Json) : Result((WriteTx, Json), Text)
) : ReplayCatalog
  var next = rc
  next.versioned_actions = next.versioned_actions.set(
    version_key(schema_version, name),
    ReplayAction(run: fn(tx, args, _at) run(tx, args) end)
  )
  next
end

## Registers a time-aware historical handler for `name` at `schema_version`.
fn with_versioned_timed_action(
  rc: ReplayCatalog,
  schema_version: Int,
  name: Text,
  run: fn(WriteTx, Json, Time) : Result((WriteTx, Json), Text)
) : ReplayCatalog
  var next = rc
  next.versioned_actions = next.versioned_actions.set(
    version_key(schema_version, name),
    ReplayAction(run: run)
  )
  next
end

## Registers a bug-fix override for `name` applied across ALL schema versions during replay.
fn with_override_action(
  rc: ReplayCatalog,
  name: Text,
  run: fn(WriteTx, Json) : Result((WriteTx, Json), Text)
) : ReplayCatalog
  var next = rc
  next.overrides = next.overrides.set(name, ReplayAction(run: fn(tx, args, _at) run(tx, args) end))
  next
end

## Registers a time-aware bug-fix override for `name` applied across ALL schema versions during replay.
fn with_override_timed_action(
  rc: ReplayCatalog,
  name: Text,
  run: fn(WriteTx, Json, Time) : Result((WriteTx, Json), Text)
) : ReplayCatalog
  var next = rc
  next.overrides = next.overrides.set(name, ReplayAction(run: run))
  next
end

## Registers a targeted bug-fix override replacing calls recorded at `from_version` for `name`
## (e.g. Experiment 18: replay v1 calls through v2's corrected code, leaving v2 & v3 untouched).
fn with_override_for_version(
  rc: ReplayCatalog,
  from_version: Int,
  name: Text,
  run: fn(WriteTx, Json) : Result((WriteTx, Json), Text)
) : ReplayCatalog
  var next = rc
  next.version_overrides = next.version_overrides.set(
    version_key(from_version, name),
    ReplayAction(run: fn(tx, args, _at) run(tx, args) end)
  )
  next
end

## Declares the exact set of invariants enforced while replaying calls at historical `schema_version`.
## Versions without explicit entries default to `db.schema.invariants`.
fn with_version_invariants(rc: ReplayCatalog, schema_version: Int, invs: List(Invariant)) : ReplayCatalog
  var next = rc
  next.version_invariants = next.version_invariants.set(schema_version, invs)
  next
end

fn replay_meta_table() : Table(Text, ReplayMeta)
  Table.text_key[ReplayMeta](replay_meta_bucket)
end

fn calls_by_principal_index() : Index(Int, CallRecord, Text)
  Table.text_index[Int, CallRecord](replay_by_principal_bucket, fn(c) c.principal end)
end

fn replay_calls_table() : Table(Int, CallRecord)
  Table.int_key[CallRecord](replay_calls_bucket).with_index(calls_by_principal_index())
end

fn replay_proposals_table() : Table(Text, ReplayProposal)
  Table.text_key[ReplayProposal](replay_proposals_bucket)
end

fn replay_baseline_table() : Table(Text, ReplayBaseline)
  Table.text_key[ReplayBaseline](replay_baseline_bucket)
end

## Returns the persisted CoW replay baseline pin if one has been recorded.
fn get_baseline(store: Store) : Result(Option(ReplayBaseline), ReplayError)
  wrap_table(Table.get(store, replay_baseline_table(), "current"))
end

## Pins the current committed CoW catalog root as the replay starting baseline (before any
## new replayable calls are recorded, typically right after compaction or snapshot import).
fn pin_baseline(db: Db, now: Time) : Result((Db, ReplayBaseline), ReplayError)
  cnt = try call_count(Ledger.store(db))
  if cnt > 0
    return Error(
      ReplayFailed(
        detail: "cannot pin replay baseline after #{cnt} replay calls have been recorded; compact first"
      )
    )
  end
  var tx = Modb.begin_write(Ledger.store(db))
  if (try wrap_modb(Modb.get_pin(Ledger.store(db), replay_baseline_pin_id))) is Some(_)
    tx = try wrap_modb(Modb.tx_unpin_root(tx, replay_baseline_pin_id))
  end
  (tx1, _pin) = try wrap_modb(Modb.tx_pin_base_root(tx, replay_baseline_pin_id))
  bl = ReplayBaseline(
    pin_id: replay_baseline_pin_id,
    schema_version: db.state.version,
    txid: Ledger.txid(db),
    pinned_at: now
  )
  tx2 = try wrap_table(Table.put(tx1, replay_baseline_table(), "current", bl))
  committed = try wrap_modb(Modb.commit(tx2))
  Ok((Ledger.update_store(db, committed), bl))
end

## Lock-coordinated `pin_baseline` for multi-worker HTTP servers.
fn pin_baseline_locked(files: Files, path: Text, sc: Schema, now: Time) : Result(
  ReplayBaseline,
  ReplayError
)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      (_next, bl) = try pin_baseline(db, now)
      Ok(bl)
    end
  )
end

fn wrap_table(res: Result(T, TableError)) : Result(T, ReplayError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, ReplayError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(Table.Storage(e))) end)
end

fn resolve_action(rc: ReplayCatalog, schema_version: Int, action: Text) : Result(
  ReplayAction,
  ReplayError
)
  vk = version_key(schema_version, action)
  case rc.version_overrides.get(vk)
    Some(a): return Ok(a)
    None: Unit
  end
  case rc.overrides.get(action)
    Some(a): return Ok(a)
    None: Unit
  end
  case rc.versioned_actions.get(vk)
    Some(a): return Ok(a)
    None: Unit
  end
  case rc.actions.get(action)
    Some(a): Ok(a)
    None: Error(UnknownReplayAction(action: action, schema_version: schema_version))
  end
end

## Appends a `CallRecord` inside an active `WriteTx`, assigning the next monotonic `seq`.
fn tx_record_call(
  tx: WriteTx,
  schema_version: Int,
  audit_seq: Option(Int),
  principal: Text,
  grant_id: Option(Text),
  grant_chain: List(Text),
  world_id: Option(Text),
  action: Text,
  args: Json,
  reason: Text,
  at: Time,
  outcome: OriginalOutcome
) : Result((WriteTx, CallRecord), TableError)
  meta = (try Table.tx_get(tx, replay_meta_table(), "state")) or ReplayMeta(next_call_seq: 1)
  rec = CallRecord(
    seq: meta.next_call_seq,
    audit_seq: audit_seq,
    schema_version: schema_version,
    principal: principal,
    grant_id: grant_id,
    grant_chain: grant_chain,
    world_id: world_id,
    action: action,
    args: args,
    reason: reason,
    at: at,
    outcome: outcome
  )
  t1 = try Table.put(tx, replay_calls_table(), rec.seq, rec)
  t2 = try Table.put(t1, replay_meta_table(), "state", ReplayMeta(next_call_seq: rec.seq + 1))
  Ok((t2, rec))
end

## Persists an `OrigRefused` call attempt into `_modb_replay_calls` WITHOUT mutating user tables
## or appending to `_modb_audit` (enabling `NowAccepted` detection during divergent replay).
fn record_refused(
  db: Db,
  principal: Text,
  grant_id: Option(Text),
  grant_chain: List(Text),
  world_id: Option(Text),
  action: Text,
  args: Json,
  reason: Text,
  at: Time,
  error_text: Text
) : Result((Db, CallRecord), ReplayError)
  tx0 = Modb.begin_write(Ledger.store(db))
  (tx1, rec) = try wrap_table(
    tx_record_call(
      tx0,
      db.state.version,
      None,
      principal,
      grant_id,
      grant_chain,
      world_id,
      action,
      args,
      reason,
      at,
      OrigRefused(error: error_text)
    )
  )
  committed = try wrap_modb(Modb.commit(tx1))
  Ok((Ledger.update_store(db, committed), rec))
end

## Executes an approved action from `rc` atomically inside `Ledger.transact`, recording both the
## hash-chained `AuditEntry` and the replayable `CallRecord(OrigOk(reply))` in the same commit.
fn execute(db: Db, rc: ReplayCatalog, meta: WriteMeta, args: Json) : Result(
  (Db, Json, CallRecord),
  ReplayError
)
  sc_ver = db.state.version
  audit_seq = db.state.next_audit_seq
  action_def = try resolve_action(rc, sc_ver, meta.action)
  summary = "execute '#{meta.action}' (v#{sc_ver})"
  (next_db, (reply, rec)) = try Ledger.transact(
    db,
    meta,
    summary,
    args,
    fn(le) LedgerFailure(le) end,
    fn(tx)
      (tx1, rep) = try action_def.run(tx, args, meta.at).map_error(fn(d)
        ReplayActionRejected(action: meta.action, detail: d)
      end)
      (tx2, crec) = try wrap_table(
        tx_record_call(
          tx1,
          sc_ver,
          Some(audit_seq),
          meta.principal,
          None,
          [],
          None,
          meta.action,
          args,
          meta.reason,
          meta.at,
          OrigOk(reply: rep)
        )
      )
      Ok((tx2, (rep, crec)))
    end
  )
  Ok((next_db, reply, rec))
end

## Executes an approved action like `execute`, and on business or invariant refusal records
## `OrigRefused(error)` into `_modb_replay_calls` (leaving user tables & `_modb_audit` untouched).
fn execute_recording_refusals(db: Db, rc: ReplayCatalog, meta: WriteMeta, args: Json) : Result(
  (Db, Json, CallRecord),
  (Db, ReplayError)
)
  case execute(db, rc, meta, args)
    Ok(res): Ok(res)
    Error(err):
      should_record? = case err
        ReplayActionRejected(action: _, detail: _): true
        LedgerFailure(Ledger.InvariantViolation(name: _, detail: _)): true
        LedgerFailure(_) | ExportFailure(_) | GrantFailure(_) | ProposalNotFound(id: _) | ProposalAlreadyExists(
          id: _
        ) | ProposalNotPending(id: _, status: _) | ProposalStale(
          id: _,
          expected_audit_seq: _,
          actual_audit_seq: _,
          expected_call_seq: _,
          actual_call_seq: _
        ) | UnknownReplayAction(action: _, schema_version: _) | MissingReplayMigration(version: _) | ReplayFailed(
          detail: _
        ): false
      end
      if not should_record?
        return Error((db, err))
      end
      case record_refused(
        db,
        meta.principal,
        None,
        [],
        None,
        meta.action,
        args,
        meta.reason,
        meta.at,
        err.to_text
      )
        Ok((next_db, _rec)): Error((next_db, err))
        Error(_): Error((db, err))
      end
  end
end

## Lists all recorded replayable calls in ascending sequence order.
fn list_calls(store: Store) : Result(List(CallRecord), ReplayError)
  rows = try wrap_table(Table.all(store, replay_calls_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Returns the most recent `limit` replayable calls in ascending sequence order (`limit <= 0` = all).
fn list_calls_tail(store: Store, limit: Int) : Result(List(CallRecord), ReplayError)
  total = try call_count(store)
  return Ok([]) if total <= 0
  if limit <= 0 or limit >= total
    list_calls(store)
  else
    start_seq = total - limit + 1
    rows = try wrap_table(Table.scan(store, replay_calls_table(), Some(start_seq), None, limit))
    Ok(rows.map(fn(p) p.1 end))
  end
end

## Lists all recorded replayable calls submitted by `principal`.
fn calls_by_principal(store: Store, principal: Text) : Result(List(CallRecord), ReplayError)
  rows = try wrap_table(
    Table.lookup(store, replay_calls_table(), calls_by_principal_index(), principal)
  )
  Ok(rows.map(fn(p) p.1 end))
end

## Returns total number of recorded replayable calls (`0` if none recorded yet).
fn call_count(store: Store) : Result(Int, ReplayError)
  meta_opt = try wrap_table(Table.get(store, replay_meta_table(), "state"))
  case meta_opt
    Some(m): Ok(m.next_call_seq - 1)
    None: Ok(0)
  end
end

## Looks up a persisted `ReplayProposal` by ID.
fn get_proposal(store: Store, proposal_id: Text) : Result(Option(ReplayProposal), ReplayError)
  wrap_table(Table.get(store, replay_proposals_table(), proposal_id))
end

## Lists all persisted `ReplayProposal`s.
fn list_proposals(store: Store) : Result(List(ReplayProposal), ReplayError)
  rows = try wrap_table(Table.all(store, replay_proposals_table()))
  Ok(rows.map(fn(p) p.1 end))
end

fn find_migration(sc: Schema, version: Int) : Result(Migration, ReplayError)
  for m in sc.migrations
    return Ok(m) if m.version == version
  end
  Error(MissingReplayMigration(version: version))
end

fn advance_sim_tx(
  cur_tx: WriteTx,
  sc: Schema,
  cur_ver: Int,
  target_ver: Int,
  migrations_run: List(Int)
) : Result((WriteTx, Int, List(Int)), ReplayError)
  var tx = cur_tx
  var v = cur_ver
  var ran = migrations_run
  while v < target_ver
    next_v = v + 1
    m = try find_migration(sc, next_v)
    tx = try m.apply(tx).map_error(fn(e)
      ReplayFailed(detail: "migration v#{next_v} failed during replay: #{e.to_text}")
    end)
    v = next_v
    ran = ran.append(v)
  end
  Ok((tx, v, ran))
end

fn check_replay_invariants(invs: List(Invariant), tx: WriteTx) : Result(
  Option((Text, Text)),
  ReplayError
)
  for inv in invs
    case try wrap_table(inv.check(tx))
      Some(detail): return Ok(Some((inv.name, detail)))
      None: Unit
    end
  end
  Ok(None)
end

fn should_exclude_call?(call: CallRecord, filter: ReplayFilter, excluded_grants: Set(Text)) : Bool
  case filter
    ReplayAll: false
    ExcludePrincipal(principal: p): call.principal == p
    ExcludeGrant(grant_id: _):
      case call.grant_id
        Some(cg): excluded_grants.has?(cg)
        None: false
      end
    ExcludeSeqs(seqs: seqs):
      for s in seqs
        return true if s == call.seq
      end
      false
    ExcludeWorld(world_id: wid):
      case call.world_id
        Some(cw): cw == wid
        None: false
      end
    StopBeforeSeq(seq: stop_seq): call.seq >= stop_seq
  end
end

fn merge_sorted_bucket_names(a: List(Text), b: List(Text)) : List(Text)
  var out = []
  var i = 0
  var j = 0
  while i < a.size and j < b.size
    sa = a.get(i) or stop "bucket merge a"
    sb = b.get(j) or stop "bucket merge b"
    if sa == sb
      out = out.append(sa)
      i += 1
      j += 1
    else if sa < sb
      out = out.append(sa)
      i += 1
    else
      out = out.append(sb)
      j += 1
    end
  end
  while i < a.size
    out = out.append(a.get(i) or stop "bucket tail a")
    i += 1
  end
  while j < b.size
    out = out.append(b.get(j) or stop "bucket tail b")
    j += 1
  end
  out
end

fn diff_sorted_rows(live_rows: List((Bytes, Bytes)), sim_rows: List((Bytes, Bytes))) : (
  Int,
  Int,
  Int
)
  var added = 0
  var removed = 0
  var modified = 0
  var i = 0
  var j = 0
  while i < live_rows.size and j < sim_rows.size
    (lk, lv) = live_rows.get(i) or stop "live row idx"
    (sk, sv) = sim_rows.get(j) or stop "sim row idx"
    if lk == sk
      if lv != sv
        modified += 1
      end
      i += 1
      j += 1
    else if lk < sk
      removed += 1
      i += 1
    else
      added += 1
      j += 1
    end
  end
  removed += live_rows.size - i
  added += sim_rows.size - j
  (added, removed, modified)
end

fn diff_user_stores(live_store: Store, sim_store: Store) : Result(List(BucketRowDiff), ReplayError)
  live_all = try wrap_modb(Modb.buckets(live_store))
  sim_all = try wrap_modb(Modb.buckets(sim_store))
  var live_user = []
  for b in live_all
    if not b.starts_with?("_modb_")
      live_user = live_user.append(b)
    end
  end
  var sim_user = []
  for b in sim_all
    if not b.starts_with?("_modb_")
      sim_user = sim_user.append(b)
    end
  end
  names = merge_sorted_bucket_names(live_user, sim_user)
  var diffs = []
  for bname in names
    lrows = try wrap_modb(Modb.scan(live_store, bname, None, None, 0))
    srows = try wrap_modb(Modb.scan(sim_store, bname, None, None, 0))
    (a, r, m) = diff_sorted_rows(lrows, srows)
    if a + r + m > 0
      diffs = diffs.append(BucketRowDiff(bucket: bname, added: a, removed: r, modified: m))
    end
  end
  Ok(diffs)
end

## Simulates replaying the entire recorded call history offline on an isolated in-memory store
## without modifying `db` in any way, returning a reviewable `ReplayProposal`.
fn preview_replay(
  db: Db,
  rc: ReplayCatalog,
  filter: ReplayFilter,
  proposal_id: Text,
  description: Text,
  created_by: Text,
  now: Time
) : Result(ReplayProposal, ReplayError)
  if proposal_id.trim.empty?
    return Error(ReplayFailed(detail: "proposal_id cannot be empty"))
  end
  if created_by.trim.empty?
    return Error(ReplayFailed(detail: "created_by cannot be empty"))
  end
  excluded_grants = case filter
    ExcludeGrant(grant_id: gid): try Grants.grant_subtree_ids(Ledger.store(db), gid).map_error(
      fn(e) GrantFailure(e) end
    )
    ReplayAll | ExcludePrincipal(principal: _) | ExcludeSeqs(seqs: _) | ExcludeWorld(world_id: _) | StopBeforeSeq(
      seq: _
    ): Set.empty
  end

  calls = try list_calls(Ledger.store(db))
  base_calls = try call_count(Ledger.store(db))
  baseline_opt = try get_baseline(Ledger.store(db))
  (init_tx, init_ver) = case baseline_opt
    Some(bl):
      pin = try (try wrap_modb(Modb.get_pin(Ledger.store(db), bl.pin_id))).or_fail(
        ReplayFailed(detail: "missing replay baseline pin '#{bl.pin_id}'")
      )
      (Modb.begin_write_from_root(Ledger.store(db), pin.catalog_root), bl.schema_version)
    None:
      sim_base = try wrap_modb(Modb.open_disk(sim_empty()))
      (Modb.begin_write_tracked(sim_base), 0)
  end
  var cur_tx = init_tx
  var cur_ver = init_ver
  var migrations_run = []
  var outcomes = []
  var excluded_n = 0
  var unchanged_n = 0
  var reply_changed_n = 0
  var now_refused_n = 0
  var now_inv_blocked_n = 0
  var still_refused_n = 0
  var now_accepted_n = 0

  for call in calls
    if call.schema_version > cur_ver
      (tx_next, v_next, m_next) = try advance_sim_tx(
        cur_tx,
        db.schema,
        cur_ver,
        call.schema_version,
        migrations_run
      )
      cur_tx = tx_next
      cur_ver = v_next
      migrations_run = m_next
    end

    if should_exclude_call?(call, filter, excluded_grants)
      excluded_n += 1
      outcomes = outcomes.append(
        Excluded(seq: call.seq, action: call.action, principal: call.principal)
      )
    else
      action_def = try resolve_action(rc, call.schema_version, call.action)
      invs = rc.version_invariants.get(cur_ver) or db.schema.invariants
      step_tx = Modb.tx_clear_touched(cur_tx)
      case action_def.run(step_tx, call.args, call.at)
        Ok((tx1, new_reply)):
          case try check_replay_invariants(invs, tx1)
            None:
              cur_tx = tx1
              case call.outcome
                OrigOk(reply: old_reply):
                  if Json.encode(old_reply) == Json.encode(new_reply)
                    unchanged_n += 1
                    outcomes = outcomes.append(
                      Unchanged(seq: call.seq, action: call.action, principal: call.principal)
                    )
                  else
                    reply_changed_n += 1
                    outcomes = outcomes.append(
                      ReplyChanged(
                        seq: call.seq,
                        action: call.action,
                        principal: call.principal,
                        old_reply: old_reply,
                        new_reply: new_reply
                      )
                    )
                  end
                OrigRefused(error: old_err):
                  now_accepted_n += 1
                  outcomes = outcomes.append(
                    NowAccepted(
                      seq: call.seq,
                      action: call.action,
                      principal: call.principal,
                      old_error: old_err,
                      new_reply: new_reply
                    )
                  )
              end
            Some((inv_name, inv_detail)):
              case call.outcome
                OrigOk(reply: old_reply):
                  now_inv_blocked_n += 1
                  outcomes = outcomes.append(
                    NowInvariantBlocked(
                      seq: call.seq,
                      action: call.action,
                      principal: call.principal,
                      old_reply: old_reply,
                      invariant: inv_name,
                      detail: inv_detail
                    )
                  )
                OrigRefused(error: old_err):
                  still_refused_n += 1
                  outcomes = outcomes.append(
                    StillRefused(
                      seq: call.seq,
                      action: call.action,
                      principal: call.principal,
                      old_error: old_err,
                      new_error: "invariant '#{inv_name}': #{inv_detail}"
                    )
                  )
              end
          end
        Error(act_err):
          case call.outcome
            OrigOk(reply: old_reply):
              now_refused_n += 1
              outcomes = outcomes.append(
                NowRefused(
                  seq: call.seq,
                  action: call.action,
                  principal: call.principal,
                  old_reply: old_reply,
                  new_error: act_err
                )
              )
            OrigRefused(error: old_err):
              still_refused_n += 1
              outcomes = outcomes.append(
                StillRefused(
                  seq: call.seq,
                  action: call.action,
                  principal: call.principal,
                  old_error: old_err,
                  new_error: act_err
                )
              )
          end
      end
    end
  end

  if cur_ver < db.schema.target_version
    (tx_final, v_final, m_final) = try advance_sim_tx(
      cur_tx,
      db.schema,
      cur_ver,
      db.schema.target_version,
      migrations_run
    )
    cur_tx = tx_final
    cur_ver = v_final
    migrations_run = m_final
  end

  (diffs, proposed_snap, proposed_delta_opt) = case baseline_opt
    Some(_bl):
      raw_diffs = try wrap_modb(
        Modb.diff_user_tx_from_root(cur_tx, Modb.catalog_root(Ledger.store(db)))
      )
      var row_diffs = []
      var deltas = []
      for bd in raw_diffs
        var a = 0
        var r = 0
        var m = 0
        var ops = []
        for ch in bd.changes
          case ch
            Added(key: k, value: v):
              a += 1
              ops = ops.append(KeyDelta(key_hex: k.to_hex, value_hex: Some(v.to_hex)))
            Modified(key: k, old_value: _, new_value: nv):
              m += 1
              ops = ops.append(KeyDelta(key_hex: k.to_hex, value_hex: Some(nv.to_hex)))
            Removed(key: k, value: _):
              r += 1
              ops = ops.append(KeyDelta(key_hex: k.to_hex, value_hex: None))
          end
        end
        if a + r + m > 0
          row_diffs = row_diffs.append(
            BucketRowDiff(bucket: bd.bucket, added: a, removed: r, modified: m)
          )
          deltas = deltas.append(BucketDelta(bucket: bd.bucket, ops: ops))
        end
      end
      empty_digest = Export.compute_snapshot_digest(
        Export.export_format_version,
        Ledger.txid(db),
        cur_ver,
        false,
        now,
        []
      )
      empty_snap = Export.PortableSnapshot(
        format_version: Export.export_format_version,
        source_txid: Ledger.txid(db),
        schema_version: cur_ver,
        include_internal: false,
        exported_at: now,
        bucket_count: 0,
        entry_count: 0,
        buckets: [],
        sha256: empty_digest
      )
      (row_diffs, empty_snap, Some(deltas))
    None:
      sim_store = try wrap_modb(Modb.commit(cur_tx))
      full_diffs = try diff_user_stores(Ledger.store(db), sim_store)
      full_snap = try Export.export_store(sim_store, false, now).map_error(fn(e)
        ExportFailure(e)
      end)
      (full_diffs, full_snap, None)
  end

  summary = ReplaySummary(
    total_calls: calls.size,
    excluded: excluded_n,
    unchanged: unchanged_n,
    reply_changed: reply_changed_n,
    now_refused: now_refused_n,
    now_invariant_blocked: now_inv_blocked_n,
    still_refused: still_refused_n,
    now_accepted: now_accepted_n,
    migrations_run: migrations_run
  )
  Ok(
    ReplayProposal(
      id: proposal_id,
      description: description,
      filter: filter,
      base_live_txid: Ledger.txid(db),
      base_audit_seq: Ledger.audit_count(db),
      base_call_seq: base_calls,
      target_schema_version: cur_ver,
      created_by: created_by,
      created_at: now,
      status: Pending,
      summary: summary,
      outcomes: outcomes,
      bucket_diffs: diffs,
      proposed_state: proposed_snap,
      proposed_delta: proposed_delta_opt
    )
  )
end

## Simulates replay offline and persists the resulting `Pending` `ReplayProposal` in
## `_modb_replay_proposals` (never modifying live user tables or `_modb_audit`).
fn simulate_replay(
  db: Db,
  rc: ReplayCatalog,
  filter: ReplayFilter,
  proposal_id: Text,
  description: Text,
  created_by: Text,
  now: Time
) : Result((Db, ReplayProposal), ReplayError)
  if (try get_proposal(Ledger.store(db), proposal_id)) is Some(_)
    return Error(ProposalAlreadyExists(id: proposal_id))
  end
  prop = try preview_replay(db, rc, filter, proposal_id, description, created_by, now)
  tx0 = Modb.begin_write(Ledger.store(db))
  tx1 = try wrap_table(Table.put(tx0, replay_proposals_table(), proposal_id, prop))
  committed = try wrap_modb(Modb.commit(tx1))
  Ok((Ledger.update_store(db, committed), prop))
end

fn proposal_status_label(st: ProposalStatus) : Text
  case st
    Pending: "pending"
    Accepted(commit_txid: t, accepted_by: who, accepted_at: _): "accepted(txid=#{t}, by=#{who})"
    Discarded(discarded_by: who, discarded_at: _): "discarded(by=#{who})"
  end
end

enum ProposalPatch
  ReplaceBuckets(live_user: List(Text), decoded_buckets: List((Text, List((Bytes, Bytes)))))
  ApplyDeltas(decoded_deltas: List((Text, List((Bytes, Option(Bytes))))))
end

fn prepare_proposal_adoption(db: Db, proposal_id: Text) : Result(
  (ReplayProposal, ProposalPatch),
  ReplayError
)
  prop_opt = try get_proposal(Ledger.store(db), proposal_id)
  prop = try prop_opt.or_fail(ProposalNotFound(id: proposal_id))
  case prop.status
    Pending: Unit
    Accepted(commit_txid: _, accepted_by: _, accepted_at: _) | Discarded(
      discarded_by: _,
      discarded_at: _
    ): return Error(ProposalNotPending(id: proposal_id, status: proposal_status_label(prop.status)))
  end
  actual_audit = Ledger.audit_count(db)
  actual_calls = try call_count(Ledger.store(db))
  if actual_audit != prop.base_audit_seq or actual_calls != prop.base_call_seq
    return Error(
      ProposalStale(
        id: proposal_id,
        expected_audit_seq: prop.base_audit_seq,
        actual_audit_seq: actual_audit,
        expected_call_seq: prop.base_call_seq,
        actual_call_seq: actual_calls
      )
    )
  end
  patch = case prop.proposed_delta
    Some(bd_list):
      var decoded_deltas = []
      for bd in bd_list
        if bd.bucket.starts_with?("_modb_")
          return Error(
            ReplayFailed(detail: "proposal cannot overwrite internal bucket '#{bd.bucket}'")
          )
        end
        var ops = []
        for op in bd.ops
          kb = try Bytes.from_hex(op.key_hex).or_fail(
            ReplayFailed(detail: "invalid delta key hex in bucket '#{bd.bucket}'")
          )
          vb_opt = case op.value_hex
            Some(vh):
              vb = try Bytes.from_hex(vh).or_fail(
                ReplayFailed(detail: "invalid delta value hex in bucket '#{bd.bucket}'")
              )
              Some(vb)
            None: None
          end
          ops = ops.append((kb, vb_opt))
        end
        decoded_deltas = decoded_deltas.append((bd.bucket, ops))
      end
      ApplyDeltas(decoded_deltas: decoded_deltas)
    None:
      decoded_buckets = try Export.decode_snapshot_buckets(prop.proposed_state).map_error(fn(e)
        ExportFailure(e)
      end)
      for (bname, _rows) in decoded_buckets
        if bname.starts_with?("_modb_")
          return Error(ReplayFailed(detail: "proposal cannot overwrite internal bucket '#{bname}'"))
        end
      end
      all_live = try wrap_modb(Modb.buckets(Ledger.store(db)))
      var live_user = []
      for b in all_live
        if not b.starts_with?("_modb_")
          live_user = live_user.append(b)
        end
      end
      ReplaceBuckets(live_user: live_user, decoded_buckets: decoded_buckets)
  end
  Ok((prop, patch))
end

fn apply_proposal_in_tx(
  tx0: WriteTx,
  patch: ProposalPatch,
  accepted_prop: ReplayProposal
) : Result(WriteTx, TableError)
  var cur_tx = tx0
  case patch
    ReplaceBuckets(live_user: live_user, decoded_buckets: decoded_buckets):
      for bname in live_user
        cur_tx = try Modb.tx_delete_bucket(cur_tx, bname).map_error(fn(e) Table.Storage(e) end)
      end
      for (bname, rows) in decoded_buckets
        for (k, v) in rows
          cur_tx = try Modb.tx_put(cur_tx, bname, k, v).map_error(fn(e) Table.Storage(e) end)
        end
      end
    ApplyDeltas(decoded_deltas: decoded_deltas):
      for (bname, ops) in decoded_deltas
        for (k, v_opt) in ops
          case v_opt
            Some(v): cur_tx = try Modb.tx_put(cur_tx, bname, k, v).map_error(fn(e)
              Table.Storage(e)
            end)
            None: cur_tx = try Modb.tx_delete(cur_tx, bname, k).map_error(fn(e)
              Table.Storage(e)
            end)
          end
        end
      end
  end
  Table.put(cur_tx, replay_proposals_table(), accepted_prop.id, accepted_prop)
end

## Atomically adopts a `Pending`, fresh `ReplayProposal` onto the live database:
## applies `proposed_delta` (when baseline-pinned) or replaces user buckets with `proposed_state`,
## preserves all `_modb_*` audit/history/grant buckets untouched, enforces every commit-time
## `Schema` invariant, and appends an immutable hash-chained `AuditEntry`.
fn accept_proposal(db: Db, proposal_id: Text, admin_meta: WriteMeta) : Result(
  (Db, ReplayProposal),
  ReplayError
)
  (prop, patch) = try prepare_proposal_adoption(db, proposal_id)
  expected_txid = Ledger.txid(db) + 1
  var accepted = prop
  accepted.status = Accepted(
    commit_txid: expected_txid,
    accepted_by: admin_meta.principal,
    accepted_at: admin_meta.at
  )
  audit_payload = AcceptProposalAuditPayload(
    proposal_id: prop.id,
    description: prop.description,
    filter: prop.filter,
    base_audit_seq: prop.base_audit_seq,
    base_call_seq: prop.base_call_seq,
    summary: prop.summary,
    bucket_diffs: prop.bucket_diffs
  ).to_json
  audit_summary = "accept replay proposal '#{prop.id}' (#{prop.summary.excluded} excluded, #{prop
    .summary.reply_changed} changed, #{prop.summary.now_refused} refused, #{prop.summary
    .now_accepted} now accepted)"

  (next_db, out_prop) = try Ledger.transact(
    db,
    admin_meta,
    audit_summary,
    audit_payload,
    fn(le) LedgerFailure(le) end,
    fn(tx)
      t1 = try wrap_table(apply_proposal_in_tx(tx, patch, accepted))
      Ok((t1, accepted))
    end
  )
  Ok((next_db, out_prop))
end

## Runs a real `accept_proposal` commit up to a simulated power-cut boundary (`phase == 1` or `2`)
## for deterministic torn-write crash testing.
fn accept_proposal_and_crash(
  db: Db,
  proposal_id: Text,
  admin_meta: WriteMeta,
  phase: Int,
  rng: Random
) : Result(BlockStore, ReplayError)
  (prop, patch) = try prepare_proposal_adoption(db, proposal_id)
  expected_txid = Ledger.txid(db) + 1
  var accepted = prop
  accepted.status = Accepted(
    commit_txid: expected_txid,
    accepted_by: admin_meta.principal,
    accepted_at: admin_meta.at
  )
  audit_payload = AcceptProposalAuditPayload(
    proposal_id: prop.id,
    description: prop.description,
    filter: prop.filter,
    base_audit_seq: prop.base_audit_seq,
    base_call_seq: prop.base_call_seq,
    summary: prop.summary,
    bucket_diffs: prop.bucket_diffs
  ).to_json
  audit_summary = "accept replay proposal '#{prop.id}'"
  Ledger.write_and_crash(
    db,
    admin_meta,
    audit_summary,
    audit_payload,
    phase,
    rng,
    fn(tx) apply_proposal_in_tx(tx, patch, accepted) end
  ).map_error(fn(le) LedgerFailure(le) end)
end

## Marks a `Pending` proposal as `Discarded` without modifying user tables or `_modb_audit`.
fn discard_proposal(db: Db, proposal_id: Text, discarded_by: Text, now: Time) : Result(
  (Db, ReplayProposal),
  ReplayError
)
  prop_opt = try get_proposal(Ledger.store(db), proposal_id)
  prop = try prop_opt.or_fail(ProposalNotFound(id: proposal_id))
  case prop.status
    Pending: Unit
    Accepted(commit_txid: _, accepted_by: _, accepted_at: _) | Discarded(
      discarded_by: _,
      discarded_at: _
    ): return Error(ProposalNotPending(id: proposal_id, status: proposal_status_label(prop.status)))
  end
  var discarded = prop
  discarded.status = Discarded(discarded_by: discarded_by, discarded_at: now)
  tx0 = Modb.begin_write(Ledger.store(db))
  tx1 = try wrap_table(Table.put(tx0, replay_proposals_table(), proposal_id, discarded))
  committed = try wrap_modb(Modb.commit(tx1))
  Ok((Ledger.update_store(db, committed), discarded))
end

## Lock-coordinated `simulate_replay` for multi-worker HTTP servers.
fn simulate_replay_locked(
  files: Files,
  path: Text,
  sc: Schema,
  rc: ReplayCatalog,
  filter: ReplayFilter,
  proposal_id: Text,
  description: Text,
  created_by: Text,
  now: Time
) : Result(ReplayProposal, ReplayError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      (_next, prop) = try simulate_replay(db, rc, filter, proposal_id, description, created_by, now)
      Ok(prop)
    end
  )
end

## Lock-coordinated read-only `get_proposal` over `ReadFiles` + shared `flock`.
fn get_proposal_locked(rf: ReadFiles, path: Text, sc: Schema, proposal_id: Text) : Result(
  Option(ReplayProposal),
  ReplayError
)
  Ledger.read_locked(
    rf,
    path,
    sc,
    fn(le) LedgerFailure(le) end,
    fn(db) get_proposal(Ledger.store(db), proposal_id) end
  )
end

## Lock-coordinated read-only `list_proposals` over `ReadFiles` + shared `flock`.
fn list_proposals_locked(rf: ReadFiles, path: Text, sc: Schema) : Result(
  List(ReplayProposal),
  ReplayError
)
  Ledger.read_locked(
    rf,
    path,
    sc,
    fn(le) LedgerFailure(le) end,
    fn(db) list_proposals(Ledger.store(db)) end
  )
end

## Lock-coordinated `accept_proposal` for multi-worker HTTP servers.
fn accept_proposal_locked(
  files: Files,
  path: Text,
  sc: Schema,
  proposal_id: Text,
  admin_meta: WriteMeta
) : Result(ReplayProposal, ReplayError)
  Ledger.locked(
    files,
    path,
    sc,
    admin_meta.at,
    fn(le) LedgerFailure(le) end,
    fn(db)
      (_next, prop) = try accept_proposal(db, proposal_id, admin_meta)
      Ok(prop)
    end
  )
end

## Lock-coordinated `discard_proposal` for multi-worker HTTP servers.
fn discard_proposal_locked(
  files: Files,
  path: Text,
  sc: Schema,
  proposal_id: Text,
  discarded_by: Text,
  now: Time
) : Result(ReplayProposal, ReplayError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(le) LedgerFailure(le) end,
    fn(db)
      (_next, prop) = try discard_proposal(db, proposal_id, discarded_by, now)
      Ok(prop)
    end
  )
end

## Compacts a ledger-backed database cleanly (`include_internal: false`, fresh verification
## checkpoint) and pins its resulting CoW root as `_modb_replay_baseline` so future
## `simulate_replay` and O(diff) delta proposals preserve all pre-compaction state.
## Runs `after_import(ldb)` (e.g. to re-provision root Grants) inside the atomic staging step
## before verification and file replacement.
fn compact_with_baseline(
  files: Files,
  path: Text,
  sc: Schema,
  now: Time,
  after_import: fn(Db) : Result(Db, ReplayError)
) : Result(Export.CompactReport, ReplayError)
  rep = try Export.compact_db_with_hook(
    files,
    path,
    sc,
    false,
    true,
    now,
    fn(ldb0)
      ldb1 = try after_import(ldb0).map_error(fn(re) Export.PostImportFailed(detail: re.to_text) end)
      (ldb2, _bl) = try pin_baseline(ldb1, now).map_error(
        fn(re) Export.PostImportFailed(detail: re.to_text) end
      )
      Ok(ldb2)
    end
  ).map_error(fn(ee) ExportFailure(ee) end)
  Ok(
    Export.CompactReport(
      before_txid: rep.before_txid,
      after_txid: rep.after_txid,
      schema_version: rep.schema_version,
      include_internal: rep.include_internal,
      before_pages: rep.before_pages,
      after_pages: rep.after_pages,
      before_free_pages: rep.before_free_pages,
      after_free_pages: rep.after_free_pages,
      before_audit_entries: rep.before_audit_entries,
      after_audit_entries: rep.after_audit_entries,
      checkpoint_recorded?: rep.checkpoint_recorded?,
      baseline_pinned?: true,
      sha256: rep.sha256
    )
  )
end

## Convenience overload of `compact_with_baseline` with no extra post-import hook.
fn compact_with_baseline_default(files: Files, path: Text, sc: Schema, now: Time) : Result(
  Export.CompactReport,
  ReplayError
)
  compact_with_baseline(files, path, sc, now, fn(db) Ok(db) end)
end

struct TallyRow
  count: Int
end

struct AddArgs
  name: Text
  delta: Int
end

test "Modb.Replay unit: execute, selective undo proposal, staleness guard, and atomic acceptance"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T13:00:00Z") or stop "t0"
  tallies = Table.text_key[TallyRow]("tallies")
  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "seed a=10", fn(tx) Table.put(tx, tallies, "a", TallyRow(count: 10)) end)
  ).with_invariant(
    Ledger.row_invariant(
      "non_negative",
      tallies,
      fn(k, r) if r.count < 0: Some("tally '#{k}' < 0") else: None end
    )
  )

  rc = catalog().with_action(
    "add",
    fn(tx, args)
      a = try Json.decode[AddArgs](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      cur = (try Table.tx_get(tx, tallies, a.name).map_error(fn(e) e.to_text end)) or
        TallyRow(count: 0)
      next = cur.count + a.delta
      if next < 0
        return Error("insufficient balance in '#{a.name}': #{cur.count} + #{a.delta}")
      end
      t1 = try Table.put(tx, tallies, a.name, TallyRow(count: next)).map_error(fn(e) e.to_text end)
      Ok((t1, next.to_json))
    end
  )

  assert Ledger.open(files, "replay-unit.modb", sc, t0) is Ok(db0)
  ## Rogue agent drains 8 from 'a' (10 -> 2), causing Alice's -5 withdrawal to be REFUSED!
  m_rogue = WriteMeta(principal: "agent:rogue", action: "add", reason: "drain", at: t0)
  assert execute_recording_refusals(db0, rc, m_rogue, AddArgs(name: "a", delta: -8).to_json) is
    Ok((db1, rep1, _))
  assert rep1 == 2.to_json

  m_alice = WriteMeta(principal: "user:alice", action: "add", reason: "spend", at: t0)
  assert execute_recording_refusals(db1, rc, m_alice, AddArgs(name: "a", delta: -5).to_json) is
    Error((db2, ReplayActionRejected(action: "add", detail: _)))
  assert Table.get(Ledger.store(db2), tallies, "a") == Ok(Some(TallyRow(count: 2)))

  ## Simulate removing agent:rogue -> proposal shows Excluded + NowAccepted(5) + live DB untouched!
  assert simulate_replay(
    db2,
    rc,
    ExcludePrincipal(principal: "agent:rogue"),
    "prop-undo-rogue",
    "Remove rogue agent drain",
    "admin:ada",
    t0
  ) is
    Ok((db3, prop))
  assert prop.summary.excluded == 1 and prop.summary.now_accepted == 1
  assert Table.get(Ledger.store(db3), tallies, "a") == Ok(Some(TallyRow(count: 2)))

  ## Accept proposal -> live DB becomes a=5, audit chain unbroken, verify_all green!
  m_acc = WriteMeta(
    principal: "admin:ada",
    action: "accept_replay_proposal",
    reason: "approved undo",
    at: t0
  )
  assert accept_proposal(db3, "prop-undo-rogue", m_acc) is Ok((db4, acc_prop))
  assert acc_prop.status is Accepted(commit_txid: _, accepted_by: "admin:ada", accepted_at: _)
  assert Table.get(Ledger.store(db4), tallies, "a") == Ok(Some(TallyRow(count: 5)))
  assert Ledger.verify_all(db4) is Ok(_)

  ## CoW-pinned ReplayBaseline preserves pre-existing rows while applying O(diff) delta proposals
  assert Export.export_db(db4, false, t0) is Ok(compacted_snap)
  sc_v1 = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "init v1 tables", fn(tx) Ok(tx) end)
  ).with_invariant(
    Ledger.row_invariant(
      "non_negative",
      tallies,
      fn(k, r) if r.count < 0: Some("tally '#{k}' < 0") else: None end
    )
  )
  assert Export.import_db(files, "replay-compact.modb", sc_v1, compacted_snap, t0) is Ok(cdb0)
  assert Table.get(Ledger.store(cdb0), tallies, "a") == Ok(Some(TallyRow(count: 5)))
  assert pin_baseline(cdb0, t0) is Ok((cdb1, bl))
  assert bl.schema_version == 1
  assert call_count(Ledger.store(cdb1)) == Ok(0)

  ## Post-baseline calls: rogue drains 4 (5 -> 1), then Alice -3 refused, then Carol +20 on 'b'
  assert execute_recording_refusals(cdb1, rc, m_rogue, AddArgs(name: "a", delta: -4).to_json) is
    Ok((cdb2, _, _))
  ## Once calls exist, pin_baseline rejects cleanly
  assert pin_baseline(cdb2, t0) is Error(ReplayFailed(detail: _))
  assert execute_recording_refusals(cdb2, rc, m_alice, AddArgs(name: "a", delta: -3).to_json) is
    Error((cdb3, ReplayActionRejected(action: "add", detail: _)))
  m_carol = WriteMeta(principal: "user:carol", action: "add", reason: "fund b", at: t0)
  assert execute_recording_refusals(cdb3, rc, m_carol, AddArgs(name: "b", delta: 20).to_json) is
    Ok((cdb4, _, _))
  assert list_calls_tail(Ledger.store(cdb4), 2) is Ok(tail2) and tail2.size == 2

  assert simulate_replay(
    cdb4,
    rc,
    ExcludePrincipal(principal: "agent:rogue"),
    "prop-delta-1",
    "Undo rogue post-compact drain via CoW baseline",
    "admin:ada",
    t0
  ) is
    Ok((cdb5, dprop))
  assert dprop.proposed_delta is Some(deltas) and not deltas.empty?
  assert dprop.proposed_state.bucket_count == 0
  assert dprop.summary.excluded == 1 and dprop.summary.now_accepted == 1
  assert Table.get(Ledger.store(cdb5), tallies, "a") == Ok(Some(TallyRow(count: 1)))

  assert accept_proposal(cdb5, "prop-delta-1", m_acc) is Ok((cdb6, _))
  ## Pre-baseline 'a'=5 preserved minus Alice's now-accepted 3 => 2; post-baseline 'b'=20 preserved!
  assert Table.get(Ledger.store(cdb6), tallies, "a") == Ok(Some(TallyRow(count: 2)))
  assert Table.get(Ledger.store(cdb6), tallies, "b") == Ok(Some(TallyRow(count: 20)))
  assert Ledger.verify_all(cdb6) is Ok(_)
  assert Modb.verify(Ledger.store(cdb6)) is Ok(_)

  ## Adopting another proposal created prior to accept fails staleness guard
  assert simulate_replay(cdb6, rc, ReplayAll, "prop-stale", "stale check", "admin:ada", t0) is
    Ok((cdb7, _))
  assert execute(cdb7, rc, m_carol, AddArgs(name: "b", delta: 1).to_json) is Ok((cdb8, _, _))
  assert accept_proposal(cdb8, "prop-stale", m_acc) is Error(ProposalStale(id: "prop-stale", expected_audit_seq: _, actual_audit_seq: _, expected_call_seq: _, actual_call_seq: _))
end
