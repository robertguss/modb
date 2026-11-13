Research run on 2026-11-13 by a subagent using Exa, for the ticket [Analytical and specialised stores](../issues/02-analytical-and-specialised.md). Nothing here was checked a second time. Lines marked "inference" are the researcher's reasoning, not a source.

# Analytical and specialised stores (researched 2026-11-13)

**OLTP** (online transaction processing) is many small reads and writes of a few rows each. **OLAP** (online analytical processing) is few large reads over many rows. A **row store** keeps each row's fields together on disk; a **column store** keeps each column's values together.

## 1. Why analytical systems split from transactional ones

In 2005 Stonebraker and Çetintemel argued that OLTP engines are "write-optimized" while warehouses must be "read optimized", where a column store "is drastically more efficient" because a query reads only the columns it needs. They added a human reason: administrators kept analysts off operational systems, "fearing that the complex ad-hoc queries from these users will degrade response time" https://cs.brown.edu/research/db/publications/fits_all.pdf. So the split has two causes: storage layout, and **workload interference** (one kind of work slowing the other). A 2025 retelling by a builder of hybrid systems agrees: the two kinds of engine converged on everything except "storage engines" (2025-05-04) https://neon.com/blog/htap-is-dead.

## 2. Column stores and warehouses

**For.** Scans and aggregates over billions of rows. Teradata hashes each row's primary-index columns to pick one of many parallel units (AMPs), so all of them scan at once https://docs.teradata.com/r/Enterprise_IntelliFlex_VMware/Database-Design/Indexes-and-Maps/Primary-Indexes-and-Primary-AMP-Indexes. Vertica is the commercial form of the C-Store research system (2005). ClickHouse, DuckDB and Snowflake are the current generation.

**Core idea.** Columnar pieces written once and never edited; changes add new pieces, and background work combines them. ClickHouse "doesn't modify existing parts, it simply writes more", then merges them https://clickhouse.com/blog/updates-in-clickhouse-2-sql-style-updates. In Snowflake, when rows change "all of the impacted micro-partitions are re-created" https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions (read through a course page quoting it, https://www.datainterview.com/courses/snowflake/micro-partitions). DuckDB is a library inside one process, not a server.

**Strengths, and what pays for each.**
- *Fast scans, high compression.* Paid for by slow single-row changes: a ClickHouse **mutation** is "I/O-heavy, rewriting all parts that match" https://clickhouse.com/docs/concepts/features/operations/update/overview.
- *Cheap bulk loads.* Paid for by merge work. In Vertica, many small loads create many storage containers and "additional work for the Tuple Mover" (its merge process) https://www.vertica.com/kb/Data-Loading-in-Vertica-Using-COPY/Content/BestPractices/Data-Loading-in-Vertica-Using-COPY.htm.
- *Parallel speed (Teradata).* Paid for by a good distribution key. A poor one causes **skew**: one unit holds most rows and the query waits for it https://docs.teradata.com/r/Enterprise_IntelliFlex_VMware/Database-Administration/Performance-Management-All-DBAs/Identifying-and-Fixing-Skewed-Tables/Primary-Index-and-Skewed-Row-Distribution.
- *No server (DuckDB).* Paid for by one writing process: either "one process can both read and write", or many read and none write https://duckdb.org/docs/2.0/connect/concurrency.

**Weaknesses.** ClickHouse's ReplacingMergeTree removes duplicates "only during a merge", at "an unknown time"; a plain `SELECT` can return stale rows unless it adds `FINAL` https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/replacingmergetree. Vertica removed its in-memory write store in version 10.0, per a user quoting release notes on its forum https://forum.vertica.com/discussion/241559/wosdata-resource-behaviour-tuning.

**Overlapping clients.**
- DuckDB uses **optimistic concurrency control**: no locks, conflicts found at commit. "Appends will never conflict"; for two edits to one row "the second thread … will fail with a conflict error" https://duckdb.org/docs/2.0/connect/concurrency.
- Snowflake locks: `UPDATE`, `DELETE` and `MERGE` "hold locks that prevent them from running in parallel" with each other, and a blocked statement waits up to `LOCK_TIMEOUT` https://docs.snowflake.com/en/sql-reference/transactions.
- ClickHouse avoids multi-row transactions. Its 2025 answer to updates is **patch parts**, small pieces holding only changed rows and columns, applied on read and folded in at the next merge; "up to 23x faster than mutations" (vendor claim) https://clickhouse.com/docs/concepts/features/operations/update/overview.

**Agent struggle.** Writes visible but not settled; lock timeouts that look like hangs; cost that grows with bytes scanned, unseen in advance.

## 3. Lakehouse formats: Parquet, Iceberg, DuckLake

**For.** Warehouse tables as open files in cheap object storage, readable by many engines.

**Core idea.**
- *Parquet*: a file of **row groups**, each holding one chunk per column; metadata is written "after the data to allow for single pass writing" https://parquet.apache.org/docs/file-format/, so files are not edited in place.
- *Iceberg*: a table is many files tracked by metadata files. A writer prepares new metadata, then "commits by swapping the table's metadata file pointer"; if another commit won, it must retry on the new version https://iceberg.apache.org/spec/. When retries run out the commit fails with `CommitFailedException` https://aws.amazon.com/blogs/big-data/manage-concurrent-write-conflicts-in-apache-iceberg-on-the-aws-glue-data-catalog/.
- *DuckLake*: Parquet data, but all metadata in a SQL database. A commit is "a single SQL transaction in the catalog database", so it "supports as many table changes as the catalog database can commit"; small changes can be stored in the catalog itself https://ducklake.select/manifesto/. 1.0 shipped 2026-04-13 https://ducklake.select/2026/04/13/ducklake-10/.

**Strengths, and what pays.** Open format and separate compute, paid for by slow small writes (each change writes several files). **Time travel** (reading an earlier commit), paid for by keeping old files until cleanup runs.

**Weaknesses.** DuckLake's authors name "small changes and many concurrent changes" as the two biggest performance problems of data lakes https://ducklake.select/manifesto/.

**Agent struggle.** Commit failures that need a retry policy; compaction and snapshot expiry that nobody owns.

## 4. Attempts to rejoin OLTP and OLAP, and their cost

Gartner named the goal **HTAP** (hybrid transactional/analytical processing) in 2014 https://neon.com/blog/htap-is-dead. Every attempt I found keeps two layouts of the data and pays to keep them in step.

| Attempt | How it rejoins | What it costs |
|---|---|---|
| HyPer (2011) | Forks the OLTP process; analytics run on the operating system's copy-on-write snapshot https://vldb.org/pvldb/vol4/p1367-funke.pdf | Pages copied as OLTP writes. The group later used multi-version concurrency control (MVCC) instead (2015; seen only in a review) http://muratbuffalo.blogspot.com/2022/08/fast-serializable-multi-version.html |
| SAP HANA | Writes go to a write-optimised **delta store**; a **delta merge** moves them into the compressed main store https://help.sap.com/doc/saphelp_ewm900/9.0/en-US/62/9d41934c0744ef9a8f21fa4c70baa3/content.htm | Every read reads both stores and merges results; merging is recurring work |
| Oracle In-Memory | Rows in the buffer cache plus a columnar copy in memory, kept "transactionally consistent" https://docs.oracle.com/en/database/oracle/oracle-database/26/inmem/intro-to-in-memory-column-store.html | Memory for a second copy and change tracking on writes (inference) |
| TiDB + TiFlash | Columnar replicas are Raft **learners**: they receive the log but do not vote, so OLTP never waits for them. Reads get snapshot isolation by checking the Raft index https://docs.pingcap.com/tidb/stable/tiflash-overview/, https://www.vldb.org/pvldb/vol13/p3072-huang.pdf | A second full copy; an analytical read may wait for its replica to catch up |
| SingleStore | Row store and column store in one engine. Its builders found "the columnstore alone could handle a surprising number of OLTP-style queries" https://neon.com/blog/htap-is-dead | Two engines to build and tune |
| Snowflake hybrid tables (was Unistore) | Row store with row locks beside columnar storage https://docs.snowflake.com/en/sql-reference/transactions | 2 TB row-store quota per database; no streams, clustering keys, data sharing or replication; space from deletes takes "some number of hours" to return https://docs.snowflake.com/en/user-guide/tables-hybrid-limitations |

**Why it did not catch on.** The SingleStore builder gives four reasons https://neon.com/blog/htap-is-dead: replacing an OLTP system is "really, really hard"; most workloads fit one large machine; the cloud favoured object storage over fast local disks; and OLTP and OLAP "are owned by different teams". Two of the four are organisational. He also says few companies use Snowflake hybrid tables, which is his view, not a measurement.

**What replaced it.** The rejoin moved outside the database. Change data capture (**CDC**, streaming the transaction log out) feeds an open-format copy. Databricks bought Mooncake on 2025-10-01 to mirror Postgres changes "in real time to the lakehouse" https://www.databricks.com/blog/mooncake-labs-joins-databricks-accelerate-vision-lakebase. That is the lagging second copy HTAP set out to avoid.

Inference: every design accepts either a lagging second copy or read-time merging of a write layer with a read layer. None removed the cost; each chose where to put it.

## 5. Time series

**For.** Metrics and events that arrive in time order and rarely change.
**Core idea and its price.** Prometheus keeps the current block in memory behind a write-ahead log, cuts two-hour blocks and compacts them later https://prometheus.io/docs/prometheus/latest/storage/. It relies on in-order samples; `Commit()` "may also refuse data that is out of order" https://github.com/prometheus/prometheus/blob/main/tsdb/docs/usage.md. TimescaleDB converts cooling time **chunks** to a compressed columnstore; updates decompress only touched batches, but without a usable filter "may convert large amounts of data to the rowstore and back" https://github.com/timescale/docs/blob/latest/use-timescale/compression/modify-compressed-data.md.
**Overlap.** Writers to separate series never conflict. Late or corrected data is the failure mode.
**Agent struggle.** Backfilling or fixing past values is the expensive path, and agents do exactly that.

## 6. Full-text search

**For.** Finding documents by words, ranked by relevance.
**Core idea.** An **inverted index** maps each word to the documents containing it. Lucene stores it as immutable **segments**; a document is searchable only after a **refresh**. Elasticsearch refreshes every second, "but only on indices that have received one search request or more in the last 30 seconds" https://www.elastic.co/docs/manage-data/data-store/near-real-time-search.
**Strength and price.** Fast ranked search, paid for by **near-real-time** visibility (writes are not visible at once) and segment merging.
**Overlap.** Optimistic per document: a write carries `if_seq_no` and `if_primary_term` and fails if the document changed https://www.elastic.co/docs/reference/elasticsearch/rest-apis/optimistic-concurrency-control.
**Agent struggle.** Write, search at once, find nothing.

## 7. Vector

**For.** Finding items nearest an embedding (a list of numbers standing for meaning).
**Core idea.** Approximate indexes such as **HNSW**, a layered graph linking each item to near neighbours.
**Strength and price.** Fast search, paid for by possibly incomplete answers. In pgvector, filters apply after the index scan: with a condition matching 10% of rows, "only 4 rows will match on average" by default; 0.8.0 added iterative scans https://docs.pgedge.com/pgvector/development/filtering/ (a mirror of pgvector's docs). Deletes leave **tombstones** (markers); "the search still traverses deleted nodes" and recall can drift https://multigrid.ai/learn/index-updates (secondary). Weaviate's code shows the mechanism https://github.com/weaviate/weaviate/blob/master/adapters/repos/db/vector/hnsw/delete.go.
**Agent struggle.** A filtered search returns too few results, with no error.

## 8. Spatial

**For.** Shapes that overlap or lie near a point or region.
**Core idea.** An **R-tree** (in PostGIS, built through Postgres's GiST index type) nests rectangles; spatial indexes "index the bounding boxes of the features", not the shapes https://postgis.net/workshops/en/postgis-intro/indexing.html.
**Strength and price.** Fast candidate search, paid for by an exact second test; the box operator `&&` alone over-counts, as the same page shows.
**Agent struggle.** Using the box test alone and trusting the answer.

## Summary table

| System | Strength | What pays for it | Weakness |
|---|---|---|---|
| Teradata | Parallel scans on every unit | Rows placed by hash of a key | Skew from a poor key |
| Vertica | Column storage, compression | Write-once containers, merge work | Small loads create too many containers |
| ClickHouse | Very fast inserts and scans | Immutable parts, background merges | Updates and deduplication settle at an unknown time |
| DuckDB | No server, fast local analytics | One writing process | Same-row conflicts abort |
| Snowflake | Elastic compute, pruning | Immutable micro-partitions | Writers to one table block each other |
| Parquet | Compact, open | Write-once files | No in-place edits |
| Iceberg | Open tables, time travel | Optimistic pointer-swap commits | Slow small and concurrent writes; retries |
| DuckLake | Fast small commits | A SQL catalog database | Throughput capped by the catalog |
| HTAP (HyPer, HANA, Oracle, TiDB) | Fresh analytics on live data | A second layout kept in step | Extra memory or storage; lag or read-time merging |
| Prometheus, TimescaleDB | Cheap appends, compression | In-order arrival | Late writes and backfills are costly |
| Lucene / Elasticsearch | Ranked text search | Immutable segments, periodic refresh | Writes not visible at once |
| HNSW (pgvector) | Fast similarity search | Approximate answers | Filters and deletes cut recall silently |
| R-tree (PostGIS) | Fast spatial candidates | Bounding boxes only | Needs an exact second test |

## Ideas worth borrowing

1. **Immutable pieces plus background merge.** Simple crash safety and lock-free reads. Cost: merge work, and a window where data is visible but unsettled, which the database must report.
2. **Derived indexes fed from one log, like a Raft learner.** Text, vector and column copies that never block a write and can be rebuilt. Cost: lag.
3. **Freshness in the interface.** Like Elasticsearch's refresh or TiFlash's Raft-index check, an agent could ask "does this read include my write?" Cost: a wait on the read path.
4. **Metadata in a transactional catalog, data in plain files (DuckLake).** The catalog is the single point of order, which suits one operation at a time. Cost: throughput equals the catalog's.
5. **Approximate index plus exact check (spatial).** The approximation is never the final answer. Cost: a second pass; vectors have no cheap exact check.
6. **Patch parts instead of rewrites (ClickHouse).** A small change records only what changed. Cost: reads apply patches until a merge.

## What I could not confirm

- Founding dates of Teradata and Vertica; I did not look them up.
- Vertica's write-store removal comes from a forum post quoting release notes.
- HyPer's move to MVCC: seen only in a review of the 2015 paper.
- Snowflake's micro-partition quote, read through a course page; pgvector's behaviour, read on a mirror.
- HNSW recall drift after deletes rests on secondary sources, with no measurement.
- Low use of Snowflake hybrid tables is one practitioner's view; ClickHouse's 23x is a vendor claim.
