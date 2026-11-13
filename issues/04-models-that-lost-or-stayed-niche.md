# Models that lost or stayed niche

Type: research
Status: resolved

## Question

Using the map's research template, what did the data models that lost to relational, or stayed niche, do well and badly?

Cover hierarchical (IMS), network (CODASYL), object databases (GemStone, ObjectStore), XML stores, graph (Neo4j), triple stores, and logic or Datalog systems (Datomic's query language, TypeDB, Souffle).

Go deepest on why each lost or stayed niche, and whether that reason still holds when the user is an AI agent and not a person writing queries by hand.

## Answer

Findings: [research/04-models-that-lost-or-stayed-niche.md](../research/04-models-that-lost-or-stayed-niche.md).

- Many losses were market reasons (standards, vendor size, too little gain to pay for) that do not apply here. The technical reasons that survive are loss of data independence, complexity, and stored data and code having to change together.
- Record-at-a-time navigation (IMS, CODASYL, and Datomic's ordered clauses) makes the writer the query planner. That is worse for agents with no memory, not better.
- A new query language starts where SPARQL does with an LLM: 3.3% correct unprompted against 47% for SQL, but 76% with similar worked examples. The database can serve those examples.
- Weak default isolation (Neo4j read committed, duplicate `MERGE`) is a quiet hazard for agents that retry. Datomic's single writer with compare-and-swap fits coordination-first.
- GemStone's reduced-conflict classes are an old, working form of type-declared semantic merging.
