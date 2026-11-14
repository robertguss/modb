# Can a landing ask an agent's questions again inside one call?

Type: prototype
Status: claimed

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
