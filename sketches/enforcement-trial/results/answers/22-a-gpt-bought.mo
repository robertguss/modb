module Answer
expose bought
use Shop{Shop}

fn bought(shop: Shop, customer: Int) : List(Text)
  var names = []
  orders = shop.orders.values.filter(fn(order) order.customer == customer end)
  for order in orders
    lines = shop.lines.values.filter(fn(line) line.order == order.id end)
    for line in lines
      if shop.products.get(line.product) is Some(product)
        names = names.append(product.name)
      end
    end
  end
  names.unique.sort
end
