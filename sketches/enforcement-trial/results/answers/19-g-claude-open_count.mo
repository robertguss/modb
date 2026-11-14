module Answer
expose open_count
use Shop{Shop}

fn open_count(shop: Shop) : Int
  shop.orders.with_status(Shop.Open).size
end
