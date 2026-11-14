module Answer
expose product_name
use Shop{Shop}

fn product_name(shop: Shop, product: Int) : Option(Text)
  shop.products.get(product).map(fn(row) row.name end)
end
