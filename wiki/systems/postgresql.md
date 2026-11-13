# PostgreSQL

PostgreSQL is an open-source relational database: tables queried with SQL, and transactions that succeed or fail as a whole. It is the main row store in the [relational and transactional family](../families/relational-and-transactional.md).

## What it is for

- General transactional work with many concurrent users ([PG docs](https://www.postgresql.org/docs/current/mvcc-intro.html)).
- It began as POSTGRES at Berkeley in 1986, under the leader of Ingres. SQL was added in 1994 (Postgres95), and it was renamed PostgreSQL in 1996 ([PG history](https://www.postgresql.org/docs/current/history.html)).
- The 2024 to 2026 wave centred on it. Databricks bought [Neon](neon.md) (about $1B), Snowflake bought Crunchy Data ($250M), and three distributed-Postgres projects compete: Multigres, Neki and PgDog ([Pavlo, Jan 2026](https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html)).
- Other systems build on it unchanged. [Electric](electric.md) syncs "Shapes" out of Postgres ([docs](https://electric.ax/docs/sync/)). [Chronos](chronos.md), an MIT research system, adds branches over Postgres by rewriting queries ([arXiv 2609.14889](https://arxiv.org/abs/2609.14889)). [pgvector](pgvector.md) and [PostGIS](postgis.md) are index extensions for it.

## Core idea

- **[Multi-version snapshots](../ideas/multi-version-snapshots.md) (MVCC).** Each write makes a new version of the row. Each reader sees a **snapshot**: the committed state at one moment. Readers never wait for writers ([PG MVCC](https://www.postgresql.org/docs/current/mvcc-intro.html)).
- **Old versions live in the table itself**, and a cleanup process, VACUUM, removes the ones nobody can see any more ([research 01](../../research/01-relational-and-transactional.md)).
- This storage came from POSTGRES time travel. Berkeley POSTGRES never overwrote rows. Time travel was dropped in version 6.2 for "performance impact, storage size, and a pg_time file which grows toward infinite size" ([6.3 manual](https://www.postgresql.org/docs/6.3/c0503.htm)). The no-overwrite storage survived as multi-version reads, with vacuum discarding unneeded versions ([Pachot](https://dev.to/franckpachot/postgresql-multi-version-from-time-travel-to-concurrency-control-b5)).
- **Isolation levels.** An isolation level says which effects of concurrent transactions one transaction may see. The default is read committed. "Repeatable read" is snapshot isolation (SI). "Serializable" is true serializability through SSI ([PG docs](https://www.postgresql.org/docs/current/transaction-iso.html)).

## Strengths and what pays for each

- **True serializability.** SSI (Serializable Snapshot Isolation) runs transactions under SI, tracks read-then-write dependencies between concurrent transactions, and aborts one when an anomaly is *possible* ([Ports and Grittner, VLDB 2012](http://vldb.org/pvldb/vol5/p1850_danrkports_vldb2012.pdf)). *Paid for by* false aborts: every serializable transaction must be retried on SQLSTATE `40001` ([PG docs](https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html)).
- **Readers never wait for writers.** *Paid for by* keeping old row versions in the table until VACUUM can remove them; the oldest open snapshot holds up that cleanup ([routine vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html)).
- **Transactional DDL.** DDL (data definition language: `CREATE`, `ALTER`, `DROP`) runs inside transactions, so a migration can be rolled back ([PG wiki](https://wiki.postgresql.org/wiki/Transactional_DDL_in_PostgreSQL:_A_Competitive_Analysis)). *Paid for by* exclusive locks: most `ALTER TABLE` forms block even plain `SELECT` ([Xata](https://xata.io/blog/migrations-and-exclusive-locks)).
- **Valid-time keys.** Version 18 (2025-09-25) added `WITHOUT OVERLAPS` and `PERIOD` foreign keys, so a row can carry the period when it was true in the world ([feature matrix](https://www.postgresql.org/about/featurematrix/detail/temporal-constraints/)). *Paid for by* care with writes that split periods (see Weaknesses). There is no system versioning.
- **Functions the optimizer can use.** Each function is labelled `VOLATILE`, `STABLE` or `IMMUTABLE`, "a promise to the optimizer"; only non-volatile ones may be used in an index scan ([PG volatility](https://www.postgresql.org/docs/current/xfunc-volatility.html)). *Paid for by* trust: the database does not check the label.

## Weaknesses

- **One long transaction stops cleanup everywhere.** VACUUM cannot remove any version an open transaction might still see. The cut-off is the oldest snapshot in the whole cluster (the "xmin horizon"), so one idle session stops cleanup in every table ([routine vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html); [postgres-ai](https://github.com/postgres-ai/postgres-howtos/blob/main/0030_how_to_deal_with_long-running_transactions_oltp.md)).
  - Tables bloat and queries slow down.
  - Freezing old transaction IDs, needed before the 32-bit counter wraps, also stalls. Wraparound is described as "catastrophic data loss".
  - The fixes are timeouts: `idle_in_transaction_session_timeout`, and `transaction_timeout` since PostgreSQL 17. See [transaction time limits](../ideas/transaction-time-limits.md).
- **Migrations queue up.** While an `ALTER` waits behind a long transaction, every later query on that table queues behind the `ALTER` ([Xata](https://xata.io/blog/migrations-and-exclusive-locks)). The usual guard is a short `lock_timeout` and retrying by hand; there is no automatic retry. `CREATE INDEX CONCURRENTLY` avoids the lock but cannot run inside a transaction ([docs](https://www.postgresql.org/docs/current/sql-createindex.html)).
- **Serializable has had bugs.** Jepsen found that PostgreSQL 12.3's serializable level let write skew through because of a bug in conflict detection; a fix followed ([Jepsen, 2020-06-12](https://jepsen.io/analyses/postgresql-12.3)).
- **Managed copies can break snapshot isolation.** Amazon RDS for PostgreSQL clusters showed "Long Fork" even when healthy ([Jepsen, 2025-04-29](https://jepsen.io/analyses/amazon-rds-for-postgresql-17.4)).
- **History and overlapping writes still collide.** `UPDATE/DELETE FOR PORTION OF` was reverted from PostgreSQL 19 on 2026-09-15 ([commit message](https://www.postgresql.org/message-id/E1x6QRv-00000000QOV-0oQc%40gemulon.postgresql.org)). A contributor's write-up gives the reason: updating part of a period splits a row in two, and a second writer waiting on that row wakes to find it shrunk and silently updates nothing ([tapoueh](https://tapoueh.org/blog/2026/09/getting-ready-for-postgresql-19/)). Research 05 notes the reason comes from that blog, not the commit.
- **Triggers are hard to reason about.** They fire "in alphabetical order by trigger name"; cascades have "no direct limitation", and avoiding infinite recursion "is the trigger programmer's responsibility" ([PG triggers](https://www.postgresql.org/docs/current/trigger-definition.html)). See [stored procedures and triggers](../ideas/stored-procedures-and-triggers.md).
- **Not confirmed.** PostgreSQL 19 is not out; GA was moved to 2026-11-19 ([datapace, secondary](https://datapace.ai/blog/postgresql-19-release-date)). The draft notes list `REPACK (CONCURRENTLY)`, which rebuilds a table without an exclusive lock, but research 01 did not confirm it survived beta 4.

## Overlapping work

- Reads use snapshots and never block. Serializable transactions are checked by SSI and aborted with `40001`; the application or its client library replays them ([research 01](../../research/01-relational-and-transactional.md)).
- Stored procedures run inside the caller's transaction and use whatever the database does: locks or snapshots ([research 07](../../research/07-code-inside-the-database.md)).
- Code and data change separately: stored data changes through separate migration scripts ([research 07](../../research/07-code-inside-the-database.md)).

## What an agent struggles with

Research 01 marks this as its own inference.

- **Thinking inside a transaction.** An agent that opens a transaction, then calls a model for 30 seconds, is the long transaction that stalls VACUUM or blocks a migration.
- **Retrying correctly.** After `40001` the agent must replay the *whole* transaction and re-read data. If its reasoning depended on what it read, the retry must re-run the reasoning too.
- **Migrations.** The safe pattern (short `lock_timeout`, then retry) lives in blogs, not in the database.
- **Hidden effects.** A trigger is invisible at the call site, so an agent writing one row cannot see what else will change ([research 07](../../research/07-code-inside-the-database.md)).
- **Permissions it cannot read.** Row-level security is enforced but the agent cannot inspect it; MCP servers show schemas, not policies (inference, [research 09](../../research/09-agents-and-databases-today.md)). In the July 2025 Supabase MCP leak, an agent holding the all-powerful `service_role` key followed instructions planted in a support ticket and copied a token table into that ticket ([General Analysis](https://generalanalysis.com/blog/supabase-mcp-blog)).

## Worth borrowing

- **A hard limit on how long a transaction stays open** (`transaction_timeout`). Cost: long work must be split or moved outside the transaction, for example to a branch ([research 01](../../research/01-relational-and-transactional.md)).
- **Valid time beside system time**, as in the version 18 keys, for after-the-fact corrections. Cost: an "as of when?" on every query and care with writes that split periods ([research 05](../../research/05-databases-that-keep-history.md)). See [valid time and system time](../ideas/valid-time-and-system-time.md).

## Disagreements

- **Whether agents really hold transactions open.** Research 01 says it found no study of agents doing this and marks its agent section as reasoning. Research 08 and 09 cite a 2026 workshop paper stating that agents hold transactions open while waiting for the model ([SAO workshop](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- [research/08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- Primary links are given inline above.
