module Answer
expose idle_customers
use Shop{Shop}

fn idle_customers(shop: Shop) : List(Int)
  var ids = []
  for customer in shop.customers.walk
    if shop.orders.of_customer(customer.id) == []
      ids = ids.append(customer.id)
    end
  end
  ids
end
