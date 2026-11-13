# CockroachDB

CockroachDB is a distributed SQL database that spreads the relational model over many machines. It defaults to serializable transactions and changes schemas in background stages. It belongs to the [relational and transactional family](../families/relational-and-transactional.md).

## What it is for

- Relational transactions spread over many machines, like [Spanner](spanner.md) ([research 01](../../research/01-relational-and-transactional.md)).

## Core idea

- **[Serializable by default](../ideas/serializable-by-default.md).** Retries are pushed onto the client ([retry reference](https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference)). Read committed is opt-in ([docs](https://docs.cockroachlabs.com/docs/stable/read-committed)).
- **[Schema changes in stages](../ideas/staged-schema-changes.md)**, adopted from Google's F1. Schema changes run as background jobs that hold no locks on table data and can be paused or cancelled ([online schema changes](https://docs.cockroachlabs.com/docs/stable/online-schema-changes)).
- **Published design models.** CockroachDB publishes a TLA+ specification of its parallel commits ([blog](https://www.cockroachlabs.com/blog/parallel-commits/)). TLA+ describes a design as states and steps, and a model checker explores every interleaving of a small instance. See [formal design models](../ideas/formal-design-models.md).

## Strengths and what pays for each

- **Serializable by default.** *Paid for by* client-side retries ([retry reference](https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference)).
- **Online schema change in steps, with no locks on table data.** *Paid for by* non-atomic DDL. DDL in a multi-statement transaction "can fail while other statements succeed", and a backfill can get stuck retrying if it runs past the garbage-collection window ([issue #105632](https://github.com/cockroachdb/cockroach/issues/105632)).
- **Read committed for clients without retry loops** ([docs](https://docs.cockroachlabs.com/docs/stable/read-committed)). *Paid for by* a weaker level, which moves the cost of serializability into application bugs ([research 01](../../research/01-relational-and-transactional.md)).

## Weaknesses

- **Long transactions fail.** A long transaction whose reads are overwritten is forced to "refresh" and may fail with a retry error ([retry reference](https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference)).
- **Backfills can get stuck** past the garbage-collection window ([issue #105632](https://github.com/cockroachdb/cockroach/issues/105632)).
- **Not confirmed.** Research 01 did not check which release added read committed.

## Overlapping work

- Conflicts surface as retry errors that the client must handle by replaying the transaction ([retry reference](https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference)).

## What an agent struggles with

Inference from research 01.

- **Retrying correctly.** After a retry error the agent must replay the whole transaction and re-read data. If its reasoning depended on what it read, the retry must re-run the reasoning too.
- **Thinking inside a transaction.** A long-open transaction is the one most likely to be forced to refresh and fail.

## Worth borrowing

- **Serializable by default.** Cost: every write needs a retry path, and aborts rise under contention, unless the database replays the transaction itself ([research 01](../../research/01-relational-and-transactional.md)).
- **Schema change as staged states run by a background job.** Cost: a change takes several steps over time and is not atomic ([research 01](../../research/01-relational-and-transactional.md)).
- **A design specification beside the code.** Cost: the specification is a second program that must be kept matched to the code ([research 08](../../research/08-correctness-first-databases.md)).

## Disagreements

- **Whether agents really hold transactions open.** Research 01 found no study and marks its agent reasoning as inference; research 08 and 09 cite a 2026 workshop paper saying agents do ([SAO workshop](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf)).

## Sources

- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- Primary links are given inline above.
