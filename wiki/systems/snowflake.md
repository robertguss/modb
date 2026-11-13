# Snowflake

Snowflake is a cloud data warehouse. It stores tables as immutable columnar micro-partitions, scales compute separately, and keeps a bounded window of history. It belongs to the [analytical and lakehouse family](../families/analytical-and-lakehouse.md).

## What it is for

- Scans and aggregates over very large tables. It is one of the current generation of column stores, with ClickHouse and DuckDB ([research 02](../../research/02-analytical-and-specialised.md)). See [storing data by column](../ideas/column-storage.md).
- Snowflake bought Crunchy Data, a PostgreSQL company, for $250M ([Pavlo, Jan 2026](https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html)).

## Core idea

- **[Write-once pieces](../ideas/immutable-pieces-with-background-merge.md).** A **micro-partition** is one of the small immutable columnar files a table is split into. When rows change, "all of the impacted micro-partitions are re-created" ([micro-partitions](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions), read by research 02 through a [course page](https://www.datainterview.com/courses/snowflake/micro-partitions) quoting it).
- **[Locks held until commit](../ideas/locks-held-until-commit.md) for writes.** `UPDATE`, `DELETE` and `MERGE` "hold locks that prevent them from running in parallel" with each other; a blocked statement waits up to `LOCK_TIMEOUT` ([transactions](https://docs.snowflake.com/en/sql-reference/transactions)).

## Strengths and what pays for each

- **Elastic compute and pruning** (skipping micro-partitions a query cannot need). *Paid for by* immutable micro-partitions that are re-created on change ([research 02](../../research/02-analytical-and-specialised.md)).
- **[Time travel](../ideas/time-travel-queries.md).** `AT` and `BEFORE` reach back 1 day by default and up to 90 days on Enterprise, followed by 7 days of Fail-safe that only Snowflake can recover ([time travel](https://docs.snowflake.com/en/user-guide/data-time-travel)). *Paid for by* storage billed throughout ([storage costs](https://docs.snowflake.com/en/user-guide/data-cdp-storage-costs)).
- **Row-level transactions beside the warehouse.** Hybrid tables (formerly Unistore) are a row store with row locks beside columnar storage ([transactions](https://docs.snowflake.com/en/sql-reference/transactions)). *Paid for by* a list of limits: a 2 TB row-store quota per database; no streams, clustering keys, data sharing or replication; and space from deletes takes "some number of hours" to return ([hybrid table limits](https://docs.snowflake.com/en/user-guide/tables-hybrid-limitations)). See [transactions and analytics together](../ideas/transactions-and-analytics-together.md).

## Weaknesses

- **Writers to one table block each other** ([transactions](https://docs.snowflake.com/en/sql-reference/transactions)).
- **History expires** after the retention window ([research 05](../../research/05-databases-that-keep-history.md)).
- **History records time and transaction only**, not the user or the reason ([research 05](../../research/05-databases-that-keep-history.md)).
- **Hybrid tables see little use**, according to one practitioner who built a competing system. Research 02 marks this as his view, not a measurement ([Neon blog](https://neon.com/blog/htap-is-dead)).

## Overlapping work

- Writing statements on the same table take locks and queue, each waiting up to `LOCK_TIMEOUT` ([transactions](https://docs.snowflake.com/en/sql-reference/transactions)).

## What an agent struggles with

From research 02:

- **Lock timeouts that look like hangs.**
- **Cost that grows with bytes scanned**, unseen in advance.

## Worth borrowing

- **Bounded history windows.** These are what mainstream users actually accept ([research 05](../../research/05-databases-that-keep-history.md)).

## Disagreements

- **Whether history-keeping stores record who made a change.** Research 00 says bitemporal stores record when a fact changed and who wrote it, but not why. Research 05 says Snowflake records only time and transaction, with no user.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- Primary links are given inline above.
