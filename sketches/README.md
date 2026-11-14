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
