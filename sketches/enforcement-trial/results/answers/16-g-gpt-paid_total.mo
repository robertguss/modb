module Answer
expose paid_total
use Shop{Shop, Status}

fn paid_total(shop: Shop, customer: Int) : Int
  var total = 0
  for order in shop.orders.of_customer(customer)
    if order.status == Paid
      total = total + order.total
    end
  end
  total
end
