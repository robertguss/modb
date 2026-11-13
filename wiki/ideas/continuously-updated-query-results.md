# Query results kept fresh as data changes

The database keeps a query's result up to date as the underlying data changes, and pushes the new result to whoever is watching, instead of computing it again each time it is read ([research 00](../../research/00-landscape-overview.md); [research 07](../../research/07-code-inside-the-database.md)).

## What it is

Two forms appear in the research:

- **Incremental view maintenance.** A view is compiled so that each change to the input produces a change to the output, without re-running the query. In [Materialize](../systems/materialize.md) each view becomes a dataflow on Differential Dataflow, which processes changes as `(time, diff)` updates, including multi-way joins ([arrangements](https://materialize.com/docs/fundamentals/concepts/arrangements/); [Materialize](https://materialize.com/blog/differential-from-scratch/)).
- **Subscriptions driven by read sets.** In [Convex](../systems/convex.md) the *read set* (everything a query read) drives subscriptions: when data a query read changes, "the query is rerun" ([How Convex works](https://stack.convex.dev/how-convex-works)). Sync engines push the rows an app needs into the client: [Electric](../systems/electric.md) syncs "Shapes" out of Postgres, [Zero](../systems/zero.md) syncs the subset of rows the app's queries need, and [SpacetimeDB](../systems/spacetimedb.md) modules sync state to clients ([research 00](../../research/00-landscape-overview.md)).

## The problem it solves

Results that are always fresh without re-running queries ([research 00](../../research/00-landscape-overview.md)). For Convex and SpacetimeDB, research 00 lists reactivity as part of what they get by removing the separate application server, along with no ORM and no cache invalidation ([research 00](../../research/00-landscape-overview.md)).

## What it costs

- **Memory.** A Materialize *arrangement* (the indexed history a dataflow keeps) uses memory "roughly proportional to its number of distinct (data, time) pairs" ([arrangements](https://materialize.com/docs/fundamentals/concepts/arrangements/)). For agents, that cost stays invisible until it bites ([research 07](../../research/07-code-inside-the-database.md)).
- **A restricted language.** Views must be written in a language the engine can differentiate ([research 07](../../research/07-code-inside-the-database.md)).
- **Slow changes to the view.** Changing a view means building a replacement and computing it from scratch (*hydrating*). This "briefly reduces freshness", and larger changes use blue/green deployments ([updating views](https://materialize.com/docs/transform-data/updating-materialized-views/)).
- **Determinism.** Convex's exact subscriptions rest on functions being deterministic and their reads being recorded; the sandbox that guarantees this forbids I/O and limits user code to 1 second ([research 07](../../research/07-code-inside-the-database.md)).

## Systems that use it

- [Materialize](../systems/materialize.md): incrementally maintained SQL views, strict-serializable by default ([consistency](https://materialize.com/blog/strong-consistency-in-materialize/)).
- [Convex](../systems/convex.md): queries re-run when their read set changes.
- [SpacetimeDB](../systems/spacetimedb.md): module state synced to clients.
- [Zero](../systems/zero.md): the rows an app's queries need, synced to the client.
- [Electric](../systems/electric.md): "Shapes" synced out of Postgres.

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- Materialize arrangements: https://materialize.com/docs/fundamentals/concepts/arrangements/
- Differential from scratch: https://materialize.com/blog/differential-from-scratch/
- Updating materialized views: https://materialize.com/docs/transform-data/updating-materialized-views/
- How Convex works: https://stack.convex.dev/how-convex-works
