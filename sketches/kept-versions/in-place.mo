## Six ways to add a row to a map that travels with a number. A way that
## changes the map in place takes the same time for each row at any size. A way
## that copies the map takes four times as long for twice the rows. The sixth
## way, `local`, assigns the field of a record that never leaves one function.
module InPlace

struct Held
  rows: Map(Int, Int)
  next: Int
end

## The map sits in a record, and a field is assigned.
fn field(held: Held, i: Int) : Held
  var changed = held
  changed.rows = changed.rows.set(i, i)
  changed
end

## The map is taken out of the record before it changes.
fn take(held: Held, i: Int) : Held
  var changed = held
  var rows = changed.rows
  changed.rows = {}
  rows = rows.set(i, i)
  changed.rows = rows
  changed
end

## The record is taken apart and built again.
fn apart(held: Held, i: Int) : Held
  case held
    Held(rows: rows, next: next): Held(rows: rows.set(i, i), next: next + 1)
  end
end

## The map travels alone.
fn bare(rows: Map(Int, Int), i: Int) : Map(Int, Int)
  rows.set(i, i)
end

## The map comes back in a tuple that is taken apart at once.
fn pair(rows: Map(Int, Int), i: Int) : (Map(Int, Int), Int)
  (rows.set(i, i), i + 1)
end

fn by_pair(rows: Map(Int, Int), i: Int, count: Int) : Map(Int, Int)
  return rows if i == count
  (grown, next) = pair(rows, i)
  by_pair(grown, next, count)
end

fn in_record(job: Text, count: Int) : Int
  var held = Held(rows: {}, next: 0)
  for i in 0..count
    if job == "local"
      held.rows = held.rows.set(i, i)
    else if job == "field"
      held = field(held, i)
    else if job == "take"
      held = take(held, i)
    else
      held = apart(held, i)
    end
  end
  held.rows.size
end

fn alone(count: Int) : Int
  var rows = {}
  for i in 0..count
    rows = bare(rows, i)
  end
  rows.size
end

fn main(args: Args, console: Console)
  job = args.list.first or ""
  count = (args.list.get(1) or "").to_int or 0
  size = if job == "bare"
    alone(count)
  else if job == "pair"
    by_pair({}, 0, count).size
  else
    in_record(job, count)
  end
  console.print("#{job} #{count} #{size}")
end
