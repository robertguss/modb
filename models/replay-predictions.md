# Predictions for the replay model

Written on 2026-11-14, before the model exists. The model and what it showed go in `README.md` beside this file. A prediction that fails stays here and is marked as failed.

## What is modelled

- One main line holding two numbers, and two agents, A and B.
- An agent forks a world. It reads, and the answers are recorded. It decides one call from those answers. It lands by having that call replayed on the main line as the main line then is.
- Three mechanisms, each of which can be switched off:
  - **F**, the write function's own check, run at replay;
  - **P**, the promises, checked on the result of the call;
  - **R**, the recorded reads: the agent's reads are run again at landing, and a different answer sends the world back.
- An agent that is refused or sent back may fork again, twice at most.
- An agent decides the same way from the same answers.

## Properties

- **Serial.** Every call that lands is the call its agent would have chosen had it read the main line at that moment. The main line is then what the agents would have produced working one after another.
- **Rule.** The case's own rule holds on the main line.
- **NoNeedlessSendBack.** No world is sent back by R when its agent would have chosen the same call anyway.
- **CanFinish.** Both agents can finish. This guards against a model in which nothing can happen.

## The six cases

| Case | The mistake | Rule |
| --- | --- | --- |
| seat | Two agents book the last seat | Bookings never exceed seats |
| meeting | One agent moves a meeting's start, the other its end | A meeting starts before it ends |
| skew | Two people on call each leave because the other is on call | Someone is always on call |
| discount | One agent works out a discount from a price that the other changes | None declared |
| lost update | Both agents read a balance and set it to what they worked out | None declared |
| intent | Both agents add to a balance by a call that says "add", having read it first | None declared |

The first, second and fourth are the three cases the survey says merges get wrong ([merging by meaning](../wiki/ideas/merging-by-meaning.md)).

## Predictions

1. **Which mechanism catches which case.**

   | Case | F | P | R |
   | --- | --- | --- | --- |
   | seat | yes | yes | yes |
   | meeting | yes | yes | yes |
   | skew | yes | yes | yes |
   | discount | no | no | yes |
   | lost update | no | no | yes |
   | intent | nothing to catch | nothing to catch | nothing to catch |

   For every case and every one of the eight on and off settings, Serial and Rule both hold exactly when at least one mechanism that is switched on has "yes" for that case. For intent they always hold. That is 48 runs: 37 hold and 11 fail.
2. **Which property fails.** For seat, meeting and skew with everything off, both Rule and Serial fail. For discount and lost update without R, Serial fails and Rule holds.
3. **NoNeedlessSendBack fails in intent whenever R is on,** and holds in the other 44 runs.
4. **CanFinish** is reachable in all 48 runs.
5. **What this adds up to.** R alone is enough for all six cases. F and P are enough only where the mistake breaks a declared rule. The recorded reads carry the weight. F and P are worth having for the reason they give the agent and for calls made without reading.

## Where I am least sure

- Whether forking again after being sent back can break Serial. I predict it cannot.
- Whether intent truly needs no mechanism. I predict it does not.
- Serial follows from R by the way R is built, so the R runs cannot surprise. The property's worth is in showing that F and P do not give it.

## Not in this model, with what I expect

- **A world with more than one call.** I expect that promises cannot be checked after each replayed call: a transfer written as two calls breaks "the total stays the same" in between. Either a world lands whole with promises checked at its end, or whatever must land whole has to be one write function. `design-ideas.md` says promises "are checked after every replayed call". This needs its own model.
- Reads that see the world's own earlier calls.
- A slow agent sent back for ever.
- A helper's world inside an agent's world.
- Taking one agent's work back out.
- An agent that decides differently from the same answers, as a real agent may.
- What a cell-by-cell merge does. The survey covers it.
