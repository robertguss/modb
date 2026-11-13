# PostGIS (R-tree indexes)

PostGIS adds spatial data to PostgreSQL: shapes that overlap, or lie near a point or region. Its spatial indexes are R-trees. It belongs to the [time-series, search, vector and spatial family](../families/specialised-stores.md).

## What it is for

- Finding shapes that overlap or lie near a point or region ([research 02](../../research/02-analytical-and-specialised.md)). It runs inside [PostgreSQL](postgresql.md).

## Core idea

- **An R-tree** nests rectangles inside rectangles. In PostGIS it is built through Postgres's GiST index type ([PostGIS workshop](https://postgis.net/workshops/en/postgis-intro/indexing.html)).
- Spatial indexes "index the bounding boxes of the features", not the shapes themselves (same page). A bounding box is the smallest rectangle that encloses a shape.

## Strengths and what pays for each

- **Fast candidate search.** *Paid for by* an exact second test. The box operator `&&` alone over-counts, as the same workshop page shows ([PostGIS workshop](https://postgis.net/workshops/en/postgis-intro/indexing.html)).

## Weaknesses

- **The index answer is only a candidate list.** It needs an exact test on the real shapes ([research 02](../../research/02-analytical-and-specialised.md)).

## What an agent struggles with

- **Using the box test alone and trusting the answer** ([research 02](../../research/02-analytical-and-specialised.md)).

## Worth borrowing

- **Approximate index plus exact check.** The approximation is never the final answer. Cost: a second pass ([research 02](../../research/02-analytical-and-specialised.md)).

## Sources

- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- Primary links are given inline above.
