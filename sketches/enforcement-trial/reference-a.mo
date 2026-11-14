module Reference
expose orders_of, product_name, large_orders, paid_total, open_count, bought, units_sold, latest, mentions,
  idle_customers, city_customers
use Shop{Shop, Status, walk}

fn orders_of(shop: Shop, customer: Int) : List(Int)
  shop.orders.values.filter(fn(order) order.customer == customer end).map(fn(order) order.id end).sort
end

fn product_name(shop: Shop, product: Int) : Option(Text)
  shop.products.get(product).map(fn(found) found.name end)
end

fn large_orders(shop: Shop, least: Int) : List(Int)
  shop.orders.values.filter(fn(order) order.total >= least end).map(fn(order) order.id end).sort
end

fn paid_total(shop: Shop, customer: Int) : Int
  shop.orders.values.filter(fn(order) order.customer == customer and order.status == Paid end).map(fn(order) order.total end).sum
end

fn open_count(shop: Shop) : Int
  shop.orders.values.count(fn(order) order.status == Open end)
end

fn bought(shop: Shop, customer: Int) : List(Text)
  var names = []
  for order in shop.orders.values.filter(fn(order) order.customer == customer end)
    for line in shop.lines.values.filter(fn(line) line.order == order.id end)
      names = names.concat(shop.products.get(line.product).map(fn(product) [product.name] end) or [])
    end
  end
  names.unique.sort
end

fn units_sold(shop: Shop, product: Int) : Int
  shop.lines.values.filter(fn(line) line.product == product end).map(fn(line) line.quantity end).sum
end

fn latest(shop: Shop, customer: Int, n: Int) : List(Int)
  shop.orders.values.filter(fn(order) order.customer == customer end).sort_by_desc(fn(order) (order.placed, order.id) end).take(n).map(fn(order) order.id end)
end

fn mentions(shop: Shop, word: Text) : List(Int)
  walk(shop.orders).values.filter(fn(order) order.note.contains?(word) end).map(fn(order) order.id end).sort
end

fn idle_customers(shop: Shop) : List(Int)
  walk(shop.customers).keys.filter(fn(id) not shop.orders.values.any?(fn(order) order.customer == id end) end).sort
end

fn city_customers(shop: Shop, city: Text) : List(Text)
  shop.customers.values.filter(fn(customer) customer.city == city end).map(fn(customer) customer.name end).sort
end
