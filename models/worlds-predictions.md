# Predictions for the worlds model

Written on 2026-11-14, before the model exists. The model and what it showed go in `README.md` beside this file. A prediction that fails stays here and is marked as failed.

## The question

A world is an agent's own copy of the data. A call is one use of an approved write function. When a world holds more than one call, what lands together, and when is the rule checked?

## What is modelled

- One main line holding three numbers, x, y and z, and two agents, A and B.
- Each agent has a fixed program of at most two steps. A step may read, and then makes one call. A later step reads the agent's own world, so it sees the agent's earlier calls.
- A world records, for each step, the answers read and the call made.
- Landing has two switches.
  - **Unit.** `call`: each call lands by itself, in order, and another agent's call may land in between. `world`: every call in the world lands in one step, or none does.
  - **Check.** `each`: the rule is checked after every call. `end`: the rule is checked once, after the world's last call.

  | Unit | Check | What it is |
  | --- | --- | --- |
  | call | each | The call is the unit. This is a Mo service today. |
  | world | end | The world is the unit, as a transaction is in an ordinary database. |
  | world | each | The world lands whole and the rule is still checked after every call. |
  | call | end | Each call lands by itself and the rule waits for the last one. Meant to fail. |

- The write function's own check always runs at replay.
- The recorded reads have three settings.
  - `off`.
  - `main`: every recorded answer is compared with the main line as it is before the replay starts.
  - `inplace`: each step's read is run again at its place in the replay, on the main line plus the world's own earlier calls.

  Under the call unit a call's reads are run again on the main line when that call lands. `main` and `inplace` are then the same, so one is run.
- An agent that is refused or sent back may fork again, three tries in all. Under the call unit the calls that already landed stay landed, and the agent carries on from the step that was refused.
- An agent decides the same way from the same answers.

## Properties

- **Rule.** The case's own rule holds on the main line in every state.
- **Serial.** When both agents have finished or given up, the main line is a state that whole worlds landing one after another could have produced: neither world, A's alone, B's alone, A's then B's, or B's then A's. A world left half landed fails this.
- **ApprovedOnly.** The main line never holds what single approved calls, each checked by itself, could not have produced. Only the budget case has such a state.
- **BothFinish.** Both agents can finish. Where the prediction is "no", an agent is refused every time it tries.

## The six cases

| Case | A's world | B's world | Rule | Start |
| --- | --- | --- | --- | --- |
| transfer | take 1 from x; put 1 on y | nothing | x and y together stay 2 | x 2, y 0 |
| budget | spend 2; close | nothing | spent (x) never exceeds the budget (y) | x 1, y 2 |
| audit | take 1 from x; put 1 on y | read x and y, write their sum to z | none declared | x 2, y 0 |
| stuck | take 2 from x; put 2 on y, which may hold 2 at most | put 1 on y | none declared | x 2, y 0 |
| ownread | add 1 to x; read x and write it to y | set x to 5 | none declared | x 0, y 0 |
| apart | add 1 to x; add 1 to y | add 1 to x | none declared | x 0, y 0 |

In budget, "close" sets the budget to what was spent. Each call is safe by itself. A "spend" that goes over the budget is refused by the rule. "Close" can only lower the budget, because spent is never above it when the rule holds. Together they are not safe: "spend 2" takes spent to 3, above the budget of 2, and "close" then raises the budget to 3.

## Predictions

1. **What each way of landing does**, with the recorded reads `inplace`.

   | Case | call, each | world, end | world, each | call, end (meant to fail) |
   | --- | --- | --- | --- | --- |
   | transfer | never lands | lands, correct | never lands | lands; Rule fails in between |
   | budget | never lands | lands; ApprovedOnly fails | never lands | lands; Rule and ApprovedOnly fail |
   | audit | Serial fails | correct | correct | Serial fails |
   | stuck | Serial fails | correct | correct | Serial fails |
   | ownread | Serial fails | correct | correct | Serial fails |
   | apart | correct | correct | correct | correct |

   - audit under the call unit: B reads between "take" and "put" and writes a sum of 1. The true sum is 2 at all times.
   - stuck under the call unit: "take" lands, B's "put" lands, and A's "put" is refused for ever. The 2 that A took is gone.
   - ownread under the call unit: A's "add" lands, B sets x to 5, A's second step is sent back, reads 5 and writes 5 to y. No order of whole worlds gives x 5 and y 5.
   - "Never lands" means A is refused on every try, because "take" or "spend" breaks the rule the moment it is checked.
2. **The recorded reads.**
   - ownread under the world unit: `off`, Serial fails; `main`, A can never land, because its second read saw its own "add" and the main line never shows that; `inplace`, correct.
   - ownread under the call unit: Serial fails with the reads on or off.
   - audit under the world unit is correct with the reads off, `main` or `inplace`, because B can never see the middle.
   - transfer, budget, stuck and apart read nothing, so the setting changes nothing.
3. **BothFinish** is "no" in transfer and budget whenever Check is `each`, in stuck always (y cannot hold both puts), and in ownread under the world unit with `main`. It is "yes" in every other setting.
4. **Count.** Transfer and budget run under both checks; the four cases with no rule run under `each` alone, since the checks cannot differ. That is 40 settings. Rule, Serial and ApprovedOnly all hold in 26 and at least one fails in 14.

   | Case | Settings | All hold | One fails |
   | --- | --- | --- | --- |
   | transfer | 10 | 8 | 2 |
   | budget | 10 | 5 | 5 |
   | audit | 5 | 3 | 2 |
   | stuck | 5 | 3 | 2 |
   | ownread | 5 | 2 | 3 |
   | apart | 5 | 5 | 0 |
5. **What this adds up to.**
   - The call is the unit: a change that needs two calls is refused for ever when its middle breaks a declared rule. When its middle breaks none, it lands with a gap that another agent can read, or that stays open for good. The recorded reads do not close the gap.
   - The world is the unit with the rule at the end: the transfer works. An agent can also combine approved calls into a change that no approved call could make, and Serial cannot see it.
   - The world lands whole with the rule after every call: nothing goes wrong in these cases. The price is that a change whose middle breaks a rule must be one approved function.
   - The recorded reads must be run again in place. Comparing them with the main line refuses every world that read its own change.

## Where I am least sure

- ownread under the call unit with the reads on. The prediction rests on the agent carrying on from the refused step. If that reasoning is wrong, it shows here.
- Whether three tries are enough that no agent gives up only for want of tries. B lands one call at most, so it can send A back once. A lands two calls at most, so it can send B back twice. The model is run again with four tries, and I predict the same results.
- budget with the world as the unit and the rule at the end. I predict Serial holds there and only ApprovedOnly fails.
- Rule and ApprovedOnly hold under "world, each" by the way it is built. Serial is the real test of it.

## Not in this model, with what I expect

- Whether a person should have to approve a combination of calls. The model shows what a combination can do, not who should allow it.
- A rule marked by the person as "checked at the end of a world", rule by rule. SQL databases have this as deferred constraints (from memory, not checked). It would put the choice in the person's hands for each rule.
- Checks made while the agent works in its own copy. Here they are made at landing only.
- A slow agent with a long world sent back for ever. A longer world reads more, so I expect it to be sent back more often.
- Needless send-backs. The first model counted them.
- Helpers, taking an agent's work out, and an agent that decides differently from the same answers.
