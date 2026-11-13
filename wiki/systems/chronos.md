# Chronos (MIT research system)

Chronos is a 2026 research system from MIT that adds branches on top of existing databases without changing them. Its merges become visible in every store at once.

## What it is for

Letting agents explore on branches across several stores: Postgres, SQLite, DuckDB and Qdrant (https://arxiv.org/abs/2609.14889).

## Core idea

- Branches are added by *query rewriting*: Chronos rewrites queries so the unchanged databases underneath behave as if branched ([06](../../research/06-divergent-copies-and-merging.md)).
- Merges have "atomic cross-store visibility": a merge never appears in one store before another (https://arxiv.org/abs/2609.14889).

## Strengths and what pays for each

- **Atomic merge across stores.** Paid for by query rewriting; it is research only ([06](../../research/06-divergent-copies-and-merging.md)).
- **Faster exploration.** The paper reports up to 16.7× faster exploration (https://arxiv.org/abs/2609.14889, via [09](../../research/09-agents-and-databases-today.md)).

## Weaknesses

- **Conflict rules are unclear.** The abstract covers visibility, not how clashing changes are decided ([06](../../research/06-divergent-copies-and-merging.md)).

## Overlapping work

Chronos and Dolt are the only branching systems found that document merging data back ([09](../../research/09-agents-and-databases-today.md)). An atomic merge across every store an agent touched is one of five things "multi-world isolation" would need (inference, [06](../../research/06-divergent-copies-and-merging.md)). See [Many branches that reconcile with each other](../ideas/branches-that-reconcile-with-each-other.md).

## Worth borrowing

Chronos shows branching can be added on top of existing databases without changing them. The researcher counts this as evidence against building a new engine ([09](../../research/09-agents-and-databases-today.md)).

## Sources

- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://arxiv.org/abs/2609.14889
