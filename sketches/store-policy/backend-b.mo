module BackendB
expose ops, commit, recover
use BackendA
use Nodes
use Policy
use Story

fn ops() : Nodes.Ops(Files)
  Nodes.Ops(get: fetch, put: keep, remove: free)
end

fn fetch(files: Files, name: Int) : Option(Nodes.Node)
  case files.read_text("n#{name}")
    Ok(text): Some(node_from(text))
    Error(NotFound(path: _)): None
    Error(_): stop "a node could not be read"
  end
end

fn keep(files: Files, name: Int, node: Nodes.Node) : Files
  case files.write_text("n#{name}", node_text(node))
    Ok(_): files
    Error(_): stop "a node could not be written"
  end
end

fn free(files: Files, name: Int) : Files
  case files.remove("n#{name}")
    Ok(_) | Error(NotFound(path: _)): files
    Error(_): stop "a node could not be removed"
  end
end

fn node_text(node: Nodes.Node) : Text
  case node
    Nodes.Branch(slots): "B #{slots.map(fn(slot) slot.to_text end).join(" ")}"
    Nodes.Leaf(value): "L #{value}"
  end
end

fn node_from(text: Text) : Nodes.Node
  words = text.split(" ")
  numbers = words.drop(1).filter_map(fn(word) word.to_int end)
  case words.first
    Some("B"): Nodes.Branch(numbers)
    Some("L"): Nodes.Leaf(numbers.first or stop "a leaf has a value")
    Some(_) | None: stop "a node file starts with B or L"
  end
end

fn call_text(call: Policy.Call) : Text
  case call
    Policy.Put(key: key, value: value): "put #{key} #{value}"
    Policy.Hold(who: who): "hold #{who}"
    Policy.Drop(who: who): "drop #{who}"
    Policy.Sweep: "sweep"
  end
end

fn call_from(line: Text) : Policy.Call
  words = line.split(" ")
  rest = words.drop(1)
  case words.first
    Some("put"):
      Policy.Put(
        key: (rest.get(0) or "").to_int or stop "a put has a key",
        value: (rest.get(1) or "").to_int or stop "a put has a value",
      )
    Some("hold"): Policy.Hold(who: rest.join(" "))
    Some("drop"): Policy.Drop(who: rest.join(" "))
    Some("sweep"): Policy.Sweep
    Some(_) | None: stop "a log line starts with put, hold, drop or sweep"
  end
end

fn commit(files: Files, head: Policy.Head, call: Policy.Call) : Policy.Head
  case files.append_text("log", "#{call_text(call)}\n")
    Ok(_): Policy.apply(ops(), files, head, call).1
    Error(_): stop "the log could not be written"
  end
end

fn recover(files: Files) : Policy.Head
  case files.read_text("log")
    Ok(text): Policy.replay(ops(), files, text.lines.map(call_from)).1
    Error(NotFound(path: _)): Policy.start
    Error(_): stop "the log could not be read"
  end
end

fn sound_after(files: Files, calls: List(Policy.Call)) : Bool
  promise "no held version reaches a freed node, whatever the calls"
    result
    allows files: Files.in_memory({}), calls: [], result: true
    forbids files: Files.in_memory({}), calls: [], result: false
  end

  (_, head) = Policy.replay(ops(), files, calls.map(Story.fold))
  Policy.sound?(ops(), files, head)
end

test "the story over files gives the same answers as over a map"
  assert Story.tell(ops(), Files.in_memory({})) == Story.tell(BackendA.ops(), {})
end

test "replaying the log file over the surviving files gives the same state"
  files = Files.in_memory({})
  var head = Policy.start
  for call in Story.calls.append(Policy.Sweep)
    head = commit(files, head, call)
  end
  assert recover(files) == head
  assert Policy.sound?(ops(), files, head)
  assert Policy.get_at(ops(), files, head, "ada", 1) == Some(10)
  assert Policy.stored(ops(), files, head) == 10
end
