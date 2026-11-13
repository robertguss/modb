# Schemas that only grow, with conversion on read

The schema may add things but never break old data, and old records are converted as they are read instead of being rewritten. This keeps history intact when code and data shapes change.

## What it is

When code changes, stored data has three options: never break it, convert it on read, or rewrite it ([05](../../research/05-databases-that-keep-history.md)). This idea is the first two together.

- **Grow, never break.** [Datomic](../systems/datomic.md): "You can never alter :db/valueType"; "grow your schema, and never break it" (https://docs.datomic.com/schema/schema-change.html, https://blog.datomic.com/2017/01/the-ten-rules-of-schema-growth.html).
- **Convert on read.** *Upcasting* converts old events as they are read ([KurrentDB](../systems/kurrentdb.md) and event stores, https://arxiv.org/html/2104.01146). Akka's *event adapters* translate old events each time they are read, because events are "usually never deleted" (https://doc.akka.io/libraries/akka-core/current/persistence-schema-evolution.html).

## The problem it solves

History is never rewritten ([05](../../research/05-databases-that-keep-history.md)). Changing code and stored data together is a real problem, sharper for agents, which change code often (inference, [04](../../research/04-models-that-lost-or-stayed-niche.md)).

## What it costs

- **Breaking changes are refused** and need a hand-written migration. [SpacetimeDB](../systems/spacetimedb.md) migrates additive changes automatically (new tables, new indexes, columns added at the end with a default), but changing or removing columns "will cause the publish to fail" (https://spacetimedb.com/docs/databases/automatic-migrations/, https://spacetimedb.com/docs/databases/incremental-migrations/).
- **Old formats live forever** and every read pays to convert them (Akka, above).
- **Immutability bends under pressure.** A practitioner study of event stores found five techniques: versioned events, weak schema, upcasting, in-place transformation, copy-and-transform. Only the last two break immutability, and they are kept for when performance or maintainability suffers (https://arxiv.org/html/2104.01146).

## Systems that use it

- [Datomic](../systems/datomic.md): grow only ([05](../../research/05-databases-that-keep-history.md)).
- [KurrentDB](../systems/kurrentdb.md): upcasting ([05](../../research/05-databases-that-keep-history.md)).
- [SpacetimeDB](../systems/spacetimedb.md): automatic additive migration; breaking changes refused ([07](../../research/07-code-inside-the-database.md)).
- [Convex](../systems/convex.md): a deploy that changes the schema checks all existing documents, and the push fails if any do not match (https://docs.convex.dev/database/schemas). Data migrations run "in batches asynchronously" through a library (https://github.com/get-convex/migrations).
- [GemStone](../systems/gemstone.md): each class keeps a *class history* of versions. Old instances "continue to access the old class's methods" until migrated, one, some or all at a time (https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/11-ClassHistory.htm). Earlier, changing a method on stored objects meant relinking every program that used it ("relink the world"), one reason object databases lost (https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf).
- [Prevayler](../systems/prevayler.md): old data sits in a journal of serialized commands that new classes must still read (inference, [07](../../research/07-code-inside-the-database.md)). How Prevayler handles class changes in an existing journal is not confirmed ([07](../../research/07-code-inside-the-database.md)).

Systems that rewrite instead:

- [SQL:2011 temporal tables](../systems/sql-temporal-tables.md) in SQL Server, and [Oracle](../systems/oracle.md), carry changes into history tables but refuse some, or need history switched off first ([05](../../research/05-databases-that-keep-history.md)). Oracle Flashback Time Travel fails some schema changes with ORA-55610 unless the archive is detached and reattached (https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html).

## Sources

- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- https://docs.datomic.com/schema/schema-change.html
- https://blog.datomic.com/2017/01/the-ten-rules-of-schema-growth.html
- https://arxiv.org/html/2104.01146
- https://doc.akka.io/libraries/akka-core/current/persistence-schema-evolution.html
- https://spacetimedb.com/docs/databases/automatic-migrations/
- https://spacetimedb.com/docs/databases/incremental-migrations/
- https://docs.convex.dev/database/schemas
- https://github.com/get-convex/migrations
- https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/11-ClassHistory.htm
- https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf
- https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html
