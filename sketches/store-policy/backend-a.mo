module BackendA
expose State(..), ops, put, hold, drop, sweep, get, held
use Nodes
use Policy
use Story

struct State
  nodes: Map(Int, Nodes.Node)
  head: Policy.Head
end

service
  state State = empty
  tools put, hold, drop, sweep, get, held
  token from env "STORE_TOKEN"

  promise "no held version reaches a freed node"
    Policy.sound?(ops(), after.nodes, after.head)
    allows before: empty, after: empty, now: t0
    forbids before: empty, after: broken, now: t0
  end
end

empty = State(nodes: {}, head: Policy.start)
broken = State(nodes: {}, head: Policy.Head(next: 2, root: 1, holders: {}, log: []))
t0 = Time.parse("2026-01-01T00:00:00Z") or stop "time"

fn ops() : Nodes.Ops(Map(Int, Nodes.Node))
  Nodes.Ops(get: fetch, put: keep, remove: free)
end

fn fetch(nodes: Map(Int, Nodes.Node), name: Int) : Option(Nodes.Node)
  nodes.get(name)
end

fn keep(nodes: Map(Int, Nodes.Node), name: Int, node: Nodes.Node) : Map(Int, Nodes.Node)
  nodes.set(name, node)
end

fn free(nodes: Map(Int, Nodes.Node), name: Int) : Map(Int, Nodes.Node)
  nodes.remove(name)
end

fn step(state: State, call: Policy.Call) : (State, Unit)
  (nodes, head) = Policy.apply(ops(), state.nodes, state.head, Story.fold(call))
  (State(nodes: nodes, head: head), Unit)
end

fn put(state: State, _now: Time, key: Int, value: Int) : (State, Unit)
  step(state, Policy.Put(key: key, value: value))
end

fn hold(state: State, _now: Time, who: Text) : (State, Unit)
  step(state, Policy.Hold(who: who))
end

fn drop(state: State, _now: Time, who: Text) : (State, Unit)
  step(state, Policy.Drop(who: who))
end

fn sweep(state: State, _now: Time) : (State, Unit)
  step(state, Policy.Sweep)
end

fn get(state: State, _now: Time, key: Int) : Option(Int)
  Policy.get(ops(), state.nodes, state.head, key)
end

fn held(state: State, _now: Time, who: Text, key: Int) : Option(Int)
  Policy.get_at(ops(), state.nodes, state.head, who, key)
end

test "the story over a map: held rows stay, and the sweep frees the rest"
  told = Story.tell(ops(), {})
  assert told.rows == [Some(11), Some(30), Some(10), Some(20), None, None]
  assert told.sound
  assert told.before == 16
  assert told.stored == 10
end

test "replaying the log from an empty map gives the same state"
  (nodes, head) = Policy.replay(ops(), {}, Story.calls.append(Policy.Sweep))
  assert Policy.replay(ops(), {}, head.log) == (nodes, head)
end
