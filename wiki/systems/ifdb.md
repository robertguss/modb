# IFDB (MIT research system)

IFDB is a 2013 research version of [PostgreSQL](postgresql.md) from MIT in which every row carries an information-flow label, and every result carries the labels of what it read. It never shipped.

## What it is for

Keeping sensitive data from leaking out of a database-backed application, by tracking where each value came from and who may see it ([20](../../research/20-keeping-sensitive-data-from-agents.md)). It predates agents ([21](../../research/21-security-of-a-database-agents-use.md)).

## Core idea

*Information-flow control* inside the database: rows carry labels, and results are tainted by what they read (https://pmg.csail.mit.edu/pubs/schultz13__ifdb_decentralized_ifc-abstract.html). See [labels that follow data](../ideas/information-flow-labels.md).

## Strengths and what pays for each

- **Handles transactions and constraints "without introducing covert channels"** (https://pmg.csail.mit.edu/pubs/schultz13__ifdb_decentralized_ifc-abstract.html), unlike [row and column security](../ideas/row-and-column-security.md) in mainline PostgreSQL. *Paid for by* a check on every read and write, at about 1% throughput ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Caught real leaks.** Ported to two web applications, it caught real leaks; throughput equalled PostgreSQL on a real application and was "about 1% lower" on a TPC-C-like benchmark (https://dl.acm.org/doi/10.1145/2465351.2465357). *Paid for by* policies someone has to write ([21](../../research/21-security-of-a-database-agents-use.md)).

## Weaknesses

- **Never shipped** ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Research 21 found no adoption ([21](../../research/21-security-of-a-database-agents-use.md)).

## Worth borrowing

Row labels, the one database-side IFC design the research found ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Cost: every operator must define how labels combine, and side channels must be designed out from the start.

Research 21 would extend them with "written by which agent, from which input". Cost: labels must survive joins and travel with results ([21](../../research/21-security-of-a-database-agents-use.md)). See [the lethal trifecta inside a shared database](../ideas/lethal-trifecta-in-a-shared-database.md).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- https://pmg.csail.mit.edu/pubs/schultz13__ifdb_decentralized_ifc-abstract.html
- https://dl.acm.org/doi/10.1145/2465351.2465357
