# Multi-version snapshots

Each write makes a new version of a row instead of overwriting it, and each reader sees a **snapshot**: the committed state at one moment. The usual name is multi-version concurrency control (MVCC).

## What it is

- Each write makes a new version of the row. Each reader sees the committed state at one moment, so readers never wait for writers ([research 01](../../research/01-relational-and-transactional.md); [PG MVCC](https://www.postgresql.org/docs/current/mvcc-intro.html)).
- Its alternative is [locks held until commit](locks-held-until-commit.md) (two-phase locking), where readers block writers and writers block readers ([research 01](../../research/01-relational-and-transactional.md)).
- On its own, MVCC gives **snapshot isolation** (SI). SI forbids most anomalies but allows **write skew**: two transactions each read x and y, each check that x + y stays positive, each write a different one, and both commit ([Berenson et al., 1995](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf)). True serializability needs more, such as PostgreSQL's SSI ([research 01](../../research/01-relational-and-transactional.md)).
- In PostgreSQL it grew out of time travel. Berkeley POSTGRES never overwrote rows; when time travel was dropped in 6.2, the no-overwrite storage survived as multi-version reads ([6.3 manual](https://www.postgresql.org/docs/6.3/c0503.htm); [Pachot](https://dev.to/franckpachot/postgresql-multi-version-from-time-travel-to-concurrency-control-b5)).

## The problem it solves

- Concurrent transactions must not interfere, and locking makes readers and writers wait for each other. MVCC "reduces lock contention" ([PG docs](https://www.postgresql.org/docs/current/mvcc-intro.html)).
- Reads can be long without blocking writes. Spanner's read-only transactions take no locks and never abort ([concurrency control](https://docs.cloud.google.com/spanner/docs/concurrency-control)).
- Reads against a frozen value while writes continue. Datomic offers this for any past moment, at the cost of a single writer ([research 05](../../research/05-databases-that-keep-history.md)).
- Agents may need a much larger form of it. The Berkeley agent paper asks for "multi-world isolation", forks from many agents that reconcile with each other, and calls it "MVCC on steroids" ([arXiv 2509.00997](https://arxiv.org/html/2509.00997v2)). See [branches that reconcile with each other](branches-that-reconcile-with-each-other.md).

## What it costs

- **Old versions must live somewhere until nobody can see them.** Where each system keeps them decides how long transactions fail ([research 01](../../research/01-relational-and-transactional.md)):

| System | Where old versions live | Who cleans up | What a long transaction does |
|---|---|---|---|
| PostgreSQL | In the table itself | VACUUM | Stops cleanup in every table; bloat; ID-wraparound risk |
| InnoDB | Undo log | Purge | History list grows, even for read-only transactions |
| Oracle | Circular undo segments | Overwritten when space runs out | The long *reader* fails with ORA-01555 "snapshot too old" |
| SQLite (WAL mode) | Write-ahead log file | Checkpoint | WAL file keeps growing ("checkpoint starvation") |

- **The oldest reader holds up cleanup** ([research 01](../../research/01-relational-and-transactional.md)).
- **Snapshot isolation is not serializability.** Write skew passes unless the engine adds checks, which cost false aborts and retries ([research 01](../../research/01-relational-and-transactional.md)).
- **Optimistic snapshot transactions abort.** FoundationDB reads a snapshot and rejects a transaction at commit if someone changed what it read; the client retries ([FoundationDB paper](https://www.foundationdb.org/files/fdb-paper.pdf)).
- **Second copies cost pages.** HyPer ran analytics on an operating-system copy-on-write snapshot, paying for pages copied as OLTP writes; its group later used MVCC instead (seen only in a review) ([VLDB 2011](https://vldb.org/pvldb/vol4/p1367-funke.pdf); [review](http://muratbuffalo.blogspot.com/2022/08/fast-serializable-multi-version.html)).

## Systems that use it

- [PostgreSQL](../systems/postgresql.md), [Oracle Database](../systems/oracle.md) and [MySQL (InnoDB)](../systems/mysql.md) all use it ([PG MVCC](https://www.postgresql.org/docs/current/mvcc-intro.html); [Oracle concepts](https://docs.oracle.com/en/database/oracle/oracle-database/18/cncpt/data-concurrency-and-consistency.html); [InnoDB consistent read](https://dev.mysql.com/doc/refman/8.4/en/innodb-consistent-read.html)).
- [SQLite](../systems/sqlite.md) in WAL mode lets readers run alongside its single writer ([wal.html](https://sqlite.org/wal.html)). Turso's rewrite adds concurrent writers through MVCC, started with `BEGIN CONCURRENT` ([Turso docs](https://docs.turso.tech/tursodb/concurrent-writes)).
- [Spanner](../systems/spanner.md): lock-free read-only transactions that never abort ([research 01](../../research/01-relational-and-transactional.md)).
- [CockroachDB](../systems/cockroachdb.md): a long transaction whose reads are overwritten must "refresh" and may fail ([retry reference](https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference)).
- [TypeDB](../systems/typedb.md): transactions are ACID "up to snapshot isolation" ([research 04](../../research/04-models-that-lost-or-stayed-niche.md)).
- [FoundationDB](../systems/foundationdb.md): snapshot reads with optimistic checks at commit ([FoundationDB paper](https://www.foundationdb.org/files/fdb-paper.pdf)).

## Cannot be combined with

- **Transactions held open without limit.** The oldest open snapshot either stops cleanup (PostgreSQL, InnoDB, SQLite) or breaks the reader (Oracle) ([research 01](../../research/01-relational-and-transactional.md)). The fixes are time limits; see [long transactions and time limits](transaction-time-limits.md).
- **Write-skew-free results without extra checks.** Plain snapshots allow write skew ([research 01](../../research/01-relational-and-transactional.md)).

## Disagreements

- **Turso's concurrent writes.** Research 00 says Turso's MVCC concurrent writes are in beta ([v0.5](https://turso.tech/blog/turso-0.5.0)). Research 09 says Turso supports concurrent writers via `BEGIN CONCURRENT`, with no beta caveat, and that schema changes are not allowed inside them ([docs](https://docs.turso.tech/tursodb/concurrent-writes)).
- **Whether agents really hold transactions open.** Research 01 found no study and marks its reasoning as inference. Research 08 and 09 cite a 2026 workshop paper saying agents hold transactions open while waiting for the model ([SAO workshop](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- Primary links are given inline above.
