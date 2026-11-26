## MoDB Layer 4: Sensitivity / Taint Labels, Non-Widening Clearances, and
## Cross-Module Enforcement across Views, k-Anonymous Releases, FTS/Vec Search, and Export.
module Modb.Policy
expose clearances_bucket,
Sensitivity(..),
ExportMode(..),
ClearanceRecord(..),
ReleasePolicy(..),
SensitivityPolicy(..),
GovernedReadResult(..),
GovernedExportResult(..),
PolicyError(..),
to_text,
rank,
permits?,
max_sensitivity,
min_sensitivity,
sensitivity_to_text,
sensitivity_from_text,
policy,
with_default_clearance,
with_default_bucket_sensitivity,
with_bucket_sensitivity,
with_view_field_sensitivity,
with_scope_sensitivity,
with_release_policy,
bucket_sensitivity,
field_sensitivity,
scope_sensitivity,
view_max_sensitivity,
clearances_table,
tx_get_clearance,
get_clearance,
list_clearances,
tx_effective_clearance,
effective_clearance,
tx_set_clearance,
set_clearance,
set_clearance_locked,
scope_filter_for_clearance,
collect_program_fields,
execute_read_program_governed,
execute_read_program_governed_recorded,
execute_read_program_governed_locked,
execute_release_governed,
execute_release_governed_recorded,
execute_release_governed_locked,
search_fts_governed,
search_vec_governed,
hybrid_search_governed,
export_governed,
export_governed_locked
use Json
use Modb{Store, WriteTx, pins_bucket}
use Modb.Export
use Modb.Fts
use Modb.Grants
use Modb.Ledger{Db, LedgerError, Schema, WriteMeta}
use Modb.Table{Table, TableError}
use Modb.Vec
use Modb.Views

## Reserved internal bucket holding per-grant persisted Sensitivity clearances.
clearances_bucket = "_modb_clearances"

## Total lattice of data Sensitivity / taint levels (`Public < Internal < Confidential < Secret`).
enum Sensitivity
  Public
  Internal
  Confidential
  Secret
end

## Controls how `export_governed` handles buckets above caller clearance.
enum ExportMode
  StrictFailClosed
  RedactRestricted
end

## Persisted clearance ceiling assigned to a specific Grant ID.
struct ClearanceRecord
  grant_id: Text
  max_sensitivity: Sensitivity
  granted_by: Text
  reason: Text
  updated_at: Time
end

## Governance policy describing allowed k-anonymous declassification on a `ReleaseDef`.
struct ReleasePolicy
  input_sensitivity: Sensitivity
  output_sensitivity: Sensitivity
  min_group_size: Int
end

## Sensitivity classification policy across buckets, View fields, search scopes, and Releases.
struct SensitivityPolicy
  default_clearance: Sensitivity
  default_bucket_sensitivity: Sensitivity
  bucket_sensitivities: Map(Text, Sensitivity)
  view_field_sensitivities: Map(Text, Map(Text, Sensitivity))
  scope_sensitivities: Map(Text, Sensitivity)
  release_policies: Map(Text, ReleasePolicy)
end

## Output of `execute_read_program_governed`, including clearance and redaction telemetry.
struct GovernedReadResult
  result: Views.ReadResult
  clearance: Sensitivity
  max_sensitivity_read: Sensitivity
  redacted_fields: List(Text)
end

## Output of `export_governed`, including exported and redacted bucket lists.
struct GovernedExportResult
  snapshot: Export.PortableSnapshot
  clearance: Sensitivity
  exported_buckets: List(Text)
  redacted_buckets: List(Text)
  max_sensitivity_exported: Sensitivity
end

## Every failure returned by `Modb.Policy` operations.
enum PolicyError
  LedgerFailure(LedgerError)
  GrantFailure(Grants.GrantError)
  ViewsFailure(Views.ViewsError)
  ExportFailure(Export.ExportError)
  FtsFailure(Fts.FtsError)
  VecFailure(Vec.VecError)
  InvalidPolicy(reason: Text)
  ClearanceDenied(subject: Text, required: Sensitivity, actual: Sensitivity)
  ClearanceWideningDenied(
    grant_id: Text,
    parent_id: Text,
    requested: Sensitivity,
    parent_clearance: Sensitivity
  )
  DeclassificationDenied(
    release: Text,
    input_sensitivity: Sensitivity,
    output_sensitivity: Sensitivity,
    min_group_size: Int
  )
  ExportBlocked(bucket: Text, required: Sensitivity, actual: Sensitivity)
end

## Integer rank (`0..3`) ordering the Sensitivity lattice.
fn rank(s: Sensitivity) : Int
  case s
    Public: 0
    Internal: 1
    Confidential: 2
    Secret: 3
  end
end

## Returns `true` iff `clearance` dominates `data` (`rank(data) <= rank(clearance)`).
fn permits?(clearance: Sensitivity, data: Sensitivity) : Bool
  rank(data) <= rank(clearance)
end

## Returns the higher of two `Sensitivity` levels.
fn max_sensitivity(a: Sensitivity, b: Sensitivity) : Sensitivity
  if rank(a) >= rank(b): a else: b
end

## Returns the lower of two `Sensitivity` levels.
fn min_sensitivity(a: Sensitivity, b: Sensitivity) : Sensitivity
  if rank(a) <= rank(b): a else: b
end

## Formats a `Sensitivity` level as lowercase canonical text.
fn sensitivity_to_text(s: Sensitivity) : Text
  case s
    Public: "public"
    Internal: "internal"
    Confidential: "confidential"
    Secret: "secret"
  end
end

## Parses a `Sensitivity` level from text (case-insensitive).
fn sensitivity_from_text(raw: Text) : Option(Sensitivity)
  norm = Text.from_chars(raw.trim.chars.map(fn(c) c.ascii_lowercase end))
  if norm == "public"
    Some(Public)
  else if norm == "internal"
    Some(Internal)
  else if norm == "confidential"
    Some(Confidential)
  else if norm == "secret"
    Some(Secret)
  else
    None
  end
end

## Formats a `PolicyError` as a human-readable diagnostic.
fn to_text(err: PolicyError) : Text
  case err
    LedgerFailure(e): e.to_text
    GrantFailure(e): e.to_text
    ViewsFailure(e): Views.to_text(e)
    ExportFailure(e): Export.to_text(e)
    FtsFailure(e): Fts.to_text(e)
    VecFailure(e): Vec.to_text(e)
    InvalidPolicy(reason: r): "invalid sensitivity policy: #{r}"
    ClearanceDenied(subject: s, required: req, actual: act): "clearance denied for #{s}: requires '#{sensitivity_to_text(
      req
    )}', caller has '#{sensitivity_to_text(act)}'"
    ClearanceWideningDenied(grant_id: g, parent_id: p, requested: req, parent_clearance: pc): "cannot assign clearance '#{sensitivity_to_text(
      req
    )}' to child grant '#{g}': exceeds parent '#{p}' clearance '#{sensitivity_to_text(pc)}'"
    DeclassificationDenied(
      release: r,
      input_sensitivity: inp,
      output_sensitivity: out,
      min_group_size: k
    ): "declassification denied on release '#{r}' (#{sensitivity_to_text(inp)} -> #{sensitivity_to_text(
      out
    )}): requires k-anonymity min_group_size >= #{k}"
    ExportBlocked(bucket: b, required: req, actual: act): "export blocked on bucket '#{b}': requires '#{sensitivity_to_text(
      req
    )}' clearance, caller has '#{sensitivity_to_text(act)}'"
  end
end

## Creates a default `SensitivityPolicy` (`default_clearance: Public`, `default_bucket_sensitivity: Public`).
fn policy() : SensitivityPolicy
  SensitivityPolicy(
    default_clearance: Public,
    default_bucket_sensitivity: Public,
    bucket_sensitivities: {},
    view_field_sensitivities: {},
    scope_sensitivities: {},
    release_policies: {}
  )
end

## Configures the fallback clearance when a grant has no explicit clearance record.
fn with_default_clearance(pol: SensitivityPolicy, s: Sensitivity) : SensitivityPolicy
  var next = pol
  next.default_clearance = s
  next
end

## Configures the fallback sensitivity for unmapped user buckets.
fn with_default_bucket_sensitivity(pol: SensitivityPolicy, s: Sensitivity) : SensitivityPolicy
  var next = pol
  next.default_bucket_sensitivity = s
  next
end

## Labels a storage bucket with sensitivity `s`.
fn with_bucket_sensitivity(pol: SensitivityPolicy, bucket: Text, s: Sensitivity) : SensitivityPolicy
  var next = pol
  next.bucket_sensitivities = next.bucket_sensitivities.set(bucket, s)
  next
end

## Labels `(view, field)` with sensitivity `s`.
fn with_view_field_sensitivity(
  pol: SensitivityPolicy,
  view: Text,
  field: Text,
  s: Sensitivity
) : SensitivityPolicy
  var next = pol
  cur = next.view_field_sensitivities.get(view) or {}
  next.view_field_sensitivities = next.view_field_sensitivities.set(view, cur.set(field, s))
  next
end

## Labels a search scope with sensitivity `s` for fail-closed FTS/Vec filtering.
fn with_scope_sensitivity(pol: SensitivityPolicy, scope: Text, s: Sensitivity) : SensitivityPolicy
  var next = pol
  next.scope_sensitivities = next.scope_sensitivities.set(scope, s)
  next
end

## Registers a k-anonymous declassification policy on a `ReleaseDef`.
fn with_release_policy(
  pol: SensitivityPolicy,
  release_name: Text,
  rp: ReleasePolicy
) : SensitivityPolicy
  var next = pol
  next.release_policies = next.release_policies.set(release_name, rp)
  next
end

## Looks up a bucket's sensitivity (`_modb_*` buckets default to at least `Internal`).
fn bucket_sensitivity(pol: SensitivityPolicy, bucket: Text) : Sensitivity
  case pol.bucket_sensitivities.get(bucket)
    Some(s): s
    None:
      if bucket.starts_with?("_modb_")
        max_sensitivity(Internal, pol.default_bucket_sensitivity)
      else
        pol.default_bucket_sensitivity
      end
  end
end

## Looks up `(view, field)` sensitivity (defaults to `Public`).
fn field_sensitivity(pol: SensitivityPolicy, view: Text, field: Text) : Sensitivity
  case pol.view_field_sensitivities.get(view)
    Some(fm): fm.get(field) or Public
    None: Public
  end
end

## Looks up a search scope's sensitivity (defaults to `Public`).
fn scope_sensitivity(pol: SensitivityPolicy, scope: Text) : Sensitivity
  pol.scope_sensitivities.get(scope) or Public
end

## Computes the maximum sensitivity across all declared fields of `vdef`.
fn view_max_sensitivity(pol: SensitivityPolicy, vdef: Views.ViewDef) : Sensitivity
  var m = Public
  for f in vdef.fields
    m = max_sensitivity(m, field_sensitivity(pol, vdef.name, f.name))
  end
  m
end

## Typed table storing grant clearance caps in `_modb_clearances`.
fn clearances_table() : Table(Text, ClearanceRecord)
  Table.text_key[ClearanceRecord](clearances_bucket)
end

fn wrap_table(res: Result(T, TableError)) : Result(T, PolicyError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

## Reads a persisted clearance record inside `tx`.
fn tx_get_clearance(tx: WriteTx, grant_id: Text) : Result(Option(ClearanceRecord), PolicyError)
  wrap_table(Table.tx_get(tx, clearances_table(), grant_id))
end

## Reads a persisted clearance record from committed `store`.
fn get_clearance(store: Store, grant_id: Text) : Result(Option(ClearanceRecord), PolicyError)
  wrap_table(Table.get(store, clearances_table(), grant_id))
end

## Lists all persisted clearance records in sorted Grant ID order.
fn list_clearances(store: Store) : Result(List(ClearanceRecord), PolicyError)
  rows = try wrap_table(Table.all(store, clearances_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Computes effective clearance inside `tx` by walking the entire `Grants` ancestor chain
## and taking the minimum explicit clearance (`pol.default_clearance` if none is recorded).
## Admin callers without a `grant_id` receive `Secret`.
fn tx_effective_clearance(
  tx: WriteTx,
  pol: SensitivityPolicy,
  grant_id_opt: Option(Text),
  is_admin: Bool
) : Result(Sensitivity, PolicyError)
  case grant_id_opt
    None:
      if is_admin
        Ok(Secret)
      else
        Ok(pol.default_clearance)
      end
    Some(gid):
      var cur_opt = Some(gid)
      var visited = Set.empty
      var any_set? = false
      var eff = Secret
      while cur_opt is Some(cur_id)
        if visited.has?(cur_id)
          return Error(
            GrantFailure(
              Grants.InvalidGrant(reason: "cycle in grant hierarchy at '#{cur_id}'")
            )
          )
        end
        visited = visited.add(cur_id)
        g_opt = try Grants.tx_get(tx, cur_id).map_error(fn(e) GrantFailure(e) end)
        g = try g_opt.or_fail(GrantFailure(Grants.GrantNotFound(id: cur_id)))
        case try tx_get_clearance(tx, cur_id)
          Some(rec):
            eff = if any_set?: min_sensitivity(eff, rec.max_sensitivity) else: rec.max_sensitivity
            any_set? = true
          None: Unit
        end
        cur_opt = g.parent_id
      end
      if any_set?
        Ok(eff)
      else
        Ok(pol.default_clearance)
      end
  end
end

## Committed-store wrapper around `tx_effective_clearance`.
fn effective_clearance(
  store: Store,
  pol: SensitivityPolicy,
  grant_id_opt: Option(Text),
  is_admin: Bool
) : Result(Sensitivity, PolicyError)
  tx_effective_clearance(Modb.begin_write(store), pol, grant_id_opt, is_admin)
end

## Sets or narrows a Grant's Sensitivity clearance inside `tx`, strictly rejecting any attempt to
## give a delegated child higher clearance than its parent Grant (`ClearanceWideningDenied`).
fn tx_set_clearance(
  tx: WriteTx,
  pol: SensitivityPolicy,
  grant_id: Text,
  max_sens: Sensitivity,
  granted_by: Text,
  reason: Text,
  now: Time
) : Result((WriteTx, ClearanceRecord), PolicyError)
  if grant_id.trim.empty?
    return Error(InvalidPolicy(reason: "grant_id cannot be empty"))
  end
  if granted_by.trim.empty?
    return Error(InvalidPolicy(reason: "granted_by cannot be empty"))
  end
  g_opt = try Grants.tx_get(tx, grant_id).map_error(fn(e) GrantFailure(e) end)
  g = try g_opt.or_fail(GrantFailure(Grants.GrantNotFound(id: grant_id)))
  case g.parent_id
    Some(pid):
      parent_eff = try tx_effective_clearance(tx, pol, Some(pid), false)
      if rank(max_sens) > rank(parent_eff)
        return Error(
          ClearanceWideningDenied(
            grant_id: grant_id,
            parent_id: pid,
            requested: max_sens,
            parent_clearance: parent_eff
          )
        )
      end
    None: Unit
  end
  rec = ClearanceRecord(
    grant_id: grant_id,
    max_sensitivity: max_sens,
    granted_by: granted_by,
    reason: reason,
    updated_at: now
  )
  t1 = try wrap_table(Table.put(tx, clearances_table(), grant_id, rec))
  Ok((t1, rec))
end

## Sets a Grant's Sensitivity clearance atomically and appends an audited ledger entry.
fn set_clearance(
  db: Db,
  pol: SensitivityPolicy,
  meta: WriteMeta,
  grant_id: Text,
  max_sens: Sensitivity,
  now: Time
) : Result((Db, ClearanceRecord), PolicyError)
  payload = Json.Object({
    "grant_id": Json.String(grant_id),
    "max_sensitivity": Json.String(sensitivity_to_text(max_sens))
  })
  Ledger.transact(
    db,
    meta,
    "set clearance '#{sensitivity_to_text(max_sens)}' on grant '#{grant_id}'",
    payload,
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_set_clearance(tx, pol, grant_id, max_sens, meta.principal, meta.reason, now) end
  )
end

## Lock-coordinated multi-worker wrapper for `set_clearance`.
fn set_clearance_locked(
  files: Files,
  path: Text,
  sc: Schema,
  pol: SensitivityPolicy,
  meta: WriteMeta,
  grant_id: Text,
  max_sens: Sensitivity,
  now: Time
) : Result(ClearanceRecord, PolicyError)
  Ledger.locked(
    files,
    path,
    sc,
    meta.at,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, rec) = try set_clearance(db, pol, meta, grant_id, max_sens, now)
      Ok(rec)
    end
  )
end

## Returns a fail-closed `(doc_id, scope) -> Bool` predicate for `Fts.search_filtered`,
## `Vec.search_filtered`, and `Vec.hybrid_search_filtered`.
fn scope_filter_for_clearance(pol: SensitivityPolicy, clearance: Sensitivity) : fn(
  Text,
  Text
) : Bool
  fn(_doc_id, scope) permits?(clearance, scope_sensitivity(pol, scope)) end
end

fn collect_pred_fields(pred: Views.Pred, seen: Set(Text), acc: List(Text)) : (
  Set(Text),
  List(Text)
)
  case pred
    Views.Eq(field: f, value: _) | Views.Neq(field: f, value: _) | Views.Gt(field: f, value: _) | Views
      .Gte(field: f, value: _) | Views.Lt(field: f, value: _) | Views.Lte(field: f, value: _) | Views
      .Contains(field: f, substr: _) | Views.StartsWith(field: f, prefix: _) | Views.InList(
        field: f,
        values: _
      ) | Views.IsNull(field: f) | Views.NotNull(field: f):
      if seen.has?(f): (seen, acc) else: (seen.add(f), acc.append(f))
    Views.And(preds: ps) | Views.Or(preds: ps):
      var s = seen
      var out = acc
      for p in ps
        (s2, o2) = collect_pred_fields(p, s, out)
        s = s2
        out = o2
      end
      (s, out)
    Views.Not(pred: p): collect_pred_fields(p, seen, acc)
  end
end

fn push_unique_field(seen: Set(Text), acc: List(Text), field: Text) : (Set(Text), List(Text))
  if seen.has?(field): (seen, acc) else: (seen.add(field), acc.append(field))
end

## Extracts every View source field touched by `prog` (`where_clause`, `select`, `group_by`,
## `aggregates`, and non-alias `order_by` fields).
fn collect_program_fields(prog: Views.ReadProgram) : List(Text)
  var seen = Set.empty
  var out = []
  var agg_aliases = Set.empty
  is_agg? = (prog.group_by is Some(_)) or (prog.aggregates is Some(_))

  case prog.where_clause
    Some(p):
      (s2, o2) = collect_pred_fields(p, seen, out)
      seen = s2
      out = o2
    None: Unit
  end
  case prog.group_by
    Some(gf):
      (s2, o2) = push_unique_field(seen, out, gf)
      seen = s2
      out = o2
    None: Unit
  end
  for a in (prog.aggregates or [])
    agg_aliases = agg_aliases.add(a.alias)
    case a.op
      Views.Count: Unit
      Views.Sum(field: f) | Views.Avg(field: f) | Views.Min(field: f) | Views.Max(field: f):
        (s2, o2) = push_unique_field(seen, out, f)
        seen = s2
        out = o2
    end
  end
  case prog.select
    Some(cols):
      for c in cols
        if not is_agg? or not agg_aliases.has?(c)
          (s2, o2) = push_unique_field(seen, out, c)
          seen = s2
          out = o2
        end
      end
    None: Unit
  end
  case prog.order_by
    Some(srt):
      if not is_agg? or not agg_aliases.has?(srt.field)
        (_s2, o2) = push_unique_field(seen, out, srt.field)
        out = o2
      end
    None: Unit
  end
  out
end

fn prepare_governed_program(
  store: Store,
  cat: Views.ViewCatalog,
  pol: SensitivityPolicy,
  prog: Views.ReadProgram,
  grant_id_opt: Option(Text),
  is_admin: Bool
) : Result((Views.ReadProgram, Sensitivity, Sensitivity, List(Text)), PolicyError)
  vdef = try cat.views.get(prog.view).or_fail(ViewsFailure(Views.UnknownView(name: prog.view)))
  try Views.validate_program(vdef, prog).map_error(fn(e) ViewsFailure(e) end)
  eff = try effective_clearance(store, pol, grant_id_opt, is_admin)
  any_visible? = vdef.fields.any?(fn(vf) permits?(eff, field_sensitivity(pol, vdef.name, vf.name)) end)
  if not any_visible?
    req = view_max_sensitivity(pol, vdef)
    return Error(ClearanceDenied(subject: "view:#{vdef.name}", required: req, actual: eff))
  end

  touched = collect_program_fields(prog)
  var max_read = Public
  for f in touched
    fs = field_sensitivity(pol, vdef.name, f)
    if not permits?(eff, fs)
      return Error(
        ClearanceDenied(subject: "view:#{vdef.name}.#{f}", required: fs, actual: eff)
      )
    end
    max_read = max_sensitivity(max_read, fs)
  end

  is_agg? = (prog.group_by is Some(_)) or (prog.aggregates is Some(_))
  var eff_prog = prog
  var redacted = []
  if not is_agg? and prog.select is None
    var visible = []
    for vf in vdef.fields
      fs = field_sensitivity(pol, vdef.name, vf.name)
      if permits?(eff, fs)
        visible = visible.append(vf.name)
        max_read = max_sensitivity(max_read, fs)
      else
        redacted = redacted.append(vf.name)
      end
    end
    if visible.empty?
      req = view_max_sensitivity(pol, vdef)
      return Error(ClearanceDenied(subject: "view:#{vdef.name}", required: req, actual: eff))
    end
    if not redacted.empty?
      eff_prog.select = Some(visible)
    end
  end
  Ok((eff_prog, eff, max_read, redacted))
end

## Executes a sandboxed `ReadProgram` on `store` under `SensitivityPolicy`:
## enforces static clearance BEFORE scanning (blocking filter/aggregate/sort oracle attacks),
## auto-redacts above-clearance wildcard projections, and fails closed if nothing is visible.
fn execute_read_program_governed(
  store: Store,
  cat: Views.ViewCatalog,
  pol: SensitivityPolicy,
  prog: Views.ReadProgram,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: Views.ReadLimits,
  now: Time
) : Result(GovernedReadResult, PolicyError)
  (eff_prog, eff, max_read, redacted) = try prepare_governed_program(
    store,
    cat,
    pol,
    prog,
    grant_id_opt,
    is_admin
  )
  res = try Views.execute_read_program(
    store,
    cat,
    eff_prog,
    grant_id_opt,
    is_admin,
    limits,
    now
  ).map_error(fn(e) ViewsFailure(e) end)
  Ok(
    GovernedReadResult(
      result: res,
      clearance: eff,
      max_sensitivity_read: max_read,
      redacted_fields: redacted
    )
  )
end

## Recorded variant of `execute_read_program_governed` writing provenance into `_modb_read_log`.
fn execute_read_program_governed_recorded(
  db: Db,
  cat: Views.ViewCatalog,
  pol: SensitivityPolicy,
  prog: Views.ReadProgram,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: Views.ReadLimits,
  now: Time
) : Result((Db, GovernedReadResult, Views.ReadLogEntry), PolicyError)
  (eff_prog, eff, max_read, redacted) = try prepare_governed_program(
    Ledger.store(db),
    cat,
    pol,
    prog,
    grant_id_opt,
    is_admin
  )
  (next_db, res, log_entry) = try Views.execute_read_program_recorded(
    db,
    cat,
    eff_prog,
    principal,
    grant_id_opt,
    is_admin,
    limits,
    now
  ).map_error(fn(e) ViewsFailure(e) end)
  gov = GovernedReadResult(
    result: res,
    clearance: eff,
    max_sensitivity_read: max_read,
    redacted_fields: redacted
  )
  Ok((next_db, gov, log_entry))
end

## Lock-coordinated variant of `execute_read_program_governed_recorded`.
fn execute_read_program_governed_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Views.ViewCatalog,
  pol: SensitivityPolicy,
  prog: Views.ReadProgram,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  limits: Views.ReadLimits,
  now: Time
) : Result(GovernedReadResult, PolicyError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, gov, _entry) = try execute_read_program_governed_recorded(
        db,
        cat,
        pol,
        prog,
        principal,
        grant_id_opt,
        is_admin,
        limits,
        now
      )
      Ok(gov)
    end
  )
end

fn check_release_policy(
  store: Store,
  cat: Views.ViewCatalog,
  pol: SensitivityPolicy,
  release_name: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool
) : Result(Unit, PolicyError)
  rdef = try cat.releases.get(release_name).or_fail(
    ViewsFailure(Views.UnknownRelease(name: release_name))
  )
  eff = try effective_clearance(store, pol, grant_id_opt, is_admin)
  case pol.release_policies.get(release_name)
    Some(rp):
      declassifies? = rank(rp.output_sensitivity) < rank(rp.input_sensitivity)
      if declassifies?
        req_k = if rp.min_group_size < 2: 2 else: rp.min_group_size
        if rdef.min_group_size < req_k
          return Error(
            DeclassificationDenied(
              release: release_name,
              input_sensitivity: rp.input_sensitivity,
              output_sensitivity: rp.output_sensitivity,
              min_group_size: req_k
            )
          )
        end
      end
      if not permits?(eff, rp.output_sensitivity)
        return Error(
          ClearanceDenied(
            subject: "release:#{release_name}",
            required: rp.output_sensitivity,
            actual: eff
          )
        )
      end
    None:
      var max_b = Public
      for b in rdef.source_buckets
        max_b = max_sensitivity(max_b, bucket_sensitivity(pol, b))
      end
      if not permits?(eff, max_b)
        return Error(
          ClearanceDenied(subject: "release:#{release_name}", required: max_b, actual: eff)
        )
      end
  end
  Ok(Unit)
end

## Executes an approved k-anonymous `ReleaseDef` under `SensitivityPolicy`:
## allows declassification ONLY when `rdef.min_group_size >= rp.min_group_size >= 2`
## and caller clearance covers `output_sensitivity`.
fn execute_release_governed(
  store: Store,
  cat: Views.ViewCatalog,
  pol: SensitivityPolicy,
  release_name: Text,
  args: Json,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result(Views.ReleaseResult, PolicyError)
  try check_release_policy(store, cat, pol, release_name, grant_id_opt, is_admin)
  Views.execute_release(store, cat, release_name, args, grant_id_opt, is_admin, now).map_error(
    fn(e) ViewsFailure(e) end
  )
end

## Recorded variant of `execute_release_governed` writing provenance into `_modb_read_log`.
fn execute_release_governed_recorded(
  db: Db,
  cat: Views.ViewCatalog,
  pol: SensitivityPolicy,
  release_name: Text,
  args: Json,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result((Db, Views.ReleaseResult, Views.ReadLogEntry), PolicyError)
  try check_release_policy(Ledger.store(db), cat, pol, release_name, grant_id_opt, is_admin)
  Views.execute_release_recorded(
    db,
    cat,
    release_name,
    args,
    principal,
    grant_id_opt,
    is_admin,
    now
  ).map_error(fn(e) ViewsFailure(e) end)
end

## Lock-coordinated variant of `execute_release_governed_recorded`.
fn execute_release_governed_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Views.ViewCatalog,
  pol: SensitivityPolicy,
  release_name: Text,
  args: Json,
  principal: Text,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result(Views.ReleaseResult, PolicyError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, res, _entry) = try execute_release_governed_recorded(
        db,
        cat,
        pol,
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

## Executes fail-closed `Fts.search_filtered` enforcing caller clearance per document scope.
fn search_fts_governed(
  store: Store,
  pol: SensitivityPolicy,
  idx: Fts.FtsIndex,
  query: Text,
  opts: Fts.SearchOptions,
  grant_id_opt: Option(Text),
  is_admin: Bool
) : Result(List(Fts.SearchHit), PolicyError)
  eff = try effective_clearance(store, pol, grant_id_opt, is_admin)
  Fts.search_filtered(store, idx, query, opts, scope_filter_for_clearance(pol, eff)).map_error(
    fn(e) FtsFailure(e) end
  )
end

## Executes fail-closed `Vec.search_filtered` enforcing caller clearance per vector scope.
fn search_vec_governed(
  store: Store,
  pol: SensitivityPolicy,
  idx: Vec.VecIndex,
  query_vec: List(Float),
  opts: Vec.VecSearchOptions,
  grant_id_opt: Option(Text),
  is_admin: Bool
) : Result(List(Vec.VecHit), PolicyError)
  eff = try effective_clearance(store, pol, grant_id_opt, is_admin)
  Vec.search_filtered(store, idx, query_vec, opts, scope_filter_for_clearance(pol, eff)).map_error(
    fn(e) VecFailure(e) end
  )
end

## Executes fail-closed `Vec.hybrid_search_filtered` enforcing caller clearance on both channels.
fn hybrid_search_governed(
  store: Store,
  pol: SensitivityPolicy,
  fts_idx: Fts.FtsIndex,
  vec_idx: Vec.VecIndex,
  query_text: Text,
  query_vec: Option(List(Float)),
  opts: Vec.HybridOptions,
  grant_id_opt: Option(Text),
  is_admin: Bool
) : Result(List(Vec.HybridHit), PolicyError)
  eff = try effective_clearance(store, pol, grant_id_opt, is_admin)
  Vec.hybrid_search_filtered(
    store,
    fts_idx,
    vec_idx,
    query_text,
    query_vec,
    opts,
    scope_filter_for_clearance(pol, eff)
  ).map_error(fn(e) VecFailure(e) end)
end

## Exports committed `store` into a SHA-256 `PortableSnapshot` governed by caller clearance:
## `StrictFailClosed` blocks if any included bucket exceeds clearance;
## `RedactRestricted` omits restricted buckets before reading their B+Tree pages.
fn export_governed(
  store: Store,
  pol: SensitivityPolicy,
  mode: ExportMode,
  include_internal: Bool,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result(GovernedExportResult, PolicyError)
  eff = try effective_clearance(store, pol, grant_id_opt, is_admin)
  if mode is StrictFailClosed
    bnames = try Modb.buckets(store).map_error(fn(e) ExportFailure(Export.StorageFailure(e)) end)
    for b in bnames
      skip_internal? = b == pins_bucket or (not include_internal and b.starts_with?("_modb_"))
      if not skip_internal?
        bs = bucket_sensitivity(pol, b)
        if not permits?(eff, bs)
          return Error(ExportBlocked(bucket: b, required: bs, actual: eff))
        end
      end
    end
  end
  (snap, skipped) = try Export.export_filtered_store(
    store,
    include_internal,
    fn(b) permits?(eff, bucket_sensitivity(pol, b)) end,
    now
  ).map_error(fn(e) ExportFailure(e) end)
  var exported = []
  var max_exp = Public
  for b in snap.buckets
    exported = exported.append(b.name)
    max_exp = max_sensitivity(max_exp, bucket_sensitivity(pol, b.name))
  end
  Ok(
    GovernedExportResult(
      snapshot: snap,
      clearance: eff,
      exported_buckets: exported,
      redacted_buckets: skipped,
      max_sensitivity_exported: max_exp
    )
  )
end

## Lock-coordinated read-only variant of `export_governed`.
fn export_governed_locked(
  rf: ReadFiles,
  path: Text,
  sc: Schema,
  pol: SensitivityPolicy,
  mode: ExportMode,
  include_internal: Bool,
  grant_id_opt: Option(Text),
  is_admin: Bool,
  now: Time
) : Result(GovernedExportResult, PolicyError)
  Ledger.read_locked(
    rf,
    path,
    sc,
    fn(e) LedgerFailure(e) end,
    fn(db)
      export_governed(Ledger.store(db), pol, mode, include_internal, grant_id_opt, is_admin, now)
    end
  )
end

struct ItemRec
  id: Int
  label: Text
  secret_cost: Int
end

test "Modb.Policy: lattice, cascading clearance attenuation, views, declassification, search & export"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T16:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T18:00:00Z") or stop "t1"
  sc = Ledger.schema(0).with_require_reason(false)
  pub_tbl = Table.int_key[ItemRec]("public_items")
  sec_tbl = Table.int_key[ItemRec]("vault_items")
  f_idx = Fts.index("gov")
  v_idx = Vec.index("gov", 4)
  assert Ledger.open(files, "pol.modb", sc, t0) is Ok(db0)
  assert Ledger.write(
    db0,
    Ledger.WriteMeta(principal: "admin", action: "seed", reason: "init", at: t0),
    "seed",
    Json.Null,
    fn(tx)
      t_a = try Table.put(tx, pub_tbl, 1, ItemRec(id: 1, label: "alpha", secret_cost: 100))
      t_b = try Table.put(t_a, pub_tbl, 2, ItemRec(id: 2, label: "beta", secret_cost: 200))
      t_c = try Table.put(t_b, pub_tbl, 3, ItemRec(id: 3, label: "gamma", secret_cost: 300))
      t_d = try Table.put(t_c, sec_tbl, 9, ItemRec(id: 9, label: "topsecret", secret_cost: 999))
      t_e = try Fts.tx_index_document(
        t_d,
        f_idx,
        Fts.DocumentInput(
          doc_id: "d1",
          scope: "open",
          fields: [Fts.FieldInput(name: "body", text: "deploy guide", weight: 2)]
        )
      ).map_error(fn(e) Table.DecodeKey(reason: Fts.to_text(e)) end)
      t_f = try Fts.tx_index_document(
        t_e,
        f_idx,
        Fts.DocumentInput(
          doc_id: "d2",
          scope: "restricted",
          fields: [Fts.FieldInput(name: "body", text: "deploy secret key", weight: 2)]
        )
      ).map_error(fn(e) Table.DecodeKey(reason: Fts.to_text(e)) end)
      t_g = try Vec.tx_put_vector(
        t_f,
        v_idx,
        Vec.VectorInput(doc_id: "d1", scope: "open", values: [1.0, 0.0, 0.0, 0.0])
      ).map_error(fn(e) Table.DecodeKey(reason: Vec.to_text(e)) end)
      Vec.tx_put_vector(
        t_g,
        v_idx,
        Vec.VectorInput(doc_id: "d2", scope: "restricted", values: [1.0, 0.0, 0.0, 0.0])
      ).map_error(fn(e) Table.DecodeKey(reason: Vec.to_text(e)) end)
    end
  ) is
    Ok(db1)

  vcat = Views.catalog().with_view(
    Views.ViewDef(
      name: "items_view",
      description: "Items with secret cost",
      source_buckets: ["public_items"],
      fields: [
        Views.ViewField(name: "id", field_type: "int", description: "id"),
        Views.ViewField(name: "label", field_type: "text", description: "label"),
        Views.ViewField(name: "secret_cost", field_type: "int", description: "cost")
      ],
      narrows: None,
      load: fn(store)
        rows = try Table.all(store, pub_tbl).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            it = p.1
            {
              "id": Json.int(it.id),
              "label": Json.String(it.label),
              "secret_cost": Json.int(it.secret_cost)
            }
          end)
        )
      end
    )
  ).with_release(
    Views.ReleaseDef(
      name: "cost_summary",
      description: "Aggregate cost",
      source_buckets: ["public_items"],
      min_group_size: 3,
      args_description: "{}",
      run: fn(store, _args)
        rows = try Table.all(store, pub_tbl).map_error(fn(e) e.to_text end)
        var s = 0
        for (_k, r) in rows
          s += r.secret_cost
        end
        Ok((rows.size, Json.Object({"count": Json.int(rows.size), "total": Json.int(s)})))
      end
    )
  )

  pol = policy().with_view_field_sensitivity("items_view", "secret_cost", Confidential)
    .with_bucket_sensitivity("public_items", Internal).with_bucket_sensitivity("vault_items", Secret)
    .with_scope_sensitivity("restricted", Confidential).with_release_policy(
      "cost_summary",
      ReleasePolicy(input_sensitivity: Confidential, output_sensitivity: Public, min_group_size: 3)
    )

  m = Ledger.WriteMeta(principal: "admin", action: "setup", reason: "grants", at: t0)
  assert Grants.issue_root_scoped(
    db1,
    m,
    Grants.GrantSpec(
      id: "g-lead",
      principal: "agent:lead",
      allowed_actions: ["noop"],
      max_calls: 20,
      expires_at: t1
    ),
    Some(["items_view"]),
    Some(["cost_summary"])
  ) is
    Ok((db2, _))
  assert Grants.delegate_scoped(
    db2,
    m,
    "g-lead",
    Grants.GrantSpec(
      id: "g-sub",
      principal: "agent:sub",
      allowed_actions: ["noop"],
      max_calls: 10,
      expires_at: t1
    ),
    Some(["items_view"]),
    Some(["cost_summary"]),
    {}
  ) is
    Ok((db3, _))

  ## Parent clearance set to Internal -> widening child to Confidential MUST fail!
  assert set_clearance(db3, pol, m, "g-lead", Internal, t0) is Ok((db4, _))
  assert set_clearance(db4, pol, m, "g-sub", Confidential, t0) is
    Error(
      ClearanceWideningDenied(
        grant_id: "g-sub",
        parent_id: "g-lead",
        requested: Confidential,
        parent_clearance: Internal
      )
    )

  ## Wildcard ReadProgram on items_view auto-redacts `secret_cost`; explicit filter oracle is rejected BEFORE scanning!
  wildcard_p = Views.ReadProgram(
    view: "items_view",
    where_clause: None,
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert execute_read_program_governed(
    Ledger.store(db4),
    vcat,
    pol,
    wildcard_p,
    Some("g-sub"),
    false,
    Views.default_limits(),
    t0
  ) is
    Ok(gov_r)
  assert gov_r.clearance is Internal and gov_r.redacted_fields == ["secret_cost"]

  oracle_p = Views.ReadProgram(
    view: "items_view",
    where_clause: Some(Views.Gt(field: "secret_cost", value: Json.int(150))),
    select: Some(["id"]),
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert execute_read_program_governed(
    Ledger.store(db4),
    vcat,
    pol,
    oracle_p,
    Some("g-sub"),
    false,
    Views.default_limits(),
    t0
  ) is
    Error(
      ClearanceDenied(subject: "view:items_view.secret_cost", required: Confidential, actual: Internal)
    )

  ## Declassified k-anonymous release succeeds for Internal caller!
  assert execute_release_governed(
    Ledger.store(db4),
    vcat,
    pol,
    "cost_summary",
    Json.Object({}),
    Some("g-sub"),
    false,
    t0
  ) is
    Ok(rel_r)
  assert rel_r.cohort_size == 3

  ## Search hides "restricted" scope completely
  assert search_fts_governed(
    Ledger.store(db4),
    pol,
    f_idx,
    "deploy",
    Fts.default_search_options(10),
    Some("g-sub"),
    false
  ) is
    Ok(fhits)
  assert fhits.size == 1 and (fhits.first or stop "h").doc_id == "d1"

  ## Export: StrictFailClosed blocks on Secret bucket; RedactRestricted omits vault_items and passes verify_snapshot!
  assert export_governed(
    Ledger.store(db4),
    pol,
    StrictFailClosed,
    false,
    Some("g-sub"),
    false,
    t0
  ) is
    Error(ExportBlocked(bucket: "vault_items", required: Secret, actual: Internal))
  assert export_governed(
    Ledger.store(db4),
    pol,
    RedactRestricted,
    false,
    Some("g-sub"),
    false,
    t0
  ) is
    Ok(exp_r)
  assert exp_r.redacted_buckets == ["vault_items"]
  assert Export.verify_snapshot(exp_r.snapshot) is Ok(_)
end
