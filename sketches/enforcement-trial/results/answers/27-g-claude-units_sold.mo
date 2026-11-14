module Answer
expose units_sold
use Shop{Shop}

fn units_sold(shop: Shop, product: Int) : Int
  var total = 0
  for line in shop.lines.of_product(product)
    total = total + line.quantity
  end
  total
end
