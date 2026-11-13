# Write-once pieces merged in the background

Data is written as pieces that are never edited (parts, segments, files). A change adds a new piece, and background work later merges pieces together and drops what is obsolete.

## What it is

- **Log-structured merge (LSM) trees.** Writes go to an in-memory table (memtable) and a log, are flushed to sorted files, then compacted ([RocksDB wiki](https://github.com/meta/rocksdb/wiki/RocksDB-Overview)). **Compaction** is the background merge.
- **Columnar parts.** ClickHouse "doesn't modify existing parts, it simply writes more", then merges them ([ClickHouse blog](https://clickhouse.com/blog/updates-in-clickhouse-2-sql-style-updates)). In Snowflake, changed rows mean "all of the impacted micro-partitions are re-created" ([Snowflake](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions)).
- **Search segments.** Lucene stores its index as immutable segments that are merged over time ([Elastic docs](https://www.elastic.co/docs/manage-data/data-store/near-real-time-search)).
- **Table files.** An Iceberg table is many files tracked by metadata; each change writes several new files ([Iceberg spec](https://iceberg.apache.org/spec/); [research 02](../../research/02-analytical-and-specialised.md)).
- **Time-series blocks.** Prometheus cuts two-hour blocks and compacts them later ([Prometheus storage](https://prometheus.io/docs/prometheus/latest/storage/)).

## The problem it solves

- **Write-heavy workloads on flash** ([research 00](../../research/00-landscape-overview.md)). Cheap sequential writes ([research 03](../../research/03-key-value-document-distributed.md)).
- **Cheap bulk loads**, fast scans and high compression ([research 02](../../research/02-analytical-and-specialised.md)).
- **Simple crash safety and lock-free reads**, since nothing a reader holds is ever changed (research 02's suggestion to borrow).
- **Time travel**, by keeping old pieces until cleanup ([research 02](../../research/02-analytical-and-specialised.md)).

## What it costs

- **Merge work.** RocksDB names the costs as write, read and space amplification, and compaction styles trade one against another. At write amplification 50 and 500 MB/s of disk, the database sustains only 10 MB/s ([tuning guide](https://github.com/meta/rocksdb/wiki/RocksDB-Tuning-Guide)). Many small Vertica loads create "additional work for the Tuple Mover" ([Vertica KB](https://www.vertica.com/kb/Data-Loading-in-Vertica-Using-COPY/Content/BestPractices/Data-Loading-in-Vertica-Using-COPY.htm)).
- **Stalls when merging falls behind.** RocksDB stalls writes, or reads slow because too many files must be checked ([tuning guide](https://github.com/meta/rocksdb/wiki/RocksDB-Tuning-Guide)). Latency depends on background work the caller cannot see (inference, [research 03](../../research/03-key-value-document-distributed.md)).
- **Slow small changes.** A ClickHouse mutation rewrites "all parts that match" ([ClickHouse](https://clickhouse.com/docs/concepts/features/operations/update/overview)). Iceberg writes several files per change ([research 02](../../research/02-analytical-and-specialised.md)).
- **A window where data is visible but not settled**, which the database must report ([research 02](../../research/02-analytical-and-specialised.md)):
  - ClickHouse's ReplacingMergeTree removes duplicates "only during a merge", at "an unknown time"; a plain `SELECT` can return stale rows unless it adds `FINAL` ([ReplacingMergeTree](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/replacingmergetree)).
  - In Elasticsearch a write is not searchable until a refresh ([near-real-time search](https://www.elastic.co/docs/manage-data/data-store/near-real-time-search)).
- **Cleanup someone must own.** Old files stay until compaction and snapshot expiry run ([research 02](../../research/02-analytical-and-specialised.md)).
- **A cheaper variant.** ClickHouse's patch parts hold only changed rows and columns, applied on read and folded in at the next merge, "up to 23x faster than mutations" (vendor claim). Cost: reads apply patches until a merge ([research 02](../../research/02-analytical-and-specialised.md)).

## Systems that use it

- [RocksDB](../systems/rocksdb.md): LSM tree with background compaction.
- [ClickHouse](../systems/clickhouse.md): immutable columnar parts and merges.
- [Snowflake](../systems/snowflake.md): re-created micro-partitions.
- [Apache Iceberg](../systems/iceberg.md): new files and metadata per commit.
- [Elasticsearch (Lucene)](../systems/elasticsearch.md): immutable segments, refresh and merge.

## Cannot be combined with

- **Reads that are settled the moment a write returns**, without extra work on the read path. Each system above leaves a window of unsettled or invisible data, closed only by a merge, a refresh, `FINAL`, or applying patches on read ([research 02](../../research/02-analytical-and-specialised.md)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- Primary links are given inline above.
