# Models

TLA+ models of the design's protocols. Each has its predictions written and committed before the model, and settings that must fail.

Run `python3 models/check.py`, or name one model: `python3 models/check.py worlds`. It needs Java and a TLC jar at `build/tla2tools.jar` or named by `TLA2TOOLS_JAR`. Without the jar it exits 77; a skip is not a pass. The runs here used TLC 2026.11.06 from the `v1.8.0` release of https://github.com/tlaplus/tlaplus, downloaded on 2026-11-14, SHA-256 `e1f11b75c4b5bc4478ba0ac5cb6ae28e40a01b0016bc33e0aa97da22dfdbcd7f`. Mo pins a different digest for the same release name; that release is rebuilt over time.

## Replay

`Replay.tla` models the replay rule from `design-ideas.md` ("Many agents working together"). The predictions are in [replay-predictions.md](replay-predictions.md), committed in `31be56c` before the model existed.

**Result on 2026-11-14: all 48 settings came out as predicted.** Six cases, eight on and off settings of the three mechanisms, each of five properties checked in its own run (240 runs, about two minutes). In 37 settings the main line stays correct; in 11 it does not.

| Case | The function's own check alone | The promises alone | The recorded reads alone | Nothing |
| --- | --- | --- | --- | --- |
| seat | correct | correct | correct | wrong |
| meeting | correct | correct | correct | wrong |
| skew | correct | correct | correct | wrong |
| discount | wrong | wrong | correct | wrong |
| lost update | wrong | wrong | correct | wrong |
| intent | correct | correct | correct, with a needless send-back | correct |

What it shows:

1. The recorded reads alone keep the main line correct in every case.
2. The function's own check and the promises do so only where the mistake breaks a declared rule.
3. A discount worked out from a price that has since changed, and two agents each setting a balance, are caught by nothing but the recorded reads.
4. A call that says what it means ("add 2") needs no mechanism. The recorded reads still send it back, for nothing.
5. Forking again after being sent back never broke the result.

One trace, lost update with everything off: the balance is 2; A forks and decides "set 4"; B forks and decides "set 3"; A lands and the balance is 4; B lands and the balance is 3. Working one after the other they would have reached 5.

**A measurement that failed, kept.** The first run checked all five properties in one TLC run and reported three settings as not predicted: seat, meeting and skew with everything off showed only Serial broken, not the rule. TLC reports the first broken property in a state, and both break in the same state. The runner now checks each property in its own run, and those three settings match the prediction.

**Limits.**

- The model is tiny: 13 to 19 states for each setting, two agents, one call in each world, two tries.
- Serial follows from the recorded reads by the way they are defined. The model's worth is in showing that the function's check and the promises do not give it.
- An agent is modelled as deciding the same call from the same answers. A real agent may not.
- In seat, meeting and skew the function's check tests the same condition the agent decided on. That is why it is enough there.
- A world that only read finishes without a check and counts as having run when it forked.
- Not modelled: a world with more than one call, reads that see the world's own calls, a slow agent sent back for ever, helpers, and taking an agent's work out. The predictions file says what is expected of each.
- There is no implementation to compare the model with.

## Worlds

`Worlds.tla` models a world that holds two calls, and asks what lands together and when the rule is checked. The predictions are in [worlds-predictions.md](worlds-predictions.md), committed in `ee5c636` before the model existed.

**Result on 2026-11-14: all 40 settings came out as predicted.** Six cases, four ways of landing, the recorded reads off, compared with the main line, or run again in place, and each of four properties checked in its own run (160 runs, about a minute and a half). In 26 settings nothing goes wrong on the main line; in 14 something does.

With the recorded reads run again in place:

| Case | Each call by itself, rule after each | World whole, rule at the end | World whole, rule after each | Each call by itself, rule at the end (meant to fail) |
| --- | --- | --- | --- | --- |
| transfer | never lands | correct | never lands | rule broken in between |
| budget | never lands | budget raised | never lands | rule broken in between, budget raised |
| audit | wrong sum recorded | correct | correct | not run, no rule |
| stuck | left half landed | correct | correct | not run, no rule |
| ownread | wrong | correct | correct | not run, no rule |
| apart | correct | correct | correct | not run, no rule |

What it shows:

1. **Each call by itself.** A transfer written as "take" then "put" never lands, because "take" breaks the rule and is refused on every try. Where no rule is declared the two calls land with a gap between them. Another agent read the gap, and in another case the gap stayed open for good. The recorded reads did not close it.
2. **The world whole, rule at the end.** The transfer lands. An agent can also combine two approved calls into a change neither can make. The result keeps the rule and counts as a proper whole world, so nothing in the design catches it.
3. **The world whole, rule after each call.** Nothing went wrong in the six cases. A change whose middle breaks a rule cannot land as two calls. It has to be one approved function.
4. **The recorded reads must be run again in place.** Each read is run at its point in the replay, where it sees the world's own earlier calls. Compared with the main line, a world that read its own change is refused for ever.
5. Under "rule at the end" a write function cannot rely on the rule holding when it starts. "Close" was safe only because spent is never above the budget.

Traces:

- audit, each call by itself: x 2, y 0. A's "take" lands: x 1, y 0. B reads 1 and 0 and writes the sum 1 to z. A's "put" lands: x 1, y 1, z 1. The sum was 2 before and after.
- stuck, each call by itself: A's "take 2" lands: x 0, y 0. B's "put 1" lands: y 1. A's "put 2" is refused on all three tries, because y holds 2 at most. The 2 is gone.
- ownread, each call by itself: A's "add 1" lands: x 1. B sets x to 5. A's second step is sent back, reads 5 and writes 5 to y. No order of whole worlds gives x 5, y 5.
- ownread, world whole, reads off: A forks at x 0 and records "write 1 to y". B lands: x 5. A lands: x 6, y 1.
- budget, world whole, rule at the end: spent 1, budget 2. A's world lands in one step: spent 3, budget 3.

**Checks on the model itself.** The six traces above were read and each fails the way the prediction says. With four tries in place of three the 40 results are the same. The first model, run through the changed runner, still gives 0 of 48 not as predicted.

**Limits.**

- Every prediction matched, so the model confirmed what was expected and did not surprise. The third way of landing came from writing the predictions, not from a run.
- The model is tiny: 4 to 29 states for each run, two agents, two calls in a world, six cases chosen by hand.
- ApprovedOnly is written by hand for one case: the budget is never raised.
- Serial is judged when both agents have finished or given up, on the main line alone. It does not look at states on the way.
- Rule and ApprovedOnly hold under "world whole, rule after each" by the way it is built.
- Not modelled: who should approve a combination of calls, a rule marked as checked at the end of a world, checks made while the agent works in its copy, a long world sent back for ever, and needless send-backs.
- There is no implementation to compare the model with.
