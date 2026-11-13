# Key-value, document and distributed stores

Research run on 2026-11-13 by a subagent using Exa. It goes deeper than [00-landscape-overview.md](00-landscape-overview.md) on what these systems gave up from relational databases, what they took back, and what each does when the network splits. Lines marked "inference" are my reasoning, not a source.

## Terms used below

- **Key-value store**: you put and get values by a key. The store does not look inside the value.
- **Network partition**: some machines can still run but cannot reach each other.
- **Quorum**: a write or read counts once some minimum number of copies (replicas) answer.
- **Eventual consistency**: copies may disagree for a while, and agree once writes stop.
- **Linearizable / strictly serializable**: every reader sees one order of events that matches real time, as if there were one copy.
- **Optimistic concurrency**: run without locks, then check at commit whether someone else changed the same data; if so, fail and retry.
- **Last write wins (LWW)**: when two writes clash, keep the one with the later clock timestamp and silently drop the other.

## Systems

### dbm and Berkeley DB (embedded library, Berkeley DB from about 1991)

- **For**: Berkeley DB began as a free replacement for Unix's `dbm`/`ndbm` on-disk hash files and the in-memory `hsearch` ([AOSA](https://aosabook.org/en/v1/bdb.html)). Transactions arrived in version 2.0 (1997), replication in 4.0 (2001), SQL in 5.0 (2010) (same source).
- **Core idea**: a library linked into the program, with hash or B-tree files, a write-ahead log (log the change before changing the data, so a crash can be replayed) and locks. "No inter-process communication ... is required" ([What is Berkeley DB](https://web.stanford.edu/class/cs276a/projects/docs/berkeleydb/ref/intro/dbis.html)).
- **Strengths and payers**: strict ACID by default (same page), paid for by locks and a log that every write goes through. No server latency, paid for by having no network access and no query language.
- **Weakness**: it locks whole pages. One writer on a page blocks writers of other records on that page. The authors chose this because it limits the states a page can be in during recovery, and later called the choice "problematic at times" ([AOSA](https://aosabook.org/en/v1/bdb.html)).
- **Overlap**: locks, deadlock detection, and the option to relax isolation.
- **Agent struggle (inference)**: bytes in, bytes out. An agent must already know the value encoding and which keys exist.

### Redis (in-memory data structures, 2009)

- **Core idea**: typed structures (lists, sets, hashes) held in memory. Commands run one at a time on a main thread (see the overview).
- **Strengths and payers**: each command is atomic for free, paid for by one core doing all command work. Speed comes from memory, paid for by durability: with the default `appendfsync everysec` you "can afford to lose up to one second worth of writes" ([persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/)).
- **Gave up**: rollback. "Redis does not support rollbacks of transactions" ([transactions](https://redis.io/docs/latest/develop/using-commands/transactions/)). `MULTI/EXEC` only queues commands. `WATCH` adds optimistic check-and-set: the transaction aborts if a watched key changed.
- **On partition**: Redis Cluster keeps writes "in a best-effort way". "Usually there are small windows where acknowledged writes can be lost", larger for clients in a minority partition ([cluster spec](https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/)). `WAIT` "does not make Redis a strongly consistent store" ([WAIT](https://redis.io/docs/latest/commands/WAIT/)).
- **Agent struggle (inference)**: an "OK" may not survive a failover, and no reply says so.

### LevelDB and RocksDB (log-structured merge trees, 2011 / 2012)

- **Core idea**: writes go to a log and an in-memory table, then to sorted files that background compaction merges.
- **LevelDB** keeps atomic batches and snapshots, but "this is not a SQL database ... no support for indexes", and "only a single process ... can access a particular database at a time" ([README](https://github.com/google/leveldb/blob/main/README.md)).
- **Strengths and payers**: cheap sequential writes, paid for by compaction. RocksDB names the costs: write, read and space amplification. Compaction style trades one against another. For example, at write amplification 50 and 500 MB/s of disk, the database sustains only 10 MB/s ([tuning guide](https://github.com/meta/rocksdb/wiki/RocksDB-Tuning-Guide)).
- **Failure**: when compaction falls behind, RocksDB stalls writes, or reads slow because too many files must be checked (same source).
- **Added back**: transactions. RocksDB offers pessimistic (locking) and optimistic modes. The optimistic one "may not be a good solution" when many transactions update the same keys ([Transactions](https://github.com/meta/rocksdb/wiki/Transactions)).
- **Agent struggle (inference)**: latency depends on background work the caller cannot see.

### Dynamo (2007) and DynamoDB (2012)

- **Dynamo's problem**: the shopping cart "must allow customers to add and remove items ... even amidst network and server failures" ([Dynamo paper](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf)).
- **Gave up, on purpose**: "data stores that provide ACID guarantees tend to have poor availability ... Dynamo does not provide any isolation" guarantees. It allows only single-key updates and has no relational schema (same paper).
- **Core idea**: a "sloppy quorum" writes to the first N *healthy* nodes, so writes are never refused. Vector clocks (a per-node counter attached to each version) detect concurrent versions. Conflict resolution is pushed "to the reads" and to the application (same paper).
- **Price**: the cart merge never loses an add, but "deleted items can resurface" (same paper). Every application must be written to expect several versions of the same item.
- **DynamoDB added transactions back in 2018.** Customers "asked for full ACID transactions" across items and tables. AWS found long transactions "were not required" and workloads "not highly contentious". It therefore built single-shot transactions (all reads and writes sent in one request) with optimistic timestamp ordering ([USENIX ATC 2023](https://www.usenix.org/conference/atc23/presentation/idziorek)). A plain write to an item inside a running transaction is rejected with `TransactionConflictException` ([docs](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis.html)).
- **On partition, across Regions**: two modes ([global tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html)). Eventual mode (MREC): a transaction is atomic only in its own Region, and other Regions may see part of it. Strong mode (MRSC, generally available 2025-06-30 ([AWS](https://aws.amazon.com/about-aws/whats-new/2025/06/amazon-dynamo-db-global-tables-multi-region-strong-consistency-generally-available/))): exactly three Regions ([doc history](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DocumentHistory.html)), "do not support transaction operations", and a write to an item being changed elsewhere fails with `ReplicatedWriteConflictException` and must be retried ([global tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html)).
- **Agent struggle (inference)**: the guarantee depends on the mode, the API and the Region. An agent cannot read it from the data.

### Bigtable (2006) and what came after

- **Core idea**: a sorted map from (row, column, time) to bytes, spread over many servers.
- **Gave up**: "Bigtable supports single-row transactions ... does not currently support general transactions across row keys". The team skipped general transactions until there was a clear use. They found "most applications require only single-row transactions", and that requests for more were mainly about secondary indexes ([Bigtable](https://www.usenix.org/legacy/events/osdi06/tech/chang/chang_html/)).
- **Added back, and why**: Spanner's authors reported "consistently received complaints" that Bigtable was hard to use "for ... complex, evolving schemas, or ... strong consistency in the presence of wide-area replication". Many teams chose Megastore "despite its relatively low performance". Their conclusion: "it is better to have application programmers deal with performance problems due to overuse of transactions ... rather than always coding around the lack of transactions" ([Spanner, TOCS](https://doi.org/10.1145/2491245)).
- **Agent struggle (inference)**: secondary indexes kept by hand across rows go stale after partial failures.

### Cassandra (2008)

- **Core idea**: Bigtable's table layout on Dynamo's leaderless replication. Each request picks a consistency level, Cassandra's menu form of Dynamo's `R + W > N` rule ([architecture](https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html)).
- **Gave up**: joins. "Joins are not supported", so data is duplicated into one table per query ([data modeling](https://cassandra.apache.org/doc/latest/cassandra/developing/data-modeling/intro.html)). Conflicts resolve by last write wins on client or coordinator clocks, so "correctness does depend on these clocks" ([architecture](https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html)).
- **On partition**: a low consistency level stays available and diverges. A quorum level refuses when too few replicas answer.
- **Added back**: compare-and-set "lightweight transactions" on one partition, through Paxos (same page). Next is Accord, CEP-15 ([wiki](https://cwiki.apache.org/confluence/spaces/CASSANDRA/pages/188744725/CEP-15+General+Purpose+Transactions)): strict-serializable transactions across partitions, with no leader. They are non-interactive and enabled per table ([The Consensus, 2026-08](https://theconsensus.dev/p/2026/08/16/transactions-in-cassandra.html)). 6.0 also adds CQL `CHECK` constraints, so some schema rules come back. Both are off by default ([Digitalis, 2026-09](https://digitalis.io/post/apache-cassandra-6-0-everything-that-changed-in-one-page), secondary). As of these sources, 6.0 is alpha only; 5.0.9 is the current stable release ([tags](https://github.com/apache/cassandra/tags); [tracker](https://is.cassandra.released.info/)).
- **Agent struggle (inference)**: a timestamp clash discards a write silently, and the duplicated tables can drift apart.

### MongoDB (2009)

- **Core idea**: JSON-like documents. Data used together is embedded together. "An operation on a single document is atomic" ([atomicity](https://www.mongodb.com/docs/manual/core/write-operations-atomicity/)).
- **Added back, step by step**: `$lookup`, a left outer join ([docs](https://www.mongodb.com/docs/v7.0/reference/operator/aggregation/lookup/)). JSON Schema validation from 3.6 ([docs](https://www.mongodb.com/docs/v5.0/core/schema-validation/)). Multi-document transactions in 4.0 (2018) for replica sets, extended to sharded clusters in 4.2 ([vendor blog](https://www.mongodb.com/company/blog/product-release-announcements/mongodb-multi-document-acid-transactions-general-availability)). The docs still warn that transactions cost more and "should not be a replacement for effective schema design" ([transactions](https://www.mongodb.com/docs/manual/core/transactions/)).
- **Failure**: Jepsen found that 4.2.6 transactions violated snapshot isolation under default settings. They "appeared to lose acknowledged writes" because transactions ignored safer client settings and fell back to `w: 1` ([Jepsen, 2020](https://jepsen.io/analyses/mongodb-4.2.6)). Since 5.0 the default write concern is `majority` ([vendor PDF](https://webassets.mongodb.com/mongodb_whats_new_5.0.pdf)).
- **On partition**: one primary per replica set. With `majority`, writes on the minority side fail; with weaker settings, they can be rolled back later.
- **Agent struggle (inference)**: the guarantee is a setting passed with each call, and the old defaults were unsafe.

### CouchDB (2005)

- **Core idea**: JSON documents with revision IDs, and replication between any two copies, including offline ones.
- **Overlap**: on one node, an update must quote the `_rev` it read, or it gets `409 Conflict`. Across replicas, conflicting edits are kept as branches of a revision tree. Every node picks the same "winner" by a deterministic rule, but "the application ... must always resolve conflicts" ([conflicts](https://docs.couchdb.org/en/stable/replication/conflicts.html)). A plain GET shows only the winner (same page).
- **Gave up**: multi-document transactions. A rewrite on FoundationDB ended in 2022 when its sponsor stopped funding it ([dev list](https://lists.apache.org/thread/9gby4nr209qc4dzf2hh6xqb0cn1439b7)).
- **Agent struggle (inference)**: losing edits stay hidden unless the agent asks with `conflicts=true`.

## What was given up, and what came back

| Gave up | Who took it back | Why |
|---|---|---|
| Multi-item transactions | BDB 2.0, RocksDB, DynamoDB 2018, MongoDB 4.0/4.2, Spanner, Cassandra 6 (alpha) | Users kept coding around their absence (Spanner). Customers asked (DynamoDB). Index upkeep (Bigtable) |
| Schema | MongoDB validation, Cassandra `CHECK` (alpha) | Bad data spread through schemaless collections (inference) |
| Joins | MongoDB `$lookup` only | The others still duplicate data per query |

Transactions came back narrowed: single-shot (DynamoDB, Accord) or with warnings (MongoDB). Strong consistency across sites stayed opt-in and costs latency or features.

## Summary table

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

## Ideas worth borrowing

1. **Keep conflicts as data, as CouchDB and Dynamo do.** Store concurrent versions and make resolving them an explicit step. Cost: every reader must handle more than one version, and unresolved conflicts must be made visible, which CouchDB does not do.
2. **Single-shot transactions with optimistic checks (DynamoDB, Accord).** The whole read and write set is declared up front, which suits a database that wants to analyse what it runs. Cost: no back-and-forth inside a transaction, and retries under contention.
3. **Check-and-set on a version token (`_rev`, `WATCH`).** It is the simplest way to stop lost updates between agents. Cost: callers must re-read and retry.
4. **State the guarantee in the reply.** Every system above hides its consistency level in configuration. Saying "durable on a majority" or "merged from two versions" in each answer would cost bytes and design effort (inference).
5. **Bigtable's restraint.** Add a general feature only after real use demands it. Cost: some users code around the gap meanwhile, as Spanner's authors found.

## What I could not confirm

- The year `dbm` first shipped, and the years in the headings for Redis, LevelDB, RocksDB, DynamoDB, Cassandra, MongoDB and CouchDB. These come from memory, not from a page fetched in this session. The "about 1991" for Berkeley DB is inferred from the AOSA history, which names 4BSD and the 1.85 release without a year.
- MongoDB's one-minute default limit on transaction runtime. I saw it quoted only by a secondary source.
- DynamoDB's item-count limit per transaction. I did not fetch the limits page.
- Cassandra 6.0 details (Accord off by default, `CHECK` constraints) come from third-party pages describing alpha builds. They may change before GA, and no GA date is announced.
- Whether MRSC still lacks transactions after mid-2025. The developer guide said so when fetched.
