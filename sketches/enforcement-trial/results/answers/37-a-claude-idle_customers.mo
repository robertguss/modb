module Answer
expose idle_customers
use Shop{Shop, walk}

fn idle_customers(shop: Shop) : List(Int)
  var ids = []
  for customer in walk(shop.customers).values
    if not shop.orders.values.any?(fn(order) order.customer == customer.id end)
      ids = ids.append(customer.id)
    end
  end
  ids
end
