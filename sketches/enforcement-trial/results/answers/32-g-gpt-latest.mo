module Answer
expose latest
use Shop{Shop}

fn latest(shop: Shop, customer: Int, n: Int) : List(Int)
  if n <= 0
    []
  else
    shop.orders.of_customer(customer)
      .sort_by_desc(fn(row) row.id end)
      .sort_by_desc(fn(row) row.placed end)
      .take(n)
      .map(fn(row) row.id end)
  end
end
