# Landscape overview: the families of databases and the 2024 to 2026 wave

Research run on 2026-11-13 by a subagent using Exa. A first pass that seeds the family tickets. Nothing here has been checked a second time; section 4 is the researcher's inference.

Exa was available and I used it for all web access. Dates are given where the page showed one; "n.d." means it did not. I did not fetch the DuckDB home page in this session, so DuckDB's in-process design is cited only through DuckLake.

## 1. The families that exist today

| Family | Core idea (data model + storage/consistency) | Problem it solved | Representatives |
|---|---|---|---|
| Relational row store | Tables and SQL. Multiversion concurrency control (MVCC): each statement sees a snapshot, which reduces lock contention ([PG docs](https://www.postgresql.org/docs/current/mvcc-intro.html)) | General transactional work with many concurrent users | PostgreSQL |
| Analytical column store | Data stored by column, compressed, read-optimized ([C-Store, VLDB 2005](https://www.vldb.org/conf/2005/papers/p553-stonebraker.pdf)) | Scans over billions of rows | Vertica, DuckDB |
| Key-value / LSM | Writes go to an in-memory memtable and a log, are flushed to sorted files, then compacted ([RocksDB wiki](https://github.com/meta/rocksdb/wiki/RocksDB-Overview)) | Write-heavy workloads on flash | RocksDB |
| Document | "Data accessed together is stored together", in nested JSON-like documents ([MongoDB](https://www.mongodb.com/docs/manual/data-modeling/)) | Joins and the mismatch between objects and tables | MongoDB |
| Graph | Native graph storage where each node points to its neighbours ("index-free adjacency") ([Neo4j](https://neo4j.com/blog/graph-database/16-things-to-consider-when-selecting-the-right-graph-database/), vendor page) | Queries that traverse many relationships | Neo4j |
| Time series | Tables partitioned automatically by time ("hypertables") | Append-mostly metric data | TimescaleDB, now TigerData ([Pavlo](https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html)) |
| Vector | Approximate nearest-neighbour indexes such as HNSW ([TigerData](https://www.tigerdata.com/blog/vector-database-basics-hnsw)) | Similarity search over embeddings | pgvector, turbopuffer |
| Immutable fact / bitemporal | The database accumulates facts (datoms) and never updates in place ([Datomic](https://docs.datomic.com/transactions/model.html)). XTDB makes every table track both system time and valid time ([XTDB v2 GA, 2025-06-12](https://www.xtdb.com/blog/launching-xtdb-v2)) | Audit, history, "as of" queries | Datomic, XTDB |
| Ledger / simulation-tested | TigerBeetle: a fixed schema of accounts and debit/credit transfers, single-threaded ([ARCHITECTURE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md)). FoundationDB: an ordered key-value core with transactions; data models are stateless "layers" on top, and the core "provides no indexing and never will" ([layer concept](https://apple.github.io/foundationdb/layer-concept.html); [Record Layer](https://www.foundationdb.org/blog/announcing-record-layer/)) | Correctness under faults; financial throughput | TigerBeetle, FoundationDB |
| Stream / incremental view | Views are updated incrementally as changes arrive, including multi-way joins ([Materialize](https://materialize.com/blog/differential-from-scratch/); [Timely, CACM](https://cacm.acm.org/research/incremental-iterative-data-processing-with-timely-dataflow/)) | Results that are always fresh without re-running queries | Materialize |
| Versioned, branch and merge | Prolly trees: content-addressed B-trees that give cheap diffs and shared structure between versions ([Dolt](https://www.dolthub.com/docs/architecture/storage-engine/)). lakeFS creates a branch as a metadata-only operation ([lakeFS](https://docs.lakefs.io/quickstart/branch/)) | Reproducibility, review, safe experiments | Dolt, lakeFS |
| Local-first / sync | CRDTs merge concurrent changes without a server ([Automerge](https://automerge.org/)). Electric syncs "Shapes" out of Postgres ([docs](https://electric.ax/docs/sync/)). PowerSync syncs to a local SQLite, with writes queued for upload ([docs](https://docs.powersync.com/intro/setup-guide)). Zero syncs the subset of rows the app's queries need ([docs](https://zero.rocicorp.dev/docs/when-to-use)) | Offline use, instant UI, collaboration | Automerge, Electric, PowerSync, Zero |
| Embedded | A library inside the application process. SQLite allows a single writer at a time ([isolation](https://sqlite.org/isolation.html)) | Zero operational overhead | SQLite, DuckDB, Turso |
| Database as app server | Convex: queries and mutations are deterministic TypeScript functions running in the database, with optimistic concurrency and reactive subscriptions ([How Convex works](https://stack.convex.dev/how-convex-works)). SpacetimeDB: "modules" compiled to Wasm or run on V8, executing inside the database and syncing state to clients ([docs](https://spacetimedb.com/docs/databases/)) | Removing the app tier, ORMs and cache invalidation | Convex, SpacetimeDB |

## 2. The recent wave, 2024 to 2026

**Documented events:**
- **PostgreSQL consolidation.** Databricks bought Neon (about $1B) and Snowflake bought Crunchy Data ($250M). Three distributed-Postgres projects are competing: Multigres, Neki and PgDog ([Pavlo, Jan 2026](https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html)).
- **New file formats to replace Parquet.** Five appeared in 2025, including Vortex (donated to the Linux Foundation), Lance and Nimble (Pavlo, same post). DuckLake moves lakehouse metadata into a SQL database ([2025-05-27](https://ducklake.select/2025/05/27/ducklake-01/)) and reached 1.0 ([MotherDuck](https://motherduck.com/blog/announcing-ducklake-1-0-on-motherduck/), n.d.).
- **Object storage as the only durable store.** turbopuffer is "not tiering": object storage is the source of truth ([blog](https://turbopuffer.com/blog/turbopuffer)).
- **Embedded.** Turso's Rust rewrite of SQLite has concurrent writes via MVCC, now in beta ([v0.5](https://turso.tech/blog/turso-0.5.0), n.d.).
- **Sync and in-database code.** Zero 1.0 shipped ([InfoQ, 2026-06](https://www.infoq.com/news/2026/06/zero-version-1/)). SpacetimeDB 2.0 added TypeScript modules and HTTP "procedures" ([release, 2026-02-20](https://github.com/clockworklabs/SpacetimeDB/releases/tag/v2.0.1)).

**What is driving it:** AI agents as database users and the cost of object storage.
- **Agents.** Neon reports that over 80% of its databases are created by AI agents ([Neon](https://neon.com/blog/neon-and-databricks)). This is the company's own telemetry, so treat it as a vendor claim. Pavlo names branching as the feature that matters to agents, and says MCP database servers are mostly thin proxies with no real guardrails.
- **Agent-memory products.** SurrealDB "Agent Memory" and Contextbase both launched in 2026. I found only their launch announcements, no technical depth, so treat them as marketing.
- **Funding.** Pavlo saw fewer early-stage database rounds in 2025: "the buzz around vector databases has muted".

**Vendor claims I could not confirm:**
- SpacetimeDB 2.0: 170k transactions per second.
- turbopuffer: 10x lower cost.
- TigerBeetle: the simulator runs "24/7 on 1024 cores" ([safety](https://docs.tigerbeetle.com/concepts/safety/)).

## 3. Genuine first-principles rethinks

| System | Assumption dropped | What they got |
|---|---|---|
| Datomic, XTDB | Rows can be changed in place | Free history, queries as of any time, audit |
| FoundationDB | The core needs a data model | One verified transactional core; many models built as layers |
| TigerBeetle | Multi-threading and a general schema | One core with no locks and a fixed domain. The designers argue a single core "can easily scale to 1mil TPS" ([ARCHITECTURE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md)) |
| SQLite, DuckDB, Cloudflare Durable Objects | A server and a wire protocol | Durable Objects run SQLite "in the very same thread" as app code, at near-zero latency. The price: one object's throughput is limited to one thread ([Cloudflare, 2024-09-26](https://blog.cloudflare.com/sqlite-in-durable-objects/)) |
| Convex, SpacetimeDB | A separate application server | Transactions plus reactivity for free. Convex requires functions to be deterministic |
| Materialize | Queries are computed when they are read | Results maintained continuously |
| Dolt, lakeFS, Neon | History is linear | Branch, diff and merge for data |
| Zero, Electric, Automerge | Clients fetch data by request and response | Local reads and offline use. Automerge also drops the authoritative server |
| turbopuffer, DuckLake | Local disks are where data lives / file-based metadata | Cheap storage, any node can serve any data |

## 4. Open ground (my inference, not sourced)

1. **Why a write happened is not stored.** Bitemporal stores record *when* a fact changed and who wrote it, but not *why*: the intent, the triggering request, or the agent's reasoning. Provenance is left to logs outside the database.
2. **Invariants stop at the row.** Constraints are CHECK, foreign keys and uniqueness. Only TigerBeetle enforces rich domain invariants, and only by hard-coding a single domain. No general system lets users declare invariants that must hold across transactions and have the database prove or enforce them.
3. **In-database code is opaque to the database.** Convex and SpacetimeDB run general-purpose languages, with determinism enforced by a sandbox. The database cannot analyse that code (read and write sets, effects) to plan, verify or migrate it.
4. **Simulation testing protects the vendor, not the user.** FoundationDB's [client-testing](https://apple.github.io/foundationdb/client-testing.html) is a partial exception. I found no system that offers deterministic replay of *the user's* workload with injected faults as a product feature.
5. **Merging branches is structural, not semantic.** Dolt merges cells. Nobody merges by intent, for example "both branches added stock".
6. **Agents get human-shaped access.** Access control is still accounts and roles. Capability-scoped, budgeted access for agents is bolted on through proxies (Pavlo).

## Corrections to what you believed

- **Redis: mostly right, with exceptions.** Client commands still run on the main thread ([Redis PR #13665](https://github.com/redis/redis/pull/13665); [8.0-M03](https://redis.io/blog/redis-8-0-m03-is-out-even-more-performance-new-features/)). Two exceptions:
  - I/O threads handle reading, writing and TLS.
  - The Redis Query Engine uses a pool of worker threads for queries ([InfoQ](https://www.infoq.com/news/2024/07/redis-vector-database-genai-rag/); [8.4](https://redis.io/blog/redis-8-4-open-source-ga/)).
- **TigerBeetle: understated.** It is not only the state machine that runs on one thread; ARCHITECTURE.md says "TigerBeetle is single-threaded".
- **SQLite: right for mainline SQLite.** In WAL mode readers run alongside the single writer ([wal.html](https://sqlite.org/wal.html)). `BEGIN CONCURRENT` lives on an unmerged branch ([doc](https://sqlite.org/src/doc/begin-concurrent/doc/begin_concurrent.md)). Turso's rewrite lifts the limit in beta.
- **Deterministic simulation: confirmed for both.**
  - FoundationDB simulates a whole cluster in one single-threaded process, reproducible from the seed ([testing](https://apple.github.io/foundationdb/testing.html)).
  - TigerBeetle's simulator (the VOPR) injects network and disk faults and can reproduce any run from the seed and commit ([vopr.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md)).
  - Jepsen also tested TigerBeetle independently ([report](https://jepsen.io/analyses/tigerbeetle-0.16.11.pdf)).

I did not read Automerge's or Materialize's papers in full, or verify the Durable Objects GA date. Section 4 is reasoning, not a literature search: someone may have dropped one of those assumptions in a system I did not find.