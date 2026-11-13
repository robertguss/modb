# ClickHouse

ClickHouse is a column-oriented analytical database. It writes data as immutable parts and merges them in the background, which makes inserts and scans fast and single-row changes slow. It belongs to the [analytical and lakehouse family](../families/analytical-and-lakehouse.md).

## What it is for

- Scans and aggregates over billions of rows. It is one of the current generation of column stores, with DuckDB and Snowflake ([research 02](../../research/02-analytical-and-specialised.md)). See [storing data by column](../ideas/column-storage.md).

## Core idea

- **[Write-once pieces merged in the background](../ideas/immutable-pieces-with-background-merge.md).** ClickHouse "doesn't modify existing parts, it simply writes more", then merges them ([ClickHouse blog](https://clickhouse.com/blog/updates-in-clickhouse-2-sql-style-updates)).
- **No multi-row transactions** ([research 02](../../research/02-analytical-and-specialised.md)).

## Strengths and what pays for each

- **Very fast inserts and scans, high compression.** *Paid for by* slow single-row changes. A **mutation** (ClickHouse's word for an update or delete of existing rows) is "I/O-heavy, rewriting all parts that match" ([update overview](https://clickhouse.com/docs/concepts/features/operations/update/overview)).
- **Cheaper small updates through patch parts (2025).** A patch part is a small piece holding only the changed rows and columns, applied on read and folded in at the next merge. ClickHouse says they are "up to 23x faster than mutations" (vendor claim) ([update overview](https://clickhouse.com/docs/concepts/features/operations/update/overview)). *Paid for by* reads applying patches until a merge ([research 02](../../research/02-analytical-and-specialised.md)).

## Weaknesses

- **Deduplication settles at an unknown time.** ReplacingMergeTree removes duplicates "only during a merge", at "an unknown time"; a plain `SELECT` can return stale rows unless it adds `FINAL` ([ReplacingMergeTree](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/replacingmergetree)).

## Overlapping work

- ClickHouse avoids multi-row transactions. Its answer to concurrent updates is patch parts rather than locks ([research 02](../../research/02-analytical-and-specialised.md)).

## What an agent struggles with

From research 02's notes on column stores:

- **Writes visible but not settled.** A query may show rows that a later merge removes or replaces.
- **Cost that grows with bytes scanned**, unseen in advance.

## Worth borrowing

From research 02:

- **Immutable pieces plus background merge.** Simple crash safety and lock-free reads. Cost: merge work, and a window where data is visible but unsettled, which the database must report.
- **Patch parts instead of rewrites.** A small change records only what changed. Cost: reads apply patches until a merge.

## Sources

- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- Primary links are given inline above.
