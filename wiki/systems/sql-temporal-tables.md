# SQL:2011 temporal tables (SQL Server, MariaDB)

SQL:2011 is the SQL standard that added tables which keep their own history. SQL Server and MariaDB implement its system-versioned tables; PostgreSQL has part of it.

## What it is for

Standard SQL history inside a mainstream relational database ([05](../../research/05-databases-that-keep-history.md)).

## Core idea

- SQL:2011 standardised two kinds of table (https://sigmodrecord.org/2012/09/30/temporal-features-in-sql2011/):
  - *system-versioned tables*, where the database records when each row version was current;
  - *application-time period tables*, where the application records when a fact was true in the world.
- Together these are the two timelines of a *bitemporal* store. See [Two timelines](../ideas/valid-time-and-system-time.md).
- A history table sits beside the live one ([05](../../research/05-databases-that-keep-history.md)).

## Strengths and what pays for each

- **History in standard SQL.** Paid for by a history table beside the live one ([05](../../research/05-databases-that-keep-history.md)). See [Reading the database as it was](../ideas/time-travel-queries.md).
- **History cannot be edited while versioning is on.** In SQL Server you "cannot directly delete rows from history table while SYSTEM_VERSIONING = ON" (https://learn.microsoft.com/en-us/sql/relational-databases/tables/modifying-data-in-a-system-versioned-temporal-table?view=sql-server-ver15). Paid for by an awkward path for deletion (below).
- **MariaDB gates history deletion behind its own privilege.** It needs a separate `DELETE HISTORY` privilege (https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/system-versioned-tables).

## Weaknesses

- **Deleting history means switching it off.** In SQL Server you turn versioning off to delete history; then anyone with enough permission can rewrite or drop it (https://learn.microsoft.com/en-us/sql/relational-databases/tables/stopping-system-versioning-on-a-system-versioned-temporal-table?view=sql-server-ver17).
- **Retention defaults to infinite** (https://learn.microsoft.com/en-us/sql/relational-databases/tables/manage-retention-of-historical-data-in-system-versioned-temporal-tables?view=sql-server-ver17).
- **Schema changes.** SQL Server carries changes into history tables but refuses some, or needs history switched off first ([05](../../research/05-databases-that-keep-history.md)).
- **No user, no reason.** These tables record time and transaction only ([05](../../research/05-databases-that-keep-history.md)).

## Overlapping work

Writes that change part of a period collide with history. PostgreSQL 18 (2025-09-25) added valid-time keys (`WITHOUT OVERLAPS`, `PERIOD` foreign keys) but no system versioning (https://www.postgresql.org/about/featurematrix/detail/temporal-constraints/). `UPDATE/DELETE FOR PORTION OF` was reverted from PostgreSQL 19 on 2026-09-15 (https://www.postgresql.org/message-id/E1x6QRv-00000000QOV-0oQc%40gemulon.postgresql.org). A contributor's write-up gives the reason: updating part of a period splits a row in two, and a second writer waiting on that row wakes to find it shrunk, cannot see the new piece, and silently updates nothing (https://tapoueh.org/blog/2026/09/getting-ready-for-postgresql-19/). The revert reason comes from that blog; the commit message seen lists commits, not the reason ([05](../../research/05-databases-that-keep-history.md)). See [PostgreSQL](postgresql.md).

## What an agent struggles with

Two time axes double the ways a query can be wrong. "As of when?" is easy to forget ([05](../../research/05-databases-that-keep-history.md)).

## Worth borrowing

Valid time for after-the-fact corrections. Costs query complexity and care with writes that split periods (researcher's inference, [05](../../research/05-databases-that-keep-history.md)).

## Disagreements

- **Who made a change.** [00](../../research/00-landscape-overview.md) says bitemporal stores record when a fact changed and who wrote it. [05](../../research/05-databases-that-keep-history.md) says SQL:2011 tables record only time and transaction, with no user.

## Sources

- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- https://sigmodrecord.org/2012/09/30/temporal-features-in-sql2011/
- https://learn.microsoft.com/en-us/sql/relational-databases/tables/modifying-data-in-a-system-versioned-temporal-table?view=sql-server-ver15
- https://learn.microsoft.com/en-us/sql/relational-databases/tables/stopping-system-versioning-on-a-system-versioned-temporal-table?view=sql-server-ver17
- https://learn.microsoft.com/en-us/sql/relational-databases/tables/manage-retention-of-historical-data-in-system-versioned-temporal-tables?view=sql-server-ver17
- https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/system-versioned-tables
- https://www.postgresql.org/about/featurematrix/detail/temporal-constraints/
- https://www.postgresql.org/message-id/E1x6QRv-00000000QOV-0oQc%40gemulon.postgresql.org
- https://tapoueh.org/blog/2026/09/getting-ready-for-postgresql-19/
