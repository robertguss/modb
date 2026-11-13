# Facts that are added, never changed

The database never edits a stored value. A change adds a new fact, and the old one stays.

## What it is

- In [Datomic](../systems/datomic.md), data is *datoms*: one fact each (entity, attribute, value, transaction, added or retracted). Changes add datoms; nothing is edited ([05](../../research/05-databases-that-keep-history.md), https://docs.datomic.com/transactions/acid.html).
- In an event store such as [KurrentDB](../systems/kurrentdb.md), events are appended to streams, and state is rebuilt from them ([05](../../research/05-databases-that-keep-history.md)).
- [Kafka](../systems/kafka.md) is a partitioned, replicated append-only log (https://kafka.apache.org/43/design/design/).
- [Amazon QLDB](../systems/amazon-qldb.md) chained its journal with SHA-256 hashes, so any change to the past could be detected (https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html).

## The problem it solves

Rows changed in place lose the past. Datomic and [XTDB](../systems/xtdb.md) dropped that assumption and got free history, queries as of any time, and audit ([00](../../research/00-landscape-overview.md)). A database can then be held as a value frozen in time ([05](../../research/05-databases-that-keep-history.md)). Any reader can query any past moment without locks ([05](../../research/05-databases-that-keep-history.md)). See [Reading the database as it was](time-travel-queries.md).

## What it costs

- **Storage grows forever.** Every system with unbounded history added a way to forget: Datomic `noHistory`, SQL Server retention, KurrentDB `$maxAge` and scavenging, Snowflake's 90-day cap, Kafka compaction ([05](../../research/05-databases-that-keep-history.md)). Berkeley POSTGRES never overwrote rows; its time travel was dropped in v6.2 for "performance impact, storage size, and a pg_time file which grows toward infinite size" (https://www.postgresql.org/docs/6.3/c0503.htm). The no-overwrite storage survived as multi-version reads, with vacuum discarding versions nobody needs (https://dev.to/franckpachot/postgresql-multi-version-from-time-travel-to-concurrency-control-b5). See [Multi-version snapshots](multi-version-snapshots.md).
- **Deleting is second-class.** See [Deleting personal data from a store that keeps history](deleting-personal-data-from-history.md).
- **"Now" costs more** unless current state is kept separately ([05](../../research/05-databases-that-keep-history.md)).
- **Schema can never break the past.** See [Schemas that only grow](grow-only-schema.md).
- **In Datomic and XTDB, one writer.** Paid for with write throughput capped by one machine ([05](../../research/05-databases-that-keep-history.md)).

## Systems that use it

[Datomic](../systems/datomic.md), [XTDB](../systems/xtdb.md), [KurrentDB](../systems/kurrentdb.md), [Apache Kafka](../systems/kafka.md), [Amazon QLDB](../systems/amazon-qldb.md).

## Disagreements

- **Does Datomic ever remove data?** [00](../../research/00-landscape-overview.md) says Datomic accumulates facts and never updates in place. [05](../../research/05-databases-that-keep-history.md) adds that `noHistory` and excision, which deletes datoms outside the timeline, let history be dropped.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- https://docs.datomic.com/transactions/acid.html
- https://kafka.apache.org/43/design/design/
- https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html
- https://www.postgresql.org/docs/6.3/c0503.htm
- https://dev.to/franckpachot/postgresql-multi-version-from-time-travel-to-concurrency-control-b5
