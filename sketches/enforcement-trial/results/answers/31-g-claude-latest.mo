module Answer
expose latest
use Shop{Shop}

fn latest(shop: Shop, customer: Int, n: Int) : List(Int)
  shop.orders.of_customer(customer)
    .sort_by_desc(fn(o) (o.placed, o.id) end)
    .take(n.max(0))
    .map(fn(o) o.id end)
end
