# Apache Cassandra

Cassandra puts Bigtable's table layout on Dynamo's leaderless replication. Each request picks how many copies must answer, and clashing writes are settled by clock timestamps.

## What it is for

Tunable, leaderless availability over many machines ([03](../../research/03-key-value-document-distributed.md)). The 2008 start year comes from memory in the research file, not a fetched page (not confirmed).

## Core idea

- [Bigtable](bigtable.md)'s table layout on [Dynamo](dynamodb.md)'s leaderless replication. Each request picks a *consistency level*, Cassandra's menu form of Dynamo's `R + W > N` rule (enough read and write copies overlap) ([03](../../research/03-key-value-document-distributed.md), https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html).
- Conflicts resolve by [last writer wins](../ideas/last-writer-wins.md) on client or coordinator clocks, so "correctness does depend on these clocks" (same page).

## Strengths and what pays for each

- **Tunable, leaderless availability.** Paid for by last-writer-wins on clocks and no joins ([03](../../research/03-key-value-document-distributed.md)).
- **On a partition**, a low consistency level stays available and diverges. A quorum level refuses when too few replicas answer ([03](../../research/03-key-value-document-distributed.md)).

## Weaknesses

- **No joins.** "Joins are not supported", so data is duplicated into one table per query (https://cassandra.apache.org/doc/latest/cassandra/developing/data-modeling/intro.html).
- Silent overwrites when timestamps clash, and duplicated tables that drift apart ([03](../../research/03-key-value-document-distributed.md)).

## Overlapping work

- **Lightweight transactions:** compare-and-set on one partition, through Paxos (a consensus protocol) (https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html).
- **Accord (CEP-15)** is next: strict-serializable transactions across partitions, with no leader (https://cwiki.apache.org/confluence/spaces/CASSANDRA/pages/188744725/CEP-15+General+Purpose+Transactions). They are non-interactive and enabled per table (https://theconsensus.dev/p/2026/08/16/transactions-in-cassandra.html). See [Transactions whose reads and writes are known up front](../ideas/read-and-write-sets-known-up-front.md).
- **6.0 adds CQL `CHECK` constraints**, so some schema rules come back. Both Accord and `CHECK` are off by default (https://digitalis.io/post/apache-cassandra-6-0-everything-that-changed-in-one-page, secondary). See [Rules the database enforces across transactions](../ideas/invariants-the-database-enforces.md).
- As of these sources, 6.0 is alpha only; 5.0.9 is the current stable release (https://github.com/apache/cassandra/tags, https://is.cassandra.released.info/). The 6.0 details come from third-party pages describing alpha builds and may change before GA; no GA date is announced ([03](../../research/03-key-value-document-distributed.md), not confirmed).

## What an agent struggles with

A timestamp clash discards a write silently, and the duplicated tables can drift apart ([03](../../research/03-key-value-document-distributed.md), inference). The consistency level is chosen per request and not shown in the reply; see [Telling the caller what a read or write guarantees](../ideas/consistency-reported-to-the-caller.md).

## Worth borrowing

**Single-shot transactions with optimistic checks (Accord).** The whole read and write set is declared up front. Cost: no back-and-forth inside a transaction, and retries under contention ([03](../../research/03-key-value-document-distributed.md)).

## Sources

- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html
- https://cassandra.apache.org/doc/latest/cassandra/developing/data-modeling/intro.html
- https://cwiki.apache.org/confluence/spaces/CASSANDRA/pages/188744725/CEP-15+General+Purpose+Transactions
- https://theconsensus.dev/p/2026/08/16/transactions-in-cassandra.html
- https://digitalis.io/post/apache-cassandra-6-0-everything-that-changed-in-one-page
- https://github.com/apache/cassandra/tags
- https://is.cassandra.released.info/
