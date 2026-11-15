module Checks
use Shop{sample, Customer, Product, Order, Status}
use Writes{add_customer, add_product, place_order, move_customer, rename_product, note_order}

test "add_customer changes its row and rejects unavailable changes"
  changed = add_customer(sample, 9, "Dee", "Faro")
  assert changed.customers.get(9) == Some(Customer(id: 9, name: "Dee", city: "Faro"))
  assert add_customer(sample, 1, "Dee", "Faro") == sample
end

test "add_product changes its row and rejects unavailable changes"
  changed = add_product(sample, 9, "book", 7)
  assert changed.products.get(9) == Some(Product(id: 9, name: "book", price: 7))
  assert add_product(sample, 1, "book", 7) == sample
end

test "place_order changes its row and rejects unavailable changes"
  changed = place_order(sample, 9, 1, 8)
  assert changed.orders.get(9) == Some(Order(id: 9, customer: 1, status: Open, total: 0, placed: 8, note: ""))
  assert place_order(sample, 9, 999, 8) == sample
end

test "move_customer changes its row and rejects unavailable changes"
  changed = move_customer(sample, 1, "Faro")
  assert changed.customers.get(1) == Some(Customer(id: 1, name: "Ada", city: "Faro"))
  assert move_customer(sample, 999, "Faro") == sample
end

test "rename_product changes its row and rejects unavailable changes"
  changed = rename_product(sample, 1, "pencil")
  assert changed.products.get(1) == Some(Product(id: 1, name: "pencil", price: 2))
  assert rename_product(sample, 999, "pencil") == sample
end

test "note_order changes its row and rejects unavailable changes"
  changed = note_order(sample, 2, "rush")
  assert changed.orders.get(2) == Some(Order(id: 2, customer: 2, status: Open, total: 5, placed: 4, note: "rush"))
  assert note_order(sample, 999, "rush") == sample
end

