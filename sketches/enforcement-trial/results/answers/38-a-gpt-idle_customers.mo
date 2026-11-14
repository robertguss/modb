module Answer
expose idle_customers
use Shop{Shop, walk}

fn idle_customers(shop: Shop) : List(Int)
  var ids = []
  for customer in walk(shop.customers).values
    id = customer.id
    if not shop.orders.values.any?(fn(order) order.customer == id end)
      ids = ids.append(id)
    end
  end
  ids
end
