# Analytical stores and lakehouse formats

Databases and file formats built for few, large reads over many rows rather than many small writes. They include column-store warehouses and **lakehouse** formats, which keep warehouse tables as open files in cheap object storage.

## What they are for

- **OLAP rather than OLTP.** OLTP (online transaction processing) is many small reads and writes of a few rows each. OLAP (online analytical processing) is few large reads over many rows ([research 02](../../research/02-analytical-and-specialised.md)).
- **Scans and aggregates over billions of rows** ([C-Store, VLDB 2005](https://www.vldb.org/conf/2005/papers/p553-stonebraker.pdf)).
- **Why they split from transactional databases.** In 2005 Stonebraker and Çetintemel argued that OLTP engines are "write-optimized" while warehouses must be "read optimized", where a column store "is drastically more efficient". They added a human reason: administrators kept analysts off operational systems, "fearing that the complex ad-hoc queries from these users will degrade response time" ([One size fits all](https://cs.brown.edu/research/db/publications/fits_all.pdf)). So the split has two causes: storage layout, and **workload interference**, one kind of work slowing the other. A 2025 retelling agrees the two converged on everything except "storage engines" ([Neon blog](https://neon.com/blog/htap-is-dead)).
- **Lakehouse formats** put warehouse tables in cheap object storage as open files that many engines can read ([research 02](../../research/02-analytical-and-specialised.md)).

## Members

- [ClickHouse](../systems/clickhouse.md): column store with immutable parts merged in the background; updates and deduplication settle at an unknown time.
- [DuckDB](../systems/duckdb.md): column store as a library inside one process; one writing process.
- [Snowflake](../systems/snowflake.md): cloud warehouse on immutable micro-partitions; writers to one table block each other.
- [Apache Iceberg](../systems/iceberg.md): open table format; commits swap a metadata pointer and retry on conflict.
- [DuckLake](../systems/ducklake.md): Parquet data with all metadata in a SQL database; throughput capped by that catalog.

Mentioned in the sources without a page of their own:

- Teradata: hashes each row's key to one of many parallel units; a poor key causes skew ([Teradata docs](https://docs.teradata.com/r/Enterprise_IntelliFlex_VMware/Database-Design/Indexes-and-Maps/Primary-Indexes-and-Primary-AMP-Indexes)).
- Vertica: commercial form of C-Store; many small loads create many containers and merge work ([Vertica KB](https://www.vertica.com/kb/Data-Loading-in-Vertica-Using-COPY/Content/BestPractices/Data-Loading-in-Vertica-Using-COPY.htm)).
- C-Store: the 2005 research column store ([VLDB 2005](https://www.vldb.org/conf/2005/papers/p553-stonebraker.pdf)).
- Apache Parquet: a file of row groups, one chunk per column, metadata written after the data, never edited in place ([Parquet](https://parquet.apache.org/docs/file-format/)).
- Vortex: a 2025 file format meant to replace Parquet, donated to the Linux Foundation (Pavlo).
- Lance: another 2025 Parquet replacement (Pavlo).
- Nimble: another 2025 Parquet replacement (Pavlo).
- MotherDuck: announced DuckLake 1.0 on its platform ([MotherDuck](https://motherduck.com/blog/announcing-ducklake-1-0-on-motherduck/)).
- HyPer: 2011 system that ran analytics on an operating-system copy-on-write snapshot of the OLTP process ([VLDB 2011](https://vldb.org/pvldb/vol4/p1367-funke.pdf)).
- SAP HANA: writes go to a delta store merged into the main store; every read reads both ([SAP help](https://help.sap.com/doc/saphelp_ewm900/9.0/en-US/62/9d41934c0744ef9a8f21fa4c70baa3/content.htm)).
- Oracle Database In-Memory: a columnar copy in memory kept "transactionally consistent" with the rows ([Oracle docs](https://docs.oracle.com/en/database/oracle/oracle-database/26/inmem/intro-to-in-memory-column-store.html)).
- TiDB and TiFlash: columnar replicas that receive the Raft log without voting ([PingCAP docs](https://docs.pingcap.com/tidb/stable/tiflash-overview/)).
- SingleStore: row store and column store in one engine ([Neon blog](https://neon.com/blog/htap-is-dead)).
- Snowflake hybrid tables (Unistore): a row store with row locks beside columnar storage, with a 2 TB quota and missing features ([Snowflake docs](https://docs.snowflake.com/en/user-guide/tables-hybrid-limitations)).
- Mooncake (Databricks): bought on 2025-10-01 to mirror Postgres changes "in real time to the lakehouse" ([Databricks](https://www.databricks.com/blog/mooncake-labs-joins-databricks-accelerate-vision-lakebase)).

## Shared tradeoffs

- **Fast scans are paid for by slow single-row changes.** Data is kept in [columns](../ideas/column-storage.md) and in [write-once pieces merged in the background](../ideas/immutable-pieces-with-background-merge.md). A change rewrites or adds pieces, and background merges do the rest ([research 02](../../research/02-analytical-and-specialised.md)).
- **Data can be visible before it is settled.** ClickHouse's deduplication waits for a merge at "an unknown time" ([ReplacingMergeTree](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/replacingmergetree)).
- **Lakehouse formats are slow at small and concurrent writes.** Each change writes several files, and concurrent commits retry ([research 02](../../research/02-analytical-and-specialised.md)). DuckLake's authors call these the two biggest performance problems of data lakes ([manifesto](https://ducklake.select/manifesto/)). See [object storage as the only durable store](../ideas/object-storage-as-source-of-truth.md).
- **Time travel costs storage.** Old files or micro-partitions are kept until cleanup ([research 02](../../research/02-analytical-and-specialised.md)); Snowflake bills the storage throughout ([storage costs](https://docs.snowflake.com/en/user-guide/data-cdp-storage-costs)).
- **Rejoining transactions and analytics keeps two layouts.** Every attempt found keeps two layouts and pays to keep them in step; the rejoin has since moved outside the database, to change streams feeding a lagging copy ([research 02](../../research/02-analytical-and-specialised.md)). See [transactions and analytics together](../ideas/transactions-and-analytics-together.md).
- **What agents struggle with.** Writes visible but not settled; lock timeouts that look like hangs; cost that grows with bytes scanned, unseen in advance; commit failures that need a retry policy; compaction and snapshot expiry that nobody owns ([research 02](../../research/02-analytical-and-specialised.md)).
- **The wave is about file formats and metadata.** Five new formats to replace Parquet appeared in 2025, and DuckLake moved lakehouse metadata into a SQL database ([research 00](../../research/00-landscape-overview.md)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- Primary links are given inline above.
