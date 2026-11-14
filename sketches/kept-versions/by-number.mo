## Numbered rows in the tree by number. Every put keeps the version before it.
module ByNumber
use Tree

row = "0123456789012345678901234567890123456789012345678901234567890123"

struct Rows
  tree: Map(Int, Tree.Node(Text))
  kept: List(Int)
  rows: Int
end

service
  state Rows = Rows(tree: {}, kept: [], rows: 0)
  tools grow, put, get, old
  token from env "PERF_TOKEN"
end

## Adds `step` rows to the version being written and keeps no version.
fn grow(state: Rows, _now: Time, step: Int) : (Rows, Int)
  var tree = state.tree
  for key in state.rows..(state.rows + step)
    tree = Tree.put(tree, key, row)
  end
  (Rows(tree: tree, kept: state.kept, rows: state.rows + step), state.rows + step)
end

## Keeps the version as it is, then sets one row. Gives the number of kept versions.
fn put(state: Rows, _now: Time, key: Int, value: Text) : (Rows, Int)
  kept = state.kept.append(Tree.root(state.tree))
  tree = Tree.put(Tree.keep(state.tree), key, value)
  (Rows(tree: tree, kept: kept, rows: state.rows), kept.size)
end

## Reads one row of the newest version.
fn get(state: Rows, _now: Time, key: Int) : Text
  Tree.get(state.tree, key) or ""
end

## Reads one row of a kept version, oldest first.
fn old(state: Rows, _now: Time, version: Int, key: Int) : Text
  Tree.get_at(state.tree, state.kept.get(version) or 0, key) or ""
end
