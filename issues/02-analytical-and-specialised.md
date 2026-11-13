# Analytical and specialised stores

Type: research
Status: resolved

## Question

Using the map's research template, what do analytical and specialised stores do well and badly, and what pays for each strength?

Cover column stores and warehouses (Teradata, Vertica, ClickHouse, DuckDB, Snowflake), lakehouse formats (Parquet, Iceberg, DuckLake), and the specialised index families: time series, full-text search, vector and spatial.

Go deepest on why analytical systems split from transactional ones, and what attempts to rejoin them have cost.

## Answer

Findings: [research/02-analytical-and-specialised.md](../research/02-analytical-and-specialised.md)

- Analytical systems split from transactional ones for two reasons: storage layout (columns read fast, rows write fast) and workload interference (big queries slowing small ones).
- Every attempt to rejoin them (HyPer, SAP HANA, Oracle In-Memory, TiDB/TiFlash, SingleStore, Snowflake hybrid tables) keeps two layouts and pays with a second copy that lags, or with merging a write layer and a read layer on every read.
- HTAP as a product did not catch on, partly for organisational reasons; the rejoin now happens outside the database, by streaming the transaction log into open-format copies (Databricks bought Mooncake for this in 2025-10).
- Almost every analytical and specialised store writes immutable pieces and merges later, so writes are visible before they settle: duplicates until a merge, text searchable only after a refresh, vector results silently short under filters.
- Most borrowable for agents: derived indexes fed from one log, and freshness reported to the reader ("does this read include my write?").
