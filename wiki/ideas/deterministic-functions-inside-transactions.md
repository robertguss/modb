# Deterministic functions as transactions

The transaction is a function that the database itself runs, and the function must give the same result every time it runs on the same data. Because it has no side effects, the database can run it again whenever it needs to: after a conflict, during replay, or to refresh a subscription ([research 07](../../research/07-code-inside-the-database.md)).

## What it is

The client does not open a transaction and send statements one by one. It names a function, and the database runs the whole function as one transaction. The function may read and write data but may not touch the outside world, such as the network or the clock, because a second run would then behave differently ([research 07](../../research/07-code-inside-the-database.md)).

## The problem it solves

Every gain research 07 found traces back to **determinism** or **known reads and writes** ([research 07](../../research/07-code-inside-the-database.md)):

- **Determinism lets the system run a function again.** [Prevayler](../systems/prevayler.md), Mo and Akka Persistence replay commands to rebuild state. [Convex](../systems/convex.md) and [Mnesia](../systems/mnesia.md) retry a transaction after a conflict.
- **Knowing what a function read and wrote gives three things:**
  1. conflict detection without locks (Convex, [GemStone](../systems/gemstone.md));
  2. exact subscriptions: Convex re-runs a query when anything it read changes;
  3. scheduling before execution. The research system Calvin needs "advance knowledge of all transactions' read/write sets"; when a set depends on data, it runs a "reconnaissance query" first and restarts if the guess was wrong ([Calvin, SIGMOD 2012](https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf)). See [read and write sets known up front](read-and-write-sets-known-up-front.md).

It also moves retries inside the database. In ordinary serializable databases the engine returns an error and the application or its client library replays the transaction; an agent must then replay the *whole* transaction, re-reading data, and re-run its reasoning if that depended on what it read (inference, [research 01](../../research/01-relational-and-transactional.md)).

In sync engines the same idea appears as merging by re-running the operation. [Zero](../systems/zero.md) runs each named write function on the client and again, authoritatively, on the server, then re-runs pending ones on top of server state ([Zero mutators](https://zero.rocicorp.dev/docs/mutators)). [Bayou](../systems/bayou.md)'s merge procedures are code the server re-runs when a write's check fails ([research 06](../../research/06-divergent-copies-and-merging.md)).

## What it costs

- **No I/O inside a transaction.** Convex removes `fetch` from mutations for exactly this reason ([How Convex works](https://stack.convex.dev/how-convex-works)). Effects must move to a separate step, which in Mo could be its capabilities ([research 07](../../research/07-code-inside-the-database.md)).
- **Enforcement, or discipline.** Every system states the side-effect rule, but only Convex and SpacetimeDB reducers enforce it, with a sandbox; the others rely on discipline ([research 07](../../research/07-code-inside-the-database.md)). A retried Mnesia Fun that sends a message sends it twice ([research 07](../../research/07-code-inside-the-database.md)). Prevayler commands must use the `executionTime` passed in and never the clock, or replay diverges ([Prevayler API](https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html)).
- **Budgets.** Convex gives user code 1 second and caps a transaction at 16,000 written documents ([Convex limits](https://docs.convex.dev/production/state/limits)).
- **Wide reads conflict with every write** ([research 07](../../research/07-code-inside-the-database.md)).
- **The code is opaque to the database.** It runs general-purpose languages, so it cannot analyse the code's reads, writes and effects to plan, verify or migrate it (inference, [research 00](../../research/00-landscape-overview.md)). Every system learns read sets by watching code run. A whole-program compiler could derive conservative read and write sets and check effects before anything runs; research 07 found no production database that does (inference, [research 07](../../research/07-code-inside-the-database.md)).

## Systems that use it

- [Convex](../systems/convex.md): deterministic TypeScript queries and mutations, sandboxed, retried on conflict ([research 07](../../research/07-code-inside-the-database.md)).
- [SpacetimeDB](../systems/spacetimedb.md): reducers "designed to be free of side effects" ([reducers](https://github.com/clockworklabs/SpacetimeDB/blob/master/docs/docs/00200-core-concepts/00200-functions/00300-reducers/00300-reducers.md)).
- [Erlang ETS and Mnesia](../systems/mnesia.md): a transaction is a Fun that "shall not have any side effects" because it may be restarted ([mnesia](https://www.erlang.org/doc/apps/mnesia/mnesia.html)).
- [Prevayler](../systems/prevayler.md): deterministic commands replayed from a journal ([research 07](../../research/07-code-inside-the-database.md)).
- [Datomic](../systems/datomic.md): transaction functions run inside the single writer, the transactor ([transaction functions](https://docs.datomic.com/transactions/transaction-functions.html); [research 04](../../research/04-models-that-lost-or-stayed-niche.md); [research 05](../../research/05-databases-that-keep-history.md)).
- [Zero](../systems/zero.md): named mutators re-run on the server ([research 06](../../research/06-divergent-copies-and-merging.md)).

For contrast, [GemStone](../systems/gemstone.md) cannot re-run a failed commit: "you must abort the transaction in order to get a new view" ([GemStone guide](https://downloads.gemtalksystems.com/docs/GemStone64/3.6.x/GS64-ProgGuide-3.6.pdf); [research 04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Cannot be combined with

- **Calls to the outside world inside the transaction.** SpacetimeDB 2.0's procedures may call HTTP, and the price is that their transaction callback "may be invoked multiple times, possibly seeing a different version of the database state each time" ([procedures](https://spacetimedb.com/docs/functions/procedures/)).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 04: Models that lost or stayed niche](../../research/04-models-that-lost-or-stayed-niche.md)
- [research 05: Databases that keep history](../../research/05-databases-that-keep-history.md)
- [research 06: Divergent copies and merging](../../research/06-divergent-copies-and-merging.md)
- [research 01: Relational and transactional](../../research/01-relational-and-transactional.md)
- How Convex works: https://stack.convex.dev/how-convex-works
- Calvin: https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf
