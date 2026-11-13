# Convex

Convex is a database that is also the application server. Queries and mutations are deterministic TypeScript functions that run inside the database, with optimistic concurrency and live query subscriptions ([How Convex works](https://stack.convex.dev/how-convex-works); [research 00](../../research/00-landscape-overview.md)).

## What it is for

Removing the separate application tier, the ORM (the layer that maps objects to tables) and cache invalidation ([research 00](../../research/00-landscape-overview.md)).

## Core idea

- **Optimistic concurrency control (OCC).** Take no locks; "record what each transaction reads and writes", and check for overlap at commit ([How Convex works](https://stack.convex.dev/how-convex-works)). Research 09 notes that these transactions are serializable ([Convex OCC](https://docs.convex.dev/database/advanced/occ); [research 09](../../research/09-agents-and-databases-today.md)). See [optimistic concurrency](../ideas/optimistic-concurrency.md).
- **Retry by re-running the function.** On a conflict, Convex throws away the *write set* (everything the function wrote) and runs the function again. That is safe only because mutations are sandboxed: "this is why… `fetch` isn't available in mutations" ([How Convex works](https://stack.convex.dev/how-convex-works)).
- **Subscriptions from the read set.** The *read set* is everything a query read. When any of it changes, "the query is rerun" ([How Convex works](https://stack.convex.dev/how-convex-works)).

## Strengths and what pays for each

- **Transactions that retry themselves, and exact subscriptions.** Paid for by: a sandbox with no I/O and a 1-second budget for user code ([research 07](../../research/07-code-inside-the-database.md)). Research 00 puts it as "transactions plus reactivity for free", paid for by requiring functions to be deterministic ([research 00](../../research/00-landscape-overview.md)).
- **A schema check at deploy.** A deploy that changes the schema checks every existing document, and the push fails if any does not match ([Convex schemas](https://docs.convex.dev/database/schemas)). Paid for by: every breaking change needs a written migration ([research 07](../../research/07-code-inside-the-database.md)).
- **Fixes three of the four old complaints about stored procedures.** The functions live in the application repository, in a general language, and deploy together with the schema. So they are versioned, testable and portable. Nothing fixes the fourth: the work still lands on the most expensive server ([research 07](../../research/07-code-inside-the-database.md)).

## Weaknesses

- A mutation that keeps conflicting fails after several retries. The error names the table, the other function and a document ID ([Convex errors](https://docs.convex.dev/error)).
- User code gets 1 second, and a transaction may write at most 16,000 documents ([Convex limits](https://docs.convex.dev/production/state/limits)).
- A query that reads widely conflicts with every write to what it read ([research 07](../../research/07-code-inside-the-database.md)).
- Data migrations run "in batches asynchronously" through a library ([convex migrations](https://github.com/get-convex/migrations)).
- The database learns read sets only by watching code run; it cannot analyse the code beforehand (inference, [research 07](../../research/07-code-inside-the-database.md); [research 00](../../research/00-landscape-overview.md)).

## Overlapping work

OCC: each transaction runs without locks, and at commit Convex checks whether anything it read was changed by a transaction that committed first. If so, it re-runs the function ([How Convex works](https://stack.convex.dev/how-convex-works)).

## What an agent struggles with

Research 07 rates Convex and SpacetimeDB the most legible systems it studied: the function is the whole transaction, and conflicts come back named. The traps are hidden rules: no `fetch`, the 1-second budget, and wide reads that conflict with every write ([research 07](../../research/07-code-inside-the-database.md)).

## Worth borrowing

- **Deterministic, sandboxed transaction functions.** One property buys retry, replay and subscriptions. Cost: no I/O inside a transaction, so effects move to a separate step, which in Mo could be its capabilities ([research 07](../../research/07-code-inside-the-database.md)). See [deterministic functions as transactions](../ideas/deterministic-functions-inside-transactions.md).
- **Conflict errors that name the other writer.** Cheap and easy for agents to read. Cost: recording who wrote what ([research 07](../../research/07-code-inside-the-database.md)).
- **Refusing a deploy that the stored data does not fit.** Cost: every breaking change needs a written migration ([research 07](../../research/07-code-inside-the-database.md)).
- **Read and write sets derived by a compiler instead of observed at run time** (the gap Convex leaves). Cost: the sets must be conservative, so a computed key widens to the whole table, which moves Convex's broad-conflict problem to compile time (inference, [research 07](../../research/07-code-inside-the-database.md)). See [read and write sets known up front](../ideas/read-and-write-sets-known-up-front.md).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 09: Agents and databases today](../../research/09-agents-and-databases-today.md)
- How Convex works: https://stack.convex.dev/how-convex-works
- Convex OCC: https://docs.convex.dev/database/advanced/occ
- Convex errors: https://docs.convex.dev/error
- Convex limits: https://docs.convex.dev/production/state/limits
- Convex schemas: https://docs.convex.dev/database/schemas
- Convex migrations: https://github.com/get-convex/migrations
