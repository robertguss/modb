module Answer
expose open_count
use Shop{Shop, Status}

fn open_count(shop: Shop) : Int
  shop.orders.values.count(fn(order) order.status == Open end)
end
