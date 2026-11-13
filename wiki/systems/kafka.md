# Apache Kafka

Kafka is a partitioned, replicated, append-only log. Some teams use it as a database of events.

## What it is for

Very high write rates, with many readers replaying the same log ([05](../../research/05-databases-that-keep-history.md)).

## Core idea

- Records are appended to a partitioned, replicated log (https://kafka.apache.org/43/design/design/).
- *Log compaction* keeps only the latest record for each key. A *tombstone* (a key with a null value) deletes that key (same page).

## Strengths and what pays for each

- **Huge write rates and replay by many readers.** Paid for by no queries and no conditional writes ([05](../../research/05-databases-that-keep-history.md)).

## Weaknesses

- **Compaction keeps only "the final state"** (https://kafka.apache.org/43/design/design/).
- **Lagging readers can miss deletes.** A reader more than `delete.retention.ms` behind (24 hours by default) can miss a tombstone (same page). See [Deleting personal data](../ideas/deleting-personal-data-from-history.md).

## Overlapping work

None per key. KIP-27 proposed an "expected offset" so brokers would refuse stale writes, citing "multiple competing tasks" creating "an inconsistent state" (https://cwiki.apache.org/confluence/spaces/KAFKA/pages/60623883/KIP-27+-+Conditional+Publish). It is not implemented; its formal status line was not seen ([05](../../research/05-databases-that-keep-history.md)). A 2026 post says Kafka still "has no such mechanism" and suggests one owner per entity (vendor claim, from an event-store vendor: https://docs.eventsourcingdb.io/blog/2026/07/20/kafka-is-not-an-event-store/).

## What an agent struggles with

"What is true now" needs a separate read model ([05](../../research/05-databases-that-keep-history.md)). See [Storing events instead of current state](../ideas/storing-events-instead-of-state.md).

## Worth borrowing

One owner per key instead of locks. Costs routing (researcher's inference, [05](../../research/05-databases-that-keep-history.md)).

## Sources

- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- https://kafka.apache.org/43/design/design/
- https://cwiki.apache.org/confluence/spaces/KAFKA/pages/60623883/KIP-27+-+Conditional+Publish
- https://docs.eventsourcingdb.io/blog/2026/07/20/kafka-is-not-an-event-store/
