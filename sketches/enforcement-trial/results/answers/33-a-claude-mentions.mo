module Answer
expose mentions
use Shop{Shop, walk}

fn mentions(shop: Shop, word: Text) : List(Int)
  walk(shop.orders).values.filter(fn(order) order.note.contains?(word) end).map(fn(order) order.id end)
end
