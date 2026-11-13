# Models that lost to relational or stayed niche

These are the data models that competed with relational databases and either lost (hierarchical, network, object, XML) or kept a niche (graph, triple stores, Datalog). The question for each is which of its *technical* reasons still hold.

## What they are for

- Two surveys by relational partisans anchor the research. The 2005 review gives numbered lessons from each era (https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf). The 2024 sequel concludes that non-relational systems "are either a niche market or are fast becoming SQL/RM systems" (https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf) ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- The 2005 paper's Lesson 9 says debates "are usually settled by the elephants of the marketplace, and often for reasons that have little to do with the technology". The research therefore sets adoption, standards and vendor size aside ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- Each model aimed at a shape of data: trees (hierarchical), graphs of records (network), programming-language objects (object), loosely structured documents (XML), relationship-heavy data (property graphs), facts merged from many sources (triples), recursive rules over facts (Datalog) ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Members

- [GemStone/S](../systems/gemstone.md): persistent Smalltalk objects, optimistic commits, reduced-conflict classes.
- [Neo4j](../systems/neo4j.md): property graph with pointer-based edges and the Cypher language.
- [RDF triple stores (SPARQL)](../systems/rdf-triple-stores.md): subject-predicate-object facts joined by global identifiers.
- [TypeDB](../systems/typedb.md): typed entity-relation-attribute model; explicit inference since 3.0.

[Datomic](../systems/datomic.md) is also covered by this research as a Datalog database ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

Mentioned in the research without a page:

- IMS: IBM's hierarchical database, built for the Apollo program, first "READY" on 1968-08-14; programs break when storage is reorganised ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://www.ibm.com/history/information-management-system).
- CODASYL network databases: records linked by owner-to-member chains, walked by a programmer-"navigator" (1970s) ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://dl.acm.org/doi/10.1145/355611.362534).
- IDMS: a CODASYL database Broadcom still ships, at version 19.0 ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://www.broadcom.com/products/mainframe/databases/idms).
- ObjectStore: stored C++ objects in memory format, with a page server that "has no knowledge of the contents of a page" ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://doi.org/10.1145/125223.125244).
- XML stores: schema-last documents queried with XQuery; overtaken by JSON ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- MarkLogic: the best-known XML store, now sold as multi-model, bought by Progress in 2023 for $355 million ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://research.isg-one.com/analyst-perspectives/progress-enables-knowledge-graphs-for-semantic-ai).
- Blazegraph: the triple store behind the Wikidata Query Service; development ceased in 2016 ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- QLever: the triple store Wikimedia now recommends as Blazegraph's replacement ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- Wikidata Query Service: the largest public triple store, split in two in 2025 to buy time ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service/WDQS_backend_update/Backend_Replacement).
- Souffle (Soufflé): Datalog compiled into parallel C++ for static program analysis; batch only, no concurrent writers ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://github.com/souffle-lang/souffle/).
- Mangle: Google's 2025 Datalog extension, similar to Soufflé ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://github.com/google/mangle).
- SurrealDB Agent Memory: an agent-memory product launched in 2026; only its launch announcement was found, so treat it as marketing ([00](../../research/00-landscape-overview.md)).

## Shared tradeoffs

- **Navigation against declaration.** IMS's DL/1 and CODASYL are *record-at-a-time*: the program fetches one record per call and decides where to go next, writing the query plan by hand. Lesson 4: this "forces the programmer to do manual query optimization". Lesson 10: "query optimizers can beat all but the best record-at-a-time DBMS application programmers" ([04](../../research/04-models-that-lost-or-stayed-niche.md)). Datomic repeats the cost: its `:where` clauses "are executed in order", so clause order is the query plan (https://docs.datomic.com/reference/best.html). See [Set-at-a-time queries and data independence](../ideas/set-at-a-time-queries.md).
- **Loss of data independence.** *Data independence* means programs keep working when storage or schema is reorganised. Lesson 1 calls it "highly desirable"; the relational model won on it ([04](../../research/04-models-that-lost-or-stayed-niche.md)). Object databases lost partly to "relink the world": changing a method on stored objects meant relinking every program ([04](../../research/04-models-that-lost-or-stayed-niche.md)). GemStone's answer is a class history: old instances keep the old class's methods until migrated ([07](../../research/07-code-inside-the-database.md), https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/11-ClassHistory.htm).
- **Schema-last leaves nothing to look up.** A 2025 study found much agent querying went to schema and statistics lookups (https://arxiv.org/abs/2509.00997); with no declared shape there is nothing to look up ([04](../../research/04-models-that-lost-or-stayed-niche.md), inference).
- **Niche languages lack examples, and the database can supply them.** Correct SPARQL rose from 3.3% to 75.75% with worked examples in the prompt (https://arxiv.org/html/2411.05521). See [Serving schema and worked examples to agents](../ideas/schema-and-examples-for-agents.md).
- **Graph speed must beat relational.** Graph databases must win on speed alone, and the 2024 paper cites relational systems beating them; [00](../../research/00-landscape-overview.md) presents index-free adjacency as the answer to many-hop queries (vendor page). The two files disagree; see [Neo4j](../systems/neo4j.md).
- **Summary** ([04](../../research/04-models-that-lost-or-stayed-niche.md)):

| System | Strength | What pays for it | Weakness |
|---|---|---|---|
| IMS | Predictable fast transactions, ordered queue | Storage layout fixed in advance; trees only | Programs break when storage is reorganised |
| CODASYL | Graph-shaped data, no workarounds | Programmer tracks position in every set | Hard to load, recover and reorganise |
| ObjectStore | Stored pointer costs one load instruction | Server cannot see inside pages; queries run on client | Code and stored layout change together |
| GemStone | Optimistic commits; Rc classes avoid false conflicts | Aborts grow with transaction length | Retry means abort and redo |
| XML stores | Schema-last flexibility | Complex schema language | Nothing for a reader to discover |
| Neo4j | Fast long traversals, short query language | Must beat relational systems on speed alone | Read committed; lost updates; duplicate `MERGE` |
| Triple stores | Merge facts from any source | Long identifiers, many self-joins | Scaling (Wikidata); 3.3% LLM accuracy unprompted |
| Datomic | Serial writes, compare-and-swap, history | One transactor bounds write throughput | Clause order is the query plan |
| TypeDB | Typed relations, constraints in the schema | Rewrite; dropped rule inference | Small ecosystem |
| Soufflé | Fast recursive rules | Batch only, fixed facts | No concurrent writers |

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf
- https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf
- https://www.ibm.com/history/information-management-system
- https://dl.acm.org/doi/10.1145/355611.362534
- https://www.broadcom.com/products/mainframe/databases/idms
- https://doi.org/10.1145/125223.125244
- https://research.isg-one.com/analyst-perspectives/progress-enables-knowledge-graphs-for-semantic-ai
- https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service/WDQS_backend_update/Backend_Replacement
- https://github.com/souffle-lang/souffle/
- https://github.com/google/mangle
- https://docs.datomic.com/reference/best.html
- https://arxiv.org/abs/2509.00997
- https://arxiv.org/html/2411.05521
