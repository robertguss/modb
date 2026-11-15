module Checks
use Shop{Customer, Product, Order, Line, Status}
use Writes

test "add_customer adds one customer and refuses a taken id"
  shop = Writes.add_customer(Shop.sample, 4, "Dee", "Faro")
  assert shop.customers.size == 4
  assert shop.customers.get(4) == Some(Customer(id: 4, name: "Dee", city: "Faro"))
  assert Writes.add_customer(Shop.sample, 1, "Dee", "Faro") == Shop.sample
end

test "move_customer changes only the city"
  shop = Writes.move_customer(Shop.sample, 2, "Faro")
  assert shop.customers.get(2) == Some(Customer(id: 2, name: "Ben", city: "Faro"))
  assert shop.customers.size == 3
  assert Writes.move_customer(Shop.sample, 9, "Faro") == Shop.sample
end

test "add_product adds one product and refuses a taken id or a negative price"
  shop = Writes.add_product(Shop.sample, 5, "nib", 3)
  assert shop.products.get(5) == Some(Product(id: 5, name: "nib", price: 3))
  assert shop.products.size == 5
  assert Writes.add_product(Shop.sample, 1, "nib", 3) == Shop.sample
  assert Writes.add_product(Shop.sample, 5, "nib", -1) == Shop.sample
end

test "set_price changes the price and leaves order totals alone"
  shop = Writes.set_price(Shop.sample, 2, 6)
  assert shop.products.get(2) == Some(Product(id: 2, name: "ink", price: 6))
  assert shop.orders == Shop.sample.orders
  assert Writes.set_price(Shop.sample, 9, 6) == Shop.sample
  assert Writes.set_price(Shop.sample, 2, -1) == Shop.sample
end

test "place_order adds an empty open order for an existing customer"
  shop = Writes.place_order(Shop.sample, 7, 3, 6)
  assert shop.orders.get(7) ==
    Some(Order(id: 7, customer: 3, status: Open, total: 0, placed: 6, note: ""))
  assert shop.orders.size == 7
  assert Writes.place_order(Shop.sample, 1, 3, 6) == Shop.sample
  assert Writes.place_order(Shop.sample, 7, 9, 6) == Shop.sample
end

test "add_line adds a line to an open order and raises its total"
  shop = Writes.add_line(Shop.sample, 9, 2, 3, 2)
  assert shop.lines.get(9) == Some(Line(id: 9, order: 2, product: 3, quantity: 2))
  assert shop.lines.size == 9
  assert shop.orders.get(2) ==
    Some(Order(id: 2, customer: 2, status: Open, total: 13, placed: 4, note: ""))
  assert Writes.add_line(Shop.sample, 1, 2, 3, 2) == Shop.sample
  assert Writes.add_line(Shop.sample, 9, 1, 3, 2) == Shop.sample
  assert Writes.add_line(Shop.sample, 9, 8, 3, 2) == Shop.sample
  assert Writes.add_line(Shop.sample, 9, 2, 8, 2) == Shop.sample
  assert Writes.add_line(Shop.sample, 9, 2, 3, 0) == Shop.sample
end

test "remove_line takes a line off an open order and lowers its total"
  shop = Writes.remove_line(Shop.sample, 4)
  assert not shop.lines.has?(4)
  assert shop.lines.size == 7
  assert shop.orders.get(3) ==
    Some(Order(id: 3, customer: 1, status: Open, total: 0, placed: 5, note: "call first"))
  assert Writes.remove_line(Shop.sample, 1) == Shop.sample
  assert Writes.remove_line(Shop.sample, 99) == Shop.sample
  assert Writes.remove_line(Writes.add_line(Shop.sample, 9, 2, 3, 2), 9) == Shop.sample
end

test "set_status changes only the status"
  shop = Writes.set_status(Shop.sample, 2, Paid)
  assert shop.orders.get(2) ==
    Some(Order(id: 2, customer: 2, status: Paid, total: 5, placed: 4, note: ""))
  assert shop.lines == Shop.sample.lines
  assert Writes.set_status(Shop.sample, 9, Paid) == Shop.sample
end

test "set_note changes only the note"
  shop = Writes.set_note(Shop.sample, 2, "ring twice")
  assert shop.orders.get(2) ==
    Some(Order(id: 2, customer: 2, status: Open, total: 5, placed: 4, note: "ring twice"))
  assert Writes.set_note(Shop.sample, 9, "ring twice") == Shop.sample
end
