# FoundationDB

FoundationDB is an ordered key-value store with transactions across keys. Other data models are built on top of it as "layers", and the whole database is tested by running a simulated cluster from a single random seed ([FoundationDB paper](https://www.foundationdb.org/files/fdb-paper.pdf); [research 08](../../research/08-correctness-first-databases.md)).

## What it is for

One small, heavily tested transactional core on which other data models are built. The core "provides no indexing and never will"; data models are stateless layers on top, such as the Record Layer ([layer concept](https://apple.github.io/foundationdb/layer-concept.html); [Record Layer](https://www.foundationdb.org/blog/announcing-record-layer/); [research 00](../../research/00-landscape-overview.md)). It was described at SIGMOD 2021; the company began earlier, but research 08 could not confirm the start year.

## Core idea

The simulator came before the database: FoundationDB "is validated with a deterministic simulation framework that productively fuzzes faults against a specification" ([paper](https://www.foundationdb.org/files/fdb-paper.pdf)).

The code is written in Flow, an extension of C++ with actors (small concurrent tasks scheduled by Flow's own runtime). The network, disk, time and random numbers are all reached through interfaces, so "an entire FoundationDB cluster" runs "within a single-threaded process" ([testing](https://apple.github.io/foundationdb/testing.html)). "Multithreaded concurrency is avoided (instead, one database node is deployed per core)" ([paper](https://www.foundationdb.org/files/fdb-paper.pdf)). See [deterministic simulation testing](../ideas/deterministic-simulation-testing.md).

## Strengths and what pays for each

- **Any failure replays from its seed.** Paid for by: a custom language and runtime, and no threads ([research 08](../../research/08-correctness-first-databases.md)).
- **Rare bugs become common.** BUGGIFY marks lines of code that misbehave on purpose, only in simulation. For each seed a random subset is switched on, each firing 5% of the time ([BUGGIFY](https://transactional.blog/simulation/buggify)). Paid for by: developers writing those hostile paths into the product code by hand.
- **A great deal of testing.** Tens of thousands of simulations run every night, about "one trillion CPU-hours" equivalent in total ([testing](https://apple.github.io/foundationdb/testing.html)). The fake clock runs about 10 times faster than real time. *Swarm testing* (each run picks random cluster sizes, workloads and faults) adds variety. A `TEST(cond)` macro counts how many runs reached a rare condition ([paper](https://www.foundationdb.org/files/fdb-paper.pdf)). Paid for by: compute.
- **One verified transactional core, many data models as layers.** Paid for by: the core has no data model and no indexing of its own ([research 00](../../research/00-landscape-overview.md)).

## Weaknesses

Stated by its authors ([paper](https://www.foundationdb.org/files/fdb-paper.pdf)):

- Simulation cannot reliably detect "performance issues".
- It cannot test code "not implemented in Flow", so the team "largely avoided taking dependencies".
- Some bugs came from the operating system's contract being "weaker than it was believed to be": the simulated disk obeys the contract its authors believed.

Transactions may not run "for over five seconds" or exceed 10 MB ([known limitations](https://apple.github.io/foundationdb/known-limitations.html)).

A rewrite of CouchDB on FoundationDB ended in 2022 when its sponsor stopped funding it ([dev list](https://lists.apache.org/thread/9gby4nr209qc4dzf2hh6xqb0cn1439b7); [research 03](../../research/03-key-value-document-distributed.md)).

## Overlapping work

Optimistic concurrency: a transaction reads a snapshot and is rejected at commit if someone else changed what it read, and the client retries ([paper](https://www.foundationdb.org/files/fdb-paper.pdf)). See [optimistic concurrency](../ideas/optimistic-concurrency.md).

## What an agent struggles with

The five-second limit, since agents hold transactions open while the model thinks ([SAO workshop paper](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf); [research 08](../../research/08-correctness-first-databases.md)). See [transaction time limits](../ideas/transaction-time-limits.md).

## Worth borrowing

- **BUGGIFY-style hooks and `TEST()` coverage counters.** Cost: product code carries test-only branches ([research 08](../../research/08-correctness-first-databases.md)).
- **Client-side BUGGIFY.** It makes the client "randomly throw errors that an application might see in production", to test the application's error handling ([client testing](https://apple.github.io/foundationdb/client-testing.html)). Research 00 calls it a partial exception to simulation protecting only the vendor; research 08 notes it does not replay the application deterministically. See [simulating the user's own workload](../ideas/simulating-the-users-own-workload.md).

## Disagreements

- **Evidence that agents hold transactions open.** Research 08 cites a 2026 workshop paper saying agents hold transactions open while waiting for the model ([research 08](../../research/08-correctness-first-databases.md)); research 09 cites the same paper ([research 09](../../research/09-agents-and-databases-today.md)). Research 01 says it found no study of agents holding transactions open and marks its agent section as reasoning ([research 01](../../research/01-relational-and-transactional.md)).

## Sources

- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 03: Key-value, document and distributed](../../research/03-key-value-document-distributed.md)
- FoundationDB paper: https://www.foundationdb.org/files/fdb-paper.pdf
- Testing: https://apple.github.io/foundationdb/testing.html
- Client testing: https://apple.github.io/foundationdb/client-testing.html
- Known limitations: https://apple.github.io/foundationdb/known-limitations.html
- Layer concept: https://apple.github.io/foundationdb/layer-concept.html
- Record Layer: https://www.foundationdb.org/blog/announcing-record-layer/
- BUGGIFY: https://transactional.blog/simulation/buggify
- SAO workshop paper: https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf
- CouchDB dev list: https://lists.apache.org/thread/9gby4nr209qc4dzf2hh6xqb0cn1439b7
