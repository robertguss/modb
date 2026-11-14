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

Result on 2026-11-14, with `mo` 0.2.0 built from commit `ef37424`: `12 passed, 0 failed, 0 stopped`. That is six tests of the tree and six of the worlds.

Two controls, each of which must fail and did:

- In `land`, replace the `Asked` arm with `Asked(key: _, answer: _): continue`, so a landing no longer checks the questions a world asked. `11 passed, 1 failed`: the second of two overlapping worlds lands.
- In `open` in `tree.mo`, write `frozen: 1` in place of `frozen: next`, so no node is ever kept. `5 passed, 7 failed`: kept versions change under a later write.

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

What it does not show: freeing the nodes of a version nobody keeps, removing a row, the worlds running as a service, or a tree tuned for speed.
