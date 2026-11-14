# Sketches

Small Mo programs that check a claim about what Mo can do today. They are not database code and nothing is built on them.

Run one with the `mo` built in `~/code/mo`: `mo test sketches/land-whole/main.mo`.

## land-whole

The claim: a Mo service can land a list of calls whole or not at all, with the rule checked after every call, and Mo needs no change for it.

`land` is one tool. It runs each call on its own copy of the state, checks the rule after each, and returns the new state or a failure. A tool that returns a failure changes nothing.

Result on 2026-11-14, with `mo` 0.2.0 as built in `~/code/mo` that day, minutes after commit `51121de6`: `5 passed, 0 failed, 0 stopped`. That is three tests, the promise "the total never changes" on generated sequences of landings, and the recovery check.

The control: delete the line that returns `RuleBroken` and run again. It must fail, and did: `3 passed, 2 failed, 0 stopped`, with `mo test` reporting that `land([Take(1)])` broke the promise.

What it does not show: forks, recorded reads, or a replay on a main line that has moved. The rule is written twice, as the promise and as the function `rule?`, because a promise is checked by `mo test` and cannot be called when a write lands.
