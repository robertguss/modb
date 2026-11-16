module Nodes
expose Node(..), Ops(..), capacity, read, write, children

width = 16
levels = 3
capacity = 4096
blank = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

enum Node
  Branch(List(Int))
  Leaf(Int)
end

struct Ops(S)
  get: fn(S, Int) : Option(Node)
  put: fn(S, Int, Node) : S
  remove: fn(S, Int) : S
end

fn digit(key: Int, level: Int) : Int
  (key / width.pow(level)) % width
end

fn read(ops: Ops(S), store: S, root: Int, key: Int) : Option(Int)
  return None if key < 0 or key >= capacity
  var at = root
  for step in 0..levels
    case ops.get(store, at)
      Some(Branch(slots)): at = slots.get(digit(key, levels - 1 - step)) or 0
      Some(Leaf(_)) | None: return None
    end
  end
  case ops.get(store, at)
    Some(Leaf(value)): Some(value)
    Some(Branch(_)) | None: None
  end
end

fn write(ops: Ops(S), store: S, next: Int, root: Int, key: Int, value: Int) : (S, Int, Int)
  return (store, next, root) if key < 0 or key >= capacity
  var nodes = store
  var from = root
  for step in 0..levels
    slots = case ops.get(nodes, from)
      Some(Branch(found)): found
      Some(Leaf(_)) | None: blank
    end
    slot = digit(key, levels - 1 - step)
    from = slots.get(slot) or 0
    copy = slots.set(slot, next + step + 1) or stop "a branch has 16 slots"
    nodes = ops.put(nodes, next + step, Branch(copy))
  end
  nodes = ops.put(nodes, next + levels, Leaf(value))
  (nodes, next + levels + 1, next)
end

fn children(ops: Ops(S), store: S, name: Int) : Option(List(Int))
  case ops.get(store, name)
    Some(Branch(slots)): Some(slots.filter(fn(slot) slot != 0 end))
    Some(Leaf(_)): Some([])
    None: None
  end
end
