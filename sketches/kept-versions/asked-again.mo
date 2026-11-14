## The worlds in a running service. The service keeps every open world with
## the questions it asked and the answers it got, and a landing asks them
## again. Every caller reads through the same view, `Worlds.anywhere?`.
module AskedAgain
use Tree
use Worlds

## `begun` counts the worlds ever opened, and is the next world's number.
struct Shared
  db: Worlds.Db
  rows: Int
  worlds: Map(Int, Worlds.World)
  begun: Int
end

enum Problem
  NoWorld(Int)
  NoQuestion(Text)
  Refused(Worlds.Refused)
end

service
  state Shared = Shared(db: Worlds.Db(tree: {}, main: 0), rows: 0, worlds: {}, begun: 0)
  tools grow, begin, ask, move, land
  token from env "PERF_TOKEN"
end

## Adds `step` accounts to the main line, for setting up. Account `key` holds
## 100 + key % 900.
fn grow(state: Shared, _now: Time, step: Int) : (Shared, Int)
  var tree = state.db.tree
  for key in state.rows..(state.rows + step)
    tree = Tree.put(tree, key, 100 + key % 900)
  end
  rows = state.rows + step
  (
    Shared(
      db: Worlds.Db(tree: tree, main: Tree.root(tree)),
      rows: rows,
      worlds: state.worlds,
      begun: state.begun
    ),
    rows
  )
end

## Opens a world on the main line as it is now. Gives the world's number.
fn begin(state: Shared, _now: Time) : (Shared, Int)
  worlds = state.worlds.set(state.begun, Worlds.begin(state.db))
  (Shared(db: state.db, rows: state.rows, worlds: worlds, begun: state.begun + 1), state.begun)
end

fn named(name: Text, argument: Int) : Result(Worlds.Question, Problem)
  case name
    "row": Ok(Worlds.Row(key: argument))
    "branch_total": Ok(Worlds.BranchTotal(branch: argument))
    "below": Ok(Worlds.Below(amount: argument))
    "bands": Ok(Worlds.Bands(width: argument))
    _: Error(NoQuestion(name))
  end
end

fn opened(state: Shared, number: Int) : Result(Worlds.World, Problem)
  case state.worlds.get(number)
    Some(found): Ok(found)
    None: Error(NoWorld(number))
  end
end

## Asks a question in a world and records the answer there.
fn ask(state: Shared, _now: Time, world: Int, question: Text, argument: Int) : Result(
  (Shared, Worlds.Answer),
  Problem
)
  asking = try opened(state, world)
  wanted = try named(question, argument)
  case Worlds.ask(state.db, asking, Worlds.anywhere?, wanted)
    Error(why): Error(Refused(why))
    Ok((asked, got)): Ok((
      Shared(
        db: state.db,
        rows: state.rows,
        worlds: state.worlds.set(world, asked),
        begun: state.begun
      ),
      got
    ))
  end
end

## Moves money in a world. The main line does not change.
fn move(state: Shared, _now: Time, world: Int, from: Int, to: Int, amount: Int) : Result(
  (Shared, Int),
  Problem
)
  moving = try opened(state, world)
  case Worlds.act(
    state.db,
    moving,
    Worlds.anywhere?,
    Worlds.Move(from: from, to: to, amount: amount)
  )
    Error(why): Error(Refused(why))
    Ok((db, moved)): Ok((
      Shared(db: db, rows: state.rows, worlds: state.worlds.set(world, moved), begun: state.begun),
      moved.steps.size
    ))
  end
end

## Lands a world whole, or sends it back and changes nothing. Gives the main
## line's new version.
fn land(state: Shared, _now: Time, world: Int) : Result((Shared, Int), Problem)
  landing = try opened(state, world)
  case Worlds.land(state.db, landing, Worlds.anywhere?)
    Error(why): Error(Refused(why))
    Ok(db): Ok((
      Shared(db: db, rows: state.rows, worlds: state.worlds.remove(world), begun: state.begun),
      db.main
    ))
  end
end

## Read functions for `mo query`, which runs `FUNCTION(state)` on an exported
## copy of the state, outside the service. They take no other argument, so
## each question's argument is written in.
fn branch_total_3(state: Shared) : Worlds.Answer
  Worlds.answer(state.db.tree, state.db.main, Worlds.anywhere?, Worlds.BranchTotal(branch: 3))
end

fn below_105(state: Shared) : Worlds.Answer
  Worlds.answer(state.db.tree, state.db.main, Worlds.anywhere?, Worlds.Below(amount: 105))
end

fn bands_100(state: Shared) : Worlds.Answer
  Worlds.answer(state.db.tree, state.db.main, Worlds.anywhere?, Worlds.Bands(width: 100))
end

## A world that has asked the three questions and moved 1 from account 0 to
## account 1, and the database it then stands in.
fn asked_and_moved(state: Shared) : Result((Worlds.Db, Worlds.World), Worlds.Refused)
  var world = Worlds.begin(state.db)
  for question in [
    Worlds.BranchTotal(branch: 3),
    Worlds.Below(amount: 105),
    Worlds.Bands(width: 100)
  ]
    (asked, _) = try Worlds.ask(state.db, world, Worlds.anywhere?, question)
    world = asked
  end
  Worlds.act(state.db, world, Worlds.anywhere?, Worlds.Move(from: 0, to: 1, amount: 1))
end

## The cost of a landing is the cost of `landed` less the cost of `prepared`.
fn prepared(state: Shared) : Bool
  asked_and_moved(state) is Ok(_)
end

fn landed(state: Shared) : Bool
  case asked_and_moved(state)
    Ok((db, world)): Worlds.land(db, world, Worlds.anywhere?) is Ok(_)
    Error(_): false
  end
end

## The same rows in Mo's own `Map`. The cost of the sum over it is the cost of
## `plain_summed` less the cost of `plain_built`.
fn plain(state: Shared) : Map(Int, Int)
  Tree.fold(state.db.tree, state.db.main, {}, fn(rows, key, held) rows.set(key, held) end)
end

fn plain_built(state: Shared) : Int
  plain(state).size
end

fn plain_summed(state: Shared) : Int
  var sum = 0
  for (key, held) in plain(state)
    sum = if Worlds.anywhere?(key) and key % Worlds.branches == 3: sum + held else: sum
  end
  sum
end

t0 = Time.parse("2026-01-01T00:00:00Z") or stop "time"

test "through the tools, a world that relied on a branch's total is sent back and nothing changes"
  (grown, _) = grow(Shared(db: Worlds.Db(tree: {}, main: 0), rows: 0, worlds: {}, begun: 0), t0, 30)
  (one, relying) = begin(grown, t0)
  assert ask(one, t0, relying, "branch_total", 3) is Ok((asked, Worlds.Number(339)))
  assert move(asked, t0, relying, 5, 15, 1) is Ok((moved, _))
  (two, other) = begin(moved, t0)
  assert move(two, t0, other, 3, 4, 2) is Ok((left, _))
  assert land(left, t0, other) is Ok((landed, _))
  assert land(landed, t0, relying) == Error(Refused(Worlds.Moved(Worlds.BranchTotal(branch: 3))))
  assert ask(landed, t0, relying, "nothing", 0) == Error(NoQuestion("nothing"))
  assert land(landed, t0, 7) == Error(NoWorld(7))
end
