# Row and column security

The database hides whole rows, or whole columns, from a reader according to a policy. It hides; it does not transform what a permitted reader sees.

## What it is

A policy checked on each query that removes rows or columns the reader may not see. [PostgreSQL](../systems/postgresql.md) row policies are the example the research studied (https://www.postgresql.org/docs/current/ddl-rowsecurity.html).

## The problem it solves

Whole rows or columns stay out of a reader's results ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Supabase and Postgres use row-level security as one of the few ways agent access is scoped today ([09](../../research/09-agents-and-databases-today.md)). See [access scoped to what an agent may do](scoped-access-for-agents.md).

## What it costs

- **A policy check on every query** ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Side channels.** In PostgreSQL, unique and foreign-key checks "always bypass row security", which the docs call a "covert channel" (https://www.postgresql.org/docs/current/ddl-rowsecurity.html). A reader can learn that a hidden row exists from a constraint failure.
- **Speed exceptions.** Functions marked `LEAKPROOF` may run before the policy, for speed (https://www.postgresql.org/docs/current/sql-createfunction.html).
- **A policy the agent cannot read.** It is enforced, but an agent cannot inspect it; MCP servers show schemas, not policies (inference, [09](../../research/09-agents-and-databases-today.md)).

## Systems that use it

- [PostgreSQL](../systems/postgresql.md) and Supabase (https://www.postgresql.org/docs/current/ddl-rowsecurity.html, [09](../../research/09-agents-and-databases-today.md)).
- [IFDB](../systems/ifdb.md) went further: rows carry labels and results are tainted by what they read, without covert channels (https://pmg.csail.mit.edu/pubs/schultz13__ifdb_decentralized_ifc-abstract.html). See [labels that follow data](information-flow-labels.md).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- https://www.postgresql.org/docs/current/sql-createfunction.html
- https://pmg.csail.mit.edu/pubs/schultz13__ifdb_decentralized_ifc-abstract.html
