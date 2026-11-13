# One writer at a time

All writes go through one writer, one thread, one process or one owner, in order. With nothing running alongside, writes cannot interfere, so they need no locks, at the price of one writer's throughput.

## What it is

The research finds the same rule at several scales:

- **One writer per database file.** SQLite allows a single writer at a time ([00](../../research/00-landscape-overview.md), https://sqlite.org/isolation.html). In WAL mode readers run alongside the single writer (https://sqlite.org/wal.html).
- **One writing process.** DuckDB: either "one process can both read and write", or many read and none write ([02](../../research/02-analytical-and-specialised.md), https://duckdb.org/docs/2.0/connect/concurrency). LevelDB: "only a single process ... can access a particular database at a time" ([03](../../research/03-key-value-document-distributed.md), https://github.com/google/leveldb/blob/main/README.md).
- **One command thread.** Redis runs client commands one at a time on a main thread ([00](../../research/00-landscape-overview.md); [03](../../research/03-key-value-document-distributed.md)). TigerBeetle "is single-threaded"; batched requests run one after another on the one thread, with no locks ([00](../../research/00-landscape-overview.md); [08](../../research/08-correctness-first-databases.md), https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md).
- **One transactor or log.** Datomic's *transactor* applies every write in order, so writes are "fully serialized" ([04](../../research/04-models-that-lost-or-stayed-niche.md); [05](../../research/05-databases-that-keep-history.md), https://docs.datomic.com/transactions/acid.html). XTDB writes are "serialized via a totally-ordered log" and applied one at a time ([05](../../research/05-databases-that-keep-history.md), https://docs.xtdb.com/about/txs-in-xtdb.html).
- **One owner per key or entity.** For Kafka, a vendor post suggests one owner per entity, since Kafka has no conditional writes ([05](../../research/05-databases-that-keep-history.md), vendor, https://docs.eventsourcingdb.io/blog/2026/07/20/kafka-is-not-an-event-store/). Akka Persistence rests on "the single-writer principle", because two live instances would interleave events ([07](../../research/07-code-inside-the-database.md), https://doc.akka.io/libraries/akka-core/current/typed/persistence.html). Each Cloudflare Durable Object runs "in one single thread" ([07](../../research/07-code-inside-the-database.md)).
- **One transaction at a time in memory.** Prevayler's `execute()` guarantees "only one Transaction is executed at a time" ([07](../../research/07-code-inside-the-database.md), https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html).
- **One node per core.** FoundationDB avoids multithreaded concurrency: "one database node is deployed per core" ([08](../../research/08-correctness-first-databases.md), https://www.foundationdb.org/files/fdb-paper.pdf).
- **A single point of order for metadata.** DuckLake commits are "a single SQL transaction in the catalog database"; the catalog is the single point of order, which suits one operation at a time ([02](../../research/02-analytical-and-specialised.md), https://ducklake.select/manifesto/).

## The problem it solves

- **Serializability without locks.** SQLite is serializable through a single writer ([01](../../research/01-relational-and-transactional.md)). Each Redis command is atomic for free ([03](../../research/03-key-value-document-distributed.md)). Prevayler has no concurrency bugs inside the model ([07](../../research/07-code-inside-the-database.md)).
- **Hot spots that contend anyway.** In TigerBeetle, transfers concentrate on a few hot accounts, so they contend whatever you do (https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md). The designers argue a single core "can easily scale to 1mil TPS" ([00](../../research/00-landscape-overview.md)).
- **Deterministic testing.** FoundationDB and TigerBeetle avoid threads entirely so a simulator can own the schedule ([08](../../research/08-correctness-first-databases.md)). See [Deterministic simulation and fault-injection testing](deterministic-simulation-testing.md).
- **Lock-free reads of a frozen value** while writes continue (Datomic, [05](../../research/05-databases-that-keep-history.md)).
- Datomic's single writer plus compare-and-swap is close to the project map's settled one-operation-at-a-time rule ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

## What it costs

- **Throughput bounded by one writer.** Datomic: one writer, capped by one machine ([05](../../research/05-databases-that-keep-history.md)). One Durable Object's throughput is limited to one thread ([00](../../research/00-landscape-overview.md)). One object is the throughput ceiling, and no transaction spans two objects ([07](../../research/07-code-inside-the-database.md)).
- **Writers wait.** SQLite returns busy errors when several write at once ([08](../../research/08-correctness-first-databases.md)).
- **Long transactions block everyone.** Prevayler transactions must be short "because they block the system", and long ones are "an open question" (https://cl-prevalence.common-lisp.dev/). Prevayler snapshots block writes while they run ([07](../../research/07-code-inside-the-database.md)).
- **No interactive writes in XTDB**, and the partition key must be chosen up front for actors ([05](../../research/05-databases-that-keep-history.md); [07](../../research/07-code-inside-the-database.md)).
- **Async work breaks the guarantee.** In Durable Objects, "awaiting async operations like `fetch()` … opens the input gate, allowing other requests to interleave" ([07](../../research/07-code-inside-the-database.md), https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/).
- **Durability or memory.** Redis pays for speed with durability ([03](../../research/03-key-value-document-distributed.md)); Prevayler needs all data in RAM ([07](../../research/07-code-inside-the-database.md)).

## Systems that use it

- [SQLite](../systems/sqlite.md) ([00](../../research/00-landscape-overview.md); [01](../../research/01-relational-and-transactional.md); [08](../../research/08-correctness-first-databases.md))
- [DuckDB](../systems/duckdb.md) ([02](../../research/02-analytical-and-specialised.md))
- [Redis](../systems/redis.md) ([00](../../research/00-landscape-overview.md); [03](../../research/03-key-value-document-distributed.md))
- [RocksDB and LevelDB](../systems/rocksdb.md): LevelDB allows one process ([03](../../research/03-key-value-document-distributed.md))
- [Datomic](../systems/datomic.md) ([04](../../research/04-models-that-lost-or-stayed-niche.md); [05](../../research/05-databases-that-keep-history.md))
- [XTDB](../systems/xtdb.md) ([05](../../research/05-databases-that-keep-history.md))
- [Apache Kafka](../systems/kafka.md): one owner per key suggested ([05](../../research/05-databases-that-keep-history.md))
- [Prevayler](../systems/prevayler.md) ([07](../../research/07-code-inside-the-database.md))
- [Cloudflare Durable Objects](../systems/cloudflare-durable-objects.md) ([00](../../research/00-landscape-overview.md); [07](../../research/07-code-inside-the-database.md))
- [TigerBeetle](../systems/tigerbeetle.md) ([00](../../research/00-landscape-overview.md); [08](../../research/08-correctness-first-databases.md))

## Disagreements

- **How much Redis runs on its one thread.** [03](../../research/03-key-value-document-distributed.md) says one core does all command work. [00](../../research/00-landscape-overview.md) agrees client commands run on the main thread, but says I/O threads handle reading, writing and TLS, and the Redis Query Engine runs queries on a pool of worker threads.
- **Whether SQLite's one-writer limit is being lifted.** `BEGIN CONCURRENT` lives on an unmerged SQLite branch ([00](../../research/00-landscape-overview.md), https://sqlite.org/src/doc/begin-concurrent/doc/begin_concurrent.md). [00](../../research/00-landscape-overview.md) says Turso's rewrite lifts the limit in beta; [09](../../research/09-agents-and-databases-today.md) states that Turso supports concurrent writers via `BEGIN CONCURRENT`, with no beta caveat (https://docs.turso.tech/tursodb/concurrent-writes).
- **DuckDB's single writing process.** [02](../../research/02-analytical-and-specialised.md) cites DuckDB's concurrency docs directly; [00](../../research/00-landscape-overview.md) did not fetch DuckDB's own pages.

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- [08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- [09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://sqlite.org/isolation.html
- https://sqlite.org/wal.html
- https://sqlite.org/src/doc/begin-concurrent/doc/begin_concurrent.md
- https://duckdb.org/docs/2.0/connect/concurrency
- https://github.com/google/leveldb/blob/main/README.md
- https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md
- https://docs.datomic.com/transactions/acid.html
- https://docs.xtdb.com/about/txs-in-xtdb.html
- https://docs.eventsourcingdb.io/blog/2026/07/20/kafka-is-not-an-event-store/
- https://doc.akka.io/libraries/akka-core/current/typed/persistence.html
- https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html
- https://cl-prevalence.common-lisp.dev/
- https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/
- https://www.foundationdb.org/files/fdb-paper.pdf
- https://ducklake.select/manifesto/
- https://docs.turso.tech/tursodb/concurrent-writes
