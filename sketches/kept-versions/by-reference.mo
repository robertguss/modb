## The control: the same tree with each node holding its children directly.
## Every put keeps the version before it.
module ByReference

row = "0123456789012345678901234567890123456789012345678901234567890123"
width = 16
levels = 5
blank = [
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing,
  Missing
]

enum Node
  Missing
  Branch(List(Node))
  Leaf(Text)
end

struct Rows
  kept: List(Node)
  newest: Node
  rows: Int
end

service
  state Rows = Rows(kept: [], newest: Missing, rows: 0)
  tools grow, put, get, old
  token from env "PERF_TOKEN"
end

fn digit(key: Int, level: Int) : Int
  (key / width.pow(level)) % width
end

fn place(node: Node, key: Int, value: Text, level: Int) : Node
  return Leaf(value) if level == 0
  children = case node
    Branch(found): found
    Missing | Leaf(_): blank
  end
  slot = digit(key, level - 1)
  below = place(children.get(slot) or Missing, key, value, level - 1)
  Branch(children.set(slot, below) or stop "a branch has 16 slots")
end

fn find(node: Node, key: Int, level: Int) : Text
  case node
    Leaf(value): value
    Missing: ""
    Branch(children): find(children.get(digit(key, level - 1)) or Missing, key, level - 1)
  end
end

## Adds `step` rows to the newest version and keeps no version.
fn grow(state: Rows, _now: Time, step: Int) : (Rows, Int)
  var newest = state.newest
  for key in state.rows..(state.rows + step)
    newest = place(newest, key, row, levels)
  end
  (Rows(kept: state.kept, newest: newest, rows: state.rows + step), state.rows + step)
end

## Keeps the version as it is, then sets one row. Gives the number of kept versions.
fn put(state: Rows, _now: Time, key: Int, value: Text) : (Rows, Int)
  kept = state.kept.append(state.newest)
  (Rows(kept: kept, newest: place(state.newest, key, value, levels), rows: state.rows), kept.size)
end

## Reads one row of the newest version.
fn get(state: Rows, _now: Time, key: Int) : Text
  find(state.newest, key, levels)
end

## Reads one row of a kept version, oldest first.
fn old(state: Rows, _now: Time, version: Int, key: Int) : Text
  find(state.kept.get(version) or Missing, key, levels)
end
