# Reading the database as it was

A *time-travel query* reads the data as it stood at an earlier moment. Some systems keep that past forever; mainstream ones keep a bounded window.

## What it is

A query that names a past point ("as of last Tuesday") and gets the data as it was then. Systems differ in how far back they reach and where the old versions live ([05](../../research/05-databases-that-keep-history.md)).

## The problem it solves

Audit, history and "as of" questions ([00](../../research/00-landscape-overview.md)). In [Datomic](../systems/datomic.md), any reader can query any past moment without locks ([05](../../research/05-databases-that-keep-history.md)).

## What it costs

- **Storage.** Old versions must be kept. Iceberg pays by keeping old files until cleanup runs ([02](../../research/02-analytical-and-specialised.md)). Snowflake bills storage throughout its window (https://docs.snowflake.com/en/user-guide/data-cdp-storage-costs).
- **"Now" gets dearer** unless current state is kept separately. Datomic and XTDB default to the present ([05](../../research/05-databases-that-keep-history.md)).
- **Reads can fail once history is gone.** Oracle Flashback Query fails with "snapshot too old" once undo is overwritten (https://docs.oracle.com/en/database/oracle/oracle-database/18/admin/managing-undo.html).
- **Unbounded history was given up once.** POSTGRES dropped time travel in v6.2 for "performance impact, storage size, and a pg_time file which grows toward infinite size" (https://www.postgresql.org/docs/6.3/c0503.htm).
- **Somebody must own expiry.** For lakehouse tables, [02](../../research/02-analytical-and-specialised.md) lists "compaction and snapshot expiry that nobody owns" among what an agent struggles with.

## Systems that use it

- [Datomic](../systems/datomic.md) and [XTDB](../systems/xtdb.md): history is kept by design; queries default to the present ([05](../../research/05-databases-that-keep-history.md)).
- [SQL:2011 temporal tables](../systems/sql-temporal-tables.md): a history table beside the live one, retention infinite by default in SQL Server ([05](../../research/05-databases-that-keep-history.md)).
- [Snowflake](../systems/snowflake.md): `AT`/`BEFORE` reach back 1 day by default, up to 90 on Enterprise, then 7 days of Fail-safe only Snowflake can recover (https://docs.snowflake.com/en/user-guide/data-time-travel).
- [Oracle](../systems/oracle.md): Flashback Query reads *undo*, the old row images kept for rollback. Flashback Time Travel copies changes into history tables even a DBA cannot edit (https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html).
- [Apache Iceberg](../systems/iceberg.md): reading an earlier commit, paid for by keeping old files until cleanup ([02](../../research/02-analytical-and-specialised.md)).
- [PostgreSQL](../systems/postgresql.md): Berkeley POSTGRES had time travel and dropped it; the no-overwrite storage survived as multi-version reads (https://dev.to/franckpachot/postgresql-multi-version-from-time-travel-to-concurrency-control-b5).

The researcher's reading: bounded history windows are what mainstream users actually accept ([05](../../research/05-databases-that-keep-history.md)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- https://docs.snowflake.com/en/user-guide/data-time-travel
- https://docs.snowflake.com/en/user-guide/data-cdp-storage-costs
- https://docs.oracle.com/en/database/oracle/oracle-database/18/admin/managing-undo.html
- https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html
- https://www.postgresql.org/docs/6.3/c0503.htm
- https://dev.to/franckpachot/postgresql-multi-version-from-time-travel-to-concurrency-control-b5
