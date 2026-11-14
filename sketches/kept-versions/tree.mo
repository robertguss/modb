## Numbered rows that keep their old versions. A tree is one map of nodes that
## name their children by number, so a saved copy holds each node once. An
## empty map is an empty tree.
##
## The tree is a bare map and not a record that holds one, because Mo copies a
## map held in a record every time it changes.
module Tree
expose Node(..), capacity, get, get_at, put, keep, open, root, entries

width = 16
levels = 5
capacity = 1_048_576
blank = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

## Number 0 holds the head, and in a branch it means no child. `root` is the
## version being written. A node numbered below `frozen` belongs to a kept
## version and is never written again.
enum Node(V)
  Head(next: Int, frozen: Int, root: Int)
  Branch(List(Int))
  Leaf(V)
end

fn head(tree: Map(Int, Node(V))) : (Int, Int, Int)
  case tree.get(0)
    Some(Head(next: next, frozen: frozen, root: top)): (next, frozen, top)
    Some(Branch(_)) | Some(Leaf(_)): stop "number 0 is not the head"
    None: (1, 1, 0)
  end
end

## The number of the version being written.
fn root(tree: Map(Int, Node(V))) : Int
  head(tree).2
end

fn digit(key: Int, level: Int) : Int
  (key / width.pow(level)) % width
end

## Reads a row of the version being written.
fn get(tree: Map(Int, Node(V)), key: Int) : Option(V)
  get_at(tree, root(tree), key)
end

## Reads a row of any version, by the number of its root.
fn get_at(tree: Map(Int, Node(V)), version: Int, key: Int) : Option(V)
  return None if key < 0 or key >= capacity
  var at = version
  for step in 0..levels
    case tree.get(at)
      Some(Branch(children)): at = children.get(digit(key, levels - 1 - step)) or 0
      Some(Leaf(_)) | Some(Head(next: _)) | None: return None
    end
  end
  case tree.get(at)
    Some(Leaf(value)): Some(value)
    Some(Branch(_)) | Some(Head(next: _)) | None: None
  end
end

## Sets a row of the version being written. Kept versions do not change: a
## node a kept version holds is written under a new number.
fn put(tree: Map(Int, Node(V)), key: Int, value: V) : Map(Int, Node(V))
  if key < 0 or key >= capacity
    stop "the key is outside the tree"
  end
  (start, frozen, top) = head(tree)
  var nodes = tree
  var next = start
  var from = top
  var to = if from >= frozen: from else: next
  next = next.max(to + 1)
  written = to
  for step in 0..levels
    children = case nodes.get(from)
      Some(Branch(found)): found
      Some(Leaf(_)) | Some(Head(next: _)) | None: blank
    end
    slot = digit(key, levels - 1 - step)
    from = children.get(slot) or 0
    child = if from >= frozen: from else: next
    next = next.max(child + 1)
    nodes = nodes.set(to, Branch(children.set(slot, child) or stop "a branch has 16 slots"))
    to = child
  end
  nodes = nodes.set(to, Leaf(value))
  nodes.set(0, Head(next: next, frozen: frozen, root: written))
end

## Starts writing from the version whose root is `version`. Every node made so
## far now belongs to a kept version.
fn open(tree: Map(Int, Node(V)), version: Int) : Map(Int, Node(V))
  next = head(tree).0
  tree.set(0, Head(next: next, frozen: next, root: version))
end

## Keeps the version being written. Its number is `root(tree)`.
fn keep(tree: Map(Int, Node(V))) : Map(Int, Node(V))
  open(tree, root(tree))
end

## Every row of a version, in key order.
fn entries(tree: Map(Int, Node(V)), version: Int) : List((Int, V))
  return [] if version == 0
  walk(tree, version, 0)
end

fn walk(tree: Map(Int, Node(V)), at: Int, prefix: Int) : List((Int, V))
  case tree.get(at)
    Some(Leaf(value)): [(prefix, value)]
    Some(Head(next: _)) | None: []
    Some(Branch(children)):
      var rows = []
      for (slot, child) in children.enumerate
        continue if child == 0
        rows = rows.concat(walk(tree, child, prefix * width + slot))
      end
      rows
  end
end

fn filled(count: Int) : Map(Int, Node(Int))
  var tree = {}
  for key in 0..count
    tree = put(tree, key, key * 10)
  end
  tree
end

test "a row is read back, and a missing row is not"
  tree = filled(40)
  assert get(tree, 17) == Some(170)
  assert get(tree, 40) == None
  assert get(tree, capacity) == None
  assert get(filled(0), 0) == None
end

test "a kept version does not change when the tree is written again"
  first = keep(filled(40))
  second = put(first, 17, -1)
  assert get_at(second, root(first), 17) == Some(170)
  assert get(second, 17) == Some(-1)
  assert get(second, 18) == Some(180)
end

test "a kept version costs the nodes on one path, not a copy"
  first = keep(filled(4000))
  second = put(first, 17, -1)
  assert second.size - first.size == levels + 1
end

test "writing without keeping adds no node for a row that is there"
  first = filled(40)
  second = put(first, 17, -1)
  assert second.size == first.size
end

test "two versions opened from one root do not see each other"
  base = keep(filled(40))
  left = put(open(base, root(base)), 1, 111)
  right = put(open(left, root(base)), 2, 222)
  assert get_at(right, root(left), 1) == Some(111)
  assert get_at(right, root(left), 2) == Some(20)
  assert get(right, 1) == Some(10)
  assert get(right, 2) == Some(222)
end

test "entries lists a version's rows in key order"
  assert entries(filled(3), root(filled(3))) == [(0, 0), (1, 10), (2, 20)]
  assert entries(filled(18), root(filled(18))).size == 18
  assert entries(filled(0), 0) == []
end
