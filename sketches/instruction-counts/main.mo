module Main

struct Order
  buyer: Int
  band: Int
  amount: Int
end

struct Shop
  orders: Map(Int, Order)
  ids: List(Int)
  by_buyer: Map(Int, List(Int))
  by_band: Map(Int, List(Int))
end

service
  state Shop = empty
  tools grow
  token from env "PERF_TOKEN"
end

empty = Shop(orders: {}, ids: [], by_buyer: {}, by_band: {})

fn grow(state: Shop, _now: Time, step: Int) : (Shop, Int)
  var orders = state.orders
  var ids = state.ids
  var by_buyer = state.by_buyer
  var by_band = state.by_band
  first = state.orders.size
  for id in first..(first + step)
    order = Order(buyer: id / 10, band: id % 10, amount: 100 + id % 900)
    orders = orders.set(id, order)
    ids = ids.append(id)
    by_buyer = by_buyer.update(order.buyer, [], fn(held) held.append(id) end)
    by_band = by_band.update(order.band, [], fn(held) held.append(id) end)
  end
  (Shop(orders: orders, ids: ids, by_buyer: by_buyer, by_band: by_band), orders.size)
end

fn total(state: Shop, picked: List(Int)) : Int
  var sum = 0
  for id in picked
    sum += (state.orders.get(id) or stop "an index names an order that is not there").amount
  end
  sum
end

fn index_one_row(state: Shop) : Int
  (state.orders.get(7) or stop "no order 7").amount
end

fn index_ten_rows(state: Shop) : Int
  total(state, state.by_buyer.get(3) or [])
end

fn index_growing_answer(state: Shop) : Int
  total(state, state.by_band.get(3) or [])
end

fn walk_loop(state: Shop) : Int
  var sum = 0
  for (_, order) in state.orders
    if order.buyer == 3
      sum += order.amount
    end
  end
  sum
end

fn walk_filter(state: Shop) : Int
  state.orders.values.filter(fn(order) order.buyer == 3 end).map(fn(order) order.amount end).sum
end

fn walk_values(state: Shop) : Int
  state.orders.values.size
end

fn walk_keys(state: Shop) : Int
  state.orders.keys.size
end

fn walk_contains(state: Shop) : Bool
  state.ids.contains?(-1)
end

fn walk_reverse(state: Shop) : Int
  state.ids.reverse.size
end

fn walk_unique(state: Shop) : Int
  state.ids.unique.size
end

t0 = Time.parse("2026-01-01T00:00:00Z") or stop "time"

test "the index gives the walk's answer"
  (shop, rows) = grow(empty, t0, 60)
  assert rows == 60
  assert index_ten_rows(shop) == walk_loop(shop)
  assert index_ten_rows(shop) == walk_filter(shop)
  assert index_growing_answer(shop) == 100 * 6 + 3 + 13 + 23 + 33 + 43 + 53
  assert not walk_contains(shop)
end
