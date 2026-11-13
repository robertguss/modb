# Oracle Database

Oracle Database is a commercial relational row store. It keeps old row images in a circular undo area and uses them both for snapshot reads and for its history features. It belongs to the [relational and transactional family](../families/relational-and-transactional.md).

## What it is for

- One of the row stores in wide use for general transactional work, beside PostgreSQL, MySQL and SQLite ([research 01](../../research/01-relational-and-transactional.md)).

## Core idea

- **[Multi-version snapshots](../ideas/multi-version-snapshots.md).** Each write makes a new version; each reader sees a snapshot, so readers never wait for writers ([Oracle concepts](https://docs.oracle.com/en/database/oracle/oracle-database/18/cncpt/data-concurrency-and-consistency.html)).
- **Old versions live in circular undo segments.** *Undo* is the old row images kept so a transaction can be rolled back. They are overwritten when space runs out ([research 01](../../research/01-relational-and-transactional.md)).
- **Isolation.** The default is read committed. There is no "repeatable read". Oracle's "serializable" is snapshot isolation, which allows **write skew**: two transactions each read the same two values, each write a different one, and together break a rule both checked ([Hermitage](https://github.com/ept/hermitage/blob/master/oracle.md)).

## Strengths and what pays for each

- **Readers never block, through undo-based snapshots.** *Paid for by* circular undo that gets overwritten, so a long reader can fail (see Weaknesses) ([research 01](../../research/01-relational-and-transactional.md)).
- **Two schema versions side by side.** Edition-Based Redefinition lets two versions of schema objects exist at once ([PG wiki, quoting Oracle](https://wiki.postgresql.org/wiki/Transactional_DDL_in_PostgreSQL:_A_Competitive_Analysis)). See [staged schema changes](../ideas/staged-schema-changes.md).
- **History inside a mainstream database.** *Paid for by* a bounded window and a storage bill ([research 05](../../research/05-databases-that-keep-history.md)).
  - **Flashback Query** reads undo, and fails with "snapshot too old" once it is overwritten ([managing undo](https://docs.oracle.com/en/database/oracle/oracle-database/18/admin/managing-undo.html)).
  - **Flashback Time Travel** copies changes into history tables that even a database administrator cannot edit ([flashback](https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html)).
  - **Flashback Transaction Query** shows `LOGON_USER` and an `UNDO_SQL` for each change ([reference](https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/FLASHBACK_TRANSACTION_QUERY.html)).
- **Fresh analytics on live rows.** Oracle Database In-Memory keeps rows in the buffer cache plus a columnar copy in memory, kept "transactionally consistent" ([In-Memory guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/inmem/intro-to-in-memory-column-store.html)). *Paid for by* memory for a second copy and change tracking on writes (inference, [research 02](../../research/02-analytical-and-specialised.md)). See [transactions and analytics together](../ideas/transactions-and-analytics-together.md).

## Weaknesses

- **The long reader fails.** When the undo a reader needs is overwritten, it fails with ORA-01555 "snapshot too old" ([Oracle undo](https://docs.oracle.com/cd/B19306_01/server.102/b14231/undo.htm)). This is the reverse of PostgreSQL and InnoDB, where the long reader stops cleanup instead.
- **"Serializable" allows write skew** ([Hermitage](https://github.com/ept/hermitage/blob/master/oracle.md)).
- **DDL commits any open transaction** ([PG wiki](https://wiki.postgresql.org/wiki/Transactional_DDL_in_PostgreSQL:_A_Competitive_Analysis)).
- **History and schema changes collide.** Some schema changes fail with ORA-55610 unless the history archive is detached and reattached ([flashback](https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html)).
- **Undo SQL is approximate.** It "is not the exact opposite" in every case ([reference](https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/FLASHBACK_TRANSACTION_QUERY.html)).
- **Who made a change is weakly recorded.** The logon user is usually a shared application account ([research 05](../../research/05-databases-that-keep-history.md)).
- **Redaction can be probed.** Oracle Data Redaction puts no limit on "the WHERE clause", which can be used "in an iterative fashion to infer the actual data"; SYSDBA is exempt ([redaction security](https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/security-considerations-for-using-oracle-data-redaction.html)). See [masking query results by role](../ideas/dynamic-masking.md).

## Overlapping work

- Readers use snapshots and never block writers. Writers to the same row wait on each other ([research 01](../../research/01-relational-and-transactional.md)).

## What an agent struggles with

Inference from research 01, which reasons about all the relational engines together.

- **Trusting a level's name.** An agent that asks for "serializable" gets snapshot isolation and can commit write skew.
- **Probing redacted columns.** An agent writes ad hoc SQL, exactly the reader redaction says it does not stop (inference, [research 20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Thinking inside a long read.** An agent that holds a snapshot while it calls a model risks ORA-01555 when the undo is overwritten.

## Worth borrowing

- **Bounded history windows.** These are what mainstream users actually accept ([research 05](../../research/05-databases-that-keep-history.md)). See [time-travel queries](../ideas/time-travel-queries.md).

## Disagreements

- **Whether history-keeping stores record who made a change.** Research 00 says bitemporal stores record when a fact changed and who wrote it, but not why. Research 05 says Oracle records only a logon user, usually a shared account.

## Sources

- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- Primary links are given inline above.
