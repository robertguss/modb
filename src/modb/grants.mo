## MoDB Layer 4: Attenuated Grants and Delegation Chains ("helpers get less, never more").
## Persisted in `_modb_grants` with atomic audit logging, strict non-widening enforcement,
## full-ancestor budget conservation, and immediate cascading revocation.
module Modb.Grants
expose GrantError(..),
Grant(..),
GrantSpec(..),
grants_bucket,
grants_by_principal_bucket,
grants_by_parent_bucket,
to_text,
grants_table,
get,
tx_get,
list_all,
list_by_principal,
list_children,
grant_subtree_ids,
tx_verify_active,
tx_issue_root,
tx_delegate,
tx_authorize,
tx_revoke,
issue_root,
delegate,
revoke,
issue_root_locked,
delegate_locked,
revoke_locked
use Json
use Modb{Store, WriteTx}
use Modb.Ledger{Db, LedgerError, Schema, WriteMeta}
use Modb.Table{Index, Table, TableError}

## Reserved internal bucket names for grants and secondary indexes.
grants_bucket = "_modb_grants"
grants_by_principal_bucket = "_modb_grants_by_principal"
grants_by_parent_bucket = "_modb_grants_by_parent"

## Every failure returned by `Modb.Grants` operations.
enum GrantError
  LedgerFailure(LedgerError)
  GrantNotFound(id: Text)
  GrantAlreadyExists(id: Text)
  InvalidGrant(reason: Text)
  WideningDenied(field: Text, detail: Text)
  Revoked(id: Text, revoked_ancestor: Text)
  Expired(id: Text, expired_ancestor: Text)
  ActionDenied(id: Text, action: Text)
  BudgetExhausted(id: Text, ancestor_id: Text, max_calls: Int)
end

## Formats a `GrantError` as a readable diagnostic.
fn to_text(err: GrantError) : Text
  case err
    LedgerFailure(e): e.to_text
    GrantNotFound(id: id): "grant '#{id}' not found"
    GrantAlreadyExists(id: id): "grant '#{id}' already exists"
    InvalidGrant(reason: r): "invalid grant: #{r}"
    WideningDenied(field: f, detail: d): "grant widening denied on '#{f}': #{d}"
    Revoked(id: id, revoked_ancestor: anc): "grant '#{id}' revoked (via '#{anc}')"
    Expired(id: id, expired_ancestor: anc): "grant '#{id}' expired (via '#{anc}')"
    ActionDenied(id: id, action: a): "grant '#{id}' does not permit action '#{a}'"
    BudgetExhausted(id: id, ancestor_id: anc, max_calls: m): "grant '#{id}' exhausted call budget #{m} (at '#{anc}')"
  end
end

## Persisted authority grant with delegation chain and remaining call budget.
struct Grant
  id: Text
  parent_id: Option(Text)
  principal: Text
  allowed_actions: List(Text)
  max_calls: Int
  used_calls: Int
  expires_at: Time
  revoked: Bool
  chain: List(Text)
end

## Caller-supplied parameters for issuing or delegating a grant.
struct GrantSpec
  id: Text
  principal: Text
  allowed_actions: List(Text)
  max_calls: Int
  expires_at: Time
end

fn grants_by_principal_index() : Index(Text, Grant, Text)
  Table.text_index[Text, Grant](grants_by_principal_bucket, fn(g) g.principal end)
end

fn grants_by_parent_index() : Index(Text, Grant, Text)
  Table.text_index[Text, Grant](grants_by_parent_bucket, fn(g) g.parent_id or "" end)
end

## Typed table descriptor for `_modb_grants` with principal and parent indexes.
fn grants_table() : Table(Text, Grant)
  Table.text_key[Grant](grants_bucket).with_index(grants_by_principal_index()).with_index(
    grants_by_parent_index()
  )
end

fn wrap_table(res: Result(T, TableError)) : Result(T, GrantError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

fn normalize_actions(actions: List(Text)) : Result(List(Text), GrantError)
  var seen = Set.empty
  var sorted = []
  for raw in actions
    a = raw.trim
    if a.empty?
      return Error(InvalidGrant(reason: "action name cannot be empty"))
    end
    if not seen.has?(a)
      seen = seen.add(a)
      var pos = 0
      while pos < sorted.size
        cur = sorted.get(pos) or stop "action sort idx"
        break if a < cur
        pos += 1
      end
      sorted = sorted.take(pos).append(a).concat(sorted.drop(pos))
    end
  end
  Ok(sorted)
end

fn list_has_text?(items: List(Text), target: Text) : Bool
  for item in items
    return true if item == target
  end
  false
end

fn validate_spec_basic(spec: GrantSpec) : Result(List(Text), GrantError)
  if spec.id.trim.empty?
    return Error(InvalidGrant(reason: "grant id cannot be empty"))
  end
  if spec.principal.trim.empty?
    return Error(InvalidGrant(reason: "grant principal cannot be empty"))
  end
  if spec.max_calls < 0
    return Error(InvalidGrant(reason: "max_calls must be >= 0, got #{spec.max_calls}"))
  end
  normalize_actions(spec.allowed_actions)
end

## Loads a grant and every ancestor up to the root (`[leaf, parent, ..., root]`).
fn load_ancestor_chain(tx: WriteTx, grant_id: Text) : Result(List(Grant), GrantError)
  tbl = grants_table()
  var chain = []
  var visited = Set.empty
  var cur_opt = Some(grant_id)
  while true
    case cur_opt
      None: break
      Some(cid):
        if visited.has?(cid)
          return Error(InvalidGrant(reason: "cycle in grant parent chain at '#{cid}'"))
        end
        visited = visited.add(cid)
        g_opt = try wrap_table(Table.tx_get(tx, tbl, cid))
        g = try g_opt.or_fail(GrantNotFound(id: cid))
        chain = chain.append(g)
        cur_opt = g.parent_id
    end
  end
  Ok(chain)
end

## Looks up a grant by ID on a committed `Store`.
fn get(store: Store, id: Text) : Result(Option(Grant), GrantError)
  wrap_table(Table.get(store, grants_table(), id))
end

## Looks up a grant by ID inside an active `WriteTx`.
fn tx_get(tx: WriteTx, id: Text) : Result(Option(Grant), GrantError)
  wrap_table(Table.tx_get(tx, grants_table(), id))
end

## Lists all persisted grants.
fn list_all(store: Store) : Result(List(Grant), GrantError)
  rows = try wrap_table(Table.all(store, grants_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Lists all grants issued to `principal`.
fn list_by_principal(store: Store, principal: Text) : Result(List(Grant), GrantError)
  rows = try wrap_table(Table.lookup(store, grants_table(), grants_by_principal_index(), principal))
  Ok(rows.map(fn(p) p.1 end))
end

## Lists direct child grants delegated from `parent_id`.
fn list_children(store: Store, parent_id: Text) : Result(List(Grant), GrantError)
  rows = try wrap_table(Table.lookup(store, grants_table(), grants_by_parent_index(), parent_id))
  Ok(rows.map(fn(p) p.1 end))
end

## Returns the set containing `root_id` and every descendant grant ID delegated beneath it.
fn grant_subtree_ids(store: Store, root_id: Text) : Result(Set(Text), GrantError)
  var seen = Set.empty.add(root_id)
  var queue = [root_id]
  var idx = 0
  while idx < queue.size
    cur = queue.get(idx) or stop "grant subtree queue index"
    idx += 1
    children = try list_children(store, cur)
    for ch in children
      if not seen.has?(ch.id)
        seen = seen.add(ch.id)
        queue = queue.append(ch.id)
      end
    end
  end
  Ok(seen)
end

## Verifies that `grant_id` and every ancestor in its delegation chain are active (unrevoked and
## unexpired at `now`), without consuming call budget.
fn tx_verify_active(tx: WriteTx, grant_id: Text, now: Time) : Result(Grant, GrantError)
  chain = try load_ancestor_chain(tx, grant_id)
  for anc in chain
    if anc.revoked
      return Error(Revoked(id: grant_id, revoked_ancestor: anc.id))
    end
    if now > anc.expires_at
      return Error(Expired(id: grant_id, expired_ancestor: anc.id))
    end
  end
  Ok(chain.first or stop "non-empty grant chain")
end

## Issues a root grant inside `tx` (typically called by an Admin principal).
fn tx_issue_root(tx: WriteTx, issuer: Text, spec: GrantSpec, now: Time) : Result(
  (WriteTx, Grant),
  GrantError
)
  if issuer.trim.empty?
    return Error(InvalidGrant(reason: "issuer principal cannot be empty"))
  end
  if spec.expires_at < now
    return Error(InvalidGrant(reason: "grant expires_at is already in the past"))
  end
  actions = try validate_spec_basic(spec)
  tbl = grants_table()
  if (try wrap_table(Table.tx_get(tx, tbl, spec.id))) is Some(_)
    return Error(GrantAlreadyExists(id: spec.id))
  end
  chain = if issuer == spec.principal: [issuer] else: [issuer, spec.principal]
  g = Grant(
    id: spec.id,
    parent_id: None,
    principal: spec.principal,
    allowed_actions: actions,
    max_calls: spec.max_calls,
    used_calls: 0,
    expires_at: spec.expires_at,
    revoked: false,
    chain: chain
  )
  t1 = try wrap_table(Table.put(tx, tbl, g.id, g))
  Ok((t1, g))
end

## Delegates a strictly narrowed child grant from `parent_id` inside `tx`.
## Enforces: active ancestor chain, `actions subset parent.actions`,
## `max_calls <= parent.remaining_calls`, and `expires_at <= parent.expires_at`.
fn tx_delegate(tx: WriteTx, parent_id: Text, spec: GrantSpec, now: Time) : Result(
  (WriteTx, Grant),
  GrantError
)
  actions = try validate_spec_basic(spec)
  parent = try tx_verify_active(tx, parent_id, now)
  tbl = grants_table()
  if (try wrap_table(Table.tx_get(tx, tbl, spec.id))) is Some(_)
    return Error(GrantAlreadyExists(id: spec.id))
  end

  for act in actions
    if not list_has_text?(parent.allowed_actions, act)
      return Error(
        WideningDenied(
          field: "allowed_actions",
          detail: "action '#{act}' is not permitted by parent grant '#{parent_id}'"
        )
      )
    end
  end

  remaining = parent.max_calls - parent.used_calls
  if spec.max_calls > remaining
    return Error(
      WideningDenied(
        field: "max_calls",
        detail: "requested #{spec.max_calls} exceeds parent '#{parent_id}' remaining budget #{remaining}"
      )
    )
  end

  if spec.expires_at > parent.expires_at
    return Error(
      WideningDenied(
        field: "expires_at",
        detail: "child expiry #{spec.expires_at.to_text} exceeds parent '#{parent_id}' expiry #{parent
          .expires_at.to_text}"
      )
    )
  end

  child = Grant(
    id: spec.id,
    parent_id: Some(parent_id),
    principal: spec.principal,
    allowed_actions: actions,
    max_calls: spec.max_calls,
    used_calls: 0,
    expires_at: spec.expires_at,
    revoked: false,
    chain: parent.chain.append(spec.principal)
  )
  t1 = try wrap_table(Table.put(tx, tbl, child.id, child))
  Ok((t1, child))
end

## Authorizes `action` under `grant_id` at `now` inside `tx`:
## verifies active ancestor chain (catching parent revocation), checks `action` permission,
## enforces call budget across `grant` AND every ancestor (conserving total authority),
## and increments `used_calls` along the chain.
fn tx_authorize(tx: WriteTx, grant_id: Text, action: Text, now: Time) : Result(
  (WriteTx, Grant),
  GrantError
)
  chain = try load_ancestor_chain(tx, grant_id)
  leaf = chain.first or stop "non-empty grant chain"
  for anc in chain
    if anc.revoked
      return Error(Revoked(id: grant_id, revoked_ancestor: anc.id))
    end
    if now > anc.expires_at
      return Error(Expired(id: grant_id, expired_ancestor: anc.id))
    end
  end
  if not list_has_text?(leaf.allowed_actions, action)
    return Error(ActionDenied(id: grant_id, action: action))
  end
  for anc in chain
    if anc.used_calls >= anc.max_calls
      return Error(BudgetExhausted(id: grant_id, ancestor_id: anc.id, max_calls: anc.max_calls))
    end
  end

  tbl = grants_table()
  var cur_tx = tx
  var updated_leaf = leaf
  var first? = true
  for anc in chain
    var next_anc = anc
    next_anc.used_calls += 1
    if first?
      updated_leaf = next_anc
      first? = false
    end
    cur_tx = try wrap_table(Table.put(cur_tx, tbl, next_anc.id, next_anc))
  end
  Ok((cur_tx, updated_leaf))
end

## Marks `grant_id` revoked inside `tx` (cascades immediately to all descendant grants).
fn tx_revoke(tx: WriteTx, grant_id: Text) : Result((WriteTx, Grant), GrantError)
  tbl = grants_table()
  g_opt = try wrap_table(Table.tx_get(tx, tbl, grant_id))
  g = try g_opt.or_fail(GrantNotFound(id: grant_id))
  var updated = g
  updated.revoked = true
  t1 = try wrap_table(Table.put(tx, tbl, updated.id, updated))
  Ok((t1, updated))
end

## Ledger-audited root grant issuance.
fn issue_root(db: Db, meta: WriteMeta, spec: GrantSpec) : Result((Db, Grant), GrantError)
  Ledger.transact(
    db,
    meta,
    "issue root grant '#{spec.id}' for #{spec.principal}",
    spec.to_json,
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_issue_root(tx, meta.principal, spec, meta.at) end
  )
end

## Ledger-audited narrowed grant delegation.
fn delegate(db: Db, meta: WriteMeta, parent_id: Text, spec: GrantSpec) : Result(
  (Db, Grant),
  GrantError
)
  Ledger.transact(
    db,
    meta,
    "delegate grant '#{spec.id}' from '#{parent_id}' to #{spec.principal}",
    Json.Object({"parent_id": parent_id.to_json, "spec": spec.to_json}),
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_delegate(tx, parent_id, spec, meta.at) end
  )
end

## Ledger-audited grant revocation (immediately blocks all descendants).
fn revoke(db: Db, meta: WriteMeta, grant_id: Text) : Result((Db, Grant), GrantError)
  Ledger.transact(
    db,
    meta,
    "revoke grant '#{grant_id}'",
    Json.Object({"grant_id": grant_id.to_json}),
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_revoke(tx, grant_id) end
  )
end

## Lock-coordinated root grant issuance for multi-worker HTTP servers.
fn issue_root_locked(files: Files, path: Text, sc: Schema, meta: WriteMeta, spec: GrantSpec) : Result(
  Grant,
  GrantError
)
  Ledger.transact_locked(
    files,
    path,
    sc,
    meta,
    "issue root grant '#{spec.id}' for #{spec.principal}",
    spec.to_json,
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_issue_root(tx, meta.principal, spec, meta.at) end
  )
end

## Lock-coordinated grant delegation for multi-worker HTTP servers.
fn delegate_locked(
  files: Files,
  path: Text,
  sc: Schema,
  meta: WriteMeta,
  parent_id: Text,
  spec: GrantSpec
) : Result(Grant, GrantError)
  Ledger.transact_locked(
    files,
    path,
    sc,
    meta,
    "delegate grant '#{spec.id}' from '#{parent_id}' to #{spec.principal}",
    Json.Object({"parent_id": parent_id.to_json, "spec": spec.to_json}),
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_delegate(tx, parent_id, spec, meta.at) end
  )
end

## Lock-coordinated grant revocation for multi-worker HTTP servers.
fn revoke_locked(files: Files, path: Text, sc: Schema, meta: WriteMeta, grant_id: Text) : Result(
  Grant,
  GrantError
)
  Ledger.transact_locked(
    files,
    path,
    sc,
    meta,
    "revoke grant '#{grant_id}'",
    Json.Object({"grant_id": grant_id.to_json}),
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_revoke(tx, grant_id) end
  )
end

test "Modb.Grants: attenuation, non-widening, ancestor budget conservation, and cascading revocation"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  t2 = Time.parse("2026-11-25T12:00:00Z") or stop "t2"
  sc = Ledger.schema(0).with_require_reason(true)
  assert Ledger.open(files, "grants.modb", sc, t0) is Ok(db0)

  admin_meta = WriteMeta(principal: "admin:ada", action: "grant_issue", reason: "init", at: t0)
  root_spec = GrantSpec(
    id: "g-agent",
    principal: "agent:planner",
    allowed_actions: ["place_order", "ship_order"],
    max_calls: 3,
    expires_at: t1
  )
  assert issue_root(db0, admin_meta, root_spec) is Ok((db1, g_agent))
  assert g_agent.chain == ["admin:ada", "agent:planner"]

  ## Widening actions, budget, or expiry MUST fail with WideningDenied
  del_meta = WriteMeta(
    principal: "agent:planner",
    action: "grant_delegate",
    reason: "helper",
    at: t0
  )
  assert delegate(
    db1,
    del_meta,
    "g-agent",
    GrantSpec(
      id: "bad-act",
      principal: "helper:1",
      allowed_actions: ["place_order", "delete_all"],
      max_calls: 1,
      expires_at: t1
    )
  ) is
    Error(WideningDenied(field: "allowed_actions", detail: _))

  assert delegate(
    db1,
    del_meta,
    "g-agent",
    GrantSpec(
      id: "bad-budget",
      principal: "helper:1",
      allowed_actions: ["place_order"],
      max_calls: 4,
      expires_at: t1
    )
  ) is
    Error(WideningDenied(field: "max_calls", detail: _))

  assert delegate(
    db1,
    del_meta,
    "g-agent",
    GrantSpec(
      id: "bad-exp",
      principal: "helper:1",
      allowed_actions: ["place_order"],
      max_calls: 2,
      expires_at: t2
    )
  ) is
    Error(WideningDenied(field: "expires_at", detail: _))

  ## Valid narrowed helper grant succeeds and inherits full chain
  assert delegate(
    db1,
    del_meta,
    "g-agent",
    GrantSpec(
      id: "g-helper",
      principal: "helper:worker",
      allowed_actions: ["place_order"],
      max_calls: 2,
      expires_at: t1
    )
  ) is
    Ok((db2, g_helper))
  assert g_helper.chain == ["admin:ada", "agent:planner", "helper:worker"]

  ## Helper cannot invoke ungranted action; invoking granted action consumes budget on helper & parent
  tx0 = Modb.begin_write(Ledger.store(db2))
  assert tx_authorize(tx0, "g-helper", "ship_order", t0) is
    Error(ActionDenied(id: "g-helper", action: "ship_order"))
  assert tx_authorize(tx0, "g-helper", "place_order", t0) is Ok((tx1, _))
  assert tx_authorize(tx1, "g-helper", "place_order", t0) is Ok((tx2, _))
  assert tx_authorize(tx2, "g-helper", "place_order", t0) is
    Error(BudgetExhausted(id: "g-helper", ancestor_id: "g-helper", max_calls: 2))

  ## Revoking parent immediately blocks helper
  rev_meta = WriteMeta(
    principal: "admin:ada",
    action: "grant_revoke",
    reason: "compromised",
    at: t0
  )
  assert revoke(db2, rev_meta, "g-agent") is Ok((db3, _))
  tx_rev = Modb.begin_write(Ledger.store(db3))
  assert tx_authorize(tx_rev, "g-helper", "place_order", t0) is
    Error(Revoked(id: "g-helper", revoked_ancestor: "g-agent"))
  assert Ledger.verify_all(db3) is Ok(_)
end
