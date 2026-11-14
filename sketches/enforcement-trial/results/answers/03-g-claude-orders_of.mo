module Answer
expose orders_of
use Shop{Shop}

fn orders_of(shop: Shop, customer: Int) : List(Int)
  shop.orders.of_customer(customer).map(fn(order) order.id end)
end
