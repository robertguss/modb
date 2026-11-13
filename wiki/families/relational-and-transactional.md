# Relational and transactional databases

Databases that store data as tables, answer questions in a declarative language (SQL), and group reads and writes into **transactions**: units that succeed or fail as a whole. This family covers the row stores in wide use and the ones spread over many machines.

## What they are for

- **Data independence.** Codd's 1970 paper starts from the idea that programs should keep working when the way data is stored changes ([Codd, CACM 1970](https://dl.acm.org/doi/pdf/10.1145/362384.362685)).
- **General transactional work with many concurrent users** ([PG docs](https://www.postgresql.org/docs/current/mvcc-intro.html)).
- **The same model across many machines.** Spanner (2012) and CockroachDB spread it over many servers ([Spanner, OSDI 2012](https://www.usenix.org/system/files/conference/osdi12/osdi12-final-16.pdf)).
- **The 2024 to 2026 wave is PostgreSQL consolidation** (see Members below) ([Pavlo, Jan 2026](https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html)).

## Members

- [PostgreSQL](../systems/postgresql.md): open-source row store with snapshots kept in the table; true serializability through SSI; transactional DDL.
- [Oracle Database](../systems/oracle.md): commercial row store with snapshots from circular undo; its "serializable" is snapshot isolation.
- [MySQL (InnoDB)](../systems/mysql.md): row store with snapshots in an undo log and next-key locks; its repeatable read loses updates.
- [SQLite](../systems/sqlite.md): embedded library with one writer at a time and exhaustive testing.
- [Spanner](../systems/spanner.md): Google's globally distributed database; external consistency paid for with synchronised clocks.
- [CockroachDB](../systems/cockroachdb.md): distributed SQL, serializable by default, schema changes in background stages.

Mentioned in the sources without a page of their own:

- System R: IBM's 1970s system that produced SQL and three isolation levels; its predicate locks proved too hard ([System R history](https://web.stanford.edu/class/cs245/readings/system-r-history-evaluation.pdf)).
- Ingres: the Berkeley system whose leader began POSTGRES in 1986 ([PG history](https://www.postgresql.org/docs/current/history.html)).
- POSTGRES and Postgres95: PostgreSQL's forerunners; SQL arrived with Postgres95 in 1994 ([PG history](https://www.postgresql.org/docs/current/history.html)).
- F1: Google's system on Spanner that introduced schema changes in delete-only and write-only stages ([F1, VLDB 2013](https://www.vldb.org/pvldb/vol6/p1045-rae.pdf)).
- MariaDB: a MySQL relative whose system-versioned tables need a separate `DELETE HISTORY` privilege ([MariaDB docs](https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/system-versioned-tables)).
- MariaDB Galera Cluster: Jepsen found lost updates "even in healthy clusters", "weaker than Read Uncommitted" ([Jepsen](https://jepsen.io/analyses/mariadb-galera-cluster-12.1.2)).
- Amazon RDS for PostgreSQL: Jepsen found snapshot-isolation violations ("Long Fork") even when healthy ([Jepsen, 2025-04-29](https://jepsen.io/analyses/amazon-rds-for-postgresql-17.4)).
- Microsoft SQL Server: its SQL:2011 history tables cannot be deleted from while versioning is on ([Microsoft docs](https://learn.microsoft.com/en-us/sql/relational-databases/tables/modifying-data-in-a-system-versioned-temporal-table?view=sql-server-ver15)).
- Turso: a Rust rewrite of SQLite with concurrent writers; research 00 says beta, research 09 gives no beta caveat ([v0.5](https://turso.tech/blog/turso-0.5.0); [docs](https://docs.turso.tech/tursodb/concurrent-writes)).
- Multigres: one of three competing distributed-Postgres projects (Pavlo).
- Neki: another of the three (Pavlo).
- PgDog: the third (Pavlo).
- Crunchy Data: a PostgreSQL company Snowflake bought for $250M (Pavlo).

## Shared tradeoffs

- **Two ways to keep transactions apart** ([research 01](../../research/01-relational-and-transactional.md)):
  - [Locks held until commit](../ideas/locks-held-until-commit.md) (two-phase locking): readers block writers and writers block readers.
  - [Multi-version snapshots](../ideas/multi-version-snapshots.md) (MVCC): readers never wait, but old versions must live somewhere until nobody can see them. PostgreSQL, Oracle and InnoDB all use it.
- **Serializability is always paid for.** The price is blocking (locks), aborts (optimistic checks) or clock waits (Spanner). Weaker levels move the cost into application bugs ([research 01](../../research/01-relational-and-transactional.md)). See [serializable by default](../ideas/serializable-by-default.md).
- **The name of an isolation level is a weak promise.** Oracle's "serializable" is snapshot isolation; MySQL's repeatable read loses updates ([Hermitage](https://github.com/ept/hermitage/blob/master/oracle.md); [Jepsen MySQL](https://jepsen.io/analyses/mysql-8.0.34)). Only a checker shows the guarantee. See [guarantees checked by a tool](../ideas/guarantees-checked-by-a-tool.md).
- **The oldest open snapshot blocks cleanup or breaks readers.** None of the engines treats a minute-long transaction as normal; each fails in its own way ([research 01](../../research/01-relational-and-transactional.md)). See [long transactions and time limits](../ideas/transaction-time-limits.md). Research 01 found no study of agents holding transactions open; research 08 and 09 cite a 2026 workshop paper saying they do ([SAO workshop](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf)).
- **Schema changes fight running transactions.** Exclusive locks (PostgreSQL), implicit commits (MySQL, Oracle) or non-atomic stages (F1, CockroachDB) ([research 01](../../research/01-relational-and-transactional.md)). See [staged schema changes](../ideas/staged-schema-changes.md).
- **Retries are left outside the database.** Serializable engines return an error, and the application replays the transaction ([research 01](../../research/01-relational-and-transactional.md)).
- **Bugs survive decades of use.** SQLite's WAL-reset corruption bug lived from 2010 to 2026 ([wal.html](https://sqlite.org/wal.html)). Jepsen keeps finding that documentation promises more than the system gives ([research 08](../../research/08-correctness-first-databases.md)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- Primary links are given inline above.
