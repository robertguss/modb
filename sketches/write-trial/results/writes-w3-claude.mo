module Writes
expose add_customer,
move_customer,
add_product,
set_price,
place_order,
add_line,
remove_line,
set_status,
set_note
use Shop{Shop, Customer, Product, Order, Line, Status}

fn add_customer(shop: Shop, id: Int, name: Text, city: Text) : Shop
  if shop.customers.has?(id)
    shop
  else
    with_customers(shop, shop.customers.set(id, Customer(id: id, name: name, city: city)))
  end
end

fn move_customer(shop: Shop, customer: Int, city: Text) : Shop
  case shop.customers.get(customer)
    Some(found): with_customers(
      shop,
      shop.customers.set(customer, Customer(id: found.id, name: found.name, city: city))
    )
    None: shop
  end
end

fn add_product(shop: Shop, id: Int, name: Text, price: Int) : Shop
  if shop.products.has?(id) or price < 0
    shop
  else
    with_products(shop, shop.products.set(id, Product(id: id, name: name, price: price)))
  end
end

fn set_price(shop: Shop, product: Int, price: Int) : Shop
  case shop.products.get(product)
    Some(found):
      if price < 0
        shop
      else
        with_products(
          shop,
          shop.products.set(product, Product(id: found.id, name: found.name, price: price))
        )
      end
    None: shop
  end
end

fn place_order(shop: Shop, id: Int, customer: Int, placed: Int) : Shop
  if shop.orders.has?(id) or not shop.customers.has?(customer)
    shop
  else
    with_orders(
      shop,
      shop.orders.set(
        id,
        Order(id: id, customer: customer, status: Open, total: 0, placed: placed, note: "")
      )
    )
  end
end

fn add_line(shop: Shop, id: Int, order: Int, product: Int, quantity: Int) : Shop
  case (shop.orders.get(order), shop.products.get(product))
    (Some(found), Some(item)):
      if shop.lines.has?(id) or quantity <= 0 or found.status != Open
        shop
      else
        Shop(
          customers: shop.customers,
          products: shop.products,
          orders: shop.orders.set(order, with_total(found, found.total + item.price * quantity)),
          lines: shop.lines.set(
            id,
            Line(id: id, order: order, product: product, quantity: quantity)
          )
        )
      end
    _: shop
  end
end

fn remove_line(shop: Shop, line: Int) : Shop
  case shop.lines.get(line)
    Some(row):
      case (shop.orders.get(row.order), shop.products.get(row.product))
        (Some(found), Some(item)):
          if found.status != Open
            shop
          else
            Shop(
              customers: shop.customers,
              products: shop.products,
              orders: shop.orders.set(
                found.id,
                with_total(found, found.total - item.price * row.quantity)
              ),
              lines: shop.lines.remove(line)
            )
          end
        _: shop
      end
    None: shop
  end
end

fn set_status(shop: Shop, order: Int, status: Status) : Shop
  case shop.orders.get(order)
    Some(found): with_orders(
      shop,
      shop.orders.set(
        order,
        Order(
          id: found.id,
          customer: found.customer,
          status: status,
          total: found.total,
          placed: found.placed,
          note: found.note
        )
      )
    )
    None: shop
  end
end

fn set_note(shop: Shop, order: Int, note: Text) : Shop
  case shop.orders.get(order)
    Some(found): with_orders(
      shop,
      shop.orders.set(
        order,
        Order(
          id: found.id,
          customer: found.customer,
          status: found.status,
          total: found.total,
          placed: found.placed,
          note: note
        )
      )
    )
    None: shop
  end
end

fn with_total(order: Order, total: Int) : Order
  Order(
    id: order.id,
    customer: order.customer,
    status: order.status,
    total: total,
    placed: order.placed,
    note: order.note
  )
end

fn with_customers(shop: Shop, customers: Map(Int, Customer)) : Shop
  Shop(customers: customers, products: shop.products, orders: shop.orders, lines: shop.lines)
end

fn with_products(shop: Shop, products: Map(Int, Product)) : Shop
  Shop(customers: shop.customers, products: products, orders: shop.orders, lines: shop.lines)
end

fn with_orders(shop: Shop, orders: Map(Int, Order)) : Shop
  Shop(customers: shop.customers, products: shop.products, orders: orders, lines: shop.lines)
end
