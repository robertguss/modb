module Answer
expose paid_total
use Shop{Shop}

fn paid_total(shop: Shop, customer: Int) : Int
  shop.orders.of_customer(customer).filter(fn(row) row.status == Shop.Paid end).map(fn(row) row.total end).sum
end
