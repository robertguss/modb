module Answer
expose bought
use Shop{Shop}

fn bought(shop: Shop, customer: Int) : List(Text)
  var names = []
  for order in shop.orders.values.filter(fn(o) o.customer == customer end)
    for line in shop.lines.values.filter(fn(l) l.order == order.id end)
      case shop.products.get(line.product)
        Some(product):
          if not names.contains?(product.name)
            names = names.append(product.name)
          end
        None: names = names
      end
    end
  end
  names.sort
end
