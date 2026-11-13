# pgvector (HNSW indexes)

pgvector adds similarity search over embeddings to PostgreSQL, using approximate indexes such as HNSW. An embedding is a list of numbers standing for the meaning of an item. It belongs to the [time-series, search, vector and spatial family](../families/specialised-stores.md).

## What it is for

- Finding the items nearest an embedding ([research 02](../../research/02-analytical-and-specialised.md)). Research 00 names pgvector and turbopuffer as the vector family's representatives ([TigerData](https://www.tigerdata.com/blog/vector-database-basics-hnsw)).
- It runs inside [PostgreSQL](postgresql.md).
- The market has cooled: Pavlo wrote that "the buzz around vector databases has muted" ([Pavlo, Jan 2026](https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html)).

## Core idea

- **Approximate nearest-neighbour indexes.** HNSW is a layered graph that links each item to its near neighbours; a search walks the graph instead of comparing every row ([research 02](../../research/02-analytical-and-specialised.md)).

## Strengths and what pays for each

- **Fast similarity search.** *Paid for by* possibly incomplete answers ([research 02](../../research/02-analytical-and-specialised.md)).

## Weaknesses

- **Filters cut results silently.** Filters apply after the index scan. With a condition matching 10% of rows, "only 4 rows will match on average" by default. Version 0.8.0 added iterative scans ([pgEdge mirror of pgvector's docs](https://docs.pgedge.com/pgvector/development/filtering/)).
- **Deletes can lower recall.** Deletes leave **tombstones** (markers for removed items), and "the search still traverses deleted nodes", so recall (the share of true neighbours found) can drift ([multigrid, secondary](https://multigrid.ai/learn/index-updates)). Weaviate's code shows the mechanism ([delete.go](https://github.com/weaviate/weaviate/blob/master/adapters/repos/db/vector/hnsw/delete.go)). Research 02 says this rests on secondary sources with no measurement.

## What an agent struggles with

- **A filtered search returns too few results, with no error** ([research 02](../../research/02-analytical-and-specialised.md)).

## Worth borrowing

From research 02:

- **Approximate index plus exact check**, so the approximation is never the final answer. Cost: a second pass, and vectors have no cheap exact check.
- **Derived indexes fed from one log**, like a Raft learner, that never block a write and can be rebuilt. Cost: lag. See [derived copies fed from one log](../ideas/derived-copies-fed-from-one-log.md).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- Primary links are given inline above.
