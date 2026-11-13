# Datomic

Datomic is a database that stores facts and never edits them in place, so any past moment can be queried. It was released in 2012 and has been free since 2023.

## What it is for

Datomic was built so a database can be held as a value frozen in time, instead of a place that is overwritten ([05](../../research/05-databases-that-keep-history.md), https://blog.datomic.com/2023/04/datomic-is-free.html). It serves audit, history and "as of" queries ([00](../../research/00-landscape-overview.md), https://docs.datomic.com/transactions/model.html).

## Core idea

- Data is made of *datoms*. A datom is one fact: entity, attribute, value, transaction, and whether it was added or retracted. A change adds datoms; nothing is edited ([05](../../research/05-databases-that-keep-history.md), https://docs.datomic.com/transactions/acid.html). See [Facts that are added, never changed](../ideas/append-only-facts.md).
- One process, the *transactor*, applies every write in order. Writes are "strong serializable because they are fully serialized" (https://docs.datomic.com/transactions/acid.html). Every transaction does a compare-and-swap on the log's root ([04](../../research/04-models-that-lost-or-stayed-niche.md)). See [One writer at a time](../ideas/one-writer-at-a-time.md).
- The query language is *Datalog*: queries are made of rules, which may call themselves recursively ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- Datomic dropped the assumption that rows can be changed in place. What it got: free history, queries as of any time, and audit ([00](../../research/00-landscape-overview.md)).

## Strengths and what pays for each

- **Any reader can query any past moment, without locks.** Paid for by a single writer, capped by one machine ([05](../../research/05-databases-that-keep-history.md)). See [Reading the database as it was](../ideas/time-travel-queries.md).
- **Serial writes with compare-and-swap.** Paid for by one transactor bounding write throughput ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **A transaction is an entity you can annotate.** You "can add additional attributes ... such as the purpose of the transaction, the application that executed it, the provenance of the data ..., or the user who caused it" (https://docs.datomic.com/transactions/transaction-data-reference.html). Paid for by every team designing its own attributes; nothing checks them ([05](../../research/05-databases-that-keep-history.md)).

## Weaknesses

- **History grows forever.** Often-changing values grow the database without end. Datomic advises turning history off (`noHistory`) for "a counter or version incrementer" because of "database size or indexing performance" (https://docs.datomic.com/reference/best.html).
- **Deleting is slow and sits outside history.** *Excision* (permanent removal of datoms) "happens outside the timeline of Datomic history" and runs at the next indexing job. Large excisions cost indexing "proportional to the size of the entire database" and reduce write availability, so keep each to a few thousand datoms. It is deliberately lossy: you cannot ask whether a datom ever existed (https://docs.datomic.com/operation/excision.html). `noHistory` exists "to conserve storage, not to make semantic guarantees about removing information" (https://docs.datomic.com/schema/schema-reference.html). A 2018 write-up found no excision in Datomic Cloud and advised keeping personal data in a separate store (https://vvvvalvalval.github.io/posts/2018-05-01-making-a-datomic-system-gdpr-compliant.html). Whether Datomic Cloud supports excision today is not confirmed ([05](../../research/05-databases-that-keep-history.md)). See [Deleting personal data from a store that keeps history](../ideas/deleting-personal-data-from-history.md).
- **Schema can only grow.** "You can never alter :db/valueType"; "grow your schema, and never break it" (https://docs.datomic.com/schema/schema-change.html, https://blog.datomic.com/2017/01/the-ten-rules-of-schema-growth.html). See [Schemas that only grow](../ideas/grow-only-schema.md).
- **Clause order is the query plan.** `:where` clauses "are executed in order", so the writer must put "the most selective clauses first" (https://docs.datomic.com/reference/best.html). That is manual query optimisation in a declarative language ([04](../../research/04-models-that-lost-or-stayed-niche.md)). See [Set-at-a-time queries](../ideas/set-at-a-time-queries.md).
- **Binaries are free, source is not open.** Datomic became free under Apache 2.0 in April 2023, but the source is not open (https://forum.datomic.com/t/datomic-is-now-free/2208).

## Overlapping work

- `:db/cas` (compare-and-swap) aborts a transaction if a value is no longer what the writer expected (https://docs.datomic.com/transactions/transaction-functions.html).
- Longer checks run as *transaction functions* inside the transactor, so they see every earlier write ([05](../../research/05-databases-that-keep-history.md)). See [Invariants the database enforces](../ideas/invariants-the-database-enforces.md).

## What an agent struggles with

- Deletion is a separate background process ([05](../../research/05-databases-that-keep-history.md)).
- Datomic's single writer plus compare-and-swap is close to a one-operation-at-a-time rule, which suits agents (inference, [04](../../research/04-models-that-lost-or-stayed-niche.md)).
- The reason for a write can be recorded, but is optional and unchecked. Teams invent attributes like "admin user working on behalf of another user" (https://cjohansen.no/annotating-datomic-transactions/). See [Recording why a write happened](../ideas/recording-why-a-write-happened.md).

## Worth borrowing

These are the researchers' inference.

- Reads against a frozen value while writes continue. Costs a single writer ([05](../../research/05-databases-that-keep-history.md)).
- Single writer plus compare-and-swap. Costs write throughput bounded by one writer ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- The transaction as a record with a required, typed reason, requester and approver. Datomic shows the slot; the cost is designing a schema for intent and making every writer supply it ([05](../../research/05-databases-that-keep-history.md)).
- Grow-only schema, so history is never rewritten ([05](../../research/05-databases-that-keep-history.md)).

## Disagreements

- **Does Datomic ever remove data?** [00](../../research/00-landscape-overview.md) says Datomic accumulates facts and never updates in place. [05](../../research/05-databases-that-keep-history.md) adds that `noHistory` and excision let history be dropped.
- **Who made a change.** [00](../../research/00-landscape-overview.md) says bitemporal stores record when a fact changed and who wrote it, but not why. [05](../../research/05-databases-that-keep-history.md) says Datomic can hold a purpose or requester only in optional, unchecked transaction attributes.
- **Cross-transaction invariants.** [00](../../research/00-landscape-overview.md) says only TigerBeetle enforces rich domain invariants (marked inference). [05](../../research/05-databases-that-keep-history.md) describes Datomic transaction functions running checks on the serial transactor.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- https://docs.datomic.com/transactions/acid.html
- https://docs.datomic.com/transactions/model.html
- https://docs.datomic.com/transactions/transaction-functions.html
- https://docs.datomic.com/transactions/transaction-data-reference.html
- https://docs.datomic.com/reference/best.html
- https://docs.datomic.com/operation/excision.html
- https://docs.datomic.com/schema/schema-reference.html
- https://docs.datomic.com/schema/schema-change.html
- https://blog.datomic.com/2017/01/the-ten-rules-of-schema-growth.html
- https://blog.datomic.com/2023/04/datomic-is-free.html
- https://forum.datomic.com/t/datomic-is-now-free/2208
- https://vvvvalvalval.github.io/posts/2018-05-01-making-a-datomic-system-gdpr-compliant.html
- https://cjohansen.no/annotating-datomic-transactions/
