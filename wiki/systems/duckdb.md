# DuckDB

DuckDB is an analytical SQL database that runs as a library inside one process, not as a server. It is a column store for fast local analytics. It belongs to the [analytical and lakehouse family](../families/analytical-and-lakehouse.md).

## What it is for

- Fast local analytics with no server to run ([research 02](../../research/02-analytical-and-specialised.md)).
- Research 00 lists it both as an analytical column store, beside Vertica ([C-Store, VLDB 2005](https://www.vldb.org/conf/2005/papers/p553-stonebraker.pdf)), and as an embedded database, beside SQLite and Turso.
- Others build on it unchanged: [Chronos](chronos.md) adds branches over DuckDB by rewriting queries ([arXiv 2609.14889](https://arxiv.org/abs/2609.14889)).

## Core idea

- **A library inside one process, not a server** ([research 02](../../research/02-analytical-and-specialised.md)). See [database inside the application process](../ideas/database-inside-the-application-process.md).
- **[Storing data by column](../ideas/column-storage.md)** ([research 00](../../research/00-landscape-overview.md)).
- **[Optimistic concurrency](../ideas/optimistic-concurrency.md) inside the process.** No locks; conflicts are found at commit. "Appends will never conflict"; for two edits to one row, "the second thread … will fail with a conflict error" ([concurrency](https://duckdb.org/docs/2.0/connect/concurrency)).
- **One writing process.** Either "one process can both read and write", or many processes read and none write (same page).

## Strengths and what pays for each

- **No server.** *Paid for by* one writing process ([concurrency](https://duckdb.org/docs/2.0/connect/concurrency)).
- **Appends never conflict.** *Paid for by* aborts when two threads edit the same row (same page).
- **Graph queries in SQL.** A 2024 survey cites relational systems beating graph databases, DuckDB's SQL/PGQ "by up to 10×" ([What Goes Around, 2024](https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf)). Research 04 says it did not read the cited study.

## Weaknesses

- **Same-row conflicts abort** ([concurrency](https://duckdb.org/docs/2.0/connect/concurrency)).
- **Only one process can write** (same page).

## Overlapping work

- Inside a process, threads run optimistically and the second writer of a row fails. Across processes, only one may write ([concurrency](https://duckdb.org/docs/2.0/connect/concurrency)).

## What an agent struggles with

- **Conflict errors that need a retry.** Research 02 records the conflict error but no agent-specific finding; that an agent must catch and retry it is inference.
- **Several agents in separate processes cannot all write** to one database file (inference from the one-writing-process rule, [research 02](../../research/02-analytical-and-specialised.md)).

## Worth borrowing

- **Dropping the server and the wire protocol.** SQLite, DuckDB and Cloudflare Durable Objects all did this ([research 00](../../research/00-landscape-overview.md)). Cost: one writing process.

## Disagreements

- **How the in-process design is sourced.** Research 00 says it did not fetch DuckDB's own pages and cites the in-process design only through DuckLake. Research 02 states it directly and cites DuckDB's concurrency docs (one writing process).
- **Graph databases against relational systems.** Research 00 presents Neo4j's index-free adjacency (from a vendor page) as what solves many-hop queries. Research 04 cites the 2024 survey that relational systems, DuckDB's SQL/PGQ among them, beat graph databases "by up to 10×", but did not read the cited study.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- Primary links are given inline above.
