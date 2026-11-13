# Locks held until commit

A transaction takes locks on what it reads and writes and holds them until it ends, so no other transaction can change that data in between. The usual name is two-phase locking.

## What it is

- A transaction takes locks as it reads and writes and holds them until it ends. Readers block writers and writers block readers. This was System R's design in the 1970s ([research 01](../../research/01-relational-and-transactional.md)).
- System R began with **predicate locks**: locking a condition, such as "employees in Evanston", even when no row matches. They proved too hard ([System R history, 1981](https://web.stanford.edu/class/cs245/readings/system-r-history-evaluation.pdf)).
- What gets locked varies: a row, a range of an index, a page, or a whole table (see Systems below).
- Its main alternative is [multi-version snapshots](multi-version-snapshots.md), where readers never wait. Another is [optimistic concurrency](optimistic-concurrency.md), which takes no locks and checks at commit.

## The problem it solves

- It stops concurrent transactions from interfering, and is one of three ways to pay for serializability: blocking (locks), aborts (optimistic checks), or clock waits (Spanner) ([research 01](../../research/01-relational-and-transactional.md)).
- It gives strict guarantees in simple engines. Berkeley DB is strict ACID by default, paid for by locks and a log that every write goes through ([What is Berkeley DB](https://web.stanford.edu/class/cs276a/projects/docs/berkeleydb/ref/intro/dbis.html)).

## What it costs

- **Waiting.** Readers and writers block each other ([research 01](../../research/01-relational-and-transactional.md)). InnoDB's next-key locks (an index record plus the gap before it) make other sessions' inserts into a scanned range wait ([InnoDB locking](https://dev.mysql.com/doc/refman/26.10/en/innodb-locking.html)). In Snowflake, `UPDATE`, `DELETE` and `MERGE` block each other and wait up to `LOCK_TIMEOUT` ([Snowflake transactions](https://docs.snowflake.com/en/sql-reference/transactions)).
- **Deadlocks.** A deadlock is two transactions each waiting for a lock the other holds. Systems must detect them and abort one, or prevent them:
  - Spanner uses **wound-wait**: an older transaction aborts a younger one holding a lock it needs; a younger one waits ([concurrency control](https://docs.cloud.google.com/spanner/docs/concurrency-control)).
  - Neo4j detects deadlocks and ends one transaction with a transient error to retry ([Neo4j](https://neo4j.com/docs/operations-manual/current/database-internals/concurrent-data-access/)).
  - Mnesia detects deadlocks and restarts the transaction, so "a transaction can be restarted any number of times and therefore the Fun shall not have any side effects" ([mnesia](https://www.erlang.org/doc/apps/mnesia/mnesia.html)).
- **Coarse locks block unrelated work.** Berkeley DB locks whole pages, so one writer blocks writers of other records on that page. The authors chose this to limit the states a page can be in during recovery, and later called it "problematic at times" ([AOSA](https://aosabook.org/en/v1/bdb.html)). Erlang's ETS tables give writes "exclusive access" to the whole table by default ([ets](https://www.erlang.org/doc/apps/stdlib/ets.html)).
- **Locks held long hurt everyone.** Spanner aborts a read-write transaction idle for 10 seconds "so that they don't hold on to locks indefinitely" ([transactions](https://docs.cloud.google.com/spanner/docs/transactions)). In MySQL, online DDL must wait for any transaction holding a metadata lock, so "a long running or inactive transaction ... can cause an online DDL operation to timeout" ([online DDL](https://dev.mysql.com/doc/refman/8.4/en/innodb-online-ddl-limitations.html)). In PostgreSQL, an `ALTER TABLE` waiting for its exclusive lock makes every later query on the table queue behind it ([Xata](https://xata.io/blog/migrations-and-exclusive-locks)).
- **The server may not know what it locks.** ObjectStore's server ships pages and does two-phase locking, but "has no knowledge of the contents of a page" ([ObjectStore, CACM](https://doi.org/10.1145/125223.125244)).
- **Locking under a weak level still loses updates.** Neo4j's default is read committed; writes take locks, yet lost updates can happen "when a query does not have a direct dependency on the property being read" ([Neo4j](https://neo4j.com/docs/operations-manual/current/database-internals/concurrent-data-access/)).

## Systems that use it

- [MySQL (InnoDB)](../systems/mysql.md): next-key locks; locking serializable ([research 01](../../research/01-relational-and-transactional.md)).
- [Spanner](../systems/spanner.md): locks in read-write transactions, with wound-wait. Its repeatable read level instead defers locks to commit and does not check reads ([research 01](../../research/01-relational-and-transactional.md)).
- [Snowflake](../systems/snowflake.md): locks on writing statements ([research 02](../../research/02-analytical-and-specialised.md)).
- [Berkeley DB](../systems/berkeley-db.md): page locks, deadlock detection, and an option to relax isolation ([research 03](../../research/03-key-value-document-distributed.md)).
- [RocksDB](../systems/rocksdb.md): offers a pessimistic (locking) transaction mode beside an optimistic one ([Transactions](https://github.com/meta/rocksdb/wiki/Transactions)).
- [Neo4j](../systems/neo4j.md): write locks with deadlock detection ([research 04](../../research/04-models-that-lost-or-stayed-niche.md)).
- [Mnesia](../systems/mnesia.md): a transaction is an Erlang function run under locks ([research 07](../../research/07-code-inside-the-database.md)).

## Cannot be combined with

- **Transactions held open for a long time**, such as an agent thinking between reads and writes. Every lock it holds blocks others until it ends; Spanner aborts such transactions after 10 idle seconds ([research 01](../../research/01-relational-and-transactional.md)). That agents do this is inference in research 01 and cited from a workshop paper in research 08 and 09 (see [long transactions and time limits](transaction-time-limits.md)).
- **Side effects inside a transaction that may be restarted after a deadlock.** Mnesia states the rule but the language does not enforce it, so a retried function that sends a message sends it twice ([research 07](../../research/07-code-inside-the-database.md)).

## Sources

- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- Primary links are given inline above.
