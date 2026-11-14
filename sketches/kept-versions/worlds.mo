## Worlds on the tree by number. A world is an agent's own version of the
## rows. It costs one number to start, sees its own changes, and lands whole
## or not at all. The rows are balances, and the rule is that their total
## never changes. A landing asks again every question the world asked.
module Worlds
expose Call(..),
Question(..),
Answer(..),
Step(..),
Refused(..),
Db(..),
World(..),
branches,
begin,
answer,
ask,
act,
land,
anywhere?
use Tree

branches = 10

enum Call
  Move(from: Int, to: Int, amount: Int)
  Give(to: Int, amount: Int)
end

## One of a fixed set of read functions, with its argument. An account's
## branch is its number modulo `branches`.
enum Question
  Row(key: Int)
  BranchTotal(branch: Int)
  Below(amount: Int)
  Bands(width: Int)
end

enum Answer
  Number(Int)
  Keys(List(Int))
  Counts(Map(Int, Int))
end

enum Step
  Asked(question: Question, answer: Answer)
  Called(Call)
end

enum Refused
  OutsideView(key: Int)
  Short(key: Int, have: Int, want: Int)
  RuleBroken(step: Int)
  Moved(Question)
end

## `main` is the version that every landed world has changed.
struct Db
  tree: Map(Int, Tree.Node(Int))
  main: Int
end

## `version` is the world's own version, and `steps` is what it asked and did.
struct World
  version: Int
  steps: List(Step)
end

fn begin(db: Db) : World
  World(version: db.main, steps: [])
end

fn balance(db: Db, version: Int, key: Int) : Int
  Tree.get_at(db.tree, version, key) or 0
end

fn total(tree: Map(Int, Tree.Node(Int)), version: Int) : Int
  Tree.fold(tree, version, 0, fn(sum, _key, held) sum + held end)
end

## Answers a question on one version, over the rows the view lets through.
fn answer(tree: Map(Int, Tree.Node(Int)), version: Int, view: fn(Int) : Bool, question: Question) : Answer
  case question
    Row(key: key): Number(Tree.get_at(tree, version, key) or 0)
    BranchTotal(branch: branch): Number(
      Tree.fold(
        tree,
        version,
        0,
        fn(sum, key, held)
          if view(key) and key % branches == branch: sum + held else: sum
        end
      )
    )
    Below(amount: amount): Keys(
      Tree.fold(
        tree,
        version,
        [],
        fn(keys, key, held)
          if view(key) and held < amount: keys.append(key) else: keys
        end
      )
    )
    Bands(width: width): Counts(
      Tree.fold(
        tree,
        version,
        {},
        fn(counts, key, held)
          if view(key): counts.set(held / width, (counts.get(held / width) or 0) + 1) else: counts
        end
      )
    )
  end
end

fn touched(wanted: Call) : List(Int)
  case wanted
    Move(from: a, to: b, amount: _): [a, b]
    Give(to: b, amount: _): [b]
  end
end

## Runs one call on the version being written.
fn apply(tree: Map(Int, Tree.Node(Int)), wanted: Call) : Result(Map(Int, Tree.Node(Int)), Refused)
  case wanted
    Give(to: b, amount: n):
      there = Tree.get(tree, b) or 0
      Ok(Tree.put(tree, b, there + n))
    Move(from: a, to: b, amount: n):
      have = Tree.get(tree, a) or 0
      return Error(Short(key: a, have: have, want: n)) if have < n
      taken = Tree.put(tree, a, have - n)
      there = Tree.get(taken, b) or 0
      Ok(Tree.put(taken, b, there + n))
  end
end

## Asks a question of the world's own version, through its view, and records
## the answer.
fn ask(db: Db, world: World, view: fn(Int) : Bool, question: Question) : Result(
  (World, Answer),
  Refused
)
  case question
    Row(key: key) if not view(key): Error(OutsideView(key: key))
    Row(key: _) | BranchTotal(branch: _) | Below(amount: _) | Bands(width: _):
      got = answer(db.tree, world.version, view, question)
      asked = world.steps.append(Asked(question: question, answer: got))
      Ok((World(version: world.version, steps: asked), got))
  end
end

## Runs a call on the world's own version. The main line does not change.
fn act(db: Db, world: World, view: fn(Int) : Bool, wanted: Call) : Result((Db, World), Refused)
  for key in touched(wanted)
    return Error(OutsideView(key: key)) if not view(key)
  end
  tree = try apply(Tree.open(db.tree, world.version), wanted)
  version = Tree.root(tree)
  Ok((
    Db(tree: tree, main: db.main),
    World(version: version, steps: world.steps.append(Called(wanted)))
  ))
end

## Replays a world on the main line as it is now. Every question is asked
## again and must get the answer it got in the world, and the rule must hold
## after every call. It gives the new database, or the reason and no change.
fn land(db: Db, world: World, view: fn(Int) : Bool) : Result(Db, Refused)
  var tree = Tree.open(db.tree, db.main)
  before = total(tree, db.main)
  var step = 0
  for taken in world.steps
    case taken
      Asked(question: question, answer: got):
        now = answer(tree, Tree.root(tree), view, question)
        return Error(Moved(question)) if now != got
      Called(wanted):
        tree = try apply(tree, wanted)
        return Error(RuleBroken(step: step)) if total(tree, Tree.root(tree)) != before
    end
    step += 1
  end
  Ok(Db(tree: tree, main: Tree.root(tree)))
end

fn start() : Db
  var tree = {}
  for key in 0..8
    tree = Tree.put(tree, key, 10)
  end
  Db(tree: tree, main: Tree.root(tree))
end

## Thirty accounts holding 10 each, so each of the ten branches holds 30.
## One world asks what branch 3 holds and then moves money inside branch 5.
## Before it lands, another world's move lands.
fn after_another_lands(other: Call) : Result(Db, Refused)
  var tree = {}
  for key in 0..30
    tree = Tree.put(tree, key, 10)
  end
  db = Db(tree: tree, main: Tree.root(tree))
  (asked, _) = try ask(db, begin(db), anywhere?, BranchTotal(branch: 3))
  (first, relying) = try act(db, asked, anywhere?, Move(from: 5, to: 15, amount: 1))
  (second, moving) = try act(first, begin(first), anywhere?, other)
  land(try land(second, moving, anywhere?), relying, anywhere?)
end

fn anywhere?(_key: Int) : Bool
  true
end

fn low?(key: Int) : Bool
  key < 4
end

test "a world sees its own change, and the main line does not"
  db = start()
  assert act(db, begin(db), anywhere?, Move(from: 0, to: 1, amount: 3)) is Ok((changed, world))
  assert balance(changed, world.version, 0) == 7
  assert balance(changed, world.version, 1) == 13
  assert balance(changed, changed.main, 0) == 10
  assert changed.main == db.main
end

test "a world's first change costs the nodes on its paths, not a copy"
  db = start()
  assert act(db, begin(db), anywhere?, Move(from: 0, to: 1, amount: 3)) is Ok((changed, _world))
  assert changed.tree.size - db.tree.size <= 12
end

test "two worlds that do not overlap both land, and the old main line can still be read"
  db = start()
  assert act(db, begin(db), anywhere?, Move(from: 0, to: 1, amount: 3)) is Ok((first, left))
  assert act(first, begin(first), anywhere?, Move(from: 2, to: 3, amount: 4)) is Ok((second, right))
  assert land(second, left, anywhere?) is Ok(once)
  assert land(once, right, anywhere?) is Ok(twice)
  assert [0, 1, 2, 3].map(fn(key) balance(twice, twice.main, key) end) == [7, 13, 6, 14]
  assert [0, 1, 2, 3].map(fn(key) balance(twice, db.main, key) end) == [10, 10, 10, 10]
end

test "the second of two overlapping worlds is sent back, and nothing changes"
  db = start()
  assert ask(db, begin(db), anywhere?, Row(key: 0)) is Ok((left, Number(10)))
  assert act(db, left, anywhere?, Move(from: 0, to: 1, amount: 5)) is Ok((first, left_done))
  assert ask(first, begin(first), anywhere?, Row(key: 0)) is Ok((right, Number(10)))
  assert act(first, right, anywhere?, Move(from: 0, to: 2, amount: 4)) is Ok((second, right_done))
  assert land(second, left_done, anywhere?) is Ok(once)
  assert land(once, right_done, anywhere?) == Error(Moved(Row(key: 0)))
  assert balance(once, once.main, 0) == 5
  assert balance(once, once.main, 2) == 10
end

test "a world whose second call breaks the rule lands nothing"
  db = start()
  assert act(db, begin(db), anywhere?, Move(from: 0, to: 1, amount: 1)) is Ok((first, moved))
  assert act(first, moved, anywhere?, Give(to: 2, amount: 5)) is Ok((second, given))
  assert land(second, given, anywhere?) == Error(RuleBroken(step: 1))
  assert balance(second, second.main, 0) == 10
end

test "a view narrows what a world may ask and change"
  db = start()
  assert ask(db, begin(db), low?, Row(key: 5)) == Error(OutsideView(key: 5))
  assert act(db, begin(db), low?, Move(from: 0, to: 5, amount: 1)) == Error(OutsideView(key: 5))
  assert act(db, begin(db), low?, Move(from: 0, to: 3, amount: 1)) is Ok(_)
end

test "a question over every row is answered through the view"
  db = start()
  assert ask(db, begin(db), anywhere?, BranchTotal(branch: 3)) is Ok((_, Number(10)))
  assert ask(db, begin(db), anywhere?, Below(amount: 11)) is Ok((_, Keys([0, 1, 2, 3, 4, 5, 6, 7])))
  assert ask(db, begin(db), low?, Below(amount: 11)) is Ok((_, Keys([0, 1, 2, 3])))
  assert ask(db, begin(db), low?, Bands(width: 10)) is Ok((_, counted))
  assert counted == Counts({1: 4})
end

test "a world that relied on a branch's total is sent back when money has left the branch"
  assert after_another_lands(Move(from: 3, to: 4, amount: 2)) ==
    Error(Moved(BranchTotal(branch: 3)))
end

test "a world lands when rows it read have changed and its answer has not"
  assert after_another_lands(Move(from: 3, to: 13, amount: 2)) is Ok(landed)
  assert [3, 13, 5, 15].map(fn(key) balance(landed, landed.main, key) end) == [8, 12, 9, 11]
end
