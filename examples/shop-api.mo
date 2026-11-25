## Milestone 2A: Real typed HTTP/REST API server (`mo serve`) backed by pure-Mo MoDB
## (Layer 1 CoW B+Tree + Layer 2 typed tables & secondary indexes + Layer 3 accountable
## tamper-evident audit ledger, commit-time invariants, and atomic schema migrations).
##
## Run locally:
##   mo serve --workers 1 --data ./shop-data examples/shop-api.mo
## Test in-memory (zero sockets):
##   mo test examples/shop-api.mo
module ShopApi
use Api
use Json
use Modb.Ledger
use Modb.Table

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

  get "/audit" get_audit
  get "/admin/verify" get_admin_verify

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
  custs = customers_table()
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
        all_orders = try Table.tx_scan(tx, ords, None, None, 0)
        for (oid, o) in all_orders
          if o.quantity <= 0
            return Ok(Some("order ##{oid} has non-positive quantity #{o.quantity}"))
          end
          if (try Table.tx_get(tx, custs, o.buyer_id)) is None
            return Ok(Some("order ##{oid} references unknown buyer ##{o.buyer_id}"))
          end
          if (try Table.tx_get(tx, prods, o.sku)) is None
            return Ok(Some("order ##{oid} references unknown sku '#{o.sku}'"))
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

fn open_shop(files: Files, clock: Clock) : Result(Ledger.Db, ShopApiError)
  Ledger.open(files, db_path(), shop_schema(), clock.now).map_error(map_ledger_error)
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

## Public health & ledger status endpoint.
fn get_health(files: Files, clock: Clock) : Result(HealthResponse, ShopApiError)
  db = try open_shop(files, clock)
  Ok(
    HealthResponse(
      status: "ok",
      txid: Ledger.txid(db),
      schema_version: Ledger.schema_version(db),
      audit_count: Ledger.audit_count(db)
    )
  )
end

## Registers or updates a customer with unique-email enforcement and audit logging.
fn post_customer(caller: Caller, files: Files, clock: Clock, body: CustomerInput) : Result(
  CustomerRow,
  ShopApiError
)
  try require_staff(caller)
  return Error(InvalidInput(reason: "customer id must be > 0")) if body.id <= 0
  return Error(InvalidInput(reason: "email cannot be empty")) if body.email.trim.empty?
  meta = try write_meta(caller, "register_customer", clock)
  db = try open_shop(files, clock)
  cust = Customer(email: body.email, name: body.name, tier: body.tier)
  custs = customers_table()
  _ = try Ledger.write(
    db,
    meta,
    "register customer ##{body.id} (#{body.email})",
    body.to_json,
    fn(tx) Table.put(tx, custs, body.id, cust) end
  ).map_error(map_ledger_error)
  Ok(CustomerRow(id: body.id, email: body.email, name: body.name, tier: body.tier))
end

## Fetches a customer by primary ID.
fn get_customer(files: Files, clock: Clock, id: Int) : Result(CustomerRow, ShopApiError)
  db = try open_shop(files, clock)
  cust_opt = try Table.get(Ledger.store(db), customers_table(), id).map_error(map_table_error)
  cust = try cust_opt.or_fail(CustomerMissing(id: id))
  Ok(CustomerRow(id: id, email: cust.email, name: cust.name, tier: cust.tier))
end

## Lists all orders placed by customer `id` via the `orders_by_buyer` secondary index.
fn get_customer_orders(files: Files, clock: Clock, id: Int) : Result(List(OrderRow), ShopApiError)
  db = try open_shop(files, clock)
  if (try Table.get(Ledger.store(db), customers_table(), id).map_error(map_table_error)) is None
    return Error(CustomerMissing(id: id))
  end
  rows = try Table.lookup(Ledger.store(db), orders_table(), orders_by_buyer(), id).map_error(
    map_table_error
  )
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

## Upserts a product (Admin only); commit-time invariants reject price <= 0 or stock < 0.
fn post_product(caller: Caller, files: Files, clock: Clock, body: ProductInput) : Result(
  ProductRow,
  ShopApiError
)
  try require_admin(caller)
  return Error(InvalidInput(reason: "sku cannot be empty")) if body.sku.trim.empty?
  meta = try write_meta(caller, "save_product", clock)
  db = try open_shop(files, clock)
  prod = Product(title: body.title, category: body.category, price: body.price, stock: body.stock)
  prods = products_table()
  _ = try Ledger.write(
    db,
    meta,
    "upsert product '#{body.sku}' (stock=#{body.stock}, price=#{body.price.to_fixed(2)})",
    body.to_json,
    fn(tx) Table.put(tx, prods, body.sku, prod) end
  ).map_error(map_ledger_error)
  Ok(
    ProductRow(
      sku: body.sku,
      title: body.title,
      category: body.category,
      price: body.price,
      stock: body.stock
    )
  )
end

## Lists products (uses `products_by_category` secondary index when `?category=` is passed).
fn list_products(files: Files, clock: Clock, category: Option(Text)) : Result(
  List(ProductRow),
  ShopApiError
)
  db = try open_shop(files, clock)
  rows = case category
    Some(cat): try Table.lookup(Ledger.store(db), products_table(), products_by_category(), cat)
      .map_error(map_table_error)
    None: try Table.all(Ledger.store(db), products_table()).map_error(map_table_error)
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

## Fetches a single product by SKU.
fn get_product(files: Files, clock: Clock, sku: Text) : Result(ProductRow, ShopApiError)
  db = try open_shop(files, clock)
  prod_opt = try Table.get(Ledger.store(db), products_table(), sku).map_error(map_table_error)
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

## Places an order atomically with exact `Decimal` Member discount, stock decrement,
## commit-time referential/stock invariants, and a hash-chained audit entry.
fn post_order(caller: Caller, files: Files, clock: Clock, body: OrderInput) : Result(
  OrderRow,
  ShopApiError
)
  return Error(InvalidInput(reason: "order id must be > 0")) if body.id <= 0
  return Error(InvalidInput(reason: "quantity must be > 0")) if body.quantity <= 0
  meta = try write_meta(caller, "place_order", clock)
  db = try open_shop(files, clock)
  custs = customers_table()
  prods = products_table()
  ords = orders_table()

  (_next_db, placed) = try Ledger.transact(
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
      t1 = try Table.put(tx, prods, body.sku, updated_prod).map_error(map_table_error)
      t2 = try Table.put(t1, ords, body.id, ord).map_error(map_table_error)
      Ok((t2, ord))
    end
  )
  Ok(
    OrderRow(
      id: body.id,
      buyer_id: placed.buyer_id,
      sku: placed.sku,
      quantity: placed.quantity,
      total: placed.total,
      status: placed.status
    )
  )
end

## Marks an order as shipped (Admin/Clerk only).
fn post_ship_order(caller: Caller, files: Files, clock: Clock, id: Int) : Result(
  OrderRow,
  ShopApiError
)
  try require_staff(caller)
  meta = try write_meta(caller, "ship_order", clock)
  db = try open_shop(files, clock)
  ords = orders_table()
  (_next_db, shipped) = try Ledger.transact(
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
      t1 = try Table.put(tx, ords, id, next).map_error(map_table_error)
      Ok((t1, next))
    end
  )
  Ok(
    OrderRow(
      id: id,
      buyer_id: shipped.buyer_id,
      sku: shipped.sku,
      quantity: shipped.quantity,
      total: shipped.total,
      status: shipped.status
    )
  )
end

## Queries the accountable audit log (supports `?principal=`, `?action=`, `?since=`, `?limit=`).
fn get_audit(
  files: Files,
  clock: Clock,
  principal: Option(Text),
  action: Option(Text),
  since: Option(Int),
  limit: Option(Int)
) : Result(List(Ledger.AuditEntry), ShopApiError)
  db = try open_shop(files, clock)
  cap = limit or 50
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

## Runs full B+Tree + audit hash-chain + schema invariant verification.
fn get_admin_verify(files: Files, clock: Clock) : Result(VerifySummary, ShopApiError)
  db = try open_shop(files, clock)
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

test "ShopApi end-to-end via ApiTest.send: auth, X-Reason, invariants, orders, audit, and verify"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T03:00:00Z") or stop "t0"
  clock = Clock.fixed(t0)
  env = Env.of({
    "SHOP_ADMIN_TOKEN": "tok-admin",
    "SHOP_CLERK_TOKEN": "tok-clerk",
    "SHOP_AGENT_TOKEN": "tok-agent"
  })

  ## 1. Health triggers atomic v0 -> v1 -> v2 schema migration
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
    clock,
    env
  )
  assert oversold.status == 409

  ## 6. Ship order + verify secondary index queries (`?category=beans` and `/customers/1/orders`)
  ship = ApiTest.send(
    ShopApi,
    Api.post("/orders/1001/ship").with_bearer("tok-clerk").with_header("X-Reason", "packed-box"),
    files,
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

  beans = ApiTest.send(ShopApi, Api.get("/products?category=beans"), files, clock, env)
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

  cust_orders = ApiTest.send(ShopApi, Api.get("/customers/1/orders"), files, clock, env)
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
  ver = ApiTest.send(ShopApi, Api.get("/admin/verify"), files, clock, env)
  assert ver.status == 200
  assert Json.decode_strict[VerifySummary](ver.text) is Ok(vsum)
  assert vsum.ok and
    vsum.audit_entries == 5 and
    vsum.schema_version == 2 and
    vsum.invariants_checked == 3

  docs = ApiTest.send(ShopApi, Api.get("/docs"), files, clock, env)
  assert docs.status == 200 and docs.text.contains?("/openapi.json")
end
