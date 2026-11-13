# Correctness-first databases and the tools that test them

Databases built so that correctness under faults comes first, mostly by testing them in a simulated world that one random seed controls, together with the outside tools that check whether databases keep their promises ([research 08](../../research/08-correctness-first-databases.md); [research 00](../../research/00-landscape-overview.md)).

## What they are for

Correctness under crashes, lost messages and bad disks, and for [TigerBeetle](../systems/tigerbeetle.md) financial throughput as well ([research 00](../../research/00-landscape-overview.md)). The tools in the family exist because vendor documentation often promises more than the system gives ([research 08](../../research/08-correctness-first-databases.md)).

## Members

- [FoundationDB](../systems/foundationdb.md): an ordered key-value core with transactions; the whole cluster runs in one simulated, seeded process.
- [TigerBeetle](../systems/tigerbeetle.md): a single-threaded ledger with a fixed schema and memory allocated at startup, tested by its VOPR simulator.
- [Jepsen](../systems/jepsen.md): an independent tester that runs real clusters under faults and checks the recorded history against the claimed model.
- [Antithesis](../systems/antithesis.md): deterministic simulation as a service, through a hypervisor, for software not written to be deterministic.
- [SQLite](../systems/sqlite.md), described in research 08 alongside these: exhaustive testing rather than simulation, with 100% MC/DC coverage and a moving crash point ([SQLite testing](https://www.sqlite.org/testing.html)).

Mentioned only:

- TLA+: a language for describing a design as states and steps, explored by a model checker; Amazon found three DynamoDB bugs with it ([research 08](../../research/08-correctness-first-databases.md)).
- P and PObserve (AWS): AWS's state-machine modelling language, and a checker of production logs against the P specification ([AWS, CACM 2025](https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/)).
- shuttle and turmoil: open-source Rust deterministic-simulation tools AWS uses (same source).
- Workers IO: makes a claim similar to Antithesis's; vendor claim, unverified ([Workers IO](https://workers.io/)).
- AetheriusDB: docs describe a simulator for its own workloads only; beta and unverified ([AetheriusDB](https://aetheriusdb.com/operate/deterministic-sim/)).
- Polar Signals: forced a Go database onto one thread for simulation, then wrote a Rust system from scratch for full control ([Polar Signals](https://www.polarsignals.com/blog/posts/2025/07/08/dst-rust)).
- S2: could seed its own hash maps for determinism, "but our dependencies..?" ([S2](https://s2.dev/blog/dst.md)).
- NautilusTrader: a Rust project where forgetting one of two build switches silently "falls back to real tokio without an error" ([NautilusTrader](https://nautilustrader.io/docs/latest/concepts/dst/)).
- Temporal: a durable-execution engine that lets users replay recorded workflow histories against new code ([Temporal](https://docs.temporal.io/develop/python/testing-suite)).
- NATS JetStream: Jepsen found it fsyncs "only once every two minutes, but acknowledges messages immediately", losing 131,418 of 930,005 messages under simulated power failures ([Jepsen](https://jepsen.io/analyses/nats-2.12.1)).
- Hermitage: a checker of isolation anomalies, named in research 01 beside Elle; it shows Oracle's "serializable" allows write skew ([Hermitage](https://github.com/ept/hermitage/blob/master/oracle.md); [research 01](../../research/01-relational-and-transactional.md)).
- Elle: Jepsen's checker, named in research 01 as an example of guarantees checked by a tool ([research 01](../../research/01-relational-and-transactional.md)).
- Azure Cosmos DB: publishes TLA+ specifications ([azure-cosmos-tla](https://github.com/Azure/azure-cosmos-tla)).
- FoundationDB Record Layer: a data-model layer built on FoundationDB's core ([Record Layer](https://www.foundationdb.org/blog/announcing-record-layer/); [research 00](../../research/00-landscape-overview.md)).

## Shared tradeoffs

**Control of the world, paid for in design freedom.** Deterministic simulation needs time, randomness, I/O and scheduling under the test's control: no threads (or a scheduler the test owns), every I/O call through a replaceable interface, no hidden nondeterminism, and few dependencies ([research 08](../../research/08-correctness-first-databases.md)). FoundationDB pays with a custom C++ dialect and no threads; TigerBeetle with one thread, a fixed schema and fixed limits; Antithesis users with a paid outside service. Retrofitting is hard; a language with these rules built in is the alternative ([research 08](../../research/08-correctness-first-databases.md)). See [deterministic simulation testing](../ideas/deterministic-simulation-testing.md).

**Simulation and outside testing find different bugs** ([research 08](../../research/08-correctness-first-databases.md)).

- Simulation finds long chains of faults, slow-to-appear bugs and replayable races.
- It misses performance and liveness, workload blind spots, wrong beliefs about the operating system, and code outside the runtime. TigerBeetle's latency collapse and its multi-filter query bug were found by Jepsen, not by its simulator ([Jepsen](https://jepsen.io/analyses/tigerbeetle-0.16.11); [TigerBeetle blog](https://tigerbeetle.com/blog/2025-06-06-fuzzer-blind-spots-meet-jepsen/)).
- Jepsen, testing from outside, cannot replay a run exactly and finds only what its workload exercises. See [guarantees checked by a tool](../ideas/guarantees-checked-by-a-tool.md).

**Formal models catch design bugs, at the cost of a second program.** The specification must be kept matched to the code, and MongoDB's attempt to check real traces against its TLA+ spec failed ([research 08](../../research/08-correctness-first-databases.md)). See [checking designs with formal models](../ideas/formal-design-models.md).

**The testing protects the vendor, not the user.** No database found offers deterministic replay of the user's own workload with injected faults as a product feature; FoundationDB's client-side BUGGIFY is a partial exception (inference, [research 00](../../research/00-landscape-overview.md); [research 08](../../research/08-correctness-first-databases.md)). See [simulating the user's own workload](../ideas/simulating-the-users-own-workload.md).

**For agents.** FoundationDB's five-second transaction limit, TigerBeetle's fixed schema, and SQLite's busy errors when several write at once ([research 08](../../research/08-correctness-first-databases.md)).

**Disagreement inside the family's sources.** Research 00 lists TigerBeetle's simulator running "24/7 on 1024 cores" among vendor claims it could not confirm; research 08 states it as a strength without a vendor mark ([research 00](../../research/00-landscape-overview.md); [research 08](../../research/08-correctness-first-databases.md)).

## Sources

- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 01: Relational and transactional](../../research/01-relational-and-transactional.md)
- FoundationDB paper: https://www.foundationdb.org/files/fdb-paper.pdf
- TigerBeetle ARCHITECTURE.md: https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md
- Antithesis DST: https://antithesis.com/docs/resources/deterministic_simulation_testing/
