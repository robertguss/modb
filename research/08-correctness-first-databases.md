Research run on 2026-11-13 by a subagent using Exa, for the ticket [Correctness-first databases](../issues/08-correctness-first-databases.md). Section 9 compares with Mo and is the researcher's inference, drawn from `~/code/mo/docs/agent-guide.md`. Vendor claims are marked.

# Correctness-first databases: how they get it and what it costs (researched 2026-11-13)

**Deterministic simulation testing (DST)** runs the real program in a fake world (clock, network, disk) where every choice comes from one number, the **seed**, so a seed replays its run exactly. **Fault injection** means the test causes crashes, lost messages and bad disks on purpose.

## 1. FoundationDB

- **For what, when, why.** An ordered key-value store with transactions across keys. It was described at SIGMOD 2021; the company began earlier (start year not confirmed). The simulator came before the database: FoundationDB "is validated with a deterministic simulation framework that productively fuzzes faults against a specification" https://www.foundationdb.org/files/fdb-paper.pdf.
- **Core idea.** The code is written in Flow, an extension of C++ with actors (small concurrent tasks scheduled by Flow's own runtime). The network, disk, time and random numbers are all reached through interfaces, so "an entire FoundationDB cluster" runs "within a single-threaded process" https://apple.github.io/foundationdb/testing.html. "Multithreaded concurrency is avoided (instead, one database node is deployed per core)" (paper).
- **Strengths, and what pays for each.**
  - Any failure replays from its seed. *Paid for by* a custom language and runtime, and no threads.
  - Rare bugs become common. BUGGIFY marks lines of code that misbehave on purpose, only in simulation. For each seed a random subset is switched on, each firing 5% of the time https://transactional.blog/simulation/buggify. *Paid for by* the developers writing those hostile paths into the product code by hand.
  - A lot of testing. Tens of thousands of simulations run every night, about "one trillion CPU-hours" equivalent in total (testing.html). The fake clock runs about 10 times faster than real time. **Swarm testing** (each run picks random cluster sizes, workloads and faults) adds variety. A `TEST(cond)` macro counts how many runs reached a rare condition (paper). *Paid for by* compute.
- **Weaknesses, stated by its authors.** Simulation cannot reliably detect "performance issues" or test code "not implemented in Flow", so the team "largely avoided taking dependencies". Some bugs came from the operating system's contract being "weaker than it was believed to be" (paper).
- **Many clients.** Optimistic concurrency: a transaction reads a snapshot and is rejected at commit if someone else changed what it read, and the client retries (paper). Transactions may not run "for over five seconds" or exceed 10 MB https://apple.github.io/foundationdb/known-limitations.html.
- **What an agent would struggle with.** The five-second limit, since agents hold transactions open while the model thinks https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf.
- **Borrow:** BUGGIFY-style hooks and `TEST()` coverage counters. *Cost:* product code carries test-only branches.

## 2. TigerBeetle

- **For what, when, why.** A ledger database (accounts and debit/credit transfers); start year not confirmed. Transfers concentrate on a few hot accounts, so they contend whatever you do https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md.
- **Core idea.** A fixed schema, one thread, and no memory allocated after startup. It sizes all memory from command-line arguments at startup and never allocates again (ARCHITECTURE.md).
- **Strengths, and what pays for each.**
  - The **VOPR** simulator runs a whole cluster on one thread, injects network, disk and process faults, and speeds time up. It is "deterministic based on a seed number and the Git commit" https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md. It runs "24/7 on 1024 cores" https://docs.tigerbeetle.com/concepts/safety/. *Paid for by* stubbing out "the clock, network, and disk" (vopr.md), and by one thread.
  - Static allocation "designs away memory fragmentation, out-of-memory errors and use-after-frees" (safety page). *Paid for by* fixed limits chosen at startup, and by giving up a general-purpose data model.
- **Weaknesses.** Jepsen (an independent tester, section 4) found that queries with several filters "often omitted results, even in healthy clusters". The client "does not time out", and killing one node raised client latency "by three to five orders of magnitude" https://jepsen.io/analyses/tigerbeetle-0.16.11. TigerBeetle's own analysis: the query bug "only occurs when there are multiple iterators and one of them probes the other". The four fuzzers that ran queries never produced that case, a "blind spot" in their generated workload https://tigerbeetle.com/blog/2025-06-06-fuzzer-blind-spots-meet-jepsen/. After fixes, Jepsen found it consistent with **strong serializability** (every transaction appears to happen at one instant, in real-time order) through crashes, partitions, clock errors and disk corruption (Jepsen report).
- **Many clients.** Batched requests run one after another on the one thread, with no locks (ARCHITECTURE.md).
- **Agents would struggle with** its fixed schema: only accounts and transfers.
- **Borrow:** fixed limits allocated at startup. *Cost:* every limit becomes a user-visible setting.

## 3. SQLite

- **For what, when, why.** An embedded SQL database: a library inside the application, with no server (first released 2000-08-17) https://www.sqlite.org/chronology.html.
- **Core idea.** Exhaustive testing rather than simulation. The library is about 155.8 thousand lines; the project has "590 times as much test code" https://www.sqlite.org/testing.html.
- **Strengths, and what pays for each.**
  - **100% MC/DC coverage** (each condition in each branch shown to change the outcome on its own; an avionics standard) from the TH3 harness. *Paid for by* TH3 being proprietary and huge: about 248.5 million test runs before a release https://www.sqlite.org/th3.html.
  - Crash tests use an in-memory file system that snapshots after N writes, damages the files as a power loss would, then checks the database; the loop moves N forward each time. Out-of-memory and I/O-error tests work the same way (testing.html). *Paid for by* all I/O going through one replaceable interface (the VFS).
- **Weaknesses / many clients.** One writer at a time https://sqlite.org/isolation.html.
- **Agents would struggle with** busy errors when several write at once.
- **Borrow:** the moving crash point. *Cost:* every write must be a countable step.

## 4. Jepsen: what breaks most often

Jepsen is a tester, not a database. It runs real clusters under partitions, crashes and clock skew, records every operation, and checks that history against the consistency model the vendor claims. Recurring findings:

- **The documentation promises more than the system gives.** MySQL's "Repeatable Read" allows lost updates https://jepsen.io/analyses/mysql-8.0.34. Amazon RDS for PostgreSQL clusters violate **snapshot isolation** (each transaction sees one consistent past moment), showing "Long Fork" even when healthy (2025-04-29) https://jepsen.io/analyses/amazon-rds-for-postgresql-17.4.
- **Acknowledged writes are lost.** A write is confirmed, then gone https://jepsen.io/consistency/phenomena/lost-write. The usual cause is acknowledging before **fsync** (the call that forces data from memory onto disk). NATS JetStream fsyncs "only once every two minutes, but acknowledges messages immediately". Simulated power failures lost 131,418 of 930,005 messages (2025-12-08) https://jepsen.io/analyses/nats-2.12.1.
- **Bugs appear without faults.** MariaDB Galera Cluster allowed lost updates "even in healthy clusters" and appeared "weaker than Read Uncommitted" https://jepsen.io/analyses/mariadb-galera-cluster-12.1.2. TigerBeetle's query bug also needed no faults.

Its cost: testing from outside, it cannot replay a run exactly.

## 5. Antithesis and simulation as a service

Antithesis runs ordinary, nondeterministic software inside a **deterministic hypervisor** (a virtual machine whose every source of randomness is controlled), so the code needs no rewrite https://antithesis.com/docs/resources/deterministic_simulation_testing/ https://antithesis.com/blog/deterministic_hypervisor/. The whole system, "including dependencies like Kafka and Postgres", runs "on a single CPU core" https://antithesis.com/product/. Each event can branch into alternate timelines, and one run often finds many timelines where a bug triggered https://antithesis.com/docs/introduction/how_antithesis_works/. The cost: a paid outside service, and the properties are still yours to write.

Workers IO makes a similar claim (vendor, unverified) https://workers.io/.

## 6. Formal methods on real databases

**TLA+** is a language for describing a system's design as states and steps. A **model checker** explores every interleaving of a small instance and reports the shortest path to a violated property.

- **Amazon, 2015.** On DynamoDB's replication, 939 lines of TLA+ "found three bugs requiring traces of up to 35 steps". The worst could lose data, and had "passed unnoticed through extensive design reviews, code reviews, and testing" https://cacm.acm.org/research/how-amazon-web-services-uses-formal-methods/.
- **Amazon, 2025.** AWS now favours **P**, which models designs as communicating state machines familiar to its engineers, used on S3, EBS, DynamoDB, MemoryDB and Aurora. PObserve checks production logs against the P specification. AWS also uses deterministic simulation (open-source Rust tools shuttle and turmoil) https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/.
- **MongoDB** tried to check that real server traces matched its TLA+ spec. "This whole experiment failed. Our traces never matched our specification." Generating tests from the spec did work for a smaller algorithm https://vldb.org/pvldb/vol13/p1346-davis.pdf https://www.mongodb.com/company/blog/engineering/conformance-checking-at-mongodb-testing-our-code-matches-our-tla-specs.
- CockroachDB https://www.cockroachlabs.com/blog/parallel-commits/ and Azure Cosmos DB https://github.com/Azure/azure-cosmos-tla also publish TLA+ specifications.

The recurring cost: the specification is a second program that must be kept matched to the code.

## 7. What deterministic simulation demands of a language and runtime

Every source says the same four things must be controlled: **time, randomness, I/O, and scheduling** (which task runs next) https://antithesis.com/docs/resources/deterministic_simulation_testing/ https://guidobattiston.com/posts/dst-go/.

1. **No threads, or a scheduler the test owns.** FoundationDB and TigerBeetle avoid threads entirely. In Go, goroutines are scheduled by the runtime onto OS threads, "giving up your scheduling control to not one, but two external actors". Polar Signals had to force their Go database onto one thread, then wrote their Rust system from scratch to "claim the responsibility of full control" https://www.polarsignals.com/blog/posts/2025/07/08/dst-rust.
2. **Every I/O call through a replaceable interface**, including the clock and random numbers.
3. **No hidden nondeterminism.** Rust's `HashMap` randomizes its iteration order. S2 could seed its own maps, "but our dependencies..?" https://s2.dev/blog/dst.md. In one Rust project, forgetting one of the two build switches silently "falls back to real tokio without an error" https://nautilustrader.io/docs/latest/concepts/dst/.
4. **Few dependencies.** Code outside the controlled runtime cannot be simulated (FoundationDB paper).

Retrofitting is hard, which is why Antithesis works at the hypervisor level. A language with these rules built in is the alternative.

## 8. Bugs simulation finds, and bugs it misses

**It finds:** long chains of faults and recoveries, like DynamoDB's 35-step trace but in real code; bugs that "take time to play out", which a fake clock skips (FoundationDB paper); and races that a seed can replay but real runs cannot.

**It misses:**
- Performance and liveness. **Liveness** means the system eventually makes progress. TigerBeetle's latency collapse was found by Jepsen, not the VOPR.
- Workload blind spots. The generator never produced the query shape that failed.
- Wrong beliefs about the operating system: the simulated disk obeys the contract its authors believed (FoundationDB paper).
- Code outside the runtime.

## 9. Simulation of the user's own workload

No database I found offers it as a full feature. The closest:
- FoundationDB's client-side BUGGIFY makes the client "randomly throw errors that an application might see in production", to test the application's error handling https://apple.github.io/foundationdb/client-testing.html. It does not replay the application deterministically.
- Temporal (a durable-execution engine, not a database) lets users replay recorded workflow histories against new code, and run tests with skipped time https://docs.temporal.io/develop/python/testing-suite.
- Antithesis sells it as a service, outside the database.

**Comparison with Mo (inference).** Mo already meets section 7 for services, which handle one message at a time. `mo test` generates call sequences, advances a fake clock, crashes and restarts "through the real log and snapshot path backed by an in-memory store", checks promises after every step, and shrinks failures; `--strength` counts how many wrong versions the checks catch (`~/code/mo/docs/agent-guide.md`, lines 15, 17, 49). Missing compared with FoundationDB and TigerBeetle: disk faults (torn or corrupt writes, a lying fsync); networking ("Simulation still provides no networking", line 25); BUGGIFY-style hooks; coverage counters for rare conditions; and a check that the underlying store keeps its contract. The last matters because the check runs on an in-memory store, not SQLite.

## Summary table

| System | Strength | What pays for it | Weakness |
|---|---|---|---|
| FoundationDB | Whole cluster replayable from a seed; ~1 trillion CPU-hours simulated | Custom C++ dialect (Flow), no threads, few dependencies, BUGGIFY code in product | Blind to performance and to OS contracts; 5 s / 10 MB transactions |
| TigerBeetle | No allocation bugs; VOPR on 1,024 cores; strong serializability confirmed by Jepsen | One thread, fixed schema, fixed limits at startup | Fuzzer blind spot missed a query bug; client never times out |
| SQLite | 100% MC/DC; crash and I/O-error loops | 590× test code; proprietary TH3; one writer | Concurrent writers wait |
| Jepsen | Finds what vendors claim but don't deliver | Real clusters, outside view, no replay | Only finds what its workload exercises |
| Antithesis | Simulation without rewriting code | Paid service; one core per simulated system | Properties still written by the user |
| TLA+ / P | Finds design bugs 35 steps deep | A second program to keep in step with code | Specs drift; MongoDB trace check failed |

## Ideas worth borrowing

- **Hostile hooks plus coverage counters** (FoundationDB). Cost: test-only branches in product code.
- **Disk faults with a moving crash point** (SQLite, TigerBeetle). Cost: storage becomes an interface of countable writes.
- **Allocate at startup, assert in production** (TigerBeetle). Cost: limits the user must choose.
- **Simulate the user's own operations**, the gap no database fills. Cost: user code must run in the deterministic runtime, as Mo code already does.
- **Name the consistency model and check histories against it** (Jepsen). Cost: writing the checker.

## What I could not confirm

- Whether any database released in 2026 offers simulation of the user's workload. AetheriusDB's docs describe a simulator for its own workloads only, and the product is beta and unverified https://aetheriusdb.com/operate/deterministic-sim/.
- Workers IO's claims beyond its homepage.
- How many bugs simulation has found at FoundationDB or TigerBeetle; neither publishes a count.
- Whether running a user's own layer inside FoundationDB's simulator is supported; I found only an unsourced remark that it is "not widely used".
- Antithesis's current pricing and customer list.
