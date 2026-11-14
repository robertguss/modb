module Answer
expose open_count
use Shop{Shop, Status}

fn open_count(shop: Shop) : Int
  var count = 0
  for _order in shop.orders.with_status(Open)
    count += 1
  end
  count
end
