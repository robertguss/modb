## A book of named tallies, version 3: the book counts the moves made.
module Book
expose State(..), empty, add, move, from_v2
use UpgradeOld

struct State
  tallies: Map(Text, Int)
  moves: Int
end

empty = State(tallies: {}, moves: 0)

## Turns a version 2 book into a version 3 book.
fn from_v2(old: UpgradeOld.State) : State
  State(tallies: old.tallies, moves: 0)
end

## Adds `n` to a tally and gives its new count.
fn add(book: State, name: Text, n: Int) : (State, Int)
  count = (book.tallies.get(name) or 0) + n
  (State(tallies: book.tallies.set(name, count), moves: book.moves), count)
end

## Moves `n` from one tally to another and gives what the giver has left.
fn move(book: State, giver: Text, taker: Text, n: Int) : Result((State, Int), Text)
  left = (book.tallies.get(giver) or 0) - n
  return Error("not enough") if left < 0
  gained = (book.tallies.get(taker) or 0) + n
  Ok((State(tallies: book.tallies.set(giver, left).set(taker, gained), moves: book.moves + 1), left))
end
