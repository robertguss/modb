module Answer
expose large_orders
use Shop{Shop}

fn large_orders(shop: Shop, least: Int) : List(Int)
  shop.orders.total_at_least(least).map(fn(row) row.id end)
end
