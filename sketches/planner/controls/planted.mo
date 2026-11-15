module Planted
expose largest, doubled, gifts, spend_by_city, product_buyers, revenue, unlined, busiest
use Shop{Shop, walk}

fn largest(shop: Shop, customer: Int) : Int
  var best = 0
  for order in shop.orders.values.filter(fn(order) order.customer == customer end)
    best = best.max(order.total)
  end
  best
end

fn doubled(shop: Shop, customer: Int) : Int
  var total = 0
  for order in shop.orders.values.filter(fn(order) order.customer == customer end)
    total = total + total + order.total
  end
  total
end

fn gifts(shop: Shop, customer: Int) : List(Int)
  shop.orders.values.filter(fn(order) order.customer == customer and order.note.contains?("gift") end)
    .map(fn(order) order.id end).sort
end

fn spend_by_city(shop: Shop, city: Text) : Int
  var total = 0
  for customer in shop.customers.values.filter(fn(customer) customer.city == city end)
    for order in shop.orders.values.filter(fn(order) order.customer == customer.id end)
      total = total + order.total
    end
  end
  total
end

fn product_buyers(shop: Shop, product: Int) : List(Text)
  var names = []
  for line in shop.lines.values.filter(fn(line) line.product == product end)
    if shop.orders.get(line.order) is Some(order)
      if shop.customers.get(order.customer) is Some(customer)
        names = names.append(customer.name)
      end
    end
  end
  names.unique.sort
end

fn revenue(shop: Shop, product: Int) : Int
  var total = 0
  for line in shop.lines.values.filter(fn(line) line.product == product end)
    if shop.products.get(line.product) is Some(found)
      total = total + line.quantity * found.price
    end
  end
  total
end

fn unlined(shop: Shop) : List(Int)
  var ids = []
  for order in walk(shop.orders).values
    if not shop.lines.values.any?(fn(line) line.order == order.id end)
      ids = ids.append(order.id)
    end
  end
  ids.sort
end

fn busiest(shop: Shop) : Int
  var best = 0
  var most = 0
  for customer in walk(shop.customers).values
    count = shop.orders.values.count(fn(order) order.customer == customer.id end)
    if count > most
      most = count
      best = customer.id
    end
  end
  best
end
