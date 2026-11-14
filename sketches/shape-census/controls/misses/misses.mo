module Misses

struct Order
  id: Int
  buyer: Int
  amount: Int
  paid: Bool
end

fn big?(order: Order) : Bool
  order.amount > 100
end

fn by_helper(orders: List(Order)) : List(Order)
  orders.filter(big?)
end

fn by_wrapped_helper(orders: List(Order)) : List(Order)
  orders.filter(fn(order) big?(order) end)
end

fn by_key_arithmetic(orders: List(Order), buyer: Int) : List(Order)
  orders.filter(fn(order) order.buyer * 2 == buyer * 2 end)
end

fn by_two_fields(orders: List(Order)) : List(Order)
  orders.filter(fn(order) order.id == order.buyer end)
end

fn by_negation(orders: List(Order), buyer: Int) : List(Order)
  orders.filter(fn(order) order.buyer != buyer end)
end

fn by_either(orders: List(Order), buyer: Int) : Option(Order)
  orders.find(fn(order) order.buyer == buyer or order.paid end)
end

fn by_modulo(orders: List(Order)) : Int
  orders.count(fn(order) order.id % 10 == 3 end)
end

fn by_loop_helper(orders: List(Order)) : Int
  var total = 0
  for order in orders
    if big?(order)
      total += order.amount
    end
  end
  total
end

fn by_loop_branches(orders: List(Order), buyer: Int) : Int
  var total = 0
  for order in orders
    if order.buyer == buyer
      total += order.amount
    else
      total += 1
    end
  end
  total
end

fn by_loop_arithmetic(orders: List(Order), buyer: Int) : Int
  var total = 0
  for order in orders
    if order.buyer + 1 == buyer + 1
      total += order.amount
    end
  end
  total
end
