# Correctness-first databases

Type: research
Status: resolved

## Question

Using the map's research template, how do the databases built around correctness achieve it, and what does it cost them?

Cover FoundationDB's simulation, TigerBeetle (its simulator, static allocation, single thread), what Jepsen's analyses most often find broken across systems, SQLite's testing, Antithesis, and formal methods used on real databases (TLA+ at Amazon and elsewhere).

Go deepest on what deterministic simulation requires of the implementation language and runtime, which bugs it finds that other testing misses, and whether any system offers simulation of the user's own workload as a feature.

Context: Mo has simulation in the language (generated sequences of calls, a fake clock, crash and restart), so this decides how much of the database's correctness story Mo already supplies.

## Answer

Findings: [research/08-correctness-first-databases.md](../research/08-correctness-first-databases.md).

- Deterministic simulation needs four things controlled: time, randomness, I/O and scheduling. FoundationDB and TigerBeetle paid with no threads, few dependencies and (FoundationDB) a custom language; retrofitting is hard.
- Simulation finds long fault chains and rare races, but misses performance and liveness problems, workload blind spots and wrong beliefs about the OS. Jepsen found a TigerBeetle query bug that four fuzzers missed.
- Jepsen's most common findings: documentation promises a stronger isolation level than delivered, and acknowledged writes lost because fsync came after the acknowledgement.
- No database offers deterministic simulation of the user's own workload as a feature; FoundationDB's client BUGGIFY and Antithesis (a service) come closest.
- Mo already supplies generated call sequences, a fake clock, crash and restart, promises and shrinking; it lacks disk faults, networking, BUGGIFY-style hooks and a check of the real store (simulation uses an in-memory store, not SQLite).
