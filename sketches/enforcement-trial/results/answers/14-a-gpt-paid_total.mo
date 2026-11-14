module Answer
expose paid_total
use Shop{Shop, Status}

fn paid_total(shop: Shop, customer: Int) : Int
  orders = shop.orders.values.filter(fn(order) order.customer == customer end)
  var total = 0
  for order in orders
    if order.status == Paid
      total = total + order.total
    end
  end
  total
end
