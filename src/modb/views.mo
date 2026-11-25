## MoDB Milestone 8: Grant-Scoped Views, Approved k-Anonymous Releases,
## Zero-Approval Sandboxed Ad-Hoc Read Programs, Read Provenance Logging,
## and Stateless Agent Self-Onboarding (`design.md` §6).
module Modb.Views
expose read_log_bucket,
read_meta_bucket,
ViewsError(..),
ViewField(..),
ViewDef(..),
ReleaseDef(..),
ActionDoc(..),
InvariantDoc(..),
ViewCatalog(..),
Pred(..),
AggOp(..),
AggSpec(..),
SortSpec(..),
ReadProgram(..),
ReadLimits(..),
ReadResult(..),
ReleaseResult(..),
ReadKind(..),
ReadLogEntry(..),
ViewSummary(..),
ReleaseSummary(..),
CallerGrantInfo(..),
OnboardingManifest(..),
to_text,
default_limits,
catalog,
with_view,
with_release,
with_action_doc,
with_invariant_doc,
view_narrows_map,
validate_program,
execute_read_program,
execute_read_program_recorded,
execute_release,
execute_release_recorded,
list_read_log,
describe_for_caller,
execute_read_program_locked,
execute_release_locked
use Crypto
use Json
use Modb{Store}
use Modb.Claims
use Modb.Errors{ModbError}
use Modb.Grants
use Modb.Ledger{Db, LedgerError, Schema}
use Modb.Table{Table, TableError}
use Modb.World

## Reserved internal buckets for persisted read provenance logging.
read_log_bucket = "_modb_read_log"
read_meta_bucket = "_modb_read_meta"

## Every failure returned by `Modb.Views` operations.
enum ViewsError
  LedgerFailure(LedgerError)
  GrantFailure(Grants.GrantError)
  UnknownView(name: Text)
  UnknownRelease(name: Text)
  FieldNotInView(view: Text, field: Text, allowed: List(Text))
  InvalidProgram(reason: Text)
  WorkBudgetExceeded(metric: Text, limit: Int)
  ViewLoadFailed(view: Text, detail: Text)
  ReleaseFailed(release: Text, detail: Text)
  ReleaseThresholdBlocked(release: Text, min_group_size: Int, actual_count: Int)
end

## Formats a `ViewsError` as a human-readable diagnostic.
fn to_text(err: ViewsError) : Text
  case err
    LedgerFailure(e): e.to_text
    GrantFailure(e): e.to_text
    UnknownView(name: n): "unknown view '#{n}'"
    UnknownRelease(name: n): "unknown release '#{n}'"
    FieldNotInView(view: v, field: f, allowed: a): "field '#{f}' is not exposed by view '#{v}' (allowed: #{a
      .join(", ")})"
    InvalidProgram(reason: r): "invalid read program: #{r}"
    WorkBudgetExceeded(metric: m, limit: lim): "read program exceeded work budget (#{m} > #{lim})"
    ViewLoadFailed(view: v, detail: d): "failed loading view '#{v}': #{d}"
    ReleaseFailed(release: r, detail: d): "release '#{r}' failed: #{d}"
    ReleaseThresholdBlocked(release: r, min_group_size: m, actual_count: c): "release '#{r}' blocked by k-anonymity threshold: cohort size #{c} < min_group_size #{m}"
  end
end

## One typed field exposed by a `ViewDef`.
struct ViewField
  name: Text
  field_type: Text
  description: Text
end

## Approved view projecting committed data into a strictly narrowed set of fields.
struct ViewDef
  name: Text
  description: Text
  source_buckets: List(Text)
  fields: List(ViewField)
  narrows: Option(Text)
  load: fn(Store) : Result(List(Map(Text, Json)), Text)
end

## Approved statistical / aggregate release function guarded by `min_group_size` (k-anonymity).
## `run` returns `(cohort_size, payload_json)`; `Modb.Views` centrally refuses if `cohort_size < min_group_size`.
struct ReleaseDef
  name: Text
  description: Text
  source_buckets: List(Text)
  min_group_size: Int
  args_description: Text
  run: fn(Store, Json) : Result((Int, Json), Text)
end

## Self-describing metadata for one write action shown in agent onboarding manifests.
struct ActionDoc
  name: Text
  description: Text
  args_hint: Text
end

## Self-describing metadata for one commit-time invariant shown in agent onboarding manifests.
struct InvariantDoc
  name: Text
  description: Text
end

## Registry of approved views, releases, and onboarding documentation.
struct ViewCatalog
  views: Map(Text, ViewDef)
  releases: Map(Text, ReleaseDef)
  action_docs: Map(Text, ActionDoc)
  invariant_docs: List(InvariantDoc)
end

## Composable read-only filter predicate evaluated over narrowed View rows.
enum Pred
  Eq(field: Text, value: Json)
  Neq(field: Text, value: Json)
  Gt(field: Text, value: Json)
  Gte(field: Text, value: Json)
  Lt(field: Text, value: Json)
  Lte(field: Text, value: Json)
  Contains(field: Text, substr: Text)
  StartsWith(field: Text, prefix: Text)
  InList(field: Text, values: List(Json))
  IsNull(field: Text)
  NotNull(field: Text)
  And(preds: List(Pred))
  Or(preds: List(Pred))
  Not(pred: Pred)
end

## Supported ad-hoc grouping/aggregate operations.
enum AggOp
  Count
  Sum(field: Text)
  Min(field: Text)
  Max(field: Text)
  Avg(field: Text)
end

## One output aggregate column in a grouped/aggregated `ReadProgram`.
struct AggSpec
  alias: Text
  op: AggOp
end

## Sort specification for `ReadProgram` output rows.
struct SortSpec
  field: Text
  desc: Bool
end

## Zero-approval sandboxed ad-hoc read pipeline over a single authorized View.
struct ReadProgram
  view: Text
  where_clause: Option(Pred)
  select: Option(List(Text))
  group_by: Option(Text)
  aggregates: Option(List(AggSpec))
  order_by: Option(SortSpec)
  limit: Option(Int)
end

## Explicit work bounds enforced during sandboxed read execution.
struct ReadLimits
  max_rows_scanned: Int
  max_ops: Int
  max_result_rows: Int
end

## Output of executing a zero-approval `ReadProgram`.
struct ReadResult
  view: Text
  txid: Int
  rows_scanned: Int
  ops_used: Int
  result_count: Int
  answer_hash: Text
  rows: List(Json)
end

## Output of executing an approved k-anonymous `ReleaseDef`.
struct ReleaseResult
  release: Text
  txid: Int
  cohort_size: Int
  min_group_size: Int
  answer_hash: Text
  data: Json
end

## Provenance entry kind recorded in `_modb_read_log`.
enum ReadKind
  AdHocProgram
  ApprovedRelease
end

## Immutable read provenance record persisted in `_modb_read_log`.
struct ReadLogEntry
  seq: Int
  txid: Int
  principal: Text
  grant_id: Option(Text)
  kind: ReadKind
  target: Text
  request_json: Json
  rows_scanned: Int
  result_count: Int
  answer_hash: Text
  at: Time
end

struct ReadMeta
  next_read_seq: Int
end

## Public summary of a View shown in an agent's `OnboardingManifest`.
struct ViewSummary
  name: Text
  description: Text
  narrows: Option(Text)
  fields: List(ViewField)
end

## Public summary of a Release shown in an agent's `OnboardingManifest`.
struct ReleaseSummary
  name: Text
  description: Text
  min_group_size: Int
  args_description: Text
end

## Active Grant summary shown in an agent's `OnboardingManifest`.
struct CallerGrantInfo
  grant_id: Text
  parent_id: Option(Text)
  principal: Text
  chain: List(Text)
  remaining_calls: Int
  max_calls: Int
  expires_at: Time
  active: Bool
end

## Complete self-onboarding manifest answering `design.md` §6 Need 6 ("teach a stateless agent what it may do").
struct OnboardingManifest
  txid: Int
  schema_version: Int
  audit_count: Int
  require_reason: Bool
  principal: Text
  role: Text
  grant: Option(CallerGrantInfo)
  allowed_actions: List(ActionDoc)
  allowed_views: List(ViewSummary)
  allowed_releases: List(ReleaseSummary)
  active_claims: List(Claims.Claim)
  open_worlds: List(Text)
  invariants: List(InvariantDoc)
  read_limits: ReadLimits
end

## Sensible default work bounds for ad-hoc read programs.
fn default_limits() : ReadLimits
  ReadLimits(max_rows_scanned: 10000, max_ops: 100000, max_result_rows: 500)
end

## Creates an empty `ViewCatalog`.
fn catalog() : ViewCatalog
  ViewCatalog(views: {}, releases: {}, action_docs: {}, invariant_docs: [])
end

## Registers a narrowed `ViewDef` in `cat`.
fn with_view(cat: ViewCatalog, vdef: ViewDef) : ViewCatalog
  var next = cat
  next.views = next.views.set(vdef.name, vdef)
  next
end

## Registers an approved k-anonymous `ReleaseDef` in `cat`.
fn with_release(cat: ViewCatalog, rdef: ReleaseDef) : ViewCatalog
  var next = cat
  next.releases = next.releases.set(rdef.name, rdef)
  next
end

## Registers documentation for a write action shown in `OnboardingManifest`.
fn with_action_doc(cat: ViewCatalog, name: Text, description: Text, args_hint: Text) : ViewCatalog
  var next = cat
  next.action_docs = next.action_docs.set(
    name,
    ActionDoc(name: name, description: description, args_hint: args_hint)
  )
  next
end

## Registers documentation for a commit-time invariant shown in `OnboardingManifest`.
fn with_invariant_doc(cat: ViewCatalog, name: Text, description: Text) : ViewCatalog
  var next = cat
  next.invariant_docs = next.invariant_docs.append(
    InvariantDoc(name: name, description: description)
  )
  next
end

## Builds the `narrow_view -> wider_view` hierarchy map for `Modb.Grants` view-attenuation checks.
fn view_narrows_map(cat: ViewCatalog) : Map(Text, Text)
  var out = {}
  for (vname, vdef) in cat.views.entries
    case vdef.narrows
      Some(wider): out = out.set(vname, wider)
      None: Unit
    end
  end
  out
end

fn read_log_table() : Table(Int, ReadLogEntry)
  Table.int_key[ReadLogEntry](read_log_bucket)
end

fn read_meta_table() : Table(Text, ReadMeta)
  Table.text_key[ReadMeta](read_meta_bucket)
end

fn wrap_table(res: Result(T, TableError)) : Result(T, ViewsError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, ViewsError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(Table.Storage(e))) end)
end

fn hash_json(val: Json) : Text
  Crypto.sha256(Json.encode(val).bytes).to_hex
end

fn field_map_of(vdef: ViewDef) : Map(Text, ViewField)
  var m = {}
  for f in vdef.fields
    m = m.set(f.name, f)
  end
  m
end

fn field_names_of(vdef: ViewDef) : List(Text)
  vdef.fields.map(fn(f) f.name end)
end

fn require_view_field(vdef: ViewDef, fmap: Map(Text, ViewField), field: Text) : Result(
  ViewField,
  ViewsError
)
  case fmap.get(field)
    Some(vf): Ok(vf)
    None: Error(FieldNotInView(view: vdef.name, field: field, allowed: field_names_of(vdef)))
  end
end

fn is_numeric_field_type?(ft: Text) : Bool
  ft == "int" or ft == "float" or ft == "decimal" or ft == "number"
end

fn validate_pred(vdef: ViewDef, fmap: Map(Text, ViewField), pred: Pred) : Result(Unit, ViewsError)
  case pred
    Eq(field: f, value: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    Neq(field: f, value: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    Gt(field: f, value: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    Gte(field: f, value: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    Lt(field: f, value: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    Lte(field: f, value: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    Contains(field: f, substr: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    StartsWith(field: f, prefix: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    InList(field: f, values: _):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    IsNull(field: f):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    NotNull(field: f):
      _ = try require_view_field(vdef, fmap, f)
      Ok(Unit)
    And(preds: ps):
      for p in ps
        try validate_pred(vdef, fmap, p)
      end
      Ok(Unit)
    Or(preds: ps):
      for p in ps
        try validate_pred(vdef, fmap, p)
      end
      Ok(Unit)
    Not(pred: p): validate_pred(vdef, fmap, p)
  end
end

## Statically type- and field-checks `prog` against `vdef` BEFORE scanning a single row.
## Rejects any reference to a field hidden by the View (`FieldNotInView`).
fn validate_program(vdef: ViewDef, prog: ReadProgram) : Result(Unit, ViewsError)
  fmap = field_map_of(vdef)
  case prog.where_clause
    Some(p): try validate_pred(vdef, fmap, p)
    None: Unit
  end
  case prog.limit
    Some(lim) if lim < 0: return Error(InvalidProgram(reason: "limit must be >= 0"))
    Some(_) | None: Unit
  end

  var output_fields = Set.empty
  is_agg? = (prog.group_by is Some(_)) or (prog.aggregates is Some(_))
  if is_agg?
    case prog.group_by
      Some(gf):
        _ = try require_view_field(vdef, fmap, gf)
        output_fields = output_fields.add(gf)
      None: Unit
    end
    aggs = prog.aggregates or []
    if aggs.empty?
      return Error(InvalidProgram(reason: "group_by requires at least one aggregate spec"))
    end
    for a in aggs
      if a.alias.trim.empty?
        return Error(InvalidProgram(reason: "aggregate alias cannot be empty"))
      end
      case a.op
        Count: Unit
        Sum(field: f) | Avg(field: f):
          vf = try require_view_field(vdef, fmap, f)
          if not is_numeric_field_type?(vf.field_type)
            return Error(
              InvalidProgram(
                reason: "numeric aggregate requires numeric field, but '#{f}' has type '#{vf
                  .field_type}'"
              )
            )
          end
        Min(field: f) | Max(field: f): _ = try require_view_field(vdef, fmap, f)
      end
      output_fields = output_fields.add(a.alias)
    end
    case prog.select
      Some(cols):
        for c in cols
          if not output_fields.has?(c)
            return Error(
              InvalidProgram(reason: "select column '#{c}' is not produced by group_by/aggregates")
            )
          end
        end
      None: Unit
    end
    case prog.order_by
      Some(s):
        if not output_fields.has?(s.field)
          return Error(
            InvalidProgram(reason: "order_by field '#{s.field}' is not produced by aggregates")
          )
        end
      None: Unit
    end
  else
    case prog.select
      Some(cols):
        if cols.empty?
          return Error(InvalidProgram(reason: "select list cannot be empty"))
        end
        for c in cols
          _ = try require_view_field(vdef, fmap, c)
        end
      None: Unit
    end
    case prog.order_by
      Some(s): _ = try require_view_field(vdef, fmap, s.field)
      None: Unit
    end
  end
  Ok(Unit)
end

fn json_as_int(v: Json) : Option(Int)
  case v
    Json.Number(n): n.to_int
    Json.Null | Json.Boolean(_) | Json.String(_) | Json.Array(_) | Json.Object(_): None
  end
end

fn json_as_text(v: Json) : Option(Text)
  case v
    Json.String(s): Some(s)
    Json.Null | Json.Boolean(_) | Json.Number(_) | Json.Array(_) | Json.Object(_): None
  end
end

## Deterministic total ordering over scalar `Json` values for comparisons and sorting.
## Returns `-1` (a < b), `0` (a == b), or `1` (a > b).
fn compare_json(a: Json, b: Json) : Int
  case json_as_int(a)
    Some(ia):
      case json_as_int(b)
        Some(ib): return if ia < ib: -1 else if ia > ib: 1 else: 0
        None: Unit
      end
    None: Unit
  end
  case a
    Json.Null:
      case b
        Json.Null: 0
        Json.Boolean(_) | Json.Number(_) | Json.String(_) | Json.Array(_) | Json.Object(_): -1
      end
    Json.Boolean(ba):
      case b
        Json.Null: 1
        Json.Boolean(bb): if ba == bb: 0 else if not ba: -1 else: 1
        Json.Number(_) | Json.String(_) | Json.Array(_) | Json.Object(_):
          ta = a.to_text
          tb = b.to_text
          if ta < tb: -1 else if ta > tb: 1 else: 0
      end
    Json.String(sa):
      case b
        Json.Null: 1
        Json.String(sb): if sa < sb: -1 else if sa > sb: 1 else: 0
        Json.Boolean(_) | Json.Number(_) | Json.Array(_) | Json.Object(_):
          ta = a.to_text
          tb = b.to_text
          if ta < tb: -1 else if ta > tb: 1 else: 0
      end
    Json.Number(_) | Json.Array(_) | Json.Object(_):
      case b
        Json.Null: 1
        Json.Boolean(_) | Json.Number(_) | Json.String(_) | Json.Array(_) | Json.Object(_):
          ta = a.to_text
          tb = b.to_text
          if ta < tb: -1 else if ta > tb: 1 else: 0
      end
  end
end

fn eval_pred(row: Map(Text, Json), pred: Pred, ops: Int, max_ops: Int) : Result(
  (Bool, Int),
  ViewsError
)
  next_ops = ops + 1
  if next_ops > max_ops
    return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
  end
  case pred
    Eq(field: f, value: target):
      actual = row.get(f) or Json.Null
      Ok((compare_json(actual, target) == 0, next_ops))
    Neq(field: f, value: target):
      actual = row.get(f) or Json.Null
      Ok((compare_json(actual, target) != 0, next_ops))
    Gt(field: f, value: target):
      actual = row.get(f) or Json.Null
      Ok((compare_json(actual, target) > 0, next_ops))
    Gte(field: f, value: target):
      actual = row.get(f) or Json.Null
      Ok((compare_json(actual, target) >= 0, next_ops))
    Lt(field: f, value: target):
      actual = row.get(f) or Json.Null
      Ok((compare_json(actual, target) < 0, next_ops))
    Lte(field: f, value: target):
      actual = row.get(f) or Json.Null
      Ok((compare_json(actual, target) <= 0, next_ops))
    Contains(field: f, substr: sub):
      matched = case json_as_text(row.get(f) or Json.Null)
        Some(s): s.contains?(sub)
        None: false
      end
      Ok((matched, next_ops))
    StartsWith(field: f, prefix: pfx):
      matched = case json_as_text(row.get(f) or Json.Null)
        Some(s): s.starts_with?(pfx)
        None: false
      end
      Ok((matched, next_ops))
    InList(field: f, values: vs):
      actual = row.get(f) or Json.Null
      var cur_ops = next_ops
      for cand in vs
        cur_ops += 1
        if cur_ops > max_ops
          return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
        end
        if compare_json(actual, cand) == 0
          return Ok((true, cur_ops))
        end
      end
      Ok((false, cur_ops))
    IsNull(field: f):
      actual = row.get(f) or Json.Null
      Ok((actual is Json.Null, next_ops))
    NotNull(field: f):
      actual = row.get(f) or Json.Null
      Ok((not (actual is Json.Null), next_ops))
    And(preds: ps):
      var cur_ops = next_ops
      for p in ps
        (ok, o2) = try eval_pred(row, p, cur_ops, max_ops)
        cur_ops = o2
        return Ok((false, cur_ops)) if not ok
      end
      Ok((true, cur_ops))
    Or(preds: ps):
      var cur_ops = next_ops
      for p in ps
        (ok, o2) = try eval_pred(row, p, cur_ops, max_ops)
        cur_ops = o2
        return Ok((true, cur_ops)) if ok
      end
      Ok((false, cur_ops))
    Not(pred: p):
      (ok, o2) = try eval_pred(row, p, next_ops, max_ops)
      Ok((not ok, o2))
  end
end

fn project_row(vdef: ViewDef, row: Map(Text, Json), select_opt: Option(List(Text))) : Map(
  Text,
  Json
)
  cols = case select_opt
    Some(cs): cs
    None: field_names_of(vdef)
  end
  var out = {}
  for c in cols
    out = out.set(c, row.get(c) or Json.Null)
  end
  out
end

fn compute_group_agg(
  group_rows: List(Map(Text, Json)),
  group_by_opt: Option(Text),
  group_val: Json,
  aggs: List(AggSpec),
  ops: Int,
  max_ops: Int
) : Result((Map(Text, Json), Int), ViewsError)
  var out = {}
  var cur_ops = ops
  case group_by_opt
    Some(gf): out = out.set(gf, group_val)
    None: Unit
  end
  for spec in aggs
    cur_ops += 1
    if cur_ops > max_ops
      return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
    end
    agg_val = case spec.op
      Count: Json.int(group_rows.size)
      Sum(field: f):
        var total = 0
        for r in group_rows
          cur_ops += 1
          if cur_ops > max_ops
            return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
          end
          total += json_as_int(r.get(f) or Json.Null) or 0
        end
        Json.int(total)
      Avg(field: f):
        var total = 0
        var cnt = 0
        for r in group_rows
          cur_ops += 1
          if cur_ops > max_ops
            return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
          end
          case json_as_int(r.get(f) or Json.Null)
            Some(n):
              total += n
              cnt += 1
            None: Unit
          end
        end
        if cnt == 0: Json.Null else: Json.int(total / cnt)
      Min(field: f):
        var best = None
        for r in group_rows
          cur_ops += 1
          if cur_ops > max_ops
            return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
          end
          val = r.get(f) or Json.Null
          if not (val is Json.Null)
            best = case best
              None: Some(val)
              Some(cur): if compare_json(val, cur) < 0: Some(val) else: Some(cur)
            end
          end
        end
        best or Json.Null
      Max(field: f):
        var best = None
        for r in group_rows
          cur_ops += 1
          if cur_ops > max_ops
            return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
          end
          val = r.get(f) or Json.Null
          if not (val is Json.Null)
            best = case best
              None: Some(val)
              Some(cur): if compare_json(val, cur) > 0: Some(val) else: Some(cur)
            end
          end
        end
        best or Json.Null
    end
    out = out.set(spec.alias, agg_val)
  end
  Ok((out, cur_ops))
end

fn sort_rows(rows: List(Map(Text, Json)), sort: SortSpec, ops: Int, max_ops: Int) : Result(
  (List(Map(Text, Json)), Int),
  ViewsError
)
  var sorted = []
  var cur_ops = ops
  for r in rows
    rv = r.get(sort.field) or Json.Null
    var pos = 0
    while pos < sorted.size
      cur_ops += 1
      if cur_ops > max_ops
        return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
      end
      existing = sorted.get(pos) or stop "sort idx"
      ev = existing.get(sort.field) or Json.Null
      cmp = compare_json(rv, ev)
      before? = if sort.desc: cmp > 0 else: cmp < 0
      break if before?
      pos += 1
    end
    sorted = sorted.take(pos).append(r).concat(sorted.drop(pos))
  end
  Ok((sorted, cur_ops))
end

fn authorize_view_read(
  store: Store,
  cat: ViewCatalog,
  view_name: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result(ViewDef, ViewsError)
  vdef = try cat.views.get(view_name).or_fail(UnknownView(name: view_name))
  case grant_id_opt
    Some(gid):
      _ = try Grants.verify_view(store, gid, view_name, view_narrows_map(cat), now).map_error(fn(e)
        GrantFailure(e)
      end)
      Ok(vdef)
    None:
      if is_admin
        Ok(vdef)
      else
        Error(GrantFailure(Grants.ViewDenied(id: "(no grant)", view: view_name)))
      end
  end
end

## Executes a zero-approval sandboxed `ReadProgram` on committed `store` (pure read-only).
## Enforces Grant authorization, static field/type checks BEFORE scanning, and `ReadLimits`.
fn execute_read_program(
  store: Store,
  cat: ViewCatalog,
  prog: ReadProgram,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: ReadLimits,
  now: Time
) : Result(ReadResult, ViewsError)
  vdef = try authorize_view_read(store, cat, prog.view, grant_id_opt, is_admin, now)
  try validate_program(vdef, prog)

  raw_rows = try vdef.load(store).map_error(fn(d) ViewLoadFailed(view: vdef.name, detail: d) end)
  var scanned = 0
  var ops = 0
  var matched = []

  for raw_row in raw_rows
    scanned += 1
    if scanned > limits.max_rows_scanned
      return Error(WorkBudgetExceeded(metric: "rows_scanned", limit: limits.max_rows_scanned))
    end
    ## Strictly project raw_row to vdef's declared fields (defense in depth against view leaks).
    narrowed = project_row(vdef, raw_row, None)
    keep? = case prog.where_clause
      Some(p):
        (ok, o2) = try eval_pred(narrowed, p, ops, limits.max_ops)
        ops = o2
        ok
      None:
        ops += 1
        if ops > limits.max_ops
          return Error(WorkBudgetExceeded(metric: "ops", limit: limits.max_ops))
        end
        true
    end
    if keep?
      matched = matched.append(narrowed)
    end
  end

  is_agg? = (prog.group_by is Some(_)) or (prog.aggregates is Some(_))
  var shaped = []
  if is_agg?
    aggs = prog.aggregates or []
    case prog.group_by
      None:
        (agg_row, o2) = try compute_group_agg(matched, None, Json.Null, aggs, ops, limits.max_ops)
        ops = o2
        shaped = [agg_row]
      Some(gf):
        var group_order = []
        var group_vals = {}
        var group_buckets = {}
        for r in matched
          ops += 1
          if ops > limits.max_ops
            return Error(WorkBudgetExceeded(metric: "ops", limit: limits.max_ops))
          end
          gv = r.get(gf) or Json.Null
          gk = gv.to_text
          if not group_buckets.has?(gk)
            group_order = group_order.append(gk)
            group_vals = group_vals.set(gk, gv)
            group_buckets = group_buckets.set(gk, [r])
          else
            prev = group_buckets.get(gk) or []
            group_buckets = group_buckets.set(gk, prev.append(r))
          end
        end
        for gk in group_order
          gv = group_vals.get(gk) or Json.Null
          grows = group_buckets.get(gk) or []
          (agg_row, o2) = try compute_group_agg(grows, Some(gf), gv, aggs, ops, limits.max_ops)
          ops = o2
          shaped = shaped.append(agg_row)
        end
    end
    case prog.select
      Some(cols):
        var projected = []
        for r in shaped
          var pr = {}
          for c in cols
            pr = pr.set(c, r.get(c) or Json.Null)
          end
          projected = projected.append(pr)
        end
        shaped = projected
      None: Unit
    end
  else
    for r in matched
      shaped = shaped.append(project_row(vdef, r, prog.select))
    end
  end

  case prog.order_by
    Some(s):
      (sr, o2) = try sort_rows(shaped, s, ops, limits.max_ops)
      shaped = sr
      ops = o2
    None: Unit
  end

  eff_limit = case prog.limit
    Some(l): if l < limits.max_result_rows: l else: limits.max_result_rows
    None: limits.max_result_rows
  end
  final_maps = if shaped.size > eff_limit: shaped.take(eff_limit) else: shaped
  final_json = final_maps.map(fn(m) Json.Object(m) end)
  ans_hash = hash_json(Json.Array(final_json))

  Ok(
    ReadResult(
      view: vdef.name,
      txid: Modb.txid(store),
      rows_scanned: scanned,
      ops_used: ops,
      result_count: final_json.size,
      answer_hash: ans_hash,
      rows: final_json
    )
  )
end

## Executes an approved k-anonymous `ReleaseDef` on committed `store` (pure read-only).
## Centrally enforces Grant authorization and `cohort_size >= rdef.min_group_size`.
fn execute_release(
  store: Store,
  cat: ViewCatalog,
  release_name: Text,
  args: Json,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result(ReleaseResult, ViewsError)
  rdef = try cat.releases.get(release_name).or_fail(UnknownRelease(name: release_name))
  case grant_id_opt
    Some(gid): _ = try Grants.verify_release(store, gid, release_name, now).map_error(fn(e)
      GrantFailure(e)
    end)
    None:
      if not is_admin
        return Error(GrantFailure(Grants.ReleaseDenied(id: "(no grant)", release: release_name)))
      end
  end
  (cohort_size, payload) = try rdef.run(store, args).map_error(fn(d)
    ReleaseFailed(release: release_name, detail: d)
  end)
  if cohort_size < rdef.min_group_size
    return Error(
      ReleaseThresholdBlocked(
        release: release_name,
        min_group_size: rdef.min_group_size,
        actual_count: cohort_size
      )
    )
  end
  Ok(
    ReleaseResult(
      release: release_name,
      txid: Modb.txid(store),
      cohort_size: cohort_size,
      min_group_size: rdef.min_group_size,
      answer_hash: hash_json(payload),
      data: payload
    )
  )
end

fn append_read_log(
  db: Db,
  principal: Text,
  grant_id: Option(Text),
  kind: ReadKind,
  target: Text,
  req_json: Json,
  read_txid: Int,
  rows_scanned: Int,
  result_count: Int,
  answer_hash: Text,
  at: Time
) : Result((Db, ReadLogEntry), ViewsError)
  tx0 = Modb.begin_write(Ledger.store(db))
  meta = (try wrap_table(Table.tx_get(tx0, read_meta_table(), "meta"))) or
    ReadMeta(next_read_seq: 1)
  seq = meta.next_read_seq
  entry = ReadLogEntry(
    seq: seq,
    txid: read_txid,
    principal: principal,
    grant_id: grant_id,
    kind: kind,
    target: target,
    request_json: req_json,
    rows_scanned: rows_scanned,
    result_count: result_count,
    answer_hash: answer_hash,
    at: at
  )
  tx1 = try wrap_table(Table.put(tx0, read_log_table(), seq, entry))
  tx2 = try wrap_table(Table.put(tx1, read_meta_table(), "meta", ReadMeta(next_read_seq: seq + 1)))
  committed = try wrap_modb(Modb.commit(tx2))
  Ok((Ledger.update_store(db, committed), entry))
end

## Executes a `ReadProgram` and persists its provenance entry in `_modb_read_log`.
fn execute_read_program_recorded(
  db: Db,
  cat: ViewCatalog,
  prog: ReadProgram,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: ReadLimits,
  now: Time
) : Result((Db, ReadResult, ReadLogEntry), ViewsError)
  res = try execute_read_program(Ledger.store(db), cat, prog, grant_id_opt, is_admin, limits, now)
  (next_db, entry) = try append_read_log(
    db,
    principal,
    grant_id_opt,
    AdHocProgram,
    prog.view,
    prog.to_json,
    res.txid,
    res.rows_scanned,
    res.result_count,
    res.answer_hash,
    now
  )
  Ok((next_db, res, entry))
end

## Executes an approved `ReleaseDef` and persists its provenance entry in `_modb_read_log`.
fn execute_release_recorded(
  db: Db,
  cat: ViewCatalog,
  release_name: Text,
  args: Json,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result((Db, ReleaseResult, ReadLogEntry), ViewsError)
  res = try execute_release(Ledger.store(db), cat, release_name, args, grant_id_opt, is_admin, now)
  (next_db, entry) = try append_read_log(
    db,
    principal,
    grant_id_opt,
    ApprovedRelease,
    release_name,
    args,
    res.txid,
    res.cohort_size,
    1,
    res.answer_hash,
    now
  )
  Ok((next_db, res, entry))
end

## Lists persisted read provenance entries in ascending sequence order (optional tail `limit`).
fn list_read_log(store: Store, limit: Int) : Result(List(ReadLogEntry), ViewsError)
  rows = try wrap_table(Table.all(store, read_log_table()))
  all = rows.map(fn(p) p.1 end)
  if limit > 0 and all.size > limit
    Ok(all.drop(all.size - limit))
  else
    Ok(all)
  end
end

fn list_has_text?(xs: List(Text), target: Text) : Bool
  for x in xs
    return true if x == target
  end
  false
end

## Builds the caller-tailored `OnboardingManifest` (`design.md` §6 Need 6), exposing ONLY the
## actions, narrowed views (and their visible fields), releases, active claims, open worlds,
## commit-time invariants, and read limits applicable to this caller/grant.
fn describe_for_caller(
  db: Db,
  cat: ViewCatalog,
  principal: Text,
  role_label: Text,
  is_admin: Bool,
  direct_actions: List(Text),
  grant_id_opt: Option(Text),
  limits: ReadLimits,
  now: Time
) : Result(OnboardingManifest, ViewsError)
  store = Ledger.store(db)
  narrows = view_narrows_map(cat)

  var grant_info = None
  var perm_action_names = direct_actions
  var perm_view_names = None
  var perm_release_names = None
  var effective_principal = principal

  case grant_id_opt
    Some(gid):
      g_opt = try Grants.get(store, gid).map_error(fn(e) GrantFailure(e) end)
      g = try g_opt.or_fail(GrantFailure(Grants.GrantNotFound(id: gid)))
      active? = Grants.tx_verify_active(Modb.begin_write(store), gid, now) is Ok(_)
      rem = g.max_calls - g.used_calls
      grant_info = Some(
        CallerGrantInfo(
          grant_id: g.id,
          parent_id: g.parent_id,
          principal: g.principal,
          chain: g.chain,
          remaining_calls: if rem < 0: 0 else: rem,
          max_calls: g.max_calls,
          expires_at: g.expires_at,
          active: active?
        )
      )
      effective_principal = g.principal
      if active?
        perm_action_names = g.allowed_actions
        perm_view_names = Some(g.allowed_views or [])
        perm_release_names = Some(g.allowed_releases or [])
      else
        perm_action_names = []
        perm_view_names = Some([])
        perm_release_names = Some([])
      end
    None:
      if is_admin
        perm_action_names = cat.action_docs.keys
        perm_view_names = None
        perm_release_names = None
      else
        perm_view_names = Some([])
        perm_release_names = Some([])
      end
  end

  var allowed_actions = []
  for aname in perm_action_names
    case cat.action_docs.get(aname)
      Some(doc): allowed_actions = allowed_actions.append(doc)
      None: allowed_actions = allowed_actions.append(
        ActionDoc(name: aname, description: "permitted write action", args_hint: "{}")
      )
    end
  end

  var allowed_views = []
  for (vname, vdef) in cat.views.entries
    visible? = case perm_view_names
      None: is_admin
      Some(allowed): Grants.view_permitted_by?(allowed, vname, narrows)
    end
    if visible?
      allowed_views = allowed_views.append(
        ViewSummary(
          name: vdef.name,
          description: vdef.description,
          narrows: vdef.narrows,
          fields: vdef.fields
        )
      )
    end
  end

  var allowed_releases = []
  for (rname, rdef) in cat.releases.entries
    visible? = case perm_release_names
      None: is_admin
      Some(allowed): list_has_text?(allowed, rname)
    end
    if visible?
      allowed_releases = allowed_releases.append(
        ReleaseSummary(
          name: rdef.name,
          description: rdef.description,
          min_group_size: rdef.min_group_size,
          args_description: rdef.args_description
        )
      )
    end
  end

  claims = try Claims.list_active(store, now).map_error(fn(ce)
    case ce
      Claims.LedgerFailure(le): LedgerFailure(le)
      Claims.InvalidClaim(reason: _) | Claims.AlreadyClaimed(resource: _, holder: _, expires_at: _) | Claims
        .ClaimNotFound(resource: _) | Claims.NotHolder(resource: _, expected: _, actual: _): InvalidProgram(
          reason: ce.to_text
        )
    end
  end)
  all_worlds = try World.list_worlds(store).map_error(fn(we)
    case we
      World.LedgerFailure(le): LedgerFailure(le)
      World.GrantFailure(ge): GrantFailure(ge)
      World.WorldNotFound(id: _) | World.WorldAlreadyExists(id: _) | World.WorldNotOpen(
        id: _,
        status: _
      ) | World.WorldExpired(id: _) | World.UnknownQuery(name: _) | World.UnknownAction(name: _) | World
        .QueryFailed(query: _, detail: _) | World.ActionRejected(action: _, detail: _) | World
        .StaleRead(query: _, args: _, expected: _, actual: _) | World.InvariantRejected(
          name: _,
          detail: _
        ): InvalidProgram(reason: we.to_text)
    end
  end)
  var open_worlds = []
  for w in all_worlds
    if w.status is World.Open and (is_admin or w.principal == effective_principal)
      open_worlds = open_worlds.append(w.id)
    end
  end

  Ok(
    OnboardingManifest(
      txid: Ledger.txid(db),
      schema_version: Ledger.schema_version(db),
      audit_count: Ledger.audit_count(db),
      require_reason: db.schema.require_reason,
      principal: effective_principal,
      role: role_label,
      grant: grant_info,
      allowed_actions: allowed_actions,
      allowed_views: allowed_views,
      allowed_releases: allowed_releases,
      active_claims: claims,
      open_worlds: open_worlds,
      invariants: cat.invariant_docs,
      read_limits: limits
    )
  )
end

## Lock-coordinated sandboxed `ReadProgram` execution + provenance recording for multi-worker HTTP.
fn execute_read_program_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: ViewCatalog,
  prog: ReadProgram,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: ReadLimits,
  now: Time
) : Result(ReadResult, ViewsError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next_db, res, _entry) = try execute_read_program_recorded(
        db,
        cat,
        prog,
        principal,
        grant_id_opt,
        is_admin,
        limits,
        now
      )
      Ok(res)
    end
  )
end

## Lock-coordinated approved `ReleaseDef` execution + provenance recording for multi-worker HTTP.
fn execute_release_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: ViewCatalog,
  release_name: Text,
  args: Json,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result(ReleaseResult, ViewsError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next_db, res, _entry) = try execute_release_recorded(
        db,
        cat,
        release_name,
        args,
        principal,
        grant_id_opt,
        is_admin,
        now
      )
      Ok(res)
    end
  )
end

struct DemoItem
  id: Int
  category: Text
  cost: Int
  secret_note: Text
end

test "Modb.Views: narrowed views, static field rejection, k-anonymous release, and read log"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  sc = Ledger.schema(0).with_require_reason(false)
  tbl = Table.int_key[DemoItem]("items")
  assert Ledger.open(files, "views.modb", sc, t0) is Ok(db0)
  assert Ledger.write(
    db0,
    Ledger.WriteMeta(principal: "admin", action: "seed", reason: "init", at: t0),
    "seed 3 items",
    Json.Null,
    fn(tx)
      t_a = try Table.put(
        tx,
        tbl,
        1,
        DemoItem(id: 1, category: "ops", cost: 100, secret_note: "s1")
      )
      t_b = try Table.put(
        t_a,
        tbl,
        2,
        DemoItem(id: 2, category: "ops", cost: 300, secret_note: "s2")
      )
      Table.put(t_b, tbl, 3, DemoItem(id: 3, category: "ml", cost: 500, secret_note: "s3"))
    end
  ) is
    Ok(db1)

  vcat = catalog().with_view(
    ViewDef(
      name: "items_full",
      description: "Full items including cost",
      source_buckets: ["items"],
      fields: [
        ViewField(name: "id", field_type: "int", description: "id"),
        ViewField(name: "category", field_type: "text", description: "category"),
        ViewField(name: "cost", field_type: "int", description: "cost")
      ],
      narrows: None,
      load: fn(store)
        rows = try Table.all(store, tbl).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            it = p.1
            {"id": Json.int(it.id), "category": Json.String(it.category), "cost": Json.int(it.cost)}
          end)
        )
      end
    )
  ).with_view(
    ViewDef(
      name: "items_public",
      description: "Public items hiding cost and secret_note",
      source_buckets: ["items"],
      fields: [
        ViewField(name: "id", field_type: "int", description: "id"),
        ViewField(name: "category", field_type: "text", description: "category")
      ],
      narrows: Some("items_full"),
      load: fn(store)
        rows = try Table.all(store, tbl).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            it = p.1
            {"id": Json.int(it.id), "category": Json.String(it.category)}
          end)
        )
      end
    )
  ).with_release(
    ReleaseDef(
      name: "category_avg_cost",
      description: "Average cost for a category (min_group_size=2)",
      source_buckets: ["items"],
      min_group_size: 2,
      args_description: "{\"category\": \"ops\"}",
      run: fn(store, args)
        cat_name = try args.text_at("category").or_fail("missing category")
        rows = try Table.all(store, tbl).map_error(fn(e) e.to_text end)
        var sum = 0
        var cnt = 0
        for (_k, it) in rows
          if it.category == cat_name
            sum += it.cost
            cnt += 1
          end
        end
        avg = if cnt == 0: 0 else: sum / cnt
        Ok((
          cnt,
          Json.Object({
            "category": Json.String(cat_name),
            "count": Json.int(cnt),
            "avg_cost": Json.int(avg)
          })
        ))
      end
    )
  )

  ## Issue root grant with items_full -> delegate narrowed items_public
  assert Grants.issue_root_scoped(
    db1,
    Ledger.WriteMeta(principal: "admin", action: "issue_grant", reason: "root", at: t0),
    Grants.GrantSpec(
      id: "g-root",
      principal: "agent:lead",
      allowed_actions: ["noop"],
      max_calls: 10,
      expires_at: t1
    ),
    Some(["items_full"]),
    Some(["category_avg_cost"])
  ) is
    Ok((db2, _))
  assert Grants.delegate_scoped(
    db2,
    Ledger.WriteMeta(principal: "agent:lead", action: "delegate_grant", reason: "sub", at: t0),
    "g-root",
    Grants.GrantSpec(
      id: "g-sub",
      principal: "agent:helper",
      allowed_actions: ["noop"],
      max_calls: 5,
      expires_at: t1
    ),
    Some(["items_public"]),
    Some(["category_avg_cost"]),
    view_narrows_map(vcat)
  ) is
    Ok((db3, _))

  ## Negative control: g-sub querying hidden field `cost` on `items_public` fails statically!
  bad_prog = ReadProgram(
    view: "items_public",
    where_clause: Some(Gt(field: "cost", value: Json.int(50))),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert execute_read_program(
    Ledger.store(db3),
    vcat,
    bad_prog,
    Some("g-sub"),
    false,
    default_limits(),
    t0
  ) is
    Error(FieldNotInView(view: "items_public", field: "cost", allowed: _))

  ## Valid ad-hoc ReadProgram on `items_public` succeeds and records provenance
  good_prog = ReadProgram(
    view: "items_public",
    where_clause: Some(Eq(field: "category", value: Json.String("ops"))),
    select: Some(["id"]),
    group_by: None,
    aggregates: None,
    order_by: Some(SortSpec(field: "id", desc: true)),
    limit: Some(10)
  )
  assert execute_read_program_recorded(
    db3,
    vcat,
    good_prog,
    "agent:helper",
    Some("g-sub"),
    false,
    default_limits(),
    t0
  ) is
    Ok((db4, rres, rlog))
  assert rres.result_count == 2 and rlog.seq == 1

  ## Approved k-anonymous release: "ops" (2 rows >= 2) succeeds; "ml" (1 row < 2) blocked!
  assert execute_release_recorded(
    db4,
    vcat,
    "category_avg_cost",
    Json.Object({"category": Json.String("ops")}),
    "agent:helper",
    Some("g-sub"),
    false,
    t0
  ) is
    Ok((db5, rel_ok, _))
  assert rel_ok.cohort_size == 2
  assert execute_release(
    Ledger.store(db5),
    vcat,
    "category_avg_cost",
    Json.Object({"category": Json.String("ml")}),
    Some("g-sub"),
    false,
    t0
  ) is
    Error(ReleaseThresholdBlocked(release: "category_avg_cost", min_group_size: 2, actual_count: 1))

  ## Onboarding manifest for g-sub hides `items_full` and `cost` completely
  assert describe_for_caller(
    db5,
    vcat,
    "agent:helper",
    "worker",
    false,
    [],
    Some("g-sub"),
    default_limits(),
    t0
  ) is
    Ok(manifest)
  assert manifest.allowed_views.size == 1
  assert (manifest.allowed_views.first or stop "v").name == "items_public"
end
