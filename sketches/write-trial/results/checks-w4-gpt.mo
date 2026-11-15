module Checks
use Shop{sample, Status}
use Writes{rename_customer, move_customer, rename_product, price_product, note_order, status_order}

test "rename_customer"
  changed = rename_customer(sample, 1, "Ann")
  assert changed.customers.get(1) is Some(row)
  assert row.name == "Ann"
  assert rename_customer(sample, 999, "Ann") == sample
end

test "move_customer"
  changed = move_customer(sample, 1, "Faro")
  assert changed.customers.get(1) is Some(row)
  assert row.city == "Faro"
  assert move_customer(sample, 999, "Faro") == sample
end

test "rename_product"
  changed = rename_product(sample, 1, "pencil")
  assert changed.products.get(1) is Some(row)
  assert row.name == "pencil"
  assert rename_product(sample, 999, "pencil") == sample
end

test "price_product"
  changed = price_product(sample, 1, 7)
  assert changed.products.get(1) is Some(row)
  assert row.price == 7
  assert price_product(sample, 999, 7) == sample
end

test "note_order"
  changed = note_order(sample, 1, "hello")
  assert changed.orders.get(1) is Some(row)
  assert row.note == "hello"
  assert note_order(sample, 999, "hello") == sample
end

test "status_order"
  changed = status_order(sample, 1, Paid)
  assert changed.orders.get(1) is Some(row)
  assert row.status == Paid
  assert status_order(sample, 999, Paid) == sample
end

test "negative price is refused"
  assert price_product(sample, 1, -1) == sample
end
