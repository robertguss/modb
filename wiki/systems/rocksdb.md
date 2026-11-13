# RocksDB and LevelDB

LevelDB and RocksDB are embedded key-value stores built on log-structured merge trees: writes land in a log and an in-memory table, then in sorted files that background work merges.

## What it is for

Write-heavy workloads on flash ([00](../../research/00-landscape-overview.md), https://github.com/meta/rocksdb/wiki/RocksDB-Overview). The research file gives 2011 for LevelDB and 2012 for RocksDB from memory, not from a fetched page ([03](../../research/03-key-value-document-distributed.md), not confirmed).

## Core idea

- A *log-structured merge tree (LSM)*: writes go to a log and an in-memory table (the *memtable*), are flushed to sorted files, and background *compaction* merges those files ([03](../../research/03-key-value-document-distributed.md); [00](../../research/00-landscape-overview.md), https://github.com/meta/rocksdb/wiki/RocksDB-Overview).
- LevelDB keeps atomic batches and snapshots, but "this is not a SQL database ... no support for indexes", and "only a single process ... can access a particular database at a time" (https://github.com/google/leveldb/blob/main/README.md). See [The database inside the application process](../ideas/database-inside-the-application-process.md) and [One writer at a time](../ideas/one-writer-at-a-time.md).

## Strengths and what pays for each

- **Cheap sequential writes.** Paid for by compaction. RocksDB names the costs: write, read and space *amplification* (extra bytes written, read or stored per byte of user data). Each compaction style trades one against another. For example, at write amplification 50 and 500 MB/s of disk, the database sustains only 10 MB/s ([03](../../research/03-key-value-document-distributed.md), https://github.com/meta/rocksdb/wiki/RocksDB-Tuning-Guide).

## Weaknesses

- When compaction falls behind, RocksDB stalls writes, or reads slow because too many files must be checked (https://github.com/meta/rocksdb/wiki/RocksDB-Tuning-Guide).

## Overlapping work

RocksDB added transactions back. It offers pessimistic (locking) and optimistic modes. The optimistic one "may not be a good solution" when many transactions update the same keys ([03](../../research/03-key-value-document-distributed.md), https://github.com/meta/rocksdb/wiki/Transactions). See [Optimistic concurrency and version-checked writes](../ideas/optimistic-concurrency.md).

## What an agent struggles with

Latency depends on background work the caller cannot see ([03](../../research/03-key-value-document-distributed.md), inference).

## Worth borrowing

- The memtable, log and compaction design as a write path ([00](../../research/00-landscape-overview.md)). Cost: amplification and write stalls when compaction falls behind ([03](../../research/03-key-value-document-distributed.md)).

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- https://github.com/meta/rocksdb/wiki/RocksDB-Overview
- https://github.com/google/leveldb/blob/main/README.md
- https://github.com/meta/rocksdb/wiki/RocksDB-Tuning-Guide
- https://github.com/meta/rocksdb/wiki/Transactions
