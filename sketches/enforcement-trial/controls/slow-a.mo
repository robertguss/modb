module Answer
expose all_totals, by_note, by_helper, not_customer, either, looped, looped_more, bound, handed, counted,
  wrong_field
use Shop{Shop, Order, Status}

fn all_totals(shop: Shop) : Int
  shop.orders.values.map(fn(order) order.total end).sum
end

fn by_note(shop: Shop, word: Text) : List(Order)
  shop.orders.values.filter(fn(order) order.note.contains?(word) end)
end

fn paid?(order: Order) : Bool
  order.status == Paid
end

fn by_helper(shop: Shop) : List(Order)
  shop.orders.values.filter(paid?)
end

fn not_customer(shop: Shop, customer: Int) : List(Order)
  shop.orders.values.filter(fn(order) order.customer != customer end)
end

fn either(shop: Shop, customer: Int) : List(Order)
  shop.orders.values.filter(fn(order) order.customer == customer or order.status == Paid end)
end

fn looped(shop: Shop) : Int
  var sum = 0
  for order in shop.orders.values
    sum += order.total
  end
  sum
end

fn looped_more(shop: Shop, customer: Int) : Int
  var sum = 0
  for (_, order) in shop.orders
    if order.customer == customer
      sum += order.total
    else
      sum += 1
    end
  end
  sum
end

fn bound(shop: Shop) : Int
  orders = shop.orders.values
  orders.size
end

fn size_of(orders: Map(Int, Order)) : Int
  orders.size
end

fn handed(shop: Shop) : Int
  size_of(shop.orders)
end

fn counted(shop: Shop) : Int
  shop.lines
    .values
    .count(fn(line) line.quantity > 1 end)
end

fn wrong_field(shop: Shop, name: Text) : Int
  shop.products.values.count(fn(product) product.name == name end)
end
