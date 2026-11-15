module Writes
expose add_customer, move_customer, add_product, set_price, place_order, add_line, remove_line, set_status, set_note
use Shop{Shop, Customer, Product, Order, Line, Status}

fn with_order(shop: Shop, row: Order) : Shop
  Shop(
    customers: shop.customers,
    products: shop.products,
    orders: shop.orders.set(row.id, row),
    lines: shop.lines
  )
end

fn with_total(row: Order, total: Int) : Order
  Order(id: row.id, customer: row.customer, status: row.status, total: total, placed: row.placed, note: row.note)
end

fn add_customer(shop: Shop, id: Int, name: Text, city: Text) : Shop
  return shop if shop.customers.has?(id)
  Shop(
    customers: shop.customers.set(id, Customer(id: id, name: name, city: city)),
    products: shop.products,
    orders: shop.orders,
    lines: shop.lines
  )
end

fn move_customer(shop: Shop, customer: Int, city: Text) : Shop
  case shop.customers.get(customer)
    None: shop
    Some(row): Shop(
      customers: shop.customers.set(customer, Customer(id: row.id, name: row.name, city: city)),
      products: shop.products,
      orders: shop.orders,
      lines: shop.lines
    )
  end
end

fn add_product(shop: Shop, id: Int, name: Text, price: Int) : Shop
  return shop if shop.products.has?(id) or price < 0
  Shop(
    customers: shop.customers,
    products: shop.products.set(id, Product(id: id, name: name, price: price)),
    orders: shop.orders,
    lines: shop.lines
  )
end

fn set_price(shop: Shop, product: Int, price: Int) : Shop
  return shop if price < 0
  case shop.products.get(product)
    None: shop
    Some(row): Shop(
      customers: shop.customers,
      products: shop.products.set(product, Product(id: row.id, name: row.name, price: price)),
      orders: shop.orders,
      lines: shop.lines
    )
  end
end

fn place_order(shop: Shop, id: Int, customer: Int, placed: Int) : Shop
  return shop if shop.orders.has?(id) or not shop.customers.has?(customer)
  with_order(shop, Order(id: id, customer: customer, status: Open, total: 0, placed: placed, note: ""))
end

fn add_line(shop: Shop, id: Int, order: Int, product: Int, quantity: Int) : Shop
  return shop if shop.lines.has?(id) or quantity < 1
  case (shop.orders.get(order), shop.products.get(product))
    (Some(row), Some(item)) if row.status == Open: Shop(
      customers: shop.customers,
      products: shop.products,
      orders: shop.orders.set(order, with_total(row, row.total + item.price * quantity)),
      lines: shop.lines.set(id, Line(id: id, order: order, product: product, quantity: quantity))
    )
    _: shop
  end
end

fn remove_line(shop: Shop, line: Int) : Shop
  case shop.lines.get(line)
    None: shop
    Some(gone): case (shop.orders.get(gone.order), shop.products.get(gone.product))
      (Some(row), Some(item)) if row.status == Open: Shop(
        customers: shop.customers,
        products: shop.products,
        orders: shop.orders.set(row.id, with_total(row, row.total - item.price * gone.quantity)),
        lines: shop.lines.remove(line)
      )
      _: shop
    end
  end
end

fn set_status(shop: Shop, order: Int, status: Status) : Shop
  case shop.orders.get(order)
    None: shop
    Some(row): with_order(
      shop,
      Order(id: row.id, customer: row.customer, status: status, total: row.total, placed: row.placed, note: row.note)
    )
  end
end

fn set_note(shop: Shop, order: Int, note: Text) : Shop
  case shop.orders.get(order)
    None: shop
    Some(row): with_order(
      shop,
      Order(id: row.id, customer: row.customer, status: row.status, total: row.total, placed: row.placed, note: note)
    )
  end
end
