# Last writer wins

When two writes clash, last writer wins (LWW) keeps one of them, usually the one with the later timestamp or the later arrival, and silently drops the other. It needs no coordination and never asks anyone.

## What it is

- *Last write wins*: when two writes clash, keep the one with the later clock timestamp and silently drop the other ([03](../../research/03-key-value-document-distributed.md)).
- Variants decide "later" differently:
  - **Clock timestamps.** Cassandra resolves conflicts by LWW on client or coordinator clocks ([03](../../research/03-key-value-document-distributed.md), https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html).
  - **Arrival order at the server.** PowerSync's default is per-field last-writer-wins, decided by arrival order at the server ([06](../../research/06-divergent-copies-and-merging.md), https://docs.powersync.com/handling-writes/handling-update-conflicts).
  - **Save count, then latest save.** Lotus Notes picks the copy "edited and saved the most times"; on a tie, the latest save wins ([06](../../research/06-divergent-copies-and-merging.md), https://help.hcl-software.com/domino/14.5.0/admin/admn_replicationorsaveconflicts_c.html).
  - **A deterministic winner.** CouchDB and Automerge pick a winner that is the same on every copy, and keep the losers on the side (https://docs.couchdb.org/en/stable/replication/conflicts.html, https://automerge.org/docs/reference/documents/conflicts/). [06](../../research/06-divergent-copies-and-merging.md) groups them, with Notes, lakeFS's win flags and PowerSync, as systems that "pick a winner silently".
  - **Full rewrite of shared memory.** Letta lets several agents share a memory block; a full rewrite of a block is last-writer-wins with no merge, and appending is the only safe concurrent operation ([09](../../research/09-agents-and-databases-today.md), https://docs.letta.com/v1-sdk/memory/shared-memory/index.md).

## The problem it solves

- **Convergence with no coordination.** All copies end up the same without talking to each other ([06](../../research/06-divergent-copies-and-merging.md)).
- **A simple write path.** PowerSync and Electric trade merge logic for "field-level last-writer-wins" or your own API ([06](../../research/06-divergent-copies-and-merging.md)).
- **Availability during a partition.** Cassandra at a low consistency level stays available and diverges ([03](../../research/03-key-value-document-distributed.md)).

## What it costs

- **Silent loss.** A timestamp clash discards a write silently ([03](../../research/03-key-value-document-distributed.md), inference). An agent that does not ask for conflicts builds on a value that silently replaced someone's work ([06](../../research/06-divergent-copies-and-merging.md)).
- **Correctness depends on clocks.** In Cassandra, "correctness does depend on these clocks" (https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html).
- **The winner has nothing to do with meaning.** Notes' rule (most saves) is unrelated to what the edits meant; Automerge's winner of a same-field clash is arbitrary ([06](../../research/06-divergent-copies-and-merging.md)).
- **Rules that need rejection cannot be kept.** A merge that never rejects cannot keep uniqueness or "never below zero" ([06](../../research/06-divergent-copies-and-merging.md), https://www.vldb.org/pvldb/vol8/p185-bailis.pdf).

## Systems that use it

- [Apache Cassandra](../systems/cassandra.md): LWW on client or coordinator clocks ([03](../../research/03-key-value-document-distributed.md)).
- [CouchDB](../systems/couchdb.md): a deterministic winner for plain reads; losers kept but hidden ([03](../../research/03-key-value-document-distributed.md); [06](../../research/06-divergent-copies-and-merging.md)).
- [Automerge](../systems/automerge.md): a winner that is the same everywhere for same-property clashes; losers through `getConflicts` ([06](../../research/06-divergent-copies-and-merging.md)).
- PowerSync, Lotus Notes and Letta, which have no pages ([06](../../research/06-divergent-copies-and-merging.md); [09](../../research/09-agents-and-databases-today.md)).

## Cannot be combined with

[Rules the database enforces across transactions](invariants-the-database-enforces.md) whose operations a merge cannot keep alone, such as uniqueness of a chosen value or a counter that must stay above a bound ([06](../../research/06-divergent-copies-and-merging.md), https://www.vldb.org/pvldb/vol8/p185-bailis.pdf). See also [Keeping conflicts as data](conflicts-kept-as-data.md), the alternative that keeps the loser.

## Sources

- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html
- https://docs.powersync.com/handling-writes/handling-update-conflicts
- https://help.hcl-software.com/domino/14.5.0/admin/admn_replicationorsaveconflicts_c.html
- https://docs.couchdb.org/en/stable/replication/conflicts.html
- https://automerge.org/docs/reference/documents/conflicts/
- https://docs.letta.com/v1-sdk/memory/shared-memory/index.md
- https://www.vldb.org/pvldb/vol8/p185-bailis.pdf
