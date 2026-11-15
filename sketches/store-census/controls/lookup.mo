module Lookup

struct Prices
  table: Map(Text, Int)
end

service
  state Prices = Prices(table: {"apples": 3})
  tools price
  token from env "LOOKUP_TOKEN"
end

fn price(state: Prices, _now: Time, item: Text) : (Prices, Int)
  (state, state.table.get(item) or 0)
end
