# The database inside the application process

An embedded database is a library linked into the program, not a separate server. Queries are function calls in the same process, with no network and no wire protocol.

## What it is

- A library inside the application process ([00](../../research/00-landscape-overview.md)). Berkeley DB: "No inter-process communication ... is required" ([03](../../research/03-key-value-document-distributed.md), https://web.stanford.edu/class/cs276a/projects/docs/berkeleydb/ref/intro/dbis.html).
- Forms in the research:
  - **Embedded SQL.** SQLite, a library inside the application with no server, first released 2000-08-17 ([08](../../research/08-correctness-first-databases.md), https://www.sqlite.org/chronology.html). DuckDB is "a library inside one process, not a server" ([02](../../research/02-analytical-and-specialised.md)).
  - **Embedded key-value.** Berkeley DB, with hash or B-tree files, a write-ahead log and locks ([03](../../research/03-key-value-document-distributed.md)). LevelDB: "only a single process ... can access a particular database at a time" (https://github.com/google/leveldb/blob/main/README.md).
  - **Storage in the same thread as app code.** Cloudflare Durable Objects run SQLite "in the very same thread" as app code ([00](../../research/00-landscape-overview.md); [07](../../research/07-code-inside-the-database.md), https://blog.cloudflare.com/sqlite-in-durable-objects/).
  - **All data in the program's memory.** Prevayler keeps all business objects in RAM, writes each change as a serializable command to a journal, and rebuilds from a snapshot plus the journal ([07](../../research/07-code-inside-the-database.md), https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html).
  - **Tables owned by a language process.** Erlang's ETS is an in-memory table owned by the process that created it; Mnesia is a replicated database built on it and queried from Erlang ([07](../../research/07-code-inside-the-database.md), https://www.erlang.org/doc/apps/stdlib/ets.html).

## The problem it solves

- **Zero operational overhead** ([00](../../research/00-landscape-overview.md)): no server to run.
- **No server latency** ([03](../../research/03-key-value-document-distributed.md)). The vendor says a Durable Objects query takes microseconds (vendor claim, [07](../../research/07-code-inside-the-database.md)).
- **No mismatch between program and data.** In Prevayler queries are plain method calls ([07](../../research/07-code-inside-the-database.md)); Mnesia stores native Erlang terms ([07](../../research/07-code-inside-the-database.md)).
- SQLite, DuckDB and Durable Objects dropped the assumption that a database needs a server and a wire protocol ([00](../../research/00-landscape-overview.md)).

## What it costs

- **One writer, or one process.** SQLite allows a single writer at a time (https://sqlite.org/isolation.html). DuckDB: either "one process can both read and write", or many read and none write (https://duckdb.org/docs/2.0/connect/concurrency). One Durable Object's throughput is limited to one thread (https://blog.cloudflare.com/sqlite-in-durable-objects/). See [One writer at a time](one-writer-at-a-time.md).
- **No network access and no query language** for Berkeley DB ([03](../../research/03-key-value-document-distributed.md)).
- **All data in RAM** for Prevayler, with commands that must be deterministic ([07](../../research/07-code-inside-the-database.md)).
- **Data lives and dies with the process.** An ETS table "is automatically destroyed" when its owner terminates, unless an heir is named (https://www.erlang.org/doc/apps/stdlib/ets.html).
- **Sharing is hard.** An image "does not work well if you have to share data between different applications" ([07](../../research/07-code-inside-the-database.md), https://book.seaside.st/book/advanced/persistency/image-based-persistency).

## Systems that use it

- [SQLite](../systems/sqlite.md) ([00](../../research/00-landscape-overview.md); [08](../../research/08-correctness-first-databases.md)).
- [DuckDB](../systems/duckdb.md) ([02](../../research/02-analytical-and-specialised.md)).
- [Berkeley DB](../systems/berkeley-db.md) ([03](../../research/03-key-value-document-distributed.md)).
- [RocksDB and LevelDB](../systems/rocksdb.md) ([03](../../research/03-key-value-document-distributed.md)).
- [Cloudflare Durable Objects](../systems/cloudflare-durable-objects.md) ([00](../../research/00-landscape-overview.md); [07](../../research/07-code-inside-the-database.md)).
- [Prevayler](../systems/prevayler.md) ([07](../../research/07-code-inside-the-database.md)).
- [Erlang ETS and Mnesia](../systems/mnesia.md) ([07](../../research/07-code-inside-the-database.md)).
- Turso, which has no page: a Rust rewrite of SQLite in the embedded family ([00](../../research/00-landscape-overview.md), https://turso.tech/blog/turso-0.5.0).

## Cannot be combined with

Many processes writing to one database: LevelDB allows one process at a time, and DuckDB allows one writing process ([02](../../research/02-analytical-and-specialised.md); [03](../../research/03-key-value-document-distributed.md)).

## Disagreements

- **DuckDB as an in-process library.** [00](../../research/00-landscape-overview.md) says it did not fetch DuckDB's own pages and cites the in-process design only through DuckLake. [02](../../research/02-analytical-and-specialised.md) states it directly and cites DuckDB's concurrency docs (one writing process).
- **Durable Objects query latency.** [00](../../research/00-landscape-overview.md) repeats Cloudflare's "near-zero latency" without a vendor mark. [07](../../research/07-code-inside-the-database.md) marks the same blog's microsecond query figure as a vendor claim.
- **Turso's concurrent writes.** [00](../../research/00-landscape-overview.md) says Turso's MVCC concurrent writes are in beta. [09](../../research/09-agents-and-databases-today.md) states that Turso supports concurrent writers via `BEGIN CONCURRENT`, with no beta caveat, and adds that schema changes are not allowed inside those transactions (https://docs.turso.tech/tursodb/concurrent-writes).

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- [08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- [09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://web.stanford.edu/class/cs276a/projects/docs/berkeleydb/ref/intro/dbis.html
- https://www.sqlite.org/chronology.html
- https://sqlite.org/isolation.html
- https://duckdb.org/docs/2.0/connect/concurrency
- https://github.com/google/leveldb/blob/main/README.md
- https://blog.cloudflare.com/sqlite-in-durable-objects/
- https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html
- https://www.erlang.org/doc/apps/stdlib/ets.html
- https://book.seaside.st/book/advanced/persistency/image-based-persistency
- https://turso.tech/blog/turso-0.5.0
- https://docs.turso.tech/tursodb/concurrent-writes
