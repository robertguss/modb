module Answer
expose orders_of
use Shop{Shop}

fn orders_of(shop: Shop, customer: Int) : List(Int)
  shop.orders.values.filter(fn(order) order.customer == customer end).map(fn(order) order.id end).sort
end
