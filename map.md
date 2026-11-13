# Map: MoDB, a database for many agents, built in Mo

## Destination

One written decision, short enough to read in a sitting, that names:

1. the kind of database to build first and what is new about it;
2. the ideas borrowed from existing databases and the tradeoff accepted with each;
3. a first slice that holds real data of Robert's;
4. what Mo must gain to build it, each stated as a capability other programs would also use;
5. how the work sits beside Phases 6 to 8.

Reaching it means a spec can start. No database code and no change to Mo is part of this map. Robert approved this destination on 2026-11-13.

## Notes

**Tracker and wiki.** [AGENTS.md](AGENTS.md) holds the conventions for tickets, for `research/` and for the wiki. Research findings are sources; the wiki compiled from them is what a decision ticket reads. Vocabulary is in [GLOSSARY.md](GLOSSARY.md).

**Why this effort exists.** Robert wants an ambitious program that drives what Mo gains next, as an experiment in designing a language alongside a demanding project. The purpose is learning and his own use. Adoption by others and comparison of Mo with other languages are not measures.

**Settled before charting (2026-11-13).**

- The kind of database is open and is chosen from first principles after research. It is not another SQL database or another vector database.
- The leading idea is many agents working on the same data.
- For the first version, coordination comes before speed: one operation executes at a time, and speed needs only to be fast enough that an agent never waits. The research then found evidence against this; [Which problems of agents sharing data is this database for?](issues/15-which-problems-is-this-database-for.md) must weigh it.
- Mo must not become a language for one database.

**Mo on 2026-11-13 (v0.2 and part of Phase 6).**

- Runs command-line programs (arguments, environment, console, files, clock, random) and services (state saved to SQLite, crash recovery, timers, typed live upgrades, reached as MCP tools over HTTP).
- Lacks byte writes, seek and sync on files; any connection other than `mo serve`; an HTTP client and TLS; parallel execution. Speed is unmeasured.
- Sources in `~/code/mo`: `src/base/hostops.def`, `docs/agent-guide.md`, `docs/design/services.md`, `docs/ROADMAP.md`.

**Standing preferences.**

- Ask Robert one question at a time, with a recommendation, the reason and a confidence percentage.
- Grilling tickets call the `grilling` and `domain-modeling` skills.
- Web research uses Exa, with no personal or project details in queries.
- Record every strength with the constraint that pays for it. Features of databases are not independent parts.

**Research template.**

For each system or family covered:

- what it is for, when it appeared, and the problem that made it exist;
- the core idea: the data model, and the storage or consistency idea underneath;
- strengths, each with the constraint that pays for it;
- weaknesses and well-known ways it fails;
- how it handles many clients whose work overlaps: locks, snapshots, conflicts, retries;
- what an AI agent using it would struggle with;
- ideas worth borrowing, and what borrowing each would cost.

End with one table (system, strength, what pays for it, weakness), a short "Ideas worth borrowing" list, and "What I could not confirm". Every factual claim carries a source URL; prefer primary sources and mark vendor claims.

[research/00-landscape-overview.md](research/00-landscape-overview.md) is a first pass over all the families and seeds the family tickets.

## Decisions so far

- [Agents and databases today](issues/09-agents-and-databases-today.md): copies and long-open work are well served; approval and permissions sit beside the database; nobody records why a change was made or reconciles agents with each other by meaning; and there is real evidence against coordination-first.
- [Relational and transactional databases](issues/01-relational-and-transactional.md): full isolation is always paid for with blocking, retries or clock waits; isolation level names cannot be trusted without a test tool; and a client that thinks inside an open transaction harms every engine.
- [Analytical and specialised stores](issues/02-analytical-and-specialised.md): every attempt to rejoin analytics and transactions keeps two copies of the data; these stores write unchangeable pieces and combine them later, so a client can fail to read its own write; worth borrowing are indexes built from one log and a read that says whether it includes your own write.
- [Models that lost or stayed niche](issues/04-models-that-lost-or-stayed-niche.md): query styles where the writer plans the route by hand are worse for an agent with no memory; a new query language starts weak with models (3.3% correct against 47% for SQL in one 2024 benchmark) but worked examples served by the database close most of the gap; a single writer with compare-and-swap fits coordination-first better than weak default isolation.
- [Key-value, document and distributed stores](issues/03-key-value-document-distributed.md): these stores dropped transactions and then added them back in a narrower form; when the network splits they keep taking writes and settle the conflict later, out of sight; and the guarantee lives in settings, not in the reply, which is how confirmed writes have been lost.
- [Code inside the database, and databases inside a language](issues/07-code-inside-the-database.md): determinism and known reads and writes pay for almost every gain of putting code with data; no system found works out reads and writes from the code before it runs (inference: a whole-program compiler could); stored procedures failed on version control, testing and deployment, not on code sitting next to data.
- [Databases that keep history](issues/05-databases-that-keep-history.md): no system makes why a change was made, or on whose instruction, a required and checked part of a write; every system that kept unlimited history later added a way to forget, and personal data needs its own treatment from the first slice; history and overlapping writes still clash.
- [Correctness-first databases](issues/08-correctness-first-databases.md): deterministic simulation needs control of time, randomness, I/O and task order, which Mo already has for services; it misses performance, liveness and whatever the generator never produces, and Mo's has no disk faults or networking; no database lets users simulate their own workload.
- [Divergent copies and merging](issues/06-divergent-copies-and-merging.md): a merge can decide alone only for rules where any two valid copies always combine into a valid one; merges see what each side wrote, never what it read or assumed, so they can be right cell by cell and wrong in meaning; nothing provides multi-world isolation yet, and branching speed trades against read speed.

## Not yet specified

- What is new about the database, in one sentence.
- What the first slice stores and does on its first day.
- Whether it is a Mo service on Mo's existing saved state, or has its own storage engine.
- How agents reach it, and how an agent with no memory learns what it may do.
- Which guarantees a person approves as promises, and how simulation tests them.
- Whether a prototype of what an agent sees is needed before the decision.
- Its name and where its code lives.
- Writing the decision and handing it to a spec.

## Out of scope

- Database code and changes to Mo: the destination is a decision.
- Adoption by other people, and comparing Mo with other languages: not this effort's measures.
