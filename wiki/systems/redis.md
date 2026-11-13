# Redis

Redis is an in-memory store of typed data structures such as lists, sets and hashes. Client commands run one at a time on a main thread.

## What it is for

Fast access to typed structures held in memory ([03](../../research/03-key-value-document-distributed.md)). The research file gives 2009 as its start year from memory, not from a fetched page ([03](../../research/03-key-value-document-distributed.md), not confirmed).

## Core idea

- Typed structures (lists, sets, hashes) held in memory. Commands run one at a time on a main thread ([03](../../research/03-key-value-document-distributed.md)).
- Client commands still run on the main thread, with two exceptions: I/O threads handle reading, writing and TLS, and the Redis Query Engine uses a pool of worker threads for queries ([00](../../research/00-landscape-overview.md), https://github.com/redis/redis/pull/13665, https://redis.io/blog/redis-8-0-m03-is-out-even-more-performance-new-features/, https://www.infoq.com/news/2024/07/redis-vector-database-genai-rag/, https://redis.io/blog/redis-8-4-open-source-ga/).

See [One writer at a time](../ideas/one-writer-at-a-time.md).

## Strengths and what pays for each

- **Each command is atomic for free.** Paid for by one core doing all command work ([03](../../research/03-key-value-document-distributed.md)).
- **Speed comes from memory.** Paid for by durability. With the default `appendfsync everysec` you "can afford to lose up to one second worth of writes" ([03](../../research/03-key-value-document-distributed.md), https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/).

## Weaknesses

- **No rollback.** "Redis does not support rollbacks of transactions". `MULTI/EXEC` only queues commands ([03](../../research/03-key-value-document-distributed.md), https://redis.io/docs/latest/develop/using-commands/transactions/).
- **Acknowledged writes can be lost.** Redis Cluster keeps writes "in a best-effort way". "Usually there are small windows where acknowledged writes can be lost", larger for clients in a minority partition (https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/). A *partition* is when some machines still run but cannot reach each other. `WAIT` "does not make Redis a strongly consistent store" (https://redis.io/docs/latest/commands/WAIT/).

- **RediShell (CVE-2025-49844).** A use-after-free in Redis's Lua interpreter leads to code execution on the host. It needs a login, but Wiz counts about 60,000 internet-facing Redis instances with no authentication (security vendor claim, https://www.wiz.io/blog/wiz-research-redis-rce-cve-2025-49844). See [a memory-safe engine that parses nothing before login](../ideas/memory-safe-engine.md).

## Overlapping work

`WATCH` adds an optimistic check-and-set: the transaction aborts if a watched key changed ([03](../../research/03-key-value-document-distributed.md), https://redis.io/docs/latest/develop/using-commands/transactions/). See [Optimistic concurrency and version-checked writes](../ideas/optimistic-concurrency.md).

## What an agent struggles with

An "OK" may not survive a failover, and no reply says so ([03](../../research/03-key-value-document-distributed.md), inference). See [Telling the caller what a read or write guarantees](../ideas/consistency-reported-to-the-caller.md) and [Replying only after a write is durable](../ideas/reply-only-after-durable-write.md).

## Worth borrowing

- **Check-and-set on a version token (`WATCH`).** The simplest way to stop lost updates between agents. Cost: callers must re-read and retry ([03](../../research/03-key-value-document-distributed.md)).
- **One command thread.** Atomic commands with no locks. Cost: one core bounds command throughput ([03](../../research/03-key-value-document-distributed.md)).

## Disagreements

- **How much work runs on the one thread.** [03](../../research/03-key-value-document-distributed.md) says one core does all command work. [00](../../research/00-landscape-overview.md) agrees that client commands run on the main thread, but says the Redis Query Engine runs queries on a pool of worker threads and I/O threads handle reading, writing and TLS.

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- https://www.wiz.io/blog/wiz-research-redis-rce-cve-2025-49844
- https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/
- https://redis.io/docs/latest/develop/using-commands/transactions/
- https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/
- https://redis.io/docs/latest/commands/WAIT/
- https://github.com/redis/redis/pull/13665
- https://redis.io/blog/redis-8-0-m03-is-out-even-more-performance-new-features/
- https://www.infoq.com/news/2024/07/redis-vector-database-genai-rag/
- https://redis.io/blog/redis-8-4-open-source-ga/
