## Milestone 3: Multi-agent concurrent typed HTTP/REST API server (`mo serve --workers 8`)
## backed by pure-Mo MoDB (Layer 1 CoW B+Tree + persistent root pins + O(diff) tree diff +
## Layer 2 typed tables & secondary indexes + Layer 3 accountable tamper-evident audit ledger,
## commit-time invariants, migrations + Layer 4 attenuated Grants, Claims, and speculative Worlds).
##
## Every `GET` route holds ONLY `ReadFiles` + advisory shared `flock`;
## every `POST`/`DELETE` route holds `Files` + advisory exclusive `flock`.
##
## Run locally:
##   mo serve --workers 8 --data ./shop-data examples/shop-api.mo
## Test in-memory (zero sockets):
##   mo test examples/shop-api.mo
module ShopApi
use Api
use Json
use Modb
use Modb.Claims
use Modb.Export
use Modb.Grants
use Modb.Ledger
use Modb.Replay
use Modb.Table
use Modb.World

enum Role
  Admin
  Clerk
  Agent
end

struct Caller
  principal: Text
  role: Role
  reason: Option(Text)
end

enum Tier
  Standard
  Member
end

struct Customer
  email: Text
  name: Text
  tier: Tier
end

struct CustomerInput
  id: Int
  email: Text
  name: Text
  tier: Tier
end

struct CustomerRow
  id: Int
  email: Text
  name: Text
  tier: Tier
end

struct Product
  title: Text
  category: Text
  price: Decimal
  stock: Int
end

struct ProductInput
  sku: Text
  title: Text
  category: Text
  price: Decimal
  stock: Int
end

struct ProductRow
  sku: Text
  title: Text
  category: Text
  price: Decimal
  stock: Int
end

enum OrderStatus
  Placed
  Shipped
end

struct Order
  buyer_id: Int
  sku: Text
  quantity: Int
  total: Decimal
  status: OrderStatus
end

struct OrderInput
  id: Int
  buyer_id: Int
  sku: Text
  quantity: Int
end

struct OrderRow
  id: Int
  buyer_id: Int
  sku: Text
  quantity: Int
  total: Decimal
  status: OrderStatus
end

struct HealthResponse
  status: Text
  txid: Int
  schema_version: Int
  audit_count: Int
end

struct VerifySummary
  ok: Bool
  txid: Int
  page_count: Int
  bucket_count: Int
  schema_version: Int
  audit_entries: Int
  last_audit_hash: Text
  invariants_checked: Int
end

struct GrantInput
  id: Text
  principal: Text
  allowed_actions: List(Text)
  max_calls: Int
  ttl_seconds: Int
end

struct ClaimInput
  resource: Text
  grant_id: Text
  world_id: Option(Text)
  ttl_seconds: Int
end

struct HeartbeatInput
  ttl_seconds: Int
end

struct WorldOpenInput
  id: Text
  grant_id: Text
  ttl_seconds: Int
end

struct WorldQueryInput
  query: Text
  args: Json
end

struct WorldCallInput
  action: Text
  args: Json
end

struct OkStatus
  ok: Bool
end

struct ReplaySimulateInput
  proposal_id: Text
  description: Text
  exclude_principal: Option(Text)
  exclude_grant: Option(Text)
  exclude_world: Option(Text)
  exclude_seqs: Option(List(Int))
  stop_before_seq: Option(Int)
  member_discount_override: Option(Decimal)
end

enum ShopApiError
  Unauthenticated
  Forbidden(required: Text)
  MissingReason
  InvalidInput(reason: Text)
  InvariantRejected(name: Text, detail: Text)
  EmailTaken(email: Text)
  CustomerMissing(id: Int)
  ProductMissing(sku: Text)
  OrderMissing(id: Int)
  InsufficientStock(sku: Text, requested: Int, available: Int)
  GrantMissing(id: Text)
  GrantDenied(detail: Text)
  GrantConflict(detail: Text)
  ClaimMissing(resource: Text)
  ClaimConflict(detail: Text)
  WorldMissing(id: Text)
  WorldConflict(detail: Text)
  ProposalMissing(id: Text)
  ProposalConflict(detail: Text)
  StorageFailed(message: Text)
end

api
  port 8091
  cors "*"
  auth Caller via authenticate

  get "/health" get_health

  scope "/customers"
    post "" post_customer
    get "/:id" get_customer
    get "/:id/orders" get_customer_orders
  end

  scope "/products"
    post "" post_product
    get "" list_products
    get "/:sku" get_product
  end

  scope "/orders"
    post "" post_order
    post "/:id/ship" post_ship_order
  end

  scope "/grants"
    post "" post_grant
    get "/:id" get_grant
    post "/:id/delegate" post_delegate_grant
    post "/:id/revoke" post_revoke_grant
  end

  scope "/claims"
    post "" post_claim
    get "" list_claims
    post "/:resource/heartbeat" post_claim_heartbeat
    delete "/:resource" delete_claim
  end

  scope "/worlds"
    post "" post_world
    get "/metrics" get_world_metrics
    post "/:id/query" post_world_query
    post "/:id/call" post_world_call
    get "/:id/diff" get_world_diff
    post "/:id/land" post_world_land
    delete "/:id" delete_world
  end

  get "/audit" get_audit
  post "/admin/init" post_admin_init
  get "/admin/verify" get_admin_verify
  get "/admin/export" get_admin_export

  scope "/admin/replay"
    get "/calls" get_replay_calls
    post "/simulate" post_replay_simulate
    get "/proposals" list_replay_proposals
    get "/proposals/:id" get_replay_proposal
    post "/proposals/:id/accept" post_replay_accept
    delete "/proposals/:id" delete_replay_proposal
  end

  status Unauthenticated = 401
  status Forbidden(_) = 403
  status MissingReason = 400
  status InvalidInput(_) = 400
  status InvariantRejected(_) = 422
  status EmailTaken(_) = 409
  status CustomerMissing(_) = 404
  status ProductMissing(_) = 404
  status OrderMissing(_) = 404
  status InsufficientStock(_) = 409
  status GrantMissing(_) = 404
  status GrantDenied(_) = 403
  status GrantConflict(_) = 409
  status ClaimMissing(_) = 404
  status ClaimConflict(_) = 409
  status WorldMissing(_) = 404
  status WorldConflict(_) = 409
  status ProposalMissing(_) = 404
  status ProposalConflict(_) = 409
  status StorageFailed(_) = 500
end

fn db_path() : Text
  "shop.modb"
end

fn customers_by_email() : Table.Index(Int, Customer, Text)
  Table.unique_text_index[Int, Customer]("customers_by_email", fn(c) c.email end)
end

fn customers_table() : Table.Table(Int, Customer)
  Table.int_key[Customer]("customers").with_index(customers_by_email())
end

fn products_by_category() : Table.Index(Text, Product, Text)
  Table.text_index[Text, Product]("products_by_category", fn(p) p.category end)
end

fn products_table() : Table.Table(Text, Product)
  Table.text_key[Product]("products").with_index(products_by_category())
end

fn orders_by_buyer() : Table.Index(Int, Order, Int)
  Table.int_index[Int, Order]("orders_by_buyer", fn(o) o.buyer_id end)
end

fn orders_table() : Table.Table(Int, Order)
  Table.int_key[Order]("orders").with_index(orders_by_buyer())
end

## Schema v1 -> v2 with three commit-time invariants enforced on every HTTP write.
fn shop_schema() : Ledger.Schema
  prods = products_table()
  ords = orders_table()
  Ledger.schema(2).with_require_reason(true).with_migration(
    Ledger.migration(
      1,
      "seed starter coffee catalog",
      fn(tx)
        Table.put(
          tx,
          prods,
          "house-blend",
          Product(title: "House Espresso Blend (250g)", category: "beans", price: 16.00, stock: 25)
        )
      end
    )
  ).with_migration(
    Ledger.migration(
      2,
      "seed starter pour-over dripper",
      fn(tx)
        Table.put(
          tx,
          prods,
          "brewer-v60",
          Product(title: "Ceramic Pour-Over Dripper", category: "gear", price: 26.00, stock: 5)
        )
      end
    )
  ).with_invariant(
    Ledger.row_invariant(
      "stock_non_negative",
      prods,
      fn(sku, p) if p.stock < 0: Some("product '#{sku}' stock #{p.stock} < 0") else: None end
    )
  ).with_invariant(
    Ledger.row_invariant(
      "price_positive",
      prods,
      fn(sku, p) if p.price <= 0.00: Some("product '#{sku}' price must be > 0") else: None end
    )
  ).with_invariant(
    Ledger.invariant(
      "order_referential_integrity",
      fn(tx)
        incremental? = Modb.tx_is_tracked?(tx) and
          not Modb.tx_bucket_deleted?(tx, "customers") and
          not Modb.tx_bucket_deleted?(tx, "products") and
          not Modb.tx_bucket_deleted?(tx, "orders") and
          Modb.tx_touched_deletes(tx, "customers").empty? and
          Modb.tx_touched_deletes(tx, "products").empty?
        if incremental?
          touched_ords = Modb.tx_touched_puts(tx, "orders")
          for kb in touched_ords
            case try Modb.tx_get(tx, "orders", kb).map_error(fn(e) Table.Storage(e) end)
              Some(vb):
                oid = try Table.decode_int_key(kb)
                o = try Json.decode[Order](vb).map_error(fn(e) Table.DecodeValue(e) end)
                if o.quantity <= 0
                  return Ok(Some("order ##{oid} has non-positive quantity #{o.quantity}"))
                end
                b_raw = try Modb.tx_get(tx, "customers", Table.encode_int_key(o.buyer_id)).map_error(
                  fn(e) Table.Storage(e) end
                )
                if b_raw is None
                  return Ok(Some("order ##{oid} references unknown buyer ##{o.buyer_id}"))
                end
                p_raw = try Modb.tx_get(tx, "products", o.sku.bytes).map_error(fn(e)
                  Table.Storage(e)
                end)
                if p_raw is None
                  return Ok(Some("order ##{oid} references unknown sku '#{o.sku}'"))
                end
              None: Unit
            end
          end
          return Ok(None)
        end
        all_orders = try Table.tx_scan(tx, ords, None, None, 0)
        var verified_buyers = Set.empty
        var verified_skus = Set.empty
        for (oid, o) in all_orders
          if o.quantity <= 0
            return Ok(Some("order ##{oid} has non-positive quantity #{o.quantity}"))
          end
          if not verified_buyers.has?(o.buyer_id)
            b_raw = try Modb.tx_get(tx, "customers", Table.encode_int_key(o.buyer_id)).map_error(
              fn(e) Table.Storage(e) end
            )
            if b_raw is None
              return Ok(Some("order ##{oid} references unknown buyer ##{o.buyer_id}"))
            end
            verified_buyers = verified_buyers.add(o.buyer_id)
          end
          if not verified_skus.has?(o.sku)
            p_raw = try Modb.tx_get(tx, "products", o.sku.bytes).map_error(
              fn(e) Table.Storage(e) end
            )
            if p_raw is None
              return Ok(Some("order ##{oid} references unknown sku '#{o.sku}'"))
            end
            verified_skus = verified_skus.add(o.sku)
          end
        end
        Ok(None)
      end
    )
  )
end

fn map_ledger_error(err: Ledger.LedgerError) : ShopApiError
  case err
    Ledger.InvalidMeta(reason: _): MissingReason
    Ledger.InvariantViolation(name: n, detail: d): InvariantRejected(name: n, detail: d)
    Ledger.TableFailure(Table.UniqueConflict(index: _, value: email)): EmailTaken(email: email)
    Ledger.TableFailure(Table.Storage(e)): StorageFailed(message: e.to_text)
    Ledger.TableFailure(Table.DecodeValue(e)): StorageFailed(message: e.to_text)
    Ledger.TableFailure(Table.DecodeKey(reason: r)): StorageFailed(message: r)
    Ledger.TableFailure(Table.CorruptIndex(index: idx, reason: r)): StorageFailed(
      message: "corrupt index '#{idx}': #{r}"
    )
    Ledger.SchemaTooNew(found: _, supported: _) | Ledger.InvalidMigration(reason: _) | Ledger
      .AuditCorrupt(reason: _): StorageFailed(message: err.to_text)
  end
end

fn map_table_error(err: Table.TableError) : ShopApiError
  map_ledger_error(Ledger.TableFailure(err))
end

fn map_grant_error(err: Grants.GrantError) : ShopApiError
  case err
    Grants.LedgerFailure(le): map_ledger_error(le)
    Grants.GrantNotFound(id: id): GrantMissing(id: id)
    Grants.GrantAlreadyExists(id: _): GrantConflict(detail: err.to_text)
    Grants.InvalidGrant(reason: r): InvalidInput(reason: r)
    Grants.WideningDenied(field: _, detail: _) | Grants.Revoked(id: _, revoked_ancestor: _) | Grants
      .Expired(id: _, expired_ancestor: _) | Grants.ActionDenied(id: _, action: _) | Grants
      .BudgetExhausted(id: _, ancestor_id: _, max_calls: _): GrantDenied(detail: err.to_text)
  end
end

fn map_claim_error(err: Claims.ClaimError) : ShopApiError
  case err
    Claims.LedgerFailure(le): map_ledger_error(le)
    Claims.InvalidClaim(reason: r): InvalidInput(reason: r)
    Claims.AlreadyClaimed(resource: _, holder: _, expires_at: _): ClaimConflict(detail: err.to_text)
    Claims.ClaimNotFound(resource: res): ClaimMissing(resource: res)
    Claims.NotHolder(resource: _, expected: _, actual: _): Forbidden(required: err.to_text)
  end
end

fn map_world_error(err: World.WorldError) : ShopApiError
  case err
    World.LedgerFailure(le): map_ledger_error(le)
    World.GrantFailure(ge): map_grant_error(ge)
    World.WorldNotFound(id: id): WorldMissing(id: id)
    World.UnknownQuery(name: _) | World.UnknownAction(name: _) | World.QueryFailed(
      query: _,
      detail: _
    ): InvalidInput(reason: err.to_text)
    World.InvariantRejected(name: n, detail: d): InvariantRejected(name: n, detail: d)
    World.WorldAlreadyExists(id: _) | World.WorldNotOpen(id: _, status: _) | World.WorldExpired(
      id: _
    ) | World.ActionRejected(action: _, detail: _) | World.StaleRead(
      query: _,
      args: _,
      expected: _,
      actual: _
    ): WorldConflict(detail: err.to_text)
  end
end

fn map_export_error(err: Export.ExportError) : ShopApiError
  case err
    Export.LedgerFailure(le): map_ledger_error(le)
    Export.StorageFailure(_) | Export.UnsupportedFormat(found: _, supported: _) | Export
      .InvalidEncoding(bucket: _, detail: _) | Export.ChecksumMismatch(expected: _, actual: _) | Export
      .TargetNotEmpty(path: _): StorageFailed(message: err.to_text)
  end
end

fn map_replay_error(err: Replay.ReplayError) : ShopApiError
  case err
    Replay.LedgerFailure(le): map_ledger_error(le)
    Replay.ExportFailure(ee): map_export_error(ee)
    Replay.GrantFailure(ge): map_grant_error(ge)
    Replay.ProposalNotFound(id: id): ProposalMissing(id: id)
    Replay.ProposalAlreadyExists(id: _) | Replay.ProposalNotPending(id: _, status: _) | Replay
      .ProposalStale(
        id: _,
        expected_audit_seq: _,
        actual_audit_seq: _,
        expected_call_seq: _,
        actual_call_seq: _
      ): ProposalConflict(detail: err.to_text)
    Replay.UnknownReplayAction(action: _, schema_version: _) | Replay.MissingReplayMigration(
      version: _
    ) | Replay.ReplayActionRejected(action: _, detail: _) | Replay.ReplayFailed(detail: _): InvalidInput(
      reason: err.to_text
    )
  end
end

## Approved query & write action catalog exposed to speculative multi-agent Worlds.
fn shop_catalog() : World.Catalog
  custs = customers_table()
  prods = products_table()
  ords = orders_table()
  p_cat_idx = products_by_category()
  World.catalog().with_query(
    "get_product",
    fn(tx, args)
      sku = try Json.decode[Text](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      p_opt = try Table.tx_get(tx, prods, sku).map_error(fn(e) e.to_text end)
      prod = try p_opt.or_fail("product '#{sku}' not found")
      Ok(
        ProductRow(
          sku: sku,
          title: prod.title,
          category: prod.category,
          price: prod.price,
          stock: prod.stock
        ).to_json
      )
    end
  ).with_query(
    "get_customer",
    fn(tx, args)
      id = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      c_opt = try Table.tx_get(tx, custs, id).map_error(fn(e) e.to_text end)
      cust = try c_opt.or_fail("customer ##{id} not found")
      Ok(CustomerRow(id: id, email: cust.email, name: cust.name, tier: cust.tier).to_json)
    end
  ).with_query(
    "list_products",
    fn(tx, args)
      cat_opt = try Json.decode[Option(Text)](Json.encode(args).bytes).map_error(
        fn(e) e.to_text end
      )
      rows = case cat_opt
        Some(cat): try Table.tx_lookup(tx, prods, p_cat_idx, cat).map_error(fn(e) e.to_text end)
        None: try Table.tx_scan(tx, prods, None, None, 0).map_error(fn(e) e.to_text end)
      end
      Ok(
        rows.map(fn(p)
          ProductRow(
            sku: p.0,
            title: p.1.title,
            category: p.1.category,
            price: p.1.price,
            stock: p.1.stock
          )
        end).to_json
      )
    end
  ).with_action(
    "place_order",
    fn(tx, args)
      body = try Json.decode[OrderInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      return Error("order id must be > 0") if body.id <= 0
      return Error("quantity must be > 0") if body.quantity <= 0
      buyer_opt = try Table.tx_get(tx, custs, body.buyer_id).map_error(fn(e) e.to_text end)
      buyer = try buyer_opt.or_fail("customer ##{body.buyer_id} not found")
      prod_opt = try Table.tx_get(tx, prods, body.sku).map_error(fn(e) e.to_text end)
      prod = try prod_opt.or_fail("product '#{body.sku}' not found")
      if prod.stock < body.quantity
        return Error(
          "insufficient stock for '#{body.sku}': requested #{body.quantity}, available #{prod.stock}"
        )
      end
      subtotal = prod.price * body.quantity.to_decimal
      total = case buyer.tier
        Standard: subtotal.round(2)
        Member: (subtotal * 0.90).round(2)
      end
      var updated_prod = prod
      updated_prod.stock -= body.quantity
      ord = Order(
        buyer_id: body.buyer_id,
        sku: body.sku,
        quantity: body.quantity,
        total: total,
        status: Placed
      )
      t1 = try Table.put(tx, prods, body.sku, updated_prod).map_error(fn(e) e.to_text end)
      t2 = try Table.put(t1, ords, body.id, ord).map_error(fn(e) e.to_text end)
      row = OrderRow(
        id: body.id,
        buyer_id: ord.buyer_id,
        sku: ord.sku,
        quantity: ord.quantity,
        total: ord.total,
        status: ord.status
      )
      Ok((t2, row.to_json))
    end
  ).with_action(
    "save_product",
    fn(tx, args)
      body = try Json.decode[ProductInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      return Error("sku cannot be empty") if body.sku.trim.empty?
      prod = Product(
        title: body.title,
        category: body.category,
        price: body.price,
        stock: body.stock
      )
      t1 = try Table.put(tx, prods, body.sku, prod).map_error(fn(e) e.to_text end)
      row = ProductRow(
        sku: body.sku,
        title: body.title,
        category: body.category,
        price: body.price,
        stock: body.stock
      )
      Ok((t1, row.to_json))
    end
  ).with_action(
    "ship_order",
    fn(tx, args)
      id = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      ord_opt = try Table.tx_get(tx, ords, id).map_error(fn(e) e.to_text end)
      ord = try ord_opt.or_fail("order ##{id} not found")
      var next = ord
      next.status = Shipped
      t1 = try Table.put(tx, ords, id, next).map_error(fn(e) e.to_text end)
      row = OrderRow(
        id: id,
        buyer_id: next.buyer_id,
        sku: next.sku,
        quantity: next.quantity,
        total: next.total,
        status: next.status
      )
      Ok((t1, row.to_json))
    end
  )
end

fn place_order_action(rate: Decimal) : fn(Modb.WriteTx, Json) : Result((Modb.WriteTx, Json), Text)
  custs = customers_table()
  prods = products_table()
  ords = orders_table()
  fn(tx, args)
    body = try Json.decode[OrderInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
    return Error("order id must be > 0") if body.id <= 0
    return Error("quantity must be > 0") if body.quantity <= 0
    buyer_opt = try Table.tx_get(tx, custs, body.buyer_id).map_error(fn(e) e.to_text end)
    buyer = try buyer_opt.or_fail("customer ##{body.buyer_id} not found")
    prod_opt = try Table.tx_get(tx, prods, body.sku).map_error(fn(e) e.to_text end)
    prod = try prod_opt.or_fail("product '#{body.sku}' not found")
    if prod.stock < body.quantity
      return Error(
        "insufficient stock for '#{body.sku}': requested #{body.quantity}, available #{prod.stock}"
      )
    end
    subtotal = prod.price * body.quantity.to_decimal
    total = case buyer.tier
      Standard: subtotal.round(2)
      Member: (subtotal * (1.00 - rate)).round(2)
    end
    var updated_prod = prod
    updated_prod.stock -= body.quantity
    ord = Order(
      buyer_id: body.buyer_id,
      sku: body.sku,
      quantity: body.quantity,
      total: total,
      status: Placed
    )
    t1 = try Table.put(tx, prods, body.sku, updated_prod).map_error(fn(e) e.to_text end)
    t2 = try Table.put(t1, ords, body.id, ord).map_error(fn(e) e.to_text end)
    row = OrderRow(
      id: body.id,
      buyer_id: ord.buyer_id,
      sku: ord.sku,
      quantity: ord.quantity,
      total: ord.total,
      status: ord.status
    )
    Ok((t2, row.to_json))
  end
end

## Replay action catalog covering all direct HTTP mutations and World actions, with optional
## Member discount rate override (e.g. `Some(0.20)` = 20% off) for live bug-fix replay demos.
fn shop_replay_catalog(member_discount_override: Option(Decimal)) : Replay.ReplayCatalog
  custs = customers_table()
  prods = products_table()
  ords = orders_table()

  base = Replay.catalog().with_action(
    "register_customer",
    fn(tx, args)
      body = try Json.decode[CustomerInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      return Error("customer id must be > 0") if body.id <= 0
      return Error("email cannot be empty") if body.email.trim.empty?
      cust = Customer(email: body.email, name: body.name, tier: body.tier)
      t1 = try Table.put(tx, custs, body.id, cust).map_error(fn(e) e.to_text end)
      row = CustomerRow(id: body.id, email: body.email, name: body.name, tier: body.tier)
      Ok((t1, row.to_json))
    end
  ).with_action(
    "save_product",
    fn(tx, args)
      body = try Json.decode[ProductInput](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      return Error("sku cannot be empty") if body.sku.trim.empty?
      prod = Product(
        title: body.title,
        category: body.category,
        price: body.price,
        stock: body.stock
      )
      t1 = try Table.put(tx, prods, body.sku, prod).map_error(fn(e) e.to_text end)
      row = ProductRow(
        sku: body.sku,
        title: body.title,
        category: body.category,
        price: body.price,
        stock: body.stock
      )
      Ok((t1, row.to_json))
    end
  ).with_action("place_order", place_order_action(0.10)).with_action(
    "ship_order",
    fn(tx, args)
      id = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      ord_opt = try Table.tx_get(tx, ords, id).map_error(fn(e) e.to_text end)
      ord = try ord_opt.or_fail("order ##{id} not found")
      var next = ord
      next.status = Shipped
      t1 = try Table.put(tx, ords, id, next).map_error(fn(e) e.to_text end)
      row = OrderRow(
        id: id,
        buyer_id: next.buyer_id,
        sku: next.sku,
        quantity: next.quantity,
        total: next.total,
        status: next.status
      )
      Ok((t1, row.to_json))
    end
  )
  case member_discount_override
    Some(rate): Replay.with_override_action(base, "place_order", place_order_action(rate))
    None: base
  end
end

## Authenticates callers via Bearer token and captures accountable `X-Reason` header.
fn authenticate(req: Api.Request, env: Env) : Result(Caller, ShopApiError)
  token = (req.bearer_token or "").trim
  return Error(Unauthenticated) if token.empty?
  admin_tok = env.get("SHOP_ADMIN_TOKEN") or "dev-admin"
  clerk_tok = env.get("SHOP_CLERK_TOKEN") or "dev-clerk"
  agent_tok = env.get("SHOP_AGENT_TOKEN") or "dev-agent"
  reason = req.header("X-Reason")
  if token == admin_tok
    Ok(Caller(principal: "admin:ada", role: Admin, reason: reason))
  else if token == clerk_tok
    Ok(Caller(principal: "clerk:grace", role: Clerk, reason: reason))
  else if token == agent_tok
    Ok(Caller(principal: "agent:order-bot", role: Agent, reason: reason))
  else
    Error(Unauthenticated)
  end
end

fn write_meta(caller: Caller, action: Text, clock: Clock) : Result(Ledger.WriteMeta, ShopApiError)
  reason = (caller.reason or "").trim
  return Error(MissingReason) if reason.empty?
  Ok(Ledger.WriteMeta(principal: caller.principal, action: action, reason: reason, at: clock.now))
end

fn require_staff(caller: Caller) : Result(Unit, ShopApiError)
  case caller.role
    Admin | Clerk: Ok(Unit)
    Agent: Error(Forbidden(required: "admin or clerk role"))
  end
end

fn require_admin(caller: Caller) : Result(Unit, ShopApiError)
  case caller.role
    Admin: Ok(Unit)
    Clerk | Agent: Error(Forbidden(required: "admin role"))
  end
end

## Public read-only health & ledger status endpoint (`ReadFiles` + shared `flock`).
fn get_health(rf: ReadFiles) : Result(HealthResponse, ShopApiError)
  if not rf.exists?(db_path())
    return Ok(HealthResponse(status: "uninitialized", txid: 0, schema_version: 0, audit_count: 0))
  end
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db)
      Ok(
        HealthResponse(
          status: "ok",
          txid: Ledger.txid(db),
          schema_version: Ledger.schema_version(db),
          audit_count: Ledger.audit_count(db)
        )
      )
    end
  )
end

## Idempotent Admin bootstrap endpoint: initializes and atomically runs migrations under exclusive lock.
fn post_admin_init(caller: Caller, files: Files, clock: Clock) : Result(
  HealthResponse,
  ShopApiError
)
  try require_admin(caller)
  (cur_txid, st) = try Ledger.init_locked(files, db_path(), shop_schema(), clock.now).map_error(
    map_ledger_error
  )
  Ok(
    HealthResponse(
      status: "ok",
      txid: cur_txid,
      schema_version: st.version,
      audit_count: st.next_audit_seq - 1
    )
  )
end

## Registers or updates a customer with unique-email enforcement, audit logging & replay capture.
fn post_customer(caller: Caller, files: Files, clock: Clock, body: CustomerInput) : Result(
  CustomerRow,
  ShopApiError
)
  try require_staff(caller)
  return Error(InvalidInput(reason: "customer id must be > 0")) if body.id <= 0
  return Error(InvalidInput(reason: "email cannot be empty")) if body.email.trim.empty?
  meta = try write_meta(caller, "register_customer", clock)
  cust = Customer(email: body.email, name: body.name, tier: body.tier)
  row = CustomerRow(id: body.id, email: body.email, name: body.name, tier: body.tier)
  custs = customers_table()
  Ledger.locked(
    files,
    db_path(),
    shop_schema(),
    meta.at,
    map_ledger_error,
    fn(db)
      sc_ver = Ledger.schema_version(db)
      aseq = db.state.next_audit_seq
      (_next, out) = try Ledger.transact(
        db,
        meta,
        "register customer ##{body.id} (#{body.email})",
        body.to_json,
        map_ledger_error,
        fn(tx)
          t1 = try Table.put(tx, custs, body.id, cust).map_error(map_table_error)
          (t2, _rec) = try Replay.tx_record_call(
            t1,
            sc_ver,
            Some(aseq),
            meta.principal,
            None,
            [],
            None,
            "register_customer",
            body.to_json,
            meta.reason,
            meta.at,
            Replay.OrigOk(reply: row.to_json)
          ).map_error(map_table_error)
          Ok((t2, row))
        end
      )
      Ok(out)
    end
  )
end

## Fetches a customer by primary ID (`ReadFiles` + shared `flock`).
fn get_customer(rf: ReadFiles, id: Int) : Result(CustomerRow, ShopApiError)
  custs = customers_table()
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db)
      cust_opt = try Table.get(Ledger.store(db), custs, id).map_error(map_table_error)
      cust = try cust_opt.or_fail(CustomerMissing(id: id))
      Ok(CustomerRow(id: id, email: cust.email, name: cust.name, tier: cust.tier))
    end
  )
end

## Lists all orders placed by customer `id` via `orders_by_buyer` (`ReadFiles` + shared `flock`).
fn get_customer_orders(rf: ReadFiles, id: Int) : Result(List(OrderRow), ShopApiError)
  custs = customers_table()
  ords = orders_table()
  idx = orders_by_buyer()
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db)
      if (try Table.get(Ledger.store(db), custs, id).map_error(map_table_error)) is None
        return Error(CustomerMissing(id: id))
      end
      rows = try Table.lookup(Ledger.store(db), ords, idx, id).map_error(map_table_error)
      Ok(
        rows.map(fn(p)
          OrderRow(
            id: p.0,
            buyer_id: p.1.buyer_id,
            sku: p.1.sku,
            quantity: p.1.quantity,
            total: p.1.total,
            status: p.1.status
          )
        end)
      )
    end
  )
end

## Upserts a product (Admin only); commit-time invariants reject price <= 0 or stock < 0.
fn post_product(caller: Caller, files: Files, clock: Clock, body: ProductInput) : Result(
  ProductRow,
  ShopApiError
)
  try require_admin(caller)
  return Error(InvalidInput(reason: "sku cannot be empty")) if body.sku.trim.empty?
  meta = try write_meta(caller, "save_product", clock)
  prod = Product(title: body.title, category: body.category, price: body.price, stock: body.stock)
  row = ProductRow(
    sku: body.sku,
    title: body.title,
    category: body.category,
    price: body.price,
    stock: body.stock
  )
  prods = products_table()
  Ledger.locked(
    files,
    db_path(),
    shop_schema(),
    meta.at,
    map_ledger_error,
    fn(db)
      sc_ver = Ledger.schema_version(db)
      aseq = db.state.next_audit_seq
      (_next, out) = try Ledger.transact(
        db,
        meta,
        "upsert product '#{body.sku}' (stock=#{body.stock}, price=#{body.price.to_fixed(2)})",
        body.to_json,
        map_ledger_error,
        fn(tx)
          t1 = try Table.put(tx, prods, body.sku, prod).map_error(map_table_error)
          (t2, _rec) = try Replay.tx_record_call(
            t1,
            sc_ver,
            Some(aseq),
            meta.principal,
            None,
            [],
            None,
            "save_product",
            body.to_json,
            meta.reason,
            meta.at,
            Replay.OrigOk(reply: row.to_json)
          ).map_error(map_table_error)
          Ok((t2, row))
        end
      )
      Ok(out)
    end
  )
end

## Lists products (`ReadFiles` + shared `flock`; uses `products_by_category` when `?category=` is passed).
fn list_products(rf: ReadFiles, category: Option(Text)) : Result(List(ProductRow), ShopApiError)
  prods = products_table()
  idx = products_by_category()
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db)
      rows = case category
        Some(cat): try Table.lookup(Ledger.store(db), prods, idx, cat).map_error(map_table_error)
        None: try Table.all(Ledger.store(db), prods).map_error(map_table_error)
      end
      Ok(
        rows.map(fn(p)
          ProductRow(
            sku: p.0,
            title: p.1.title,
            category: p.1.category,
            price: p.1.price,
            stock: p.1.stock
          )
        end)
      )
    end
  )
end

## Fetches a single product by SKU (`ReadFiles` + shared `flock`).
fn get_product(rf: ReadFiles, sku: Text) : Result(ProductRow, ShopApiError)
  prods = products_table()
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db)
      prod_opt = try Table.get(Ledger.store(db), prods, sku).map_error(map_table_error)
      prod = try prod_opt.or_fail(ProductMissing(sku: sku))
      Ok(
        ProductRow(
          sku: sku,
          title: prod.title,
          category: prod.category,
          price: prod.price,
          stock: prod.stock
        )
      )
    end
  )
end

## Places an order atomically under exclusive `flock` with exact `Decimal` Member discount,
## stock decrement, commit-time referential/stock invariants, hash-chained audit entry, and
## replay capture (including `InsufficientStock` refusals so selective undo surfaces `NowAccepted`).
fn post_order(caller: Caller, files: Files, clock: Clock, body: OrderInput) : Result(
  OrderRow,
  ShopApiError
)
  return Error(InvalidInput(reason: "order id must be > 0")) if body.id <= 0
  return Error(InvalidInput(reason: "quantity must be > 0")) if body.quantity <= 0
  meta = try write_meta(caller, "place_order", clock)
  custs = customers_table()
  prods = products_table()
  ords = orders_table()

  Ledger.locked(
    files,
    db_path(),
    shop_schema(),
    meta.at,
    map_ledger_error,
    fn(db)
      sc_ver = Ledger.schema_version(db)
      aseq = db.state.next_audit_seq
      res = Ledger.transact(
        db,
        meta,
        "place order ##{body.id} (#{body.quantity}x #{body.sku} for buyer ##{body.buyer_id})",
        body.to_json,
        map_ledger_error,
        fn(tx)
          buyer_opt = try Table.tx_get(tx, custs, body.buyer_id).map_error(map_table_error)
          buyer = try buyer_opt.or_fail(CustomerMissing(id: body.buyer_id))
          prod_opt = try Table.tx_get(tx, prods, body.sku).map_error(map_table_error)
          prod = try prod_opt.or_fail(ProductMissing(sku: body.sku))
          if prod.stock < body.quantity
            return Error(
              InsufficientStock(sku: body.sku, requested: body.quantity, available: prod.stock)
            )
          end
          subtotal = prod.price * body.quantity.to_decimal
          total = case buyer.tier
            Standard: subtotal.round(2)
            Member: (subtotal * 0.90).round(2)
          end
          var updated_prod = prod
          updated_prod.stock -= body.quantity
          ord = Order(
            buyer_id: body.buyer_id,
            sku: body.sku,
            quantity: body.quantity,
            total: total,
            status: Placed
          )
          row = OrderRow(
            id: body.id,
            buyer_id: ord.buyer_id,
            sku: ord.sku,
            quantity: ord.quantity,
            total: ord.total,
            status: ord.status
          )
          t1 = try Table.put(tx, prods, body.sku, updated_prod).map_error(map_table_error)
          t2 = try Table.put(t1, ords, body.id, ord).map_error(map_table_error)
          (t3, _rec) = try Replay.tx_record_call(
            t2,
            sc_ver,
            Some(aseq),
            meta.principal,
            None,
            [],
            None,
            "place_order",
            body.to_json,
            meta.reason,
            meta.at,
            Replay.OrigOk(reply: row.to_json)
          ).map_error(map_table_error)
          Ok((t3, row))
        end
      )
      case res
        Ok((_next, row)): Ok(row)
        Error(InsufficientStock(sku: s, requested: req, available: avail)):
          _ = try Replay.record_refused(
            db,
            meta.principal,
            None,
            [],
            None,
            "place_order",
            body.to_json,
            meta.reason,
            meta.at,
            "insufficient stock for '#{s}': requested #{req}, available #{avail}"
          ).map_error(map_replay_error)
          Error(InsufficientStock(sku: s, requested: req, available: avail))
        Error(other): Error(other)
      end
    end
  )
end

## Marks an order as shipped (Admin/Clerk only) under exclusive `flock` with replay capture.
fn post_ship_order(caller: Caller, files: Files, clock: Clock, id: Int) : Result(
  OrderRow,
  ShopApiError
)
  try require_staff(caller)
  meta = try write_meta(caller, "ship_order", clock)
  ords = orders_table()
  Ledger.locked(
    files,
    db_path(),
    shop_schema(),
    meta.at,
    map_ledger_error,
    fn(db)
      sc_ver = Ledger.schema_version(db)
      aseq = db.state.next_audit_seq
      (_next, row) = try Ledger.transact(
        db,
        meta,
        "ship order ##{id}",
        Json.Object({"order_id": id.to_json}),
        map_ledger_error,
        fn(tx)
          ord_opt = try Table.tx_get(tx, ords, id).map_error(map_table_error)
          ord = try ord_opt.or_fail(OrderMissing(id: id))
          var next = ord
          next.status = Shipped
          row = OrderRow(
            id: id,
            buyer_id: next.buyer_id,
            sku: next.sku,
            quantity: next.quantity,
            total: next.total,
            status: next.status
          )
          t1 = try Table.put(tx, ords, id, next).map_error(map_table_error)
          (t2, _rec) = try Replay.tx_record_call(
            t1,
            sc_ver,
            Some(aseq),
            meta.principal,
            None,
            [],
            None,
            "ship_order",
            id.to_json,
            meta.reason,
            meta.at,
            Replay.OrigOk(reply: row.to_json)
          ).map_error(map_table_error)
          Ok((t2, row))
        end
      )
      Ok(row)
    end
  )
end

## Issues a root grant (Admin only).
fn post_grant(caller: Caller, files: Files, clock: Clock, body: GrantInput) : Result(
  Grants.Grant,
  ShopApiError
)
  try require_admin(caller)
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  meta = try write_meta(caller, "issue_grant", clock)
  spec = Grants.GrantSpec(
    id: body.id,
    principal: body.principal,
    allowed_actions: body.allowed_actions,
    max_calls: body.max_calls,
    expires_at: clock.now + 1.second * body.ttl_seconds
  )
  Grants.issue_root_locked(files, db_path(), shop_schema(), meta, spec).map_error(map_grant_error)
end

## Reads a grant by ID (`ReadFiles` + shared `flock`).
fn get_grant(rf: ReadFiles, id: Text) : Result(Grants.Grant, ShopApiError)
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db)
      g_opt = try Grants.get(Ledger.store(db), id).map_error(map_grant_error)
      g_opt.or_fail(GrantMissing(id: id))
    end
  )
end

## Delegates a strictly narrowed helper grant from `id`.
fn post_delegate_grant(caller: Caller, files: Files, clock: Clock, id: Text, body: GrantInput) : Result(
  Grants.Grant,
  ShopApiError
)
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  meta = try write_meta(caller, "delegate_grant", clock)
  spec = Grants.GrantSpec(
    id: body.id,
    principal: body.principal,
    allowed_actions: body.allowed_actions,
    max_calls: body.max_calls,
    expires_at: clock.now + 1.second * body.ttl_seconds
  )
  Grants.delegate_locked(files, db_path(), shop_schema(), meta, id, spec).map_error(map_grant_error)
end

## Revokes grant `id` (Admin only; cascades immediately to all descendant grants).
fn post_revoke_grant(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Grants.Grant,
  ShopApiError
)
  try require_admin(caller)
  meta = try write_meta(caller, "revoke_grant", clock)
  Grants.revoke_locked(files, db_path(), shop_schema(), meta, id).map_error(map_grant_error)
end

## Acquires a resource claim/lease for slow-agent coordination.
fn post_claim(caller: Caller, files: Files, clock: Clock, body: ClaimInput) : Result(
  Claims.Claim,
  ShopApiError
)
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  meta = try write_meta(caller, "acquire_claim", clock)
  exp = clock.now + 1.second * body.ttl_seconds
  Claims.acquire_locked(
    files,
    db_path(),
    shop_schema(),
    meta,
    body.resource,
    body.grant_id,
    body.world_id,
    exp
  ).map_error(map_claim_error)
end

## Lists all currently active claims (`ReadFiles` + shared `flock`).
fn list_claims(rf: ReadFiles, clock: Clock) : Result(List(Claims.Claim), ShopApiError)
  now = clock.now
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db) Claims.list_active(Ledger.store(db), now).map_error(map_claim_error) end
  )
end

## Extends an active claim lease owned by the caller.
fn post_claim_heartbeat(
  caller: Caller,
  files: Files,
  clock: Clock,
  resource: Text,
  body: HeartbeatInput
) : Result(Claims.Claim, ShopApiError)
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  meta = try write_meta(caller, "heartbeat_claim", clock)
  exp = clock.now + 1.second * body.ttl_seconds
  Claims.heartbeat_locked(files, db_path(), shop_schema(), meta, resource, exp).map_error(
    map_claim_error
  )
end

## Releases a claim owned by the caller.
fn delete_claim(caller: Caller, files: Files, clock: Clock, resource: Text) : Result(
  OkStatus,
  ShopApiError
)
  meta = try write_meta(caller, "release_claim", clock)
  _ = try Claims.release_locked(files, db_path(), shop_schema(), meta, resource).map_error(
    map_claim_error
  )
  Ok(OkStatus(ok: true))
end

## Opens an O(1) persistent speculative World anchored to the current committed root.
fn post_world(caller: Caller, files: Files, clock: Clock, body: WorldOpenInput) : Result(
  World.WorldRecord,
  ShopApiError
)
  _ = caller
  return Error(InvalidInput(reason: "ttl_seconds must be > 0")) if body.ttl_seconds <= 0
  now = clock.now
  exp = now + 1.second * body.ttl_seconds
  World.open_world_locked(files, db_path(), shop_schema(), body.id, body.grant_id, now, exp)
    .map_error(map_world_error)
end

## Reads landing & needless send-back telemetry (`ReadFiles` + shared `flock`).
fn get_world_metrics(rf: ReadFiles) : Result(World.LandingMetrics, ShopApiError)
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db) World.metrics(Ledger.store(db)).map_error(map_world_error) end
  )
end

## Runs a registered read query inside World `id` and records its answer hash for landing validation.
fn post_world_query(caller: Caller, files: Files, clock: Clock, id: Text, body: WorldQueryInput) : Result(
  Json,
  ShopApiError
)
  _ = caller
  World.world_query_locked(
    files,
    db_path(),
    shop_schema(),
    shop_catalog(),
    id,
    body.query,
    body.args,
    clock.now
  ).map_error(map_world_error)
end

## Stages an approved write action inside World `id` (checks invariants immediately, main line untouched).
fn post_world_call(caller: Caller, files: Files, clock: Clock, id: Text, body: WorldCallInput) : Result(
  Json,
  ShopApiError
)
  reason = (caller.reason or "").trim
  return Error(MissingReason) if reason.empty?
  World.world_call_locked(
    files,
    db_path(),
    shop_schema(),
    shop_catalog(),
    id,
    body.action,
    body.args,
    reason,
    clock.now
  ).map_error(map_world_error)
end

## Computes the structural CoW diff for World `id` (`ReadFiles` + shared `flock`).
fn get_world_diff(rf: ReadFiles, id: Text) : Result(List(World.BucketDiffSummary), ShopApiError)
  World.world_diff_locked(rf, db_path(), shop_schema(), shop_catalog(), id).map_error(
    map_world_error
  )
end

## Lands World `id` whole-or-nothing with in-place read validation & per-call invariant enforcement.
fn post_world_land(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  World.LandResult,
  ShopApiError
)
  reason = (caller.reason or "").trim
  return Error(MissingReason) if reason.empty?
  World.land_world_locked(files, db_path(), shop_schema(), shop_catalog(), id, reason, clock.now)
    .map_error(map_world_error)
end

## Abandons an open World in O(1), unpinning its base root for freelist reclamation.
fn delete_world(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  OkStatus,
  ShopApiError
)
  _ = caller
  _ = try World.drop_world_locked(files, db_path(), shop_schema(), id, clock.now).map_error(
    map_world_error
  )
  Ok(OkStatus(ok: true))
end

## Queries the accountable audit log (`ReadFiles` + shared `flock`).
fn get_audit(
  rf: ReadFiles,
  principal: Option(Text),
  action: Option(Text),
  since: Option(Int),
  limit: Option(Int)
) : Result(List(Ledger.AuditEntry), ShopApiError)
  cap = limit or 50
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db)
      entries = case (principal, action, since)
        (Some(who), _, _): try Ledger.audit_by_principal(db, who).map_error(map_ledger_error)
        (None, Some(act), _): try Ledger.audit_by_action(db, act).map_error(map_ledger_error)
        (None, None, Some(s)): try Ledger.audit_since(db, s, cap).map_error(map_ledger_error)
        (None, None, None): try Ledger.audit_tail(db, cap).map_error(map_ledger_error)
      end
      if cap > 0 and entries.size > cap
        Ok(entries.drop(entries.size - cap))
      else
        Ok(entries)
      end
    end
  )
end

## Runs full B+Tree + audit hash-chain + schema invariant verification (`ReadFiles` + shared `flock`).
fn get_admin_verify(rf: ReadFiles) : Result(VerifySummary, ShopApiError)
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db)
      rep = try Ledger.verify_all(db).map_error(map_ledger_error)
      Ok(
        VerifySummary(
          ok: true,
          txid: rep.storage.txid,
          page_count: rep.storage.page_count,
          bucket_count: rep.storage.bucket_count,
          schema_version: rep.audit.schema_version,
          audit_entries: rep.audit.entry_count,
          last_audit_hash: rep.audit.last_hash,
          invariants_checked: rep.invariants_checked
        )
      )
    end
  )
end

## Exports a layout-independent SHA-256 verified portable JSON snapshot (`ReadFiles` + shared `flock`).
fn get_admin_export(rf: ReadFiles, clock: Clock, include_internal: Option(Bool)) : Result(
  Api.Response,
  ShopApiError
)
  inc = include_internal or true
  snap = try Export.export_locked(rf, db_path(), shop_schema(), inc, clock.now).map_error(
    map_export_error
  )
  Ok(
    Api.response(
      200,
      [("content-type", "application/json")],
      Export.encode_snapshot_json(snap).bytes
    )
  )
end

## Lists all recorded replayable calls (`ReadFiles` + shared `flock`).
fn get_replay_calls(rf: ReadFiles) : Result(List(Replay.CallRecord), ShopApiError)
  Ledger.read_locked(
    rf,
    db_path(),
    shop_schema(),
    map_ledger_error,
    fn(db) Replay.list_calls(Ledger.store(db)).map_error(map_replay_error) end
  )
end

## Simulates an offline replay (selective undo or bug-fix discount override) and persists a
## reviewable `ReplayProposal` without mutating live business tables (Admin only).
fn post_replay_simulate(caller: Caller, files: Files, clock: Clock, body: ReplaySimulateInput) : Result(
  Replay.ReplayProposal,
  ShopApiError
)
  try require_admin(caller)
  case body.member_discount_override
    Some(rate):
      if rate < 0.00 or rate >= 1.00
        return Error(InvalidInput(reason: "member_discount_override must be in [0.00, 1.00)"))
      end
    None: Unit
  end
  flt = case (
    body.exclude_principal,
    body.exclude_grant,
    body.exclude_world,
    body.exclude_seqs,
    body.stop_before_seq
  )
    (Some(p), _, _, _, _): Replay.ExcludePrincipal(principal: p)
    (None, Some(g), _, _, _): Replay.ExcludeGrant(grant_id: g)
    (None, None, Some(w), _, _): Replay.ExcludeWorld(world_id: w)
    (None, None, None, Some(seqs), _): Replay.ExcludeSeqs(seqs: seqs)
    (None, None, None, None, Some(s)): Replay.StopBeforeSeq(seq: s)
    (None, None, None, None, None): Replay.ReplayAll
  end
  rc = shop_replay_catalog(body.member_discount_override)
  Replay.simulate_replay_locked(
    files,
    db_path(),
    shop_schema(),
    rc,
    flt,
    body.proposal_id,
    body.description,
    caller.principal,
    clock.now
  ).map_error(map_replay_error)
end

## Lists all replay proposals (`ReadFiles` + shared `flock`).
fn list_replay_proposals(rf: ReadFiles) : Result(List(Replay.ReplayProposal), ShopApiError)
  Replay.list_proposals_locked(rf, db_path(), shop_schema()).map_error(map_replay_error)
end

## Inspects one replay proposal by ID (`ReadFiles` + shared `flock`).
fn get_replay_proposal(rf: ReadFiles, id: Text) : Result(Replay.ReplayProposal, ShopApiError)
  opt = try Replay.get_proposal_locked(rf, db_path(), shop_schema(), id).map_error(map_replay_error)
  opt.or_fail(ProposalMissing(id: id))
end

## Atomically adopts a fresh `Pending` replay proposal onto live state with audit logging (Admin only).
fn post_replay_accept(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Replay.ReplayProposal,
  ShopApiError
)
  try require_admin(caller)
  meta = try write_meta(caller, "accept_replay_proposal", clock)
  Replay.accept_proposal_locked(files, db_path(), shop_schema(), id, meta).map_error(
    map_replay_error
  )
end

## Discards a `Pending` replay proposal without touching live data (Admin only).
fn delete_replay_proposal(caller: Caller, files: Files, clock: Clock, id: Text) : Result(
  Replay.ReplayProposal,
  ShopApiError
)
  try require_admin(caller)
  Replay.discard_proposal_locked(files, db_path(), shop_schema(), id, caller.principal, clock.now)
    .map_error(map_replay_error)
end

test "ShopApi end-to-end via ApiTest.send: ReadFiles/Files split, locks, auth, X-Reason, invariants, orders, audit, and verify"
  files = Files.in_memory({})
  ro = files.read_only
  t0 = Time.parse("2026-11-25T03:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "SHOP_ADMIN_TOKEN": "tok-admin",
    "SHOP_CLERK_TOKEN": "tok-clerk",
    "SHOP_AGENT_TOKEN": "tok-agent"
  })

  ## 1. Read-only GET /health before init does NOT create or mutate shop.modb
  h_pre = ApiTest.send(ShopApi, Api.get("/health"), files, ro, clock, env)
  assert h_pre.status == 200
  assert Json.decode_strict[HealthResponse](h_pre.text) ==
    Ok(HealthResponse(status: "uninitialized", txid: 0, schema_version: 0, audit_count: 0))
  assert not files.exists?(db_path())

  ## Admin bootstrap runs atomic v0 -> v1 -> v2 schema migration under exclusive lock (idempotent)
  assert ApiTest.send(
    ShopApi,
    Api.post("/admin/init").with_bearer("tok-clerk"),
    files,
    ro,
    clock,
    env
  ).status ==
    403
  init_resp = ApiTest.send(
    ShopApi,
    Api.post("/admin/init").with_bearer("tok-admin"),
    files,
    ro,
    clock,
    env
  )
  assert init_resp.status == 200
  assert Json.decode_strict[HealthResponse](init_resp.text) ==
    Ok(HealthResponse(status: "ok", txid: 2, schema_version: 2, audit_count: 2))

  h0 = ApiTest.send(ShopApi, Api.get("/health"), files, clock, env)
  assert h0.status == 200
  assert Json.decode_strict[HealthResponse](h0.text) ==
    Ok(HealthResponse(status: "ok", txid: 2, schema_version: 2, audit_count: 2))

  ## 2. Unauthenticated write -> 401; Agent trying to register customer -> 403; missing X-Reason -> 400
  assert ApiTest.send(
    ShopApi,
    Api.post("/customers").with_json(
      CustomerInput(id: 1, email: "ada@shop.org", name: "Ada", tier: Member)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    401

  assert ApiTest.send(
    ShopApi,
    Api.post("/customers").with_bearer("tok-agent").with_header("X-Reason", "try").with_json(
      CustomerInput(id: 1, email: "ada@shop.org", name: "Ada", tier: Member)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    403

  assert ApiTest.send(
    ShopApi,
    Api.post("/customers").with_bearer("tok-clerk").with_json(
      CustomerInput(id: 1, email: "ada@shop.org", name: "Ada", tier: Member)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    400

  ## 3. Register customer + reject duplicate email with 409
  c1 = ApiTest.send(
    ShopApi,
    Api.post("/customers").with_bearer("tok-clerk").with_header("X-Reason", "signup-1").with_json(
      CustomerInput(id: 1, email: "ada@shop.org", name: "Ada Lovelace", tier: Member)
    ),
    files,
    ro,
    clock,
    env
  )
  assert c1.status == 200
  assert Json.decode_strict[CustomerRow](c1.text) ==
    Ok(CustomerRow(id: 1, email: "ada@shop.org", name: "Ada Lovelace", tier: Member))

  dup = ApiTest.send(
    ShopApi,
    Api.post("/customers").with_bearer("tok-clerk").with_header("X-Reason", "dup").with_json(
      CustomerInput(id: 2, email: "ada@shop.org", name: "Impostor", tier: Standard)
    ),
    files,
    ro,
    clock,
    env
  )
  assert dup.status == 409

  ## 4. Commit-time invariant rejects negative stock and non-positive price with 422 (zero audit entry)
  bad_stock = ApiTest.send(
    ShopApi,
    Api.post("/products").with_bearer("tok-admin").with_header("X-Reason", "bad-stock").with_json(
      ProductInput(sku: "bad-1", title: "Broken", category: "beans", price: 12.00, stock: -3)
    ),
    files,
    ro,
    clock,
    env
  )
  assert bad_stock.status == 422

  bad_price = ApiTest.send(
    ShopApi,
    Api.post("/products").with_bearer("tok-admin").with_header("X-Reason", "bad-price").with_json(
      ProductInput(sku: "bad-2", title: "Free", category: "beans", price: 0.00, stock: 5)
    ),
    files,
    ro,
    clock,
    env
  )
  assert bad_price.status == 422

  ## 5. Agent places order (10% Member discount on 2x $16.00 = $28.80) + oversold order rejected (409)
  ord = ApiTest.send(
    ShopApi,
    Api.post("/orders").with_bearer("tok-agent").with_header("X-Reason", "agent-task-77").with_json(
      OrderInput(id: 1001, buyer_id: 1, sku: "house-blend", quantity: 2)
    ),
    files,
    ro,
    clock,
    env
  )
  assert ord.status == 200
  assert Json.decode_strict[OrderRow](ord.text) ==
    Ok(
      OrderRow(id: 1001, buyer_id: 1, sku: "house-blend", quantity: 2, total: 28.80, status: Placed)
    )

  oversold = ApiTest.send(
    ShopApi,
    Api.post("/orders").with_bearer("tok-agent").with_header("X-Reason", "too-many").with_json(
      OrderInput(id: 1002, buyer_id: 1, sku: "brewer-v60", quantity: 99)
    ),
    files,
    ro,
    clock,
    env
  )
  assert oversold.status == 409

  ## 6. Ship order + verify secondary index queries (`?category=beans` and `/customers/1/orders`)
  ship = ApiTest.send(
    ShopApi,
    Api.post("/orders/1001/ship").with_bearer("tok-clerk").with_header("X-Reason", "packed-box"),
    files,
    ro,
    clock,
    env
  )
  assert ship.status == 200
  assert Json.decode_strict[OrderRow](ship.text) ==
    Ok(
      OrderRow(
        id: 1001,
        buyer_id: 1,
        sku: "house-blend",
        quantity: 2,
        total: 28.80,
        status: Shipped
      )
    )

  beans = ApiTest.send(ShopApi, Api.get("/products?category=beans"), files, ro, clock, env)
  assert beans.status == 200
  assert Json.decode_strict[List(ProductRow)](beans.text) ==
    Ok([
      ProductRow(
        sku: "house-blend",
        title: "House Espresso Blend (250g)",
        category: "beans",
        price: 16.00,
        stock: 23
      )
    ])

  cust_orders = ApiTest.send(ShopApi, Api.get("/customers/1/orders"), files, ro, clock, env)
  assert cust_orders.status == 200
  assert Json.decode_strict[List(OrderRow)](cust_orders.text) ==
    Ok([
      OrderRow(
        id: 1001,
        buyer_id: 1,
        sku: "house-blend",
        quantity: 2,
        total: 28.80,
        status: Shipped
      )
    ])

  ## 7. Accountable audit trail: 2 migrations + customer + order + ship = 5 entries
  agent_audit = ApiTest.send(
    ShopApi,
    Api.get("/audit?principal=agent:order-bot"),
    files,
    ro,
    clock,
    env
  )
  assert agent_audit.status == 200
  assert Json.decode_strict[List(Ledger.AuditEntry)](agent_audit.text) is Ok(agent_rows)
  assert agent_rows.size == 1
  first_agent = agent_rows.first or stop "expected agent audit row"
  assert first_agent.action == "place_order"
  assert first_agent.reason == "agent-task-77"

  ## 8. Full B+Tree + hash-chain + invariant verification + OpenAPI docs
  ver = ApiTest.send(ShopApi, Api.get("/admin/verify"), files, ro, clock, env)
  assert ver.status == 200
  assert Json.decode_strict[VerifySummary](ver.text) is Ok(vsum)
  assert vsum.ok and
    vsum.audit_entries == 5 and
    vsum.schema_version == 2 and
    vsum.invariants_checked == 3

  docs = ApiTest.send(ShopApi, Api.get("/docs"), files, ro, clock, env)
  assert docs.status == 200 and docs.text.contains?("/openapi.json")
end

test "ShopApi Milestone 3 via ApiTest.send: Grants delegation/revocation, Claims, and speculative Worlds"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "SHOP_ADMIN_TOKEN": "tok-admin",
    "SHOP_CLERK_TOKEN": "tok-clerk",
    "SHOP_AGENT_TOKEN": "tok-agent"
  })

  ## Bootstrap DB + customer #1
  assert ApiTest.send(ShopApi, Api.post("/admin/init").with_bearer("tok-admin"), files, clock, env)
    .status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/customers").with_bearer("tok-clerk").with_header("X-Reason", "seed").with_json(
      CustomerInput(id: 1, email: "ada@worlds.org", name: "Ada", tier: Member)
    ),
    files,
    clock,
    env
  ).status ==
    200

  ## 1. Admin issues root agent grant + delegates narrower helper grant; widening rejected (403)
  g_root = ApiTest.send(
    ShopApi,
    Api.post("/grants").with_bearer("tok-admin").with_header("X-Reason", "grant-lead").with_json(
      GrantInput(
        id: "g-lead",
        principal: "agent:lead",
        allowed_actions: ["place_order", "save_product"],
        max_calls: 10,
        ttl_seconds: 3600
      )
    ),
    files,
    clock,
    env
  )
  assert g_root.status == 200

  assert ApiTest.send(
    ShopApi,
    Api.post("/grants/g-lead/delegate").with_bearer("tok-agent").with_header("X-Reason", "widen")
      .with_json(
        GrantInput(
          id: "g-bad",
          principal: "helper:bad",
          allowed_actions: ["place_order", "ship_order"],
          max_calls: 5,
          ttl_seconds: 1800
        )
      ),
    files,
    clock,
    env
  ).status ==
    403

  g_help = ApiTest.send(
    ShopApi,
    Api.post("/grants/g-lead/delegate").with_bearer("tok-agent").with_header("X-Reason", "narrow")
      .with_json(
        GrantInput(
          id: "g-helper",
          principal: "helper:sub",
          allowed_actions: ["place_order"],
          max_calls: 5,
          ttl_seconds: 1800
        )
      ),
    files,
    clock,
    env
  )
  assert g_help.status == 200
  assert ApiTest.send(ShopApi, Api.get("/grants/g-helper"), files, clock, env).status == 200

  ## 2. Claims acquire, heartbeat, list (`ReadFiles`), and release
  assert ApiTest.send(
    ShopApi,
    Api.post("/claims").with_bearer("tok-agent").with_header("X-Reason", "pricing-pass").with_json(
      ClaimInput(resource: "sku:house-blend", grant_id: "g-lead", world_id: None, ttl_seconds: 300)
    ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(ShopApi, Api.get("/claims"), files, clock, env).status == 200
  assert ApiTest.send(
    ShopApi,
    Api.delete("/claims/sku:house-blend").with_bearer("tok-agent").with_header("X-Reason", "done"),
    files,
    clock,
    env
  ).status ==
    200

  ## 3. Stale-price World rejected with 409 when Admin reprices product before landing!
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds").with_bearer("tok-agent").with_json(
      WorldOpenInput(id: "w-stale", grant_id: "g-lead", ttl_seconds: 600)
    ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-stale/query").with_bearer("tok-agent").with_json(
      WorldQueryInput(query: "get_product", args: "house-blend".to_json)
    ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-stale/call").with_bearer("tok-agent").with_header("X-Reason", "order-at-16")
      .with_json(
        WorldCallInput(
          action: "place_order",
          args: OrderInput(id: 3001, buyer_id: 1, sku: "house-blend", quantity: 1).to_json
        )
      ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(ShopApi, Api.get("/worlds/w-stale/diff"), files, clock, env).status == 200

  ## Admin reprices house-blend $16 -> $20 on main line before w-stale lands
  assert ApiTest.send(
    ShopApi,
    Api.post("/products").with_bearer("tok-admin").with_header("X-Reason", "reprice").with_json(
      ProductInput(
        sku: "house-blend",
        title: "House Espresso Blend (250g)",
        category: "beans",
        price: 20.00,
        stock: 25
      )
    ),
    files,
    clock,
    env
  ).status ==
    200

  ## Landing w-stale MUST return 409 StaleRead and leave stock at 25!
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-stale/land").with_bearer("tok-agent").with_header("X-Reason", "land"),
    files,
    clock,
    env
  ).status ==
    409

  ## 4. Helper opens world -> Admin revokes parent g-lead -> helper landing blocked with 403!
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds").with_bearer("tok-agent").with_json(
      WorldOpenInput(id: "w-rev", grant_id: "g-helper", ttl_seconds: 600)
    ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-rev/call").with_bearer("tok-agent").with_header("X-Reason", "helper-order")
      .with_json(
        WorldCallInput(
          action: "place_order",
          args: OrderInput(id: 3002, buyer_id: 1, sku: "house-blend", quantity: 1).to_json
        )
      ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/grants/g-lead/revoke").with_bearer("tok-admin").with_header("X-Reason", "stop"),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-rev/land").with_bearer("tok-agent").with_header("X-Reason", "try-land"),
    files,
    clock,
    env
  ).status ==
    403

  ## 5. Fresh grant opens world, reads repriced $20, places order, lands cleanly (200) -> stock 24!
  assert ApiTest.send(
    ShopApi,
    Api.post("/grants").with_bearer("tok-admin").with_header("X-Reason", "grant-ok").with_json(
      GrantInput(
        id: "g-ok",
        principal: "agent:ok",
        allowed_actions: ["place_order"],
        max_calls: 5,
        ttl_seconds: 3600
      )
    ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds").with_bearer("tok-agent").with_json(
      WorldOpenInput(id: "w-ok", grant_id: "g-ok", ttl_seconds: 600)
    ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-ok/query").with_bearer("tok-agent").with_json(
      WorldQueryInput(query: "get_product", args: "house-blend".to_json)
    ),
    files,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-ok/call").with_bearer("tok-agent").with_header("X-Reason", "order-at-20")
      .with_json(
        WorldCallInput(
          action: "place_order",
          args: OrderInput(id: 3003, buyer_id: 1, sku: "house-blend", quantity: 1).to_json
        )
      ),
    files,
    clock,
    env
  ).status ==
    200
  land_ok = ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-ok/land").with_bearer("tok-agent").with_header("X-Reason", "commit"),
    files,
    clock,
    env
  )
  assert land_ok.status == 200
  assert Json.decode_strict[World.LandResult](land_ok.text) is Ok(lr)
  assert lr.calls_replayed == 1 and lr.reads_verified == 1

  met_resp = ApiTest.send(ShopApi, Api.get("/worlds/metrics"), files, clock, env)
  assert met_resp.status == 200
  assert Json.decode_strict[World.LandingMetrics](met_resp.text) is Ok(met)
  assert met.total_landed == 1 and met.stale_read_rejections == 1 and met.grant_rejections == 1

  ver = ApiTest.send(ShopApi, Api.get("/admin/verify"), files, clock, env)
  assert ver.status == 200
  assert Json.decode_strict[VerifySummary](ver.text) is Ok(vsum)
  assert vsum.ok
end

test "ShopApi Milestone 4 via ApiTest.send: Selective undo (NowAccepted), bug-fix discount replay & portable export"
  files = Files.in_memory({})
  ro = files.read_only
  t0 = Time.parse("2026-11-25T16:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "SHOP_ADMIN_TOKEN": "tok-admin",
    "SHOP_CLERK_TOKEN": "tok-clerk",
    "SHOP_AGENT_TOKEN": "tok-agent"
  })

  ## 1. Bootstrap DB + register Member customer #1
  assert ApiTest.send(
    ShopApi,
    Api.post("/admin/init").with_bearer("tok-admin"),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/customers").with_bearer("tok-clerk").with_header("X-Reason", "seed").with_json(
      CustomerInput(id: 1, email: "ada@replay.org", name: "Ada", tier: Member)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  ## 2. Issue root grant `g-rogue` -> child `g-rogue-sub`; rogue child drains all 5 brewer-v60 via World!
  assert ApiTest.send(
    ShopApi,
    Api.post("/grants").with_bearer("tok-admin").with_header("X-Reason", "grant-rogue").with_json(
      GrantInput(
        id: "g-rogue",
        principal: "agent:rogue",
        allowed_actions: ["place_order"],
        max_calls: 10,
        ttl_seconds: 3600
      )
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/grants/g-rogue/delegate").with_bearer("tok-agent").with_header("X-Reason", "sub")
      .with_json(
        GrantInput(
          id: "g-rogue-sub",
          principal: "helper:rogue",
          allowed_actions: ["place_order"],
          max_calls: 5,
          ttl_seconds: 1800
        )
      ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds").with_bearer("tok-agent").with_json(
      WorldOpenInput(id: "w-drain", grant_id: "g-rogue-sub", ttl_seconds: 600)
    ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-drain/call").with_bearer("tok-agent").with_header("X-Reason", "drain-all")
      .with_json(
        WorldCallInput(
          action: "place_order",
          args: OrderInput(id: 4001, buyer_id: 1, sku: "brewer-v60", quantity: 5).to_json
        )
      ),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  assert ApiTest.send(
    ShopApi,
    Api.post("/worlds/w-drain/land").with_bearer("tok-agent").with_header("X-Reason", "land"),
    files,
    ro,
    clock,
    env
  ).status ==
    200

  ## 3. Legitimate customer order #4002 for 2x brewer-v60 is REFUSED (409 InsufficientStock)!
  refused = ApiTest.send(
    ShopApi,
    Api.post("/orders").with_bearer("tok-clerk").with_header("X-Reason", "legit-order").with_json(
      OrderInput(id: 4002, buyer_id: 1, sku: "brewer-v60", quantity: 2)
    ),
    files,
    ro,
    clock,
    env
  )
  assert refused.status == 409

  ## 4. Admin simulates excluding `g-rogue` (catches child `g-rogue-sub`!):
  ##    proposal shows Excluded=1, NowAccepted=1, and live stock stays 0 until accepted!
  sim1 = ApiTest.send(
    ShopApi,
    Api.post("/admin/replay/simulate").with_bearer("tok-admin").with_json(
      ReplaySimulateInput(
        proposal_id: "undo-rogue",
        description: "Remove rogue grant subtree",
        exclude_principal: None,
        exclude_grant: Some("g-rogue"),
        exclude_world: None,
        exclude_seqs: None,
        stop_before_seq: None,
        member_discount_override: None
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert sim1.status == 200
  assert Json.decode_strict[Replay.ReplayProposal](sim1.text) is Ok(prop1)
  assert prop1.summary.excluded == 1 and prop1.summary.now_accepted == 1
  assert not prop1.bucket_diffs.empty?

  ## Live brewer-v60 stock is STILL 0 before Admin accepts!
  p_before = ApiTest.send(ShopApi, Api.get("/products/brewer-v60"), files, ro, clock, env)
  assert p_before.status == 200
  assert Json.decode_strict[ProductRow](p_before.text) is Ok(pb)
  assert pb.stock == 0

  ## Read-only inspection over ReadFiles works
  assert ApiTest.send(ShopApi, Api.get("/admin/replay/proposals/undo-rogue"), files, ro, clock, env)
    .status ==
    200

  ## 5. Admin accepts proposal -> order #4002 is now fulfilled (2x $26 * 0.90 = $46.80) and stock = 3!
  acc1 = ApiTest.send(
    ShopApi,
    Api.post("/admin/replay/proposals/undo-rogue/accept").with_bearer("tok-admin").with_header(
      "X-Reason",
      "approve rogue undo"
    ),
    files,
    ro,
    clock,
    env
  )
  assert acc1.status == 200

  p_after = ApiTest.send(ShopApi, Api.get("/products/brewer-v60"), files, ro, clock, env)
  assert Json.decode_strict[ProductRow](p_after.text) is Ok(pa)
  assert pa.stock == 3

  o_after = ApiTest.send(ShopApi, Api.get("/customers/1/orders"), files, ro, clock, env)
  assert Json.decode_strict[List(OrderRow)](o_after.text) ==
    Ok([
      OrderRow(id: 4002, buyer_id: 1, sku: "brewer-v60", quantity: 2, total: 46.80, status: Placed)
    ])

  ## 6. Bug-fix replay: override Member discount to 20% (0.20) while excluding `g-rogue` -> $41.60!
  sim2 = ApiTest.send(
    ShopApi,
    Api.post("/admin/replay/simulate").with_bearer("tok-admin").with_json(
      ReplaySimulateInput(
        proposal_id: "fix-member-discount",
        description: "Retroactively apply 20% Member discount",
        exclude_principal: None,
        exclude_grant: Some("g-rogue"),
        exclude_world: None,
        exclude_seqs: None,
        stop_before_seq: None,
        member_discount_override: Some(0.20)
      )
    ),
    files,
    ro,
    clock,
    env
  )
  assert sim2.status == 200
  assert ApiTest.send(
    ShopApi,
    Api.post("/admin/replay/proposals/fix-member-discount/accept").with_bearer("tok-admin")
      .with_header("X-Reason", "apply 20% discount fix"),
    files,
    ro,
    clock,
    env
  ).status ==
    200
  o_fixed = ApiTest.send(ShopApi, Api.get("/customers/1/orders"), files, ro, clock, env)
  assert Json.decode_strict[List(OrderRow)](o_fixed.text) ==
    Ok([
      OrderRow(id: 4002, buyer_id: 1, sku: "brewer-v60", quantity: 2, total: 41.60, status: Placed)
    ])

  ## 7. Full verify + portable export + round-trip import into a fresh file!
  ver = ApiTest.send(ShopApi, Api.get("/admin/verify"), files, ro, clock, env)
  assert ver.status == 200 and Json.decode_strict[VerifySummary](ver.text) is Ok(vs) and vs.ok

  exp = ApiTest.send(ShopApi, Api.get("/admin/export"), files, ro, clock, env)
  assert exp.status == 200
  assert Json.decode_strict[Export.PortableSnapshot](exp.text) is Ok(snap)
  assert Export.verify_snapshot(snap) is Ok(_)
  assert Export.import_db(files, "reimported-shop.modb", shop_schema(), snap, t0) is Ok(db_reimp)
  assert Ledger.verify_all(db_reimp) is Ok(_)
end
