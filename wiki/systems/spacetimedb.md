# SpacetimeDB

SpacetimeDB is a database that runs application code inside itself. "Modules" compiled to WebAssembly, or run on V8, execute in the database and sync state to clients ([SpacetimeDB docs](https://spacetimedb.com/docs/databases/); [research 00](../../research/00-landscape-overview.md)).

## What it is for

Removing the separate application server, the ORM and cache invalidation ([research 00](../../research/00-landscape-overview.md)).

## Core idea

- **Reducers** are its mutations. Each runs in a transaction and is "designed to be free of side effects" ([reducers](https://github.com/clockworklabs/SpacetimeDB/blob/master/docs/docs/00200-core-concepts/00200-functions/00300-reducers/00300-reducers.md)).
- **Procedures**, added in version 2.0, may call HTTP. Their transaction callback "may be invoked multiple times, possibly seeing a different version of the database state each time" ([procedures](https://spacetimedb.com/docs/functions/procedures/)). In C# they are still marked unstable. Version 2.0 also added TypeScript modules ([release v2.0.1, 2026-02-20](https://github.com/clockworklabs/SpacetimeDB/releases/tag/v2.0.1)).
- **Migrations.** Republishing a module migrates additive changes automatically: new tables, new indexes, or columns added at the end with a default. Changing or removing columns "will cause the publish to fail" ([automatic migrations](https://spacetimedb.com/docs/databases/automatic-migrations/)). Those changes need a hand-written migration ([incremental migrations](https://spacetimedb.com/docs/databases/incremental-migrations/)).

## Strengths and what pays for each

- **Transactions and live updates to clients from one place.** Paid for by: reducers must be free of side effects. SpacetimeDB enforces this with a sandbox, as Convex does; most other systems rely on discipline ([research 07](../../research/07-code-inside-the-database.md); [research 00](../../research/00-landscape-overview.md)).
- **Automatic additive migration.** Paid for by: refusing every breaking change until someone writes a migration ([research 07](../../research/07-code-inside-the-database.md)).
- **Its functions live in the application repository**, in a general language, and deploy together with the schema, which fixes the versioning, testing and portability complaints about stored procedures. The work still lands on the database server ([research 07](../../research/07-code-inside-the-database.md)).

## Weaknesses

- Breaking schema changes are refused ([research 07](../../research/07-code-inside-the-database.md)).
- Procedure transactions can re-run against a different database state each time ([procedures](https://spacetimedb.com/docs/functions/procedures/)).
- The database cannot analyse the code it runs, for example its reads, writes and effects, to plan, verify or migrate it (inference, [research 00](../../research/00-landscape-overview.md)).

## Overlapping work

Research 07 could not confirm whether reducers run one at a time. The docs say only that reducers "don't see changes from other concurrent reducers" ([research 07](../../research/07-code-inside-the-database.md)).

## What an agent struggles with

Research 07 rates it, with Convex, the most legible of the systems it studied: the function is the whole transaction. The traps are hidden rules ([research 07](../../research/07-code-inside-the-database.md)).

## Worth borrowing

- **Refuse a deploy the stored data does not fit**, but migrate additive changes automatically. Cost: every breaking change needs a written migration ([research 07](../../research/07-code-inside-the-database.md)).
- **Side-effect-free transaction functions.** See [deterministic functions as transactions](../ideas/deterministic-functions-inside-transactions.md).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md) (lists SpacetimeDB 2.0's 170k transactions per second as a vendor claim it could not confirm)
- SpacetimeDB docs: https://spacetimedb.com/docs/databases/
- Reducers: https://github.com/clockworklabs/SpacetimeDB/blob/master/docs/docs/00200-core-concepts/00200-functions/00300-reducers/00300-reducers.md
- Procedures: https://spacetimedb.com/docs/functions/procedures/
- Automatic migrations: https://spacetimedb.com/docs/databases/automatic-migrations/
- Incremental migrations: https://spacetimedb.com/docs/databases/incremental-migrations/
- Release v2.0.1: https://github.com/clockworklabs/SpacetimeDB/releases/tag/v2.0.1
