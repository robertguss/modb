# Materialize

Materialize is a database that keeps query results up to date as the input data changes, instead of computing them when they are read. It is built on Differential Dataflow ([Materialize](https://materialize.com/blog/differential-from-scratch/); [research 00](../../research/00-landscape-overview.md); [research 07](../../research/07-code-inside-the-database.md)).

## What it is for

Results that are always fresh without re-running queries, including multi-way joins ([research 00](../../research/00-landscape-overview.md)). The technique is called *incremental view maintenance* ([research 07](../../research/07-code-inside-the-database.md)).

## Core idea

Each view compiles to a dataflow on Differential Dataflow, which processes changes as `(time, diff)` updates. An *arrangement* is the indexed history a dataflow keeps. Its memory is "roughly proportional to its number of distinct (data, time) pairs" ([arrangements](https://materialize.com/docs/fundamentals/concepts/arrangements/)).

## Strengths and what pays for each

- **Fresh, consistent results.** In the default strict-serializable mode, "time cannot go backwards" ([consistency](https://materialize.com/blog/strong-consistency-in-materialize/)). Paid for by: memory for arrangements, and views written in a restricted language the engine can differentiate ([research 07](../../research/07-code-inside-the-database.md)).

## Weaknesses

- Changing a view means building a replacement and *hydrating* it, that is computing it from scratch. This "briefly reduces freshness", and larger changes use blue/green deployments, where the new version runs beside the old until it is ready ([updating views](https://materialize.com/docs/transform-data/updating-materialized-views/)).
- When code changes, stored results are recomputed from the inputs ([research 07](../../research/07-code-inside-the-database.md)).

## What an agent struggles with

Plain SQL helps, but the memory cost stays invisible until it bites ([research 07](../../research/07-code-inside-the-database.md)).

## Worth borrowing

Results maintained continuously, at the price of memory and a restricted view language. See [query results kept fresh as data changes](../ideas/continuously-updated-query-results.md).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md) (its author did not read Materialize's papers in full)
- Differential from scratch: https://materialize.com/blog/differential-from-scratch/
- Timely Dataflow, CACM: https://cacm.acm.org/research/incremental-iterative-data-processing-with-timely-dataflow/
- Arrangements: https://materialize.com/docs/fundamentals/concepts/arrangements/
- Strong consistency in Materialize: https://materialize.com/blog/strong-consistency-in-materialize/
- Updating materialized views: https://materialize.com/docs/transform-data/updating-materialized-views/
