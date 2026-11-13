# Deterministic simulation and fault-injection testing

*Deterministic simulation testing* (DST) runs the real program in a fake world (clock, network, disk) where every choice comes from one number, the *seed*, so a seed replays its run exactly. *Fault injection* means the test causes crashes, lost messages and bad disks on purpose ([research 08](../../research/08-correctness-first-databases.md)).

## What it is

The program reaches time, randomness, I/O and the choice of which task runs next only through interfaces the test controls. The test can then run a whole cluster in one process, speed up time, inject faults, and replay any failure from its seed ([research 08](../../research/08-correctness-first-databases.md)). [FoundationDB](../systems/foundationdb.md) simulates a whole cluster in one single-threaded process, reproducible from the seed ([testing](https://apple.github.io/foundationdb/testing.html)). [TigerBeetle](../systems/tigerbeetle.md)'s simulator, the VOPR, injects network and disk faults and can reproduce any run from the seed and the Git commit ([vopr.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md); [research 00](../../research/00-landscape-overview.md)).

## The problem it solves

Bugs that real runs cannot reproduce. Simulation finds ([research 08](../../research/08-correctness-first-databases.md)):

- long chains of faults and recoveries, like the 35-step design bug Amazon found in DynamoDB with a model checker, but in real code (see [formal design models](formal-design-models.md));
- bugs that "take time to play out", which a fake clock skips ([FoundationDB paper](https://www.foundationdb.org/files/fdb-paper.pdf));
- races that a seed can replay but real runs cannot.

Techniques that make rare bugs common:

- **BUGGIFY** (FoundationDB) marks lines that misbehave on purpose, only in simulation; per seed a random subset is on, each firing 5% of the time ([BUGGIFY](https://transactional.blog/simulation/buggify)).
- **Swarm testing**: each run picks random cluster sizes, workloads and faults. A `TEST(cond)` macro counts how many runs reached a rare condition ([FoundationDB paper](https://www.foundationdb.org/files/fdb-paper.pdf)).
- **A moving crash point** ([SQLite](../systems/sqlite.md), which uses exhaustive testing rather than simulation): an in-memory file system snapshots after N writes, damages the files as a power loss would, then checks the database; the loop moves N forward each time ([SQLite testing](https://www.sqlite.org/testing.html)).

## What it costs

Every source says four things must be controlled: **time, randomness, I/O, and scheduling** ([Antithesis](https://antithesis.com/docs/resources/deterministic_simulation_testing/); [DST in Go](https://guidobattiston.com/posts/dst-go/)). In practice ([research 08](../../research/08-correctness-first-databases.md)):

1. **No threads, or a scheduler the test owns.** FoundationDB and TigerBeetle avoid threads entirely. In Go, the runtime schedules goroutines onto OS threads, "giving up your scheduling control to not one, but two external actors". Polar Signals had to force their Go database onto one thread, then wrote their Rust system from scratch to "claim the responsibility of full control" ([Polar Signals](https://www.polarsignals.com/blog/posts/2025/07/08/dst-rust)).
2. **Every I/O call through a replaceable interface**, including the clock and random numbers.
3. **No hidden nondeterminism.** Rust's `HashMap` randomizes its iteration order; S2 could seed its own maps, "but our dependencies..?" ([S2](https://s2.dev/blog/dst.md)). In one Rust project, forgetting one of two build switches silently "falls back to real tokio without an error" ([NautilusTrader](https://nautilustrader.io/docs/latest/concepts/dst/)).
4. **Few dependencies.** Code outside the controlled runtime cannot be simulated ([FoundationDB paper](https://www.foundationdb.org/files/fdb-paper.pdf)).

Other costs: FoundationDB's custom C++ dialect (Flow) and test-only branches in product code; TigerBeetle's single thread and stubbed clock, network and disk; compute, about "one trillion CPU-hours" of simulation at FoundationDB ([research 08](../../research/08-correctness-first-databases.md)). Retrofitting is hard, which is why [Antithesis](../systems/antithesis.md) works at the hypervisor level instead; a language with these rules built in is the alternative ([research 08](../../research/08-correctness-first-databases.md)).

**What it misses** ([research 08](../../research/08-correctness-first-databases.md)):

- Performance and *liveness* (whether the system eventually makes progress). TigerBeetle's latency collapse was found by [Jepsen](../systems/jepsen.md), not the VOPR.
- Workload blind spots. TigerBeetle's generator never produced the query shape that failed ([TigerBeetle blog](https://tigerbeetle.com/blog/2025-06-06-fuzzer-blind-spots-meet-jepsen/)).
- Wrong beliefs about the operating system: the simulated disk obeys the contract its authors believed ([FoundationDB paper](https://www.foundationdb.org/files/fdb-paper.pdf)).
- Code outside the runtime.

## Systems that use it

- [FoundationDB](../systems/foundationdb.md): the simulator came before the database ([paper](https://www.foundationdb.org/files/fdb-paper.pdf)).
- [TigerBeetle](../systems/tigerbeetle.md): the VOPR.
- [Antithesis](../systems/antithesis.md): a deterministic hypervisor for software not written to be deterministic.
- [SQLite](../systems/sqlite.md): not simulation, but crash, out-of-memory and I/O-error loops through its replaceable VFS interface, plus 100% MC/DC coverage from its proprietary TH3 harness ([testing](https://www.sqlite.org/testing.html); [TH3](https://www.sqlite.org/th3.html)).
- AWS uses deterministic simulation through the open-source Rust tools shuttle and turmoil ([AWS, CACM 2025](https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/)).
- Mo: `mo test` advances a fake clock and crashes and restarts services through the real log and snapshot path, backed by an in-memory store. Compared with FoundationDB and TigerBeetle it lacks disk faults, networking, BUGGIFY-style hooks, coverage counters for rare conditions, and a check that the underlying store keeps its contract (inference, [research 08](../../research/08-correctness-first-databases.md)).

## Cannot be combined with

From the four demands above ([research 08](../../research/08-correctness-first-databases.md)):

- Threads scheduled by the operating system or a runtime the test does not own.
- Dependencies that do their own I/O outside the controlled runtime.
- Hidden nondeterminism, such as randomized hash-map iteration in libraries.

## Disagreements

- **TigerBeetle's simulator running "24/7 on 1024 cores".** Research 00 lists it among vendor claims it could not confirm ([research 00](../../research/00-landscape-overview.md)). Research 08 states it as a strength and puts "VOPR on 1,024 cores" in its summary table without a vendor mark ([research 08](../../research/08-correctness-first-databases.md)). Source: [TigerBeetle safety](https://docs.tigerbeetle.com/concepts/safety/).

## Sources

- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- FoundationDB paper: https://www.foundationdb.org/files/fdb-paper.pdf
- FoundationDB testing: https://apple.github.io/foundationdb/testing.html
- BUGGIFY: https://transactional.blog/simulation/buggify
- VOPR: https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md
- SQLite testing: https://www.sqlite.org/testing.html
- Antithesis DST: https://antithesis.com/docs/resources/deterministic_simulation_testing/
- DST in Go: https://guidobattiston.com/posts/dst-go/
- Polar Signals: https://www.polarsignals.com/blog/posts/2025/07/08/dst-rust
- S2: https://s2.dev/blog/dst.md
- NautilusTrader: https://nautilustrader.io/docs/latest/concepts/dst/
- AWS correctness practices: https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/
