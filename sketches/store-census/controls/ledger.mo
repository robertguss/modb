module Ledger

struct Book
  entries: Map(Int, Int)
end

service
  state Book = Book(entries: {})
  tools record, history
  token from env "LEDGER_TOKEN"
end

fn record(state: Book, _now: Time, id: Int, amount: Int) : (Book, Bool)
  var next = state
  next.entries = state.entries.set(id, amount)
  (next, true)
end

fn history(state: Book, _now: Time) : (Book, Int)
  (state, state.entries.size)
end
