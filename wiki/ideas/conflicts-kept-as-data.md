# Keeping conflicts as data

When two copies change the same thing, the store keeps every conflicting version, or records the conflict in a table, instead of silently dropping one. Resolving the conflict becomes an explicit step someone must take.

## What it is

- **Concurrent versions kept side by side.** Dynamo uses *vector clocks* (a per-node counter attached to each version) to detect concurrent versions and pushes resolution "to the reads" and to the application ([03](../../research/03-key-value-document-distributed.md), https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf). CouchDB keeps conflicting edits as branches of a revision tree; every node picks the same winner, but "the application ... must always resolve conflicts" (https://docs.couchdb.org/en/stable/replication/conflicts.html).
- **Losers kept as visible documents.** Lotus Notes keeps the loser as a "Replication or Save Conflict" document for a person to sort out ([06](../../research/06-divergent-copies-and-merging.md), https://help.hcl-software.com/domino/14.5.0/admin/admn_replicationorsaveconflicts_c.html).
- **Losers exposed through an API.** Automerge picks a winner that is the same everywhere for two writers setting the same property, and exposes the losers through `getConflicts` ([06](../../research/06-divergent-copies-and-merging.md), https://automerge.org/docs/reference/documents/conflicts/).
- **Conflicts and broken rules as tables that block commit.** Dolt's three-way merge puts conflicts in `dolt_conflicts_<table>` (base, ours, theirs). Foreign-key and unique-key breakages go in `dolt_constraint_violations`, which blocks commit until empty unless forced ([06](../../research/06-divergent-copies-and-merging.md), https://www.dolthub.com/docs/concepts/dolt/git/merge/, https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/).

## The problem it solves

- **Nothing is lost.** Dynamo's cart merge never loses an add ([03](../../research/03-key-value-document-distributed.md)). In Notes, nothing is lost ([06](../../research/06-divergent-copies-and-merging.md)).
- **Writes are never refused** while copies are apart, because the decision is deferred ([03](../../research/03-key-value-document-distributed.md)).
- For rules a merge cannot keep by itself (uniqueness, "never below zero"), "stop and ask" is one of four answers the research finds; the others are picking a winner silently, re-running the operation against an authority, or never merging ([06](../../research/06-divergent-copies-and-merging.md)).

## What it costs

- **Every reader must handle more than one version** ([03](../../research/03-key-value-document-distributed.md)). In Dynamo, every application must expect several versions of the same item, and "deleted items can resurface" (Dynamo paper).
- **Unresolved conflicts must be made visible**, which CouchDB does not do: a plain `GET` returns the winner with "no indication" that others exist ([03](../../research/03-key-value-document-distributed.md); [06](../../research/06-divergent-copies-and-merging.md)).
- **Someone must resolve them.** Notes needs a person to clean up conflict documents by hand ([06](../../research/06-divergent-copies-and-merging.md)).
- **Rules checked over the merged result**, not each side, for Dolt's violation tables ([06](../../research/06-divergent-copies-and-merging.md)).
- **The resolver lacks intent.** Choosing between base, ours and theirs needs both sides' intent, which a branch does not record ([06](../../research/06-divergent-copies-and-merging.md)). See [Writes that carry their assumptions](writes-that-carry-their-assumptions.md).

## Systems that use it

- [CouchDB](../systems/couchdb.md): revision-tree branches; hidden unless asked for with `conflicts=true` ([03](../../research/03-key-value-document-distributed.md)).
- [Dynamo and DynamoDB](../systems/dynamodb.md): Dynamo keeps concurrent versions for the application to merge ([03](../../research/03-key-value-document-distributed.md)).
- [Dolt](../systems/dolt.md): conflict and constraint-violation tables that block commit ([06](../../research/06-divergent-copies-and-merging.md)).
- [Automerge](../systems/automerge.md): a deterministic winner plus `getConflicts` ([06](../../research/06-divergent-copies-and-merging.md)).
- Lotus Notes / Domino, which has no page: conflict documents for a person ([06](../../research/06-divergent-copies-and-merging.md)).

## Cannot be combined with

[Last writer wins](last-writer-wins.md) as the final answer: that rule drops the loser silently instead of keeping it ([03](../../research/03-key-value-document-distributed.md)). Systems such as CouchDB and Automerge do both: they pick a winner for plain reads and keep the losers on the side ([06](../../research/06-divergent-copies-and-merging.md)).

## Sources

- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf
- https://docs.couchdb.org/en/stable/replication/conflicts.html
- https://help.hcl-software.com/domino/14.5.0/admin/admn_replicationorsaveconflicts_c.html
- https://automerge.org/docs/reference/documents/conflicts/
- https://www.dolthub.com/docs/concepts/dolt/git/merge/
- https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/
