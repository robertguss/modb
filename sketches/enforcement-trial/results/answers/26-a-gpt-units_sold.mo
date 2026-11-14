module Answer
expose units_sold
use Shop{Shop}

fn units_sold(shop: Shop, product: Int) : Int
  var total = 0
  lines = shop.lines.values.filter(fn(line) line.product == product end)
  for line in lines
    total = total + line.quantity
  end
  total
end
