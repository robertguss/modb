# Optimistic concurrency and version-checked writes

Optimistic concurrency runs a transaction without locks, then checks at commit whether someone else changed the same data; if so, the transaction fails and is retried. A version-checked write is its smallest form: the write quotes the version it read, and is refused if that version is no longer current.

## What it is

- *Optimistic concurrency*: run without locks, then check at commit whether someone else changed the same data; if so, fail and retry ([03](../../research/03-key-value-document-distributed.md)).
- The check takes several shapes:
  - **A version token on one item.** CouchDB's `_rev` ([03](../../research/03-key-value-document-distributed.md)), Elasticsearch's `if_seq_no` and `if_primary_term` ([02](../../research/02-analytical-and-specialised.md), https://www.elastic.co/docs/reference/elasticsearch/rest-apis/optimistic-concurrency-control), KurrentDB's *expected revision* on each append ([05](../../research/05-databases-that-keep-history.md), https://docs.kurrent.io/clients/node/v1.2/appending-events), Datomic's `:db/cas` ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://docs.datomic.com/transactions/transaction-functions.html), and the ETag on an Orleans grain's state ([07](../../research/07-code-inside-the-database.md), https://dotnet.github.io/orleans/docs/grains/grain-persistence/).
  - **A watched key.** Redis's `WATCH` aborts the transaction if a watched key changed ([03](../../research/03-key-value-document-distributed.md)).
  - **Read and write sets compared at commit.** GemStone compares "your write set with those of all other transactions that committed since your transaction began" ([07](../../research/07-code-inside-the-database.md), https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/9-Transactions.htm). Convex records "what each transaction reads and writes" and checks for overlap at commit (https://stack.convex.dev/how-convex-works). FoundationDB rejects a transaction at commit if someone else changed what it read ([08](../../research/08-correctness-first-databases.md), https://www.foundationdb.org/files/fdb-paper.pdf).
  - **A pointer swap.** An Iceberg writer prepares new metadata, then "commits by swapping the table's metadata file pointer"; if another commit won, it retries on the new version ([02](../../research/02-analytical-and-specialised.md), https://iceberg.apache.org/spec/).

## The problem it solves

- **Lost updates without blocking.** Check-and-set on a version token is "the simplest way to stop lost updates between agents" ([03](../../research/03-key-value-document-distributed.md)). Expected-version checks turn overlapping work into a conflict an agent can see and retry ([05](../../research/05-databases-that-keep-history.md)).
- **Work that overlaps for minutes.** [09](../../research/09-agents-and-databases-today.md) lists optimistic concurrency, with multi-version snapshots and branches, as the best existing mechanism for it.
- **Serializability without locks.** Serializability is paid for with blocking (locks), aborts (optimistic checks) or clock waits (Spanner) ([01](../../research/01-relational-and-transactional.md)). The optimistic choice keeps readers and writers from waiting on each other.
- **Safe reruns.** When the transaction is a deterministic function, a conflict can be handled by discarding the write set and running the function again (Convex, [07](../../research/07-code-inside-the-database.md)).

## What it costs

- **Retries, and failures under contention.**
  - RocksDB's optimistic mode "may not be a good solution" when many transactions update the same keys ([03](../../research/03-key-value-document-distributed.md), https://github.com/meta/rocksdb/wiki/Transactions).
  - In DuckDB, "appends will never conflict", but for two edits to one row "the second thread … will fail with a conflict error" ([02](../../research/02-analytical-and-specialised.md), https://duckdb.org/docs/2.0/connect/concurrency).
  - When Iceberg's retries run out the commit fails with `CommitFailedException` (https://aws.amazon.com/blogs/big-data/manage-concurrent-write-conflicts-in-apache-iceberg-on-the-aws-glue-data-catalog/).
  - A Convex mutation that keeps conflicting fails after several retries; wide reads conflict with every write ([07](../../research/07-code-inside-the-database.md), https://docs.convex.dev/error).
- **Aborts grow with transaction length.** GemStone paid with aborts that grow with transaction length, and a failed commit must abort to get a new view ([04](../../research/04-models-that-lost-or-stayed-niche.md)). CockroachDB forces a long transaction whose reads are overwritten to "refresh", and it may fail with a retry error ([01](../../research/01-relational-and-transactional.md)). FoundationDB transactions may not run "for over five seconds" or exceed 10 MB (https://apple.github.io/foundationdb/known-limitations.html).
- **False aborts.** PostgreSQL's SSI aborts a transaction when an anomaly is *possible*, and every serializable transaction must be retried on SQLSTATE `40001` ([01](../../research/01-relational-and-transactional.md), https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html).
- **Retry is left to the caller.** CockroachDB pushes retries onto the client (https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference). After a retry error an agent must replay the *whole* transaction and re-read; if its reasoning depended on what it read, the reasoning must re-run too ([01](../../research/01-relational-and-transactional.md), inference).
- **The rerun must have no side effects.** Convex's retry is safe only because mutations are sandboxed: "this is why… `fetch` isn't available in mutations" ([07](../../research/07-code-inside-the-database.md)).
- **One integer per stream** for an expected-version check, which [05](../../research/05-databases-that-keep-history.md) calls cheap.

## Systems that use it

- [DuckDB](../systems/duckdb.md): optimistic concurrency control, conflicts found at commit ([02](../../research/02-analytical-and-specialised.md)).
- [Elasticsearch](../systems/elasticsearch.md): per-document sequence-number check ([02](../../research/02-analytical-and-specialised.md)).
- [Apache Iceberg](../systems/iceberg.md): optimistic pointer-swap commits ([02](../../research/02-analytical-and-specialised.md)).
- [Redis](../systems/redis.md): `WATCH` check-and-set ([03](../../research/03-key-value-document-distributed.md)).
- [RocksDB](../systems/rocksdb.md): optional optimistic transactions ([03](../../research/03-key-value-document-distributed.md)).
- [DynamoDB](../systems/dynamodb.md): single-shot transactions with optimistic timestamp ordering ([03](../../research/03-key-value-document-distributed.md), https://www.usenix.org/conference/atc23/presentation/idziorek).
- [CouchDB](../systems/couchdb.md): an update must quote `_rev`, or it gets `409 Conflict` ([03](../../research/03-key-value-document-distributed.md)).
- [GemStone/S](../systems/gemstone.md): optimistic commits, with reduced-conflict classes for counters and bags ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- [Datomic](../systems/datomic.md): `:db/cas`, and a compare-and-swap on the log's root in every transaction ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://docs.datomic.com/transactions/acid.html).
- [KurrentDB](../systems/kurrentdb.md): expected revision; a stale append throws `WrongExpectedVersionException` ([05](../../research/05-databases-that-keep-history.md)). Kafka has no such mechanism; KIP-27 proposed one ([05](../../research/05-databases-that-keep-history.md), https://cwiki.apache.org/confluence/spaces/KAFKA/pages/60623883/KIP-27+-+Conditional+Publish).
- [Amazon QLDB](../systems/amazon-qldb.md): conflicts raised `OccConflictException` for the application to retry ([05](../../research/05-databases-that-keep-history.md), https://qldbguide.com/blog/concurrency-control-in-qldb/).
- [Convex](../systems/convex.md): serializable optimistic transactions with automatic rerun ([07](../../research/07-code-inside-the-database.md); [09](../../research/09-agents-and-databases-today.md), https://docs.convex.dev/database/advanced/occ).
- [FoundationDB](../systems/foundationdb.md): snapshot reads, rejection at commit, client retries ([08](../../research/08-correctness-first-databases.md)).
- [CockroachDB](../systems/cockroachdb.md): serializable by default, with retries pushed to the client ([01](../../research/01-relational-and-transactional.md)).

## Cannot be combined with

- **Side effects inside the transaction.** A rerun repeats them, so Convex forbids `fetch` in mutations ([07](../../research/07-code-inside-the-database.md)). SpacetimeDB 2.0 procedures, which may call HTTP, have a transaction callback that "may be invoked multiple times" (https://spacetimedb.com/docs/functions/procedures/).
- **Long transactions on hot data.** Aborts grow with length (GemStone), FoundationDB caps transactions at five seconds, and optimistic modes suit low contention (RocksDB, DynamoDB) ([03](../../research/03-key-value-document-distributed.md); [04](../../research/04-models-that-lost-or-stayed-niche.md); [08](../../research/08-correctness-first-databases.md)). [Locks held until commit](locks-held-until-commit.md) is the other answer.

## Disagreements

- **Evidence that agents hold transactions open.** This matters for optimistic schemes because aborts grow with length. [01](../../research/01-relational-and-transactional.md) says it found no study of agents holding transactions open, and marks its agent section as reasoning. [08](../../research/08-correctness-first-databases.md) and [09](../../research/09-agents-and-databases-today.md) cite a 2026 workshop paper stating that agents hold transactions open while waiting for the model (https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf).

## Sources

- [01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- [08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- [09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://www.elastic.co/docs/reference/elasticsearch/rest-apis/optimistic-concurrency-control
- https://iceberg.apache.org/spec/
- https://aws.amazon.com/blogs/big-data/manage-concurrent-write-conflicts-in-apache-iceberg-on-the-aws-glue-data-catalog/
- https://duckdb.org/docs/2.0/connect/concurrency
- https://github.com/meta/rocksdb/wiki/Transactions
- https://www.usenix.org/conference/atc23/presentation/idziorek
- https://docs.kurrent.io/clients/node/v1.2/appending-events
- https://cwiki.apache.org/confluence/spaces/KAFKA/pages/60623883/KIP-27+-+Conditional+Publish
- https://qldbguide.com/blog/concurrency-control-in-qldb/
- https://docs.datomic.com/transactions/acid.html
- https://docs.datomic.com/transactions/transaction-functions.html
- https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/9-Transactions.htm
- https://dotnet.github.io/orleans/docs/grains/grain-persistence/
- https://stack.convex.dev/how-convex-works
- https://docs.convex.dev/error
- https://docs.convex.dev/database/advanced/occ
- https://spacetimedb.com/docs/functions/procedures/
- https://www.foundationdb.org/files/fdb-paper.pdf
- https://apple.github.io/foundationdb/known-limitations.html
- https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html
- https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference
- https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf
