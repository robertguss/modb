module Answer
expose bought
use Shop{Shop}

fn bought(shop: Shop, customer: Int) : List(Text)
  shop.orders.of_customer(customer)
    .flat_map(fn(order) shop.lines.of_order(order.id) end)
    .map(fn(line) line.product end)
    .unique
    .filter_map(fn(id) shop.products.get(id) end)
    .map(fn(product) product.name end)
    .unique
    .sort
end
