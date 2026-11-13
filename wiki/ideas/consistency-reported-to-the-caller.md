# Telling the caller what a read or write guarantees

The idea is that each reply from the database says what it actually guarantees: whether a write is durable on a majority, whether a read includes the caller's own write, or whether the value was merged from two versions. Today systems keep this in configuration or per-call settings, and the reply does not say.

## What it is

- **State the guarantee in the reply.** Saying "durable on a majority" or "merged from two versions" in each answer ([03](../../research/03-key-value-document-distributed.md), inference).
- **Freshness in the interface.** An agent could ask "does this read include my write?", as Elasticsearch's refresh or TiFlash's Raft-index check already allow ([02](../../research/02-analytical-and-specialised.md)). TiFlash reads get snapshot isolation by checking the Raft index, the position in the replicated log the copy has reached (https://docs.pingcap.com/tidb/stable/tiflash-overview/).

## The problem it solves

Every system in the key-value, document and distributed family hides its consistency level in configuration ([03](../../research/03-key-value-document-distributed.md)). So an agent cannot see what it got:

- **Redis.** An "OK" may not survive a failover, and no reply says so (inference). "Usually there are small windows where acknowledged writes can be lost" (https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/), and `WAIT` "does not make Redis a strongly consistent store" (https://redis.io/docs/latest/commands/WAIT/) ([03](../../research/03-key-value-document-distributed.md)).
- **MongoDB.** The guarantee is a setting passed with each call, and the old defaults were unsafe (inference). Jepsen found 4.2.6 transactions fell back to `w: 1` and "appeared to lose acknowledged writes" (https://jepsen.io/analyses/mongodb-4.2.6) ([03](../../research/03-key-value-document-distributed.md)).
- **DynamoDB.** The guarantee depends on the mode, the API and the Region; an agent cannot read it from the data (inference). In eventual multi-Region mode other Regions may see part of a transaction (https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html) ([03](../../research/03-key-value-document-distributed.md)).
- **Cassandra.** Each request picks a consistency level; a low one stays available and diverges ([03](../../research/03-key-value-document-distributed.md), https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html).
- **Elasticsearch.** A document is searchable only after a refresh, every second, "but only on indices that have received one search request or more in the last 30 seconds" (https://www.elastic.co/docs/manage-data/data-store/near-real-time-search). An agent can write, search at once, and find nothing ([02](../../research/02-analytical-and-specialised.md)).
- **ClickHouse.** ReplacingMergeTree removes duplicates "only during a merge", at "an unknown time"; a plain `SELECT` can return stale rows unless it adds `FINAL` ([02](../../research/02-analytical-and-specialised.md), https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/replacingmergetree). Write-once pieces merged in the background leave a window where data is visible but unsettled, "which the database must report" ([02](../../research/02-analytical-and-specialised.md)).

## What it costs

- Bytes in every reply, and design effort ([03](../../research/03-key-value-document-distributed.md), inference).
- A freshness check adds a wait on the read path ([02](../../research/02-analytical-and-specialised.md)).

## Systems that use it

No system in the research states the guarantee in each reply; this is a proposal ([03](../../research/03-key-value-document-distributed.md), inference). The partial mechanisms it builds on:

- [Elasticsearch](../systems/elasticsearch.md): refresh controls when a write becomes visible ([02](../../research/02-analytical-and-specialised.md)).
- [MongoDB](../systems/mongodb.md): write concern chosen per call; `majority` by default since 5.0 (https://webassets.mongodb.com/mongodb_whats_new_5.0.pdf).
- [Redis](../systems/redis.md): `WAIT`, which does not make it strongly consistent ([03](../../research/03-key-value-document-distributed.md)).
- [DynamoDB](../systems/dynamodb.md): eventual and strong multi-Region modes, chosen per table ([03](../../research/03-key-value-document-distributed.md)).
- [Apache Cassandra](../systems/cassandra.md): consistency level per request ([03](../../research/03-key-value-document-distributed.md)).

Related: [Guarantees checked by a tool, not stated by a name](guarantees-checked-by-a-tool.md) and [Replying only after a write is durable](reply-only-after-durable-write.md).

## Sources

- [02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- https://docs.pingcap.com/tidb/stable/tiflash-overview/
- https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/
- https://redis.io/docs/latest/commands/WAIT/
- https://jepsen.io/analyses/mongodb-4.2.6
- https://webassets.mongodb.com/mongodb_whats_new_5.0.pdf
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html
- https://cassandra.apache.org/doc/stable/cassandra/architecture/dynamo.html
- https://www.elastic.co/docs/manage-data/data-store/near-real-time-search
- https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/replacingmergetree
