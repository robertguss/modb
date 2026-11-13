# MySQL (InnoDB)

MySQL is a widely used relational database; InnoDB is its transactional storage engine. It mixes snapshot reads with locks on index ranges. It belongs to the [relational and transactional family](../families/relational-and-transactional.md).

## What it is for

- One of the row stores in wide use for general transactional work ([research 01](../../research/01-relational-and-transactional.md)).

## Core idea

- **[Multi-version snapshots](../ideas/multi-version-snapshots.md).** Readers see a consistent snapshot ([InnoDB consistent read](https://dev.mysql.com/doc/refman/8.4/en/innodb-consistent-read.html)). Old versions live in the **undo log** and a process called **purge** frees them ([research 01](../../research/01-relational-and-transactional.md)).
- **Isolation.** The default is repeatable read ([InnoDB isolation](https://dev.mysql.com/doc/refman/26.10/en/innodb-transaction-isolation-levels.html)). Its repeatable read is weaker than snapshot isolation. Its serializable level uses locking ([research 01](../../research/01-relational-and-transactional.md)).
- **Next-key locks.** A lock on an index record plus the gap before it, so no one can insert into a range another transaction scanned. This prevents **phantoms**: rows that appear when the same query runs again ([InnoDB locking](https://dev.mysql.com/doc/refman/26.10/en/innodb-locking.html)). See [locks held until commit](../ideas/locks-held-until-commit.md).

## Strengths and what pays for each

- **No phantoms at the default level.** *Paid for by* gap locks: other sessions' inserts into a scanned range wait ([InnoDB locking](https://dev.mysql.com/doc/refman/26.10/en/innodb-locking.html)).
- **Instant `ADD COLUMN`.** `ALGORITHM=INSTANT` changes only metadata. *Paid for by* metadata locks: every online DDL must still wait for transactions holding one, so "a long running or inactive transaction ... can cause an online DDL operation to timeout" ([online DDL](https://dev.mysql.com/doc/refman/8.4/en/innodb-online-ddl-limitations.html)).

## Weaknesses

- **Repeatable read loses updates.** Jepsen found that "MySQL Repeatable Read transactions cannot safely read a value and then write it". The usual load, change and save pattern "may find that MySQL silently discards those committed changes". AWS RDS MySQL "routinely" broke serializability ([Jepsen, 2023-12-19](https://jepsen.io/analyses/mysql-8.0.34)).
- **Old versions pile up.** Purge cannot free undo that an open snapshot still needs, so the "history list length" grows. This happens "even for transactions that are read only", and queries and shutdown get slower ([purge docs](https://dev.mysql.com/doc/refman/8.4/en/innodb-purge-configuration.html)).
- **DDL is not transactional.** DDL statements "implicitly end any transaction", and "atomic DDL is not transactional DDL" ([implicit commit](https://dev.mysql.com/doc/refman/8.4/en/implicit-commit.html); [atomic DDL](https://dev.mysql.com/doc/refman/8.4/en/atomic-ddl.html)).

## Overlapping work

- Snapshot reads for plain `SELECT`; next-key locks for ranges; locking for serializable ([research 01](../../research/01-relational-and-transactional.md)).

## What an agent struggles with

Inference from research 01.

- **Trusting the name.** An agent that trusts "repeatable read" will lose updates. The real guarantee is in Jepsen reports, not in the schema.
- **Holding a transaction open while it thinks.** That grows the history list and can make a migration time out.

## Worth borrowing

- **Guarantees checked by a tool, not stated by a name**, as Jepsen did here. Cost: building a checker for every guarantee the database claims ([research 01](../../research/01-relational-and-transactional.md)). See [guarantees checked by a tool](../ideas/guarantees-checked-by-a-tool.md).

## Sources

- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- Primary links are given inline above.
