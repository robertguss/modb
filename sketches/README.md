# Sketches

Small Mo programs that check a claim about what Mo can do today, and scripts that measure it. They are not database code and nothing is built on them.

Run one with the `mo` built in `~/code/mo`: `mo test sketches/land-whole/main.mo`.

## land-whole

The claim: a Mo service can land a list of calls whole or not at all, with the rule checked after every call, and Mo needs no change for it.

`land` is one tool. It runs each call on its own copy of the state, checks the rule after each, and returns the new state or a failure. A tool that returns a failure changes nothing.

Result on 2026-11-14, with `mo` 0.2.0 as built in `~/code/mo` that day, minutes after commit `51121de6`: `5 passed, 0 failed, 0 stopped`. That is three tests, the promise "the total never changes" on generated sequences of landings, and the recovery check.

The control: delete the line that returns `RuleBroken` and run again. It must fail, and did: `3 passed, 2 failed, 0 stopped`, with `mo test` reporting that `land([Take(1)])` broke the promise.

What it does not show: forks, recorded reads, or a replay on a main line that has moved. The rule is written twice, as the promise and as the function `rule?`, because a promise is checked by `mo test` and cannot be called when a write lands.

## service-timing

Not a claim but a measurement, for [How fast and how large is a Mo service today?](../issues/11-how-fast-and-large-is-a-mo-service.md). The numbers and what they mean are in that ticket's answer.

`main.mo` is a service whose state is a map of numbered rows, each 64 bytes of text. The scripts start it with `mo serve`, call it over loopback and time each call from the client. They write to `build/service-timing/`, which git ignores.

Use an optimised `mo`. Mo's own benchmark builds one this way, from the Mo repository:

```sh
make -j8 CC=gcc BUILD=build/bench-release DEBUG='-O2 -g -pthread' build/bench-release/debug/mo
```

Then, from this repository, with `MO` the path of that binary:

```sh
python3 sketches/service-timing/measure.py $MO 0,1000,10000,50000,100000   # time reads and writes at each size
python3 sketches/service-timing/ceiling.py $MO                            # the largest state that takes a write, snapshots, restart
python3 sketches/service-timing/waits.py $MO                              # does a read wait behind a write; run after ceiling.py
python3 sketches/service-timing/breakdown.py $MO 300 120                  # where a call's time goes
python3 sketches/service-timing/yardstick.py 1,1000,10000,50000,100000,1000000,10000000
```

`breakdown.py` reads the server's processor time for each kind of call from `/proc`. It then stops the service with `gdb` 300 times while reads run and 120 times while writes run, and counts the share of busy samples each function is in. `perf` has no build for this machine's kernel. It takes about a quarter of an hour.

`yardstick.py` does not use Mo. It does the same job with SQLite inside one Python process: one table of numbered rows of 64 bytes, read one row, change one row and commit. It uses the settings Mo's store uses (`src/host/store.c` in `~/code/mo`), so each commit is synced to disk. There is no web request around it, so its times are a floor to compare against, not a like-for-like figure.

Run them on a quiet machine. The first recorded runs were not: another session was building on the same machine. The ticket marks which numbers came from which run.

## kept-versions

The claim, for [Can a Mo library keep old versions cheaply today?](../issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md): a collection written in Mo can keep an old version for the cost of a few nodes, and the saving survives a save and a restart, with no change to Mo. The numbers and what they mean are in that ticket's answer.

`tree.mo` is the collection: numbered rows in a tree whose nodes sit in one map and name their children by number. `worlds.mo` runs a small workload on it: a world is an agent's own version, a view narrows what it may touch, and a landing takes all of a world or none of it.

```sh
mo test sketches/kept-versions/worlds.mo
```

Result on 2026-11-14, with `mo` 0.2.0 built from commit `ef37424`: `16 passed, 0 failed, 0 stopped`. That is seven tests of the tree and nine of the worlds. Three of the worlds' tests and one of the tree's came with the slice below; before it the count was 12.

Two controls, each of which must fail and did:

- In `land`, replace the `Asked` arm with `Asked(question: _, answer: _): continue` and name the view `_view`, so a landing no longer asks a world's questions again. `14 passed, 2 failed`: the second of two overlapping worlds lands, and so does a world that relied on a total that has changed.
- In `open` in `tree.mo`, write `frozen: 1` in place of `frozen: next`, so no node is ever kept. `8 passed, 8 failed`: kept versions change under a later write.

Three services hold the same rows and keep the version before every `put`. `mo test` on each passes Mo's own recovery check.

| File | How it keeps a version |
| --- | --- |
| `by-number.mo` | The tree in `tree.mo` |
| `by-reference.mo` | The same tree with each node holding its children directly. The control for saved size: it must grow by a full copy for each version, and did |
| `whole-maps.mo` | One whole `Map` for each version, as a program does today |

With `MO` the optimised `mo` described under service-timing:

```sh
python3 sketches/kept-versions/versions.py $MO 1000,10000,50000 10,100   # saved size and write time as versions are kept
python3 sketches/kept-versions/ops.py $MO 20000,60000                    # one insert and one lookup against Map, outside a service
```

`versions.py` grows each service to each number of rows, calls `put` until 10 and then 100 versions are kept, and reads the saved size from `mo-memory` at each point. It then restarts the service and reads a row of the oldest version. It also runs the plain map from service-timing, which keeps no version, to compare the time of a write. It writes to `build/kept-versions/`, which git ignores.

`in-place.mo` checks a second claim that the sketch ran into: Mo copies a map that sits in a record every time the map changes. It adds rows to a map six ways.

```sh
time $MO run sketches/kept-versions/in-place.mo field 40000   # or local, take, apart, bare, pair
```

A way that changes the map in place takes the same time at 20,000 and 40,000 rows. A way that copies it takes four times as long for twice the rows. `local`, `field`, `take` and `apart` copy; `bare` and `pair` do not. `local` is the form Mo's reference gives for changing a record's field. This is why the tree is a bare map and not a record.

What it does not show: freeing the nodes of a version nobody keeps, removing a row, or a tree tuned for speed.

## kept-versions: questions asked again at landing

The first vertical slice, for [Can a landing ask an agent's questions again inside one call?](../issues/39-can-a-landing-ask-an-agents-questions-again.md). The claim: a landing can ask again every question a world asked, by its answer, with no change to Mo. The question it measures: up to how many rows that fits in one call to a service. The numbers and what they mean are in that ticket's answer.

It extends the sketch above and adds no second copy of it.

| File | What the slice added |
| --- | --- |
| `tree.mo` | `fold`, which visits every row of a version without building a list |
| `worlds.mo` | Three questions that read every row: what a branch holds, the accounts holding less than an amount, and how many accounts fall in each band of balances. `ask` records the question and its answer. `land` asks each again and sends the world back when an answer differs |
| `asked-again.mo` | The worlds as a service. The open worlds, with their questions and answers, are in its state. The tools are `grow`, `begin`, `ask`, `move` and `land`. It also holds the read functions that `mo query` runs |
| `asked-again.py` | The measurement |

```sh
mo test sketches/kept-versions/asked-again.mo
```

Result on 2026-11-14, with `mo` 0.2.0 built from commit `ef37424`: `18 passed, 0 failed, 0 stopped`. That is the 16 above, one test that works the service's tools, and Mo's own recovery check on the service.

The control that must fail: the first one above, run on `asked-again.mo`. `15 passed, 3 failed`: a world that relied on a branch's total lands after money has left that branch, in the worlds and through the service's tools.

With `MO` the optimised `mo` described under service-timing:

```sh
python3 sketches/kept-versions/asked-again.py $MO 1000,10000,50000
```

It grows the service through a ladder of sizes, every 100 rows to 2,000 and every 500 to 12,000, then the sizes given. At each size it opens worlds and tries five things in one call each: each question alone, a landing with one question and one move, and a landing with three questions and one move. It records which are refused with `work_limit`. A thing that was refused at a smaller size is tried again only at the sizes given.

At each size given it fetches an export of the state with `mo fetch` and runs each read function through `mo query`. `mo query --max-work N` stops a function after N instructions, so the script halves the range until it has the smallest N at which the function finishes. That is the function's exact cost. It writes to `build/asked-again/`, which git ignores. A run takes about ten minutes.

The script waits 16 seconds after every refused call. Five failures within a minute restart a Mo service and three restarts within ten minutes stop it, and a call refused for its limit counts as a failure. The first run did not wait, and the service stopped at 4,500 rows.

Two runs on 2026-11-14 gave the same instruction counts to the instruction, and the same sizes at which each thing stopped fitting. The times differ between the runs, because another session was building on the same machine.

What it does not show: two agents at once, real data, a question a person did not write into the program beforehand, or a view narrower than everything inside the service. The ticket's answer lists what each stands in for.

## shape-census

Not a claim but a count, for experiment 1 in [experiments.md](../experiments.md): of the Mo code agents have already written that picks rows from a collection, how much is in a shape a compiler could turn into an index lookup. The result and what it means are there.

```sh
python3 sketches/shape-census/census.py ~/code/mo/learnability sketches/kept-versions sketches/land-whole sketches/service-timing
```

`census.py` reads Mo source as text, by its indentation. It is not a compiler. A site is one of two things:

- a call of `filter`, `find`, `count` or `any?` that is given a function;
- a `for` loop over a collection whose body tests the loop's own row in an `if`.

A site is in a shape when its test compares a stored field of the row, or the row itself, with a value that does not depend on the row, by `==`, `<`, `<=`, `>` or `>=`. Other tests may be joined to it with `and`. A field counts as stored when a `struct` in the same folder declares it. A loop is in a shape only when its body is that one `if` and nothing else.

Everything else is a miss: a named function as the test, a call or arithmetic on the row, two fields of the same row, `!=`, `not`, `or`, and a loop that does more than the one `if`.

It counts each distinct file once, and reports distinct sites first, because the corpus holds many copies of the same task.

The controls run before every count. `controls/misses/` holds ten filters hidden in helpers, key arithmetic and loops that do more; all ten must be found and none recognised. `controls/hits/` holds eight plain shapes; all eight must be recognised. Both files pass `mo check`.

What it does not count: `while` loops, `all?`, a loop that reads its row with `case`, and loops over a range or a written-out list. It writes every site to `build/shape-census/`, which git ignores.

## enforcement-trial

Not a claim but a trial, for experiment 4 in [experiments.md](../experiments.md): fresh agent sessions write ten read functions over a four-table shop under two rules. The design is in [freeze.md](enforcement-trial/freeze.md), which was committed before the first session. The result is in `experiments.md` and the sessions' answers are in `enforcement-trial/results/`.

| File | What it is |
| --- | --- |
| `rows.mo`, `shop-a.head.mo`, `shop-g.head.mo` | The shop's rows, and the store in each arm. A session's `shop.mo` is one head followed by the rows |
| `STORE-a.md`, `STORE-g.md`, `PROMPT.md`, `tasks.py` | What a session reads: the store's page, the prompt, and each task with its example |
| `rule.py` | Arm A's rule, standing in for a compiler. It uses `../shape-census/census.py` |
| `mo.py` | The `mo` a session runs. It records every check and test with a copy of `answer.mo`, and in arm A applies the rule |
| `reference-a.mo`, `reference-g.mo` | An answer to every task in each arm, which the hidden tests compare against |
| `trial.py` | `selfcheck`, `setup` and `grade` |

```sh
cp $MO build/enforcement-trial/mo
python3 sketches/enforcement-trial/trial.py selfcheck   # the controls
python3 sketches/enforcement-trial/trial.py setup       # one folder for each session, under build/
python3 sketches/enforcement-trial/trial.py grade       # after the sessions have run
```

Each session is then started by hand with the text in its `prompt.txt`.

The controls, all in `selfcheck`, which passed on 2026-11-14 before the freeze:

- The 22 reference answers pass their hidden tests, and the two arms print the same 803 answers.
- Three planted wrong answers must fail the hidden tests: one that picks the wrong orders, one off by one on a range, and one that drops the rule for orders placed on the same day.
- The eleven slow reads in `controls/slow-a.mo` pass `mo check` and must each be refused by arm A's rule.
- A read that reaches inside a table must be refused in arm G.

A known fault in `rule.py`, found in the trial and left as it was: a call whose function is wrapped onto its own line, as `filter(` then `fn(order) ... end` then `)`, is refused though it is in a shape. It happened once in 20 sessions.

## instruction-counts

The claim under test, for experiment 5 in [experiments.md](../experiments.md): the count of instructions a read runs tells a walk of the whole store from an indexed read. The result is there.

`main.mo` is a service that holds orders in a `Map`, a list of their numbers, and two indexes kept as maps: `by_buyer`, where every buyer has ten orders whatever the size, and `by_band`, where each of ten bands holds a tenth of all orders. It has ten read functions: three through an index, two walks written in Mo, and five walks done inside one built-in each (`values`, `keys`, `contains?`, `reverse`, `unique`).

```sh
mo test sketches/instruction-counts/main.mo --only Main.test.1
python3 sketches/instruction-counts/measure.py $MO 1000,4000
```

Result of the test on 2026-11-14: `1 passed, 0 failed, 0 stopped`. It checks that the index gives the walk's answer. Mo's own recovery check on this service was stopped after three minutes without an answer and has not been run to its end.

`measure.py` grows the service to each size, fetches an export and finds each read's exact cost with `mo query --max-work`, as `asked-again.py` does and with its code. It checks that the indexed read and both Mo walks give the same answer at each size. The control that must hold: the walk written as a Mo loop grows in step with the store. A run takes a minute and a half. The counts do not depend on how busy the machine is.

## planner

The claim under test, for experiments 8 to 14 in [experiments.md](../experiments.md): a compiler can plan ordinary Mo reads over stored tables, working out for itself which indexes and which answers to keep, including answers that span tables. The results are there.

`core.py` reads the Mo Core that `mo check --emit=core` prints and runs it, over tables that hold their own indexes. It can stop a run at a cut, put a kept value in at a cut, and record what a run read. `plan.py` finds every table read in a function and gives the function a class: by key, looked up, kept or walked. A read is kept when it goes over one table once and its work for each row is separate; `cut_of` finds where that work ends. `planner.py` takes the plain-Mo reads agents wrote in the enforcement trial, plans them, applies random writes and calls of the write functions agents wrote in `write-trial`, and at each checkpoint runs the same functions in real Mo on the same rows and compares every answer. A kept answer is held in parts, one for each row, with a record of what each part read, so a write to another table redoes only the parts that read what it touched, and a write redoes a read's parts only when it changed a field the read reads. A loop inside a loop gets a part for each pair of rows, and a test that only asks whether any row matches is answered from the index. A part does no lookup by key. It stops at its first one and waits, and the rest runs when the read is asked. Waiting parts that agree on every field the rest reads share one kept entry with a count, where the code sorts the list before any other use or the answer is a number. Where a list's order counts, the part does its own lookups and the whole answer is kept. A read that walks a table its code does not pass through `walk` is refused. From the plan alone, before any row is read, the script flags each table a write to which must redo one part for every row that names the written row: where a part looks that table up by key itself, or where a part is a pair whose outer row is from that table. The report gives, for writes to each table, the reads that cause a flag and the upkeep measured at both store sizes. For each write function it gives, from its Mo Core, the fields it can change, whether it is flagged and by which reads, and its upkeep at both sizes. `controls/moved.mo` holds one planted write, which gives an order to another customer. `controls/planted.mo` holds ten reads written to test the rule: three that must not be kept, four that span tables, one whose test goes beyond its index, one that gives names in table order and must not be grouped, and one that walks without saying `walk` and must be refused.

```sh
python3 sketches/planner/planner.py
```

It takes about twenty-five minutes and writes `build/planner/report.txt`; the reports of the recorded runs are `results/report-8.txt` to `report-14.txt`. The script as it ran for experiment 8 is at commit `f55a416`, for experiment 9 at `595dca7`, for experiment 10 at `6cb7e39`, for experiment 11 at `8eda276`, for experiment 12 at `0782258` and for experiment 13 at `9015185` and for experiment 14 at `aa0f07b`. It ends with sixteen checks that must hold: every answer is Mo's, under random writes and under write functions, every write function runs without a fault, upkeep skipped when an order's customer changes spoils only reads that read it, skipped upkeep spoils kept answers only, upkeep skipped after a write to another table spoils only answers that span tables, a dropped test is caught, a dropped notice that an index entry emptied or filled spoils only the reads that ask whether any row matches, lookups never done again spoil exactly the reads that wait at a lookup, grouping a list whose order counts spoils exactly that read, grouping on no fields spoils exactly the grouped reads, every `mentions` is walked, the three planted reads that must not be kept are not, the planted read that leans on order shows it, only the planted walk that does not say `walk` is refused, and the write test that counts lookups by key alone misses a write that grows.

Known limits: one Mo function can hold only so many rows (E1153), so the rows are written 400 to a function. The script knows only the Mo Core forms and built-in steps these reads use, and stops with the name of any other. A part is worked out again when something it read changes; no arithmetic is done on it. A part waits at its first lookup, whichever lookup fans out, and nothing is totalled before a lookup. The write test sees a shape, not how many rows share it, and it does not look at a part that reads an index by something other than its row's key or reads a whole table.

## write-trial

The sessions of experiment 14 in [experiments.md](../experiments.md): fresh agents write the functions that change the shop, choosing the changes themselves and told nothing of kept answers. `PROMPT.md` and `TASK.md` are what each session got, with the store of the enforcement trial. `setup.py setup` makes four session folders under `build/write-trial/`; `setup.py collect` copies what each left into `results/`, as `writes-<session>-<model>.mo` with its tests beside it. The planner reads the functions from there.

## store-census

Experiment 15 in [experiments.md](../experiments.md), Decision 2. `census.py` labels every Mo file under `~/code/mo/examples/`, `services/` and `learnability/` that declares a service: does its state hold a collection, does a handler add to it, does it want history. `controls/` holds three planted services that must come out as planted. `python3 census.py` is the run as committed; `--siblings` also expands types declared in sibling modules. Results in `results/`. The check for growth reads only a handler's own body, so it misses work passed to another module; the result says how much that cost.


## store-policy

Experiment 16 in [experiments.md](../experiments.md), Decision 2. The claim: the store's policy can be Mo code written once, over a collection it never looks inside, and run unchanged whether the nodes sit in a value or behind a capability.

| File | What it is |
| --- | --- |
| `nodes.mo` | The collection: numbered rows in a tree of nodes named by number. Every write copies the path and gives a new root. It reaches its nodes through `Ops(S)`, a record of three functions |
| `policy.mo` | The policy: the root being written, holders, a log of calls, a sweep that frees what no holder reaches, and a replay |
| `backend-a.mo` | The store is a `Map`. A service holds it, with a step promise |
| `backend-b.mo` | The store is a `Files`. One text file for each node, and the log in a file |
| `story.mo` | One fixed list of calls, and what they must give, used over both backends |
| `control-b-service.mo` | A service whose state holds a `Files`. `mo check` must refuse it |

With `MO` the frozen `mo` at `build/enforcement-trial/mo`:

```sh
$MO test sketches/store-policy/backend-b.mo    # both backends
python3 sketches/store-policy/count.py         # lines, and what the policy calls
python3 sketches/store-policy/control.py       # the two controls
```

Result on 2026-11-16: `7 passed, 0 failed, 0 stopped`. The policy is 90 lines of code and calls four things: `read`, `write` and `children` from `nodes.mo`, and `remove`.

Two controls, each of which must fail and did:

- `control.py` copies the folder to `build/store-policy-control/` and makes the sweep start from the root being written only. `3 passed, 4 failed`: Mo finds put, hold, put, sweep over both backends.
- `mo check` on `control-b-service.mo` gives E0104.

What it does not show: any cost, a crash inside a write, names by hash, or a function value that captures the store.

## log-cost

Not a claim but a measurement, for experiment 19 in [experiments.md](../experiments.md): how many bytes a logged call takes in a Mo store, and how long a call takes to run again at recovery. The numbers and what they mean are in that experiment's result.

`main.mo` is the service of `service-timing` with one more tool, `refuse`, which returns an error. The scripts write to `build/log-cost/`, which git ignores.

```sh
python3 sketches/log-cost/cost.py $MO 1,1000,10000,50000 15   # bytes of a log row; processor time of 15 starts with 0 and with 99 rows in the log
python3 sketches/log-cost/live.py $MO 10000                   # processor time of a live put and get; run after cost.py at that size
```

`cost.py` kills the service to leave a known number of rows in the log, and reads the store's file from a copy. A start is timed until the service has answered one `get`.
