## Small Coffee Roastery store built on `Modb` + `Modb.Table` — demonstrating typed Mo records,
## exact `Decimal` money, unique & non-unique secondary indexes, atomic stock-checked transactions,
## O(1) point-in-time snapshots, and crash-safe disk persistence with zero SQL strings.
module Shop
use Modb{Store}
use Modb.Table{TableError}

enum Tier
  Standard
  Member
end

struct Customer
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

enum ShopError
  Db(TableError)
  EmailTaken(email: Text)
  UnknownCustomer(id: Int)
  UnknownProduct(sku: Text)
  InvalidQuantity(quantity: Int)
  InsufficientStock(sku: Text, requested: Int, available: Int)
end

fn to_text(err: ShopError) : Text
  case err
    Db(e): "database error: #{e.to_text}"
    EmailTaken(email: e): "email already registered: #{e}"
    UnknownCustomer(id: id): "unknown customer ##{id}"
    UnknownProduct(sku: s): "unknown product '#{s}'"
    InvalidQuantity(quantity: q): "invalid order quantity #{q} (must be > 0)"
    InsufficientStock(sku: s, requested: req, available: avail): "insufficient stock for '#{s}': requested #{req}, available #{avail}"
  end
end

## Schema: typed tables and secondary indexes declared in plain Mo.
customers_by_email = Table.unique_text_index[Int, Customer]("customers_by_email", fn(c) c.email end)

customers = Table.int_key[Customer]("customers").with_index(customers_by_email)

products_by_category = Table.text_index[Text, Product]("products_by_category", fn(p) p.category end)

products = Table.text_key[Product]("products").with_index(products_by_category)

orders_by_buyer = Table.int_index[Int, Order]("orders_by_buyer", fn(o) o.buyer_id end)

orders = Table.int_key[Order]("orders").with_index(orders_by_buyer)

## Registers a customer, translating a unique-email conflict into a domain `EmailTaken` error.
fn register_customer(db: Store, id: Int, customer: Customer) : Result(Store, ShopError)
  case Table.write_tx(db, fn(tx) Table.put(tx, customers, id, customer) end)
    Ok(next_db): Ok(next_db)
    Error(Table.UniqueConflict(index: _, value: email)): Error(EmailTaken(email: email))
    Error(other): Error(Db(other))
  end
end

## Upserts a product in the catalog.
fn save_product(db: Store, sku: Text, product: Product) : Result(Store, ShopError)
  Ok(try Table.write_tx(db, fn(tx) Table.put(tx, products, sku, product) end))
end

## Places an order atomically:
## 1. Verifies buyer and product exist inside the write transaction.
## 2. Enforces `quantity > 0` and `product.stock >= quantity` (rolling back cleanly on failure).
## 3. Applies a 10% `Member` discount in exact `Decimal` arithmetic, decrements stock,
##    and writes both the updated `Product` and indexed `Order` in one durable commit.
fn place_order(db: Store, order_id: Int, buyer_id: Int, sku: Text, quantity: Int) : Result(
  (Store, Order),
  ShopError
)
  return Error(InvalidQuantity(quantity: quantity)) if quantity <= 0

  Table.transact(
    db,
    fn(e) Db(e) end,
    fn(tx)
      buyer_opt = try Table.tx_get(tx, customers, buyer_id)
      buyer = try buyer_opt.or_fail(UnknownCustomer(id: buyer_id))

      prod_opt = try Table.tx_get(tx, products, sku)
      prod = try prod_opt.or_fail(UnknownProduct(sku: sku))

      if prod.stock < quantity
        return Error(InsufficientStock(sku: sku, requested: quantity, available: prod.stock))
      end

      subtotal = prod.price * quantity.to_decimal
      total = case buyer.tier
        Standard: subtotal.round(2)
        Member: (subtotal * 0.90).round(2)
      end

      var updated_prod = prod
      updated_prod.stock -= quantity
      order = Order(buyer_id: buyer_id, sku: sku, quantity: quantity, total: total, status: Placed)

      var cur = tx
      cur = try Table.put(cur, products, sku, updated_prod)
      cur = try Table.put(cur, orders, order_id, order)
      Ok((cur, order))
    end
  )
end

## Marks an existing order as shipped.
fn mark_shipped(db: Store, order_id: Int) : Result(Store, ShopError)
  Ok(
    try Table.write_tx(
      db,
      fn(tx)
        case try Table.tx_get(tx, orders, order_id)
          None: Ok(tx)
          Some(ord):
            var shipped = ord
            shipped.status = Shipped
            Table.put(tx, orders, order_id, shipped)
        end
      end
    )
  )
end

## Looks up a customer by unique email, then returns all of their orders in order-ID sequence.
fn orders_for_email(db: Store, email: Text) : Result(List((Int, Order)), ShopError)
  case try Table.lookup_unique(db, customers, customers_by_email, email)
    None: Ok([])
    Some((buyer_id, _customer)): Ok(try Table.lookup(db, orders, orders_by_buyer, buyer_id))
  end
end

fn run_demo(files: Files, path: Text) : Result(List(Text), ShopError)
  var log = []
  var db = try Modb.open(files, path).map_error(fn(e) Db(Table.Storage(e)) end)

  db = try register_customer(
    db,
    1,
    Customer(email: "ada@lovelace.org", name: "Ada Lovelace", tier: Member)
  )
  db = try register_customer(
    db,
    2,
    Customer(email: "grace@hopper.org", name: "Grace Hopper", tier: Standard)
  )

  ## Duplicate email is rejected cleanly
  case register_customer(
    db,
    3,
    Customer(email: "ada@lovelace.org", name: "Impostor", tier: Standard)
  )
    Ok(_): stop "duplicate email must be rejected"
    Error(e): log = log.append("rejected duplicate signup -> #{e.to_text}")
  end

  db = try save_product(
    db,
    "beans-ethiopia",
    Product(title: "Yirgacheffe Whole Bean (250g)", category: "beans", price: 18.50, stock: 10)
  )
  db = try save_product(
    db,
    "brewer-v60",
    Product(title: "Ceramic Pour-Over Dripper", category: "gear", price: 26.00, stock: 3)
  )

  ## Pin an O(1) snapshot of pre-rush inventory before orders start arriving
  (db_pinned, morning_snap) = Modb.snapshot(db)
  db = db_pinned

  (db1, ord1) = try place_order(db, 1001, 1, "beans-ethiopia", 2)
  db = db1
  log = log.append(
    "placed order #1001 for Ada (Member 10% off): #{ord1.quantity}x #{ord1.sku} = $#{ord1.total
      .to_fixed(2)}"
  )

  (db2, ord2) = try place_order(db, 1002, 1, "brewer-v60", 1)
  db = db2
  log = log.append(
    "placed order #1002 for Ada (Member 10% off): #{ord2.quantity}x #{ord2.sku} = $#{ord2.total
      .to_fixed(2)}"
  )

  (db3, ord3) = try place_order(db, 1003, 2, "brewer-v60", 1)
  db = db3
  log = log.append(
    "placed order #1003 for Grace (Standard): #{ord3.quantity}x #{ord3.sku} = $#{ord3.total.to_fixed(
      2
    )}"
  )

  ## Oversized order for 5 drippers (only 1 left) fails and rolls back cleanly
  case place_order(db, 1004, 2, "brewer-v60", 5)
    Ok(_): stop "oversold order must fail"
    Error(e): log = log.append("aborted order #1004 -> #{e.to_text}")
  end

  db = try mark_shipped(db, 1001)

  ## Compare live stock vs morning snapshot
  live_beans = (try Table.get(db, products, "beans-ethiopia")) or stop "beans exist"
  snap_beans = (try Table.snapshot_get(db, morning_snap, products, "beans-ethiopia")) or
    stop "beans in snapshot"
  snap_ada_orders = try Table.snapshot_lookup(db, morning_snap, orders, orders_by_buyer, 1)
  log = log.append(
    "beans stock: morning snapshot=#{snap_beans.stock} (Ada orders then=#{snap_ada_orders.size}), live=#{live_beans
      .stock}"
  )

  db = try Modb.release_snapshot(db, morning_snap).map_error(fn(e) Db(Table.Storage(e)) end)

  ## Reopen from disk to prove full durability across tables and secondary indexes
  reopened = try Modb.open(files, path).map_error(fn(e) Db(Table.Storage(e)) end)
  ada_orders = try orders_for_email(reopened, "ada@lovelace.org")
  log = log.append("reopened '#{path}': Ada has #{ada_orders.size} durable orders")
  rep = try Modb.verify(reopened).map_error(fn(e) Db(Table.Storage(e)) end)
  log = log.append(
    "verified B+Tree store: txid=#{rep.txid}, buckets=#{rep.bucket_count}, pages=#{rep.page_count}"
  )
  Ok(log)
end

fn main(console: Console, files: Files) : Result(Unit, Text)
  lines = try run_demo(files, "shop.modb").map_error(fn(e) e.to_text end)
  for line in lines
    console.print(line)
  end
  Ok(Unit)
end

test "Shop end-to-end: unique email, atomic stock invariant, snapshot isolation and durability"
  files = Files.in_memory({})
  assert run_demo(files, "test-shop.modb") is Ok(lines)
  assert lines.take(6) == [
    "rejected duplicate signup -> email already registered: ada@lovelace.org",
    "placed order #1001 for Ada (Member 10% off): 2x beans-ethiopia = $33.30",
    "placed order #1002 for Ada (Member 10% off): 1x brewer-v60 = $23.40",
    "placed order #1003 for Grace (Standard): 1x brewer-v60 = $26.00",
    "aborted order #1004 -> insufficient stock for 'brewer-v60': requested 5, available 1",
    "beans stock: morning snapshot=10 (Ada orders then=0), live=8"
  ]
  assert lines.size == 8

  ## Inspect exact persisted records after reopen
  assert Modb.open(files, "test-shop.modb") is Ok(db)
  assert orders_for_email(db, "ada@lovelace.org") ==
    Ok([
      (1001, Order(buyer_id: 1, sku: "beans-ethiopia", quantity: 2, total: 33.30, status: Shipped)),
      (1002, Order(buyer_id: 1, sku: "brewer-v60", quantity: 1, total: 23.40, status: Placed))
    ])
  assert orders_for_email(db, "grace@hopper.org") ==
    Ok([(1003, Order(buyer_id: 2, sku: "brewer-v60", quantity: 1, total: 26.00, status: Placed))])
  assert Table.lookup(db, products, products_by_category, "gear") ==
    Ok([
      (
        "brewer-v60",
        Product(title: "Ceramic Pour-Over Dripper", category: "gear", price: 26.00, stock: 1)
      )
    ])
  assert Modb.verify(db) is Ok(_)
end
