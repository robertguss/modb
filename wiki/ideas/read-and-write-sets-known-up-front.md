# Transactions whose reads and writes are known up front

Here a transaction is sent as one request that already names everything it will read and write, instead of a conversation of reads, decisions and writes. Knowing the read set (everything read) and write set (everything written) in advance lets the database check, schedule or analyse the transaction before it runs.

## What it is

- **Single-shot transactions.** DynamoDB's transactions send all reads and writes in one request, with optimistic timestamp ordering (https://www.usenix.org/conference/atc23/presentation/idziorek). Cassandra's planned Accord transactions are strict-serializable across partitions and non-interactive (https://theconsensus.dev/p/2026/08/16/transactions-in-cassandra.html) ([03](../../research/03-key-value-document-distributed.md)).
- **Non-interactive writes with assertions.** XTDB write transactions are not interactive, so a client cannot read, decide and write inside one. It sends `ASSERT` predicates instead, which roll the transaction back if false ([05](../../research/05-databases-that-keep-history.md), https://docs.xtdb.com/about/txs-in-xtdb.html).
- **Read and write sets recorded as code runs.** Convex records "what each transaction reads and writes" and checks for overlap at commit ([07](../../research/07-code-inside-the-database.md), https://stack.convex.dev/how-convex-works).
- **Sets known before execution.** The research system Calvin needs "advance knowledge of all transactions' read/write sets". When a set depends on data, it runs a "reconnaissance query" first and restarts if the guess was wrong ([07](../../research/07-code-inside-the-database.md), https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf).

## The problem it solves

- **A database that can analyse what it runs.** Declaring the whole read and write set up front suits a database that wants to analyse what it runs ([03](../../research/03-key-value-document-distributed.md)).
- **Known reads and writes give three things** ([07](../../research/07-code-inside-the-database.md)): conflict detection without locks (Convex, GemStone); exact subscriptions, where a query re-runs when data it read changes (Convex); and scheduling before execution (Calvin).
- **No transaction held open.** AWS found long transactions "were not required" and workloads "not highly contentious" ([03](../../research/03-key-value-document-distributed.md)). A single request cannot stall while an agent thinks; an agent that opens a transaction and calls a model for 30 seconds is the long transaction every engine punishes ([01](../../research/01-relational-and-transactional.md), inference).
- **The gap it points to.** In-database code in Convex and SpacetimeDB is opaque to the database, which cannot analyse its read and write sets or effects to plan, verify or migrate it ([00](../../research/00-landscape-overview.md), inference). Every system learns read sets by watching code run. A whole-program compiler could derive conservative read and write sets and check effects before anything runs; no production database was found that does it ([07](../../research/07-code-inside-the-database.md), inference).

## What it costs

- **No back-and-forth inside a transaction**, and retries under contention ([03](../../research/03-key-value-document-distributed.md)).
- **Sets that depend on data** need a guess first and a restart if it was wrong (Calvin, [07](../../research/07-code-inside-the-database.md)).
- **Sets derived by a compiler must be conservative,** so a computed key widens to the whole table, which is Convex's broad-conflict problem moved to compile time ([07](../../research/07-code-inside-the-database.md), inference).
- **Not available everywhere.** DynamoDB's strong multi-Region mode does "not support transaction operations" (https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html).

## Systems that use it

- [Dynamo and DynamoDB](../systems/dynamodb.md): single-shot transactions since 2018 ([03](../../research/03-key-value-document-distributed.md)).
- [Apache Cassandra](../systems/cassandra.md): Accord, non-interactive, in 6.0 alpha and off by default ([03](../../research/03-key-value-document-distributed.md)).
- [XTDB](../systems/xtdb.md): non-interactive writes with `ASSERT` ([05](../../research/05-databases-that-keep-history.md)).
- [Convex](../systems/convex.md): read and write sets recorded at run time ([07](../../research/07-code-inside-the-database.md)).

Related: [Deterministic functions as transactions](deterministic-functions-inside-transactions.md) and [Optimistic concurrency and version-checked writes](optimistic-concurrency.md).

## Cannot be combined with

Interactive transactions where a client reads, decides and writes inside one open transaction ([05](../../research/05-databases-that-keep-history.md); [03](../../research/03-key-value-document-distributed.md)).

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- https://www.usenix.org/conference/atc23/presentation/idziorek
- https://theconsensus.dev/p/2026/08/16/transactions-in-cassandra.html
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html
- https://docs.xtdb.com/about/txs-in-xtdb.html
- https://stack.convex.dev/how-convex-works
- https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf
