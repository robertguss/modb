module Writes
expose rename_customer, move_customer, rename_product, price_product, note_order, status_order
use Shop{Shop, Status}

fn rename_customer(shop: Shop, customer: Int, value: Text) : Shop
  case shop.customers.get(customer)
    None: shop
    Some(row):
      var changed = row
      changed.name = value
      var result = shop
      result.customers = shop.customers.set(customer, changed)
      result
  end
end

fn move_customer(shop: Shop, customer: Int, value: Text) : Shop
  case shop.customers.get(customer)
    None: shop
    Some(row):
      var changed = row
      changed.city = value
      var result = shop
      result.customers = shop.customers.set(customer, changed)
      result
  end
end

fn rename_product(shop: Shop, product: Int, value: Text) : Shop
  case shop.products.get(product)
    None: shop
    Some(row):
      var changed = row
      changed.name = value
      var result = shop
      result.products = shop.products.set(product, changed)
      result
  end
end

fn price_product(shop: Shop, product: Int, value: Int) : Shop
  return shop if value < 0
  case shop.products.get(product)
    None: shop
    Some(row):
      var changed = row
      changed.price = value
      var result = shop
      result.products = shop.products.set(product, changed)
      result
  end
end

fn note_order(shop: Shop, order: Int, value: Text) : Shop
  case shop.orders.get(order)
    None: shop
    Some(row):
      var changed = row
      changed.note = value
      var result = shop
      result.orders = shop.orders.set(order, changed)
      result
  end
end

fn status_order(shop: Shop, order: Int, value: Status) : Shop
  case shop.orders.get(order)
    None: shop
    Some(row):
      var changed = row
      changed.status = value
      var result = shop
      result.orders = shop.orders.set(order, changed)
      result
  end
end
