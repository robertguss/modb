# Neo4j

Neo4j is a property-graph database: it stores nodes and relationships, both carrying key-value properties, and queries them with the Cypher language. It is a popular store for agent memory.

## What it is for

Relationship-heavy data: social links, fraud rings, knowledge graphs ([04](../../research/04-models-that-lost-or-stayed-niche.md)). Queries that traverse many relationships ([00](../../research/00-landscape-overview.md)).

## Core idea

- Nodes and relationships, both with key-value properties. Neo4j stores edges as pointers, "as in CODASYL", which suits "traversing long edge chains" ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf).
- Native graph storage where each node points to its neighbours ("index-free adjacency") ([00](../../research/00-landscape-overview.md), https://neo4j.com/blog/graph-database/16-things-to-consider-when-selecting-the-right-graph-database/, vendor page).

## Strengths and what pays for each

- **Fast multi-hop traversal and a short query language, Cypher.** Paid for by having to win on speed alone ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- Over $200M annual recurring revenue (vendor claim, 2024-11-19, https://neo4j.com/press-releases/neo4j-revenue-milestone-2024/).
- Graphs are a popular agent-memory store: Graphiti keeps facts in Neo4j with validity intervals on every edge (https://neo4j.com/blog/developer/graphiti-knowledge-graph-memory/).

## Weaknesses

- Relational systems are catching up. The 2024 paper cites relational systems beating graph databases, DuckDB's SQL/PGQ "by up to 10×" (https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf); the research file did not read the cited study ([04](../../research/04-models-that-lost-or-stayed-niche.md), not confirmed). SQL:2023 added graph queries, and GQL became ISO/IEC 39075 in April 2024 (https://www.iso.org/standard/76120.html).
- **Weak default isolation.** The default is *read committed*: a transaction sees only committed data but may see it change between reads. Lost updates can happen "when a query does not have a direct dependency on the property being read" (https://neo4j.com/docs/operations-manual/current/database-internals/concurrent-data-access/).
- **`MERGE` (find-or-create) can create duplicates** under concurrency without a uniqueness constraint; Neo4j recommends constraints (https://neo4j.com/docs/cypher-manual/current/clauses/merge/).

## Overlapping work

Writes take locks; deadlocks are detected and one transaction ends with a transient error to retry (https://neo4j.com/docs/operations-manual/current/database-internals/concurrent-data-access/).

## What an agent struggles with

- In one benchmark, the best model given only the schema wrote correct SQL 47% of the time and correct Cypher 34% (https://arxiv.org/abs/2411.05521). See [Serving schema and worked examples to agents](../ideas/schema-and-examples-for-agents.md).
- The bigger risk is weak isolation. Agents retry and run in parallel, and a `MERGE` duplicate is a quiet error nobody notices ([04](../../research/04-models-that-lost-or-stayed-niche.md), inference).

## Worth borrowing

- **Uniqueness by declared constraint, not find-or-create.** Cost: schema comes first ([04](../../research/04-models-that-lost-or-stayed-niche.md)). See [Rules the database enforces across transactions](../ideas/invariants-the-database-enforces.md).
- The contrast with [set-at-a-time queries](../ideas/set-at-a-time-queries.md): Neo4j stores pointers the way CODASYL did ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Disagreements

- **Graph databases versus relational systems on traversal.** [00](../../research/00-landscape-overview.md) presents index-free adjacency, from a Neo4j vendor page, as what solves many-hop queries. [04](../../research/04-models-that-lost-or-stayed-niche.md) cites the 2024 survey that relational systems beat graph databases (DuckDB SQL/PGQ "by up to 10×"), but says it did not read the cited study.

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf
- https://neo4j.com/blog/graph-database/16-things-to-consider-when-selecting-the-right-graph-database/
- https://www.iso.org/standard/76120.html
- https://neo4j.com/docs/operations-manual/current/database-internals/concurrent-data-access/
- https://neo4j.com/docs/cypher-manual/current/clauses/merge/
- https://neo4j.com/press-releases/neo4j-revenue-milestone-2024/
- https://neo4j.com/blog/developer/graphiti-knowledge-graph-memory/
- https://arxiv.org/abs/2411.05521
