module Answer
expose idle_customers
use Shop{Shop}

fn idle_customers(shop: Shop) : List(Int)
  shop.customers.walk.filter(fn(c) shop.orders.of_customer(c.id).size == 0 end).map(fn(c) c.id end)
end
