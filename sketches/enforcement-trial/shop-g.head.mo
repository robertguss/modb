module Shop
expose Shop(..), Customer(..), Product(..), Order(..), Line(..), Status(..), Table, get, walk, in_city,
  of_customer, with_status, total_at_least, placed_between, of_order, of_product, sample, large

struct Table(R)
  rows: Map(Int, R)
end

struct Shop
  customers: Table(Customer)
  products: Table(Product)
  orders: Table(Order)
  lines: Table(Line)
end

fn get(table: Table(R), id: Int) : Option(R)
  table.rows.get(id)
end

fn walk(table: Table(R)) : List(R)
  table.rows.values
end

fn in_city(customers: Table(Customer), city: Text) : List(Customer)
  customers.rows.values.filter(fn(row) row.city == city end)
end

fn of_customer(orders: Table(Order), customer: Int) : List(Order)
  orders.rows.values.filter(fn(row) row.customer == customer end)
end

fn with_status(orders: Table(Order), status: Status) : List(Order)
  orders.rows.values.filter(fn(row) row.status == status end)
end

fn total_at_least(orders: Table(Order), least: Int) : List(Order)
  orders.rows.values.filter(fn(row) row.total >= least end)
end

fn placed_between(orders: Table(Order), first: Int, last: Int) : List(Order)
  orders.rows.values.filter(fn(row) row.placed >= first and row.placed <= last end)
end

fn of_order(lines: Table(Line), order: Int) : List(Line)
  lines.rows.values.filter(fn(row) row.order == order end)
end

fn of_product(lines: Table(Line), product: Int) : List(Line)
  lines.rows.values.filter(fn(row) row.product == product end)
end

fn shop_of(
  customers: List(Customer),
  products: List(Product),
  orders: List(Order),
  lines: List(Line)
) : Shop
  Shop(
    customers: Table(rows: customers_by_id(customers)),
    products: Table(rows: products_by_id(products)),
    orders: Table(rows: orders_by_id(orders)),
    lines: Table(rows: lines_by_id(lines))
  )
end
