module Answer
expose large_orders
use Shop{Shop}

fn large_orders(shop: Shop, least: Int) : List(Int)
  shop.orders.values.filter(fn(order) order.total >= least end).map(fn(order) order.id end)
end
