## Runs a record of calls again through the kept code of three versions of the book.
module Rebuild
use Book1
use Book2
use Book3
use Calls

fn step1(book: Book1.State, tool: Calls.Tool) : (Book1.State, Text)
  case tool
    Calls.Add(name: name, n: n):
      (next, count) = Book1.add(book, name, n)
      (next, "#{count}")
    Calls.Move(giver: giver, taker: taker, n: n):
      case Book1.move(book, giver, taker, n)
        Ok(moved): (moved.0, "#{moved.1}")
        Error(why): (book, "error #{why}")
      end
  end
end

fn step2(book: Book2.State, tool: Calls.Tool) : (Book2.State, Text)
  case tool
    Calls.Add(name: name, n: n):
      (next, count) = Book2.add(book, name, n)
      (next, "#{count}")
    Calls.Move(giver: giver, taker: taker, n: n):
      case Book2.move(book, giver, taker, n)
        Ok(moved): (moved.0, "#{moved.1}")
        Error(why): (book, "error #{why}")
      end
  end
end

fn step3(book: Book3.State, tool: Calls.Tool) : (Book3.State, Text)
  case tool
    Calls.Add(name: name, n: n):
      (next, count) = Book3.add(book, name, n)
      (next, "#{count}")
    Calls.Move(giver: giver, taker: taker, n: n):
      case Book3.move(book, giver, taker, n)
        Ok(moved): (moved.0, "#{moved.1}")
        Error(why): (book, "error #{why}")
      end
  end
end

## Every call under its own version's code, with the upgrade function in its place.
fn faithful(calls: List(Calls.Call), console: Console) : Book3.State
  var one = Book1.empty
  for call in calls
    continue if call.version != 1
    (next, reply) = step1(one, call.tool)
    one = next
    console.print("reply #{call.index} #{reply}")
  end
  var two = Book2.State(tallies: one.tallies)
  for call in calls
    continue if call.version != 2
    (next, reply) = step2(two, call.tool)
    two = next
    console.print("reply #{call.index} #{reply}")
  end
  later(Book3.from_v2(two), calls, console)
end

## Version 1's calls through version 2's code, then the rest as before.
fn fixed(calls: List(Calls.Call), console: Console) : Book3.State
  var two = Book2.empty
  for call in calls
    continue if call.version == 3
    (next, reply) = step2(two, call.tool)
    two = next
    console.print("reply #{call.index} #{reply}")
  end
  later(Book3.from_v2(two), calls, console)
end

## Every call through version 3's code from an empty version 3 book.
fn newest(calls: List(Calls.Call), console: Console) : Book3.State
  var three = Book3.empty
  for call in calls
    continue if call.version == 3
    (next, reply) = step3(three, call.tool)
    three = next
    console.print("reply #{call.index} #{reply}")
  end
  later(three, calls, console)
end

fn later(book: Book3.State, calls: List(Calls.Call), console: Console) : Book3.State
  var three = book
  for call in calls
    continue if call.version != 3
    (next, reply) = step3(three, call.tool)
    three = next
    console.print("reply #{call.index} #{reply}")
  end
  three
end

fn without(calls: List(Calls.Call), caller: Text) : List(Calls.Call)
  var kept = []
  for call in calls
    continue if call.caller == caller
    kept = kept.append(call)
  end
  kept
end

fn main(args: Args, console: Console)
  job = args.list.first or ""
  book = if job == "faithful"
    faithful(Calls.story, console)
  else if job == "without-b"
    faithful(without(Calls.story, "b"), console)
  else if job == "fixed"
    fixed(Calls.story, console)
  else
    newest(Calls.story, console)
  end
  for name in ["x", "y", "z"]
    console.print("tally #{name} #{book.tallies.get(name) or 0}")
  end
  console.print("moves #{book.moves}")
end
