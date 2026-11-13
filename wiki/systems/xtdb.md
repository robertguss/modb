# XTDB

XTDB is a database in which every table keeps two timelines for each fact. Version 2 became generally available in June 2025.

## What it is for

Audit, history and "as of" queries, including corrections made after the fact ([00](../../research/00-landscape-overview.md), https://www.xtdb.com/blog/launching-xtdb-v2).

## Core idea

- Every table is *bitemporal*: each fact has a *system time* (when the database learned it) and a *valid time* (when it was true in the world). A correction today about last March keeps both what was believed and what is now known ([05](../../research/05-databases-that-keep-history.md)). See [Two timelines](../ideas/valid-time-and-system-time.md).
- Writes are "serialized via a totally-ordered log" and applied one at a time (https://docs.xtdb.com/about/txs-in-xtdb.html). See [One writer at a time](../ideas/one-writer-at-a-time.md).
- XTDB dropped the assumption that rows can be changed in place. What it got: free history, queries as of any time, and audit ([00](../../research/00-landscape-overview.md)).

## Strengths and what pays for each

- **Two timelines on every table.** Paid for by one writer and no interactive write transactions ([05](../../research/05-databases-that-keep-history.md)).
- **`ERASE` removes data for good.** It "irrevocably erases documents ... for all valid-time, for all system-time" (https://docs.xtdb.com/reference/main/sql/txs.html). Whether it leaves a trace that an erase happened is not confirmed ([05](../../research/05-databases-that-keep-history.md)).
- **Transaction metadata.** From v2.1, `METADATA` attaches free-form data to a transaction "to attach upstream request IDs, correlation IDs, or other data lineage information" (https://docs.xtdb.com/reference/main/sql/txs.html). Paid for by nothing checking it; it is free-form ([05](../../research/05-databases-that-keep-history.md)).
- **Queries default to the present** ([05](../../research/05-databases-that-keep-history.md)).

## Weaknesses

- **Two-axis queries are easy to get wrong** ([05](../../research/05-databases-that-keep-history.md)).
- **No interactive writes.** A client cannot read, decide and write inside one transaction (https://docs.xtdb.com/about/txs-in-xtdb.html).

## Overlapping work

Because a client cannot read and write inside one transaction, it sends `ASSERT` predicates instead. A false predicate rolls the transaction back (https://docs.xtdb.com/about/txs-in-xtdb.html). See [Writes that carry their assumptions](../ideas/writes-that-carry-their-assumptions.md).

## What an agent struggles with

Two time axes double the ways a query can be wrong. "As of when?" is easy to forget ([05](../../research/05-databases-that-keep-history.md)).

## Worth borrowing

These are the researcher's inference ([05](../../research/05-databases-that-keep-history.md)).

- Valid time beside system time for corrections. Costs an "as of when?" on every query and care with writes that split periods.
- A transaction record that carries a reason. XTDB's `METADATA` shows the slot; filling and checking it is left to the writer. See [Recording why a write happened](../ideas/recording-why-a-write-happened.md).

## Disagreements

- **Who made a change.** [00](../../research/00-landscape-overview.md) says bitemporal stores record when a fact changed and who wrote it, but not why. [05](../../research/05-databases-that-keep-history.md) says XTDB can hold a purpose or requester only in optional, unchecked transaction metadata.
- **Cross-transaction invariants.** [00](../../research/00-landscape-overview.md) says no general system lets users declare invariants that hold across transactions (marked inference). [05](../../research/05-databases-that-keep-history.md) describes `ASSERT` predicates that roll a transaction back.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- https://www.xtdb.com/blog/launching-xtdb-v2
- https://docs.xtdb.com/about/txs-in-xtdb.html
- https://docs.xtdb.com/reference/main/sql/txs.html
