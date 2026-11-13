# DuckLake

DuckLake is a lakehouse format that keeps table data as Parquet files but puts all metadata in a SQL database. A commit is one SQL transaction in that catalog. It belongs to the [analytical and lakehouse family](../families/analytical-and-lakehouse.md).

## What it is for

- Lakehouse tables (warehouse tables as open files in object storage) with fast small commits ([DuckLake manifesto](https://ducklake.select/manifesto/)).
- It was announced on 2025-05-27 ([DuckLake 0.1](https://ducklake.select/2025/05/27/ducklake-01/)). Version 1.0 shipped on 2026-04-13 ([DuckLake 1.0](https://ducklake.select/2026/04/13/ducklake-10/)), and MotherDuck announced it on its platform ([MotherDuck](https://motherduck.com/blog/announcing-ducklake-1-0-on-motherduck/), undated).

## Core idea

- **Parquet data, metadata in a SQL database.** A commit is "a single SQL transaction in the catalog database", so DuckLake "supports as many table changes as the catalog database can commit". Small changes can be stored in the catalog itself ([manifesto](https://ducklake.select/manifesto/)).
- It drops the assumption that lakehouse metadata lives in files: research 00 lists it with turbopuffer as getting "cheap storage, any node can serve any data" ([research 00](../../research/00-landscape-overview.md)). See [object storage as the only durable store](../ideas/object-storage-as-source-of-truth.md).

## Strengths and what pays for each

- **Fast small commits.** *Paid for by* a SQL catalog database that every commit goes through ([research 02](../../research/02-analytical-and-specialised.md)).
- **One point of order.** The catalog orders every change, which suits one operation at a time. *Paid for by* throughput equal to the catalog's ([research 02](../../research/02-analytical-and-specialised.md)).

## Weaknesses

- **Throughput is capped by the catalog** ([research 02](../../research/02-analytical-and-specialised.md)).

## Overlapping work

- Concurrent writers are ordered by the catalog database's own transactions ([manifesto](https://ducklake.select/manifesto/)).

## What an agent struggles with

- Research 02 lists, for lakehouse formats in general, commit failures that need a retry policy and compaction and snapshot expiry that nobody owns. It gives no DuckLake-specific finding.

## Worth borrowing

- **Metadata in a transactional catalog, data in plain files.** The catalog is the single point of order, which suits one operation at a time. Cost: throughput equals the catalog's ([research 02](../../research/02-analytical-and-specialised.md)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- Primary links are given inline above.
