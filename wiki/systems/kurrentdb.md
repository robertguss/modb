# KurrentDB (formerly EventStoreDB)

KurrentDB is an *event store*: a database that keeps the list of things that happened, not the current state. It is the main example of event sourcing in the research.

## What it is for

Storing what happened instead of current state. State comes from replaying events into *projections*, which are derived read models (https://martinfowler.com/eaaDev/EventSourcing.html). See [Storing events instead of current state](../ideas/storing-events-instead-of-state.md).

## Core idea

- Events are appended to *streams*. Nothing is edited ([05](../../research/05-databases-that-keep-history.md)).
- Readers see current state through projections built from the events ([05](../../research/05-databases-that-keep-history.md)).

## Strengths and what pays for each

- **A causal record of what happened, with expected-version checks.** Paid for by reading through projections ([05](../../research/05-databases-that-keep-history.md)).
- **Links between events and their causes.** Standard metadata fields `$correlationId` and `$causationId` link an event to the request and the message that caused it (https://docs.kurrent.io/server/v26.0/features/streams). This gives "because of what", not a reason or an approver ([05](../../research/05-databases-that-keep-history.md)). See [Recording why a write happened](../ideas/recording-why-a-write-happened.md).

## Weaknesses

- **Deletes wait for scavenging.** Deleted events stay readable via `$all` "until a scavenging process removes them"; "scavenging is destructive" (https://docs.kurrent.io/server/v26.0/features/streams, https://docs.kurrent.io/server/v26.0/operations/scavenge). History can also be bounded with `$maxAge` ([05](../../research/05-databases-that-keep-history.md)).
- **Format changes are painful.** A practitioner study found five techniques: versioned events, weak schema, *upcasting* (converting old events as they are read), in-place transformation, and copy-and-transform. Only the last two break immutability, and they are kept for when performance or maintainability suffers (https://arxiv.org/html/2104.01146). See [Schemas that only grow](../ideas/grow-only-schema.md).

## Overlapping work

Each append names the *expected revision* of the stream. If another writer got there first, the store throws `WrongExpectedVersionException` and the writer retries (https://docs.kurrent.io/clients/node/v1.2/appending-events). This is *optimistic concurrency*: check for a conflict only at the end. See [Optimistic concurrency](../ideas/optimistic-concurrency.md).

## What an agent struggles with

Agents read projections, which lag and can disagree with each other ([05](../../research/05-databases-that-keep-history.md)).

## Worth borrowing

These are the researcher's inference ([05](../../research/05-databases-that-keep-history.md)).

- An expected-version check on every append. Costs one integer per stream, and turns overlapping work into a conflict an agent can see and retry.
- Crypto-shredding for personal data (see [Deleting personal data](../ideas/deleting-personal-data-from-history.md)).

## Sources

- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- https://martinfowler.com/eaaDev/EventSourcing.html
- https://docs.kurrent.io/clients/node/v1.2/appending-events
- https://docs.kurrent.io/server/v26.0/features/streams
- https://docs.kurrent.io/server/v26.0/operations/scavenge
- https://arxiv.org/html/2104.01146
