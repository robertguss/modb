# Can a landing ask an agent's questions again inside one call?

Type: prototype
Status: resolved

## Question

AFK, by Robert's decision on 2026-11-14. Asked "Shall the first slice be 'questions asked again at landing', on made-up rows?", he answered "Yes". This is the first vertical slice. All three council reviewers put it first on [Which vertical slices, in what order, and what must each show?](38-which-vertical-slices-in-what-order.md).

Robert decided that when a world lands, every question its agent asked counts, by its answer. The only test of that rule so far asks for single rows, which cost almost nothing to ask again. A sum, a filter or a count reads every row. A landing runs inside one call to a service, and a call may run 1,048,576 instructions (`MO_LIMIT_SERVICE_WORK` in Mo's `src/base/limits.h`). Does asking again fit?

The slice, from top to bottom:

- **What the agent does.** In its own world it asks three questions that read every row: a sum, a filter and a count by group. Then it moves money.
- **The rule that guards it.** At landing each recorded question is asked again on the main line as it then stands. An answer that differs sends the world back, and nothing changes. The rule that the total never changes is still checked after every call.
- **How the data is kept.** The tree by number from [Can a Mo library keep old versions cheaply today?](37-can-a-mo-library-keep-old-versions-cheaply-today.md), held in a running service. The open worlds, with the questions they asked and the answers they got, are in the service's state.

The rows are made up: numbered accounts, each holding a balance. An account's branch is its number modulo 10. The three questions are the total a branch holds, the accounts holding less than a given amount, and how many accounts fall in each band of balances.

It extends `sketches/kept-versions/`. Three things are measured at 1,000, 10,000 and 50,000 rows:

1. The instructions each question takes. `mo query` stops a function at a chosen number of instructions (`--max-work`), so the smallest number at which a question finishes is its exact cost.
2. Whether a landing fits in one call of a running service, and the largest number of rows at which it does.
3. The time each question takes through `mo query` on an exported copy of the state.

Two controls:

- **Must be sent back.** A world that relied on a branch's total, after another world has moved money out of that branch.
- **Must fail.** With the check of questions taken out of `land`, the test above must fail: the stale world lands.

## Predictions, written before any code ran

1. **What one question costs.** The sum costs between 120 and 300 instructions for each row. The filter costs within a quarter of the sum. The count by group costs between 1.3 and 2 times the sum.
2. **One question in one call.** One sum alone fits in a call at 1,000 rows and does not fit at 10,000 or 50,000. The largest size at which it fits is between 3,500 and 8,700 rows.
3. **A landing in one call.** A landing that asks the three questions again and makes one move reads every row five times: three questions, and the rule's total before and after the move. The largest size at which it fits is between 600 and 1,600 rows. It is refused at 10,000 and 50,000. Which side of 1,000 it falls on is not predicted.
4. **Through `mo query`.** Each question at 50,000 rows finishes, uses under 3% of the 1,073,741,824 instructions a query may run, and takes under one second from starting `mo` to the answer.
5. **Mo's own `Map` as the floor.** Summing a plain `Map` of the same number of rows costs a third or less of the tree's cost for each row. Even so, one sum over a plain `Map` does not fit in a call at 50,000 rows.
6. **By its answer, with no change to Mo.** Worlds, their questions and their answers can be kept in a service's state and worked through tools, and `mo test` passes with Mo's own recovery check. A world that relied on a branch's total is sent back after another world moves money out of that branch. It lands after another world moves money between two accounts of that branch, because the rows changed and the answer did not. The control that must fail does fail.

Known before the slice, so not predictions:

- A service's state may not hold a function. The questions are therefore a fixed set, named in the program, and a recorded question is its name and its argument. This stands in for a program the agent sends.
- `mo query` on an exported state runs `FUNCTION(state)` and takes no other argument. A question's argument is written into the caller's own function.
- A call's limit counts instructions. Work done inside one built-in operation, such as copying a map, is not counted.
- A reply may be at most 32 KiB, so the made-up rows are chosen to keep each answer small.

Claude's guess on the ticket before this, that a sum will not fit in one call at 10,000 rows, is prediction 2.

If asking again does not fit, three ways out are already named on [Which vertical slices, in what order, and what must each show?](38-which-vertical-slices-in-what-order.md): keeping totals current as writes land, a write function that names the facts it relies on, and checking outside the call.

## Answer

Resolved on 2026-11-14. The slice is in [sketches/kept-versions/](../sketches/kept-versions/), and how to run it is in [sketches/README.md](../sketches/README.md). It ran on `mo` 0.2.0 built from Mo's commit `ef37424`, optimised as Mo's own benchmark builds it.

**In short.** Only for a small table. With no change to Mo, a landing asks every question again and sends a world back only when an answer has changed. But a landing that asks three questions again and makes one move fits in one call up to about 1,400 rows. One question alone fits up to about 6,500 rows. The tree is not the cause: reading every row of Mo's own `Map` costs 59 instructions a row, so nothing that reads every row fits in one call past about 17,700 rows. Outside a call the same questions are cheap, about a third of a second each at 50,000 rows. That way works only on an exported copy, which takes 28 seconds to fetch at that size.

### Against the predictions

| # | Predicted | Found |
| --- | --- | --- |
| 1 | The sum costs 120 to 300 instructions a row; the filter within a quarter of it; the count by group 1.3 to 2 times it | The sum costs 150 to 153, as predicted. The filter costs 6% less than the sum, as predicted. The count costs 1.11 times the sum: wrong, it is cheaper than predicted |
| 2 | One sum fits in a call at 1,000 rows and not at 10,000 or 50,000; the largest size is between 3,500 and 8,700 | As predicted: it fits at 6,500 and is refused at 7,000, 10,000 and 50,000 |
| 3 | A landing with three questions and one move fits up to between 600 and 1,600 rows, and is refused at 10,000 and 50,000 | As predicted: it fits at 1,400 and is refused at 1,500. At 10,000 and 50,000 no landing was tried, because no question could be asked there at all. By count it needs 6.8 and 34 times a call's limit |
| 4 | Through `mo query` each question at 50,000 rows uses under 3% of the limit and takes under a second | As predicted: 0.66% to 0.78%, and 0.31 to 0.39 seconds |
| 5 | A sum over a plain `Map` costs a third or less of the tree's; even so it does not fit in a call at 50,000 rows | The first half is wrong: it costs 39% of the tree's. The second half holds by count, 2.8 times a call's limit. It was not tried in a service |
| 6 | Worlds, questions and answers can be kept in a service's state with no change to Mo; a world is sent back by its answer; the control fails | As predicted: 18 checks pass, and the control fails |

### What a question costs

Instructions for each row, measured exactly through `mo query --max-work`. Two runs gave the same counts to the instruction.

| | 1,000 rows | 10,000 rows | 50,000 rows |
| --- | --- | --- | --- |
| The sum: what one branch holds | 153 | 151 | 150 |
| The filter: accounts holding less than 105 | 145 | 142 | 142 |
| The count: accounts in each band of 100 | 171 | 168 | 168 |
| A landing: the three asked again, and one move | 731 | 714 | 712 |
| The same sum over Mo's own `Map` | 59 | 59 | 59 |

The same in whole numbers, beside the 1,048,576 instructions one call may run:

| | 1,000 rows | 10,000 rows | 50,000 rows |
| --- | --- | --- | --- |
| The sum | 153,244 | 1,505,944 | 7,517,382 |
| A landing | 731,317 | 7,137,267 | 35,605,277 |
| A landing, as a share of one call | 0.70 | 6.8 | 34 |
| The sum over a `Map`, as a share of one call | 0.06 | 0.56 | 2.8 |

A landing costs more than its three questions. Taking them away leaves about 253 instructions a row at 10,000 and 50,000 rows. That is the rule: the total is read once before the calls and once after each call.

### Where one call stops being enough

Seen in the running service, growing it in steps of 100 rows to 2,000 and of 500 rows to 12,000. Both runs gave the same sizes.

| In one call | Largest size that fit | First size refused |
| --- | --- | --- |
| A landing with three questions and one move | 1,400 | 1,500 |
| A landing with one question and one move | 2,500 | 3,000 |
| The count alone | 6,000 | 6,500 |
| The sum alone | 6,500 | 7,000 |
| The filter alone | 7,000 | 7,500 |

Every refusal was `work_limit`, and the service's state was unchanged after each. Where they fit, a question took about 25 ms at 500 rows and about 50 ms at 6,500, and a landing with three questions about 37 ms at 500 rows and 50 ms at 1,400. The machine was busy, so the times are rough.

Mo runs about 40 million instructions a second in this build. A call that runs to its limit therefore takes about 26 ms.

### Outside a call

`mo query` runs a function over an exported copy of the state and may run 1,073,741,824 instructions, 1,024 times a call's limit.

| | 1,000 rows | 10,000 rows | 50,000 rows |
| --- | --- | --- | --- |
| The export's size | 73 kB | 416 kB | 1.8 MB |
| Fetching the export | 1.3 s | 5.8 s | 28 s |
| The sum, from starting `mo` to the answer | 0.12 s | 0.15 to 0.18 s | 0.31 to 0.33 s |
| The filter | 0.12 to 0.13 s | 0.15 to 0.16 s | 0.31 to 0.34 s |
| The count | 0.12 s | 0.18 to 0.19 s | 0.35 to 0.39 s |
| The sum, as a share of what a query may run | 0.01% | 0.14% | 0.70% |

Each range is the two runs; the fetch was timed in the second run only. Asking is cheap; getting the copy is not. The export is fetched through the service's own tools in pages, at the service's limit of 20 calls a second.

### By its answer

The rule works as Robert decided it. In `worlds.mo` one world asks what branch 3 holds and then moves money inside branch 5. Another world's move lands first.

- When the other world moved money out of branch 3, the first world is sent back, and nothing changes.
- When the other world moved money between two accounts of branch 3, the first world lands. The rows it read changed and its answer did not.

The same send-back is tested through the service's tools. The control: with the check of questions taken out of `land`, three tests fail, and the stale world lands.

### Three things the slice ran into

**A question too large for a call counts against the whole service.** Mo restarts a service after five failures within a minute and stops it after three restarts within ten minutes. It then stays down until a person starts it. A call refused for its limit counts as a failure. The first run of the measurement stopped the service this way, on its fifteenth refused call, at 4,500 rows. In a database that many agents share, fifteen questions that are too large, five to a minute, would stop it for everyone.

**The rule costs as much as the questions.** Checking that the total never changes reads every row. By count, a landing with no question at all and one move would stop fitting at about 4,000 rows. That was not tried.

**`mo query` reads a copy, not the service.** It takes the state and no other argument, so each question's argument is written into the function. The copy is 28 seconds old at 50,000 rows before the first question is asked. Mo has no way to run a caller's function against the live state, short of upgrading the whole service.

### What this means

The rule stands, and its first form does not scale. Asking again by reading every row is bounded by what one call may run, and so is the rule itself. Any slice that holds more than a few thousand rows meets this before anything else.

Five ways out. The first three were named before the slice. None is built, and none is chosen.

1. **Keep answers current as writes land.** A kept total is read in one step. Only some forms of question can be kept this way ([What earlier work stands behind write-once trees and views kept current?](31-earlier-work-on-write-once-trees-and-views-kept-current.md)).
2. **A write function names the facts it relies on.** Fewer questions are asked again. One question is no cheaper.
3. **Check outside the call.** As Mo stands this means an export, which is slow, and the check and the landing are no longer one step.
4. **Ask again only about what changed.** Claude's idea, from this slice. Two versions of the tree share every node that neither has changed, and a shared node has the same number in both. The rows that differ between the version a question was asked on and the main line can therefore be found by walking only where the numbers differ. A landing would cost in proportion to what changed since the world opened, not to the size of the table. A world that opened on the version that is still the main line would have nothing to ask again.
5. **A larger limit for a call.** Mo's limit is a constant. One operation runs at a time, so a longer call makes every other agent wait: the landing at 50,000 rows is 35.6 million instructions, about 0.9 seconds.

Things Mo lacks that this slice met, each one something other programs would also use. They are observations for [What must Mo gain to build it?](17-what-must-mo-gain.md), not decisions:

- a call's limit that a service can set, or a separate one for calls that only read;
- a refused call that does not count toward stopping the service;
- a caller's function run against the live state, as `mo query` runs one against a copy.

### Stand-ins

What the slice used in place of the real thing. The decision may cite this slice only with these named.

| The slice used | In place of |
| --- | --- |
| Four questions written into the program, recorded as a name and an argument | A read program the agent sends. A service's state may not hold a function, and new code reaches a running service only through Mo's upgrade tools |
| One view for every caller, `anywhere?`, in the service | A grant for each caller that names its view. No sketch has a caller yet |
| The rule written as a function in `land` | A promise that a person approved and that is checked when a write lands. A promise cannot be called at a landing today |
| Made-up rows: account `key` holds 100 + `key` % 900, and its branch is `key` % 10 | Real data, which waits for [What real data of yours goes in first?](12-what-real-data-goes-in-first.md) |
| One script that opens a world, asks, moves and lands, one world at a time | Two or more agents whose worlds overlap, through the service |
| A whole answer kept in the world, such as every account a filter found | A short fingerprint of the answer, if answers grow large |
| `grow`, which writes rows to the main line with no world and no rule | Loading data through a world |
| The tree and the worlds from the last sketch, with its own stand-ins | See [Can a Mo library keep old versions cheaply today?](37-can-a-mo-library-keep-old-versions-cheaply-today.md) |

### Not shown

- Two agents at once, and how often a world is sent back for nothing. That is the next slice on the list.
- A landing refused at 10,000 or 50,000 rows as a refused `land`. No question could be asked at those sizes, so the figures there are counts.
- A sum over a plain `Map` in a service. The 17,700 rows is a count.
- A view narrower than everything, inside the service. It is tested in `worlds.mo` only.
- Closing a world that was sent back. It stays in the service's state.
- A quiet machine. The instruction counts do not depend on it; the times do.
