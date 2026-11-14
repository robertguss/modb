module Reference
expose orders_of, product_name, large_orders, paid_total, open_count, bought, units_sold, latest, mentions,
  idle_customers, city_customers
use Shop{Shop, Status}

fn orders_of(shop: Shop, customer: Int) : List(Int)
  shop.orders.of_customer(customer).map(fn(order) order.id end).sort
end

fn product_name(shop: Shop, product: Int) : Option(Text)
  shop.products.get(product).map(fn(found) found.name end)
end

fn large_orders(shop: Shop, least: Int) : List(Int)
  shop.orders.total_at_least(least).map(fn(order) order.id end).sort
end

fn paid_total(shop: Shop, customer: Int) : Int
  shop.orders.of_customer(customer).filter(fn(order) order.status == Paid end).map(fn(order) order.total end).sum
end

fn open_count(shop: Shop) : Int
  shop.orders.with_status(Open).size
end

fn bought(shop: Shop, customer: Int) : List(Text)
  var names = []
  for order in shop.orders.of_customer(customer)
    for line in shop.lines.of_order(order.id)
      names = names.concat(shop.products.get(line.product).map(fn(product) [product.name] end) or [])
    end
  end
  names.unique.sort
end

fn units_sold(shop: Shop, product: Int) : Int
  shop.lines.of_product(product).map(fn(line) line.quantity end).sum
end

fn latest(shop: Shop, customer: Int, n: Int) : List(Int)
  shop.orders.of_customer(customer).sort_by_desc(fn(order) (order.placed, order.id) end).take(n).map(fn(order) order.id end)
end

fn mentions(shop: Shop, word: Text) : List(Int)
  shop.orders.walk.filter(fn(order) order.note.contains?(word) end).map(fn(order) order.id end).sort
end

fn idle_customers(shop: Shop) : List(Int)
  shop.customers.walk.filter(fn(customer) shop.orders.of_customer(customer.id).empty? end).map(fn(customer) customer.id end).sort
end

fn city_customers(shop: Shop, city: Text) : List(Text)
  shop.customers.in_city(city).map(fn(customer) customer.name end).sort
end
