# Predictions for the sweep model

Written on 2026-11-16, before the model exists. This is experiment 17 in [experiments.md](../experiments.md), Decision 2. The model and what it showed go in `README.md` beside this file. A prediction that fails stays here and is marked as failed.

## The question

The store keeps a version while something holds its root, and frees the nodes no kept version reaches. Experiment 16 wrote that as a sweep in Mo. Is the sweep safe however a crash falls, and what must the runtime tell it?

## What is modelled

- **A tree of two levels.** A version is a root node that lists its leaves. A write adds one leaf, or puts one leaf in place of another, and makes a new root. The old root and the leaves it shares are untouched.
- **A writer** that makes at most three writes. Each write takes three steps: write the new nodes, force the log entry, switch the root.
- **Holders.** At any step something may hold the current root, or drop a root it holds.
- **A snapshot.** When no write is under way, the store may save the current root and empty the log, as a Mo service does today.
- **A crash, between any two steps.** It loses the write and the sweep under way. Recovery starts from the snapshot's root and runs the logged writes again, in order. A write run again reads the root it started from and writes its own two nodes again.
- **A sweep.** It marks every node reached from its roots, then frees nodes that are not marked. It keeps nothing on disk between runs.
- Nodes written are on disk at once. Holding, dropping and the snapshot are each one step.

Four switches:

| Switch | Settings |
| --- | --- |
| Order | `log`: nodes, then the log, then the root, as `design.md` says. `root`: nodes, then the root, then the log. Meant to fail |
| Sweep | `excl`: one step, taken only when no write is under way, as a call to a Mo service would be. `ignore`: runs beside a write, marks from the root and the held roots, frees everything else. Meant to fail. `born`: runs beside a write, also marks the nodes of the write under way, and frees only nodes that were on disk when it marked. `pin`: runs beside a write, also marks the nodes of the write under way and every node written until it finishes |
| Names | `number`: every node gets a new name. `hash`: a node with the same contents as an earlier one gets the same name, so a write may give back a node that nothing reached |
| Keep | `held`: the sweep's roots are the current root and the held roots. `snap`: the snapshot's root as well |

That is 32 settings.

## Properties

- **Safe.** Every node reached from the current root or a held root is on disk, in every state.
- **Logged.** When no write is under way, every held root was the result of a logged write.
- **Recovers.** Recovery never reads a node that is not on disk.
- **NothingFreed.** No node is ever freed. This must be broken in every setting, or the sweep did nothing and the other results mean nothing.

Not checked: that a sweep after a crash leaves nothing unreachable. The `excl` sweep frees every node it did not mark, so this holds by how it is defined.

## Predictions

The rule, for all 32 settings:

| Property | Broken when |
| --- | --- |
| Safe | Sweep is `ignore`, or Sweep is `born` and Names is `hash` |
| Logged | Order is `root` |
| Recovers | Keep is `held` |
| NothingFreed | always |

1. With the order of `design.md`, the `excl` sweep, names by number and the snapshot's root kept, Safe, Logged and Recovers all hold: 85%.
2. Order `root` breaks Logged in all 16 of its settings and changes nothing else: 85%.
3. Sweep `ignore` breaks Safe in all 8 of its settings: 95%.
4. Sweep `born` keeps Safe with names by number and breaks it with names by hash: 70%.
5. Sweep `pin` keeps Safe under both kinds of name: 75%.
6. Keep `held` breaks Recovers in all 16 of its settings, the `excl` sweep among them: 85%. Keep `snap` keeps it in all 16: 80%.
7. All 32 settings come out as the rule says: 45%.

The two draft predictions in the plan, as they now stand:

- "The sweep holds with nothing stored beyond the roots and the log", at 80%. Claude now expects this to hold only if the snapshot's root counts as held. That is prediction 6.
- "A sweep during a write must pin that write's new nodes until its root lands", at 70%. That is predictions 3, 4 and 5.

## What the result would mean for Decision 2

- **Toward S:** the `excl` sweep is safe under both kinds of name. Then a sweep written in Mo and run as a call is enough, and it needs three things from the runtime: a node's children, removing a node, and the snapshot's root.
- **Toward R:** with names by hash, only `pin` is safe beside a write. Then a sweep that runs in the background needs the runtime to tell it of every node written while it runs, and that part belongs in the runtime.
- Both can be true. Then the split holds only while the sweep may stop the writer.

## Controls that must fail

- Order `root` must break Logged.
- Sweep `ignore` must break Safe.
- NothingFreed must be broken everywhere.

## Limits known before the model

- The tree has two levels and at most three writes. The model is tiny.
- A node written is on disk at once. Losing a node that was written but not forced is not modelled.
- One writer. No worlds landing, no views.
- Recovery reads only the root a write started from, not the leaves under it.
- A sweep is not a logged call and is never run again by recovery.
- Claude wrote the predictions and will write the model.

## How they came out, 2026-11-16

Added after the run. Nothing above this line was changed.

| # | Result |
| --- | --- |
| 1 | Held |
| 2 | **Failed in its second half.** Order `root` broke Logged in all 16. It also broke Safe in three settings the rule said were safe: `born` with numbers, and `pin` with either kind of name, each with Keep `held` |
| 3 | Held |
| 4 | Held in every setting with the order of `design.md`. **Failed in one setting** of order `root`, as in 2 |
| 5 | Held in every setting with the order of `design.md`. **Failed in two settings** of order `root`, as in 2 |
| 6 | First half held: Keep `held` broke Recovers in all 16. **Second half failed:** Keep `snap` kept Recovers in only 10 of 16. In the six where Safe is broken, Recovers is broken too |
| 7 | **Failed.** 23 of 32 came out as the rule says |

Claude saw the fault behind 6 while writing the model, after these predictions were committed and before any run: where the sweep frees a node the current root reaches, a later snapshot saves that root, and recovery then starts from it.
