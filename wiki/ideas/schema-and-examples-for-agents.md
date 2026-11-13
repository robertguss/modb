# Serving schema and worked examples to agents

The database itself hands an agent its schema, hints about the data, and worked example queries, so an agent with no memory can learn what exists and how to ask for it. The evidence is strongest for query languages with little training data.

## What it is

- **Worked examples in the prompt.** In one benchmark (SM3), with similar worked examples in each prompt, correct SPARQL rose from 3.3% to 75.75% (https://arxiv.org/html/2411.05521). A new query language starts where SPARQL does, and the database can supply the examples ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Hints about the data.** Giving agents hints about the data cut their queries by more than 20% ([09](../../research/09-agents-and-databases-today.md), https://arxiv.org/html/2509.00997v2).
- **Schema introspection.** Neon's and Supabase's MCP servers list tables and describe schemas ([09](../../research/09-agents-and-databases-today.md)). MCP is a protocol through which an agent calls outside tools.

## The problem it solves

- **Agents spend much of their querying on schema lookups.** The Berkeley "Supporting Our AI Overlords" paper found agents do high-throughput exploratory querying, much of it looking up schemas and statistics rather than attempting the task ([09](../../research/09-agents-and-databases-today.md), https://arxiv.org/abs/2509.00997). [04](../../research/04-models-that-lost-or-stayed-niche.md) cites the same study.
- **Niche languages lack training data.** Given only the schema, the best model wrote correct SQL 47% of the time, Cypher 34% and SPARQL 3.3%. The authors tie this to training data: 6,000 SPARQL posts on Stack Overflow against 673,000 for SQL (https://arxiv.org/abs/2411.05521, https://arxiv.org/html/2411.05521). The reason a language stays niche has changed: once few people learned it; now few examples exist ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Schema-last stores leave nothing to look up.** With no declared shape there is nothing for an agent to discover ([04](../../research/04-models-that-lost-or-stayed-niche.md), inference).

## What it costs

- **Keeping examples correct as the schema grows** ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **A declared schema up front**, since there must be something to serve ([04](../../research/04-models-that-lost-or-stayed-niche.md), inference).
- **Schemas are not policies.** MCP introspection shows what is stored, not what the agent is allowed to do. Row-level security is enforced but cannot be inspected by the agent ([09](../../research/09-agents-and-databases-today.md), inference). See [Access scoped to what an agent may do](scoped-access-for-agents.md).

## Systems that use it

- [RDF triple stores (SPARQL)](../systems/rdf-triple-stores.md): the clearest case for serving examples ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- [Neo4j](../systems/neo4j.md): 34% correct Cypher from the schema alone ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- [Neon](../systems/neon.md): an MCP server that lists tables and describes schemas ([09](../../research/09-agents-and-databases-today.md), https://github.com/neondatabase/mcp-server-neon/).

## Disagreements

- **Whether database MCP servers have guardrails.** [00](../../research/00-landscape-overview.md) reports Pavlo's view that MCP database servers are mostly thin proxies with no real guardrails. [09](../../research/09-agents-and-databases-today.md) describes Neon's MCP server testing a migration on a temporary branch and applying it only after the user confirms, and Supabase adding read-only mode and project scoping after the July 2025 leak; it agrees that MCP introspection shows schemas, not policies.
- The SM3 benchmark used 2024 models (Llama 3, GPT-3.5 class); whether its figures carry over to today's frontier models was not confirmed ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://arxiv.org/abs/2411.05521
- https://arxiv.org/html/2411.05521
- https://arxiv.org/abs/2509.00997
- https://arxiv.org/html/2509.00997v2
- https://github.com/neondatabase/mcp-server-neon/
