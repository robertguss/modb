# Writes that carry their assumptions

Each write states what the writer believed when it made the change, such as "room 5 is free at 10:00" or "this value is still 7". The database checks that belief when it applies the write, and rejects or reworks the write if the belief no longer holds ([research 06](../../research/06-divergent-copies-and-merging.md); [research 05](../../research/05-databases-that-keep-history.md)).

## What it is

The fullest form is [Bayou](../systems/bayou.md) (1995). Every write carries the update, a *dependency check* (a query plus the result the writer expects), and a *merge procedure* (code that produces an alternative write if the check fails, for example "book the next free slot") ([Bayou paper](https://www.cs.utexas.edu/~lorenzo/corsi/cs380d/papers/p172-terry.pdf); [research 06](../../research/06-divergent-copies-and-merging.md)).

Smaller forms of the same idea:

- **Compare-and-swap.** [Datomic](../systems/datomic.md)'s `:db/cas` aborts a transaction if a value is no longer what the writer expected; longer checks run as transaction functions inside the single writer ([transaction functions](https://docs.datomic.com/transactions/transaction-functions.html); [research 05](../../research/05-databases-that-keep-history.md)).
- **Predicates sent with the write.** [XTDB](../systems/xtdb.md) write transactions are not interactive, so a client cannot read, decide and write inside one. It sends `ASSERT` predicates instead, which roll the transaction back if false ([XTDB transactions](https://docs.xtdb.com/about/txs-in-xtdb.html); [research 05](../../research/05-databases-that-keep-history.md)).
- **Expected version.** In [KurrentDB](../systems/kurrentdb.md) each append names the *expected revision* of the stream; if another writer got there first, the store throws `WrongExpectedVersionException` and the writer retries ([Kurrent appending events](https://docs.kurrent.io/clients/node/v1.2/appending-events); [research 05](../../research/05-databases-that-keep-history.md)).
- **The operation itself, re-run.** [Zero](../systems/zero.md) re-runs each named write function on authoritative server state; research 06 calls it "Bayou's idea with the server as primary" ([research 06](../../research/06-divergent-copies-and-merging.md)).

## The problem it solves

Merges that are correct row by row but wrong in meaning. A cell-level merge reports success whenever no cell changed on both sides, so these pass cleanly (inference, [research 06](../../research/06-divergent-copies-and-merging.md)):

- **Two agents book the last seat.** Each inserts a different booking row: different keys, no conflict, capacity exceeded.
- **A row neither side wrote.** One branch moves a meeting's start, the other its end. The merge may produce a meeting that ends before it starts; [Dolt](../systems/dolt.md) catches it only if a check constraint was declared.
- **Stale reasoning.** Agent A reads prices and writes a discount table; agent B changes prices. No shared cell, so nothing flags that A's output came from data that no longer exists.

The common cause: the merge sees what was written, not what was read or assumed. Bayou's dependency check is the one mechanism research 06 found that records the assumption, so it can detect all three (inference, [research 06](../../research/06-divergent-copies-and-merging.md)).

Even the small form helps: an expected-version check turns overlapping work into a conflict an agent can see and retry ([research 05](../../research/05-databases-that-keep-history.md)).

## What it costs

- A guard per operation, and a database that stores and re-runs code ([research 06](../../research/06-divergent-copies-and-merging.md)).
- Hand-written check and merge code on every write, and reads that can show tentative data that later changes (Bayou) ([research 06](../../research/06-divergent-copies-and-merging.md)).
- An authority that orders the operations (Zero, Bayou) ([research 06](../../research/06-divergent-copies-and-merging.md)).
- The writer must state the assumption up front, which agents rarely do ([research 06](../../research/06-divergent-copies-and-merging.md)).
- The expected-version form is cheap: one integer per stream ([research 05](../../research/05-databases-that-keep-history.md)).

## Systems that use it

- [Bayou](../systems/bayou.md): dependency check plus merge procedure on every write.
- [Zero](../systems/zero.md): named mutators re-run on the server.
- [XTDB](../systems/xtdb.md): `ASSERT` predicates.
- [Datomic](../systems/datomic.md): `:db/cas` and transaction functions.
- [KurrentDB](../systems/kurrentdb.md): expected revision on append.

## Disagreements

- **Whether any general system enforces declared invariants across transactions.** Research 00 says only TigerBeetle enforces rich domain invariants and no general system lets users declare invariants that hold across transactions; it marks this as inference ([research 00](../../research/00-landscape-overview.md)). Research 05 describes Datomic transaction functions running checks on its single writer and XTDB `ASSERT` predicates that roll a transaction back ([research 05](../../research/05-databases-that-keep-history.md)); research 06 describes Dolt checking constraints over the merged result ([research 06](../../research/06-divergent-copies-and-merging.md)); research 04 lists TypeDB constraints in the schema ([research 04](../../research/04-models-that-lost-or-stayed-niche.md)). See [invariants the database enforces](invariants-the-database-enforces.md).
- **Whether anything merges by intent.** Research 00 says nobody merges by intent ([research 00](../../research/00-landscape-overview.md)). Research 06 describes Bayou's dependency checks and merge procedures as defining conflicts by meaning ([research 06](../../research/06-divergent-copies-and-merging.md)). See [merging by meaning](merging-by-meaning.md).

## Sources

- [research 06: Divergent copies and merging](../../research/06-divergent-copies-and-merging.md)
- [research 05: Databases that keep history](../../research/05-databases-that-keep-history.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 04: Models that lost or stayed niche](../../research/04-models-that-lost-or-stayed-niche.md)
- Bayou paper: https://www.cs.utexas.edu/~lorenzo/corsi/cs380d/papers/p172-terry.pdf
- Datomic transaction functions: https://docs.datomic.com/transactions/transaction-functions.html
- XTDB transactions: https://docs.xtdb.com/about/txs-in-xtdb.html
- Kurrent appending events: https://docs.kurrent.io/clients/node/v1.2/appending-events
- Zero mutators: https://zero.rocicorp.dev/docs/mutators
