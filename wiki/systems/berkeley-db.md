# Berkeley DB

Berkeley DB is a key-value store that is a library linked into the program, not a server. It began as a free replacement for the Unix `dbm` and `ndbm` hash files and later gained transactions, replication and SQL.

## What it is for

- Berkeley DB began as a free replacement for Unix's `dbm`/`ndbm` on-disk hash files and the in-memory `hsearch` ([03](../../research/03-key-value-document-distributed.md), https://aosabook.org/en/v1/bdb.html).
- Transactions arrived in version 2.0 (1997), replication in 4.0 (2001) and SQL in 5.0 (2010) (same source).
- The start year of "about 1991" is the research file's inference from the AOSA history, which names 4BSD and the 1.85 release without a year ([03](../../research/03-key-value-document-distributed.md), not confirmed).

## Core idea

- A *key-value store*: you put and get values by a key, and the store does not look inside the value ([03](../../research/03-key-value-document-distributed.md)).
- It is a library linked into the program, with hash or B-tree files, a *write-ahead log* (the change is logged before the data changes, so a crash can be replayed) and locks. "No inter-process communication ... is required" (https://web.stanford.edu/class/cs276a/projects/docs/berkeleydb/ref/intro/dbis.html). See [The database inside the application process](../ideas/database-inside-the-application-process.md).

## Strengths and what pays for each

- **Strict ACID by default.** ACID means a transaction is all-or-nothing, keeps the data valid, is isolated from others, and survives a crash. Paid for by locks and a log that every write goes through ([03](../../research/03-key-value-document-distributed.md), https://web.stanford.edu/class/cs276a/projects/docs/berkeleydb/ref/intro/dbis.html).
- **No server latency.** Paid for by having no network access and no query language ([03](../../research/03-key-value-document-distributed.md)).

## Weaknesses

- **It locks whole pages.** One writer on a page blocks writers of other records on that page. The authors chose this because it limits the states a page can be in during recovery, and later called the choice "problematic at times" ([03](../../research/03-key-value-document-distributed.md), https://aosabook.org/en/v1/bdb.html).

## Overlapping work

Locks, deadlock detection, and the option to relax isolation ([03](../../research/03-key-value-document-distributed.md)). A *deadlock* is two transactions each waiting for a lock the other holds.

## What an agent struggles with

Bytes in, bytes out. An agent must already know how values are encoded and which keys exist ([03](../../research/03-key-value-document-distributed.md), inference).

## Worth borrowing

- ACID inside the process, with no server ([03](../../research/03-key-value-document-distributed.md)). Cost: no queries, and page locks that cause contention.
- Multi-item transactions came back in BDB 2.0, one of several key-value stores that later added them ([03](../../research/03-key-value-document-distributed.md)).

## Sources

- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- https://aosabook.org/en/v1/bdb.html
- https://web.stanford.edu/class/cs276a/projects/docs/berkeleydb/ref/intro/dbis.html
