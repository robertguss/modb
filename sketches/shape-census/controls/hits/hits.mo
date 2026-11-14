module Hits

struct Order
  id: Int
  buyer: Int
  amount: Int
  paid: Bool
end

fn of_buyer(orders: List(Order), buyer: Int) : List(Order)
  orders.filter(fn(order) order.buyer == buyer end)
end

fn reversed(orders: List(Order), buyer: Int) : List(Order)
  orders.filter(fn(order) buyer == order.buyer end)
end

fn large(orders: List(Order), least: Int) : List(Order)
  orders.filter(fn(order) order.amount >= least end)
end

fn one(orders: List(Order), id: Int) : Option(Order)
  orders.find(fn(order) order.id == id end)
end

fn paid_by(orders: List(Order), buyer: Int) : Int
  orders.count(fn(order) order.buyer == buyer and order.paid end)
end

fn total_of(orders: List(Order), buyer: Int) : Int
  var total = 0
  for order in orders
    if order.buyer == buyer
      total += order.amount
    end
  end
  total
end

fn total_in(orders: Map(Int, Order), buyer: Int) : Int
  var total = 0
  for (_, order) in orders
    if order.buyer == buyer
      total += order.amount
    end
  end
  total
end

fn numbers_above(numbers: List(Int), least: Int) : List(Int)
  var kept = []
  for number in numbers
    if number > least
      kept = kept.append(number)
    end
  end
  kept
end
