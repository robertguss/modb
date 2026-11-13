# Code inside the database, and databases inside a language

Systems where application code and stored data live in the same place: either the database runs the application's functions, or a programming language's own objects are made durable and become the database ([research 07](../../research/07-code-inside-the-database.md); [research 00](../../research/00-landscape-overview.md)).

## What they are for

- **Removing the app tier.** [Convex](../systems/convex.md) and [SpacetimeDB](../systems/spacetimedb.md) remove the separate application server, the ORM and cache invalidation ([research 00](../../research/00-landscape-overview.md)).
- **Avoiding the database altogether.** [Prevayler](../systems/prevayler.md) keeps all business objects in RAM to avoid "all that database hassle" ([Prevayler FAQ](https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html)).
- **Native storage for a language.** [Erlang ETS and Mnesia](../systems/mnesia.md) store native Erlang terms and replicate them ([research 07](../../research/07-code-inside-the-database.md)).
- **State next to the code that owns it.** Actor stores such as [Cloudflare Durable Objects](../systems/cloudflare-durable-objects.md) give each object private storage in its own thread ([research 07](../../research/07-code-inside-the-database.md)).
- **Results kept fresh.** [Materialize](../systems/materialize.md) keeps query results up to date as inputs change ([research 07](../../research/07-code-inside-the-database.md)).
- **Logic atomic with the data.** [Stored procedures and triggers](../ideas/stored-procedures-and-triggers.md) are the oldest form ([research 07](../../research/07-code-inside-the-database.md)).

## Members

- [Convex](../systems/convex.md): deterministic TypeScript functions as transactions, optimistic concurrency, subscriptions from read sets.
- [SpacetimeDB](../systems/spacetimedb.md): side-effect-free reducers in Wasm or V8 modules; automatic additive migrations.
- [Prevayler](../systems/prevayler.md): all objects in RAM, every change a journaled deterministic command, one transaction at a time.
- [Erlang ETS and Mnesia](../systems/mnesia.md): process-owned tables, and transactions that are restartable Erlang functions.
- [Cloudflare Durable Objects](../systems/cloudflare-durable-objects.md): single-threaded actors with SQLite in the same thread.
- [Materialize](../systems/materialize.md): incrementally maintained views on Differential Dataflow.
- [GemStone](../systems/gemstone.md), described here in research 07 and with object databases in research 04: a shared, transactional, persistent Smalltalk with optimistic commits and per-instance class migration.

Mentioned only:

- Smalltalk images: save a whole running world, code and objects, to one file; this "does not work well if you have to share data between different applications" ([Seaside book](https://book.seaside.st/book/advanced/persistency/image-based-persistency); [research 07](../../research/07-code-inside-the-database.md)).
- Orleans: actors (grains) run turn by turn; writes carry an ETag, and a stale one fails "rather than overwriting a newer value" ([Orleans persistence](https://dotnet.github.io/orleans/docs/grains/grain-persistence/); [research 07](../../research/07-code-inside-the-database.md)).
- Akka Persistence: event-sourced actors resting on "the single-writer principle"; old events are translated by adapters on every read ([Akka](https://doc.akka.io/libraries/akka-core/current/typed/persistence.html); [research 07](../../research/07-code-inside-the-database.md)).
- Calvin: a research system that needs "advance knowledge of all transactions' read/write sets" and runs a "reconnaissance query" when they depend on data ([Calvin](https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf); [research 07](../../research/07-code-inside-the-database.md)).
- Differential Dataflow: the engine Materialize compiles views to, processing changes as `(time, diff)` updates ([research 07](../../research/07-code-inside-the-database.md)).
- Timely Dataflow: incremental, iterative data processing, cited for the stream and incremental-view family ([CACM](https://cacm.acm.org/research/incremental-iterative-data-processing-with-timely-dataflow/); [research 00](../../research/00-landscape-overview.md)).
- cl-prevalence: a Common Lisp prevalence library whose docs say transactions must be short and long ones are "an open question" ([cl-prevalence](https://cl-prevalence.common-lisp.dev/); [research 07](../../research/07-code-inside-the-database.md)).
- Mo: its typed migration writes a snapshot at the head in one SQLite transaction, so "restart never reruns the migration" (`~/code/mo/docs/design/upgrades.md`; [research 07](../../research/07-code-inside-the-database.md)).

## Shared tradeoffs

**Determinism or known reads and writes pay for every gain** ([research 07](../../research/07-code-inside-the-database.md)).

- Determinism lets the system run a function again: Prevayler, Mo and Akka replay; Convex and Mnesia retry. All state the side-effect rule, but only Convex and SpacetimeDB reducers enforce it with a sandbox; the rest rely on discipline. See [deterministic functions as transactions](../ideas/deterministic-functions-inside-transactions.md).
- Known reads and writes give conflict detection without locks (Convex, GemStone), exact subscriptions (Convex), and scheduling before execution (Calvin). See [read and write sets known up front](../ideas/read-and-write-sets-known-up-front.md) and [query results kept fresh as data changes](../ideas/continuously-updated-query-results.md).
- **The gap.** Every system learns read sets by watching code run, and PostgreSQL's volatility labels go unchecked. A whole-program compiler could derive conservative read and write sets and check effects before anything runs; research 07 found no production database that does (inference). Research 00 makes the same point: in-database code is opaque to the database (inference, [research 00](../../research/00-landscape-overview.md)).

**One thread or one writer per unit, and no transaction across units.** Prevayler runs one transaction at a time; Durable Objects, Orleans and Akka give no locks per entity, but one object is the throughput ceiling and no transaction spans two objects ([research 07](../../research/07-code-inside-the-database.md)). See [one writer at a time](../ideas/one-writer-at-a-time.md).

**Code and stored data change together, or not at all** ([research 07](../../research/07-code-inside-the-database.md)):

| System | When code changes, stored data… |
|---|---|
| PostgreSQL | changes through separate migration scripts |
| GemStone | keeps old class versions; instances migrate when asked |
| Prevayler | sits in a journal of serialized commands that new classes must still read (inference) |
| Orleans | must stay readable under serializer tolerance rules |
| Akka | is never rewritten; adapters translate it on every read |
| Convex | is checked at deploy; a mismatch blocks the deploy |
| SpacetimeDB | migrates if the change is additive; otherwise the publish fails |
| Materialize | is recomputed from inputs |
| Mo | goes through a typed migration once, with a snapshot written at the head |

**Old stored-procedure complaints, mostly fixed.** Stored procedures failed because the code lived in the database but outside the software process: deployed separately, hard to test, not portable, and run on the most expensive server. Convex and SpacetimeDB fix the first three by keeping functions in the application repository and deploying them with the schema; nothing fixes the fourth ([research 07](../../research/07-code-inside-the-database.md)).

**For agents.** Convex and SpacetimeDB are the most legible: the function is the whole transaction, and conflicts come back named. The traps are hidden rules (no `fetch`, a 1-second budget, wide reads that conflict with every write), invisible trigger cascades, Mnesia Funs that send messages twice on retry, and partition keys chosen up front ([research 07](../../research/07-code-inside-the-database.md)).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- How Convex works: https://stack.convex.dev/how-convex-works
- SpacetimeDB docs: https://spacetimedb.com/docs/databases/
- SQLite in Durable Objects: https://blog.cloudflare.com/sqlite-in-durable-objects/
