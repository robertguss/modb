module Story
expose Told(..), calls, tell, fold
use Nodes
use Policy

struct Told
  rows: List(Option(Int))
  sound: Bool
  stored: Int
  before: Int
end

calls = [
  Policy.Put(key: 1, value: 10),
  Policy.Put(key: 2, value: 20),
  Policy.Hold(who: "ada"),
  Policy.Put(key: 1, value: 11),
  Policy.Hold(who: "bo"),
  Policy.Put(key: 3, value: 30),
  Policy.Drop(who: "bo"),
]

fn tell(ops: Nodes.Ops(S), empty: S) : Told
  (filled, full) = Policy.replay(ops, empty, calls)
  before = Policy.stored(ops, filled, full)
  (store, head) = Policy.apply(ops, filled, full, Policy.Sweep)
  rows = [
    Policy.get(ops, store, head, 1),
    Policy.get(ops, store, head, 3),
    Policy.get_at(ops, store, head, "ada", 1),
    Policy.get_at(ops, store, head, "ada", 2),
    Policy.get_at(ops, store, head, "ada", 3),
    Policy.get_at(ops, store, head, "bo", 1),
  ]
  Told(
    rows: rows,
    sound: Policy.sound?(ops, store, head),
    stored: Policy.stored(ops, store, head),
    before: before,
  )
end

fn fold(call: Policy.Call) : Policy.Call
  case call
    Policy.Put(key: key, value: value):
      Policy.Put(key: ((key % Nodes.capacity) + Nodes.capacity) % Nodes.capacity, value: value)
    Policy.Hold(who: _) | Policy.Drop(who: _) | Policy.Sweep: call
  end
end
