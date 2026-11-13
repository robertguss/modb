# Set-at-a-time queries and data independence

A set-at-a-time query says *what* result is wanted, and the database's optimiser decides how to fetch it. Data independence is what that buys: programs keep working when the way data is stored changes.

## What it is

- **Data independence.** Codd's 1970 paper starts from it: programs should keep working when the way data is stored changes ([01](../../research/01-relational-and-transactional.md), https://dl.acm.org/doi/pdf/10.1145/362384.362685).
- **Declarative queries.** A relational database answers questions in a declarative language, SQL ([01](../../research/01-relational-and-transactional.md)).
- **The opposite is record-at-a-time.** In IMS's DL/1 the program fetches one record per call ("get next", "get next within parent") and decides where to go next, writing the query plan by hand. CODASYL programs move "currency indicators", markers of where they currently are, until they reach the record they want ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf).

## The problem it solves

- **Programs that survive storage changes.** "One cannot freely change IMS storage organizations ... because there is no guarantee that the DL/1 programs will continue to run" (2005 paper, Lessons 2 and 3). Lesson 1 calls data independence "highly desirable"; the relational model won on it ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Better plans than hand-written ones.** Lesson 4: record-at-a-time "forces the programmer to do manual query optimization, and this is often hard". Lesson 10: "query optimizers can beat all but the best record-at-a-time DBMS application programmers" ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **For agents.** Agents write loops cheaply, so the cost of hand-written navigation falls. The brittleness does not: an agent with no memory of why a loop assumes a layout breaks it at the next reorganisation. Holding many position markers in mind is what fails in a fresh context ([04](../../research/04-models-that-lost-or-stayed-niche.md), inference).

## What it costs

- **An optimiser** ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Skipping the optimiser leaves query order to the writer.** Datomic's query language is declarative Datalog, but `:where` clauses "are executed in order", so the writer must put "the most selective clauses first" (https://docs.datomic.com/reference/best.html). That is manual query optimisation again, in a declarative language ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Predicate locks proved too hard.** System R's locking began with predicate locks (locking a condition, even when no row matches), which proved too hard and were dropped ([01](../../research/01-relational-and-transactional.md), https://web.stanford.edu/class/cs245/readings/system-r-history-evaluation.pdf).

## Systems that use it

- [PostgreSQL](../systems/postgresql.md) and the other relational databases: SQL with an optimiser ([01](../../research/01-relational-and-transactional.md)).
- [Datomic](../systems/datomic.md): declarative Datalog, but with no clause-reordering optimiser ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- [Neo4j](../systems/neo4j.md): a short declarative language, Cypher, over storage that keeps edges as pointers "as in CODASYL" ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf).

## Sources

- [01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- https://dl.acm.org/doi/pdf/10.1145/362384.362685
- https://web.stanford.edu/class/cs245/readings/system-r-history-evaluation.pdf
- https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf
- https://db.cs.cmu.edu/papers/2024/whatgoesaround-sigmodrec2024.pdf
- https://docs.datomic.com/reference/best.html
