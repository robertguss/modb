# Schema changes in stages on a live database

Changing the shape of tables while other transactions use them, by moving each new element through intermediate states run by a background job instead of one locked step. The method comes from Google's F1 on Spanner.

## What it is

- **DDL** (data definition language: `CREATE`, `ALTER`, `DROP`) changes the shape of tables while other transactions use them ([research 01](../../research/01-relational-and-transactional.md)).
- **F1's method.** Each new schema element moves through internal states, **delete-only** and then **write-only**, before it can be read. Every server is at most one state apart, so no server corrupts data another server's schema expects ([F1, VLDB 2013](https://www.vldb.org/pvldb/vol6/p1045-rae.pdf)).
- **CockroachDB adopted it.** Schema changes run as background jobs that hold no locks on table data and can be paused or cancelled ([online schema changes](https://docs.cockroachlabs.com/docs/stable/online-schema-changes)).

## The problem it solves

Changing a schema in one step fights the transactions already running ([research 01](../../research/01-relational-and-transactional.md)):

- **PostgreSQL** runs DDL inside transactions, so a migration can be rolled back ([PG wiki](https://wiki.postgresql.org/wiki/Transactional_DDL_in_PostgreSQL:_A_Competitive_Analysis)). But most `ALTER TABLE` forms need an exclusive lock that blocks even `SELECT`, and while the `ALTER` waits behind a long transaction every later query queues behind it ([Xata](https://xata.io/blog/migrations-and-exclusive-locks)). The guard is a short `lock_timeout` and a manual retry; `CREATE INDEX CONCURRENTLY` avoids the lock but cannot run inside a transaction ([docs](https://www.postgresql.org/docs/current/sql-createindex.html)).
- **MySQL** DDL "implicitly end[s] any transaction", and "atomic DDL is not transactional DDL" ([implicit commit](https://dev.mysql.com/doc/refman/8.4/en/implicit-commit.html); [atomic DDL](https://dev.mysql.com/doc/refman/8.4/en/atomic-ddl.html)). `ALGORITHM=INSTANT` changes only metadata, but online DDL still waits for metadata locks, and a long or inactive transaction can make it time out ([online DDL](https://dev.mysql.com/doc/refman/8.4/en/innodb-online-ddl-limitations.html)).
- **Oracle** commits any open transaction before DDL. Its Edition-Based Redefinition lets two versions of schema objects exist side by side (PG wiki, quoting Oracle).
- **Many servers.** F1's problem was a schema change across many servers that cannot all switch at the same instant ([F1](https://www.vldb.org/pvldb/vol6/p1045-rae.pdf)).

## What it costs

- **A change is no longer one atomic step.** It takes several steps over time ([research 01](../../research/01-relational-and-transactional.md)).
- **Mixed transactions can half-succeed.** In CockroachDB, DDL in a multi-statement transaction "can fail while other statements succeed" ([online schema changes](https://docs.cockroachlabs.com/docs/stable/online-schema-changes)).
- **Backfills can stall.** A backfill can get stuck retrying if it runs past the garbage-collection window ([issue #105632](https://github.com/cockroachdb/cockroach/issues/105632)).
- **Agents.** The safe migration pattern (short `lock_timeout`, then retry) lives in blogs, not in the database (inference, [research 01](../../research/01-relational-and-transactional.md)). Some tools wrap it: Neon's MCP server tests a migration on a temporary branch and applies it only after the user confirms ([mcp-server-neon](https://github.com/neondatabase/mcp-server-neon/)), and Neon offers a schema diff between branches ([schema diff](https://neon.com/docs/guides/schema-diff)). Turso does not allow schema changes inside its concurrent-write transactions ([Turso docs](https://docs.turso.tech/tursodb/concurrent-writes)).

## Systems that use it

- [Spanner](../systems/spanner.md), through F1: the origin of delete-only and write-only stages.
- [CockroachDB](../systems/cockroachdb.md): staged changes as background jobs.

Systems that change schemas in one step instead, with the costs above: [PostgreSQL](../systems/postgresql.md), [MySQL (InnoDB)](../systems/mysql.md), [Oracle Database](../systems/oracle.md).

## Cannot be combined with

- **One atomic DDL step inside a larger transaction.** Staging trades atomicity for running without locks ([research 01](../../research/01-relational-and-transactional.md)).

## Sources

- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- Primary links are given inline above.
