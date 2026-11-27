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
ViewIndex(..),
ViewCompositeIndex(..),
ViewOrderedIndex(..),
QueryPlan(..),
ViewCatalog(..),
Pred(..),
AggOp(..),
AggSpec(..),
SortSpec(..),
ReadProgram(..),
ReadLimits(..),
ReadResult(..),
PagedReadResult(..),
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
read_log_table,
with_view,
with_view_index,
with_view_eq_index,
with_view_range_index,
with_view_composite_index,
with_view_composite_eq_index,
with_view_composite_range_index,
with_view_ordered_index,
with_release,
with_action_doc,
with_invariant_doc,
view_narrows_map,
validate_program,
plan_read_program,
explain_read_program,
execute_read_program,
execute_read_program_recorded,
execute_read_program_paged,
execute_read_program_paged_recorded,
execute_release,
execute_release_recorded,
list_read_log,
describe_for_caller,
execute_read_program_locked,
execute_read_program_paged_locked,
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

## Secondary or primary index lookup adapter attached to one field of a `ViewDef`.
struct ViewIndex
  field: Text
  supports_eq: Bool
  supports_range: Bool
  load_eq: fn(Store, Json) : Result(List(Map(Text, Json)), Text)
  load_range: fn(Store, Option(Json), Option(Json), Bool, Bool) : Result(
    List(Map(Text, Json)),
    Text
  )
end

## Composite multi-field index lookup adapter attached to an ordered list of fields on a `ViewDef`.
## When `supports_range_tail` is true, leading fields `[0..len-2]` use equality and the trailing field
## `fields[len-1]` accepts optional `[lo, hi]` range bounds.
struct ViewCompositeIndex
  name: Text
  fields: List(Text)
  supports_range_tail: Bool
  load_eq: fn(Store, List(Json)) : Result(List(Map(Text, Json)), Text)
  load_prefix_range: fn(Store, List(Json), Option(Json), Option(Json), Bool, Bool) : Result(
    List(Map(Text, Json)),
    Text
  )
end

## Ordered ascending index adapter allowing `OrderBy(field, asc) + Limit` early-stop pushdown.
struct ViewOrderedIndex
  field: Text
  load_ordered: fn(Store, Option(Json), Option(Json), Bool, Bool, Int) : Result(
    List(Map(Text, Json)),
    Text
  )
end

## Physical execution strategy chosen by `plan_read_program`.
enum QueryPlan
  PlanFullScan(view: Text, reason: Text)
  PlanIndexEq(view: Text, field: Text, value: Json)
  PlanIndexInList(view: Text, field: Text, values: List(Json))
  PlanIndexRange(
    view: Text,
    field: Text,
    lo: Option(Json),
    hi: Option(Json),
    lo_inclusive: Bool,
    hi_inclusive: Bool
  )
  PlanCompositeEq(view: Text, index_name: Text, fields: List(Text), values: List(Json))
  PlanCompositeRange(
    view: Text,
    index_name: Text,
    eq_fields: List(Text),
    eq_values: List(Json),
    range_field: Text,
    lo: Option(Json),
    hi: Option(Json),
    lo_inclusive: Bool,
    hi_inclusive: Bool
  )
  PlanIndexOrdered(
    view: Text,
    field: Text,
    lo: Option(Json),
    hi: Option(Json),
    lo_inclusive: Bool,
    hi_inclusive: Bool,
    limit_pushdown: Option(Int)
  )
end

## Registry of approved views, field indexes, composite/ordered indexes, releases, and onboarding docs.
struct ViewCatalog
  views: Map(Text, ViewDef)
  releases: Map(Text, ReleaseDef)
  action_docs: Map(Text, ActionDoc)
  invariant_docs: List(InvariantDoc)
  view_indexes: Map(Text, Map(Text, ViewIndex))
  composite_indexes: Map(Text, List(ViewCompositeIndex))
  ordered_indexes: Map(Text, Map(Text, ViewOrderedIndex))
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

## Keyset-paginated output returned by `execute_read_program_paged*`.
struct PagedReadResult
  result: ReadResult
  next_cursor: Option(Text)
  has_more: Bool
  page_size: Int
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
  ViewCatalog(
    views: {},
    releases: {},
    action_docs: {},
    invariant_docs: [],
    view_indexes: {},
    composite_indexes: {},
    ordered_indexes: {}
  )
end

## Registers a narrowed `ViewDef` in `cat`.
fn with_view(cat: ViewCatalog, vdef: ViewDef) : ViewCatalog
  var next = cat
  next.views = next.views.set(vdef.name, vdef)
  next
end

## Registers a `ViewIndex` on `view_name` for `idx.field`.
fn with_view_index(cat: ViewCatalog, view_name: Text, idx: ViewIndex) : ViewCatalog
  var next = cat
  cur_for_view = next.view_indexes.get(view_name) or {}
  next.view_indexes = next.view_indexes.set(view_name, cur_for_view.set(idx.field, idx))
  next
end

## Registers an equality-only `ViewIndex` (`PlanIndexEq` / `PlanIndexInList`) on `(view_name, field)`.
fn with_view_eq_index(
  cat: ViewCatalog,
  view_name: Text,
  field: Text,
  load_eq: fn(Store, Json) : Result(List(Map(Text, Json)), Text)
) : ViewCatalog
  with_view_index(
    cat,
    view_name,
    ViewIndex(
      field: field,
      supports_eq: true,
      supports_range: false,
      load_eq: load_eq,
      load_range: fn(_s, _lo, _hi, _li, _hi_inc) Ok([]) end
    )
  )
end

## Registers an ordered `ViewIndex` supporting both equality and range lookups on `(view_name, field)`.
fn with_view_range_index(
  cat: ViewCatalog,
  view_name: Text,
  field: Text,
  load_eq: fn(Store, Json) : Result(List(Map(Text, Json)), Text),
  load_range: fn(Store, Option(Json), Option(Json), Bool, Bool) : Result(
    List(Map(Text, Json)),
    Text
  )
) : ViewCatalog
  with_view_index(
    cat,
    view_name,
    ViewIndex(
      field: field,
      supports_eq: true,
      supports_range: true,
      load_eq: load_eq,
      load_range: load_range
    )
  )
end

## Registers a `ViewCompositeIndex` on `view_name`.
fn with_view_composite_index(cat: ViewCatalog, view_name: Text, idx: ViewCompositeIndex) : ViewCatalog
  var next = cat
  cur = next.composite_indexes.get(view_name) or []
  var updated = []
  var replaced? = false
  for existing in cur
    if existing.name == idx.name
      updated = updated.append(idx)
      replaced? = true
    else
      updated = updated.append(existing)
    end
  end
  if not replaced?
    updated = updated.append(idx)
  end
  next.composite_indexes = next.composite_indexes.set(view_name, updated)
  next
end

## Registers an equality-only composite index on `(view_name, fields)` (`PlanCompositeEq`).
fn with_view_composite_eq_index(
  cat: ViewCatalog,
  view_name: Text,
  name: Text,
  fields: List(Text),
  load_eq: fn(Store, List(Json)) : Result(List(Map(Text, Json)), Text)
) : ViewCatalog
  with_view_composite_index(
    cat,
    view_name,
    ViewCompositeIndex(
      name: name,
      fields: fields,
      supports_range_tail: false,
      load_eq: load_eq,
      load_prefix_range: fn(_s, _eqs, _lo, _hi, _li, _hi_inc) Ok([]) end
    )
  )
end

## Registers a prefix-equality + tail-range composite index on `(view_name, fields)` (`PlanCompositeEq` / `PlanCompositeRange`).
fn with_view_composite_range_index(
  cat: ViewCatalog,
  view_name: Text,
  name: Text,
  fields: List(Text),
  load_eq: fn(Store, List(Json)) : Result(List(Map(Text, Json)), Text),
  load_prefix_range: fn(Store, List(Json), Option(Json), Option(Json), Bool, Bool) : Result(
    List(Map(Text, Json)),
    Text
  )
) : ViewCatalog
  with_view_composite_index(
    cat,
    view_name,
    ViewCompositeIndex(
      name: name,
      fields: fields,
      supports_range_tail: true,
      load_eq: load_eq,
      load_prefix_range: load_prefix_range
    )
  )
end

## Registers an ascending-ordered index on `(view_name, field)` enabling `PlanIndexOrdered` and `OrderBy + Limit` early stop.
fn with_view_ordered_index(
  cat: ViewCatalog,
  view_name: Text,
  field: Text,
  load_ordered: fn(Store, Option(Json), Option(Json), Bool, Bool, Int) : Result(
    List(Map(Text, Json)),
    Text
  )
) : ViewCatalog
  var next = cat
  cur_for_view = next.ordered_indexes.get(view_name) or {}
  next.ordered_indexes = next.ordered_indexes.set(
    view_name,
    cur_for_view.set(field, ViewOrderedIndex(field: field, load_ordered: load_ordered))
  )
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

fn json_as_decimal(v: Json) : Option(Decimal)
  case v
    Json.Number(n): n.to_decimal
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
  case json_as_decimal(a)
    Some(da):
      case json_as_decimal(b)
        Some(db): return if da < db: -1 else if da > db: 1 else: 0
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

struct ReadCursor
  v: Int
  view: Text
  mode: Text
  sort_field: Option(Text)
  desc: Bool
  last_val: Json
  last_key: Text
  offset: Int
  emitted: Int
end

fn row_tie_key(row: Map(Text, Json)) : Text
  Json.encode(Json.Object(row))
end

fn compare_rows_with_tie(a: Map(Text, Json), b: Map(Text, Json), field: Text, desc: Bool) : Int
  cmp = compare_json(a.get(field) or Json.Null, b.get(field) or Json.Null)
  if cmp != 0
    return if desc: -cmp else: cmp
  end
  ka = row_tie_key(a)
  kb = row_tie_key(b)
  if ka < kb: -1 else if ka > kb: 1 else: 0
end

fn sort_rows_with_tie(rows: List(Map(Text, Json)), sort: SortSpec, ops: Int, max_ops: Int) : Result(
  (List(Map(Text, Json)), Int),
  ViewsError
)
  var sorted = []
  var cur_ops = ops
  for r in rows
    var pos = 0
    while pos < sorted.size
      cur_ops += 1
      if cur_ops > max_ops
        return Error(WorkBudgetExceeded(metric: "ops", limit: max_ops))
      end
      existing = sorted.get(pos) or stop "sort idx"
      if compare_rows_with_tie(r, existing, sort.field, sort.desc) < 0
        break
      end
      pos += 1
    end
    sorted = sorted.take(pos).append(r).concat(sorted.drop(pos))
  end
  Ok((sorted, cur_ops))
end

fn sort_rows(rows: List(Map(Text, Json)), sort: SortSpec, ops: Int, max_ops: Int) : Result(
  (List(Map(Text, Json)), Int),
  ViewsError
)
  sort_rows_with_tie(rows, sort, ops, max_ops)
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

fn flatten_conjuncts(pred: Pred) : List(Pred)
  case pred
    And(preds: ps):
      var out = []
      for p in ps
        for sub in flatten_conjuncts(p)
          out = out.append(sub)
        end
      end
      out
    Eq(field: _, value: _) | Neq(field: _, value: _) | Gt(field: _, value: _) | Gte(
      field: _,
      value: _
    ) | Lt(field: _, value: _) | Lte(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(
      field: _,
      prefix: _
    ) | InList(field: _, values: _) | IsNull(field: _) | NotNull(field: _) | Or(preds: _) | Not(
      pred: _
    ): [pred]
  end
end

fn dedup_json_values(vals: List(Json)) : List(Json)
  var out = []
  for v in vals
    if not out.any?(fn(x) compare_json(x, v) == 0 end)
      out = out.append(v)
    end
  end
  out
end

fn tighten_lower(cur_opt: Option(Json), cur_inc: Bool, cand: Json, cand_inc: Bool) : (
  Option(Json),
  Bool
)
  case cur_opt
    None: (Some(cand), cand_inc)
    Some(cur):
      cmp = compare_json(cand, cur)
      if cmp > 0
        (Some(cand), cand_inc)
      else if cmp == 0 and not cand_inc
        (Some(cur), false)
      else
        (Some(cur), cur_inc)
      end
  end
end

fn tighten_upper(cur_opt: Option(Json), cur_inc: Bool, cand: Json, cand_inc: Bool) : (
  Option(Json),
  Bool
)
  case cur_opt
    None: (Some(cand), cand_inc)
    Some(cur):
      cmp = compare_json(cand, cur)
      if cmp < 0
        (Some(cand), cand_inc)
      else if cmp == 0 and not cand_inc
        (Some(cur), false)
      else
        (Some(cur), cur_inc)
      end
  end
end

fn extract_eq_map(conjuncts: List(Pred)) : Map(Text, Json)
  var m = {}
  for c in conjuncts
    case c
      Eq(field: f, value: v):
        if m.get(f) is None
          m = m.set(f, v)
        end
      Neq(field: _, value: _) | Gt(field: _, value: _) | Gte(field: _, value: _) | Lt(
        field: _,
        value: _
      ) | Lte(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(field: _, prefix: _) | InList(
        field: _,
        values: _
      ) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(preds: _) | Not(pred: _): Unit
    end
  end
  m
end

fn extract_range_bounds(conjuncts: List(Pred), target_field: Text) : (
  Option(Json),
  Bool,
  Option(Json),
  Bool,
  Bool
)
  var lo_opt = None
  var lo_inc = true
  var hi_opt = None
  var hi_inc = true
  for c in conjuncts
    case c
      Gt(field: f, value: v) if f == target_field:
        (nl, nli) = tighten_lower(lo_opt, lo_inc, v, false)
        lo_opt = nl
        lo_inc = nli
      Gte(field: f, value: v) if f == target_field:
        (nl, nli) = tighten_lower(lo_opt, lo_inc, v, true)
        lo_opt = nl
        lo_inc = nli
      Lt(field: f, value: v) if f == target_field:
        (nh, nhi) = tighten_upper(hi_opt, hi_inc, v, false)
        hi_opt = nh
        hi_inc = nhi
      Lte(field: f, value: v) if f == target_field:
        (nh, nhi) = tighten_upper(hi_opt, hi_inc, v, true)
        hi_opt = nh
        hi_inc = nhi
      Eq(field: _, value: _) | Neq(field: _, value: _) | Gt(field: _, value: _) | Gte(
        field: _,
        value: _
      ) | Lt(field: _, value: _) | Lte(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(
        field: _,
        prefix: _
      ) | InList(field: _, values: _) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(
        preds: _
      ) | Not(pred: _): Unit
    end
  end
  has_any? = (lo_opt is Some(_)) or (hi_opt is Some(_))
  (lo_opt, lo_inc, hi_opt, hi_inc, has_any?)
end

fn try_plan_composite_eq(
  view_name: Text,
  comp_idxs: List(ViewCompositeIndex),
  eq_map: Map(Text, Json)
) : Option(QueryPlan)
  var best = None
  var best_arity = 0
  for cidx in comp_idxs
    if not cidx.fields.empty? and cidx.fields.size > best_arity
      var vals = []
      var all_hit? = true
      for f in cidx.fields
        case eq_map.get(f)
          Some(v): vals = vals.append(v)
          None: all_hit? = false
        end
      end
      if all_hit?
        best_arity = cidx.fields.size
        best = Some(
          PlanCompositeEq(view: view_name, index_name: cidx.name, fields: cidx.fields, values: vals)
        )
      end
    end
  end
  best
end

fn try_plan_composite_range(
  view_name: Text,
  comp_idxs: List(ViewCompositeIndex),
  eq_map: Map(Text, Json),
  conjuncts: List(Pred),
  require_tail_range: Bool
) : Option(QueryPlan)
  var best = None
  var best_arity = 0
  for cidx in comp_idxs
    if cidx.supports_range_tail and cidx.fields.size >= 2 and cidx.fields.size > best_arity
      prefix_fields = cidx.fields.take(cidx.fields.size - 1)
      tail_field = cidx.fields.last or ""
      var eq_vals = []
      var prefix_hit? = true
      for pf in prefix_fields
        case eq_map.get(pf)
          Some(v): eq_vals = eq_vals.append(v)
          None: prefix_hit? = false
        end
      end
      if prefix_hit?
        (lo_opt, lo_inc, hi_opt, hi_inc, has_any?) = extract_range_bounds(conjuncts, tail_field)
        if (not require_tail_range) or has_any?
          best_arity = cidx.fields.size
          best = Some(
            PlanCompositeRange(
              view: view_name,
              index_name: cidx.name,
              eq_fields: prefix_fields,
              eq_values: eq_vals,
              range_field: tail_field,
              lo: lo_opt,
              hi: hi_opt,
              lo_inclusive: lo_inc,
              hi_inclusive: hi_inc
            )
          )
        end
      end
    end
  end
  best
end

fn try_plan_single_range(
  vdef: ViewDef,
  idxs: Map(Text, ViewIndex),
  conjuncts: List(Pred),
  view_name: Text
) : Option(QueryPlan)
  for fdef in vdef.fields
    case idxs.get(fdef.name)
      Some(idx) if idx.supports_range:
        (lo_opt, lo_inc, hi_opt, hi_inc, has_any?) = extract_range_bounds(conjuncts, fdef.name)
        if has_any?
          return Some(
            PlanIndexRange(
              view: view_name,
              field: fdef.name,
              lo: lo_opt,
              hi: hi_opt,
              lo_inclusive: lo_inc,
              hi_inclusive: hi_inc
            )
          )
        end
      Some(_) | None: Unit
    end
  end
  None
end

fn find_field_idx(fields: List(Text), target: Text) : Option(Int)
  for i in 0..fields.size
    if (fields.get(i) or "") == target
      return Some(i)
    end
  end
  None
end

fn count_residual_for_plan(where_opt: Option(Pred), plan: QueryPlan) : Int
  where_pred = case where_opt
    Some(p): p
    None: return 0
  end
  conjuncts = flatten_conjuncts(where_pred)
  var residual = 0
  for c in conjuncts
    covered? = case plan
      PlanFullScan(view: _, reason: _): false
      PlanIndexEq(view: _, field: pf, value: pv):
        case c
          Eq(field: cf, value: cv): cf == pf and compare_json(cv, pv) == 0
          Neq(field: _, value: _) | Gt(field: _, value: _) | Gte(field: _, value: _) | Lt(
            field: _,
            value: _
          ) | Lte(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(
            field: _,
            prefix: _
          ) | InList(field: _, values: _) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(
            preds: _
          ) | Not(pred: _): false
        end
      PlanIndexInList(view: _, field: pf, values: _):
        case c
          InList(field: cf, values: _): cf == pf
          Eq(field: _, value: _) | Neq(field: _, value: _) | Gt(field: _, value: _) | Gte(
            field: _,
            value: _
          ) | Lt(field: _, value: _) | Lte(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(
            field: _,
            prefix: _
          ) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(preds: _) | Not(pred: _): false
        end
      PlanIndexRange(view: _, field: pf, lo: _, hi: _, lo_inclusive: _, hi_inclusive: _):
        case c
          Gt(field: cf, value: _) | Gte(field: cf, value: _) | Lt(field: cf, value: _) | Lte(
            field: cf,
            value: _
          ): cf == pf
          Eq(field: _, value: _) | Neq(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(
            field: _,
            prefix: _
          ) | InList(field: _, values: _) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(
            preds: _
          ) | Not(pred: _): false
        end
      PlanIndexOrdered(
        view: _,
        field: pf,
        lo: lo_opt,
        hi: hi_opt,
        lo_inclusive: _,
        hi_inclusive: _,
        limit_pushdown: _
      ):
        if (lo_opt is None) and (hi_opt is None)
          false
        else
          case c
            Gt(field: cf, value: _) | Gte(field: cf, value: _) | Lt(field: cf, value: _) | Lte(
              field: cf,
              value: _
            ): cf == pf
            Eq(field: _, value: _) | Neq(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(
              field: _,
              prefix: _
            ) | InList(field: _, values: _) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(
              preds: _
            ) | Not(pred: _): false
          end
        end
      PlanCompositeEq(view: _, index_name: _, fields: fs, values: vs):
        case c
          Eq(field: cf, value: cv):
            case find_field_idx(fs, cf)
              Some(idx):
                case vs.get(idx)
                  Some(pv): compare_json(cv, pv) == 0
                  None: false
                end
              None: false
            end
          Neq(field: _, value: _) | Gt(field: _, value: _) | Gte(field: _, value: _) | Lt(
            field: _,
            value: _
          ) | Lte(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(
            field: _,
            prefix: _
          ) | InList(field: _, values: _) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(
            preds: _
          ) | Not(pred: _): false
        end
      PlanCompositeRange(
        view: _,
        index_name: _,
        eq_fields: efs,
        eq_values: evs,
        range_field: rf,
        lo: lo_opt,
        hi: hi_opt,
        lo_inclusive: _,
        hi_inclusive: _
      ):
        case c
          Eq(field: cf, value: cv):
            case find_field_idx(efs, cf)
              Some(idx):
                case evs.get(idx)
                  Some(pv): compare_json(cv, pv) == 0
                  None: false
                end
              None: false
            end
          Gt(field: cf, value: _) | Gte(field: cf, value: _) | Lt(field: cf, value: _) | Lte(
            field: cf,
            value: _
          ): ((lo_opt is Some(_)) or (hi_opt is Some(_))) and cf == rf
          Neq(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(field: _, prefix: _) | InList(
            field: _,
            values: _
          ) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(preds: _) | Not(pred: _): false
        end
    end
    if not covered?
      residual += 1
    end
  end
  residual
end

fn ascending_order_field(prog: ReadProgram) : Option(Text)
  case (prog.group_by, prog.aggregates, prog.order_by)
    (None, None, Some(s)) if not s.desc: Some(s.field)
    (_, _, _): None
  end
end

## Chooses an index-accelerated `QueryPlan` when a registered `ViewCompositeIndex`, `ViewIndex`, or
## `ViewOrderedIndex` matches (`PlanCompositeEq` > `PlanCompositeRange` > `PlanIndexEq` >
## prefix `PlanCompositeRange` > `PlanIndexInList` > `PlanIndexOrdered` / `PlanIndexRange` > `PlanFullScan`).
fn plan_read_program(cat: ViewCatalog, prog: ReadProgram) : Result(QueryPlan, ViewsError)
  vdef = try cat.views.get(prog.view).or_fail(UnknownView(name: prog.view))
  try validate_program(vdef, prog)
  idxs = cat.view_indexes.get(prog.view) or {}
  comp_idxs = cat.composite_indexes.get(prog.view) or []
  ord_idxs = cat.ordered_indexes.get(prog.view) or {}
  if idxs.empty? and comp_idxs.empty? and ord_idxs.empty?
    return Ok(PlanFullScan(view: prog.view, reason: "no ViewIndex registered for '#{prog.view}'"))
  end

  ord_field_opt = ascending_order_field(prog)
  where_pred = case prog.where_clause
    Some(p): p
    None:
      case ord_field_opt
        Some(sf) if ord_idxs.get(sf) is Some(_): return Ok(
          PlanIndexOrdered(
            view: prog.view,
            field: sf,
            lo: None,
            hi: None,
            lo_inclusive: true,
            hi_inclusive: true,
            limit_pushdown: prog.limit
          )
        )
        Some(_) | None: return Ok(
          PlanFullScan(view: prog.view, reason: "unfiltered scan without WHERE clause")
        )
      end
  end

  conjuncts = flatten_conjuncts(where_pred)
  eq_map = extract_eq_map(conjuncts)

  # 1. Longest composite exact equality match
  case try_plan_composite_eq(prog.view, comp_idxs, eq_map)
    Some(p): return Ok(p)
    None: Unit
  end

  # 2. Composite prefix equality + trailing range match
  case try_plan_composite_range(prog.view, comp_idxs, eq_map, conjuncts, true)
    Some(p): return Ok(p)
    None: Unit
  end

  # 3. Single-field exact equality on any eq-indexed field
  for c in conjuncts
    case c
      Eq(field: f, value: v):
        case idxs.get(f)
          Some(idx) if idx.supports_eq: return Ok(PlanIndexEq(view: prog.view, field: f, value: v))
          Some(_) | None: Unit
        end
      Neq(field: _, value: _) | Gt(field: _, value: _) | Gte(field: _, value: _) | Lt(
        field: _,
        value: _
      ) | Lte(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(field: _, prefix: _) | InList(
        field: _,
        values: _
      ) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(preds: _) | Not(pred: _): Unit
    end
  end

  # 4. Composite prefix equality without trailing range bounds
  case try_plan_composite_range(prog.view, comp_idxs, eq_map, conjuncts, false)
    Some(p): return Ok(p)
    None: Unit
  end

  # 5. IN-list on any eq-indexed field
  for c in conjuncts
    case c
      InList(field: f, values: vs):
        case idxs.get(f)
          Some(idx) if idx.supports_eq: return Ok(
            PlanIndexInList(view: prog.view, field: f, values: dedup_json_values(vs))
          )
          Some(_) | None: Unit
        end
      Eq(field: _, value: _) | Neq(field: _, value: _) | Gt(field: _, value: _) | Gte(
        field: _,
        value: _
      ) | Lt(field: _, value: _) | Lte(field: _, value: _) | Contains(field: _, substr: _) | StartsWith(
        field: _,
        prefix: _
      ) | IsNull(field: _) | NotNull(field: _) | And(preds: _) | Or(preds: _) | Not(pred: _): Unit
    end
  end

  # 6. Ordered index (matching ascending OrderBy) vs single-field range index
  single_rng_opt = try_plan_single_range(vdef, idxs, conjuncts, prog.view)
  case ord_field_opt
    Some(sf) if ord_idxs.get(sf) is Some(_):
      (lo_s, li_s, hi_s, hi_s_inc, has_b_s) = extract_range_bounds(conjuncts, sf)
      if has_b_s or (single_rng_opt is None)
        base_plan = PlanIndexOrdered(
          view: prog.view,
          field: sf,
          lo: lo_s,
          hi: hi_s,
          lo_inclusive: li_s,
          hi_inclusive: hi_s_inc,
          limit_pushdown: None
        )
        res_cnt = count_residual_for_plan(prog.where_clause, base_plan)
        if res_cnt == 0
          return Ok(
            PlanIndexOrdered(
              view: prog.view,
              field: sf,
              lo: lo_s,
              hi: hi_s,
              lo_inclusive: li_s,
              hi_inclusive: hi_s_inc,
              limit_pushdown: prog.limit
            )
          )
        end
        return Ok(base_plan)
      end
    Some(_) | None: Unit
  end

  case single_rng_opt
    Some(p): Ok(p)
    None: Ok(PlanFullScan(view: prog.view, reason: "no selective indexed conjunct matched"))
  end
end

## Returns an inspection JSON summary describing how `plan_read_program` will execute `prog`.
fn explain_read_program(cat: ViewCatalog, prog: ReadProgram) : Result(Json, ViewsError)
  plan = try plan_read_program(cat, prog)
  res_cnt = count_residual_for_plan(prog.where_clause, plan)
  res_filter? = res_cnt > 0
  Ok(
    case plan
      PlanFullScan(view: v, reason: r): Json.Object({
        "view": Json.String(v),
        "strategy": Json.String("full_scan"),
        "index_used": Json.Boolean(false),
        "field": Json.Null,
        "reason": Json.String(r),
        "residual_filter": Json.Boolean(res_filter?),
        "residual_predicates": Json.int(res_cnt),
        "order_pushdown": Json.Boolean(false),
        "limit_pushdown": Json.Null
      })
      PlanIndexEq(view: v, field: f, value: val): Json.Object({
        "view": Json.String(v),
        "strategy": Json.String("index_eq"),
        "index_used": Json.Boolean(true),
        "field": Json.String(f),
        "value": val,
        "residual_filter": Json.Boolean(res_filter?),
        "residual_predicates": Json.int(res_cnt),
        "order_pushdown": Json.Boolean(false),
        "limit_pushdown": Json.Null
      })
      PlanIndexInList(view: v, field: f, values: vs): Json.Object({
        "view": Json.String(v),
        "strategy": Json.String("index_in_list"),
        "index_used": Json.Boolean(true),
        "field": Json.String(f),
        "values": Json.Array(vs),
        "residual_filter": Json.Boolean(res_filter?),
        "residual_predicates": Json.int(res_cnt),
        "order_pushdown": Json.Boolean(false),
        "limit_pushdown": Json.Null
      })
      PlanIndexRange(
        view: v,
        field: f,
        lo: lo_opt,
        hi: hi_opt,
        lo_inclusive: lo_inc,
        hi_inclusive: hi_inc
      ): Json.Object({
        "view": Json.String(v),
        "strategy": Json.String("index_range"),
        "index_used": Json.Boolean(true),
        "field": Json.String(f),
        "lo": lo_opt or Json.Null,
        "hi": hi_opt or Json.Null,
        "lo_inclusive": Json.Boolean(lo_inc),
        "hi_inclusive": Json.Boolean(hi_inc),
        "residual_filter": Json.Boolean(res_filter?),
        "residual_predicates": Json.int(res_cnt),
        "order_pushdown": Json.Boolean(false),
        "limit_pushdown": Json.Null
      })
      PlanCompositeEq(view: v, index_name: idx_name, fields: fs, values: vs): Json.Object({
        "view": Json.String(v),
        "strategy": Json.String("composite_eq"),
        "index_used": Json.Boolean(true),
        "index_name": Json.String(idx_name),
        "field": Json.String(fs.join("+")),
        "fields": Json.Array(fs.map(fn(s) Json.String(s) end)),
        "values": Json.Array(vs),
        "residual_filter": Json.Boolean(res_filter?),
        "residual_predicates": Json.int(res_cnt),
        "order_pushdown": Json.Boolean(false),
        "limit_pushdown": Json.Null
      })
      PlanCompositeRange(
        view: v,
        index_name: idx_name,
        eq_fields: efs,
        eq_values: evs,
        range_field: rf,
        lo: lo_opt,
        hi: hi_opt,
        lo_inclusive: lo_inc,
        hi_inclusive: hi_inc
      ): Json.Object({
        "view": Json.String(v),
        "strategy": Json.String("composite_range"),
        "index_used": Json.Boolean(true),
        "index_name": Json.String(idx_name),
        "field": Json.String(efs.append(rf).join("+")),
        "eq_fields": Json.Array(efs.map(fn(s) Json.String(s) end)),
        "eq_values": Json.Array(evs),
        "range_field": Json.String(rf),
        "lo": lo_opt or Json.Null,
        "hi": hi_opt or Json.Null,
        "lo_inclusive": Json.Boolean(lo_inc),
        "hi_inclusive": Json.Boolean(hi_inc),
        "residual_filter": Json.Boolean(res_filter?),
        "residual_predicates": Json.int(res_cnt),
        "order_pushdown": Json.Boolean(false),
        "limit_pushdown": Json.Null
      })
      PlanIndexOrdered(
        view: v,
        field: f,
        lo: lo_opt,
        hi: hi_opt,
        lo_inclusive: lo_inc,
        hi_inclusive: hi_inc,
        limit_pushdown: lim_opt
      ): Json.Object({
        "view": Json.String(v),
        "strategy": Json.String("index_ordered"),
        "index_used": Json.Boolean(true),
        "field": Json.String(f),
        "lo": lo_opt or Json.Null,
        "hi": hi_opt or Json.Null,
        "lo_inclusive": Json.Boolean(lo_inc),
        "hi_inclusive": Json.Boolean(hi_inc),
        "residual_filter": Json.Boolean(res_filter?),
        "residual_predicates": Json.int(res_cnt),
        "order_pushdown": Json.Boolean(true),
        "limit_pushdown": lim_opt.map(Json.int) or Json.Null
      })
    end
  )
end

fn find_composite_index(comp_idxs: List(ViewCompositeIndex), name: Text) : Option(
  ViewCompositeIndex
)
  for ci in comp_idxs
    return Some(ci) if ci.name == name
  end
  None
end

fn load_candidate_rows(
  store: Store,
  cat: ViewCatalog,
  vdef: ViewDef,
  plan: QueryPlan,
  max_result_rows: Int
) : Result(List(Map(Text, Json)), ViewsError)
  idxs = cat.view_indexes.get(vdef.name) or {}
  comp_idxs = cat.composite_indexes.get(vdef.name) or []
  ord_idxs = cat.ordered_indexes.get(vdef.name) or {}
  case plan
    PlanFullScan(view: _, reason: _): vdef.load(store).map_error(
      fn(d) ViewLoadFailed(view: vdef.name, detail: d) end
    )
    PlanIndexEq(view: _, field: f, value: val):
      case idxs.get(f)
        Some(idx): idx.load_eq(store, val).map_error(
          fn(d) ViewLoadFailed(view: vdef.name, detail: d) end
        )
        None: vdef.load(store).map_error(fn(d) ViewLoadFailed(view: vdef.name, detail: d) end)
      end
    PlanIndexInList(view: _, field: f, values: vals):
      case idxs.get(f)
        Some(idx):
          var combined = []
          for val in vals
            batch = try idx.load_eq(store, val).map_error(fn(d)
              ViewLoadFailed(view: vdef.name, detail: d)
            end)
            for row in batch
              combined = combined.append(row)
            end
          end
          Ok(combined)
        None: vdef.load(store).map_error(fn(d) ViewLoadFailed(view: vdef.name, detail: d) end)
      end
    PlanIndexRange(
      view: _,
      field: f,
      lo: lo_opt,
      hi: hi_opt,
      lo_inclusive: lo_inc,
      hi_inclusive: hi_inc
    ):
      case idxs.get(f)
        Some(idx) if idx.supports_range: idx.load_range(store, lo_opt, hi_opt, lo_inc, hi_inc)
          .map_error(fn(d)
            ViewLoadFailed(view: vdef.name, detail: d)
          end)
        Some(_) | None: vdef.load(store).map_error(
          fn(d) ViewLoadFailed(view: vdef.name, detail: d) end
        )
      end
    PlanCompositeEq(view: _, index_name: idx_name, fields: _, values: vals):
      case find_composite_index(comp_idxs, idx_name)
        Some(ci): ci.load_eq(store, vals).map_error(
          fn(d) ViewLoadFailed(view: vdef.name, detail: d) end
        )
        None: vdef.load(store).map_error(fn(d) ViewLoadFailed(view: vdef.name, detail: d) end)
      end
    PlanCompositeRange(
      view: _,
      index_name: idx_name,
      eq_fields: _,
      eq_values: eq_vals,
      range_field: _,
      lo: lo_opt,
      hi: hi_opt,
      lo_inclusive: lo_inc,
      hi_inclusive: hi_inc
    ):
      case find_composite_index(comp_idxs, idx_name)
        Some(ci) if ci.supports_range_tail: ci.load_prefix_range(
          store,
          eq_vals,
          lo_opt,
          hi_opt,
          lo_inc,
          hi_inc
        ).map_error(fn(d)
          ViewLoadFailed(view: vdef.name, detail: d)
        end)
        Some(_) | None: vdef.load(store).map_error(
          fn(d) ViewLoadFailed(view: vdef.name, detail: d) end
        )
      end
    PlanIndexOrdered(
      view: _,
      field: f,
      lo: lo_opt,
      hi: hi_opt,
      lo_inclusive: lo_inc,
      hi_inclusive: hi_inc,
      limit_pushdown: lp_opt
    ):
      case lp_opt
        Some(lp) if lp <= 0 or max_result_rows <= 0: return Ok([])
        Some(_) | None: Unit
      end
      pass_lim = case lp_opt
        Some(lp): if lp < max_result_rows: lp else: max_result_rows
        None: 0
      end
      case ord_idxs.get(f)
        Some(oi): oi.load_ordered(store, lo_opt, hi_opt, lo_inc, hi_inc, pass_lim).map_error(fn(d)
          ViewLoadFailed(view: vdef.name, detail: d)
        end)
        None: vdef.load(store).map_error(fn(d) ViewLoadFailed(view: vdef.name, detail: d) end)
      end
  end
end

fn decode_read_cursor(prog: ReadProgram, after_cursor: Option(Text)) : Result(
  Option(ReadCursor),
  ViewsError
)
  case after_cursor
    None: Ok(None)
    Some(tok):
      if tok.trim.empty?
        return Error(InvalidProgram(reason: "invalid pagination cursor: empty token"))
      end
      raw = try Bytes.from_base64url(tok).or_fail(
        InvalidProgram(reason: "invalid pagination cursor: invalid base64url")
      )
      txt = try raw.decode_utf8.or_fail(
        InvalidProgram(reason: "invalid pagination cursor: invalid UTF-8")
      )
      cur = try Json.decode[ReadCursor](txt).map_error(fn(e)
        InvalidProgram(reason: "invalid pagination cursor: #{e.to_text}")
      end)
      if cur.v != 1 or cur.view != prog.view
        return Error(InvalidProgram(reason: "invalid pagination cursor: view mismatch"))
      end
      case prog.order_by
        Some(s):
          if cur.mode != "keyset" or cur.sort_field != Some(s.field) or cur.desc != s.desc
            return Error(
              InvalidProgram(reason: "invalid pagination cursor: sort order does not match cursor")
            )
          end
        None:
          if cur.mode != "offset" or cur.offset < 0
            return Error(
              InvalidProgram(reason: "invalid pagination cursor: unsorted cursor mismatch")
            )
          end
      end
      Ok(Some(cur))
  end
end

fn row_after_keyset_cursor?(row: Map(Text, Json), cur: ReadCursor, sort: SortSpec) : Bool
  rv = row.get(sort.field) or Json.Null
  cmp = compare_json(rv, cur.last_val)
  directed = if sort.desc: -cmp else: cmp
  if directed > 0
    return true
  end
  if directed < 0
    return false
  end
  row_tie_key(row) > cur.last_key
end

fn plan_with_cursor_seek(
  cat: ViewCatalog,
  prog: ReadProgram,
  cursor_opt: Option(ReadCursor),
  paged?: Bool
) : Result(QueryPlan, ViewsError)
  eff_prog = case (cursor_opt, paged?)
    (Some(cur), true) if cur.mode == "keyset" and (not cur.desc) and (prog.group_by is None) and (
      prog.aggregates is None
    ):
      case cur.sort_field
        Some(sf):
          idxs = cat.view_indexes.get(prog.view) or {}
          ord_idxs = cat.ordered_indexes.get(prog.view) or {}
          has_range_idx? = case idxs.get(sf)
            Some(idx): idx.supports_range
            None: false
          end
          can_seek? = (ord_idxs.get(sf) is Some(_)) or has_range_idx?
          if can_seek?
            seek_pred = Gte(field: sf, value: cur.last_val)
            next_where = case prog.where_clause
              Some(w): Some(And(preds: [w, seek_pred]))
              None: Some(seek_pred)
            end
            ReadProgram(
              view: prog.view,
              where_clause: next_where,
              select: prog.select,
              group_by: prog.group_by,
              aggregates: prog.aggregates,
              order_by: prog.order_by,
              limit: None
            )
          else
            ReadProgram(
              view: prog.view,
              where_clause: prog.where_clause,
              select: prog.select,
              group_by: prog.group_by,
              aggregates: prog.aggregates,
              order_by: prog.order_by,
              limit: None
            )
          end
        None: prog
      end
    (_, true): ReadProgram(
      view: prog.view,
      where_clause: prog.where_clause,
      select: prog.select,
      group_by: prog.group_by,
      aggregates: prog.aggregates,
      order_by: prog.order_by,
      limit: None
    )
    (_, false): prog
  end
  plan_read_program(cat, eff_prog)
end

fn run_read_pipeline(
  store: Store,
  cat: ViewCatalog,
  prog: ReadProgram,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: ReadLimits,
  after_cursor: Option(Text),
  page_size_opt: Option(Int),
  now: Time
) : Result((ReadResult, Option(Text), Bool, Int), ViewsError)
  vdef = try authorize_view_read(store, cat, prog.view, grant_id_opt, is_admin, now)
  try validate_program(vdef, prog)
  case page_size_opt
    Some(ps):
      if ps <= 0
        return Error(InvalidProgram(reason: "page_size must be > 0"))
      end
      if ps > limits.max_result_rows
        return Error(WorkBudgetExceeded(metric: "result_rows", limit: limits.max_result_rows))
      end
    None: Unit
  end

  cursor_opt = try decode_read_cursor(prog, after_cursor)
  paged? = page_size_opt is Some(_)
  plan = try plan_with_cursor_seek(cat, prog, cursor_opt, paged?)
  res_lim = case prog.limit
    Some(l): if l < limits.max_result_rows: l else: limits.max_result_rows
    None: limits.max_result_rows
  end

  eff_stop_cap_opt = case (page_size_opt, cursor_opt, prog.limit)
    (None, _, _): Some(res_lim)
    (Some(ps), None, Some(l)): Some((if ps < l: ps else: l) + 1)
    (Some(ps), None, None): Some(ps + 1)
    (Some(ps), Some(cur), l_opt):
      if cur.mode == "keyset"
        rem = case l_opt
          Some(l):
            d = l - cur.emitted
            if d < 0: 0 else: d
          None: limits.max_result_rows
        end
        Some((if ps < rem: ps else: rem) + 1)
      else
        None
      end
  end

  can_early_stop? = case plan
    PlanIndexOrdered(
      view: _,
      field: sf,
      lo: _,
      hi: _,
      lo_inclusive: _,
      hi_inclusive: _,
      limit_pushdown: _
    ): (prog.group_by is None) and (prog.aggregates is None) and
      case prog.order_by
        Some(s): (not s.desc) and s.field == sf
        None: false
      end
    PlanFullScan(view: _, reason: _) | PlanIndexEq(view: _, field: _, value: _) | PlanIndexInList(
      view: _,
      field: _,
      values: _
    ) | PlanIndexRange(view: _, field: _, lo: _, hi: _, lo_inclusive: _, hi_inclusive: _) | PlanCompositeEq(
      view: _,
      index_name: _,
      fields: _,
      values: _
    ) | PlanCompositeRange(
      view: _,
      index_name: _,
      eq_fields: _,
      eq_values: _,
      range_field: _,
      lo: _,
      hi: _,
      lo_inclusive: _,
      hi_inclusive: _
    ): false
  end

  load_cap = case eff_stop_cap_opt
    Some(c): if c < limits.max_result_rows: c else: limits.max_result_rows
    None: limits.max_result_rows
  end
  raw_rows = try load_candidate_rows(store, cat, vdef, plan, load_cap)
  var scanned = 0
  var ops = 0
  var matched = []
  var ordered_monotone? = can_early_stop?
  var prev_sort_val = None
  var after_cursor_matches = 0
  var stop_boundary_val = None

  ord_field_name = case prog.order_by
    Some(s): s.field
    None: ""
  end

  for raw_row in raw_rows
    if can_early_stop? and ordered_monotone? and (eff_stop_cap_opt is Some(0))
      break
    end
    scanned += 1
    if scanned > limits.max_rows_scanned
      return Error(WorkBudgetExceeded(metric: "rows_scanned", limit: limits.max_rows_scanned))
    end
    narrowed = project_row(vdef, raw_row, None)
    if ordered_monotone?
      cur_sv = narrowed.get(ord_field_name) or Json.Null
      case prev_sort_val
        Some(psv):
          if compare_json(cur_sv, psv) < 0
            ordered_monotone? = false
          end
        None: Unit
      end
      prev_sort_val = Some(cur_sv)
    end
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
      if can_early_stop? and ordered_monotone?
        case eff_stop_cap_opt
          Some(stop_n):
            after? = case (cursor_opt, prog.order_by)
              (Some(cur), Some(s)) if cur.mode == "keyset": row_after_keyset_cursor?(
                narrowed,
                cur,
                s
              )
              (_, _): true
            end
            if after?
              after_cursor_matches += 1
              cur_sv = narrowed.get(ord_field_name) or Json.Null
              if after_cursor_matches == stop_n
                stop_boundary_val = Some(cur_sv)
              else if after_cursor_matches > stop_n
                case stop_boundary_val
                  Some(sbv):
                    if compare_json(cur_sv, sbv) > 0
                      break
                    end
                  None: Unit
                end
              end
            end
          None: Unit
        end
      end
    end
  end

  is_agg? = (prog.group_by is Some(_)) or (prog.aggregates is Some(_))
  var base_rows = []
  if is_agg?
    aggs = prog.aggregates or []
    case prog.group_by
      None:
        (agg_row, o2) = try compute_group_agg(matched, None, Json.Null, aggs, ops, limits.max_ops)
        ops = o2
        base_rows = [agg_row]
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
          base_rows = base_rows.append(agg_row)
        end
    end
  else
    base_rows = matched
  end

  var sorted_base = base_rows
  case prog.order_by
    Some(s):
      if can_early_stop? and ordered_monotone? and (not is_agg?)
        # Rows already ascending by s.field; stabilize tie-breaks within identical s.field buckets
        (sr, o2) = try sort_rows_with_tie(base_rows, s, ops, limits.max_ops)
        sorted_base = sr
        ops = o2
      else if paged?
        (sr, o2) = try sort_rows_with_tie(base_rows, s, ops, limits.max_ops)
        sorted_base = sr
        ops = o2
      else
        ## Preserve pre-M17 projection behavior on non-paged reads if select excludes order_by field
        pre_sort = if is_agg?
          case prog.select
            Some(cols): base_rows.map(fn(r)
              var pr = {}
              for c in cols
                pr = pr.set(c, r.get(c) or Json.Null)
              end
              pr
            end)
            None: base_rows
          end
        else
          base_rows.map(fn(r) project_row(vdef, r, prog.select) end)
        end
        (sr, o2) = try sort_rows(pre_sort, s, ops, limits.max_ops)
        ops = o2
        final_maps = if sr.size > res_lim: sr.take(res_lim) else: sr
        final_json = final_maps.map(fn(m) Json.Object(m) end)
        ans_hash = hash_json(Json.Array(final_json))
        return Ok((
          ReadResult(
            view: vdef.name,
            txid: Modb.txid(store),
            rows_scanned: scanned,
            ops_used: ops,
            result_count: final_json.size,
            answer_hash: ans_hash,
            rows: final_json
          ),
          None,
          false,
          final_json.size
        ))
      end
    None: Unit
  end

  if not paged?
    shaped_np = if is_agg?
      case prog.select
        Some(cols): sorted_base.map(fn(r)
          var pr = {}
          for c in cols
            pr = pr.set(c, r.get(c) or Json.Null)
          end
          pr
        end)
        None: sorted_base
      end
    else
      sorted_base.map(fn(r) project_row(vdef, r, prog.select) end)
    end
    final_maps = if shaped_np.size > res_lim: shaped_np.take(res_lim) else: shaped_np
    final_json = final_maps.map(fn(m) Json.Object(m) end)
    ans_hash = hash_json(Json.Array(final_json))
    return Ok((
      ReadResult(
        view: vdef.name,
        txid: Modb.txid(store),
        rows_scanned: scanned,
        ops_used: ops,
        result_count: final_json.size,
        answer_hash: ans_hash,
        rows: final_json
      ),
      None,
      false,
      final_json.size
    ))
  end

  ps = page_size_opt or limits.max_result_rows
  after_base = case (cursor_opt, prog.order_by)
    (Some(cur), Some(s)):
      var filtered = []
      for r in sorted_base
        if row_after_keyset_cursor?(r, cur, s)
          filtered = filtered.append(r)
        end
      end
      filtered
    (Some(cur), None): sorted_base.drop(cur.offset)
    (None, _): sorted_base
  end

  prev_emitted = case cursor_opt
    Some(cur): cur.emitted
    None: 0
  end
  remaining_cap = case prog.limit
    Some(l):
      d = l - prev_emitted
      if d < 0: 0 else: d
    None: after_base.size
  end
  capped_base = if after_base.size > remaining_cap: after_base.take(remaining_cap) else: after_base
  has_more = capped_base.size > ps
  page_raw = if has_more: capped_base.take(ps) else: capped_base
  next_cur = if has_more
    last_raw = page_raw.last or stop "non-empty page"
    next_emitted = prev_emitted + page_raw.size
    cur_obj = case prog.order_by
      Some(s): ReadCursor(
        v: 1,
        view: vdef.name,
        mode: "keyset",
        sort_field: Some(s.field),
        desc: s.desc,
        last_val: last_raw.get(s.field) or Json.Null,
        last_key: row_tie_key(last_raw),
        offset: 0,
        emitted: next_emitted
      )
      None:
        prev_off = case cursor_opt
          Some(c): c.offset
          None: 0
        end
        ReadCursor(
          v: 1,
          view: vdef.name,
          mode: "offset",
          sort_field: None,
          desc: false,
          last_val: Json.Null,
          last_key: "",
          offset: prev_off + page_raw.size,
          emitted: next_emitted
        )
    end
    Some(Json.encode(cur_obj.to_json).bytes.to_base64url)
  else
    None
  end

  page_projected = if is_agg?
    case prog.select
      Some(cols): page_raw.map(fn(r)
        var pr = {}
        for c in cols
          pr = pr.set(c, r.get(c) or Json.Null)
        end
        pr
      end)
      None: page_raw
    end
  else
    page_raw.map(fn(r) project_row(vdef, r, prog.select) end)
  end
  final_json = page_projected.map(fn(m) Json.Object(m) end)
  ans_hash = hash_json(Json.Array(final_json))
  Ok((
    ReadResult(
      view: vdef.name,
      txid: Modb.txid(store),
      rows_scanned: scanned,
      ops_used: ops,
      result_count: final_json.size,
      answer_hash: ans_hash,
      rows: final_json
    ),
    next_cur,
    has_more,
    ps
  ))
end

## Executes a zero-approval sandboxed `ReadProgram` on committed `store` (pure read-only).
## Enforces Grant authorization, static field/type checks BEFORE scanning, index-accelerated
## candidate loading when a registered `ViewCompositeIndex` / `ViewIndex` / `ViewOrderedIndex` applies,
## and `ReadLimits`.
fn execute_read_program(
  store: Store,
  cat: ViewCatalog,
  prog: ReadProgram,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: ReadLimits,
  now: Time
) : Result(ReadResult, ViewsError)
  (res, _nc, _hm, _ps) = try run_read_pipeline(
    store,
    cat,
    prog,
    grant_id_opt,
    is_admin,
    limits,
    None,
    None,
    now
  )
  Ok(res)
end

## Executes a zero-approval sandboxed `ReadProgram` with opaque keyset/offset cursor pagination.
fn execute_read_program_paged(
  store: Store,
  cat: ViewCatalog,
  prog: ReadProgram,
  after_cursor: Option(Text),
  page_size: Int,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: ReadLimits,
  now: Time
) : Result(PagedReadResult, ViewsError)
  (res, next_cur, has_more, eff_ps) = try run_read_pipeline(
    store,
    cat,
    prog,
    grant_id_opt,
    is_admin,
    limits,
    after_cursor,
    Some(page_size),
    now
  )
  Ok(PagedReadResult(result: res, next_cursor: next_cur, has_more: has_more, page_size: eff_ps))
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

## Executes a paginated `ReadProgram` and persists its provenance entry in `_modb_read_log`.
fn execute_read_program_paged_recorded(
  db: Db,
  cat: ViewCatalog,
  prog: ReadProgram,
  after_cursor: Option(Text),
  page_size: Int,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: ReadLimits,
  now: Time
) : Result((Db, PagedReadResult, ReadLogEntry), ViewsError)
  paged = try execute_read_program_paged(
    Ledger.store(db),
    cat,
    prog,
    after_cursor,
    page_size,
    grant_id_opt,
    is_admin,
    limits,
    now
  )
  req_meta = Json.Object({
    "program": prog.to_json,
    "after_cursor": after_cursor.map(fn(c) Json.String(c) end) or Json.Null,
    "page_size": Json.int(page_size)
  })
  (next_db, entry) = try append_read_log(
    db,
    principal,
    grant_id_opt,
    AdHocProgram,
    prog.view,
    req_meta,
    paged.result.txid,
    paged.result.rows_scanned,
    paged.result.result_count,
    paged.result.answer_hash,
    now
  )
  Ok((next_db, paged, entry))
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

## Lock-coordinated paginated `ReadProgram` execution + provenance recording for multi-worker HTTP.
fn execute_read_program_paged_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: ViewCatalog,
  prog: ReadProgram,
  after_cursor: Option(Text),
  page_size: Int,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: ReadLimits,
  now: Time
) : Result(PagedReadResult, ViewsError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next_db, paged, _entry) = try execute_read_program_paged_recorded(
        db,
        cat,
        prog,
        after_cursor,
        page_size,
        principal,
        grant_id_opt,
        is_admin,
        limits,
        now
      )
      Ok(paged)
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

test "plan_read_program and explain_read_program accelerate Eq, InList, and Range queries cleanly"
  assert Modb.open(Files.in_memory({}), "plan.modb") is Ok(s0)
  cat_idx = Table.text_index[Int, Json](
    "plan_items_by_cat",
    fn(r)
      r.text_at("category") or ""
    end
  )
  score_idx = Table.int_index[Int, Json]("plan_items_by_score", fn(r) r.int_at("score") or 0 end)
  items_tbl = Table.int_key[Json]("plan_items").with_index(cat_idx).with_index(score_idx)

  t0 = Time.parse("2026-11-26T12:00:00Z") or stop "time"
  tx0 = Modb.begin_write(s0)
  var tx = tx0
  var i = 1
  while i <= 40
    cat_val = if i <= 3
      "ops"
    else if i <= 6
      "ml"
    else
      "misc"
    end
    row = Json.Object({
      "id": Json.int(i),
      "category": Json.String(cat_val),
      "score": Json.int(i * 10),
      "secret": Json.String("s-#{i}")
    })
    assert Table.put(tx, items_tbl, i, row) is Ok(next_tx)
    tx = next_tx
    i += 1
  end
  assert Modb.commit(tx) is Ok(s1)

  vdef = ViewDef(
    name: "items_pub",
    description: "Public items",
    source_buckets: ["plan_items"],
    fields: [
      ViewField(name: "id", field_type: "int", description: "id"),
      ViewField(name: "category", field_type: "text", description: "cat"),
      ViewField(name: "score", field_type: "int", description: "score")
    ],
    narrows: None,
    load: fn(s)
      all_rows = try Table.all(s, items_tbl).map_error(fn(e) e.to_text end)
      Ok(
        all_rows.map(fn(p)
          r = p.1
          {
            "id": r.get("id") or Json.Null,
            "category": r.get("category") or Json.Null,
            "score": r.get("score") or Json.Null
          }
        end)
      )
    end
  )
  cat_v = with_view_range_index(
    with_view_eq_index(
      with_view(catalog(), vdef),
      "items_pub",
      "category",
      fn(s, jv)
        k = case jv
          Json.String(sv): sv
          Json.Null | Json.Boolean(_) | Json.Number(_) | Json.Array(_) | Json.Object(_): jv.to_text
        end
        rows = try Table.lookup(s, items_tbl, cat_idx, k).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            r = p.1
            {
              "id": r.get("id") or Json.Null,
              "category": r.get("category") or Json.Null,
              "score": r.get("score") or Json.Null
            }
          end)
        )
      end
    ),
    "items_pub",
    "score",
    fn(s, jv)
      k = Json.Object({"v": jv}).int_at("v") or 0
      rows = try Table.lookup(s, items_tbl, score_idx, k).map_error(fn(e) e.to_text end)
      Ok(
        rows.map(fn(p)
          r = p.1
          {
            "id": r.get("id") or Json.Null,
            "category": r.get("category") or Json.Null,
            "score": r.get("score") or Json.Null
          }
        end)
      )
    end,
    fn(s, lo_opt, hi_opt, lo_inc, hi_inc)
      lo_k = case lo_opt
        Some(jv):
          case Json.Object({"v": jv}).int_at("v")
            Some(iv): Some(if lo_inc: iv else: iv + 1)
            None: None
          end
        None: None
      end
      hi_k = case hi_opt
        Some(jv):
          case Json.Object({"v": jv}).int_at("v")
            Some(iv): Some(if hi_inc: iv + 1 else: iv)
            None: None
          end
        None: None
      end
      rows = try Table.range_by(s, items_tbl, score_idx, lo_k, hi_k, 0).map_error(fn(e)
        e.to_text
      end)
      Ok(
        rows.map(fn(p)
          r = p.1
          {
            "id": r.get("id") or Json.Null,
            "category": r.get("category") or Json.Null,
            "score": r.get("score") or Json.Null
          }
        end)
      )
    end
  )

  # Eq inside flattened And picks PlanIndexEq and scans only 3 rows instead of 40
  eq_prog = ReadProgram(
    view: "items_pub",
    where_clause: Some(
      And(
        preds: [
          Gt(field: "score", value: Json.int(10)),
          Eq(field: "category", value: Json.String("ops"))
        ]
      )
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: Some(SortSpec(field: "id", desc: false)),
    limit: None
  )
  assert plan_read_program(cat_v, eq_prog) is
    Ok(PlanIndexEq(view: "items_pub", field: "category", value: Json.String("ops")))
  assert explain_read_program(cat_v, eq_prog) is Ok(ex_eq) and
    ex_eq.text_at("strategy") == Some("index_eq")
  assert execute_read_program(s1, cat_v, eq_prog, None, true, default_limits(), t0) is Ok(r_eq)
  assert r_eq.rows_scanned == 3 and r_eq.result_count == 2

  # InList picks PlanIndexInList and deduplicates values
  in_prog = ReadProgram(
    view: "items_pub",
    where_clause: Some(
      InList(field: "category", values: [Json.String("ops"), Json.String("ml"), Json.String("ops")])
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert plan_read_program(cat_v, in_prog) is
    Ok(PlanIndexInList(view: "items_pub", field: "category", values: vs)) and
    vs.size == 2
  assert execute_read_program(s1, cat_v, in_prog, None, true, default_limits(), t0) is Ok(r_in)
  assert r_in.rows_scanned == 6 and r_in.result_count == 6

  # Range merges multiple conjuncts cleanly
  rng_prog = ReadProgram(
    view: "items_pub",
    where_clause: Some(
      And(
        preds: [
          Gte(field: "score", value: Json.int(50)),
          Gt(field: "score", value: Json.int(90)),
          Lte(field: "score", value: Json.int(130))
        ]
      )
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert plan_read_program(cat_v, rng_prog) is
    Ok(
      PlanIndexRange(
        view: "items_pub",
        field: "score",
        lo: Some(_),
        hi: Some(_),
        lo_inclusive: false,
        hi_inclusive: true
      )
    )
  assert execute_read_program(s1, cat_v, rng_prog, None, true, default_limits(), t0) is Ok(r_rng)
  assert r_rng.rows_scanned == 4 and r_rng.result_count == 4

  # Hidden field still blocked statically BEFORE scanning
  bad_hidden = ReadProgram(
    view: "items_pub",
    where_clause: Some(Eq(field: "secret", value: Json.String("s-1"))),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert plan_read_program(cat_v, bad_hidden) is
    Error(FieldNotInView(view: "items_pub", field: "secret", allowed: _))
end

test "M17 Views: composite eq/range pushdown, PlanIndexOrdered early-stop, and keyset cursor pagination"
  assert Modb.open(Files.in_memory({}), "m17-plan.modb") is Ok(s0)
  by_cat_score = Table.composite_index[Text, Int, Int, Json](
    "m17_items_by_cat_score",
    Table.text_codec(),
    Table.int_codec(),
    fn(r) (r.text_at("category") or "", r.int_at("score") or 0) end
  )
  tbl = Table.int_key[Json]("m17_items").with_index(by_cat_score)
  t0 = Time.parse("2026-11-26T12:00:00Z") or stop "time"
  tx0 = Modb.begin_write(s0)
  var tx = tx0
  for i in 1..61
    cat_s = if i <= 20
      "ops"
    else if i <= 40
      "ml"
    else
      "eng"
    end
    tag_s = if i % 2 == 0: "even" else: "odd"
    row = Json.Object({
      "id": Json.int(i),
      "category": Json.String(cat_s),
      "score": Json.int((i % 10) * 100),
      "tag": Json.String(tag_s)
    })
    assert Table.put(tx, tbl, i, row) is Ok(ntx)
    tx = ntx
  end
  assert Modb.commit(tx) is Ok(s1)

  to_view_row = fn(p)
    r = p.1
    {
      "id": r.get("id") or Json.Null,
      "category": r.get("category") or Json.Null,
      "score": r.get("score") or Json.Null,
      "tag": r.get("tag") or Json.Null
    }
  end
  vdef = ViewDef(
    name: "m17_items_v",
    description: "M17 composite + ordered test view",
    source_buckets: ["m17_items"],
    fields: [
      ViewField(name: "id", field_type: "int", description: "id"),
      ViewField(name: "category", field_type: "text", description: "category"),
      ViewField(name: "score", field_type: "int", description: "score"),
      ViewField(name: "tag", field_type: "text", description: "tag")
    ],
    narrows: None,
    load: fn(s)
      all_r = try Table.all(s, tbl).map_error(fn(e) e.to_text end)
      Ok(all_r.map(to_view_row))
    end
  )
  cat_full = with_view(catalog(), vdef)
  cat_m17 = with_view_ordered_index(
    with_view_composite_range_index(
      cat_full,
      "m17_items_v",
      "cat_score",
      ["category", "score"],
      fn(s, vals)
        ck = json_as_text(vals.get(0) or Json.Null) or ""
        sk = json_as_int(vals.get(1) or Json.Null) or 0
        rows = try Table.lookup(s, tbl, by_cat_score, (ck, sk)).map_error(fn(e) e.to_text end)
        Ok(rows.map(to_view_row))
      end,
      fn(s, eq_vals, lo_opt, hi_opt, lo_inc, hi_inc)
        ck = json_as_text(eq_vals.get(0) or Json.Null) or ""
        lo_k = case lo_opt
          Some(jv):
            case json_as_int(jv)
              Some(iv): (ck, if lo_inc: iv else: iv + 1)
              None: (ck, Table.int64_min)
            end
          None: (ck, Table.int64_min)
        end
        hi_k = case hi_opt
          Some(jv):
            case json_as_int(jv)
              Some(iv): (ck, if hi_inc: iv + 1 else: iv)
              None: (ck, Table.int64_max)
            end
          None: (ck, Table.int64_max)
        end
        rows = try Table.range_by(s, tbl, by_cat_score, Some(lo_k), Some(hi_k), 0).map_error(fn(e)
          e.to_text
        end)
        Ok(rows.map(to_view_row))
      end
    ),
    "m17_items_v",
    "id",
    fn(s, lo_opt, hi_opt, lo_inc, hi_inc, lim)
      lo_k = lo_opt.map(fn(jv)
        iv = json_as_int(jv) or Table.int64_min
        if lo_inc: iv else: iv + 1
      end)
      hi_k = hi_opt.map(fn(jv)
        iv = json_as_int(jv) or Table.int64_max
        if hi_inc: iv + 1 else: iv
      end)
      rows = try Table.scan(s, tbl, lo_k, hi_k, lim).map_error(fn(e) e.to_text end)
      Ok(rows.map(to_view_row))
    end
  )

  # 1. PlanCompositeEq + residual filter parity vs full scan
  p_ceq = ReadProgram(
    view: "m17_items_v",
    where_clause: Some(
      And(
        preds: [
          Eq(field: "tag", value: Json.String("even")),
          And(
            preds: [
              Eq(field: "category", value: Json.String("ops")),
              Eq(field: "score", value: Json.int(200))
            ]
          )
        ]
      )
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: Some(SortSpec(field: "id", desc: false)),
    limit: None
  )
  assert plan_read_program(cat_m17, p_ceq) is
    Ok(PlanCompositeEq(view: "m17_items_v", index_name: "cat_score", fields: _, values: _))
  assert explain_read_program(cat_m17, p_ceq) is Ok(ex_ceq) and
    ex_ceq.text_at("strategy") == Some("composite_eq") and
    ex_ceq.bool_at("residual_filter") == Some(true)
  assert execute_read_program(s1, cat_full, p_ceq, None, true, default_limits(), t0) is
    Ok(r_ceq_full)
  assert execute_read_program(s1, cat_m17, p_ceq, None, true, default_limits(), t0) is
    Ok(r_ceq_fast)
  assert r_ceq_fast.rows == r_ceq_full.rows and r_ceq_fast.rows_scanned == 2

  # 2. PlanCompositeRange parity
  p_crng = ReadProgram(
    view: "m17_items_v",
    where_clause: Some(
      And(
        preds: [
          Eq(field: "category", value: Json.String("ml")),
          Gte(field: "score", value: Json.int(700)),
          Lte(field: "score", value: Json.int(900))
        ]
      )
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: Some(SortSpec(field: "id", desc: false)),
    limit: None
  )
  assert plan_read_program(cat_m17, p_crng) is
    Ok(
      PlanCompositeRange(
        view: "m17_items_v",
        index_name: "cat_score",
        eq_fields: _,
        eq_values: _,
        range_field: "score",
        lo: _,
        hi: _,
        lo_inclusive: _,
        hi_inclusive: _
      )
    )
  assert execute_read_program(s1, cat_full, p_crng, None, true, default_limits(), t0) is
    Ok(r_cr_full)
  assert execute_read_program(s1, cat_m17, p_crng, None, true, default_limits(), t0) is
    Ok(r_cr_fast)
  assert r_cr_fast.rows == r_cr_full.rows and r_cr_fast.rows_scanned == 6

  # 3. PlanIndexOrdered + Limit early stop scans 3 rows instead of 60!
  p_ord = ReadProgram(
    view: "m17_items_v",
    where_clause: None,
    select: Some(["id", "category"]),
    group_by: None,
    aggregates: None,
    order_by: Some(SortSpec(field: "id", desc: false)),
    limit: Some(3)
  )
  assert plan_read_program(cat_m17, p_ord) is
    Ok(
      PlanIndexOrdered(
        view: "m17_items_v",
        field: "id",
        limit_pushdown: Some(3),
        lo: _,
        hi: _,
        lo_inclusive: _,
        hi_inclusive: _
      )
    )
  assert execute_read_program(s1, cat_full, p_ord, None, true, default_limits(), t0) is
    Ok(r_ord_full)
  assert execute_read_program(s1, cat_m17, p_ord, None, true, default_limits(), t0) is
    Ok(r_ord_fast)
  assert r_ord_fast.rows == r_ord_full.rows and r_ord_fast.rows_scanned == 3

  # 4. Paged keyset traversal matches unpaged answer rows exactly (even with ties on `score`)
  p_page = ReadProgram(
    view: "m17_items_v",
    where_clause: Some(Eq(field: "category", value: Json.String("eng"))),
    select: Some(["id", "score"]),
    group_by: None,
    aggregates: None,
    order_by: Some(SortSpec(field: "score", desc: false)),
    limit: None
  )
  assert execute_read_program(s1, cat_m17, p_page, None, true, default_limits(), t0) is
    Ok(r_unpaged)
  var collected = []
  var cur_opt = None
  var loops = 0
  while loops < 20
    loops += 1
    assert execute_read_program_paged(
      s1,
      cat_m17,
      p_page,
      cur_opt,
      7,
      None,
      true,
      default_limits(),
      t0
    ) is
      Ok(pg)
    for row in pg.result.rows
      collected = collected.append(row)
    end
    cur_opt = pg.next_cursor
    break if not pg.has_more
  end
  assert collected == r_unpaged.rows and collected.size == 20
  # Reject invalid cursor cleanly
  assert execute_read_program_paged(
    s1,
    cat_m17,
    p_page,
    Some("not-valid-base64"),
    5,
    None,
    true,
    default_limits(),
    t0
  ) is
    Error(InvalidProgram(reason: _))
end
