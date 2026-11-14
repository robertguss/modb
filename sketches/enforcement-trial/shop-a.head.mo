module Shop
expose Shop(..), Customer(..), Product(..), Order(..), Line(..), Status(..), walk, sample, large

struct Shop
  customers: Map(Int, Customer)
  products: Map(Int, Product)
  orders: Map(Int, Order)
  lines: Map(Int, Line)
end

fn walk(table: Map(Int, R)) : Map(Int, R)
  table
end

fn shop_of(
  customers: List(Customer),
  products: List(Product),
  orders: List(Order),
  lines: List(Line)
) : Shop
  Shop(
    customers: customers_by_id(customers),
    products: products_by_id(products),
    orders: orders_by_id(orders),
    lines: lines_by_id(lines)
  )
end
