# CouchDB

CouchDB stores JSON documents with revision IDs and can replicate between any two copies, including offline ones. Conflicting edits are kept, not thrown away, but a plain read hides them.

## What it is for

Replicating anywhere, including copies that are often offline ([03](../../research/03-key-value-document-distributed.md); [06](../../research/06-divergent-copies-and-merging.md)). Its founding year was not confirmed: [03](../../research/03-key-value-document-distributed.md) gives 2005 from memory, and [06](../../research/06-divergent-copies-and-merging.md) found no primary source.

## Core idea

- JSON documents with revision IDs, and replication between any two copies ([03](../../research/03-key-value-document-distributed.md)).
- On one node, an update must quote the `_rev` it read, or it gets `409 Conflict` ([03](../../research/03-key-value-document-distributed.md)). See [Optimistic concurrency and version-checked writes](../ideas/optimistic-concurrency.md).
- Across replicas, conflicting edits are kept as branches of a revision tree. Every node picks the same "winner" by a deterministic rule, but "the application ... must always resolve conflicts" (https://docs.couchdb.org/en/stable/replication/conflicts.html). See [Keeping conflicts as data](../ideas/conflicts-kept-as-data.md).

## Strengths and what pays for each

- **All copies converge with no coordination.** Paid for by conflicts that are silent unless code asks ([06](../../research/06-divergent-copies-and-merging.md)).
- **Replicate anywhere, offline.** Paid for by leaving conflicts to the application ([03](../../research/03-key-value-document-distributed.md)).

## Weaknesses

- A plain `GET` returns the winner with "no indication" that others exist; the application must ask for `_conflicts` (https://docs.couchdb.org/en/stable/replication/conflicts.html).
- **No multi-document transactions.** A rewrite on [FoundationDB](foundationdb.md) ended in 2022 when its sponsor stopped funding it ([03](../../research/03-key-value-document-distributed.md), https://lists.apache.org/thread/9gby4nr209qc4dzf2hh6xqb0cn1439b7).

## Overlapping work

Every write is accepted locally and settled later, with no locks across replicas ([06](../../research/06-divergent-copies-and-merging.md)). For rules that a merge cannot keep by itself, CouchDB's answer is to pick a winner silently ([06](../../research/06-divergent-copies-and-merging.md)); see [Last writer wins](../ideas/last-writer-wins.md).

## What an agent struggles with

Losing edits stay hidden unless the agent asks with `conflicts=true` ([03](../../research/03-key-value-document-distributed.md), inference). An agent that does not ask builds on a value that silently replaced someone's work ([06](../../research/06-divergent-copies-and-merging.md)).

## Worth borrowing

- **Keep conflicts as data.** Store concurrent versions and make resolving them an explicit step. Cost: every reader must handle more than one version, and unresolved conflicts must be made visible, which CouchDB does not do ([03](../../research/03-key-value-document-distributed.md)).
- **Check-and-set on a version token (`_rev`).** The simplest way to stop lost updates between agents. Cost: callers must re-read and retry ([03](../../research/03-key-value-document-distributed.md)).

## Sources

- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- https://docs.couchdb.org/en/stable/replication/conflicts.html
- https://lists.apache.org/thread/9gby4nr209qc4dzf2hh6xqb0cn1439b7
