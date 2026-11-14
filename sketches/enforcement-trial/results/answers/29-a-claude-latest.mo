module Answer
expose latest
use Shop{Shop}

fn latest(shop: Shop, customer: Int, n: Int) : List(Int)
  shop.orders.values
    .filter(fn(order) order.customer == customer end)
    .sort_by_desc(fn(order) (order.placed, order.id) end)
    .take(if n < 0: 0 else: n)
    .map(fn(order) order.id end)
end
