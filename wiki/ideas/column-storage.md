# Storing data by column

A **column store** keeps each column's values together on disk; a **row store** keeps each row's fields together. Analytical databases store by column so a query reads only the columns it needs.

## What it is

- A row store keeps each row's fields together; a column store keeps each column's values together ([research 02](../../research/02-analytical-and-specialised.md)).
- Data is stored by column, compressed and read-optimised ([C-Store, VLDB 2005](https://www.vldb.org/conf/2005/papers/p553-stonebraker.pdf)).
- In files: Parquet is a file of **row groups**, each holding one chunk per column, with metadata written "after the data to allow for single pass writing" ([Parquet](https://parquet.apache.org/docs/file-format/)).

## The problem it solves

- **Scans over billions of rows** ([research 00](../../research/00-landscape-overview.md)).
- A column store "is drastically more efficient" for warehouses because a query reads only the columns it needs; OLTP engines are "write-optimized" while warehouses must be "read optimized" ([Stonebraker and Çetintemel, 2005](https://cs.brown.edu/research/db/publications/fits_all.pdf)).
- **High compression** and fast scans ([research 02](../../research/02-analytical-and-specialised.md)).

## What it costs

- **Slow single-row changes.** A ClickHouse mutation is "I/O-heavy, rewriting all parts that match" ([ClickHouse](https://clickhouse.com/docs/concepts/features/operations/update/overview)). In Snowflake, when rows change "all of the impacted micro-partitions are re-created" ([Snowflake](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions)).
- **Merge work.** Columnar pieces are written once, and background work combines them ([research 02](../../research/02-analytical-and-specialised.md)). In Vertica, many small loads create many storage containers and "additional work for the Tuple Mover" ([Vertica KB](https://www.vertica.com/kb/Data-Loading-in-Vertica-Using-COPY/Content/BestPractices/Data-Loading-in-Vertica-Using-COPY.htm)). See [write-once pieces merged in the background](immutable-pieces-with-background-merge.md).
- **A second layout for transactional work.** Every attempt to serve transactions and analytics together keeps a row layout and a column layout and pays to keep them in step ([research 02](../../research/02-analytical-and-specialised.md)). See [transactions and analytics in one system](transactions-and-analytics-together.md).
- **Costly changes to cooled data.** TimescaleDB converts cooling time chunks to a compressed columnstore; an update without a usable filter "may convert large amounts of data to the rowstore and back" ([Timescale docs](https://github.com/timescale/docs/blob/latest/use-timescale/compression/modify-compressed-data.md)).
- One counterpoint: SingleStore's builders found "the columnstore alone could handle a surprising number of OLTP-style queries" ([Neon blog](https://neon.com/blog/htap-is-dead)).

## Systems that use it

- [ClickHouse](../systems/clickhouse.md): immutable columnar parts, merged in the background.
- [DuckDB](../systems/duckdb.md): a column store as a library in one process.
- [Snowflake](../systems/snowflake.md): immutable columnar micro-partitions.

## Cannot be combined with

- **Cheap single-row updates in the same layout.** The sources show every system paying for this with rewrites, patches or a second row layout ([research 02](../../research/02-analytical-and-specialised.md)). That no design avoids the cost is research 02's inference.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- Primary links are given inline above.
