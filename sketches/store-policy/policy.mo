module Policy
expose Head(..), Call(..), start, apply, replay, get, get_at, sound?, stored
use Nodes

struct Head
  next: Int
  root: Int
  holders: Map(Text, Int)
  log: List(Call)
end

enum Call
  Put(key: Int, value: Int)
  Hold(who: Text)
  Drop(who: Text)
  Sweep
end

start = Head(next: 1, root: 0, holders: {}, log: [])

fn apply(ops: Nodes.Ops(S), store: S, head: Head, call: Call) : (S, Head)
  log = head.log.append(call)
  case call
    Put(key: key, value: value):
      (nodes, next, root) = Nodes.write(ops, store, head.next, head.root, key, value)
      (nodes, Head(next: next, root: root, holders: head.holders, log: log))
    Hold(who: who):
      held = head.holders.set(who, head.root)
      (store, Head(next: head.next, root: head.root, holders: held, log: log))
    Drop(who: who):
      held = head.holders.remove(who)
      (store, Head(next: head.next, root: head.root, holders: held, log: log))
    Sweep:
      swept = sweep(ops, store, head)
      (swept, Head(next: head.next, root: head.root, holders: head.holders, log: log))
  end
end

fn replay(ops: Nodes.Ops(S), store: S, calls: List(Call)) : (S, Head)
  var nodes = store
  var head = start
  for call in calls
    step = apply(ops, nodes, head, call)
    nodes = step.0
    head = step.1
  end
  (nodes, head)
end

fn get(ops: Nodes.Ops(S), store: S, head: Head, key: Int) : Option(Int)
  Nodes.read(ops, store, head.root, key)
end

fn get_at(ops: Nodes.Ops(S), store: S, head: Head, who: Text, key: Int) : Option(Int)
  case head.holders.get(who)
    Some(root): Nodes.read(ops, store, root, key)
    None: None
  end
end

fn sweep(ops: Nodes.Ops(S), store: S, head: Head) : S
  live = reach(ops, store, head.holders.values.append(head.root))
  var nodes = store
  for name in 1..head.next
    continue if live.has?(name)
    nodes = ops.remove(nodes, name)
  end
  nodes
end

fn reach(ops: Nodes.Ops(S), store: S, roots: List(Int)) : Set(Int)
  var seen = Set.empty
  for root in roots
    seen = mark(ops, store, seen, root)
  end
  seen
end

fn mark(ops: Nodes.Ops(S), store: S, seen: Set(Int), name: Int) : Set(Int)
  return seen if name == 0 or seen.has?(name)
  var marked = seen.add(name)
  for child in Nodes.children(ops, store, name) or []
    marked = mark(ops, store, marked, child)
  end
  marked
end

fn sound?(ops: Nodes.Ops(S), store: S, head: Head) : Bool
  for name in reach(ops, store, head.holders.values.append(head.root))
    return false if Nodes.children(ops, store, name) == None
  end
  true
end

fn stored(ops: Nodes.Ops(S), store: S, head: Head) : Int
  var count = 0
  for name in 1..head.next
    count += 1 if Nodes.children(ops, store, name) != None
  end
  count
end
