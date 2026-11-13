# Derived copies fed from one log

One ordered log of changes is the source of truth, and every other form of the data (search indexes, column copies, read models, live query results) is derived by replaying that log. The derived copies never block a write and can be rebuilt, but they lag.

## What it is

- **Copies that follow the log without voting.** TiDB's columnar TiFlash replicas are Raft *learners*: they receive the replicated log but do not vote, so transactional work never waits for them. Reads get snapshot isolation by checking the Raft index ([02](../../research/02-analytical-and-specialised.md), https://docs.pingcap.com/tidb/stable/tiflash-overview/, https://www.vldb.org/pvldb/vol13/p3072-huang.pdf).
- **Change data capture (CDC).** Streaming the transaction log out to feed an open-format copy. Databricks bought Mooncake on 2025-10-01 to mirror Postgres changes "in real time to the lakehouse" ([02](../../research/02-analytical-and-specialised.md), https://www.databricks.com/blog/mooncake-labs-joins-databricks-accelerate-vision-lakebase).
- **Projections.** In event sourcing, state comes from replaying events into *projections*, derived read models ([05](../../research/05-databases-that-keep-history.md), https://martinfowler.com/eaaDev/EventSourcing.html).
- **A log as the database.** Kafka is a partitioned, replicated append-only log; "what is true now" needs a separate read model ([05](../../research/05-databases-that-keep-history.md), https://kafka.apache.org/43/design/design/).
- **Incrementally maintained views.** Materialize compiles each view to a dataflow that processes changes as `(time, diff)` updates, keeping results fresh without re-running the query ([07](../../research/07-code-inside-the-database.md), https://materialize.com/docs/fundamentals/concepts/arrangements/).

## The problem it solves

- **Text, vector and column copies that never block a write and can be rebuilt** ([02](../../research/02-analytical-and-specialised.md)).
- **Analytics on live data.** Every attempt to rejoin transactional and analytical work keeps two layouts and pays to keep them in step; the rejoin moved outside the database through CDC ([02](../../research/02-analytical-and-specialised.md)). See [Transactions and analytics in one system](transactions-and-analytics-together.md).
- **Huge write rates and replay by many readers** (Kafka, [05](../../research/05-databases-that-keep-history.md)).
- **Results that are always fresh** without re-running queries (Materialize, [07](../../research/07-code-inside-the-database.md)). See [Query results kept fresh as data changes](continuously-updated-query-results.md).

## What it costs

- **Lag.** Derived copies lag the log ([02](../../research/02-analytical-and-specialised.md)). A TiFlash analytical read may wait for its replica to catch up ([02](../../research/02-analytical-and-specialised.md)). CDC gives back "the lagging second copy HTAP set out to avoid" ([02](../../research/02-analytical-and-specialised.md)).
- **Copies that disagree.** Agents read projections, which lag and can disagree with each other ([05](../../research/05-databases-that-keep-history.md)).
- **A second copy's storage or memory.** TiFlash keeps a second full copy ([02](../../research/02-analytical-and-specialised.md)). Materialize's arrangements use memory "roughly proportional to its number of distinct (data, time) pairs" (https://materialize.com/docs/fundamentals/concepts/arrangements/).
- **Missed deletes.** Kafka compaction keeps only "the final state", and a reader lagging more than `delete.retention.ms` (default 24 hours) can miss deletes ([05](../../research/05-databases-that-keep-history.md)).
- **Rebuilding takes time.** Changing a Materialize view means building a replacement and *hydrating* it from scratch, which "briefly reduces freshness" ([07](../../research/07-code-inside-the-database.md), https://materialize.com/docs/transform-data/updating-materialized-views/).
- **A wait if a reader needs its own write.** Freshness in the interface costs a wait on the read path ([02](../../research/02-analytical-and-specialised.md)). See [Telling the caller what a read or write guarantees](consistency-reported-to-the-caller.md).

## Systems that use it

- [Apache Kafka](../systems/kafka.md): the log itself, with read models derived elsewhere ([05](../../research/05-databases-that-keep-history.md)).
- [KurrentDB](../systems/kurrentdb.md): an event store whose readers use projections ([05](../../research/05-databases-that-keep-history.md)).
- [Materialize](../systems/materialize.md): views maintained from a stream of changes ([07](../../research/07-code-inside-the-database.md)).
- TiDB with TiFlash, which has no page ([02](../../research/02-analytical-and-specialised.md)).

## Sources

- [02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- https://docs.pingcap.com/tidb/stable/tiflash-overview/
- https://www.vldb.org/pvldb/vol13/p3072-huang.pdf
- https://www.databricks.com/blog/mooncake-labs-joins-databricks-accelerate-vision-lakebase
- https://martinfowler.com/eaaDev/EventSourcing.html
- https://kafka.apache.org/43/design/design/
- https://materialize.com/docs/fundamentals/concepts/arrangements/
- https://materialize.com/docs/transform-data/updating-materialized-views/
