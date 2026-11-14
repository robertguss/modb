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

**Tracker and wiki.** [AGENTS.md](AGENTS.md) holds the conventions for tickets, for `research/` and for the wiki. Research findings are sources; the wiki compiled from them is what a decision ticket reads. Start at [wiki/overview.md](wiki/overview.md) and [wiki/index.md](wiki/index.md). Vocabulary is in [GLOSSARY.md](GLOSSARY.md). Our own candidate ideas, while they are being explored, are in [design-ideas.md](design-ideas.md).

**Why this effort exists.** Robert wants an ambitious program that drives what Mo gains next, as an experiment in designing a language alongside a demanding project. The purpose is learning and his own use. Adoption by others and comparison of Mo with other languages are not measures. Clarified on 2026-11-14: he is not aiming to run Mo in production soon and is in no hurry. "Ready for real software" meant beginning to test what Mo has and filling the language's gaps by building software. Doing it right outweighs doing it soon, so "usable sooner" is not a reason to prefer one route.

**Settled before charting (2026-11-13).**

- The kind of database is open and is chosen from first principles after research. It is not another SQL database or another vector database.
- The leading idea is many agents working on the same data.
- For the first version, coordination comes before speed: one operation executes at a time, and speed needs only to be fast enough that an agent never waits. The research then found evidence against this; [Which problems of agents sharing data is this database for?](issues/15-which-problems-is-this-database-for.md) must weigh it.
- Mo must not become a language for one database.

**Decided after outside review (2026-11-14).** Robert asked models from two other providers to review the direction. Both advised building a Mo service he uses first. One said to build a storage engine only if a guarantee needs it; the other said never to build one. Robert's decision: he still wants the database, and it stays the destination. The reviews are recorded on [Which problems of agents sharing data is this database for?](issues/15-which-problems-is-this-database-for.md) and [How does Mo's runtime become memory safe?](issues/24-how-does-mos-runtime-become-memory-safe.md). What the reviews changed is the order of the work and the first slice, not the destination.

**Steer on 2026-11-14: zoom out.** Robert said the work was chasing rabbit trails and asked for the big picture, "extremely ambitious".

- He accepts building the upper half of the database first. He reopened this on 2026-11-14 and chose vertical slices instead; see below.
- Nothing may presuppose SQL or the relational model. If SQLite sits underneath at first, it is only a place to keep bytes, as it is in Mo today; none of its tables, indexes or queries is used.
- The idea to explore at the top: no query language at all, and a database that is written and used in Mo itself.
- FERPA is one possible use, not what the design is driven by. The database is not built for his work alone; others should be able to use it.
- Memory safety, the Rust port and Safe C stay parked on [How does Mo's runtime become memory safe?](issues/24-how-does-mos-runtime-become-memory-safe.md) until an addition to the runtime forces the question.
- A side question gets a short answer and is parked. It does not grow into its own investigation unless he asks.

**Decided on 2026-11-14 while exploring many agents.** A world, an agent's own copy of the data, lands whole or not at all, and the rule is checked after every call in it ([ticket](issues/35-what-lands-together-when-a-world-holds-more-than-one-call.md)). At landing every question the agent asked counts, by its answer; the database counts needless send-backs, and a finer rule waits for that number. Both are written out in [design-ideas.md](design-ideas.md).

**Reopened on 2026-11-14 after the measurements: which half first.** Robert said the order does not matter to him and that he is in no rush. He asked for the trade-offs of each order and for a review by models of three providers. The trade-offs are in [design-ideas.md](design-ideas.md) under "Which half first". The review came back the same day and is on [Which half comes first?](issues/36-which-half-comes-first.md): none of the three chose either half outright, and each asked for an experiment first. Not decided.

**Decided on 2026-11-14: a sketch before the order.** Robert asked for the experiment the reviewers named to be built before he chooses: [Can a Mo library keep old versions cheaply today?](issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md). The same day he raised vertical slices, part of the upper half and part of the storage built together as small experiments, in place of one half and then the other. That idea is in [design-ideas.md](design-ideas.md) under "Which half first".

**Decided on 2026-11-14: vertical slices.** After the sketch reported, Robert chose them: "Yes to vertical slices." Neither half is built first. Which slices, and in what order, is [Which vertical slices, in what order, and what must each show?](issues/38-which-vertical-slices-in-what-order.md), which holds Claude's proposal of five.

**Raised on 2026-11-14, not decided: Mo with batteries included.** Robert asked whether Mo could be a framework as well as a language, with the database and storage as parts that ship with it. He thinks it "has serious legs" and is not yet sure. It would change the destination from a database beside Mo to Mo's first battery. He is not dogmatic about what is written in Mo. The idea, a picture of it and a list of deep dives owed are in [design-ideas.md](design-ideas.md). He deferred the framework the same day and returned the work to the database.

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
- [Keeping sensitive data from agents and model providers](issues/20-keeping-sensitive-data-from-agents.md): databases do ship masking and masked copies, but masking does not survive ad hoc queries and agents re-identify masked text in most measured cases; only differential privacy holds when many queries are combined, and it answers totals only; no shipping database declares sensitivity in its types and enforces it on every exit.
- [Security of a database that agents use](issues/21-security-of-a-database-agents-use.md): a shared database holds the whole lethal trifecta by itself, and only the database can label rows by writer, trust and reader; limiting what an agent can do works while detecting injected instructions does not; every 2025 to 2026 bypass broke a text filter, not a credential's own limits.
- [Compile the research into the wiki](issues/19-compile-the-research-into-the-wiki.md): 126 pages (53 systems, 63 ideas, 10 families) with an overview, an index and a log; 18 disagreements between sources are recorded on their pages and listed in the ticket.
- [One comparison across all families](issues/10-one-comparison-across-families.md): [wiki/comparisons/families.md](wiki/comparisons/families.md) sets the ten families side by side, lists the ideas worth borrowing with their costs, the ideas that cannot be combined, and nine gaps no family fills.
- [The security baseline for student records, and what mainstream databases ship](issues/22-security-baseline-for-student-records.md): a student-records database most needs a unique identity per caller, multi-factor login, limits by row and column, a record of disclosures with an activity log, and encryption in transit and at rest; FERPA requires reasonable methods so that school officials reach only records they have a legitimate educational interest in; in one 2026 breach report unpatched flaws led, then stolen credentials, then insiders.
- [Is Veil a good home for the protocol models?](issues/26-is-veil-a-good-home-for-the-protocol-models.md): Veil works and can prove what TLC can only check for small sizes, but it needs a newer Lean than Mo pins and is young; keep TLA+ for now.
- [What is Bend2, and what would proved laws mean for promises?](issues/27-what-is-bend2-and-what-would-proved-laws-mean-for-promises.md): Bend2 does not fit as a checking tool; tests and proofs caught different errors, and a frozen human-written law with an agent-written proof is the idea worth borrowing for promises.
- [Which other specification languages fit?](issues/28-which-other-specification-languages-fit.md): Add Alloy 6 for rules about grants; keep TLA+ for protocols; Quint, P and the rest add nothing here.
- [How have storage engines and databases been checked?](issues/29-how-have-storage-engines-and-databases-been-checked.md): Small models in the code's own language give the most per line; Mo's crash check does not yet test a disk that loses writes; a database that owns its log can check its own history cheaply.
- [What earlier work stands behind merging by replay, checking reads again, and taking work back out?](issues/30-earlier-work-on-merging-by-replay.md): The replay rule is known parts newly combined; the literature warns that re-checking every read blocks far too much, that first-come landing starves slow agents, and that removing one agent's work is not a plain replay.
- [What earlier work stands behind write-once trees and views kept current?](issues/31-earlier-work-on-write-once-trees-and-views-kept-current.md): The tree of write-once nodes is proven at scale, but garbage grows fast, hashes fight erasure, and only restricted forms of view can be kept current.
- [What earlier work stands behind grants as views and requests as programs?](issues/32-earlier-work-on-grants-as-views-and-requests-as-programs.md): Requests as programs is an old idea newly combined that lost for reasons other than the idea itself; grants as view functions are sound at the core and leak through errors, timing, totals and work limits.
- [Does the replay rule catch what merges get wrong?](issues/33-does-the-replay-rule-catch-what-merges-get-wrong.md): All 48 settings as predicted: recorded reads catch all five mistakes, declared rules catch three, and a call that says what it means is sent back for nothing.
- [How fast and how large is a Mo service today?](issues/11-how-fast-and-large-is-a-mo-service.md): A read takes about 10 ms at any size, nearly all of it Mo's HTTP layer; a write takes about 17 ms plus 0.66 ms per 1,000 small rows, because every write copies and checksums the whole state; a read waits behind a write; writes stop at about 125,000 small rows (9 MiB saved). SQLite by itself, on the same disk with Mo's settings, writes in about 3 ms from one row to ten million.
- [Which half comes first?](issues/36-which-half-comes-first.md): Neither. Robert chose vertical slices: small experiments that each build part of the upper half and part of the storage together.
- [Can a Mo library keep old versions cheaply today?](issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md): Yes in space and no in time. A tree whose nodes name each other by number keeps a version for 778 bytes at any size measured, with no change to Mo, where a `Map` or a tree by reference costs a whole copy and runs out of memory. A write still costs in proportion to all of the state. Mo also copies a map that sits in a record every time the map changes.
- [What lands together when a world holds more than one call?](issues/35-what-lands-together-when-a-world-holds-more-than-one-call.md): All 40 settings as predicted: calls landing one by one leave gaps, a whole world checked only at its end lets approved calls combine into a change neither could make, and a whole world checked after every call got nothing wrong. Robert chose that last way on 2026-11-14.

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
