# SQLite

SQLite is an embedded SQL database: a library inside the application, with no server. It allows one writer at a time and is known for exhaustive testing. It belongs to the [relational and transactional family](../families/relational-and-transactional.md).

## What it is for

- Zero operational overhead: a library in the application process instead of a server ([research 00](../../research/00-landscape-overview.md); [isolation](https://sqlite.org/isolation.html)). See [database inside the application process](../ideas/database-inside-the-application-process.md).
- First released 2000-08-17 ([chronology](https://www.sqlite.org/chronology.html)).
- Others build on it. Cloudflare Durable Objects run SQLite "in the very same thread" as app code ([Cloudflare, 2024-09-26](https://blog.cloudflare.com/sqlite-in-durable-objects/)); see [Cloudflare Durable Objects](cloudflare-durable-objects.md). Turso's AgentFS is a SQLite-backed filesystem where an agent's writes land in a copy-on-write layer ([Turso](https://turso.tech/blog/agentfs-overlay)). [Chronos](chronos.md) adds branches over SQLite unchanged ([arXiv 2609.14889](https://arxiv.org/abs/2609.14889)).
- Mo itself writes its upgrade snapshot in one SQLite transaction (`~/code/mo/docs/design/upgrades.md`, per [research 07](../../research/07-code-inside-the-database.md)).

## Core idea

- **[One writer at a time](../ideas/one-writer-at-a-time.md)** ([isolation](https://sqlite.org/isolation.html)). In WAL mode, readers run alongside the single writer ([wal.html](https://sqlite.org/wal.html)). WAL is the write-ahead log: changes are appended to a log file before they reach the main database.
- **Old versions live in the WAL file**, and a **checkpoint** copies them back and resets the log ([research 01](../../research/01-relational-and-transactional.md)).
- **Exhaustive testing instead of simulation.** The library is about 155.8 thousand lines; the project has "590 times as much test code" ([testing](https://www.sqlite.org/testing.html)).

## Strengths and what pays for each

- **Serializable with zero operations.** *Paid for by* one writer at a time ([research 01](../../research/01-relational-and-transactional.md)).
- **100% MC/DC coverage** from the TH3 harness. MC/DC means each condition in each branch is shown to change the outcome on its own; it is an avionics standard. *Paid for by* TH3 being proprietary and huge: about 248.5 million test runs before a release ([TH3](https://www.sqlite.org/th3.html)).
- **Crash and I/O-error loops.** Crash tests use an in-memory file system that snapshots after N writes, damages the files as a power loss would, then checks the database; the loop moves N forward each time ([testing](https://www.sqlite.org/testing.html)). *Paid for by* all I/O going through one replaceable interface, the VFS.

## Weaknesses

- **Checkpoint starvation.** An open reader stops a checkpoint from resetting the WAL, so the WAL file keeps growing ([wal.html](https://sqlite.org/wal.html)).
- **A corruption bug lived for 16 years.** The WAL-reset bug could corrupt a database when two connections wrote or checkpointed "at the same instant". It is "likely present" in every version from 3.7.0 (2010) to 3.51.2 and was fixed in 3.51.3 (2026-03-13). A reproducer without special test code came only in August 2026 ([wal.html §11](https://sqlite.org/wal.html)).
- **Concurrent writers wait.** Agents get busy errors when several write at once ([research 08](../../research/08-correctness-first-databases.md)).
- **No concurrent writes in mainline.** `BEGIN CONCURRENT` lives on an unmerged branch ([doc](https://sqlite.org/src/doc/begin-concurrent/doc/begin_concurrent.md)).

## Overlapping work

- One writer; readers in WAL mode see a snapshot and do not block it ([wal.html](https://sqlite.org/wal.html)).
- Turso's Rust rewrite adds concurrent writers through [multi-version concurrency](../ideas/multi-version-snapshots.md), started with `BEGIN CONCURRENT`; schema changes are not allowed inside those transactions ([Turso docs](https://docs.turso.tech/tursodb/concurrent-writes)). See Disagreements for whether this is still beta.

## What an agent struggles with

- **Busy errors** when several agents write at once ([research 08](../../research/08-correctness-first-databases.md)).
- **Thinking inside a transaction.** An open reader starves checkpoints (inference, [research 01](../../research/01-relational-and-transactional.md)).
- **Unsafe tooling.** Trend Micro found SQL injection in Anthropic's reference SQLite MCP server that allowed stored prompt injection. The repository was archived with no patch after being forked more than 5,000 times (2025-06-24) ([Trend Micro](https://www.trendmicro.com/en/research/25/f/why-a-classic-mcp-server-vulnerability-can-undermine-your-entire-ai-agent.html)).

## Worth borrowing

- **The moving crash point.** Cost: every write must be a countable step ([research 08](../../research/08-correctness-first-databases.md)).
- **Serializability through a single writer.** Cost: one writer at a time ([research 01](../../research/01-relational-and-transactional.md)).

## Disagreements

- **Turso's concurrent writes.** Research 00 says Turso's MVCC concurrent writes are in beta ([v0.5](https://turso.tech/blog/turso-0.5.0)). Research 09 says Turso supports concurrent writers via `BEGIN CONCURRENT`, with no beta caveat, and adds that schema changes are not allowed inside them ([docs](https://docs.turso.tech/tursodb/concurrent-writes)).
- **Whether agents really hold transactions open.** Research 01 found no study and marks its agent reasoning as inference; research 08 and 09 cite a 2026 workshop paper saying agents do ([SAO workshop](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- Primary links are given inline above.
