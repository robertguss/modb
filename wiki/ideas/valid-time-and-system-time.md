# Two timelines: valid time and system time

Each fact carries two times: when it was true in the world, and when the database learned it. A store that keeps both is called *bitemporal*.

## What it is

- *System time*: when the database learned a fact.
- *Valid time*: when the fact was true in the world.

A correction made today about last March keeps both what was believed and what is now known ([05](../../research/05-databases-that-keep-history.md)).

## The problem it solves

After-the-fact corrections. With one timeline, fixing last March's data either rewrites history or leaves it wrong. With two, both versions stay queryable ([05](../../research/05-databases-that-keep-history.md)).

## What it costs

- **Every query needs an "as of when?"** Two time axes double the ways a query can be wrong, and the question is easy to forget ([05](../../research/05-databases-that-keep-history.md)).
- **Writes that split periods collide with each other.** PostgreSQL reverted `UPDATE/DELETE FOR PORTION OF` from version 19 on 2026-09-15 (https://www.postgresql.org/message-id/E1x6QRv-00000000QOV-0oQc%40gemulon.postgresql.org). A contributor's write-up gives the reason: updating part of a period splits a row in two, and a second writer waiting on that row wakes to find it shrunk, cannot see the new piece, and silently updates nothing (https://tapoueh.org/blog/2026/09/getting-ready-for-postgresql-19/). The commit message lists commits, not the reason ([05](../../research/05-databases-that-keep-history.md)).

## Systems that use it

- [XTDB](../systems/xtdb.md): every table is bitemporal (https://www.xtdb.com/blog/launching-xtdb-v2).
- [SQL:2011 temporal tables](../systems/sql-temporal-tables.md): the standard has system-versioned tables and application-time period tables (https://sigmodrecord.org/2012/09/30/temporal-features-in-sql2011/).
- [PostgreSQL](../systems/postgresql.md): version 18 (2025-09-25) added valid-time keys (`WITHOUT OVERLAPS`, `PERIOD` foreign keys) but no system versioning (https://www.postgresql.org/about/featurematrix/detail/temporal-constraints/).
- Zep/Graphiti, an agent-memory store, keeps facts with two timelines and marks a contradicted fact invalid rather than deleting it (https://arxiv.org/abs/2501.13956). It keeps facts in Neo4j with validity intervals on every edge (https://neo4j.com/blog/developer/graphiti-knowledge-graph-memory/). [09](../../research/09-agents-and-databases-today.md) lists two timelines among the mechanisms for "who changed what, and why".

## Disagreements

- **What a bitemporal store records about a change.** [00](../../research/00-landscape-overview.md) says bitemporal stores record when a fact changed and who wrote it, but not why. [05](../../research/05-databases-that-keep-history.md) says SQL:2011 tables record only time and transaction (no user), and XTDB can hold a requester only in optional, unchecked metadata. See [Recording why a write happened](recording-why-a-write-happened.md).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://www.xtdb.com/blog/launching-xtdb-v2
- https://sigmodrecord.org/2012/09/30/temporal-features-in-sql2011/
- https://www.postgresql.org/about/featurematrix/detail/temporal-constraints/
- https://www.postgresql.org/message-id/E1x6QRv-00000000QOV-0oQc%40gemulon.postgresql.org
- https://tapoueh.org/blog/2026/09/getting-ready-for-postgresql-19/
- https://arxiv.org/abs/2501.13956
- https://neo4j.com/blog/developer/graphiti-knowledge-graph-memory/
