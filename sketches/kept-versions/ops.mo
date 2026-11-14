## Runs inserts and lookups on a Map and on the tree by number, outside a
## service, so a script can time them.
module Ops
use Tree

row = "0123456789012345678901234567890123456789012345678901234567890123"

fn map_of(count: Int) : Map(Int, Text)
  var rows = {}
  for key in 0..count
    rows = rows.set(key, row)
  end
  rows
end

fn tree_of(count: Int) : Map(Int, Tree.Node(Text))
  var tree = {}
  for key in 0..count
    tree = Tree.put(tree, key, row)
  end
  tree
end

fn main(args: Args, console: Console)
  job = args.list.first or ""
  count = (args.list.get(1) or "").to_int or 0
  var found = 0
  if job == "map-put"
    found = map_of(count).size
  else if job == "map-get"
    rows = map_of(count)
    for key in 0..count
      found += (rows.get(key) or "").byte_count
    end
  else if job == "tree-put"
    found = tree_of(count).size
  else if job == "tree-get"
    tree = tree_of(count)
    for key in 0..count
      found += (Tree.get(tree, key) or "").byte_count
    end
  else if job == "tree-keep"
    var kept = tree_of(count)
    for key in 0..count
      kept = Tree.put(Tree.keep(kept), key, row)
    end
    found = kept.size
  end
  console.print("#{job} #{count} #{found}")
end
