module Writes
expose add_customer, add_product, place_order, move_customer, rename_product, note_order
use Shop{Shop, Customer, Product, Order, Status}

fn add_customer(shop: Shop, id: Int, name: Text, city: Text) : Shop
  return shop if shop.customers.has?(id)
  var changed = shop
  changed.customers = shop.customers.set(id, Customer(id: id, name: name, city: city))
  changed
end

fn add_product(shop: Shop, id: Int, name: Text, price: Int) : Shop
  return shop if shop.products.has?(id) or price < 0
  var changed = shop
  changed.products = shop.products.set(id, Product(id: id, name: name, price: price))
  changed
end

fn place_order(shop: Shop, id: Int, customer: Int, placed: Int) : Shop
  return shop if shop.orders.has?(id) or not shop.customers.has?(customer)
  var changed = shop
  changed.orders = shop.orders.set(id, Order(id: id, customer: customer, status: Open, total: 0, placed: placed, note: ""))
  changed
end

fn move_customer(shop: Shop, customer: Int, city: Text) : Shop
  case shop.customers.get(customer)
    None: shop
    Some(row):
      var updated = row
      updated.city = city
      var changed = shop
      changed.customers = shop.customers.set(customer, updated)
      changed
  end
end

fn rename_product(shop: Shop, product: Int, name: Text) : Shop
  case shop.products.get(product)
    None: shop
    Some(row):
      var updated = row
      updated.name = name
      var changed = shop
      changed.products = shop.products.set(product, updated)
      changed
  end
end

fn note_order(shop: Shop, order: Int, note: Text) : Shop
  case shop.orders.get(order)
    None: shop
    Some(row):
      var updated = row
      updated.note = note
      var changed = shop
      changed.orders = shop.orders.set(order, updated)
      changed
  end
end

