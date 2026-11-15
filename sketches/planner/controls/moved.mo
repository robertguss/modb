module Moved
expose move_order
use Shop{Shop, Order}

fn move_order(shop: Shop, order: Int, customer: Int) : Shop
  case shop.orders.get(order)
    Some(found):
      moved = Order(id: found.id, customer: customer, status: found.status, total: found.total, placed: found.placed, note: found.note)
      Shop(customers: shop.customers, products: shop.products, orders: shop.orders.set(order, moved), lines: shop.lines)
    None: shop
  end
end
