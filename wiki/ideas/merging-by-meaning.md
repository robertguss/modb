# Merging by meaning, not by cell (gap)

A merge that knows what the changes mean, such as "both branches added stock", instead of only which cells changed. Mainstream branch merges do not do this; a few older systems had mechanisms for it.

## What it is

A merge that decides conflicts by the meaning of the operations, not by which bytes or cells changed ([00](../../research/00-landscape-overview.md), [06](../../research/06-divergent-copies-and-merging.md)).

## The problem it solves

A cell-level merge reports success whenever no cell changed on both sides. These pass cleanly but are wrong (inference, [06](../../research/06-divergent-copies-and-merging.md)):

- **Two agents book the last seat.** Each inserts a different booking row: different keys, no conflict, capacity exceeded.
- **A row neither side wrote.** One branch moves a meeting's start, the other its end. The merge may produce a meeting that ends before it starts; [Dolt](../systems/dolt.md) catches it only if a check constraint was declared.
- **Stale reasoning.** Agent A reads prices and writes a discount table; agent B changes prices. No shared cell, so nothing flags that A's output came from data that no longer exists.

The common cause: the merge sees what was written, not what was read or assumed ([06](../../research/06-divergent-copies-and-merging.md)). The research ranks this as the clearest gap for agents (inference, high confidence, [09](../../research/09-agents-and-databases-today.md)).

## What it costs

*Invariant confluence* (I-confluence) draws the line. Operations are I-confluent for a rule (an *invariant*) if any two valid states grown from a common ancestor always merge into a valid state; only then can the rule be kept without coordination (https://www.vldb.org/pvldb/vol8/p185-bailis.pdf). Uniqueness with a chosen value, auto-increment ids, deletes under a foreign key, and "counter > k" with decrements are not I-confluent. "Stock never below zero" and "this id is new" need one side to see the other, or something to decide afterwards ([06](../../research/06-divergent-copies-and-merging.md)).

Each mechanism pays differently:

- **[Bayou](../systems/bayou.md)**: every write carries hand-written check and merge code, and reads can show tentative data that later changes ([06](../../research/06-divergent-copies-and-merging.md)).
- **[GemStone](../systems/gemstone.md)**: merge semantics written and proved per type (inference, [04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **CRDTs ([Automerge](../systems/automerge.md))**: the merge can never reject a write, so rules that need rejection cannot be kept ([06](../../research/06-divergent-copies-and-merging.md)).

## Systems that use it

- **[Bayou](../systems/bayou.md)** (Xerox PARC, SOSP 1995). Only the application knows what a conflict is. Every write carries the update, a *dependency check* (a query plus the result it expects, for example "room 5 is free at 10:00"), and a *merge procedure* (code that produces an alternative write if the check fails) (https://www.cs.utexas.edu/~lorenzo/corsi/cs380d/papers/p172-terry.pdf). It is the one mechanism found that records the assumption, so it can detect all three cases above ([06](../../research/06-divergent-copies-and-merging.md)). See [Writes that carry their assumptions](writes-that-carry-their-assumptions.md).
- **[GemStone](../systems/gemstone.md)**. *Reduced-conflict* (Rc) classes, such as counters and bags, replay their changes at commit, so two sessions adding to the same bag do not conflict (https://downloads.gemtalksystems.com/docs/GemStone64/3.6.x/GS64-ProgGuide-3.6.pdf). [04](../../research/04-models-that-lost-or-stayed-niche.md) presents this as a mechanism for merging by intent.
- **[Automerge](../systems/automerge.md)** and other CRDTs merge by construction. Automerge says the one case it "cannot handle automatically, because there is no well-defined resolution" is two writers setting the same property; it picks the same winner everywhere and exposes the losers through `getConflicts` (https://automerge.org/docs/reference/documents/conflicts/). See [Data types that merge themselves](data-types-that-merge-themselves.md).
- **[Dolt](../systems/dolt.md)** merges cell by cell and checks declared constraints over the result (https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/). It does not merge by meaning.
- **[Zero](../systems/zero.md)** re-runs named write functions on the server's state, which is Bayou's idea with the server as primary ([06](../../research/06-divergent-copies-and-merging.md), https://zero.rocicorp.dev/docs/mutators).

## Disagreements

- **Does anything merge by intent?** [00](../../research/00-landscape-overview.md) says nobody does (marked inference). [06](../../research/06-divergent-copies-and-merging.md) describes Bayou (1995), whose per-write dependency checks and merge procedures define conflicts by meaning. [04](../../research/04-models-that-lost-or-stayed-niche.md) presents GemStone's reduced-conflict classes as a mechanism for merging by intent. All agree that mainstream branch merges (Dolt) are cell-level.
- **Agents as CRDT peers.** [09](../../research/09-agents-and-databases-today.md)'s table lists Electric's agent-as-Yjs-peer, which "merges everything without coordination" (https://electric.ax/blog/2026/04/08/ai-agents-as-crdt-peers-with-yjs), as a best existing mechanism for conflicting writes. [06](../../research/06-divergent-copies-and-merging.md) says the same approach suits text but cannot stop two agents claiming the last item, because a CRDT merge can never reject a write.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://www.vldb.org/pvldb/vol8/p185-bailis.pdf
- https://www.cs.utexas.edu/~lorenzo/corsi/cs380d/papers/p172-terry.pdf
- https://downloads.gemtalksystems.com/docs/GemStone64/3.6.x/GS64-ProgGuide-3.6.pdf
- https://automerge.org/docs/reference/documents/conflicts/
- https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/
- https://electric.ax/blog/2026/04/08/ai-agents-as-crdt-peers-with-yjs
