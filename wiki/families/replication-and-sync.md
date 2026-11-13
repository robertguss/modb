# Diverging replicas, self-merging data and sync engines

Systems in which several copies of the same data accept writes separately and are brought back together later. They range from 1990s replicated stores for disconnected machines, through data types that merge themselves, to today's sync engines that keep part of a server database on each client ([research 06](../../research/06-divergent-copies-and-merging.md); [research 00](../../research/00-landscape-overview.md)).

## What they are for

- **Disconnected copies.** Machines that are often offline (laptops, mobile devices, offices on slow links) must accept writes offline and catch up later ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **Collaboration.** Apps where every device edits at once ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **Fast local reads.** Server data read locally, with writes that show at once and are confirmed later ([research 06](../../research/06-divergent-copies-and-merging.md)). Research 00 says these systems drop the assumption that clients fetch data by request and response, and get local reads and offline use; [Automerge](../systems/automerge.md) also drops the authoritative server ([research 00](../../research/00-landscape-overview.md)).

The question that runs through the family: when both copies changed, who decides the result, and what does that decider know? ([research 06](../../research/06-divergent-copies-and-merging.md))

## Members

- [Bayou](../systems/bayou.md): each write carries a dependency check and a merge procedure; a primary fixes the final order.
- [Automerge](../systems/automerge.md): a CRDT library; copies converge with no server, and same-field clashes get an arbitrary but consistent winner.
- [Electric](../systems/electric.md): syncs "Shapes" out of Postgres for reading; writes go through the app's own API.
- [Zero](../systems/zero.md): named write functions run on the client and again on the server, which the client rebases onto.
- [CouchDB](../systems/couchdb.md), described with this family in research 06 and with document stores in research 03: every node picks the same winner and keeps the losers, but a plain read hides them ([CouchDB conflicts](https://docs.couchdb.org/en/stable/replication/conflicts.html)).

Mentioned only:

- Lotus Notes / HCL Domino: the copy "edited and saved the most times" wins, and the loser is kept as a conflict document for a person to sort out ([HCL](https://help.hcl-software.com/domino/14.5.0/admin/admn_replicationorsaveconflicts_c.html); [research 06](../../research/06-divergent-copies-and-merging.md)).
- Yjs: a CRDT library whose updates are "commutative, associative, and idempotent"; Electric's agent peer uses it ([Yjs](https://docs.yjs.dev/api/document-updates); [research 06](../../research/06-divergent-copies-and-merging.md)).
- PowerSync: syncs to a local SQLite with writes queued for upload; per-field last-writer-wins by arrival order, and a first-in-first-out queue that blocks on an unacknowledged write ([PowerSync](https://docs.powersync.com/handling-writes/handling-update-conflicts); [research 06](../../research/06-divergent-copies-and-merging.md)).
- Letta: an agent memory store where a full rewrite of a shared block is last-writer-wins with no merge, and appending is the only safe concurrent operation ([Letta](https://docs.letta.com/v1-sdk/memory/shared-memory/index.md); [research 09](../../research/09-agents-and-databases-today.md)).

## Shared tradeoffs

**Accept every write locally, settle later.** Bayou, CouchDB and Lotus Notes take every write locally with no locks across replicas ([research 06](../../research/06-divergent-copies-and-merging.md)). The price is that some rules cannot be kept at write time.

**Which rules a merge can keep alone.** *Invariant confluence* says a rule can be kept without coordination only if any two valid states grown from a common ancestor always merge into a valid state ([Bailis et al.](https://www.vldb.org/pvldb/vol8/p185-bailis.pdf)). "Stock never below zero" and "this id is new" fail that test. The family answers such rules in one of four ways ([research 06](../../research/06-divergent-copies-and-merging.md)):

1. Pick a winner silently: Notes, CouchDB, Automerge, PowerSync (and lakeFS flags).
2. Stop and ask: Dolt and lakeFS by default.
3. Re-run the operation with its guard against a single authority: Bayou, Zero.
4. Never merge: Neon, Xata.

See [data types that merge themselves](../ideas/data-types-that-merge-themselves.md) and [writes that carry their assumptions](../ideas/writes-that-carry-their-assumptions.md).

**The server as authority, the client as a guess.** Sync engines merge by re-running the operation, not by combining states. Paid for by a reachable server and writes written as code it can re-run. The weakness: a rejected write surfaces late, away from the code that made it ([research 06](../../research/06-divergent-copies-and-merging.md)).

**Silent winners.** CouchDB and Notes return a winner that looks normal; an agent that does not ask for conflicts builds on a value that silently replaced someone's work ([research 06](../../research/06-divergent-copies-and-merging.md)). In CouchDB, losing edits stay hidden unless the agent asks with `conflicts=true` (inference, [research 03](../../research/03-key-value-document-distributed.md)).

**No meaning across changes.** Merges match on primary key, and CRDTs merge without coordination. Neither can tell that two agents' changes are each fine alone but wrong together (inference, [research 09](../../research/09-agents-and-databases-today.md)). See [merging by meaning](../ideas/merging-by-meaning.md).

**Disagreements inside the family's sources.**

- Research 09 lists Electric's agent-as-Yjs-peer as a best existing mechanism for conflicting writes ([research 09](../../research/09-agents-and-databases-today.md)); research 06 says it suits text but cannot stop two agents claiming the last item ([research 06](../../research/06-divergent-copies-and-merging.md)).
- Research 00 says nobody merges by intent ([research 00](../../research/00-landscape-overview.md)); research 06 describes Bayou's per-write checks as defining conflicts by meaning ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Sources

- [research 06: Divergent copies and merging](../../research/06-divergent-copies-and-merging.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 03: Key-value, document and distributed](../../research/03-key-value-document-distributed.md)
- [research 09: Agents and databases today](../../research/09-agents-and-databases-today.md)
- I-confluence: https://www.vldb.org/pvldb/vol8/p185-bailis.pdf
- CouchDB conflicts: https://docs.couchdb.org/en/stable/replication/conflicts.html
