# Simulating the user's own workload (gap)

Deterministic simulation testing applied to the application's own operations, not just to the database's internals: the user's workload replayed exactly, with faults injected. Research 00 and 08 both found no database that offers it as a full feature ([research 00](../../research/00-landscape-overview.md); [research 08](../../research/08-correctness-first-databases.md)).

## What it is

[Deterministic simulation testing](deterministic-simulation-testing.md) runs a program in a fake world where one seed decides every choice, so any failure replays exactly. The databases that use it, [FoundationDB](../systems/foundationdb.md) and [TigerBeetle](../systems/tigerbeetle.md), use it on their own code. This page is about running the *user's* code and workload that way, as a product feature (inference, [research 00](../../research/00-landscape-overview.md)).

## The problem it solves

Research 00 frames the gap as: simulation testing protects the vendor, not the user (inference, [research 00](../../research/00-landscape-overview.md)). A database tested to a trillion CPU-hours says nothing about whether the application on top handles a crash, a retry or a timeout correctly.

## What it costs

User code must run in the deterministic runtime, as Mo code already does ([research 08](../../research/08-correctness-first-databases.md)). That brings every demand of deterministic simulation: controlled time, randomness, I/O and scheduling, and few dependencies outside the runtime ([research 08](../../research/08-correctness-first-databases.md)).

## Systems that use it

None fully. The closest ([research 08](../../research/08-correctness-first-databases.md)):

- [FoundationDB](../systems/foundationdb.md)'s client-side BUGGIFY makes the client "randomly throw errors that an application might see in production", to test the application's error handling ([client testing](https://apple.github.io/foundationdb/client-testing.html)). It does not replay the application deterministically. Research 00 calls it a partial exception. Research 08 found only an unsourced remark that running a user's own layer inside FoundationDB's simulator is "not widely used".
- [Antithesis](../systems/antithesis.md) sells it as a service, outside the database.
- Temporal, a durable-execution engine and not a database, lets users replay recorded workflow histories against new code, and run tests with skipped time ([Temporal testing](https://docs.temporal.io/develop/python/testing-suite)).
- AetheriusDB's docs describe a simulator for its own workloads only; the product is beta and unverified ([AetheriusDB](https://aetheriusdb.com/operate/deterministic-sim/)).
- Mo, for services: `mo test` generates call sequences, advances a fake clock, crashes and restarts "through the real log and snapshot path backed by an in-memory store", checks promises after every step and shrinks failures; `--strength` counts how many wrong versions the checks catch (`~/code/mo/docs/agent-guide.md`, lines 15, 17, 49). It lacks disk faults, networking, BUGGIFY-style hooks, rare-condition coverage counters, and a check that the underlying store (SQLite, not the in-memory store) keeps its contract (inference, [research 08](../../research/08-correctness-first-databases.md)).

## Sources

- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- FoundationDB client testing: https://apple.github.io/foundationdb/client-testing.html
- Temporal testing suite: https://docs.temporal.io/develop/python/testing-suite
- AetheriusDB deterministic simulation: https://aetheriusdb.com/operate/deterministic-sim/
