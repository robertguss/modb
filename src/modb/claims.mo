## MoDB Layer 4: Agent Claims / Leases ("agents see each other through data").
## Ordinary typed lease records in `_modb_claims` with lazy TTL expiry and atomic audit logging,
## providing slow-agent starvation prevention without a lock manager.
module Modb.Claims
expose ClaimError(..),
Claim(..),
claims_bucket,
claims_by_holder_bucket,
to_text,
claims_table,
get_active,
list_active,
list_by_holder,
tx_acquire,
tx_heartbeat,
tx_release,
tx_force_release,
acquire,
heartbeat,
release,
acquire_locked,
heartbeat_locked,
release_locked
use Json
use Modb{Store, WriteTx}
use Modb.Ledger{Db, LedgerError, Schema, WriteMeta}
use Modb.Table{Index, Table, TableError}

## Reserved internal bucket names for claims and holder index.
claims_bucket = "_modb_claims"
claims_by_holder_bucket = "_modb_claims_by_holder"

## Every failure returned by `Modb.Claims` operations.
enum ClaimError
  LedgerFailure(LedgerError)
  InvalidClaim(reason: Text)
  AlreadyClaimed(resource: Text, holder: Text, expires_at: Time)
  ClaimNotFound(resource: Text)
  NotHolder(resource: Text, expected: Text, actual: Text)
end

## Formats a `ClaimError` as a readable diagnostic.
fn to_text(err: ClaimError) : Text
  case err
    LedgerFailure(e): e.to_text
    InvalidClaim(reason: r): "invalid claim: #{r}"
    AlreadyClaimed(resource: res, holder: h, expires_at: exp): "resource '#{res}' already claimed by #{h} until #{exp
      .to_text}"
    ClaimNotFound(resource: res): "no active claim on '#{res}'"
    NotHolder(resource: res, expected: exp, actual: act): "claim on '#{res}' belongs to #{exp}, not #{act}"
  end
end

## Ordinary persisted lease record visible to all agents as data.
struct Claim
  resource: Text
  holder: Text
  grant_id: Text
  world_id: Option(Text)
  reason: Text
  acquired_at: Time
  expires_at: Time
end

fn claims_by_holder_index() : Index(Text, Claim, Text)
  Table.text_index[Text, Claim](claims_by_holder_bucket, fn(c) c.holder end)
end

## Typed table descriptor for `_modb_claims` with secondary index on `holder`.
fn claims_table() : Table(Text, Claim)
  Table.text_key[Claim](claims_bucket).with_index(claims_by_holder_index())
end

fn wrap_table(res: Result(T, TableError)) : Result(T, ClaimError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

## Returns the claim on `resource` if one exists and has not expired at `now`.
fn get_active(store: Store, resource: Text, now: Time) : Result(Option(Claim), ClaimError)
  case try wrap_table(Table.get(store, claims_table(), resource))
    None: Ok(None)
    Some(c): if now >= c.expires_at: Ok(None) else: Ok(Some(c))
  end
end

## Lists all currently active (non-expired at `now`) claims across all resources.
fn list_active(store: Store, now: Time) : Result(List(Claim), ClaimError)
  rows = try wrap_table(Table.all(store, claims_table()))
  var out = []
  for (_k, c) in rows
    if now < c.expires_at
      out = out.append(c)
    end
  end
  Ok(out)
end

## Lists all currently active claims held by `holder`.
fn list_by_holder(store: Store, holder: Text, now: Time) : Result(List(Claim), ClaimError)
  rows = try wrap_table(Table.lookup(store, claims_table(), claims_by_holder_index(), holder))
  var out = []
  for (_k, c) in rows
    if now < c.expires_at
      out = out.append(c)
    end
  end
  Ok(out)
end

## Acquires or renews a lease on `resource` inside `tx`.
## Succeeds if unheld, expired at `now`, or already held by `holder`.
fn tx_acquire(
  tx: WriteTx,
  resource: Text,
  holder: Text,
  grant_id: Text,
  world_id: Option(Text),
  reason: Text,
  now: Time,
  expires_at: Time
) : Result((WriteTx, Claim), ClaimError)
  if resource.trim.empty?
    return Error(InvalidClaim(reason: "resource cannot be empty"))
  end
  if holder.trim.empty?
    return Error(InvalidClaim(reason: "holder cannot be empty"))
  end
  if expires_at <= now
    return Error(InvalidClaim(reason: "expires_at must be strictly after now"))
  end
  tbl = claims_table()
  case try wrap_table(Table.tx_get(tx, tbl, resource))
    Some(existing):
      if now < existing.expires_at and existing.holder != holder
        return Error(
          AlreadyClaimed(
            resource: resource,
            holder: existing.holder,
            expires_at: existing.expires_at
          )
        )
      end
    None: Unit
  end
  claim = Claim(
    resource: resource,
    holder: holder,
    grant_id: grant_id,
    world_id: world_id,
    reason: reason,
    acquired_at: now,
    expires_at: expires_at
  )
  t1 = try wrap_table(Table.put(tx, tbl, resource, claim))
  Ok((t1, claim))
end

## Extends an active lease held by `holder` inside `tx`.
fn tx_heartbeat(tx: WriteTx, resource: Text, holder: Text, now: Time, new_expires_at: Time) : Result(
  (WriteTx, Claim),
  ClaimError
)
  if new_expires_at <= now
    return Error(InvalidClaim(reason: "new_expires_at must be strictly after now"))
  end
  tbl = claims_table()
  existing_opt = try wrap_table(Table.tx_get(tx, tbl, resource))
  existing = try existing_opt.or_fail(ClaimNotFound(resource: resource))
  if now >= existing.expires_at
    return Error(ClaimNotFound(resource: resource))
  end
  if existing.holder != holder
    return Error(NotHolder(resource: resource, expected: existing.holder, actual: holder))
  end
  var next = existing
  next.expires_at = new_expires_at
  t1 = try wrap_table(Table.put(tx, tbl, resource, next))
  Ok((t1, next))
end

## Releases a claim held by `holder` inside `tx`.
fn tx_release(tx: WriteTx, resource: Text, holder: Text) : Result(WriteTx, ClaimError)
  tbl = claims_table()
  existing_opt = try wrap_table(Table.tx_get(tx, tbl, resource))
  existing = try existing_opt.or_fail(ClaimNotFound(resource: resource))
  if existing.holder != holder
    return Error(NotHolder(resource: resource, expected: existing.holder, actual: holder))
  end
  wrap_table(Table.delete(tx, tbl, resource))
end

## Force-releases a claim regardless of holder (Admin recovery).
fn tx_force_release(tx: WriteTx, resource: Text) : Result(WriteTx, ClaimError)
  wrap_table(Table.delete(tx, claims_table(), resource))
end

## Ledger-audited claim acquisition.
fn acquire(
  db: Db,
  meta: WriteMeta,
  resource: Text,
  grant_id: Text,
  world_id: Option(Text),
  expires_at: Time
) : Result((Db, Claim), ClaimError)
  Ledger.transact(
    db,
    meta,
    "claim '#{resource}' until #{expires_at.to_text}",
    Json.Object({
      "resource": resource.to_json,
      "grant_id": grant_id.to_json,
      "expires_at": expires_at.to_json
    }),
    fn(e) LedgerFailure(e) end,
    fn(tx)
      tx_acquire(tx, resource, meta.principal, grant_id, world_id, meta.reason, meta.at, expires_at)
    end
  )
end

## Ledger-audited claim heartbeat.
fn heartbeat(db: Db, meta: WriteMeta, resource: Text, new_expires_at: Time) : Result(
  (Db, Claim),
  ClaimError
)
  Ledger.transact(
    db,
    meta,
    "heartbeat claim '#{resource}' until #{new_expires_at.to_text}",
    Json.Object({"resource": resource.to_json, "expires_at": new_expires_at.to_json}),
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_heartbeat(tx, resource, meta.principal, meta.at, new_expires_at) end
  )
end

## Ledger-audited claim release.
fn release(db: Db, meta: WriteMeta, resource: Text) : Result(Db, ClaimError)
  (next_db, _u) = try Ledger.transact(
    db,
    meta,
    "release claim '#{resource}'",
    Json.Object({"resource": resource.to_json}),
    fn(e) LedgerFailure(e) end,
    fn(tx)
      t1 = try tx_release(tx, resource, meta.principal)
      Ok((t1, Unit))
    end
  )
  Ok(next_db)
end

## Lock-coordinated claim acquisition for multi-worker HTTP servers.
fn acquire_locked(
  files: Files,
  path: Text,
  sc: Schema,
  meta: WriteMeta,
  resource: Text,
  grant_id: Text,
  world_id: Option(Text),
  expires_at: Time
) : Result(Claim, ClaimError)
  Ledger.transact_locked(
    files,
    path,
    sc,
    meta,
    "claim '#{resource}' until #{expires_at.to_text}",
    Json.Object({
      "resource": resource.to_json,
      "grant_id": grant_id.to_json,
      "expires_at": expires_at.to_json
    }),
    fn(e) LedgerFailure(e) end,
    fn(tx)
      tx_acquire(tx, resource, meta.principal, grant_id, world_id, meta.reason, meta.at, expires_at)
    end
  )
end

## Lock-coordinated claim heartbeat for multi-worker HTTP servers.
fn heartbeat_locked(
  files: Files,
  path: Text,
  sc: Schema,
  meta: WriteMeta,
  resource: Text,
  new_expires_at: Time
) : Result(Claim, ClaimError)
  Ledger.transact_locked(
    files,
    path,
    sc,
    meta,
    "heartbeat claim '#{resource}' until #{new_expires_at.to_text}",
    Json.Object({"resource": resource.to_json, "expires_at": new_expires_at.to_json}),
    fn(e) LedgerFailure(e) end,
    fn(tx) tx_heartbeat(tx, resource, meta.principal, meta.at, new_expires_at) end
  )
end

## Lock-coordinated claim release for multi-worker HTTP servers.
fn release_locked(files: Files, path: Text, sc: Schema, meta: WriteMeta, resource: Text) : Result(
  Unit,
  ClaimError
)
  Ledger.transact_locked(
    files,
    path,
    sc,
    meta,
    "release claim '#{resource}'",
    Json.Object({"resource": resource.to_json}),
    fn(e) LedgerFailure(e) end,
    fn(tx)
      t1 = try tx_release(tx, resource, meta.principal)
      Ok((t1, Unit))
    end
  )
end

test "Modb.Claims: acquire, contention, heartbeat, expiry takeover, and release"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T10:05:00Z") or stop "t1"
  t2 = Time.parse("2026-11-25T10:10:00Z") or stop "t2"
  t3 = Time.parse("2026-11-25T10:15:00Z") or stop "t3"
  sc = Ledger.schema(0).with_require_reason(true)
  assert Ledger.open(files, "claims.modb", sc, t0) is Ok(db0)

  m_a = WriteMeta(principal: "agent:slow", action: "claim", reason: "repricing", at: t0)
  assert acquire(db0, m_a, "sku:house-blend", "g-1", Some("w-1"), t1) is Ok((db1, c1))
  assert c1.holder == "agent:slow"

  ## Competing agent blocked while lease is active
  m_b = WriteMeta(principal: "agent:fast", action: "claim", reason: "order", at: t0)
  assert acquire(db1, m_b, "sku:house-blend", "g-2", None, t2) is
    Error(AlreadyClaimed(resource: "sku:house-blend", holder: "agent:slow", expires_at: _))

  ## Heartbeat extends lease to t2; competing agent cannot heartbeat
  assert heartbeat(db1, m_b, "sku:house-blend", t2) is
    Error(NotHolder(resource: "sku:house-blend", expected: "agent:slow", actual: "agent:fast"))
  assert heartbeat(db1, m_a, "sku:house-blend", t2) is Ok((db2, c2))
  assert c2.expires_at == t2

  ## Once time passes t2, expired claim is ignored and agent:fast takes over cleanly
  assert get_active(Ledger.store(db2), "sku:house-blend", t2) == Ok(None)
  m_b_late = WriteMeta(principal: "agent:fast", action: "claim", reason: "takeover", at: t2)
  assert acquire(db2, m_b_late, "sku:house-blend", "g-2", None, t3) is Ok((db3, c3))
  assert c3.holder == "agent:fast"

  ## Release clears claim
  assert release(db3, m_b_late, "sku:house-blend") is Ok(db4)
  assert list_active(Ledger.store(db4), t2) == Ok([])
  assert Ledger.verify_all(db4) is Ok(_)
end
