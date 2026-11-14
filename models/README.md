# Models

TLA+ models of the design's protocols. Each has its predictions written and committed before the model, and settings that must fail.

Run `python3 models/check.py`. It needs Java and a TLC jar at `build/tla2tools.jar` or named by `TLA2TOOLS_JAR`. Without the jar it exits 77; a skip is not a pass. The runs here used TLC 2026.11.06 from the `v1.8.0` release of https://github.com/tlaplus/tlaplus, downloaded on 2026-11-14, SHA-256 `e1f11b75c4b5bc4478ba0ac5cb6ae28e40a01b0016bc33e0aa97da22dfdbcd7f`. Mo pins a different digest for the same release name; that release is rebuilt over time.

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
