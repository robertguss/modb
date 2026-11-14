module Answer
expose paid_total
use Shop{Shop, Status}

fn paid_total(shop: Shop, customer: Int) : Int
  var sum = 0
  for order in shop.orders.values.filter(fn(order) order.customer == customer and order.status == Paid end)
    sum = sum + order.total
  end
  sum
end
