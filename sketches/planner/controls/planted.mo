module Planted
expose largest, doubled, gifts
use Shop{Shop}

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
