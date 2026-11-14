module Answer
expose latest
use Shop{Shop}

fn latest(shop: Shop, customer: Int, n: Int) : List(Int)
  orders = shop.orders.values.filter(fn(order) order.customer == customer end)
  orders.sort_by_desc(fn(order) (order.placed, order.id) end).take(n.max(0)).map(fn(order) order.id end)
end
