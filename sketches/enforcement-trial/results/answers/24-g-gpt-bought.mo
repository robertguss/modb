module Answer
expose bought
use Shop{Shop}

fn bought(shop: Shop, customer: Int) : List(Text)
  var names = []
  for order in shop.orders.of_customer(customer)
    for line in shop.lines.of_order(order.id)
      case shop.products.get(line.product)
        Some(product): names = names.append(product.name)
        None: Unit
      end
    end
  end
  names.unique.sort
end
