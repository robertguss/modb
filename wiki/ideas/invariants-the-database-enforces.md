# Rules the database enforces across transactions

An *invariant* is a rule that must always hold, such as "stock never below zero" or "this id is unique". This page covers rules the database itself checks and enforces, beyond what one row can express, so that a transaction breaking one is refused.

## What it is

The mechanisms in the research, from narrow to broad:

- **Row-level constraints.** CHECK, foreign keys and uniqueness ([00](../../research/00-landscape-overview.md), inference). Cassandra 6.0 adds CQL `CHECK` constraints, in alpha and off by default ([03](../../research/03-key-value-document-distributed.md), https://digitalis.io/post/apache-cassandra-6-0-everything-that-changed-in-one-page, secondary). MongoDB has JSON Schema validation from 3.6 ([03](../../research/03-key-value-document-distributed.md), https://www.mongodb.com/docs/v5.0/core/schema-validation/).
- **Declared uniqueness instead of find-or-create.** Neo4j's `MERGE` can create duplicates under concurrency without a uniqueness constraint; Neo4j recommends constraints ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://neo4j.com/docs/cypher-manual/current/clauses/merge/).
- **Constraints in the schema.** TypeDB has typed relations with constraints in the schema ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Checks run inside the serial writer.** Datomic's longer checks run as transaction functions inside the transactor, and `:db/cas` aborts if a value changed ([05](../../research/05-databases-that-keep-history.md), https://docs.datomic.com/transactions/transaction-functions.html).
- **Assertions that roll back.** XTDB's `ASSERT` predicates roll the transaction back if false ([05](../../research/05-databases-that-keep-history.md), https://docs.xtdb.com/about/txs-in-xtdb.html).
- **Rules checked over a merged result.** Dolt verifies check constraints on merged rows; foreign-key and unique-key breakages land in `dolt_constraint_violations`, which blocks commit until empty unless forced ([06](../../research/06-divergent-copies-and-merging.md), https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/, https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/).
- **A fixed domain with hard-coded rules.** TigerBeetle has a fixed schema of accounts and debit/credit transfers ([00](../../research/00-landscape-overview.md); [08](../../research/08-correctness-first-databases.md), https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md).

## The problem it solves

- **Bad data that spreads.** Schemas came back to MongoDB and Cassandra; the research file's reading is that bad data spread through schemaless collections ([03](../../research/03-key-value-document-distributed.md), inference).
- **Quiet errors under concurrency.** Agents retry and run in parallel, and a `MERGE` duplicate is a quiet error nobody notices ([04](../../research/04-models-that-lost-or-stayed-niche.md), inference).
- **Merges correct row by row but wrong in meaning.** One branch moves a meeting's start, the other its end; the cell-wise merge may produce a meeting that ends before it starts, and Dolt catches it only if a check constraint was declared ([06](../../research/06-divergent-copies-and-merging.md), inference).
- **Write skew.** Under snapshot isolation two transactions can each check that x + y stays positive and each write a different one, breaking the rule ([01](../../research/01-relational-and-transactional.md)). See [Serializable by default](serializable-by-default.md).

## What it costs

- **Schema comes first** ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Every rule checked over the merged result**, not each side ([06](../../research/06-divergent-copies-and-merging.md)).
- **Coordination for some rules.** *Invariant confluence* (I-confluence) draws the line: a rule can be kept without coordination only if any two valid states grown from a common ancestor always merge into a valid state (https://www.vldb.org/pvldb/vol8/p185-bailis.pdf). Uniqueness of a chosen value, auto-increment ids, foreign-key deletes and "counter > k" under decrement fail that test; one side must see the other, or something decides afterwards ([06](../../research/06-divergent-copies-and-merging.md)).
- **One domain.** TigerBeetle enforces rich domain invariants only by hard-coding a single domain ([00](../../research/00-landscape-overview.md), inference); agents would struggle with its fixed schema of only accounts and transfers ([08](../../research/08-correctness-first-databases.md)).
- **A single writer.** Datomic's transaction functions run on the one transactor, which bounds write throughput ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Off by default.** Cassandra's `CHECK` constraints are off by default and alpha only ([03](../../research/03-key-value-document-distributed.md)).

## Systems that use it

- [TigerBeetle](../systems/tigerbeetle.md): fixed ledger domain ([00](../../research/00-landscape-overview.md); [08](../../research/08-correctness-first-databases.md)).
- [Dolt](../systems/dolt.md): constraints checked over the merged result ([06](../../research/06-divergent-copies-and-merging.md)).
- [Neo4j](../systems/neo4j.md): uniqueness constraints recommended over `MERGE` alone ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- [Apache Cassandra](../systems/cassandra.md): CQL `CHECK` in 6.0 alpha ([03](../../research/03-key-value-document-distributed.md)).
- [MongoDB](../systems/mongodb.md): JSON Schema validation ([03](../../research/03-key-value-document-distributed.md)).
- [TypeDB](../systems/typedb.md): constraints in the schema ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- [Datomic](../systems/datomic.md): transaction functions on the transactor ([05](../../research/05-databases-that-keep-history.md)).
- [XTDB](../systems/xtdb.md): `ASSERT` predicates ([05](../../research/05-databases-that-keep-history.md)).

## Cannot be combined with

Merges that can never reject a write, such as CRDTs. Rules that need rejection (uniqueness, "never below zero") cannot be kept by them ([06](../../research/06-divergent-copies-and-merging.md)). See [Data types that merge themselves](data-types-that-merge-themselves.md) and [Last writer wins](last-writer-wins.md).

## Disagreements

- **Whether any general system enforces declared invariants across transactions.** [00](../../research/00-landscape-overview.md) says only TigerBeetle enforces rich domain invariants and no general system lets users declare cross-transaction invariants; this claim is marked as its own inference. [05](../../research/05-databases-that-keep-history.md) describes Datomic transaction functions running checks on the serial transactor and XTDB `ASSERT` predicates that roll a transaction back. [06](../../research/06-divergent-copies-and-merging.md) describes Dolt checking constraints over the merged result. [04](../../research/04-models-that-lost-or-stayed-niche.md) lists TypeDB constraints in the schema.

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- https://digitalis.io/post/apache-cassandra-6-0-everything-that-changed-in-one-page
- https://www.mongodb.com/docs/v5.0/core/schema-validation/
- https://neo4j.com/docs/cypher-manual/current/clauses/merge/
- https://docs.datomic.com/transactions/transaction-functions.html
- https://docs.xtdb.com/about/txs-in-xtdb.html
- https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/
- https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/
- https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md
- https://www.vldb.org/pvldb/vol8/p185-bailis.pdf
