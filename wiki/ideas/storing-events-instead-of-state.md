# Storing events instead of current state

Instead of storing what is true now, the database stores the list of changes, and current state is rebuilt by replaying them. This is called *event sourcing*.

## What it is

- Store what happened, not current state. State comes from replaying events into *projections*, which are derived read models (https://martinfowler.com/eaaDev/EventSourcing.html).
- A close relative is the *command log*: [Prevayler](../systems/prevayler.md) writes each change as a serializable command to a journal before applying it. A periodic snapshot plus the journal rebuilds the state (https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html).
- Akka Persistence stores the events that changed an actor and replays them on start (https://doc.akka.io/libraries/akka-core/current/typed/persistence.html).

## The problem it solves

- A causal record of what happened ([05](../../research/05-databases-that-keep-history.md)).
- Many readers can replay the same log ([05](../../research/05-databases-that-keep-history.md)).
- In Prevayler, no concurrency bugs inside the model, and queries are plain method calls ([07](../../research/07-code-inside-the-database.md)).

## What it costs

- **"What is true now" needs a separate read model** ([05](../../research/05-databases-that-keep-history.md)). Projections lag and can disagree with each other ([05](../../research/05-databases-that-keep-history.md)).
- **One writer per stream or object.** Akka rests on "the single-writer principle", because two live instances would interleave events (https://doc.akka.io/libraries/akka-core/current/typed/persistence.html). Prevayler's `execute()` guarantees "only one Transaction is executed at a time" (https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html). See [One writer at a time](one-writer-at-a-time.md).
- **Replay must be deterministic.** Prevayler commands use the passed `executionTime` and never the clock, or replay diverges (same API page). See [Deterministic functions inside transactions](deterministic-functions-inside-transactions.md).
- **Prevayler's extra constraints:** all data fits in RAM, and snapshots block writes ([07](../../research/07-code-inside-the-database.md)).
- **Old event formats live forever.** Events are "usually never deleted", so old events are translated by *event adapters* each time they are read (https://doc.akka.io/libraries/akka-core/current/persistence-schema-evolution.html). See [Schemas that only grow](grow-only-schema.md).
- **Deletion waits.** Deleted KurrentDB events stay readable until scavenging removes them (https://docs.kurrent.io/server/v26.0/operations/scavenge). Kafka readers that lag more than a day can miss deletes (https://kafka.apache.org/43/design/design/).

## Systems that use it

- [KurrentDB](../systems/kurrentdb.md): the event store; an expected-revision check on every append (https://docs.kurrent.io/clients/node/v1.2/appending-events).
- [Apache Kafka](../systems/kafka.md): an append-only log used as an event store, with no queries and no conditional writes ([05](../../research/05-databases-that-keep-history.md)).
- [Prevayler](../systems/prevayler.md): a journal of commands plus snapshots ([07](../../research/07-code-inside-the-database.md)).

## Sources

- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- https://martinfowler.com/eaaDev/EventSourcing.html
- https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html
- https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html
- https://doc.akka.io/libraries/akka-core/current/typed/persistence.html
- https://doc.akka.io/libraries/akka-core/current/persistence-schema-evolution.html
- https://docs.kurrent.io/clients/node/v1.2/appending-events
- https://docs.kurrent.io/server/v26.0/operations/scavenge
- https://kafka.apache.org/43/design/design/
