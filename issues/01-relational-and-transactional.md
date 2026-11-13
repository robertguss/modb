# Relational and transactional databases

Type: research
Status: resolved

## Question

Using the map's research template, what do relational, transactional databases do well and badly, and what pays for each strength?

Cover the line from System R and Ingres through Oracle, PostgreSQL, MySQL and SQLite, and the newer distributed ones (Spanner, CockroachDB).

Go deepest on transactions: isolation levels, locking against multi-version snapshots, what happens to a transaction that stays open for minutes, and changing the schema of a live database.

## Answer

Findings: [research/01-relational-and-transactional.md](../research/01-relational-and-transactional.md).

- **Serializability is always paid for** with blocking (locks), aborts that clients must retry (PostgreSQL SSI, CockroachDB), or clock waits (Spanner's TrueTime). Weaker levels move the cost into application bugs.
- **Names of isolation levels are unreliable.** Oracle's "serializable" allows write skew, and Jepsen showed MySQL's default repeatable read silently loses updates.
- **A transaction open for minutes is a fault in every engine.** It stops cleanup (PostgreSQL VACUUM, InnoDB purge, SQLite checkpoints), or it is killed (Oracle snapshot too old, Spanner's 10-second idle abort).
- **Live schema change** either takes an exclusive lock that queues every query behind it (PostgreSQL, MySQL metadata locks), or runs as staged background states (F1, CockroachDB) at the cost of not being atomic.
- **Worth borrowing:** serializable by default with the retry handled by the database, snapshot reads that never block, a hard limit on transaction lifetime, staged schema change, and guarantees checked by a tool.
