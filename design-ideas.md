# Design ideas

Candidate ideas for the database, captured so they are not lost. Nothing here is decided. A decision is made on a ticket and recorded on [the map](map.md); this file then says which way the idea went.

Started on 2026-11-14, when Robert asked to stay with the big picture and explore. He had the first picture below in mind, found the second intriguing, and said of the list of ideas: "ok now we are talking!"

## Two pictures of what the database is

**Picture 1: a database that programs talk to.** A separate server holds data that many programs share. Programs and agents send it requests. Mo is only what it is built in.

**Picture 2: the database is the Mo program.** There is no separate server and no query language. Data lives in Mo types. Every read and write is a Mo function the compiler has checked. An agent with a new question writes a small Mo program. "MoDB" is then Mo's own storage, history and permissions grown to full strength. This is centre E, "the database is the program", on [Which problems of agents sharing data is this database for?](issues/15-which-problems-is-this-database-for.md).

**Where they meet.** Picture 1 needs a request language, and Robert ruled out presuming SQL. If that language is Mo, an agent sends a small Mo program, and the database checks it and runs it beside the data. Picture 1 with Mo as its request language is Picture 2 seen from outside. The design this points at is a shared store (Picture 1) whose schema, requests and rules are all Mo (Picture 2).

**Why Picture 2 deserves the attention.** This is reasoning, not evidence.

- Query languages exist so that people can ask questions without writing programs. Agents write programs as easily as queries, and a program can be checked before it runs.
- A check before running covers reads as well as writes. Both outside reviews said the accountable write leaves reads out.
- The database stops being an application that could bend Mo. Durable shared state becomes an ability every Mo program has.
- It needs a language designed for it, and Mo is one.

**What it costs.**

- The bet lost once. Object databases tied data to one language and lost to relational ones: data outlived the programs, other tools could not read it, and code and stored data had to change together ([Models that lost to relational or stayed niche](wiki/families/models-that-lost-or-stayed-niche.md), [GemStone/S](wiki/systems/gemstone.md)).
- Finding data fast in a large store. A query that says what is wanted lets the database choose how to fetch it ([Set-at-a-time queries](wiki/ideas/set-at-a-time-queries.md)). An arbitrary program does not.
- Reach. "Others can use it" would mean their agents write Mo, or they use the tools a Mo program exposes.

## What Mo has today

A Mo service is already a small version of Picture 2. This is the top of `services/task-queue/main.mo` in `~/code/mo`:

```
service
  state Queue = JobQueue.empty
  tools submit, lease, heartbeat, acknowledge, fail, list, stats
  every 1.minute expire
  token from env "QUEUE_TOKEN"

fn submit(queue: Queue, _now: Time, payload: Text) : Result((Queue, Int), SubmitError)
```

Checked in Mo's code and documents on 2026-11-14:

- A service has one typed state. Each tool is a function from the old state, the time and its arguments to a new state and a reply.
- Time is an argument, so the same call always gives the same result.
- Every call is logged and the state is saved. A snapshot deletes the log (`src/host/store.c`), so the log is not a history.
- Each handler may do about a million steps of work (`MO_LIMIT_SERVICE_WORK` in `src/base/limits.h`).
- Changing a running service is a compiled upgrade with a migration from the old state.
- Promises and examples are checked by `mo test`, which also simulates a service and its recovery from a crash.
- Every outside effect goes through a capability, and each capability has a real and a fake version. A `Files` capability can already be narrowed with `within` and `read_only` (`src/base/hostops.def`).
- Values never change once made, and the heap never holds a cycle (`docs/design/bytecode.md`).
- Phase 6 adds a program's stated intent and a door where a person reviews changes.

What a service lacks to be a database:

- State larger than memory. Saved state stops at 16 MiB, a request at 16 KiB, a reply at 32 KiB, and callers at 20 requests a second.
- Finding things without walking everything.
- Questions nobody wrote a tool for.
- More than one caller. A service has one token.
- Data shared between programs. A service's state, inputs and results hold no capabilities (`docs/design/services.md`), so each service is an island.

## The ideas

### 1. The request is a program

An agent sends a small Mo program instead of a query. The database checks its types against the data's, checks what it may touch, limits its work, runs it on a snapshot, and logs the program itself. A past question can then be re-run against the data as it was.

- **Mo today:** the compiler and checker, the work limit, and bytecode that is verified when loaded.
- **Needs:** a way to accept, check and run a program that arrives while the database is running, holding only what its caller holds; a snapshot to run it on.
- **Earlier work and risk:** the wiki records [stored procedures and triggers](wiki/ideas/stored-procedures-and-triggers.md) as a trap for agents. Nearer relatives are [deterministic functions as transactions](wiki/ideas/deterministic-functions-inside-transactions.md), [Convex](wiki/systems/convex.md) and [SpacetimeDB](wiki/systems/spacetimedb.md). A program arriving from an agent has to be compiled, and Mo's compiler child runs with the server's own access today ([How does Mo's runtime become memory safe?](issues/24-how-does-mos-runtime-become-memory-safe.md)).
- **Open:** do agents write a correct small program as reliably as a query? Nobody has measured it; the experiments under `learnability/` in Mo measure how well agents write Mo and could measure this. What stops a program that walks everything?
- **Standing:** chosen by Robert on 2026-11-14 as the first idea to explore. He added that it could help with FERPA, HIPAA and other compliance rules, and asked whether it needs Lean, TLA+ or another formal method.

**One request, start to finish.**

1. The agent writes a small Mo function. Its parameters are the only data it can touch, because Mo has no other way to reach anything. A sketch, in the style of the task queue's functions: `fn overdue(forms: Forms) : Map(Department, Int)`.
2. The database compiles it. If the caller's grant leaves a field out, the type the program is handed has no such field, so a program that mentions it does not compile.
3. The database checks the type of the result against what the grant lets out: counts by department pass, a list of names does not.
4. It runs on a snapshot, under a work limit. It was never handed the network or the disk, so the reply is the only way anything leaves.
5. The program's text, the caller, the grant and the declared reason go in the log.

**Why this helps with rules about sensitive data in general.** Most such rules ask for the same three things: limit who sees what, record who saw what and why, and show afterwards that the limits held. Here the refusal happens before any data is read, the record is the exact question and can be run again, and the limit can be stated as a theorem (see "What would be checked" below). The database knows no particular law. A person writes the rules as types and grants.

**Where it stops.** Once a reply has left, the database cannot follow it. A count over a small group can still identify someone ([how hidden data is recovered](wiki/ideas/re-identification-by-linking.md), [k-anonymity](wiki/ideas/k-anonymity.md), [differential privacy](wiki/ideas/differential-privacy.md)).

**Open fork.** May a request program change data, or only read it? Claude's lean: reads are free-form programs; writes go only through functions a person approved, so the accountable write stays strict.

### 2. Promises as the schema

There are no tables and constraints. The database holds Mo types and promises, and checks every write against them before it commits. A refused write comes back with the example it broke. A person approves the promises.

- **Mo today:** promises and examples that `mo test` checks; Phase 6's review door.
- **Needs:** checking promises when a write commits, not only in tests, and knowing what that costs on every write.
- **Earlier work:** [rules the database enforces](wiki/ideas/invariants-the-database-enforces.md), [guarantees checked by a tool](wiki/ideas/guarantees-checked-by-a-tool.md), [schema and examples for agents](wiki/ideas/schema-and-examples-for-agents.md).
- **Open:** which promises can be checked from one write, and which need the whole state?

### 3. Upgrades as migrations

Changing the shape of the data is a compiled function from the old type to the new one. Old history stays readable under the type it was written with.

- **Mo today:** typed upgrades of a running service, with a migration.
- **Needs:** keeping every past type, so history from before a change can still be read.
- **Earlier work:** [grow-only schema](wiki/ideas/grow-only-schema.md), [staged schema changes](wiki/ideas/staged-schema-changes.md).
- **Open:** for a large store, convert everything at once or convert each piece when it is next read?

### 4. The log is the truth

Keep every call for good. Audit is reading the log. Undo is replaying without the bad call. An accountable write is a log entry that carries who made it, under which grant, for which task and the reason they declared.

- **Mo today:** a log of calls, calls that repeat exactly, and `mo replay` and `mo history`. The log is deleted at each snapshot.
- **Needs:** a log that is kept, room for it to grow, and a rule for replaying calls whose code has since changed.
- **Earlier work:** [storing events instead of state](wiki/ideas/storing-events-instead-of-state.md), [facts added, never changed](wiki/ideas/append-only-facts.md), [history the agent cannot erase](wiki/ideas/history-and-audit-the-agent-cannot-erase.md), [Prevayler](wiki/systems/prevayler.md). It collides with [deleting personal data from history](wiki/ideas/deleting-personal-data-from-history.md).
- **Open:** what undoing one call does to the later calls that depended on it.

### 5. A world per agent

Hand an agent its own copy of the data to try things on. It merges back through a function the owner approves.

- **Mo today:** values never change once made, so an old state stays valid while a new one is built.
- **Needs:** large collections that share their unchanged parts between copies, or a copy costs as much as the data. How Mo stores maps has not been checked.
- **Earlier work:** [copy-on-write branches](wiki/ideas/copy-on-write-branches.md), [branches that reconcile with each other](wiki/ideas/branches-that-reconcile-with-each-other.md), [three-way merge of data](wiki/ideas/three-way-merge-of-data.md), [merging by meaning](wiki/ideas/merging-by-meaning.md).
- **Open:** the merge. Every system in the survey finds it the hard part.

### 6. Simulation built in

Any database written in Mo comes with a fake clock, a fake disk that fails, and fake agents racing each other. Its promises are checked under all of it.

- **Mo today:** fake versions of every capability; `mo test` simulates a service and its crash recovery.
- **Needs:** a fake disk that tears writes, loses them and corrupts them; many simulated callers at once.
- **Earlier work:** [deterministic simulation testing](wiki/ideas/deterministic-simulation-testing.md), [simulating the user's own workload](wiki/ideas/simulating-the-users-own-workload.md).

### 7. Shared stores

One new concept: a typed, durable collection that several programs hold a capability to. A capability can be narrowed, for example to "read only these rows" or "may only call `approve`". This builds Picture 1 from Picture 2's parts. Outsiders reach it through tools and write no Mo.

- **Mo today:** capabilities, and narrowing for files. Services are islands with one token each.
- **Needs:** telling callers apart; a capability for a store; narrowing by rows and by operation.
- **Earlier work:** [attenuated capabilities](wiki/ideas/attenuated-capabilities.md), [scoped access for agents](wiki/ideas/scoped-access-for-agents.md), [row and column security](wiki/ideas/row-and-column-security.md).
- **Open:** how "only these rows" is written down and checked.

### 8. Unplanned questions

The weak point of Picture 2: a question nobody wrote a function for. Three answers, which can be combined:

- **Walk everything.** Fine while the data is small.
- **The database proposes an index.** It notices which programs are slow and offers to keep a second copy arranged for them ([derived copies fed from one log](wiki/ideas/derived-copies-fed-from-one-log.md)).
- **A declarative form inside Mo.** A way of writing "give me the items where…" in Mo that the compiler can plan, as a query language's optimiser does ([set-at-a-time queries](wiki/ideas/set-at-a-time-queries.md)). No SQL does not have to mean no declarative questions.

### 9. Sensitivity that travels in the types

A value read from a sensitive field carries a label in its type, and so does anything computed from it. Only a release function that a person approved, such as "count" or "average over at least ten", can take the label off. The database then knows whether a reply depends on sensitive data, however the program computed it. This is "data that protects itself" done with types, not with masking.

- **Mo today:** nothing. It would be a new part of the type system, useful to any program that handles secrets.
- **Earlier work:** [information-flow labels](wiki/ideas/information-flow-labels.md), [IFDB](wiki/systems/ifdb.md).
- **Open:** labels do not stop leaks through how long a program runs or how large its reply is. Choosing the release functions is where the judgement goes.

## What would be checked, and with what

Mo already has the tools. Checked on 2026-11-14: `formal/` in `~/code/mo` holds a Lean model of Mo Core with 238 theorems, among them `type_safety` and `eval_deterministic` (`MoCore/Theorems.lean`); the C VM is compared with that model; and `models/` holds three TLA+ models (`Capture.tla`, `Export.tla`, `Swap.tla`).

| Claim the database would make | Fits | Mo today |
| --- | --- | --- |
| A checked program does not go wrong, and the same call gives the same result | Lean | Proved for Mo Core |
| A program can touch only what it was handed | Lean, a new theorem | Stated as property P7 in `docs/design/sandbox-properties.md` and enforced by the language's design; the comparison with Lean runs programs without capabilities, so it is not covered there |
| Sensitive data reaches a reply only through an approved release function | Lean, after idea 9 exists | Nothing |
| With grants withdrawn, approvals gone stale and crashes mid-write, no write commits under a withdrawn grant and no reply is sent before its record is safe | TLA+ | Three models, for other protocols |
| The code behaves as the design says when things fail | Simulation (idea 6) | `mo test` simulates a service and its crash recovery |
| The rules say what their owner means | No tool; a person approves them, with examples of what each allows and refuses | Phase 6's review door |

Because a request is a Mo program, "no accepted program can read outside its grant" can be proved once for every program. Databases that filter queries test their filters.

The same method has been used for an authorization language: Cedar's authors "formalized Cedar in Lean", implemented it in Rust, and use "differential random testing to ensure that the implementation matches the model" (https://dl.acm.org/doi/full/10.1145/3649835).

The limits: a proof is about the model, and the implementation is compared with the model, not proved. No tool shows that the rules themselves are the right ones.

## How these sit with what is already decided

- The accountable write stays the centre. Ideas 2, 4 and 7 are how it would be built; idea 1 extends it to reads.
- Robert accepted building the upper half first. Every idea above belongs to the upper half.
- The lower half, a storage engine written in Mo, and the runtime questions under it are parked on their own tickets.
