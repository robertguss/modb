module Answer
expose mentions
use Shop{Shop}

fn mentions(shop: Shop, word: Text) : List(Int)
  shop.orders.walk.filter(fn(row) row.note.contains?(word) end).map(fn(row) row.id end).sort
end
