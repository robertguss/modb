## The service around the book of tallies.
module Main
use Book

service
  state Book.State = Book.empty
  tools add, move, tally, moves
  token from env "BOOK_TOKEN"
end

## Adds `n` to a tally.
fn add(book: Book.State, _now: Time, name: Text, n: Int) : (Book.State, Int)
  Book.add(book, name, n)
end

## Moves `n` from one tally to another.
fn move(book: Book.State, _now: Time, giver: Text, taker: Text, n: Int) : Result((Book.State, Int), Text)
  Book.move(book, giver, taker, n)
end

## Reads one tally.
fn tally(book: Book.State, _now: Time, name: Text) : Int
  book.tallies.get(name) or 0
end

## Reads the count of moves made.
fn moves(book: Book.State, _now: Time) : Int
  book.moves
end
