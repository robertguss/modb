# Stored procedures and triggers

A *stored procedure* is a function stored and run inside the database server. A *trigger* is one the database runs automatically when a row changes. Both keep logic next to the data ([research 07](../../research/07-code-inside-the-database.md)).

## What it is

The function runs inside the caller's transaction. [PostgreSQL](../systems/postgresql.md) asks the author to label each function `VOLATILE`, `STABLE` or `IMMUTABLE`. The label is "a promise to the optimizer"; only non-volatile functions may be used in an index scan ([PG volatility](https://www.postgresql.org/docs/current/xfunc-volatility.html)).

## The problem it solves

Logic that is atomic with the data, with no round trips between the application and the database ([research 07](../../research/07-code-inside-the-database.md)).

## What it costs

- **Compute on the database server**, the hardest part to scale (vendor opinion, [PingCAP](https://www.pingcap.com/blog/why-you-should-replace-stored-procedures-with-a-service-layer/)).
- **Labels that nobody checks.** The database trusts the volatility label; it does not verify it ([research 07](../../research/07-code-inside-the-database.md)).
- **Hidden cascades.** Triggers fire "in alphabetical order by trigger name". Cascades have "no direct limitation", and avoiding infinite recursion "is the trigger programmer's responsibility" ([PG triggers](https://www.postgresql.org/docs/current/trigger-definition.html)).
- **Code outside the software process.** Research 07 traces the complaints to one cause: the code lived in the database but outside the software process.
  - Procedures deploy separately from their callers, and the production version "often doesn't match what's in version control" (vendor opinion, [PingCAP](https://www.pingcap.com/blog/why-you-should-replace-stored-procedures-with-a-service-layer/)).
  - "There's no pure SQL unit testing framework", and debugging tools were "just not there" ([practitioner, 2026-03](https://withblue.ink/2026/03/business-logic-does-not-belong-in-the-database)).
  - Portability is lost ([practitioner](https://phil.lavin.me.uk/2013/03/why-i-dont-like-database-stored-proceedures/)).
  - The work lands on the most expensive server.

[Convex](../systems/convex.md) and [SpacetimeDB](../systems/spacetimedb.md) fix the first three: their functions live in the application repository, in a general language, and deploy together with the schema. Nothing fixes the fourth ([research 07](../../research/07-code-inside-the-database.md)). See [deterministic functions as transactions](deterministic-functions-inside-transactions.md).

**For agents.** A trigger is invisible at the call site, so an agent that writes one row cannot see what else will change ([research 07](../../research/07-code-inside-the-database.md)).

**Concurrency.** Whatever the host database does: locks or snapshots ([research 07](../../research/07-code-inside-the-database.md)).

## Systems that use it

- [PostgreSQL](../systems/postgresql.md): functions with volatility labels, and triggers ([PG volatility](https://www.postgresql.org/docs/current/xfunc-volatility.html); [PG triggers](https://www.postgresql.org/docs/current/trigger-definition.html)).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- PostgreSQL function volatility: https://www.postgresql.org/docs/current/xfunc-volatility.html
- PostgreSQL triggers: https://www.postgresql.org/docs/current/trigger-definition.html
- PingCAP (vendor opinion): https://www.pingcap.com/blog/why-you-should-replace-stored-procedures-with-a-service-layer/
- Business logic does not belong in the database: https://withblue.ink/2026/03/business-logic-does-not-belong-in-the-database
- Why I don't like stored procedures: https://phil.lavin.me.uk/2013/03/why-i-dont-like-database-stored-proceedures/
