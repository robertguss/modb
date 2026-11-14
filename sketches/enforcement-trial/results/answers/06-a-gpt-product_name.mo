module Answer
expose product_name
use Shop{Shop}

fn product_name(shop: Shop, product: Int) : Option(Text)
  case shop.products.get(product)
    Some(row): Some(row.name)
    None: None
  end
end
