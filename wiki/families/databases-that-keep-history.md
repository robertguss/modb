# Databases that keep history

These databases keep old versions of data instead of overwriting them, so they can answer "what was true then?" and "what changed?". They range from stores of immutable facts to event logs, ledgers and SQL tables with a history table beside them.

## What they are for

Audit, history and "as of" queries ([00](../../research/00-landscape-overview.md)). Datomic and XTDB dropped the assumption that rows can be changed in place, and got free history, queries as of any time, and audit in return ([00](../../research/00-landscape-overview.md)). See [Facts that are added, never changed](../ideas/append-only-facts.md) and [Reading the database as it was](../ideas/time-travel-queries.md).

## Members

- [Datomic](../systems/datomic.md): immutable facts (datoms), one serial writer, Datalog queries.
- [XTDB](../systems/xtdb.md): every table keeps [two timelines](../ideas/valid-time-and-system-time.md); writes applied one at a time from a log.
- [SQL:2011 temporal tables (SQL Server, MariaDB)](../systems/sql-temporal-tables.md): a standard history table beside the live one.
- [KurrentDB (formerly EventStoreDB)](../systems/kurrentdb.md): an event store; [state rebuilt from events](../ideas/storing-events-instead-of-state.md).
- [Apache Kafka](../systems/kafka.md): a partitioned append-only log used as a database.
- [Amazon QLDB](../systems/amazon-qldb.md): a ledger with a hash-chained journal; withdrawn in 2025.

Mentioned in the research without a page:

- MariaDB system-versioned tables: MariaDB's form of SQL:2011 history, which needs a separate `DELETE HISTORY` privilege ([05](../../research/05-databases-that-keep-history.md)).
- FlureeDB: a 2026 launch claiming signed transactions, time travel and branching for agents; vendor marketing, not verified ([09](../../research/09-agents-and-databases-today.md)).
- Zep and Graphiti: an agent-memory store that keeps facts with two timelines and marks a contradicted fact invalid instead of deleting it ([09](../../research/09-agents-and-databases-today.md), [04](../../research/04-models-that-lost-or-stayed-niche.md)).
- EventSourcingDB: an event-store vendor whose 2026 post says Kafka has no conditional publish ([05](../../research/05-databases-that-keep-history.md)).

Mainstream systems also keep bounded history: [Snowflake](../systems/snowflake.md) and [Oracle](../systems/oracle.md) ([05](../../research/05-databases-that-keep-history.md)).

## Shared tradeoffs

- **One writer.** Datomic has one transactor; XTDB applies writes one at a time from a totally ordered log ([05](../../research/05-databases-that-keep-history.md)). This buys lock-free reads of any past moment, and caps writes at one machine. See [One writer at a time](../ideas/one-writer-at-a-time.md).
- **Never forgetting costs storage, so every system added a way to forget.** Datomic `noHistory`, SQL Server retention, KurrentDB `$maxAge` and scavenging, Snowflake's 90-day cap, Kafka compaction. PostgreSQL dropped its original time travel over it ([05](../../research/05-databases-that-keep-history.md), https://www.postgresql.org/docs/6.3/c0503.htm).
- **Deleting personal data is always second-class.** Excision, scavenging and crypto-shredding all sit outside the normal write path ([05](../../research/05-databases-that-keep-history.md)). See [Deleting personal data from a store that keeps history](../ideas/deleting-personal-data-from-history.md).
- **History makes "now" pay** unless current state is kept separately. QLDB warned that table scans caused "concurrency conflicts and transaction timeouts" (https://docs.aws.amazon.com/qldb/latest/developerguide/ql-reference.select.html). Datomic and XTDB default to the present ([05](../../research/05-databases-that-keep-history.md)).
- **Schema across history has three options:** never break it (Datomic), convert on read (event stores), or rewrite (SQL Server and Oracle, which refuse some changes or need history switched off first) ([05](../../research/05-databases-that-keep-history.md)). See [Schemas that only grow](../ideas/grow-only-schema.md).
- **The slot for "why" exists but nothing fills it.** The transaction record could carry a reason; none of these systems requires, checks or types one ([05](../../research/05-databases-that-keep-history.md)). See [Recording why a write happened](../ideas/recording-why-a-write-happened.md).
- **Bounded history is what mainstream users accept.** Snowflake and Oracle keep a window and charge for storage (researcher's inference, [05](../../research/05-databases-that-keep-history.md)).

Two disagreements between sources touch the whole family:

- **Who made a change.** [00](../../research/00-landscape-overview.md) says bitemporal stores record when a fact changed and who wrote it, but not why. [05](../../research/05-databases-that-keep-history.md) says QLDB, Snowflake and SQL:2011 tables record only time and transaction (no user), Oracle records only a usually shared logon user, and Datomic and XTDB can hold a purpose or requester only in optional, unchecked transaction metadata.
- **Whether Datomic ever removes data.** [00](../../research/00-landscape-overview.md) says Datomic never updates in place. [05](../../research/05-databases-that-keep-history.md) adds `noHistory` and excision, which drop history.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://www.postgresql.org/docs/6.3/c0503.htm
- https://docs.aws.amazon.com/qldb/latest/developerguide/ql-reference.select.html
