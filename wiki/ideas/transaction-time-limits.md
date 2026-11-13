# Long transactions and time limits

What happens when a transaction stays open for seconds or minutes, and the hard limits some databases put on how long one may run. None of the mainstream engines treats a minute-long transaction as a normal case.

## What it is

- **Every engine fails on a long transaction in its own way** ([research 01](../../research/01-relational-and-transactional.md)):
  - **PostgreSQL.** VACUUM cannot remove any row version an open transaction might still see, and the cut-off is the oldest snapshot in the cluster, so one idle session stops cleanup in every table. Tables bloat, and freezing old transaction IDs stalls; wraparound is described as "catastrophic data loss" ([routine vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html); [postgres-ai](https://github.com/postgres-ai/postgres-howtos/blob/main/0030_how_to_deal_with_long-running_transactions_oltp.md)).
  - **MySQL (InnoDB).** Purge cannot free undo that an open snapshot needs, "even for transactions that are read only", and queries and shutdown slow ([purge docs](https://dev.mysql.com/doc/refman/8.4/en/innodb-purge-configuration.html)). A long or inactive transaction can make online DDL time out ([online DDL](https://dev.mysql.com/doc/refman/8.4/en/innodb-online-ddl-limitations.html)).
  - **Oracle.** The long *reader* fails with ORA-01555 "snapshot too old" once its undo is overwritten ([Oracle undo](https://docs.oracle.com/cd/B19306_01/server.102/b14231/undo.htm)).
  - **SQLite.** An open reader stops a checkpoint from resetting the write-ahead log, so the file keeps growing ([wal.html](https://sqlite.org/wal.html)).
  - **CockroachDB.** A long transaction whose reads are overwritten must "refresh" and may fail with a retry error ([retry reference](https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference)).
  - **GemStone.** Its optimistic commits abort more often the longer a transaction runs ([research 04](../../research/04-models-that-lost-or-stayed-niche.md)).
  - **Prevayler.** Transactions must be short "because they block the system", and long ones are "an open question" ([cl-prevalence](https://cl-prevalence.common-lisp.dev/)).
- **Some systems set a hard limit:**

| System | Limit |
|---|---|
| PostgreSQL | `idle_in_transaction_session_timeout`; `transaction_timeout` since version 17 ([research 01](../../research/01-relational-and-transactional.md)) |
| Spanner | May abort a read-write transaction with no read for 10 seconds "so that they don't hold on to locks indefinitely"; clients send `SELECT 1` to keep it alive ([transactions](https://docs.cloud.google.com/spanner/docs/transactions)) |
| FoundationDB | Transactions may not run "for over five seconds" or exceed 10 MB ([known limitations](https://apple.github.io/foundationdb/known-limitations.html)) |
| Convex | User code gets 1 second; a transaction may write at most 16,000 documents ([limits](https://docs.convex.dev/production/state/limits)) |

## The problem it solves

- A limit stops one forgotten or slow session from stalling cleanup, holding locks, or blocking migrations for everyone else ([research 01](../../research/01-relational-and-transactional.md)).
- Agents make the problem sharper. A 2026 workshop paper says agents retry with altered queries, fan out into bursts of parallel work, and hold transactions open while waiting for the model. That breaks the assumption in concurrency control that transactions are short, and can cause self-sustaining slowdowns ([SAO workshop](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf)). Research 01 reasons the same way: an agent that opens a transaction and then calls a model for 30 seconds is the long transaction every engine punishes (inference).

## What it costs

- **Long work must be split, or moved outside the transaction**, for example to a branch ([research 01](../../research/01-relational-and-transactional.md)). See [copy-on-write branches](copy-on-write-branches.md).
- **The limit itself becomes the agent's problem.** FoundationDB's five seconds is short for an agent that holds a transaction while the model thinks ([research 08](../../research/08-correctness-first-databases.md)). Convex's 1-second budget is one of its hidden rules ([research 07](../../research/07-code-inside-the-database.md)).
- **Partly solved elsewhere.** Research 09 judges that [optimistic concurrency](optimistic-concurrency.md) and branches already cover work that overlaps for minutes, while held-open transactions still cause the slowdowns the workshop paper describes (inference, about 65% confidence).

## Systems that use it

- Limits: [PostgreSQL](../systems/postgresql.md), [Spanner](../systems/spanner.md), [FoundationDB](../systems/foundationdb.md), [Convex](../systems/convex.md).
- Failure modes without a limit: [MySQL (InnoDB)](../systems/mysql.md), [Oracle Database](../systems/oracle.md), [SQLite](../systems/sqlite.md), [CockroachDB](../systems/cockroachdb.md), [GemStone](../systems/gemstone.md), [Prevayler](../systems/prevayler.md).

## Cannot be combined with

- **An agent that keeps a transaction open while it calls a model.** Under a limit the transaction is aborted; without one, it stalls cleanup or blocks others (inference, [research 01](../../research/01-relational-and-transactional.md); [research 08](../../research/08-correctness-first-databases.md)).
- **[Multi-version snapshots](multi-version-snapshots.md) without a bound on the oldest reader.** The oldest snapshot holds up cleanup ([research 01](../../research/01-relational-and-transactional.md)).

## Disagreements

- **Evidence that agents hold transactions open.** Research 01 says it found no study of agents holding transactions open and marks its agent section as reasoning. Research 08 and 09 cite the 2026 workshop paper stating that agents hold transactions open while waiting for the model ([SAO workshop](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf)).

## Sources

- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [research/07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- [research/08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- Primary links are given inline above.
