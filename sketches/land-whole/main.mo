## Two accounts. A world's calls land whole or not at all, and the rule is
## checked after every call.
module Main

struct Accounts
  a: Int
  b: Int
end

enum Call
  Take(Int)
  Put(Int)
  Transfer(Int)
end

enum Refused
  BadAmount(Int)
  Short(have: Int, want: Int)
  RuleBroken(step: Int)
end

service
  state Accounts = Accounts(a: 2, b: 0)
  tools land
  token from env "LAND_TOKEN"

  promise "the total never changes"
    after.a + after.b == before.a + before.b
    allows before: start, after: moved, now: t0
    forbids before: start, after: Accounts(a: 1, b: 0), now: t0
  end
end

fn amount(call: Call) : Int
  case call
    Take(n): n
    Put(n): n
    Transfer(n): n
  end
end

fn apply(state: Accounts, call: Call) : Result(Accounts, Refused)
  n = amount(call)
  return Error(BadAmount(n)) if n < 0 or n > 1000
  case call
    Take(_) if state.a < n: Error(Short(have: state.a, want: n))
    Take(_): Ok(Accounts(a: state.a - n, b: state.b))
    Put(_): Ok(Accounts(a: state.a, b: state.b + n))
    Transfer(_) if state.a < n: Error(Short(have: state.a, want: n))
    Transfer(_): Ok(Accounts(a: state.a - n, b: state.b + n))
  end
end

fn rule?(before: Accounts, after: Accounts) : Bool
  after.a + after.b == before.a + before.b
end

## Lands every call in the list, or none of them.
fn land(state: Accounts, _now: Time, calls: List(Call)) : Result((Accounts, Int), Refused)
  var world = state
  var landed = 0
  for call in calls
    next = try apply(world, call)
    return Error(RuleBroken(step: landed)) if not rule?(world, next)
    world = next
    landed += 1
  end
  Ok((world, landed))
end

start = Accounts(a: 2, b: 0)
moved = Accounts(a: 1, b: 1)
t0 = Time.parse("2026-01-01T00:00:00Z") or stop "time"

test "a transfer written as two calls is refused"
  assert land(start, t0, [Take(1), Put(1)]) == Error(RuleBroken(step: 0))
end

test "a transfer written as one call lands"
  assert land(start, t0, [Transfer(1)]) == Ok((moved, 1))
end

test "a world whose second call fails lands nothing"
  assert land(start, t0, [Transfer(1), Transfer(5)]) == Error(Short(have: 1, want: 5))
end
