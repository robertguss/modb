Research run on 2026-11-13 by a subagent using Exa, for the ticket [Models that lost or stayed niche](../issues/04-models-that-lost-or-stayed-niche.md). Each "For an agent" paragraph is the researcher's inference unless it carries a source. Nothing was checked a second time.

# Models that lost to relational, or stayed niche

Two surveys anchor this note, both by relational partisans. The 2005 review gives numbered lessons from each era https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf. The 2024 sequel concludes that non-relational systems "are either a niche market or are fast becoming SQL/RM systems" https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf.

The 2005 paper's Lesson 9 says debates "are usually settled by the elephants of the marketplace, and often for reasons that have little to do with the technology". Adoption is not a measure for this effort, so standards and vendor size do not count. The question for each family is which *technical* reasons survive.

## 1. Hierarchical: IMS

- **For and when.** IBM built it to track bills of material for the Apollo program; it printed its first "READY" on 1968-08-14 https://www.ibm.com/history/information-management-system.
- **Core idea.** Records form trees. Every record has a key made of its ancestors' keys, and that key defines one depth-first order. The language, DL/1, walks that order with commands such as "get next" and "get next within parent" (2005 paper).
- **Strengths, and what pays.** Fast, predictable transactions, "billions ... each day" (IBM, vendor claim) https://www.ibm.com/products/ims. Transactions can be queued and run in time order, which suits banks (IBM history page). What pays: the storage layout is fixed in advance, and some layouts forbid some commands (2005 paper).
- **Weaknesses.** Non-tree data needs "logical databases" grafted from trees, with "many restrictions". And "one cannot freely change IMS storage organizations ... because there is no guarantee that the DL/1 programs will continue to run" (2005 paper, Lessons 2 and 3).
- **Many clients.** A transaction manager queues and orders work.
- **For an agent.** DL/1 is *record-at-a-time*: the program fetches one record per call and decides where to go next, writing the query plan by hand. Lesson 4: this "forces the programmer to do manual query optimization, and this is often hard". Agents write loops cheaply, so that cost falls. The brittleness does not: an agent with no memory of why a loop assumes a layout breaks it at the next reorganisation.

## 2. Network: CODASYL

- **For and when.** A 1970s standard that let one record have several owners, so data no longer had to be a tree. Its designer called the programmer a "navigator" in his 1973 Turing lecture https://dl.acm.org/doi/10.1145/355611.362534.
- **Core idea.** Records linked by named "sets" (owner-to-member pointer chains). The program moves "currency indicators", markers of where it currently is, until it reaches the record it wants (2005 paper).
- **Strengths, and what pays.** Graph-shaped data with no workarounds. Paid for by complexity: the programmer tracks a position for every record type and set, "a wall map ... decorated with various colored pins". Lessons 5 and 6: more flexible than trees, harder to load and recover (2005 paper).
- **Weaknesses.** The same loss of *data independence*, meaning programs keep working when storage or schema is reorganised. Lesson 1 calls it "highly desirable"; the relational model won on it.
- **Still alive.** Broadcom still ships IDMS 19.0 https://www.broadcom.com/products/mainframe/databases/idms, a "testament to the 'stickiness' of data" (2024 paper).
- **For an agent.** Holding many pins in mind is what fails in a fresh context. Lesson 10 still applies: "query optimizers can beat all but the best record-at-a-time DBMS application programmers".

## 3. Object databases: GemStone, ObjectStore

- **For and when.** Mid-1980s, aimed at engineering and design software. The goal was to store programming-language objects directly instead of writing load and unload code (2005 paper).
- **ObjectStore's idea.** C++ objects are stored in their in-memory format, and a pointer to one compiles to "a single 'load' instruction". An unloaded page is marked no-access; the fault fetches it and its pointers are *swizzled* (rewritten from disk addresses to memory addresses). The server ships pages and does two-phase locking (locks are held until the transaction ends), but "has no knowledge of the contents of a page" https://doi.org/10.1145/125223.125244.
- **GemStone's idea.** Persistent Smalltalk objects with *optimistic* concurrency: "read and write objects as if you were the only user", and the server checks for conflicts only at commit. A failed commit cannot be retried as is; "you must abort the transaction in order to get a new view". Its *reduced-conflict* (Rc) classes, such as counters and bags, replay their changes at commit so that two sessions adding to the same bag do not conflict https://downloads.gemtalksystems.com/docs/GemStone64/3.6.x/GS64-ProgGuide-3.6.pdf.
- **Strengths, and what pays.** No mismatch between program and storage, near-memory speed. ObjectStore paid by pushing query work to the client. GemStone paid with aborts that grow with transaction length.
- **Why they lost** (2005 paper): no leverage, since saving a load program "is not a major service"; no standards; and "relink the world": changing a method on stored objects meant relinking every program that used it.
- **For an agent.** Two reasons are market reasons. The third, schema and code changing together, is real and sharper for agents, which change code often. Mo's typed live upgrades already face it.

## 4. XML stores

- **For and when.** Late 1990s and 2000s. Documents with optional structure, queried with XQuery and checked with XMLSchema (2005 paper).
- **Core idea.** *Schema-last*: store the data first and describe its structure later, if ever.
- **Why they stayed niche.** The 2005 paper predicted XMLSchema would fail from "excessive complexity" and called schema-last "probably a niche market" (Lesson 16). JSON then overtook XML (2024 paper). MarkLogic, the best-known XML store, now sells itself as multi-model and was bought by Progress in 2023 for $355 million https://research.isg-one.com/analyst-perspectives/progress-enables-knowledge-graphs-for-semantic-ai.
- **For an agent.** Schema-last looks attractive for loosely structured agent output. But a 2025 study found much agent querying went to schema and statistics lookups https://arxiv.org/abs/2509.00997. With no declared shape there is nothing to look up. The reason still holds.

## 5. Property graphs: Neo4j

- **For and when.** Relationship-heavy data: social links, fraud rings, knowledge graphs.
- **Core idea.** Nodes and relationships, both with key-value properties. Neo4j stores edges as pointers, "as in CODASYL", which suits "traversing long edge chains" (2024 paper).
- **Strengths, and what pays.** Fast multi-hop traversal and a short query language, Cypher. Paid for by having to win on speed alone, and the 2024 paper cites relational systems beating graph databases, DuckDB's SQL/PGQ "by up to 10×". SQL:2023 added graph queries; GQL became ISO/IEC 39075 in April 2024 https://www.iso.org/standard/76120.html.
- **Many clients.** The default is *read committed*: a transaction sees only committed data but may see it change between reads. Writes take locks; deadlocks are detected and one transaction ends with a transient error to retry. Lost updates can happen "when a query does not have a direct dependency on the property being read" https://neo4j.com/docs/operations-manual/current/database-internals/concurrent-data-access/. `MERGE` (find-or-create) can create duplicates under concurrency without a uniqueness constraint; Neo4j recommends constraints https://neo4j.com/docs/cypher-manual/current/clauses/merge/.
- **Status.** Over $200M annual recurring revenue (vendor claim, 2024-11-19) https://neo4j.com/press-releases/neo4j-revenue-milestone-2024/. Graphs are a popular agent-memory store: Graphiti keeps facts in Neo4j with validity intervals on every edge https://neo4j.com/blog/developer/graphiti-knowledge-graph-memory/.
- **For an agent.** In one benchmark, the best model given only the schema wrote correct SQL 47% of the time and correct Cypher 34% https://arxiv.org/abs/2411.05521. The bigger risk is weak isolation. Agents retry and run in parallel, and a `MERGE` duplicate is a quiet error nobody notices.

## 6. Triple stores (RDF and SPARQL)

- **For and when.** The semantic web: data from many sources joined through shared global identifiers (URIs).
- **Core idea.** Every fact is a *triple*: subject, predicate, object. The 2024 paper treats triple stores as a subset of property graphs.
- **Strengths, and what pays.** Any source's facts merge into one graph without a schema agreed in advance. Paid for by long identifiers, many self-joins and hard scaling.
- **Weaknesses.** The largest public triple store shows the scaling cost. The Wikidata Query Service runs on Blazegraph, which "ceased development in 2016" and "is unable to scale to meet the growth targets of Wikidata", with SLO incidents about once a week. Wikimedia split the graph in two in 2025 to buy time and now recommends QLever as the replacement https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service/WDQS_backend_update/Backend_Replacement.
- **For an agent.** The clearest data point here. In the same benchmark the best model wrote correct SPARQL 3.3% of the time, against 47% for SQL. The authors tie this to training data: 6,000 SPARQL posts on Stack Overflow against 673,000 for SQL. With similar worked examples in each prompt, SPARQL rose to 75.75% https://arxiv.org/html/2411.05521. The reason a language stays niche has changed: once few people learned it; now few examples exist, and the database can supply them.

## 7. Logic and Datalog: Datomic, TypeDB, Soufflé

*Datalog* is a query language made of rules ("X is an ancestor of Y if ..."), which may call themselves recursively. Larger rules are built from smaller ones.

- **Datomic.** Its query language is Datalog over immutable facts. All writes go through one *transactor*, so writes are "fully serialized" and every transaction does a compare-and-swap on the log's root https://docs.datomic.com/transactions/acid.html. `:db/cas` aborts a transaction if a value changed underneath it, and transaction functions run on the transactor https://docs.datomic.com/transactions/transaction-functions.html. The cost: `:where` clauses "are executed in order", so the writer must put "the most selective clauses first" https://docs.datomic.com/reference/best.html. That is manual query optimisation again, in a declarative language. Datomic binaries became free under Apache 2.0 in April 2023, but the source is not open https://forum.datomic.com/t/datomic-is-now-free/2208.
- **TypeDB.** A typed entity-relation-attribute model. Version 3.0 (2024-12-20), rewritten in Rust, replaced rule-based inference with functions, which are "easier to reason about" https://github.com/typedb/typedb/releases/tag/3.0.0. Under 2.x an "inference switch" changed what a query returned; 3.0 makes the caller ask for inferred results explicitly https://typedb.com/fundamentals/functions. Transactions are ACID "up to snapshot isolation", where each transaction reads one consistent snapshot.
- **Soufflé.** Datalog compiled into parallel C++, built for static program analysis such as points-to and taint https://github.com/souffle-lang/souffle/. It is a batch engine with no concurrent writers. Google's Mangle (2025) is a similar Datalog extension https://github.com/google/mangle.
- **Why niche.** Datalog wins at recursive rules over fixed facts, as in program analysis. It lacks training data, tooling and, in Datomic, a clause-reordering optimiser.
- **For an agent.** Small composable rules suit agents; hidden inference does not, as TypeDB's retreat shows. Datomic's single writer plus compare-and-swap is close to the map's settled one-operation-at-a-time rule.

## Summary table

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

## Ideas worth borrowing

- **Set-at-a-time queries with an optimiser** (Lessons 7 and 10): code that survives storage changes. Cost: an optimiser; Datomic shows skipping one leaves query order to the writer.
- **Rc-style semantic conflict classes** (GemStone): counters and bags declare how concurrent changes combine, a mechanism for the overview's "merging by intent". Cost: merge semantics written and proved per type.
- **Single writer plus compare-and-swap** (Datomic). Matches coordination-first. Cost: one writer bounds write throughput.
- **Examples and schema served to the agent** (SM3). A new query language starts where SPARQL does; examples lifted it from 3.3% to 76%. Cost: keeping examples correct as the schema grows.
- **Uniqueness by declared constraint, not find-or-create** (Neo4j `MERGE`). Cost: schema comes first.
- **Explicit inference** (TypeDB 3.0): derived facts asked for by name. Cost: longer queries.

## What I could not confirm

- IMS's own locking and isolation; I read only IBM marketing and the 2005 paper.
- ObjectStore's and GemStone's current owners and status; I did not search for them.
- TypeDB's adoption or the company's state after 3.0.
- Whether the SM3 figures carry over to today's frontier models; the benchmark used 2024 models (Llama 3, GPT-3.5 class).
- DuckDB's "up to 10×" over a graph database; I did not read the cited study.
- Neo4j's revenue and IBM's transaction volumes are vendor claims.
- Whether QLever is now in production at Wikidata; the recommendation page carries no date I could see.
