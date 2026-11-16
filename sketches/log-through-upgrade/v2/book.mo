## A book of named tallies, version 2: a move may not take a tally below zero.
module Book
expose State(..), empty, add, move

struct State
  tallies: Map(Text, Int)
end

empty = State(tallies: {})

## Adds `n` to a tally and gives its new count.
fn add(book: State, name: Text, n: Int) : (State, Int)
  count = (book.tallies.get(name) or 0) + n
  (State(tallies: book.tallies.set(name, count)), count)
end

## Moves `n` from one tally to another and gives what the giver has left.
fn move(book: State, giver: Text, taker: Text, n: Int) : Result((State, Int), Text)
  left = (book.tallies.get(giver) or 0) - n
  return Error("not enough") if left < 0
  gained = (book.tallies.get(taker) or 0) + n
  Ok((State(tallies: book.tallies.set(giver, left).set(taker, gained)), left))
end
