# Code inside the database, and databases inside a language

Research run on 2026-11-13 by a subagent using Exa, for [issue 07](../issues/07-code-inside-the-database.md). Vendor claims are marked. Section 7 holds the three deep questions.

## 1. Stored procedures and triggers

- **For.** A *stored procedure* is a function stored and run inside the database server. A *trigger* is one the database runs automatically when a row changes. Both keep logic next to the data and save round trips.
- **Core idea.** The function runs inside the caller's transaction. PostgreSQL asks the author to label each function `VOLATILE`, `STABLE` or `IMMUTABLE`. The label is "a promise to the optimizer"; only non-volatile functions may be used in an index scan ([PG volatility](https://www.postgresql.org/docs/current/xfunc-volatility.html)).
- **Strength and its price.** Atomic with the data, with no round trips. The price is compute on the database server, the hardest part to scale (vendor opinion, [PingCAP](https://www.pingcap.com/blog/why-you-should-replace-stored-procedures-with-a-service-layer/)).
- **Weaknesses.** The database trusts the label; it does not check it. Triggers fire "in alphabetical order by trigger name". Cascades have "no direct limitation", and avoiding infinite recursion "is the trigger programmer's responsibility" ([PG triggers](https://www.postgresql.org/docs/current/trigger-definition.html)).
- **Overlap.** Whatever the host database does: locks or snapshots.
- **Agents.** A trigger is invisible at the call site, so an agent that writes one row cannot see what else will change.

## 2. Object prevalence and image persistence

- **For.** Prevayler (Java) keeps all business objects in RAM to avoid "all that database hassle" ([Skeptical FAQ](https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html)). A Smalltalk image saves a whole running world, code and objects, to one file. GemStone/S is a shared, transactional, persistent Smalltalk.
- **Core idea (Prevayler).** Each change is a serializable command, written to a journal (a *command log*) before it is applied. A periodic snapshot plus the journal rebuilds the state (FAQ). `execute()` guarantees "only one Transaction is executed at a time" ([API](https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html)).
- **Strength and its price.** No concurrency bugs inside the model, and queries are plain method calls. Three constraints pay for this:
  - all data fits in RAM;
  - every change is a command;
  - commands are deterministic, using the passed `executionTime` and never the clock, or replay diverges (API).
- **Weaknesses.**
  - Snapshots block writes while they run (API).
  - Transactions must be short "because they block the system", and long ones are "an open question" ([cl-prevalence](https://cl-prevalence.common-lisp.dev/)).
  - An image "does not work well if you have to share data between different applications" ([Seaside book](https://book.seaside.st/book/advanced/persistency/image-based-persistency)).
  - Weak collaboration has been "blamed for the limited commercial success of Smalltalk", and version control "cannot even comprehend schema change" ([arXiv 2110.08993](https://arxiv.org/pdf/2110.08993)).
- **GemStone overlap.** *Optimistic*: at commit it compares "your write set with those of all other transactions that committed since your transaction began". Reduced-conflict classes help where collisions are likely ([Transactions](https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/9-Transactions.htm)).
- **GemStone code and data together.** Each class keeps a *class history* of versions. Old instances "continue to access the old class's methods" until migrated, one, some or all at a time ([Class History](https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/11-ClassHistory.htm)).

## 3. Erlang: ETS and Mnesia

- **ETS.** An in-memory table owned by the process that created it. "When the process terminates, the table is automatically destroyed" unless an heir is named. Writes take "exclusive access" to the table by default ([ets](https://www.erlang.org/doc/apps/stdlib/ets.html)). Single operations are atomic; there are no transactions.
- **Mnesia.** A replicated database built on ETS, queried from Erlang. A transaction is an Erlang function (a "Fun") run under locks. "Since Mnesia detects deadlocks, a transaction can be restarted any number of times and therefore the Fun shall not have any side effects" ([mnesia](https://www.erlang.org/doc/apps/mnesia/mnesia.html)). A *deadlock* is two transactions each waiting for a lock the other holds.
- **Strength and its price.** Native terms and replication, paid for by transaction code that must be restartable, which the language does not enforce.
- **Weaknesses.**
  - After a network partition heals, Mnesia emits `inconsistent_database`. The default handler only logs an error, so recovery is the application's job ([chap. 7](https://www.erlang.org/doc/apps/mnesia/mnesia_chap7.html)).
  - Disk-only tables have a 2 GB limit ([secondary source](https://medium.com/@matheuscamarques/a-comparative-technical-analysis-of-riak-and-mnesia-for-distributed-erlang-systems-c59529df59bb)).
- **Agents.** A retried Fun that sends a message sends it twice, and nothing stops an agent from writing one.

## 4. Actor state stores

An *actor* is an object that handles one message at a time and owns its state.

- **Orleans.** Grains (actors) run turn by turn on a single-threaded scheduler. Writes carry an *ETag* (a version token); a stale one fails with `InconsistentStateException` "rather than overwriting a newer value" ([persistence](https://dotnet.github.io/orleans/docs/grains/grain-persistence/)). State survives code changes only by following serializer "version-tolerance" rules much like Protobuf's ([serialization](https://dotnet.github.io/orleans/docs/implementation/serialization/)).
- **Cloudflare Durable Objects.** Each object runs "in one single thread" with private SQLite storage "in the very same thread". The vendor says a query takes microseconds ([blog, 2024-09-26](https://blog.cloudflare.com/sqlite-in-durable-objects/)).
  - *Input gates* queue new events during synchronous work. *Output gates* hold replies until writes are durable.
  - "Awaiting async operations like `fetch()` … opens the input gate, allowing other requests to interleave" ([rules](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/)).
  - A Cloudflare "migration" renames or deletes classes; reshaping data is left to the developer ([glossary](https://developers.cloudflare.com/durable-objects/reference/glossary/)).
- **Akka Persistence.** *Event sourcing*: store the events that changed the actor and replay them on start. It rests on "the single-writer principle", because two live instances would interleave events ([Akka](https://doc.akka.io/libraries/akka-core/current/typed/persistence.html)). Events are "usually never deleted", so old events are translated by *event adapters* each time they are read ([schema evolution](https://doc.akka.io/libraries/akka-core/current/persistence-schema-evolution.html)).
- **Strength and its price.** No locks inside an entity. The price is that one object is the throughput ceiling, and no transaction spans two objects.
- **Agents.** The partition key must be chosen up front, and work that spans keys has no transaction.

## 5. Database as application server: Convex and SpacetimeDB

- **Convex core idea.** Queries and mutations are TypeScript functions run inside the database. Concurrency is *optimistic concurrency control* (OCC): take no locks, "record what each transaction reads and writes", and check for overlap at commit ([How Convex works](https://stack.convex.dev/how-convex-works)).
- **Convex retries.** On conflict, Convex discards the *write set* (everything written) and reruns the function. That is safe only because mutations are sandboxed: "this is why… `fetch` isn't available in mutations".
- **Convex subscriptions.** The *read set* (everything read) drives them: when data a query read changes, "the query is rerun".
- **Convex limits.**
  - A mutation that keeps conflicting fails after several retries. The error names the table, the other function and a document ID ([errors](https://docs.convex.dev/error)).
  - User code gets 1 second, and a transaction may write at most 16,000 documents ([limits](https://docs.convex.dev/production/state/limits)).
  - A deploy that changes the schema checks all existing documents, and the push fails if any do not match ([schemas](https://docs.convex.dev/database/schemas)).
  - Data migrations run "in batches asynchronously" through a library ([migrations](https://github.com/get-convex/migrations)).
- **SpacetimeDB reducers.** *Reducers* are its mutations. Each runs in a transaction and is "designed to be free of side effects" ([reducers](https://github.com/clockworklabs/SpacetimeDB/blob/master/docs/docs/00200-core-concepts/00200-functions/00300-reducers/00300-reducers.md)).
- **SpacetimeDB procedures.** Version 2.0 added *procedures*, which may call HTTP. Their transaction callback "may be invoked multiple times, possibly seeing a different version of the database state each time" ([procedures](https://spacetimedb.com/docs/functions/procedures/)). In C# they are still marked unstable.
- **SpacetimeDB migrations.** Republishing a module migrates additive changes automatically: new tables, new indexes, or columns added at the end with a default. Changing or removing columns "will cause the publish to fail" ([automatic](https://spacetimedb.com/docs/databases/automatic-migrations/)). Those changes need a hand-written migration ([incremental](https://spacetimedb.com/docs/databases/incremental-migrations/)).
- **Agents.** The most legible systems here: the function is the whole transaction, and conflicts come back named. The traps are hidden rules: no `fetch`, the 1-second budget, and wide reads that conflict with every write.

## 6. Incrementally maintained views: Materialize and differential dataflow

- **For.** Keep query results fresh as inputs change, without re-running the query (*incremental view maintenance*).
- **Core idea.** Each view compiles to a dataflow on Differential Dataflow, which processes changes as `(time, diff)` updates. An *arrangement* is the indexed history a dataflow keeps. Its memory is "roughly proportional to its number of distinct (data, time) pairs" ([arrangements](https://materialize.com/docs/fundamentals/concepts/arrangements/)).
- **Strength and its price.** Fresh, consistent results; in the default strict-serializable mode "time cannot go backwards" ([consistency](https://materialize.com/blog/strong-consistency-in-materialize/)). The price is memory for arrangements, plus views written in a restricted language the engine can differentiate.
- **Weaknesses.** Changing a view means building a replacement and *hydrating* it, that is computing it from scratch. This "briefly reduces freshness", and larger changes use blue/green deployments ([updating views](https://materialize.com/docs/transform-data/updating-materialized-views/)).
- **Agents.** Plain SQL helps, but memory cost stays invisible until it bites.

## 7. Going deeper

### 7a. What the database gains when it can see or constrain the code

Every gain traces back to **determinism** or **known reads and writes**.

- **Determinism lets the system run a function again.** Prevayler, Mo and Akka replay to rebuild state. Convex and Mnesia retry after conflicts. All of them state the side-effect rule, but only Convex and SpacetimeDB reducers enforce it, with a sandbox; the others rely on discipline.
- **Known reads and writes give three things:**
  1. conflict detection without locks (Convex, GemStone);
  2. exact subscriptions (Convex);
  3. scheduling before execution. The research system Calvin needs "advance knowledge of all transactions' read/write sets". When a set depends on data, it runs a "reconnaissance query" first and restarts if the guess was wrong ([Calvin, SIGMOD 2012](https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf)).
- **The gap.** Every system above learns read sets by watching code run, and PostgreSQL's labels go unchecked. A whole-program compiler could derive conservative read and write sets and check effects before anything runs. That is my inference; I found no production database that does it.

### 7b. What went wrong with stored procedures

One cause underlies the complaints: the code lived in the database but outside the software process.

- Procedures deploy separately from their callers, and the production version "often doesn't match what's in version control" (vendor opinion, PingCAP).
- "There's no pure SQL unit testing framework", and debugging tools were "just not there" ([practitioner, 2026-03](https://withblue.ink/2026/03/business-logic-does-not-belong-in-the-database)).
- Portability is lost ([practitioner](https://phil.lavin.me.uk/2013/03/why-i-dont-like-database-stored-proceedures/)).
- The work lands on the most expensive server.

Convex and SpacetimeDB fix the first three. Their functions live in the application repository, in a general language, and deploy together with the schema. Nothing fixes the fourth.

### 7c. Changing code and stored data together

| System | When code changes, stored data… |
|---|---|
| PostgreSQL | changes through separate migration scripts |
| GemStone | keeps old class versions; instances migrate when asked |
| Prevayler | sits in a journal of serialized commands that new classes must still read (my inference) |
| Orleans | must stay readable under serializer tolerance rules |
| Akka | is never rewritten; adapters translate it on every read |
| Convex | is checked at deploy; a mismatch blocks the deploy |
| SpacetimeDB | migrates if the change is additive; otherwise the publish fails |
| Materialize | is recomputed from inputs |
| **Mo** | goes through a typed migration once. One SQLite transaction writes a snapshot at the head and deletes the log tail; "restart never reruns the migration" (`~/code/mo/docs/design/upgrades.md`, lines 18–19, 118–119) |

Mo's upgrade snapshot already avoids replaying old commands through new code.

## Table

| System | Strength | What pays for it | Weakness |
|---|---|---|---|
| Stored procedures, triggers | Logic atomic with data | Compute on the least scalable server | Unversioned, untested, hidden cascades; labels unchecked |
| Prevayler | No concurrency bugs; queries are method calls | RAM only, one writer, deterministic commands | Snapshots block; long transactions unsolved |
| Smalltalk image, GemStone | Code and objects together; per-instance migration | Image-only tooling; optimistic conflicts | Weak collaboration; version control blind to schema |
| ETS, Mnesia | Native terms, replication | Restartable Funs by convention | Partitions left to the application |
| Orleans, Durable Objects, Akka | No locks per entity; local storage | One thread per object; single writer | No cross-object transactions; `await` interleaves |
| Convex | Retryable transactions, exact subscriptions, deploy-time check | Sandbox: no I/O, 1 s budget | Hot spots fail after retries; wide reads conflict |
| SpacetimeDB | Automatic additive migration | Side-effect-free reducers | Breaking changes refused; procedure transactions rerun |
| Materialize | Always-fresh, consistent views | Memory; SQL-only views | Changing a view means rehydrating |

## Ideas worth borrowing

- **Deterministic, sandboxed transaction functions (Convex).** One property buys retry, replay and subscriptions. Cost: no I/O inside a transaction, so effects move to a separate step, which could be Mo's capabilities.
- **Read and write sets derived by the compiler (the gap in 7a).** Cost: the sets must be conservative, so a computed key widens to the whole table, which is Convex's broad-conflict problem moved to compile time.
- **Conflict errors that name the other writer (Convex).** Cheap, and easy for agents to read. Cost: recording who wrote what.
- **Refuse a deploy the stored data does not fit (Convex, SpacetimeDB, Mo).** Cost: every breaking change needs a written migration.
- **Snapshot at the upgrade boundary (Mo).** Avoids event adapters. Cost: old history survives only in retained snapshots.
- **Reply only after the write is durable (Durable Objects' output gates, Mo).** Cost: latency on every write.

## What I could not confirm

- Founding dates, from memory only: stored procedures (1980s), GemStone (1980s), Mnesia (late 1990s), Prevayler (about 2002), Akka Persistence (about 2014), Orleans open source (about 2015), Convex (about 2022), Materialize (about 2019), Differential Dataflow (2013).
- Mnesia's 2 GB disk-table limit; my only source is secondary.
- Whether SpacetimeDB runs reducers one at a time. Its docs say only that reducers "don't see changes from other concurrent reducers".
- Whether any system derives read and write sets statically from a general-purpose language. I searched only briefly.
- Durable Objects' throughput per object; I found no current official figure.
- How Prevayler handles class changes in an existing journal.
