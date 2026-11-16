module ControlBService
use Policy

struct State
  files: Option(Files)
  head: Policy.Head
end

service
  state State = State(files: None, head: Policy.start)
  tools peek
  token from env "STORE_TOKEN"
end

fn peek(state: State, _now: Time) : Int
  state.head.root
end
