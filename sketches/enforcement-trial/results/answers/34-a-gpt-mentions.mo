module Answer
expose mentions
use Shop{Shop, walk}

fn mentions(shop: Shop, word: Text) : List(Int)
  var ids = []
  for order in walk(shop.orders).values
    if order.note.contains?(word)
      ids = ids.append(order.id)
    end
  end
  ids.sort
end
