# Key-value, document and distributed stores

These stores gave up parts of the relational database (multi-item transactions, schemas, joins) to gain speed, scale or availability, and most later took some of it back. They range from libraries inside one program to stores spread across Regions.

## What they are for

- *Key-value stores* put and get values by a key, and do not look inside the value ([03](../../research/03-key-value-document-distributed.md)). The log-structured kind serves write-heavy workloads on flash ([00](../../research/00-landscape-overview.md), https://github.com/meta/rocksdb/wiki/RocksDB-Overview).
- *Document stores* keep data that is used together in one nested JSON-like document, to avoid joins and the mismatch between objects and tables ([00](../../research/00-landscape-overview.md), https://www.mongodb.com/docs/manual/data-modeling/).
- *Distributed stores* spread data over many machines and must choose what to do when the network splits ([03](../../research/03-key-value-document-distributed.md)). Some replicate to copies that are often offline and settle later ([06](../../research/06-divergent-copies-and-merging.md)).

## Members

- [Berkeley DB](../systems/berkeley-db.md): ACID key-value library inside the process.
- [Redis](../systems/redis.md): typed structures in memory, one command thread.
- [RocksDB and LevelDB](../systems/rocksdb.md): log-structured merge trees for cheap writes.
- [Dynamo and DynamoDB](../systems/dynamodb.md): never refuse a write; later, single-shot transactions.
- [Bigtable](../systems/bigtable.md): sorted map over many servers, single-row transactions.
- [Apache Cassandra](../systems/cassandra.md): leaderless, tunable consistency, last writer wins on clocks.
- [MongoDB](../systems/mongodb.md): documents, with joins, validation and transactions added later.
- [CouchDB](../systems/couchdb.md): replicate anywhere, conflicts kept as revision branches.

Mentioned in the research without a page:

- dbm and ndbm: Unix on-disk hash files that Berkeley DB was written to replace ([03](../../research/03-key-value-document-distributed.md)).
- hsearch: the Unix in-memory hash table Berkeley DB also replaced ([03](../../research/03-key-value-document-distributed.md)).
- LevelDB: covered on the [RocksDB and LevelDB](../systems/rocksdb.md) page; single process, no indexes ([03](../../research/03-key-value-document-distributed.md)).
- Megastore: the slower Google store many teams chose over Bigtable to get transactions ([03](../../research/03-key-value-document-distributed.md)).
- Riak: appears only in the title of a secondary source comparing it with Mnesia ([07](../../research/07-code-inside-the-database.md)); no research file describes it.

## Shared tradeoffs

- **What was given up, and what came back** ([03](../../research/03-key-value-document-distributed.md)):

| Gave up | Who took it back | Why |
|---|---|---|
| Multi-item transactions | BDB 2.0, RocksDB, DynamoDB 2018, MongoDB 4.0/4.2, Spanner, Cassandra 6 (alpha) | Users kept coding around their absence (Spanner). Customers asked (DynamoDB). Index upkeep (Bigtable) |
| Schema | MongoDB validation, Cassandra `CHECK` (alpha) | Bad data spread through schemaless collections (inference) |
| Joins | MongoDB `$lookup` only | The others still duplicate data per query |

- **Transactions came back narrowed:** single-shot (DynamoDB, Cassandra's Accord) or with warnings (MongoDB). Strong consistency across sites stayed opt-in and costs latency or features ([03](../../research/03-key-value-document-distributed.md)). See [Transactions whose reads and writes are known up front](../ideas/read-and-write-sets-known-up-front.md).
- **The guarantee hides in configuration.** Every system in the family hides its consistency level in configuration or per-call settings; none states it in the reply ([03](../../research/03-key-value-document-distributed.md), inference). See [Telling the caller what a read or write guarantees](../ideas/consistency-reported-to-the-caller.md).
- **Acknowledged writes can be lost** under default or weak settings: Redis's `everysec` and cluster failover, MongoDB's old `w: 1` ([03](../../research/03-key-value-document-distributed.md)). See [Replying only after a write is durable](../ideas/reply-only-after-durable-write.md).
- **Clashing writes are settled three ways:** silently by clock ([last writer wins](../ideas/last-writer-wins.md), Cassandra), kept as versions for the application ([conflicts kept as data](../ideas/conflicts-kept-as-data.md), Dynamo, CouchDB), or refused by a version check ([optimistic concurrency](../ideas/optimistic-concurrency.md), Redis `WATCH`, CouchDB `_rev`, DynamoDB) ([03](../../research/03-key-value-document-distributed.md); [06](../../research/06-divergent-copies-and-merging.md)).
- **Summary** ([03](../../research/03-key-value-document-distributed.md)):

| System | Strength | What pays for it | Weakness |
|---|---|---|---|
| Berkeley DB | ACID inside the process | No server, no queries, page locks | Page-lock contention |
| Redis | Atomic commands, memory speed | One command thread, async durability | Acknowledged writes can be lost |
| LevelDB/RocksDB | Cheap writes | Compaction amplification | Write stalls, unpredictable latency |
| Dynamo | Never refuses a write | No isolation, app-side merge | Deleted items resurface |
| DynamoDB | Scalable ACID transactions | Single-shot only, low contention | No transactions in strong multi-Region mode |
| Bigtable | Scale on sorted rows | Single-row atomicity | Hard for evolving schemas |
| Cassandra | Tunable, leaderless availability | LWW on clocks, no joins | Silent overwrites; duplicated tables drift |
| MongoDB | Documents read in one go | Embedding instead of joins | Guarantees depend on per-call settings |
| CouchDB | Replicate anywhere, offline | Conflicts left to the app | Hidden conflict branches |

- The years in [03](../../research/03-key-value-document-distributed.md)'s headings for Redis, LevelDB, RocksDB, DynamoDB, Cassandra, MongoDB and CouchDB come from memory, not from fetched pages (not confirmed).

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- https://github.com/meta/rocksdb/wiki/RocksDB-Overview
- https://www.mongodb.com/docs/manual/data-modeling/
