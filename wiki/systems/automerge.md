# Automerge

Automerge is a library of data types that merge themselves (CRDTs), for collaborative and offline-first apps. Copies merge concurrent changes without a server ([Automerge](https://automerge.org/); [research 00](../../research/00-landscape-overview.md)).

## What it is for

Collaborative and offline-first apps where every device edits at once ([research 06](../../research/06-divergent-copies-and-merging.md)). Research 00 groups it with sync systems that drop the assumption that clients fetch data by request and response. What they get is local reads and offline use; Automerge also drops the authoritative server ([research 00](../../research/00-landscape-overview.md)).

## Core idea

A *CRDT* (conflict-free replicated data type) is a structure whose merge is defined so that copies which have seen the same edits are identical, whatever order the edits arrived in ([research 06](../../research/06-divergent-copies-and-merging.md)).

The one case Automerge says it "cannot handle automatically, because there is no well-defined resolution" is two writers setting the same property. It then picks a winner that is the same on every copy and exposes the losers through `getConflicts` ([Automerge conflicts](https://automerge.org/docs/reference/documents/conflicts/)).

## Strengths and what pays for each

- **No conflicts to resolve and no server needed.** Paid for by: the merge can never reject a write. Rules that need a rejection, such as uniqueness or "never below zero", cannot be kept ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Weaknesses

- The winner of a same-field clash is arbitrary ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **Converging is not the same as being useful.** Several published text CRDTs interleave two people's concurrent insertions character by character, "resulting in an unreadable jumble of letters". The authors' errata on the same page says their own fix did not converge ([Kleppmann, 2019](https://martin.kleppmann.com/2019/03/25/papoc-interleaving-anomalies.html)). Research 06 cites this as a CRDT problem in general, not as a finding about Automerge itself.

## Overlapping work

Every device writes at once and nothing waits. Concurrent changes merge by construction ([research 06](../../research/06-divergent-copies-and-merging.md)).

## What an agent struggles with

- A CRDT merge cannot tell that two agents' changes are each fine alone but wrong together. Research 09 names this as its highest-confidence gap (inference, [research 09](../../research/09-agents-and-databases-today.md)).
- Running an agent as a CRDT peer suits text, but it cannot stop two agents claiming the last item, because the merge never rejects a write ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Worth borrowing

Merge-by-construction for data whose rules are merge-safe: growing sets, unbounded counters, append-only logs. Cost: the type system must know which data is which ([research 06](../../research/06-divergent-copies-and-merging.md)). See [data types that merge themselves](../ideas/data-types-that-merge-themselves.md).

## Sources

- [research 06: Divergent copies and merging](../../research/06-divergent-copies-and-merging.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md) (its author did not read Automerge's papers in full)
- [research 09: Agents and databases today](../../research/09-agents-and-databases-today.md)
- Automerge: https://automerge.org/
- Automerge conflicts: https://automerge.org/docs/reference/documents/conflicts/
- Interleaving anomalies: https://martin.kleppmann.com/2019/03/25/papoc-interleaving-anomalies.html
