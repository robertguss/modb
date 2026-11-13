# Replying only after a write is durable

The database sends "done" only once the write is safely stored, on disk or on enough copies, so an acknowledged write cannot vanish in a crash or failover. Many systems reply earlier for speed.

## What it is

- **Durable** means the write survives a crash. On one machine that needs *fsync*, the call that forces data from memory onto disk ([08](../../research/08-correctness-first-databases.md)). Across machines it means enough copies hold it, such as MongoDB's `majority` write concern ([03](../../research/03-key-value-document-distributed.md)).
- **Output gates.** In Cloudflare Durable Objects, output gates hold replies until writes are durable ([07](../../research/07-code-inside-the-database.md), https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/).
- **Mo** is listed with Durable Objects as replying only after the write is durable ([07](../../research/07-code-inside-the-database.md)).

## The problem it solves

**Acknowledged writes being lost**, one of Jepsen's recurring findings: a write is confirmed, then gone (https://jepsen.io/consistency/phenomena/lost-write). The usual cause is acknowledging before fsync ([08](../../research/08-correctness-first-databases.md)). Examples:

- **NATS JetStream** fsyncs "only once every two minutes, but acknowledges messages immediately". Simulated power failures lost 131,418 of 930,005 messages (2025-12-08) ([08](../../research/08-correctness-first-databases.md), https://jepsen.io/analyses/nats-2.12.1).
- **Redis.** With the default `appendfsync everysec` you "can afford to lose up to one second worth of writes" (https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/). Redis Cluster has "small windows where acknowledged writes can be lost" (https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/) ([03](../../research/03-key-value-document-distributed.md)).
- **MongoDB 4.2.6** transactions "appeared to lose acknowledged writes" because they fell back to `w: 1` (https://jepsen.io/analyses/mongodb-4.2.6). Since 5.0 the default write concern is `majority` (vendor PDF, https://webassets.mongodb.com/mongodb_whats_new_5.0.pdf). With weaker settings, writes on the minority side of a partition can be rolled back later ([03](../../research/03-key-value-document-distributed.md)).

For an agent, an "OK" that may not survive a failover, with no reply saying so, is the trap ([03](../../research/03-key-value-document-distributed.md), inference).

## What it costs

- **Latency on every write** ([07](../../research/07-code-inside-the-database.md)).
- **Speed given up.** Redis's speed comes from memory, paid for by durability ([03](../../research/03-key-value-document-distributed.md)); waiting for the disk takes that back.
- **Availability on a partition.** With `majority`, MongoDB writes on the minority side fail ([03](../../research/03-key-value-document-distributed.md)).

## Systems that use it

- [Cloudflare Durable Objects](../systems/cloudflare-durable-objects.md): output gates hold replies until writes are durable ([07](../../research/07-code-inside-the-database.md)).
- [MongoDB](../systems/mongodb.md): `majority` by default since 5.0 ([03](../../research/03-key-value-document-distributed.md)).
- [Redis](../systems/redis.md): does not by default; `everysec` can lose up to a second, and `WAIT` "does not make Redis a strongly consistent store" (https://redis.io/docs/latest/commands/WAIT/).
- [Jepsen](../systems/jepsen.md): the tester that finds systems which reply before the write is durable ([08](../../research/08-correctness-first-databases.md)).

Related: [Telling the caller what a read or write guarantees](consistency-reported-to-the-caller.md).

## Sources

- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- [08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/
- https://jepsen.io/consistency/phenomena/lost-write
- https://jepsen.io/analyses/nats-2.12.1
- https://jepsen.io/analyses/mongodb-4.2.6
- https://webassets.mongodb.com/mongodb_whats_new_5.0.pdf
- https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/
- https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/
- https://redis.io/docs/latest/commands/WAIT/
