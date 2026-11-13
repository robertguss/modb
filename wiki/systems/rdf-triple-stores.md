# RDF triple stores (SPARQL)

A triple store holds every fact as a *triple*: subject, predicate, object. It comes from the semantic web, where data from many sources is joined through shared global identifiers (URIs), and is queried with SPARQL.

## What it is for

The semantic web: data from many sources joined through shared global identifiers (URIs) ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Core idea

Every fact is a triple: subject, predicate, object. The 2024 "What Goes Around" paper treats triple stores as a subset of property graphs ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf). See [Neo4j](neo4j.md).

## Strengths and what pays for each

- **Any source's facts merge into one graph without a schema agreed in advance.** Paid for by long identifiers, many self-joins and hard scaling ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Weaknesses

- **Scaling.** The Wikidata Query Service, the largest public triple store, runs on Blazegraph, which "ceased development in 2016" and "is unable to scale to meet the growth targets of Wikidata", with SLO incidents about once a week. Wikimedia split the graph in two in 2025 to buy time and now recommends QLever as the replacement (https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service/WDQS_backend_update/Backend_Replacement).

## What an agent struggles with

- In one benchmark the best model given only the schema wrote correct SPARQL 3.3% of the time, against 47% for SQL. The authors tie this to training data: 6,000 SPARQL posts on Stack Overflow against 673,000 for SQL (https://arxiv.org/html/2411.05521).
- With similar worked examples in each prompt, SPARQL rose to 75.75% (same source).
- The research file's reading: the reason a language stays niche has changed. Once few people learned it; now few examples exist, and the database can supply them ([04](../../research/04-models-that-lost-or-stayed-niche.md)). The benchmark used 2024 models (Llama 3, GPT-3.5 class); whether the figures carry over to today's frontier models was not confirmed.

## Worth borrowing

**Examples and schema served to the agent.** A new query language starts where SPARQL does; examples lifted it from 3.3% to about 76%. Cost: keeping examples correct as the schema grows ([04](../../research/04-models-that-lost-or-stayed-niche.md)). See [Serving schema and worked examples to agents](../ideas/schema-and-examples-for-agents.md).

## Sources

- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf
- https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service/WDQS_backend_update/Backend_Replacement
- https://arxiv.org/html/2411.05521
