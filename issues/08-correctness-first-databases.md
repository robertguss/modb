# Correctness-first databases

Type: research
Status: claimed

## Question

Using the map's research template, how do the databases built around correctness achieve it, and what does it cost them?

Cover FoundationDB's simulation, TigerBeetle (its simulator, static allocation, single thread), what Jepsen's analyses most often find broken across systems, SQLite's testing, Antithesis, and formal methods used on real databases (TLA+ at Amazon and elsewhere).

Go deepest on what deterministic simulation requires of the implementation language and runtime, which bugs it finds that other testing misses, and whether any system offers simulation of the user's own workload as a feature.

Context: Mo has simulation in the language (generated sequences of calls, a fake clock, crash and restart), so this decides how much of the database's correctness story Mo already supplies.
