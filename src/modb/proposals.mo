## MoDB Layer 4: Human-Reviewed Agent Proposals with Machine-Checked Capability Diffs (`design.md` §6).
## Agents propose declarative Views, Release policies, Clearances, or Invariants; MoDB computes the
## exact CapabilityDiff and applies approved changes atomically alongside `_modb_audit`.
module Modb.Proposals
expose proposals_bucket,
proposals_by_status_bucket,
dynamic_views_bucket,
dynamic_releases_bucket,
dynamic_invariants_bucket,
DynamicViewSpec(..),
DynamicReleaseSpec(..),
InvariantRule(..),
DynamicInvariantSpec(..),
ProposalKind(..),
ProposalStatus(..),
CapabilityDiff(..),
GovernanceProposal(..),
ProposalError(..),
to_text,
compute_capability_diff,
get_proposal,
list_proposals,
list_dynamic_views,
list_dynamic_releases,
list_dynamic_invariants,
submit_proposal,
approve_proposal,
reject_proposal,
withdraw_proposal,
submit_proposal_locked,
approve_proposal_locked,
reject_proposal_locked,
withdraw_proposal_locked,
materialize_catalog,
materialize_policy,
eval_invariant_rule,
apply_dynamic_invariants
use Json
use Modb{Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Grants
use Modb.Ledger{Db, LedgerError, Schema, WriteMeta}
use Modb.Policy
use Modb.Table{Index, Table, TableError}
use Modb.Views

## Reserved internal buckets for governance proposals and approved dynamic declarations.
proposals_bucket = "_modb_gov_proposals"
proposals_by_status_bucket = "_modb_gov_proposals_by_status"
dynamic_views_bucket = "_modb_dynamic_views"
dynamic_releases_bucket = "_modb_dynamic_releases"
dynamic_invariants_bucket = "_modb_dynamic_invariants"

## Declarative proposal creating a new narrowed View over an existing base View.
struct DynamicViewSpec
  name: Text
  description: Text
  base_view: Text
  fields: List(Text)
  field_sensitivities: Map(Text, Policy.Sensitivity)
end

## Declarative proposal setting/updating a k-anonymous Release declassification policy.
struct DynamicReleaseSpec
  release_name: Text
  description: Text
  input_sensitivity: Policy.Sensitivity
  output_sensitivity: Policy.Sensitivity
  min_group_size: Int
end

## Declarative row-level invariant rule checkable at commit time without running arbitrary code.
enum InvariantRule
  FieldNonEmpty(field: Text)
  IntRange(field: Text, min: Option(Int), max: Option(Int))
  AllowedValues(field: Text, values: List(Text))
end

## Declarative commit-time invariant targeting JSON-encoded objects in `bucket`.
struct DynamicInvariantSpec
  name: Text
  description: Text
  bucket: Text
  rule: InvariantRule
end

## Supported agent proposal kinds.
enum ProposalKind
  ProposeView(spec: DynamicViewSpec)
  ProposeReleasePolicy(spec: DynamicReleaseSpec)
  ProposeClearance(grant_id: Text, target_clearance: Policy.Sensitivity, justification: Text)
  ProposeInvariant(spec: DynamicInvariantSpec)
end

## Review lifecycle status of a governance proposal.
enum ProposalStatus
  Pending
  Approved
  Rejected
  Withdrawn
end

## Machine-checked summary showing exactly what capability changes if the proposal is approved.
struct CapabilityDiff
  widens_access: Bool
  narrows_only: Bool
  declassifies: Bool
  risk_level: Text
  affected_targets: List(Text)
  newly_exposed_fields: List(Text)
  max_sensitivity_before: Policy.Sensitivity
  max_sensitivity_after: Policy.Sensitivity
  existing_violations: Int
  summary: Text
end

## Persisted governance proposal record in `_modb_gov_proposals`.
struct GovernanceProposal
  id: Text
  proposer: Text
  proposer_grant_id: Option(Text)
  kind: ProposalKind
  diff: CapabilityDiff
  status: ProposalStatus
  submitted_at: Time
  reviewed_by: Option(Text)
  review_note: Option(Text)
  reviewed_at: Option(Time)
end

## Every failure returned by `Modb.Proposals` operations.
enum ProposalError
  LedgerFailure(LedgerError)
  GrantFailure(Grants.GrantError)
  PolicyFailure(Policy.PolicyError)
  InvalidProposal(reason: Text)
  ProposalAlreadyExists(id: Text)
  ProposalNotFound(id: Text)
  ProposalNotPending(id: Text, status: ProposalStatus)
  ApprovalDenied(reason: Text)
  ExistingDataViolatesInvariant(
    name: Text,
    bucket: Text,
    violation_count: Int,
    sample: Text
  )
end

## Formats a `ProposalError` as a human-readable diagnostic.
fn to_text(err: ProposalError) : Text
  case err
    LedgerFailure(e): e.to_text
    GrantFailure(e): e.to_text
    PolicyFailure(e): Policy.to_text(e)
    InvalidProposal(reason: r): "invalid proposal: #{r}"
    ProposalAlreadyExists(id: i): "governance proposal '#{i}' already exists"
    ProposalNotFound(id: i): "governance proposal '#{i}' not found"
    ProposalNotPending(id: i, status: st): "governance proposal '#{i}' is already '#{status_label(st)}'"
    ApprovalDenied(reason: r): "approval denied: #{r}"
    ExistingDataViolatesInvariant(name: n, bucket: b, violation_count: c, sample: s): "cannot approve invariant '#{n}' on '#{b}': #{c} existing row(s) violate rule (e.g. #{s})"
  end
end

fn status_label(st: ProposalStatus) : Text
  case st
    Pending: "pending"
    Approved: "approved"
    Rejected: "rejected"
    Withdrawn: "withdrawn"
  end
end

fn proposals_by_status_index() : Index(Text, GovernanceProposal, Text)
  Table.text_index[Text, GovernanceProposal](
    proposals_by_status_bucket,
    fn(p) status_label(p.status) end
  )
end

fn proposals_table() : Table(Text, GovernanceProposal)
  Table.text_key[GovernanceProposal](proposals_bucket).with_index(proposals_by_status_index())
end

fn dynamic_views_table() : Table(Text, DynamicViewSpec)
  Table.text_key[DynamicViewSpec](dynamic_views_bucket)
end

fn dynamic_releases_table() : Table(Text, DynamicReleaseSpec)
  Table.text_key[DynamicReleaseSpec](dynamic_releases_bucket)
end

fn dynamic_invariants_table() : Table(Text, DynamicInvariantSpec)
  Table.text_key[DynamicInvariantSpec](dynamic_invariants_bucket)
end

fn wrap_table(res: Result(T, TableError)) : Result(T, ProposalError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, ProposalError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(Table.Storage(e))) end)
end

## Evaluates a declarative `InvariantRule` against raw serialized bucket bytes (JSON object).
## Returns `None` when valid, or `Some(detail)` describing the violation.
fn eval_invariant_rule(rule: InvariantRule, raw_val: Bytes) : Option(Text)
  obj = case Json.decode[Json](raw_val)
    Ok(v): v
    Error(e): return Some("non-JSON row bytes: #{e.to_text}")
  end
  case rule
    FieldNonEmpty(field: f):
      case obj.text_at(f)
        Some(s):
          if s.trim.empty?
            Some("field '#{f}' cannot be empty")
          else
            None
          end
        None: Some("missing string field '#{f}'")
      end
    IntRange(field: f, min: min_opt, max: max_opt):
      n = case obj.int_at(f)
        Some(v): v
        None: return Some("missing integer field '#{f}'")
      end
      case min_opt
        Some(lo) if n < lo: return Some("field '#{f}' value #{n} < min #{lo}")
        Some(_) | None: Unit
      end
      case max_opt
        Some(hi) if n > hi: return Some("field '#{f}' value #{n} > max #{hi}")
        Some(_) | None: Unit
      end
      None
    AllowedValues(field: f, values: allowed):
      s = case obj.text_at(f)
        Some(v): v
        None: return Some("missing string field '#{f}'")
      end
      if allowed.any?(fn(a) a == s end)
        None
      else
        Some("field '#{f}' value '#{s}' not in [#{allowed.join(", ")}]")
      end
  end
end

fn scan_invariant_violations_tx(tx: WriteTx, spec: DynamicInvariantSpec) : Result(
  (Int, Text),
  ProposalError
)
  rows = try wrap_modb(Modb.tx_scan(tx, spec.bucket, None, None, 0))
  var cnt = 0
  var sample = ""
  for (_k, v) in rows
    case eval_invariant_rule(spec.rule, v)
      Some(msg):
        cnt += 1
        if sample.empty?
          sample = msg
        end
      None: Unit
    end
  end
  Ok((cnt, sample))
end

fn view_field_map(vdef: Views.ViewDef) : Map(Text, Views.ViewField)
  var m = {}
  for vf in vdef.fields
    m = m.set(vf.name, vf)
  end
  m
end

fn compute_diff_tx(
  tx: WriteTx,
  cat: Views.ViewCatalog,
  pol: Policy.SensitivityPolicy,
  kind: ProposalKind
) : Result(CapabilityDiff, ProposalError)
  case kind
    ProposeView(spec: vs):
      vname = vs.name.trim
      if vname.empty?
        return Error(InvalidProposal(reason: "view name cannot be empty"))
      end
      if vs.fields.empty?
        return Error(InvalidProposal(reason: "proposed view must expose at least one field"))
      end
      if cat.views.has?(vname)
        return Error(InvalidProposal(reason: "view '#{vname}' already exists in base catalog"))
      end
      if (try wrap_table(Table.tx_get(tx, dynamic_views_table(), vname))) is Some(_)
        return Error(InvalidProposal(reason: "dynamic view '#{vname}' already approved"))
      end
      base_vdef = try cat.views.get(vs.base_view).or_fail(
        InvalidProposal(reason: "unknown base_view '#{vs.base_view}'")
      )
      bfmap = view_field_map(base_vdef)
      var seen = Set.empty
      var max_after = Policy.Public
      for fname in vs.fields
        if seen.has?(fname)
          return Error(InvalidProposal(reason: "duplicate field '#{fname}' in view proposal"))
        end
        seen = seen.add(fname)
        if not bfmap.has?(fname)
          return Error(
            InvalidProposal(
              reason: "field '#{fname}' is not present on base view '#{vs.base_view}'"
            )
          )
        end
        base_fs = Policy.field_sensitivity(pol, vs.base_view, fname)
        prop_fs = vs.field_sensitivities.get(fname) or base_fs
        if Policy.rank(prop_fs) < Policy.rank(base_fs)
          return Error(
            InvalidProposal(
              reason: "cannot lower field '#{fname}' sensitivity below base view ('#{Policy
                .sensitivity_to_text(prop_fs)}' < '#{Policy.sensitivity_to_text(base_fs)}')"
            )
          )
        end
        max_after = Policy.max_sensitivity(max_after, prop_fs)
      end
      max_before = Policy.view_max_sensitivity(pol, base_vdef)
      omitted = base_vdef.fields.size - vs.fields.size
      Ok(
        CapabilityDiff(
          widens_access: false,
          narrows_only: true,
          declassifies: false,
          risk_level: "low",
          affected_targets: ["view:#{vname}", "base:#{vs.base_view}"],
          newly_exposed_fields: [],
          max_sensitivity_before: max_before,
          max_sensitivity_after: max_after,
          existing_violations: 0,
          summary: "Narrows '#{vs.base_view}' to #{vs.fields.size} field(s) (#{omitted} omitted); max sensitivity #{Policy
            .sensitivity_to_text(max_after)}"
        )
      )

    ProposeReleasePolicy(spec: rs):
      rname = rs.release_name.trim
      if rname.empty?
        return Error(InvalidProposal(reason: "release_name cannot be empty"))
      end
      if not cat.releases.has?(rname)
        return Error(InvalidProposal(reason: "unknown release '#{rname}' in catalog"))
      end
      if rs.min_group_size < 1
        return Error(InvalidProposal(reason: "min_group_size must be >= 1"))
      end
      declassifies? = Policy.rank(rs.output_sensitivity) < Policy.rank(rs.input_sensitivity)
      if declassifies? and rs.min_group_size < 2
        return Error(
          InvalidProposal(
            reason: "declassification requires k-anonymity min_group_size >= 2"
          )
        )
      end
      existing_opt = pol.release_policies.get(rname)
      var widens? = declassifies?
      var before_sens = rs.input_sensitivity
      case existing_opt
        Some(ex):
          before_sens = ex.output_sensitivity
          if Policy.rank(rs.output_sensitivity) < Policy.rank(ex.output_sensitivity) or
            rs.min_group_size < ex.min_group_size
            widens? = true
          else
            widens? = false
          end
        None: Unit
      end
      risk = if not widens?
        "low"
      else if Policy.rank(rs.input_sensitivity) >= Policy.rank(Policy.Confidential) and
        rs.min_group_size < 3
        "high"
      else
        "medium"
      end
      Ok(
        CapabilityDiff(
          widens_access: widens?,
          narrows_only: not widens?,
          declassifies: declassifies?,
          risk_level: risk,
          affected_targets: ["release:#{rname}"],
          newly_exposed_fields: [],
          max_sensitivity_before: before_sens,
          max_sensitivity_after: rs.output_sensitivity,
          existing_violations: 0,
          summary: "Release '#{rname}' policy: #{Policy.sensitivity_to_text(rs.input_sensitivity)} -> #{Policy
            .sensitivity_to_text(rs.output_sensitivity)} (k >= #{rs.min_group_size})"
        )
      )

    ProposeClearance(grant_id: gid, target_clearance: target, justification: _just):
      g_opt = try Grants.tx_get(tx, gid).map_error(fn(e) GrantFailure(e) end)
      g = try g_opt.or_fail(GrantFailure(Grants.GrantNotFound(id: gid)))
      case g.parent_id
        Some(pid):
          peff = try Policy.tx_effective_clearance(tx, pol, Some(pid), false).map_error(
            fn(e) PolicyFailure(e) end
          )
          if Policy.rank(target) > Policy.rank(peff)
            return Error(
              PolicyFailure(
                Policy.ClearanceWideningDenied(
                  grant_id: gid,
                  parent_id: pid,
                  requested: target,
                  parent_clearance: peff
                )
              )
            )
          end
        None: Unit
      end
      cur_eff = try Policy.tx_effective_clearance(tx, pol, Some(gid), false).map_error(
        fn(e) PolicyFailure(e) end
      )
      widens? = Policy.rank(target) > Policy.rank(cur_eff)
      risk = if not widens?
        "low"
      else if Policy.rank(target) >= Policy.rank(Policy.Confidential)
        "high"
      else
        "medium"
      end
      Ok(
        CapabilityDiff(
          widens_access: widens?,
          narrows_only: not widens?,
          declassifies: false,
          risk_level: risk,
          affected_targets: ["grant:#{gid}"],
          newly_exposed_fields: [],
          max_sensitivity_before: cur_eff,
          max_sensitivity_after: target,
          existing_violations: 0,
          summary: "Clearance on '#{gid}': #{Policy.sensitivity_to_text(cur_eff)} -> #{Policy
            .sensitivity_to_text(target)}"
        )
      )

    ProposeInvariant(spec: ispec):
      iname = ispec.name.trim
      if iname.empty?
        return Error(InvalidProposal(reason: "invariant name cannot be empty"))
      end
      bname = ispec.bucket.trim
      if bname.empty? or bname.starts_with?("_modb_")
        return Error(InvalidProposal(reason: "invariant bucket must be a non-internal user bucket"))
      end
      if (try wrap_table(Table.tx_get(tx, dynamic_invariants_table(), iname))) is Some(_)
        return Error(InvalidProposal(reason: "dynamic invariant '#{iname}' already approved"))
      end
      case ispec.rule
        FieldNonEmpty(field: f):
          if f.trim.empty?
            return Error(InvalidProposal(reason: "FieldNonEmpty field cannot be empty"))
          end
        IntRange(field: f, min: lo, max: hi):
          if f.trim.empty?
            return Error(InvalidProposal(reason: "IntRange field cannot be empty"))
          end
          case (lo, hi)
            (Some(a), Some(b)) if a > b:
              return Error(InvalidProposal(reason: "IntRange min #{a} > max #{b}"))
            _: Unit
          end
        AllowedValues(field: f, values: vs):
          if f.trim.empty? or vs.empty?
            return Error(
              InvalidProposal(reason: "AllowedValues requires non-empty field and values list")
            )
          end
      end
      (v_cnt, _sample) = try scan_invariant_violations_tx(tx, ispec)
      risk = if v_cnt > 0: "medium" else: "low"
      Ok(
        CapabilityDiff(
          widens_access: false,
          narrows_only: true,
          declassifies: false,
          risk_level: risk,
          affected_targets: ["bucket:#{bname}", "invariant:#{iname}"],
          newly_exposed_fields: [],
          max_sensitivity_before: Policy.Public,
          max_sensitivity_after: Policy.Public,
          existing_violations: v_cnt,
          summary: "Add commit invariant '#{iname}' on '#{bname}' (existing violations: #{v_cnt})"
        )
      )
  end
end

## Computes the machine-checked `CapabilityDiff` for `kind` against committed `store` without mutating state.
fn compute_capability_diff(
  store: Store,
  cat: Views.ViewCatalog,
  pol: Policy.SensitivityPolicy,
  kind: ProposalKind
) : Result(CapabilityDiff, ProposalError)
  compute_diff_tx(Modb.begin_write(store), cat, pol, kind)
end

## Looks up a governance proposal by ID.
fn get_proposal(store: Store, id: Text) : Result(Option(GovernanceProposal), ProposalError)
  wrap_table(Table.get(store, proposals_table(), id))
end

## Lists governance proposals, optionally filtered by `ProposalStatus`.
fn list_proposals(store: Store, status_opt: Option(ProposalStatus)) : Result(
  List(GovernanceProposal),
  ProposalError
)
  case status_opt
    Some(st):
      rows = try wrap_table(
        Table.lookup(store, proposals_table(), proposals_by_status_index(), status_label(st))
      )
      Ok(rows.map(fn(p) p.1 end))
    None:
      rows = try wrap_table(Table.all(store, proposals_table()))
      Ok(rows.map(fn(p) p.1 end))
  end
end

## Lists all approved dynamic View specifications persisted in `_modb_dynamic_views`.
fn list_dynamic_views(store: Store) : Result(List(DynamicViewSpec), ProposalError)
  rows = try wrap_table(Table.all(store, dynamic_views_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Lists all approved dynamic Release policies persisted in `_modb_dynamic_releases`.
fn list_dynamic_releases(store: Store) : Result(List(DynamicReleaseSpec), ProposalError)
  rows = try wrap_table(Table.all(store, dynamic_releases_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Lists all approved dynamic commit-time invariants persisted in `_modb_dynamic_invariants`.
fn list_dynamic_invariants(store: Store) : Result(List(DynamicInvariantSpec), ProposalError)
  rows = try wrap_table(Table.all(store, dynamic_invariants_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Submits a declarative governance proposal for human review, computing its `CapabilityDiff`
## and persisting it atomically in `_modb_gov_proposals` alongside `_modb_audit`.
fn submit_proposal(
  db: Db,
  cat: Views.ViewCatalog,
  pol: Policy.SensitivityPolicy,
  id: Text,
  kind: ProposalKind,
  proposer: Text,
  grant_id_opt: Option(Text),
  reason: Text,
  now: Time
) : Result((Db, GovernanceProposal), ProposalError)
  pid = id.trim
  if pid.empty?
    return Error(InvalidProposal(reason: "proposal id cannot be empty"))
  end
  who = proposer.trim
  if who.empty?
    return Error(InvalidProposal(reason: "proposer cannot be empty"))
  end
  meta_reason = if reason.trim.empty?: "submit governance proposal '#{pid}'" else: reason
  meta = WriteMeta(principal: who, action: "gov_proposal_submit", reason: meta_reason, at: now)
  payload = Json.Object({"proposal_id": Json.String(pid), "proposer": Json.String(who)})
  Ledger.transact(
    db,
    meta,
    "submit governance proposal '#{pid}'",
    payload,
    fn(e) LedgerFailure(e) end,
    fn(tx)
      if (try wrap_table(Table.tx_get(tx, proposals_table(), pid))) is Some(_)
        return Error(ProposalAlreadyExists(id: pid))
      end
      case grant_id_opt
        Some(gid):
          _ = try Grants.tx_verify_active(tx, gid, now).map_error(fn(e) GrantFailure(e) end)
        None: Unit
      end
      diff = try compute_diff_tx(tx, cat, pol, kind)
      prop = GovernanceProposal(
        id: pid,
        proposer: who,
        proposer_grant_id: grant_id_opt,
        kind: kind,
        diff: diff,
        status: Pending,
        submitted_at: now,
        reviewed_by: None,
        review_note: None,
        reviewed_at: None
      )
      t1 = try wrap_table(Table.put(tx, proposals_table(), pid, prop))
      Ok((t1, prop))
    end
  )
end

## Human-only atomic approval of a `Pending` proposal: re-verifies the `CapabilityDiff` against
## live state, applies the approved View / Release policy / Clearance / Invariant atomically, and
## marks the proposal `Approved` in `_modb_audit`.
fn approve_proposal(
  db: Db,
  cat: Views.ViewCatalog,
  pol: Policy.SensitivityPolicy,
  id: Text,
  reviewer: Text,
  is_admin: Bool,
  note: Text,
  now: Time
) : Result((Db, GovernanceProposal), ProposalError)
  if not is_admin
    return Error(ApprovalDenied(reason: "human admin review required to approve '#{id}'"))
  end
  who = reviewer.trim
  if who.empty?
    return Error(ApprovalDenied(reason: "reviewer cannot be empty"))
  end
  meta_reason = if note.trim.empty?: "approve governance proposal '#{id}'" else: note
  meta = WriteMeta(principal: who, action: "gov_proposal_approve", reason: meta_reason, at: now)
  payload = Json.Object({"proposal_id": Json.String(id), "reviewer": Json.String(who)})
  Ledger.transact(
    db,
    meta,
    "approve governance proposal '#{id}'",
    payload,
    fn(e) LedgerFailure(e) end,
    fn(tx)
      p_opt = try wrap_table(Table.tx_get(tx, proposals_table(), id))
      prop = try p_opt.or_fail(ProposalNotFound(id: id))
      if not (prop.status is Pending)
        return Error(ProposalNotPending(id: id, status: prop.status))
      end
      fresh_diff = try compute_diff_tx(tx, cat, pol, prop.kind)
      t_applied = case prop.kind
        ProposeView(spec: vs):
          try wrap_table(Table.put(tx, dynamic_views_table(), vs.name.trim, vs))
        ProposeReleasePolicy(spec: rs):
          try wrap_table(Table.put(tx, dynamic_releases_table(), rs.release_name.trim, rs))
        ProposeClearance(grant_id: gid, target_clearance: target, justification: just):
          creason = if note.trim.empty?: just else: note
          (t_c, _rec) = try Policy.tx_set_clearance(tx, pol, gid, target, who, creason, now).map_error(
            fn(e) PolicyFailure(e) end
          )
          t_c
        ProposeInvariant(spec: ispec):
          (v_cnt, sample) = try scan_invariant_violations_tx(tx, ispec)
          if v_cnt > 0
            return Error(
              ExistingDataViolatesInvariant(
                name: ispec.name,
                bucket: ispec.bucket,
                violation_count: v_cnt,
                sample: sample
              )
            )
          end
          try wrap_table(Table.put(tx, dynamic_invariants_table(), ispec.name.trim, ispec))
      end
      var next_prop = prop
      next_prop.diff = fresh_diff
      next_prop.status = Approved
      next_prop.reviewed_by = Some(who)
      next_prop.review_note = Some(note)
      next_prop.reviewed_at = Some(now)
      t_done = try wrap_table(Table.put(t_applied, proposals_table(), id, next_prop))
      Ok((t_done, next_prop))
    end
  )
end

## Human-only rejection of a `Pending` proposal without modifying any target tables.
fn reject_proposal(
  db: Db,
  id: Text,
  reviewer: Text,
  is_admin: Bool,
  note: Text,
  now: Time
) : Result((Db, GovernanceProposal), ProposalError)
  if not is_admin
    return Error(ApprovalDenied(reason: "human admin review required to reject '#{id}'"))
  end
  who = reviewer.trim
  if who.empty?
    return Error(ApprovalDenied(reason: "reviewer cannot be empty"))
  end
  meta_reason = if note.trim.empty?: "reject governance proposal '#{id}'" else: note
  meta = WriteMeta(principal: who, action: "gov_proposal_reject", reason: meta_reason, at: now)
  payload = Json.Object({"proposal_id": Json.String(id), "reviewer": Json.String(who)})
  Ledger.transact(
    db,
    meta,
    "reject governance proposal '#{id}'",
    payload,
    fn(e) LedgerFailure(e) end,
    fn(tx)
      p_opt = try wrap_table(Table.tx_get(tx, proposals_table(), id))
      prop = try p_opt.or_fail(ProposalNotFound(id: id))
      if not (prop.status is Pending)
        return Error(ProposalNotPending(id: id, status: prop.status))
      end
      var next_prop = prop
      next_prop.status = Rejected
      next_prop.reviewed_by = Some(who)
      next_prop.review_note = Some(note)
      next_prop.reviewed_at = Some(now)
      t_done = try wrap_table(Table.put(tx, proposals_table(), id, next_prop))
      Ok((t_done, next_prop))
    end
  )
end

## Allows the proposer (or admin) to withdraw a `Pending` proposal cleanly.
fn withdraw_proposal(
  db: Db,
  id: Text,
  principal: Text,
  is_admin: Bool,
  reason: Text,
  now: Time
) : Result((Db, GovernanceProposal), ProposalError)
  who = principal.trim
  if who.empty?
    return Error(InvalidProposal(reason: "principal cannot be empty"))
  end
  meta_reason = if reason.trim.empty?: "withdraw governance proposal '#{id}'" else: reason
  meta = WriteMeta(principal: who, action: "gov_proposal_withdraw", reason: meta_reason, at: now)
  payload = Json.Object({"proposal_id": Json.String(id), "principal": Json.String(who)})
  Ledger.transact(
    db,
    meta,
    "withdraw governance proposal '#{id}'",
    payload,
    fn(e) LedgerFailure(e) end,
    fn(tx)
      p_opt = try wrap_table(Table.tx_get(tx, proposals_table(), id))
      prop = try p_opt.or_fail(ProposalNotFound(id: id))
      if not (prop.status is Pending)
        return Error(ProposalNotPending(id: id, status: prop.status))
      end
      if not is_admin and prop.proposer != who
        return Error(ApprovalDenied(reason: "only proposer '#{prop.proposer}' or admin may withdraw"))
      end
      var next_prop = prop
      next_prop.status = Withdrawn
      next_prop.reviewed_by = Some(who)
      next_prop.review_note = Some(reason)
      next_prop.reviewed_at = Some(now)
      t_done = try wrap_table(Table.put(tx, proposals_table(), id, next_prop))
      Ok((t_done, next_prop))
    end
  )
end

## Lock-coordinated multi-worker wrapper for `submit_proposal`.
fn submit_proposal_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Views.ViewCatalog,
  pol: Policy.SensitivityPolicy,
  id: Text,
  kind: ProposalKind,
  proposer: Text,
  grant_id_opt: Option(Text),
  reason: Text,
  now: Time
) : Result(GovernanceProposal, ProposalError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, prop) = try submit_proposal(db, cat, pol, id, kind, proposer, grant_id_opt, reason, now)
      Ok(prop)
    end
  )
end

## Lock-coordinated multi-worker wrapper for `approve_proposal`.
fn approve_proposal_locked(
  files: Files,
  path: Text,
  sc: Schema,
  cat: Views.ViewCatalog,
  pol: Policy.SensitivityPolicy,
  id: Text,
  reviewer: Text,
  is_admin: Bool,
  note: Text,
  now: Time
) : Result(GovernanceProposal, ProposalError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, prop) = try approve_proposal(db, cat, pol, id, reviewer, is_admin, note, now)
      Ok(prop)
    end
  )
end

## Lock-coordinated multi-worker wrapper for `reject_proposal`.
fn reject_proposal_locked(
  files: Files,
  path: Text,
  sc: Schema,
  id: Text,
  reviewer: Text,
  is_admin: Bool,
  note: Text,
  now: Time
) : Result(GovernanceProposal, ProposalError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, prop) = try reject_proposal(db, id, reviewer, is_admin, note, now)
      Ok(prop)
    end
  )
end

## Lock-coordinated multi-worker wrapper for `withdraw_proposal`.
fn withdraw_proposal_locked(
  files: Files,
  path: Text,
  sc: Schema,
  id: Text,
  principal: Text,
  is_admin: Bool,
  reason: Text,
  now: Time
) : Result(GovernanceProposal, ProposalError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, prop) = try withdraw_proposal(db, id, principal, is_admin, reason, now)
      Ok(prop)
    end
  )
end

## Materializes all approved dynamic narrowed Views on top of `base_cat`, wrapping the base
## View loader and strictly projecting to `spec.fields`.
fn materialize_catalog(store: Store, base_cat: Views.ViewCatalog) : Result(
  Views.ViewCatalog,
  ProposalError
)
  dviews = try list_dynamic_views(store)
  var out = base_cat
  for spec in dviews
    case out.views.get(spec.base_view)
      Some(base_vdef):
        bfmap = view_field_map(base_vdef)
        var vfields = []
        for fname in spec.fields
          case bfmap.get(fname)
            Some(vf): vfields = vfields.append(vf)
            None: Unit
          end
        end
        if not vfields.empty?
          kept_names = vfields.map(fn(f) f.name end)
          base_load = base_vdef.load
          vdef = Views.ViewDef(
            name: spec.name,
            description: spec.description,
            source_buckets: base_vdef.source_buckets,
            fields: vfields,
            narrows: Some(spec.base_view),
            load: fn(st)
              raw_rows = try base_load(st)
              Ok(
                raw_rows.map(fn(r)
                  var proj = {}
                  for k in kept_names
                    proj = proj.set(k, r.get(k) or Json.Null)
                  end
                  proj
                end)
              )
            end
          )
          out = Views.with_view(out, vdef)
        end
      None: Unit
    end
  end
  Ok(out)
end

## Materializes approved dynamic View field sensitivities (never below base View sensitivity)
## and approved dynamic Release policies on top of `base_pol`.
fn materialize_policy(store: Store, base_pol: Policy.SensitivityPolicy) : Result(
  Policy.SensitivityPolicy,
  ProposalError
)
  dviews = try list_dynamic_views(store)
  drels = try list_dynamic_releases(store)
  var out = base_pol
  for spec in dviews
    for fname in spec.fields
      base_fs = Policy.field_sensitivity(out, spec.base_view, fname)
      prop_fs = spec.field_sensitivities.get(fname) or base_fs
      eff_fs = Policy.max_sensitivity(base_fs, prop_fs)
      out = Policy.with_view_field_sensitivity(out, spec.name, fname, eff_fs)
    end
  end
  for rs in drels
    out = Policy.with_release_policy(
      out,
      rs.release_name,
      Policy.ReleasePolicy(
        input_sensitivity: rs.input_sensitivity,
        output_sensitivity: rs.output_sensitivity,
        min_group_size: rs.min_group_size
      )
    )
  end
  Ok(out)
end

## Attaches all approved dynamic commit-time invariants from `_modb_dynamic_invariants` to `base_sc`.
## Evaluates $O(\text{touched})$ rows during tracked `Ledger` writes and falls back to full scan otherwise.
fn apply_dynamic_invariants(store: Store, base_sc: Schema) : Result(Schema, ProposalError)
  dinvs = try list_dynamic_invariants(store)
  var out = base_sc
  for spec in dinvs
    s_copy = spec
    inv = Ledger.invariant(
      s_copy.name,
      fn(tx)
        if Modb.tx_is_tracked?(tx) and not Modb.tx_bucket_deleted?(tx, s_copy.bucket)
          for kb in Modb.tx_touched_puts(tx, s_copy.bucket)
            case try Modb.tx_get(tx, s_copy.bucket, kb).map_error(fn(e) Table.Storage(e) end)
              Some(vb):
                case eval_invariant_rule(s_copy.rule, vb)
                  Some(msg): return Ok(Some(msg))
                  None: Unit
                end
              None: Unit
            end
          end
          return Ok(None)
        end
        rows = try Modb.tx_scan(tx, s_copy.bucket, None, None, 0).map_error(fn(e) Table.Storage(e) end)
        for (_k, vb) in rows
          case eval_invariant_rule(s_copy.rule, vb)
            Some(msg): return Ok(Some(msg))
            None: Unit
          end
        end
        Ok(None)
      end
    )
    out = Ledger.with_invariant(out, inv)
  end
  Ok(out)
end

struct TaskRowSample
  id: Int
  title: Text
  priority: Int
  secret_budget: Int
end

test "Modb.Proposals: capability diffs, human review gate, view & O(touched) invariant materialization"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T16:15:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T18:00:00Z") or stop "t1"
  sc0 = Ledger.schema(0).with_require_reason(false)
  tbl = Table.int_key[TaskRowSample]("items")
  assert Ledger.open(files, "prop.modb", sc0, t0) is Ok(db0)
  assert Ledger.write(
    db0,
    Ledger.WriteMeta(principal: "admin", action: "seed", reason: "init", at: t0),
    "seed",
    Json.Null,
    fn(tx)
      t_a = try Table.put(tx, tbl, 1, TaskRowSample(id: 1, title: "alpha", priority: 2, secret_budget: 500))
      Table.put(t_a, tbl, 2, TaskRowSample(id: 2, title: "beta", priority: 5, secret_budget: 900))
    end
  ) is
    Ok(db1)

  vcat = Views.catalog().with_view(
    Views.ViewDef(
      name: "items_full",
      description: "Full items",
      source_buckets: ["items"],
      fields: [
        Views.ViewField(name: "id", field_type: "int", description: "id"),
        Views.ViewField(name: "title", field_type: "text", description: "title"),
        Views.ViewField(name: "priority", field_type: "int", description: "priority"),
        Views.ViewField(name: "secret_budget", field_type: "int", description: "budget")
      ],
      narrows: None,
      load: fn(store)
        rows = try Table.all(store, tbl).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            it = p.1
            {
              "id": Json.int(it.id),
              "title": Json.String(it.title),
              "priority": Json.int(it.priority),
              "secret_budget": Json.int(it.secret_budget)
            }
          end)
        )
      end
    )
  )
  pol = Policy.policy().with_view_field_sensitivity(
    "items_full",
    "secret_budget",
    Policy.Confidential
  )

  ## Negative control: attempting to lower secret_budget sensitivity in a view proposal fails statically
  assert submit_proposal(
    db1,
    vcat,
    pol,
    "p-bad-sens",
    ProposeView(
      spec: DynamicViewSpec(
        name: "items_leak",
        description: "bad",
        base_view: "items_full",
        fields: ["id", "secret_budget"],
        field_sensitivities: {"secret_budget": Policy.Public}
      )
    ),
    "agent:rogue",
    None,
    "try downgrade",
    t0
  ) is
    Error(InvalidProposal(reason: _))

  ## Valid narrowing View proposal -> risk_level = low, non-admin approval denied!
  assert submit_proposal(
    db1,
    vcat,
    pol,
    "p-view-1",
    ProposeView(
      spec: DynamicViewSpec(
        name: "items_triage",
        description: "Operational triage view",
        base_view: "items_full",
        fields: ["id", "title", "priority"],
        field_sensitivities: {}
      )
    ),
    "agent:planner",
    None,
    "add triage view",
    t0
  ) is
    Ok((db2, pv))
  assert pv.diff.narrows_only and not pv.diff.widens_access and pv.diff.risk_level == "low"
  assert approve_proposal(db2, vcat, pol, "p-view-1", "agent:planner", false, "self-approve", t0) is
    Error(ApprovalDenied(reason: _))
  assert approve_proposal(db2, vcat, pol, "p-view-1", "admin:lead", true, "lgtm", t0) is
    Ok((db3, _))

  assert materialize_catalog(Ledger.store(db3), vcat) is Ok(cat2)
  assert cat2.views.has?("items_triage")

  ## Propose invariant with existing violation (priority=5 > max 3) -> approval blocked!
  assert submit_proposal(
    db3,
    cat2,
    pol,
    "p-inv-bad",
    ProposeInvariant(
      spec: DynamicInvariantSpec(
        name: "prio_1_to_3",
        description: "prio 1..3",
        bucket: "items",
        rule: IntRange(field: "priority", min: Some(1), max: Some(3))
      )
    ),
    "agent:sre",
    None,
    "check prio",
    t0
  ) is
    Ok((db4, pb))
  assert pb.diff.existing_violations == 1
  assert approve_proposal(db4, cat2, pol, "p-inv-bad", "admin:lead", true, "try", t0) is
    Error(
      ExistingDataViolatesInvariant(
        name: "prio_1_to_3",
        bucket: "items",
        violation_count: 1,
        sample: _
      )
    )

  ## Clean invariant (`priority` in 1..10) approves cleanly and rejects future bad writes!
  assert submit_proposal(
    db4,
    cat2,
    pol,
    "p-inv-ok",
    ProposeInvariant(
      spec: DynamicInvariantSpec(
        name: "prio_1_to_10",
        description: "prio 1..10",
        bucket: "items",
        rule: IntRange(field: "priority", min: Some(1), max: Some(10))
      )
    ),
    "agent:sre",
    None,
    "add prio 1..10 guard",
    t0
  ) is
    Ok((db5, _))
  assert approve_proposal(db5, cat2, pol, "p-inv-ok", "admin:lead", true, "approved", t0) is
    Ok((_db6, _))

  assert apply_dynamic_invariants(Ledger.store(_db6), sc0) is Ok(sc_dyn)
  assert Ledger.open(files, "prop.modb", sc_dyn, t0) is Ok(db7)
  assert Ledger.write(
    db7,
    Ledger.WriteMeta(principal: "agent:w", action: "put", reason: "bad prio", at: t1),
    "bad",
    Json.Null,
    fn(tx) Table.put(tx, tbl, 3, TaskRowSample(id: 3, title: "gamma", priority: 99, secret_budget: 1)) end
  ) is
    Error(Ledger.InvariantViolation(name: "prio_1_to_10", detail: _))
  assert Ledger.write(
    db7,
    Ledger.WriteMeta(principal: "agent:w", action: "put", reason: "ok prio", at: t1),
    "ok",
    Json.Null,
    fn(tx) Table.put(tx, tbl, 3, TaskRowSample(id: 3, title: "gamma", priority: 7, secret_budget: 1)) end
  ) is
    Ok(_)
end
