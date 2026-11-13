# Cloudflare Durable Objects

Durable Objects are Cloudflare's single-threaded actors, each with its own private SQLite database running in the same thread as the object's code ([Cloudflare, 2024-09-26](https://blog.cloudflare.com/sqlite-in-durable-objects/); [research 07](../../research/07-code-inside-the-database.md)). An *actor* is an object that handles one message at a time and owns its state.

## What it is for

Running app code and its storage together, with no separate database server or wire protocol between them ([research 00](../../research/00-landscape-overview.md)).

## Core idea

Each object runs "in one single thread" with private SQLite storage "in the very same thread" ([Cloudflare blog](https://blog.cloudflare.com/sqlite-in-durable-objects/)).

- *Input gates* queue new events while the object does synchronous work.
- *Output gates* hold replies until writes are durable.
- "Awaiting async operations like `fetch()` … opens the input gate, allowing other requests to interleave" ([rules of Durable Objects](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/)).

A Cloudflare "migration" renames or deletes classes; reshaping data is left to the developer ([glossary](https://developers.cloudflare.com/durable-objects/reference/glossary/)).

## Strengths and what pays for each

- **Very fast queries.** Research 00 reports "near-zero latency" from Cloudflare's blog; research 07 reports the vendor's figure of microseconds per query and marks it a vendor claim. Paid for by: one object's throughput is limited to one thread ([research 00](../../research/00-landscape-overview.md); [research 07](../../research/07-code-inside-the-database.md)).
- **No locks inside an object, and local storage.** Paid for by: one object is the throughput ceiling, and no transaction spans two objects ([research 07](../../research/07-code-inside-the-database.md)).
- **Replies only after the write is durable** (output gates). Paid for by: latency on every write ([research 07](../../research/07-code-inside-the-database.md)).

## Weaknesses

- No transactions across objects ([research 07](../../research/07-code-inside-the-database.md)).
- An `await` lets other requests interleave, so state can change in the middle of a handler ([rules](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/)).
- Changing the shape of stored data is the developer's job ([glossary](https://developers.cloudflare.com/durable-objects/reference/glossary/)).
- Research 07 found no current official figure for throughput per object, and research 00 did not verify the general-availability date.

## Overlapping work

One thread per object: events queue at the input gate and run one at a time, except across an `await` ([research 07](../../research/07-code-inside-the-database.md)). See [one writer at a time](../ideas/one-writer-at-a-time.md).

## What an agent struggles with

The partition key (which object owns which data) must be chosen up front, and work that spans keys has no transaction ([research 07](../../research/07-code-inside-the-database.md)).

## Worth borrowing

**Reply only after the write is durable.** Mo already does this. Cost: latency on every write ([research 07](../../research/07-code-inside-the-database.md)). See [reply only after a durable write](../ideas/reply-only-after-durable-write.md).

## Disagreements

- **Query latency.** Research 00 repeats Cloudflare's "near-zero latency" without a vendor mark ([research 00](../../research/00-landscape-overview.md)). Research 07 marks the same blog's microsecond query figure as a vendor claim ([research 07](../../research/07-code-inside-the-database.md)).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- SQLite in Durable Objects: https://blog.cloudflare.com/sqlite-in-durable-objects/
- Rules of Durable Objects: https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/
- Glossary: https://developers.cloudflare.com/durable-objects/reference/glossary/
