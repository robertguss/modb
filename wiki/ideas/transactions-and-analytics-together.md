# Transactions and analytics in one system

One database that serves both many small transactional writes (OLTP) and large analytical reads (OLAP) on the same live data. Gartner named the goal **HTAP**, hybrid transactional/analytical processing, in 2014.

## What it is

- OLTP is many small reads and writes of a few rows each; OLAP is few large reads over many rows ([research 02](../../research/02-analytical-and-specialised.md)).
- HTAP aims to run both in one system, so analytics see fresh data without a separate copy ([Neon blog](https://neon.com/blog/htap-is-dead)).

## The problem it solves

- The two kinds of system split for two reasons ([research 02](../../research/02-analytical-and-specialised.md)):
  - **Storage layout.** OLTP engines are "write-optimized"; warehouses must be "read optimized", where a column store "is drastically more efficient" ([Stonebraker and Çetintemel, 2005](https://cs.brown.edu/research/db/publications/fits_all.pdf)).
  - **Workload interference.** Administrators kept analysts off operational systems, "fearing that the complex ad-hoc queries from these users will degrade response time" (same paper).
- Without HTAP, analytics run on a copy that lags the live data ([research 02](../../research/02-analytical-and-specialised.md)).

## What it costs

Every attempt research 02 found keeps two layouts of the data and pays to keep them in step:

| Attempt | How it rejoins | What it costs |
|---|---|---|
| HyPer (2011) | Forks the OLTP process; analytics run on the operating system's copy-on-write snapshot ([VLDB 2011](https://vldb.org/pvldb/vol4/p1367-funke.pdf)) | Pages copied as OLTP writes; the group later used multi-version concurrency instead (seen only in a [review](http://muratbuffalo.blogspot.com/2022/08/fast-serializable-multi-version.html)) |
| SAP HANA | Writes go to a write-optimised **delta store**; a **delta merge** moves them into the compressed main store ([SAP help](https://help.sap.com/doc/saphelp_ewm900/9.0/en-US/62/9d41934c0744ef9a8f21fa4c70baa3/content.htm)) | Every read reads both stores and merges results; merging is recurring work |
| Oracle In-Memory | Rows in the buffer cache plus a columnar copy in memory, kept "transactionally consistent" ([Oracle docs](https://docs.oracle.com/en/database/oracle/oracle-database/26/inmem/intro-to-in-memory-column-store.html)) | Memory for a second copy and change tracking on writes (inference) |
| TiDB + TiFlash | Columnar replicas are Raft **learners**: they receive the log but do not vote, so OLTP never waits for them; reads check the Raft index ([PingCAP](https://docs.pingcap.com/tidb/stable/tiflash-overview/); [VLDB 2020](https://www.vldb.org/pvldb/vol13/p3072-huang.pdf)) | A second full copy; an analytical read may wait for its replica to catch up |
| SingleStore | Row store and column store in one engine ([Neon blog](https://neon.com/blog/htap-is-dead)) | Two engines to build and tune |
| Snowflake hybrid tables (was Unistore) | Row store with row locks beside columnar storage ([Snowflake](https://docs.snowflake.com/en/sql-reference/transactions)) | 2 TB row-store quota per database; no streams, clustering keys, data sharing or replication; space from deletes takes "some number of hours" to return ([limits](https://docs.snowflake.com/en/user-guide/tables-hybrid-limitations)) |

**Why it did not catch on.** The SingleStore builder gives four reasons: replacing an OLTP system is "really, really hard"; most workloads fit one large machine; the cloud favoured object storage over fast local disks; and OLTP and OLAP "are owned by different teams". Two of the four are organisational. He also says few companies use Snowflake hybrid tables, which is his view, not a measurement ([Neon blog](https://neon.com/blog/htap-is-dead)).

**What replaced it.** The rejoin moved outside the database. Change data capture (CDC, streaming the transaction log out) feeds an open-format copy. Databricks bought Mooncake on 2025-10-01 to mirror Postgres changes "in real time to the lakehouse" ([Databricks](https://www.databricks.com/blog/mooncake-labs-joins-databricks-accelerate-vision-lakebase)). That is the lagging second copy HTAP set out to avoid.

Research 02's inference: every design accepts either a lagging second copy or read-time merging of a write layer with a read layer. None removed the cost; each chose where to put it.

## Systems that use it

- [Snowflake](../systems/snowflake.md): hybrid tables.
- [Oracle Database](../systems/oracle.md): Database In-Memory.
- Also in the table above, without pages of their own: HyPer, SAP HANA, TiDB with TiFlash, SingleStore.

## Cannot be combined with

- **A single storage layout.** No attempt found serves both workloads from one layout; each keeps a second copy or a second store (inference, [research 02](../../research/02-analytical-and-specialised.md)). See [storing data by column](column-storage.md) and [derived copies fed from one log](derived-copies-fed-from-one-log.md).

## Sources

- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- Primary links are given inline above.
