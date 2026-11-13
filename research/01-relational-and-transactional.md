# Relational and transactional databases

Research run on 2026-11-13 by a subagent using Exa. It goes deeper than [00-landscape-overview.md](00-landscape-overview.md) on one family, and deepest on transactions. Inferences are marked as mine.

## 1. What they are for, and where they came from

A relational database stores data as tables and answers questions in a declarative language (SQL). A **transaction** is a group of reads and writes that succeeds or fails as a whole.

- **The problem.** Codd's 1970 paper starts from "data independence": programs should keep working when the way data is stored changes ([Codd, CACM 1970](https://dl.acm.org/doi/pdf/10.1145/362384.362685)).
- **System R (IBM, 1970s)** proved the model could be built with full function. It produced SQL, and its locking design started with **predicate locks** (locking a condition such as "employees in Evanston", even when no row matches). That proved too hard, and it ended with locks at several granularities ([History and Evaluation of System R, 1981](https://web.stanford.edu/class/cs245/readings/system-r-history-evaluation.pdf)). It already offered three isolation levels, and recovery combined a log with "shadow pages", which cost the most performance.
- **Ingres to PostgreSQL.** POSTGRES began at Berkeley in 1986 under the leader of Ingres. SQL was added in 1994 (Postgres95), and it was renamed PostgreSQL in 1996 ([PG history](https://www.postgresql.org/docs/current/history.html)).
- **Oracle, MySQL (InnoDB) and SQLite** are the other row stores in wide use. **Spanner** (2012) and **CockroachDB** spread the same model over many machines ([Spanner, OSDI 2012](https://www.usenix.org/system/files/conference/osdi12/osdi12-final-16.pdf)).

## 2. The core idea underneath

There are two ways to stop concurrent transactions from interfering.

- **Locking (two-phase locking).** A transaction takes locks as it reads and writes and holds them until it ends. Readers block writers and writers block readers. This was System R's design.
- **Multi-version concurrency control (MVCC).** Each write makes a new version of the row. Each reader sees a **snapshot**: the committed state at one moment. Readers never wait for writers. PostgreSQL, Oracle and InnoDB all use it ([PG MVCC](https://www.postgresql.org/docs/current/mvcc-intro.html); [Oracle concepts](https://docs.oracle.com/en/database/oracle/oracle-database/18/cncpt/data-concurrency-and-consistency.html); [InnoDB consistent read](https://dev.mysql.com/doc/refman/8.4/en/innodb-consistent-read.html)).

Old versions have to live somewhere until nobody can see them. Where each system keeps them decides most of how it fails (section 4).

| System | Where old versions live | Who cleans up |
|---|---|---|
| PostgreSQL | In the table itself | VACUUM |
| InnoDB | Undo log | Purge |
| Oracle | Circular undo segments | Overwritten when space runs out |
| SQLite (WAL mode) | Write-ahead log file | Checkpoint |

## 3. Transactions in depth

### Isolation levels

An **isolation level** says which effects of concurrent transactions one transaction may see. SQL names four levels by the anomalies (wrong results) each forbids. The 1995 critique showed these definitions are ambiguous and miss **snapshot isolation** (SI) altogether ([Berenson et al.](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf)).

- SI forbids most anomalies but allows **write skew**. Two transactions each read x and y, each check that x + y stays positive, and each write a different one of the two. Both commit, and the rule is broken. The paper calls this "a generic and important type of concurrency" failure.

What each system's names actually mean:

| System | Default | Its "repeatable read" | Its "serializable" |
|---|---|---|---|
| PostgreSQL | Read committed | Snapshot isolation | True serializability (SSI) |
| Oracle | Read committed | Not offered | Snapshot isolation: allows write skew ([Hermitage](https://github.com/ept/hermitage/blob/master/oracle.md)) |
| MySQL/InnoDB | Repeatable read | Weaker than SI, see below | Locking |
| CockroachDB | Serializable | Not offered | Serializable; read committed is opt-in ([docs](https://docs.cockroachlabs.com/docs/stable/read-committed)) |
| Spanner | Serializable | Snapshot with optimistic locking ([docs](https://docs.cloud.google.com/spanner/docs/use-repeatable-read-isolation)) | Serializable, with external consistency |

Sources for PostgreSQL: [isolation docs](https://www.postgresql.org/docs/current/transaction-iso.html). For InnoDB: [isolation docs](https://dev.mysql.com/doc/refman/26.10/en/innodb-transaction-isolation-levels.html).

Jepsen tested these claims against running systems.

- **MySQL 8.0.34.** Repeatable read allows lost updates: "MySQL Repeatable Read transactions cannot safely read a value and then write it." The usual pattern of load, change and save "may find that MySQL silently discards those committed changes". AWS RDS MySQL "routinely" broke serializability ([Jepsen, 2023-12-19](https://jepsen.io/analyses/mysql-8.0.34)).
- **PostgreSQL 12.3.** Serializable let write skew through because of a bug in conflict detection. A fix followed ([Jepsen, 2020-06-12](https://jepsen.io/analyses/postgresql-12.3)).

The lesson: what an isolation level is called is a weak promise. Only a test that checks the guarantee tells you what it is.

### Locking against snapshots: what pays for serializability

- **PostgreSQL SSI** (Serializable Snapshot Isolation) runs transactions under SI. It tracks read-then-write dependencies between concurrent transactions and aborts one when an anomaly is *possible* ([Ports and Grittner, VLDB 2012](http://vldb.org/pvldb/vol5/p1850_danrkports_vldb2012.pdf)).
  - The price: false aborts, and every serializable transaction must be retried on SQLSTATE `40001` ([PG docs](https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html)).
- **InnoDB** prevents **phantoms** (rows that appear when the same query is run again) with **next-key locks**: a lock on an index record plus the gap before it. Other sessions cannot insert into the range scanned ([InnoDB locking](https://dev.mysql.com/doc/refman/26.10/en/innodb-locking.html)).
  - The price: inserts block, and deadlocks become more likely.
- **Spanner** locks in read-write transactions and avoids deadlock with **wound-wait**. An older transaction aborts ("wounds") a younger one that holds a lock it needs; a younger one waits ([concurrency control](https://docs.cloud.google.com/spanner/docs/concurrency-control)).
  - Read-only transactions take no locks and never abort.
  - The price is the clock. Each commit waits out TrueTime's uncertainty bound, "generally less than 10ms", kept small by GPS and atomic clocks. That buys **external consistency**: if T1 commits before T2 starts, T1's timestamp is smaller (OSDI paper).
- **Spanner's repeatable read** was announced in preview in 2025 and is now listed as generally available ([release notes](https://docs.cloud.google.com/spanner/docs/release-notes)). It defers locks to commit and does not check reads. Google says to switch only "after you have audited your transactions to ensure they are safe from write-skew" ([Google, vendor](https://medium.com/google-cloud/spanner-repeatable-read-isolation-14262ee60709)).
- **CockroachDB** defaults to serializable and pushes retries onto the client ([retry reference](https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference)). Read committed exists so that clients do not have to write retry loops.

The pattern across all of them: serializability is paid for with **blocking** (locks), **aborts** (optimistic checks), or **clock waits** (Spanner). The weaker levels move that cost into application bugs.

### A transaction that stays open for minutes

None of the engines treats this as a normal case. Each fails in its own way.

- **PostgreSQL.** VACUUM cannot remove any row version an open transaction might still see. The cut-off is the oldest snapshot anywhere in the cluster (the "xmin horizon"), so one idle session stops cleanup in every table ([routine vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html); [postgres-ai howto](https://github.com/postgres-ai/postgres-howtos/blob/main/0030_how_to_deal_with_long-running_transactions_oltp.md)).
  - Tables bloat and queries slow down.
  - Freezing old transaction IDs, needed before the 32-bit ID counter wraps, also stalls. Wraparound is described as "catastrophic data loss".
  - The fixes are timeouts: `idle_in_transaction_session_timeout`, and `transaction_timeout` since PostgreSQL 17.
- **InnoDB.** Purge cannot free undo logs that an open snapshot still needs, so the "history list length" grows. This happens "even for transactions that are read only", and queries and shutdown get slower ([purge docs](https://dev.mysql.com/doc/refman/8.4/en/innodb-purge-configuration.html)).
- **Oracle** does the reverse: undo is overwritten in a circle. The *long reader* fails with ORA-01555 "snapshot too old" when the undo it needs is gone ([Oracle undo](https://docs.oracle.com/cd/B19306_01/server.102/b14231/undo.htm)).
- **SQLite.** An open reader stops a checkpoint from resetting the write-ahead log (WAL), so the WAL file keeps growing ("checkpoint starvation"). There is only ever one writer ([wal.html](https://sqlite.org/wal.html)).
- **Spanner** may abort a read-write transaction that has issued no read for 10 seconds "so that they don't hold on to locks indefinitely". Clients send `SELECT 1` to keep it alive ([transactions](https://docs.cloud.google.com/spanner/docs/transactions)).
- **CockroachDB.** A long transaction whose reads are overwritten is forced to "refresh" and may fail with a retry error (retry reference). Old versions are kept only for a set garbage-collection window.

### Changing the schema of a live database

DDL (data definition language: `CREATE`, `ALTER`, `DROP`) changes the shape of tables while other transactions use them.

- **PostgreSQL** runs DDL inside transactions, so a migration can be rolled back ([PG wiki](https://wiki.postgresql.org/wiki/Transactional_DDL_in_PostgreSQL:_A_Competitive_Analysis)).
  - The price: most `ALTER TABLE` forms need an exclusive lock that even blocks plain `SELECT`. While the `ALTER` waits behind a long transaction, every later query on that table queues behind the `ALTER` ([Xata](https://xata.io/blog/migrations-and-exclusive-locks)).
  - The usual guard is a short `lock_timeout` and retrying by hand. PostgreSQL has no automatic retry.
  - `CREATE INDEX CONCURRENTLY` avoids the lock but cannot run inside a transaction ([docs](https://www.postgresql.org/docs/current/sql-createindex.html)).
- **MySQL** DDL "implicitly end[s] any transaction", and "atomic DDL is not transactional DDL" ([implicit commit](https://dev.mysql.com/doc/refman/8.4/en/implicit-commit.html); [atomic DDL](https://dev.mysql.com/doc/refman/8.4/en/atomic-ddl.html)).
  - `ALGORITHM=INSTANT` changes only metadata. But every online DDL must still wait for transactions that hold a metadata lock, so "a long running or inactive transaction ... can cause an online DDL operation to timeout" ([online DDL](https://dev.mysql.com/doc/refman/8.4/en/innodb-online-ddl-limitations.html)).
- **Oracle** commits any open transaction before DDL. Its Edition-Based Redefinition lets two versions of schema objects exist side by side (PG wiki, quoting Oracle).
- **F1 on Spanner** solved changes across many servers. It moves each new element through internal states, **delete-only** and then **write-only**, before it can be read. Every server is at most one state apart, so no server corrupts data that another server's schema expects ([F1, VLDB 2013](https://www.vldb.org/pvldb/vol6/p1045-rae.pdf)).
  - CockroachDB adopted this. Schema changes run as background jobs that hold no locks on table data and can be paused or cancelled ([online schema changes](https://docs.cockroachlabs.com/docs/stable/online-schema-changes)).
  - The price: a change is no longer one atomic step. DDL in a multi-statement transaction "can fail while other statements succeed", and a backfill can get stuck retrying if it runs past the garbage-collection window ([issue #105632](https://github.com/cockroachdb/cockroach/issues/105632)).

## 4. Weaknesses and well-known failures

- **Names hide anomalies.** Oracle's "serializable" is SI, and MySQL's repeatable read loses updates (above).
- **Old versions pile up.** Each engine's cleanup is stopped, or its readers broken, by the oldest open snapshot.
- **Bugs survive decades of use.** SQLite's WAL-reset bug could corrupt a database when two connections wrote or checkpointed "at the same instant". It is "likely present" in every version from 3.7.0 (2010) to 3.51.2 and was fixed in 3.51.3 (2026-03-13) ([wal.html §11](https://sqlite.org/wal.html)). It was found by a developer, and an independent reproducer came only in August 2026.
- **Retries are left to the client.** Every serializable engine returns an error and expects the application to replay the whole transaction.

## 5. What an AI agent would struggle with

My inference, drawing on the sources above.

1. **Thinking inside a transaction.** An agent that opens a transaction, then calls a model for 30 seconds before writing, is exactly the long transaction that every engine above punishes. It stalls VACUUM or purge, gets aborted for being idle by Spanner, or blocks a migration queue.
2. **Retrying correctly.** After a `40001` error the agent must replay the *whole* transaction, re-reading data. A retry wrapped around only the last statement is wrong. If the agent's reasoning depended on what it read, the retry has to re-run the reasoning too.
3. **Knowing what the level really guarantees.** An agent trusting the name "repeatable read" on MySQL will lose updates. The guarantee lives in Jepsen reports, not in the schema.
4. **Migrations.** The safe pattern, a short `lock_timeout` plus retries and the expand/contract steps, is folklore spread across blogs. The database does not enforce it.

## Summary table

| System | Strength | What pays for it | Weakness |
|---|---|---|---|
| System R | Declarative queries, isolation levels, log-based recovery | Shadow-page cost; predicate locks dropped as too hard | Locking: readers and writers block each other |
| PostgreSQL | True serializability via SSI; transactional DDL | Aborts and false positives; exclusive DDL locks | One long transaction stops VACUUM in every table |
| Oracle | Readers never block; undo-based snapshots | Circular undo that gets overwritten | ORA-01555 on long readers; "serializable" allows write skew |
| MySQL/InnoDB | No phantoms at the default level; instant ADD COLUMN | Gap locks block inserts; metadata locks | Repeatable read loses updates; DDL commits the open transaction |
| SQLite | Zero operations; serializable through a single writer | One writer at a time | Checkpoint starvation; WAL-reset corruption bug (2010 to 2026) |
| Spanner | External consistency across the globe; lock-free reads | TrueTime hardware and commit wait; wound-wait aborts | Idle transactions aborted after 10 s |
| CockroachDB | Serializable by default; online schema change in steps | Client-side retries; non-atomic DDL | Retry errors on long transactions; backfills stuck past the GC window |

## Ideas worth borrowing

Each with what borrowing it would cost.

- **Serializable by default** (CockroachDB, Spanner). Cost: every write needs a retry path, and aborts rise under contention, unless the database replays the transaction itself.
- **Snapshot reads that never block or abort** (MVCC; Spanner's read-only transactions). Cost: old versions must be kept, and the oldest reader holds up cleanup.
- **A hard limit on how long a transaction stays open** (Spanner's idle abort, PostgreSQL's `transaction_timeout`). Cost: long work must be split, or moved outside the transaction, for example to a branch.
- **Schema change as staged states run by a background job** (F1, CockroachDB). Cost: a change takes several steps over time and is not atomic.
- **Guarantees checked by a tool, not stated by a name** (Jepsen's Elle, Hermitage). Cost: building a checker for every guarantee the database claims.

## What I could not confirm

- **PostgreSQL 19 is not out.** GA was moved to 2026-11-19 ([datapace, secondary](https://datapace.ai/blog/postgresql-19-release-date)). The draft release notes list `REPACK (CONCURRENTLY)`, which rebuilds a table without an exclusive lock. Beta 4 reverted several features, and I did not confirm that this one survived.
- **The date Spanner's repeatable read became generally available.** The release notes say it is GA; I did not see a date next to that entry.
- **CockroachDB's version history for read committed.** I did not check which release added it.
- **Primary Ingres sources.** I relied on the PostgreSQL history page.
- **Performance figures for SSI's cost.** I did not read them in the Ports and Grittner paper.
- **Section 5 is reasoning.** I found no study of agents holding transactions open.
