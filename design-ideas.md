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
- Every call that changes the state is logged, and the state is saved. A read is not logged (`replacement` and `persist` in `src/vm/service.c`; a reviewer found this on 2026-11-14). A snapshot deletes the log (`src/host/store.c`), so the log is not a history.
- Each handler may do about a million steps of work (`MO_LIMIT_SERVICE_WORK` in `src/base/limits.h`).
- Changing a running service is a compiled upgrade with a migration from the old state.
- A caller's own function can be run over an exported copy of a service's state, with `mo query`. It runs outside the service, under a limit of 2^30 instructions (`MO_LIMIT_QUERY_WORK`), 1,024 times what a call to a service gets. Its parameters and result hold no capability and no function. A reviewer pointed out on 2026-11-14 that these notes had missed it.
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
- **Needs:** a way to accept, check and run a program that arrives while the database is running, holding only what its caller holds (`mo query` already runs a caller's function over an exported copy of the state, outside the service; inside a running service the upgrade path is the nearest thing Mo has); a snapshot to run it on.
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

**Decided by Robert on 2026-11-14: a request program only reads.** Questions are free-form programs. Data changes only through functions a person approved, so the accountable write stays strict, and a program that cannot change anything is far easier to prove things about.

**A grant can be a view function.** What a caller may see is itself a Mo function a person approved, from the full data to a narrower type. The agent's program takes that narrower type as its input, and the database runs the program on the view's result. Nothing new is needed in the type system: the narrower type is an ordinary type, and a program that mentions a field the view left out does not compile. The cost is computing the view for each request, which matters once the data is large.

**The shape this gives the whole database.** Four kinds of Mo function, each approved by a person, plus free-form programs that only read:

- types and promises say what the data is and what must stay true (idea 2);
- view functions say what a caller may read;
- write functions say how the data may change, and each call is an accountable write;
- release functions say what may leave (idea 9).

**Mo is closer to this than it looks.** Mo's upgrade path already takes source sent to a running service, compiles it in a child process, verifies the result and loads it (`src/host/compile.c` in `~/code/mo`). Accepting a read program is a cousin of that.

**Decided by Robert on 2026-11-14: agents may propose.** An agent may propose a new view, write function, release function, type or promise, as Mo code, and a person approves it.

What follows from that. These are ideas, not decisions:

- **A proposal is an accountable write to the database's own definition.** Who proposed it, who approved it and why sit in the same log as the data.
- **The machine checks first and the person comes last.** A proposal reaches a person only after it compiles, keeps every promise, and has been tried: in the proposer's own world (idea 5), under simulation (idea 6), or replayed over past calls (idea 4).
- **The person reviews what becomes possible, not code.** For example: "this view newly shows field X to caller Y", with examples. Phase 6's `mo intent` already lists a program's intent and shows how it changed.
- **Narrower is free; wider needs a person.** A view built on an approved view can only show less. It is the same thing as a read program, so it needs no approval, and an agent can hand a helper a narrower view without asking anyone. Approval is needed only to widen what can be read, to add a way to change data, or to add a way for data to leave.
- **The risk this is built around.** Both outside reviews warned that approved rules give false assurance and that the person's attention is the scarce thing. This spends that attention only on widening.

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
- **Open:** what undoing one call does to the later calls that depended on it. An answer is sketched under [Many agents working together](#many-agents-working-together).

### 5. A world per agent

Hand an agent its own copy of the data to try things on. It merges back through a function the owner approves.

- **Mo today:** values never change once made, so an old state stays valid while a new one is built.
- **Needs:** large collections that share their unchanged parts between copies, or a copy costs as much as the data. Checked on 2026-11-14: a Mo `Map` is one block, so a changed copy is a whole copy (see [Storage underneath](#storage-underneath)).
- **Earlier work:** [copy-on-write branches](wiki/ideas/copy-on-write-branches.md), [branches that reconcile with each other](wiki/ideas/branches-that-reconcile-with-each-other.md), [three-way merge of data](wiki/ideas/three-way-merge-of-data.md), [merging by meaning](wiki/ideas/merging-by-meaning.md).
- **Open:** the merge. Every system in the survey finds it the hard part. Explored under [Many agents working together](#many-agents-working-together).

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

### Which instrument comes first

Robert proposed on 2026-11-14 to write small Lean and TLA+ models, "like we did for pieces of Mo", invited pushback, and said to keep performance in mind with optimisation later. What follows is Claude's proposal. Robert has not accepted it.

**What each has cost in Mo.** Checked on 2026-11-14: the three TLA+ models are 257 lines together, and each has configurations that are meant to fail. The Lean model is 13,555 lines in 48 files (recounted on 2026-11-14; a reviewer found the earlier figure of 12,049 wrong).

| Instrument | Good for | Not good for | Use here |
| --- | --- | --- | --- |
| TLA+ | A protocol whose steps interleave or crash | Whether the design can be written in Mo; what it costs | First: the replay rule, then the order of writes to disk |
| A throwaway sketch in Mo, with generated tests | Whether Mo can express the design; cost counted in steps; finding Mo's gaps | Orders of events the tests never generate | Second: the same rule, in memory |
| Lean | Claims about the language that hold for every program | Protocols and data structures, where tests find the same errors for far less | Write the statements early; prove them once the feature is in the reference |
| Measurement | Base numbers | Errors in the design | Once, early |

**Order proposed.**

1. A TLA+ model of the replay rule from [Many agents working together](#many-agents-working-together). Predictions are written first. The cases are the three the survey says merges get wrong (two agents book the last seat; a meeting that ends before it starts; a discount worked out from prices that have since changed), two agents changing the same value, and two changes that are each allowed and together break a rule. The model shows which mechanism catches each case: the function's own check, the promises, or the recorded reads. A configuration with recorded reads switched off must fail.
2. A throwaway sketch of the same rule in today's Mo, in memory: a state, a write function, a promise, a world and replay, with the same cases as tests. Every place where Mo gets in the way goes on a list. Steps are counted.
3. A TLA+ model of the order of writes to disk from [Storage underneath](#storage-underneath), with a crash at every step.
4. Lean statements, without proofs, for "a read program cannot change data" and "a helper's grant never shows more than the grant it was made from".

**Performance, kept in mind.** Some costs come from the shape and cannot be optimised away later: one writer on the main line; each change rewrites and hashes a path of nodes; each merge runs the agent's reads again; a read hops from node to node. Each model and sketch counts these. The base numbers were measured on 2026-11-14, first on a busy machine and then on a quiet one, which gave nearly the same ([How fast and large is a Mo service?](issues/11-how-fast-and-large-is-a-mo-service.md)). A read takes about 10 ms at any size of state. A write takes about 17 ms plus 0.66 ms for every 1,000 small rows; at 100,000 rows that is about 80 ms, and a read behind it waits as long. The state stops taking writes at about 125,000 small rows, 9 MiB saved, because of the memory one call may use. One writer on the main line and a whole-state cost on each write are therefore measured facts of a Mo service today, not guesses.

**The three costs of a Mo service, measured apart on 2026-11-14.**

| Cost | Size | Where it comes from | Whose it is |
| --- | --- | --- | --- |
| On every call | About 10 ms of processor | The layer of `mo serve` that reads and checks the HTTP request. It is Mo bytecode run by the VM. | Mo's services, whatever they hold |
| On every write | About 7 ms, mostly waiting | Syncing to disk | Any store that syncs each write. SQLite by itself pays about 3 ms on this disk. |
| On every write, growing | About 0.65 ms for every 1,000 rows | The whole state is encoded and decoded back into a fresh copy (59% of a write at 100,000 rows), checksummed (9%) and the old copy freed (10%) | How Mo saves a service's state |

- The yardstick: SQLite by itself, on the same disk with the settings Mo's store uses, takes about 3 ms for a synced write and a few thousandths of a millisecond for a read, from one row to ten million. It has no HTTP request around it, so it is a floor and not a like-for-like figure.
- A write also copies the whole map before the function changes it: the service hands the function a second reference to the state, and a shared map is copied on its first change (`src/vm/service.c`, `src/heap/table.c`). A reviewer found this, and it fits the 10% of a write measured in `copy_table`. That the two are the same cost is an inference.
- Only the third cost is about how data is stored. The tree of write-once nodes under "Storage underneath" is aimed at it.
- The first cost falls on reads, which agents send in high volumes. A request program (idea 1) that does many reads in one request would pay it once. This is Claude's inference and was not measured.
- None of this is a decision. Whether the first slice lives with these costs, or Mo changes first, is open.

**Other tools looked at on 2026-11-14.**

- **Bend2** (https://bend2.dev/notes/what-is-bend2/). A typed functional language in which a program states laws and proves them in the same language, and "the compiler checks every proof before execution". A third-party status report dates its launch to 2026-09-17 (https://deliberus.com/docs/research/bend-and-deliberus/bend-hvm-status-report-2026-09-29.md). It does not model steps that interleave, so it is not an instrument for the protocols here, and using it would mean writing the database's pieces again in a language two months old. Its interest is as a relative of Mo's promises: a law is a promise that is proved, not tested.
- **Veil** (https://veil.dev/). "A foundational framework for specifying, model checking, and proving safety and liveness properties of state transition systems, built using Lean." It could put protocol models in the toolchain Mo already uses. Not tried, and whether it works with Mo's pinned Lean version is unknown.
- **Small executable models checked with generated tests.** Amazon checked a storage node of S3 this way: the models were "1% of the implementation code", the checks "prevented 16 issues from reaching production", and the authors "accept weaker correctness guarantees than full formal verification" (https://www.amazon.science/publications/using-lightweight-formal-methods-to-validate-a-key-value-storage-node-in-amazon-s3). This is the second instrument above.
- From Claude's own knowledge and not looked up: Quint (TLA+'s logic in a syntax closer to code), P (protocols as state machines), Alloy (rules about shapes of data, such as whether one grant is narrower than another), and Elle with [Jepsen](wiki/systems/jepsen.md) (checking the history of a running system), which needs something running.

## Storage underneath

Explored on 2026-11-14 at Robert's request, before "many agents". Nothing here is decided.

**What the upper half asks of storage.** A state larger than memory; a snapshot for every read program; old states kept, so a past question can be run again; a cheap copy for each agent's world; a permanent log of calls; a way to find things without walking everything.

**The central idea: store the database the way Mo already holds a value.** A Mo value never changes once made and never contains a cycle. On disk that is a tree of nodes, each written once. A change writes new nodes along one path and shares all the rest. Each node is named by the hash of its contents. Beside the tree sits the log of calls, which only grows.

What falls out of that one choice:

- **A version is a root.** A snapshot, an old state and an agent's world are each one root. None of them costs a copy.
- **A crash cannot tear the data.** Nothing is overwritten. New nodes are written first, then the root is switched.
- **The tree can be rebuilt from the log.** Calls repeat exactly, so the tree is a saved result of replaying the log. Only the log has to reach the disk before a reply is sent, which Mo already does.
- **History can be checked.** Each log entry can carry the root before and after. Anyone can replay a call and confirm it leads from one to the other.
- **Two worlds can be compared quickly.** Parts with the same hash are the same, so only the differences are walked. This is what "many agents" builds on.
- **The disk can be anything that keeps bytes under a name:** a table in SQLite at first, used only as names to bytes, then a file written in Mo, or a bucket in a cloud store ([object storage as the only durable store](wiki/ideas/object-storage-as-source-of-truth.md)).

**Three more ideas on top.**

- **An index is a view the database keeps current.** A view function, an index and a saved query result are the same thing: a function from the data to other data. If views are written in a form the database can follow, it updates them as the data changes, so a view is not recomputed for each request and "find things fast" needs no second mechanism ([derived copies fed from one log](wiki/ideas/derived-copies-fed-from-one-log.md), [query results kept fresh](wiki/ideas/continuously-updated-query-results.md), [Materialize](wiki/systems/materialize.md), [CouchDB](wiki/systems/couchdb.md), whose views are functions in the application's language).
- **Code is stored by hash too.** Each approved function is kept under the hash of its checked form, and a log entry names the function it called by that hash. Replaying an old call then always runs the code that ran at the time. This answers the open question under idea 4. Phase 6 already gives each item of a program a digest.
- **Storage laid out by type.** The database knows the type of everything it holds, so it can keep each field of a record apart. A view that leaves a field out never reads its bytes, and a sensitive field can be encrypted under its own key, released only to views approved to see it.

**Other shapes, for contrast.**

| Shape | Good at | Costs |
| --- | --- | --- |
| Tree of write-once nodes, plus the log (above) | Snapshots, history, worlds, checking | Each change rewrites a path; old versions pile up and must be cleared; reads hop from node to node |
| The log alone, all data in memory ([Prevayler](wiki/systems/prevayler.md), and Mo today) | Simplicity | Data must fit in memory; a restart replays the log |
| Pages changed in place, with a recovery log ([SQLite](wiki/systems/sqlite.md), [PostgreSQL](wiki/systems/postgresql.md)) | Large data; the most proven design | Snapshots, history and worlds need extra machinery; it works against values that never change |
| Sorted files merged in the background ([RocksDB](wiki/systems/rocksdb.md), [immutable pieces with background merge](wiki/ideas/immutable-pieces-with-background-merge.md)) | Heavy writing | Background work; worlds are hard |

**Earlier work.** In the survey: [Dolt](wiki/systems/dolt.md) and [Datomic](wiki/systems/datomic.md) store trees of unchanging pieces; [copy-on-write branches](wiki/ideas/copy-on-write-branches.md). From Claude's own knowledge and not in the survey: Git names every object by its hash; LMDB is a copy-on-write tree with one writer and no recovery log; Irmin is a Git-like store for typed values; Unison stores code by hash.

**What Mo has and lacks for this.** Checked on 2026-11-14:

- A service's state is saved whole, as one blob of at most 16 MiB, beside its log. The path from there is short: replace the one blob with a tree of nodes and write only the nodes that changed.
- Mo's `Map` and `Set` are hash tables held in one block (`src/heap/table.c`). A changed copy of a shared map is a whole copy. The tree-shaped collection would be new.
- Mo programs have no hash-of-bytes function (`src/base/prims.def` has none), cannot write bytes and cannot read at an offset. Each is a general ability, not one only a database wants.

**Two ways to build it.** As a library written in Mo, where a tree's nodes are loaded by name through a capability: everything is ordinary Mo that `mo test` can simulate and the Lean model covers. Or inside the runtime, where any Mo value can quietly live on disk: more powerful, but it hides which step touches the disk. Claude's lean is the library first. A reviewer pointed out on 2026-11-14 that the library route does not fit a service as Mo stands: a service's state, inputs and results may hold no capability (`docs/reference/README.md`, section 11.5), so a handler has no way to load a node through one.

**Open.**

- What a change costs when the tree is deep, and how fast old versions pile up.
- Erasing one person's data from every old version. It can leave a marked hole where a node was, but [deleting personal data from history](wiki/ideas/deleting-personal-data-from-history.md) shows how hard this is.
- Which form of view the database can keep current by itself.

## Many agents working together

Explored on 2026-11-14 at Robert's request, after the storage underneath. Nothing here is decided.

**What the survey says is missing.** [Many branches that reconcile with each other](wiki/ideas/branches-that-reconcile-with-each-other.md) lists five things this needs and finds no system with all five: storage shared between copies without slow reads; giving up a copy as the cheap path; a rule for two copies that both changed; one merge across everything an agent touched; a final order. [Merging by meaning](wiki/ideas/merging-by-meaning.md) names the trouble underneath: a merge sees what each side wrote, never what it read or assumed.

**The central idea: a change is a call, so merging is replaying.** Data changes only through approved write functions, and the log holds calls, not changed cells. An agent's world is therefore a root plus the list of calls the agent made in it. To bring a world back, the database replays those calls, in order, on the state as it now is. This is a rebase in Git's sense, except that each step is a function call with typed arguments and not a change to text.

Replaying is not new. [Bayou](wiki/systems/bayou.md) did it in 1995 and [Zero](wiki/systems/zero.md) does it today. What the other ideas in this file add to it:

- **Each call checks itself again.** A write function already refuses when its conditions do not hold. Replayed on the newer state, it reads the newer state. When two agents approve the same form, the second replay is refused with a typed reason the agent can act on. Bayou needed a hand-written check on every write; here the function is the check.
- **The promises are the rule over the merged result.** They are checked after every replayed call, so two changes that are each fine alone and wrong together stop at the second. For a world with more than one call this has a price: a transfer written as two calls breaks "the total stays the same" in between and never lands. Claude first wrote that the rule "cannot be right as stated". The second model corrected that: checked after every call and landed whole, it got nothing wrong, and the transfer has to be one approved function. Robert chose this on 2026-11-14 ([what the second model found](#what-the-second-model-found)).
- **The database already knows what the agent read.** Every question the agent asked was a read program the database ran, so the world's record holds each program and its answer. At replay the database runs them again. A different answer means the agent decided on something that is no longer true. [Writes that carry their assumptions](wiki/ideas/writes-that-carry-their-assumptions.md) found that agents rarely state what they assumed. Here they do not have to.
- **Giving up is free.** Dropping a world is dropping a root.
- **Two worlds reconcile the same way.** Replaying one world's calls onto another world is the same step. The main line is only the world everyone agrees is real, and its log is the final order.
- **Long thinking holds nothing.** An agent can keep a world open for hours and nothing is locked. The price is a higher chance that its replay fails.

A replay ends one of three ways. It lands. It is refused, by its own function or by a promise, and goes back to the agent with the reason. Or it would land, but an answer the agent relied on has changed. What happens then is a rule a person approves for each write function: let it through, send it back to the agent, or hold it for a person ([writes held for approval](wiki/ideas/writes-held-for-approval.md)).

**Helpers get less, never more.**

- An agent hands a helper a grant made from its own: a view function applied on top of the agent's view, fewer write functions, arguments fixed or limited, a limit on the number of calls and an end time.
- The helper's view is computed from what the agent's view returns, so it cannot show more. Nothing has to be analysed to know the grant is narrower, and no person is needed ("narrower is free"). Mo's file capabilities already narrow this way (`within`, `read_only`).
- The helper works in a world forked from the agent's world. Its calls come back to the agent's world and from there to the main line. Authority flows down and narrows at each step. Changes flow up and are replayed at each step.
- Every call in the log names the whole chain: the person who approved the function, the agent, the helper.
- Taking back an agent's grant ends every grant made from it.

**Take one agent's work back out.** The log holds every call with its caller. To remove what one agent did, because injected text misled it or because it was wrong, replay the log from before its first call and leave its calls out. The later calls that are now refused, or whose recorded answers now differ, are the ones that depended on the removed work. This is an answer to the open question under idea 4. It cannot recall anything that already left through a release function. Research on 2026-11-14 warns that this is not a plain replay in practice: the systems that do it re-run only what was affected, still paid 24% to 127% more running time and gigabytes of log a day, and sometimes need a person ([findings](research/30-earlier-work-on-merging-by-replay.md)).

**Agents see each other through data.**

- A claim such as "I am working on form 42" is an ordinary record written by an ordinary write function, as `lease` and `heartbeat` are in Mo's task queue today. No lock manager is needed.
- "Tell me when this answer changes" is a view the database keeps current (see [Storage underneath](#storage-underneath)).

**The first-version rule, made narrower.** Settled earlier: one operation runs at a time. The survey's evidence against that rule is that agents' exploring, not their writing, becomes the bottleneck. Under this design only writes to the main line must run one at a time. A read program or a world works on a root that never changes, so it could run alongside. Robert has not accepted this change to a settled rule. Mo today runs one thing at a time.

**Mo today.** One caller for each service, with one token. One call at a time. Calls are logged and repeat exactly. Simulation controls time, randomness and the order of events.

**Needs.** Telling callers apart. Grants for each caller, and grants made from grants. Worlds, which need the tree from the storage section. A record of what each world read. Running reads alongside the one writer.

**What would be checked, and with what.** The replay rule is a protocol, so a TLA+ model. "A helper's grant never shows more than the grant it was made from" is a claim about the language, so Lean. Many agents in random orders, checked against the promises, is simulation, and it could be offered to users for their own data ([simulating the user's own workload](wiki/ideas/simulating-the-users-own-workload.md)).

**Earlier work.** In the survey: [Bayou](wiki/systems/bayou.md) and [Zero](wiki/systems/zero.md) replay named writes against an authority that orders them; [Datomic](wiki/systems/datomic.md) and [XTDB](wiki/systems/xtdb.md) send a check with the write; [Chronos](wiki/systems/chronos.md) merges across several stores at once; a Berkeley paper reports that at [Neon](wiki/systems/neon.md) agents made 20 times more branches than people and rolled back 50 times more often; Biscuit tokens narrow a grant without asking its issuer ([narrowed grants](wiki/ideas/attenuated-capabilities.md)). Checked on 2026-11-14 by research: Macaroons (NDSS 2014) let a holder narrow a credential, but checking one needs the issuer's secret key, which Biscuit does not ([findings](research/32-earlier-work-on-grants-as-views-and-requests-as-programs.md)); Retro (OSDI 2010) repaired a system after a break-in by undoing the attacker's actions and re-running only the legitimate actions they had affected ([findings](research/30-earlier-work-on-merging-by-replay.md)). An earlier version of this line described both wrongly from memory.

**Costs and limits.**

- **Flagging too much.** An agent reads many things it does not rely on. Comparing answers, not the data under them, helps. Whether that is enough is unknown.
- **A failed replay costs a new round of thinking,** which costs money. An agent that works for a long time keeps losing to agents that work fast. Claims held as data ease this and do not remove it.
- **A world shows an agent its own changes before they are real.** Anything that leaves the database must run on the main line only, or data that never became real gets out.
- **What nobody declared, nothing catches.** Two changes that break a rule nobody wrote as a promise both land. The log makes this findable and removable afterwards.
- **Taking an agent's work out costs a replay of everything after it.**
- **Reads through a tree of shared nodes are slower.** The survey found no system with shared storage and fast reads.
- **The main line's order is what keeps rules such as "never below zero".** Without an order, only rules where any two valid copies always combine into a valid one can be kept ([Divergent copies and merging](issues/06-divergent-copies-and-merging.md)).

**Open.**

- Which of an agent's reads count as relied on. Decided for the first version, with the finer rule left open ([below](#which-reads-count-as-relied-on)).
- Whether a helper's world must pass through the agent's world or may go straight to the main line.
- What an agent gets back when its replay fails, so that it can plan again without reading everything again.
- Fairness between fast and slow agents.

## Mo with batteries included

Raised by Robert on 2026-11-14. Not decided.

**The idea.** Mo is the framework as well as the language. Everything a program needs is in the language, ships with it, or can be built in it, and that includes the database and its storage. Ruby on Rails is the comparison. The difference is that Rails joins separate things (Ruby, SQL, a database server), and Mo would be one thing.

**Mo already works this way at small scale.** Checked on 2026-11-14:

- A service gets saved state, crash recovery, timers, typed upgrades and MCP tools from a few lines of declaration. One program, `mo`, checks, tests, formats, serves and upgrades it.
- Mo's own rule is that "the library is written in Mo wherever it can be" (`~/code/mo/docs/design/library.md`). 26 files of Mo, 5,683 lines (recounted on 2026-11-14), ship inside `mo`: the library in `lib/`, and the HTTP and MCP handling of `mo serve` in `runtime/`.

**What it would change here.**

- The database stops being a separate product and becomes the first and largest battery: what `state` means once it outgrows memory. This is Picture 2 taken all the way. Picture 1 stays reachable through shared stores (idea 7) and tools.
- A default for every battery: it is written in Mo and ships with Mo. The runtime gains only what Mo code cannot express, such as bytes on a disk, a network connection and a hash. This keeps the settled rule that Mo must not become a language for one database: the language gains general abilities, and the database is a program.
- **Robert on 2026-11-14: this is a default, not a doctrine.** "Not everything should be or even has to be written in Mo." Each part is built in whatever is best for the job.
- Each battery is a driver project. Their order is Mo's roadmap.

**Why it may suit agents.** This is Claude's reasoning, not a finding.

- Frameworks with everything built in lost ground to ecosystems of libraries because nobody could afford to write everything themselves. When agents write the code, that cost falls.
- An agent with no memory does better with one documented way than with a choice of libraries. `mo guide` already ships in the binary.
- One compiler sees the whole program. The joins a framework holds together by convention can be checked: a change to a type that breaks a question, a view or an upgrade is an error before anything runs. Mo already does this for upgrades.

**Earlier work.** In the survey: [Mnesia](wiki/systems/mnesia.md), a database shipped with Erlang; [GemStone](wiki/systems/gemstone.md); [Prevayler](wiki/systems/prevayler.md); [Convex](wiki/systems/convex.md); [SpacetimeDB](wiki/systems/spacetimedb.md); [Cloudflare Durable Objects](wiki/systems/cloudflare-durable-objects.md); the family page [code inside the database](wiki/families/code-inside-the-database.md). [Code inside the database, and databases inside a language](issues/07-code-inside-the-database.md) found that stored procedures failed on version control, testing and deployment, not on code sitting next to data. Checked on 2026-11-14 by research ([findings](research/32-earlier-work-on-grants-as-views-and-requests-as-programs.md)): MUMPS (1967; work began in 1966), a language with a database built in that still runs large hospital systems; Dark, a language with storage built in whose code and data could not leave its hosted service, and whose company ran out of money. An earlier version of this line also named Meteor and Unison from memory; Meteor's storage is MongoDB, an outside database, and Unison's storage comes with Unison Cloud, not the language. Not checked: the business languages of the 1980s and 1990s such as dBase and FoxPro; Smalltalk.

**Costs.**

- Every battery is built and kept working by this project, for good.
- Systems like this are strong inside their walls and weak at them, because the data is reachable only through the language. Object databases lost on this (see Picture 2's costs). Tools over MCP are the door.
- One exception to "written in Mo": the encryption under HTTPS. Writing one's own is a well-known mistake, so it would be a tested outside library behind a capability.
- The list of batteries has no natural end.

**Open.**

- Which batteries, and in what order.
- Whether the database is part of the language, as `state` is, or a library a program chooses to use.
- What keeps the list short.

### What a language with its own framework could look like

Asked by Robert on 2026-11-14. He thinks the idea "has serious legs" and is not yet sure of it. Nothing here is decided.

**Deferred by Robert the same day.** He was thinking out loud and is not proposing a web framework now. When the time comes, the framework should be kept out of the application's way, and it should learn from frameworks that are proven, since what most web applications need is well known. The work goes back to the database battery.

**Three rings.**

1. **The language.** Values, types, functions, capabilities, promises, services. Mo has this.
2. **The batteries.** What every program needs, shipped with Mo and used the same way everywhere: keeping data, answering requests, acting on a schedule, knowing who is calling, reaching the outside, testing, changing while running.
3. **Components.** Ready-made pieces of an application that anyone can build and share, such as accounts, a queue, approvals or notes. A component is a module that brings its own types, promises, tools, views and upgrade path. A service names the components it uses and the compiler checks them together. Adding one to a running service is a proposal a person approves, like any other change to the definition.

**A service file, as a picture.** The first five lines are real Mo from the task queue. The four below them are made up to show what could be declared the same way. The words are not a design.

```
service
  state Queue = JobQueue.empty
  tools submit, lease, heartbeat, acknowledge, fail, list, stats
  every 1.minute expire
  token from env "QUEUE_TOKEN"

  callers from Accounts
  view mine for each caller
  on mail to "queue@example.org" submit
  sends mail
```

The made-up lines say: who may call and what each caller holds; what each caller may see; an event from outside that becomes a call; and that this service is allowed to send something out. Each would be checked by the compiler, faked in tests, and shown to a person when it changes.

**The batteries, by what every program needs.** "Mo today" was checked on 2026-11-14 against `~/code/mo/docs/agent-guide.md` and this file's earlier sections.

| Need | Mo today | Missing |
| --- | --- | --- |
| Keep data | A service's state, saved whole, at most 16 MiB, with crash recovery | The database: everything else in this file |
| State the rules | Promises, which `mo test` checks with generated inputs | Promises over data larger than memory, checked when worlds merge |
| Answer requests | Tools over MCP | Plain web requests; events from outside, such as mail or another system calling in |
| Act on a schedule | `every` timers | Nothing found |
| Work that takes days | A log of calls that repeat exactly; the task queue sample | A standard way to write steps that wait for a person or try again |
| Reach the outside | Files, clock, random numbers and environment for command-line programs; no network | A web client, encryption (an outside library), mail, calling a model. Each a capability with a fake, and each outgoing effect recorded so that it happens once |
| Know who is calling | One token for each service | Callers, grants and views (ideas 1 and 7) |
| Show things to people | Nothing | Unknown. Three options: none, because people talk to their agent; screens made from the types; a full web layer |
| Test | `mo test`, generated inputs, a recovery check for every service, `Simulation` for timers and saved state | Disk and network faults; many agents; users simulating their own workload (idea 6) |
| Change while running | Typed upgrades, `mo push`, `mo review`, `mo intent`. Approvals are recorded and do not yet gate an upgrade | Approvals that gate; agents proposing (idea 1) |
| See what happened | `mo history`, `mo replay` | A log kept for good (idea 4) |
| Learn it with no memory | `mo guide` inside the binary, `mo fix` | Worked examples served by the running service |
| Several services together | Services are islands | Shared stores (idea 7); one service calling another |
| Share pieces with others | Modules inside one program | Components, and a way to fetch them, perhaps by hash |

**How this differs from Rails and its kin.** Claude's reasoning.

- **The reader is an agent.** "Convention over configuration" saved a person's memory. For an agent with none, the equal is one declared way, a guide inside the binary, and a running service that says what a caller may do.
- **The application is alive.** The central loop of a web framework is request and reply. Here it is propose, check, approve, swap, while the service keeps running.
- **Everything outside is a capability with a fake,** so the whole application can be simulated, with time, crashes and other agents, and no mocks are written.
- **One compiler sees data, rules, code, views and upgrades.** The joins a framework holds by convention are checked.
- **Every call is in the log,** so every application gets audit, replay and undo without building them.

**Earlier work.** All from Claude's own knowledge unless a page is linked.

- Erlang with OTP is the closest relative: a language that ships with the standard way to build long-running services, a database written for it ([Mnesia](wiki/systems/mnesia.md)) and upgrades while running.
- Rails was pulled out of one real product, Basecamp. Its author later called it a framework one person can build a whole product with. Rails 8 moved background jobs, caching and live updates onto the database and treats SQLite as fit for production.
- Django was pulled out of a newspaper's website. It makes administration screens from the data definitions.
- PocketBase is one binary holding a database, accounts, file storage, live updates and an administration screen.
- Wing is a language in which cloud resources are ordinary values, with a simulator.
- In the survey: [Convex](wiki/systems/convex.md), [SpacetimeDB](wiki/systems/spacetimedb.md) and [Cloudflare Durable Objects](wiki/systems/cloudflare-durable-objects.md) each put code and its data in one unit.

**Costs and risks.**

- **Frameworks that lasted were pulled out of one real application,** not designed first: Rails, Django and OTP (from a telephone switch). A framework designed ahead of its first application tends to fit none. Each battery should be pulled by a real program that needs it.
- **Size.** A language, a runtime, a database and a framework are each a large project. The danger is spreading thin so that no part gets deep enough to be real.
- **Screens for people are the largest unknown** and the most crowded field.
- The costs listed for batteries above also apply.

**Open.**

- Which real program pulls the first batteries.
- Whether people see screens, and who makes them.
- What a component is exactly, and how components are shared.
- What belongs in the language, what in the batteries and what in a component.

## What the first model and the research found

On 2026-11-14 Robert agreed to start with a TLA+ model of the replay rule. He asked for subagents to try the tools Claude had only read about and to search more widely for papers and tools. Seven research tickets and one model followed. The findings files are sources and are not yet compiled into the wiki ([ticket](issues/34-compile-the-checking-and-earlier-work-research-into-the-wiki.md)). Except where a line says Claude checked it, what follows is as the researchers reported it.

**The replay model** ([results](models/README.md)). The predictions were committed before the model, and all 48 settings came out as predicted.

- The recorded reads alone caught all five mistakes. The function's own check and the promises caught three, the ones that break a declared rule.
- A call that says what it means, such as "add 2", needs no check, and the recorded reads send it back for nothing.
- The model is tiny and leaves out worlds with more than one call. The [second model](#what-the-second-model-found) covers those.

**Many agents** ([findings](research/30-earlier-work-on-merging-by-replay.md)).

- The replay rule is not new. It is known parts in a combination nobody was found shipping. The least precedented part is capturing an agent's reads automatically.
- **Recorded reads are complete and imprecise. Declared rules are precise and incomplete.** A 2026 preprint measured it for agents: guards that block when what was read has changed "needlessly block 92–95% of benign races", a guard that checks a declared rule "blocks none", and deleting one declared clause lets exactly its kind of error through (https://arxiv.org/abs/2609.29522; small local models, one preprint, not reviewed; Claude checked the quotes against its abstract). The model above shows the same two halves. This makes "which reads count as relied on" the first problem of many agents.
- Landing first come, first served starves slow agents. The oldest answer is to fall back to a claim after repeated failure.
- Taking an agent's work out is not a plain replay (see the note under that idea above).

**Storage** ([findings](research/31-earlier-work-on-write-once-trees-and-views-kept-current.md)).

- The shape is proven at the scale of a terabyte by Dolt.
- Garbage grows fast, and every kept version holds it in place. One Datomic user reached over 900 GB on disk for about 40 GB of live data. Dolt reports about 500 GB of garbage a week on a 650 GB database (vendor's own figure).
- History named by hashes pulls against erasing one person's data.
- Views written as arbitrary code cannot be kept current cheaply. Maps, filters, joins and reduces that can be undone can.
- To copy: Dolt's tree, written once for each batch of changes, and CouchDB's contract for views.

**Requests as programs and grants as views** ([findings](research/32-earlier-work-on-grants-as-views-and-requests-as-programs.md)).

- "The request is a program" is an old idea in a new combination. Earlier attempts lost because their data was closed to other tools, unplanned questions were slow, money or programmers ran out, and running foreign code safely was hard. None lost because a program is a worse request than a query.
- A grant as a view function is sound at its core; SpacetimeDB ships read permissions as view functions. It leaks through errors, timing and the order of evaluation inside the view; through allowed totals that combine into facts about one person; and through termination and work limits.
- An earlier system proved a guarantee "for any and all uses" of callers' programs (PINQ, 2009), and it was broken through timing and shared state. The Lean theorem should say that equal views give the same reply, the same error and the same amount of work.

**How to check all this** ([findings](research/29-how-have-storage-engines-and-databases-been-checked.md)).

- Small models written in the code's own language and checked against the code with generated calls give the most for each line. Amazon's later paper reports models under 2% of a 259,000-line system, with three layers of tests finding 20, 46 and 10 bugs the layer before had missed.
- Mo's recovery check restarts a service "on an in-memory store" (Mo's reference, section 12.5; Claude checked the wording). It does not test a disk that loses or tears writes.
- A database that writes down its own order can check its history by replaying it.
- The researcher's plan disagrees with step 3 of the order above: check the real code under simulated crashes, and skip a TLA+ model of the order of writes to disk.

**Tools** (findings: [Veil](research/26-is-veil-a-good-home-for-the-protocol-models.md), [Bend2](research/27-what-is-bend2-and-what-would-proved-laws-mean-for-promises.md), [the others](research/28-which-other-specification-languages-fit.md)).

- **Veil: later.** It built, checked the small protocol, and in about fifteen minutes proved it for any number of agents, which TLC cannot do. It needs Lean 4.35 and Mo pins 4.34 (Claude checked both files). It is young.
- **Bend2: not for checking this design.** Tests and proofs caught different errors: Mo's tests found a counterexample the researcher had missed, and passed a wrong function that the proof refused. The idea to borrow for promises is a law a person writes and freezes, with a proof an agent writes.
- **Alloy 6: add it for rules about grants.** A 31-line model found a narrowing error in one second.
- Quint, P and the rest add nothing here beside TLA+.

**What Claude would change in the order proposed above.** Robert has not accepted this.

1. Next, a model of worlds with more than one call, to settle what lands whole and when promises are checked. Robert agreed to this one on 2026-11-14 and it is done; see the next section.
2. Treat the precision of recorded reads as the first design question for many agents.
3. Put off the TLA+ model of disk writes until the storage design is firmer.
4. Use Alloy when grants are designed.

## What the second model found

A world is an agent's own copy of the data. A call is one use of an approved write function. Robert asked on 2026-11-14 what "a world with more than one call" meant, and then agreed to a model of it. The predictions were committed before the model, and all 40 settings came out as predicted ([results](models/README.md)).

The model lands a world of two calls in four ways and runs six small cases through each.

| Way of landing | What happened |
| --- | --- |
| **Each call by itself, rule after each.** A Mo service today. | A transfer written as "take" then "put" never lands: "take" breaks the rule and is refused every time. Where no rule is declared, the two calls land with a gap. Another agent read the gap and recorded a wrong sum. In another case the second call was refused for ever, and what the first had taken was gone. The recorded reads did not help. |
| **The whole world, rule at the end.** A transaction in an ordinary database. | The transfer lands and five cases come out right. In the sixth an agent combined two approved calls into a change neither could make: "spend" then "close" raised a budget from 2 to 3. The result keeps the rule, so nothing catches it. |
| **The whole world, rule after every call.** | Nothing went wrong in any case. The transfer as two calls never lands. It has to be one approved function. |
| **Each call by itself, rule at the end.** | Meant to fail, and did: the main line broke its rule in between. |

What follows from it:

- **There is a third option.** Claude put two to Robert: the call is the unit, or the world is. Writing the predictions turned up a third: the world lands whole, and the rule is still checked after every call. It is the rule this document already had, with all-or-nothing landing added. No other agent can read a gap, nothing is left half done, and a world can do only what approved calls can do one at a time.
- **Its price.** A change whose middle breaks a rule must be one approved function. The agent proposes it and a person approves it, which is the route Robert decided for new write functions.
- **Under "rule at the end" a write function cannot rely on the rules holding when it starts.** "Close" was safe only because spent is never above the budget. Every function would have to check for itself whatever it relies on.
- **The recorded reads must be run again in place.** Each read is run at its point in the replay, where it sees the world's own earlier calls. Compared with the main line, a world that read its own change is refused for ever.
- **A possible later addition, not modelled:** a person marks one rule as "checked at the end of a world". SQL databases have this as deferred constraints (from memory, not checked). It would allow the two-call transfer for that rule alone.

**Decided by Robert on 2026-11-14: the third option.** A world lands whole, or not at all, and the rule is checked after every call in it. A change whose middle breaks a rule is one approved function. Claude had recommended it at about 75%, the doubt being how often agents would have to propose new functions.

Limits. Every prediction matched, so the model confirmed what was expected and did not surprise; the third option came from writing the predictions. The cases are six, tiny and chosen by hand. Whether real work often needs a change whose middle breaks a rule is not known, and it decides how much the third option's price hurts.

**What Mo has for this today.** Checked on 2026-11-14, after the decision.

- **Landing whole needs no change to Mo.** A tool is an ordinary function from the state to a new state, and the stored state changes only when the tool returns one (reference, section 11.5). A landing tool can run a world's calls on its own copy and return the new state, or a failure and no change. A [sketch](sketches/land-whole/main.mo) does this in 85 lines. `mo test` passes its tests, its promise on generated sequences of landings, and its recovery check. With the check after each call deleted, `mo test` finds the landing that breaks the promise ([how it was run](sketches/README.md)).
- **Mo's service promises are already about steps.** A step promise reads `before` and `after` for every tool call (reference, section 12.2). Checking the rule after every call keeps one call as one step. With the rule at the end, a promise such as "the count never falls" would compare a world's start with its end and could be broken in between. Neither Claude nor the model had weighed this before Robert chose.
- **Still needed:** a promise that is checked when a write lands. In the sketch the rule is written twice, as the promise and as a function the landing tool calls. Idea 2 already names this need.
- **Still needed:** calls as data. The sketch lists the write functions by hand as a choice type and picks one with `case`. A database would have to make that list from the approved functions.
- The sketch has no forks, no recorded reads and no replay on a main line that has moved.

## Which reads count as relied on

**Decided by Robert on 2026-11-14: start simple and measure.** Every question counts, answers are compared, and the database counts needless send-backs. The finer rule is chosen when there is a number. The first model and the research both named this as the first problem of many agents. Landing whole worlds makes it sharper: a world with more calls has asked more questions, so more can change under it.

**The problem.** At landing the database asks the agent's questions again. A changed answer sends the whole world back and the agent starts over. That is safe and wasteful, because an agent reads much that it does not rely on.

**The answers on offer.** The first five are from the research ([findings](research/30-earlier-work-on-merging-by-replay.md)). The last two are Claude's.

| Answer | What it gives | What it costs |
| --- | --- | --- |
| 1. Every question counts | It caught every mistake the first model tried | The most needless send-backs |
| 2. The agent says which answers it relied on | Precise | Agents rarely say, and whatever is left out goes unchecked |
| 3. Compare answers, not the data under them | A change that leaves the answer alone does not count | A changed answer that did not matter still counts. This is already in the design |
| 4. The rules decide and the questions do not | No needless send-backs | It misses whatever no rule declares. In the first model that was the discount worked out from a changed price, and the lost update |
| 5. Follow what depends on what inside the program | Only what was affected runs again | It needs code that can be analysed, and an agent's thinking is not |
| 6. The write function names the facts it relies on | The judgement moves from the agent to approved code. "Set the discount" relies on the price. "Add 2" relies on nothing | Each function's author must say it, a person must approve it, and an omission is a hole |
| 7. Hold, show and confirm | The world is kept. The agent sees which answers changed and confirms its calls or makes them again. The confirmation goes in the log | The 2026 preprint saw agents, after a block, "re-commit unsafely from refreshed but still-incomplete reads" |

Answer 6 extends a line already in this document: for each write function a person approves what a changed answer does (let it through, send it back, or hold it for a person).

**What cannot be known from here.** How often a send-back is needless in real use. One preprint measured 92 to 95% for a related guard, with small models. A TLA+ model can show which mistakes each answer lets through. It cannot show how often they happen.

**Claude's recommendation.** Start with answers 1 and 3 together: every question counts, and answers are compared. Have the database count needless send-backs. A send-back is needless when the agent's next world holds the same calls; an agent that words the same change differently is missed, so the count is a floor. Choose between answers 6 and 7 when there is a number. This follows Robert's steer of 2026-11-14 to keep performance in mind and optimise later. Answer 6 can be added later, one function at a time, without changing the first rule. Robert agreed on 2026-11-14. Claude was about 80% sure, the doubt being that the count exists only once something is built.

## Which half first

Reopened by Robert on 2026-11-14 after the measurements: "It doesn't really matter to me which one comes first. I'm in no rush." He asked for the trade-offs of each order and for an outside review by other models. Nothing here is decided. The review came back the same day and is summarised at the end of this section, with Claude's recommendation after it.

**The two halves.**

- The upper half is what an agent or a person touches: the data as Mo types, promises as the schema, write functions a person approved, read programs, grants as view functions, proposals, a world for each agent and how it lands, the log as history.
- The storage half is how the data is kept: a state larger than memory, writing only what changed, a version that costs no copy, finding things without walking everything, and what Mo's runtime must gain for these.

**Upper half first.** It is built on Mo's services as they are: one service, with the whole state in memory and saved whole.

What it gives:

- The ideas that are new, and least certain, are tried first and with real data.
- It asks little of Mo's runtime. It asks more of the language: accepting a program while running, more than one caller, calls as data, promises checked when a write lands.
- What the upper half needs from storage is known before storage is built.

Its issues:

- The measured limits apply: about 125,000 small rows, a write that costs more as the data grows, a read that waits behind a write, 10 ms on every call and 20 calls a second, a request of 16 KiB and a reply of 32 KiB.
- The upper half's own ideas lean on storage. A world, a snapshot for a read program and an old state are each a version. In Mo today a changed copy of a map is a whole copy, so each version costs a copy, in memory and in the one saved state. Saving makes it worse than the map alone. A saved value writes shared data out in full, and the service then loads that copy back (`docs/design/saved-state.md`: "Sharing is expanded, not serialized"). A collection that shares its parts by reference loses the sharing at every write.
- A snapshot deletes the log, so "the log is the truth" cannot be built on today's store as it is. Reads are never logged, so recording what an agent asked needs something new as well.
- The write functions would be written against Mo's `Map`. If storage later brings a different collection, they are written again, unless a small module hides the collection from them.
- Times taken on it say little about the finished design. Counts, such as needless send-backs, carry over only in part: how often two worlds collide depends on how long each stays open, which depends on speed.

**Storage half first.**

What it gives:

- The ceiling and the growing cost of a write go first.
- Versions that cost no copy exist before worlds, snapshots and history are built on them, so those are built once.
- It is the half that asks most of Mo's runtime: bytes at an offset, forcing data to disk, a hash, a tree-shaped collection, reads beside the writer.
- It is the better-trodden half, with known designs and known ways of checking them.

Its issues:

- It is built for needs the upper half has only guessed at. Whether nodes need names by hash, how long history is kept and whether views are kept current all come from ideas not yet tried. One reviewer disputes this and two agree; see the end of this section.
- It changes Mo's runtime at once. That reopens the parked question of memory safety and the question of how the work sits beside Phases 6 to 8.
- Nothing of Robert's is in it, and no agent uses it, until the upper half follows.
- Both outside reviews earlier on 2026-11-14 warned about this half: one said to build a storage engine only if a guarantee needs it, the other never.
- It does not touch the 10 ms on every call, which is not a storage cost.

**What ties the halves together.** Two things: the type the data lives in, and whether a version costs a copy. Whichever half goes first settles these two for the other. The reviewers added three more: how a function reaches data that is not in memory, what is committed before a reply is sent, and how a storage failure shows in a function that is meant to be pure.

**Other orders.**

- The seam first: decide the collection the data lives in and what a version is, as an interface, then build either half against it.
- One thin slice through both: one write function, one world and one read program, on the smallest store that writes only what changed.
- A change to how Mo saves a service's state, apart from any database, since the growing cost is Mo's.
- Measure first whether agents write correct read programs. It needs neither half (a reviewer's addition).
- A third track beside both: the call path. At 10 ms a call, 20 calls a second, 16 KiB a request and 32 KiB a reply, those limits bind before storage does for many agents (a reviewer's addition).

**What would decide it.** Which half holds more that is unknown. Which rework costs more: write functions written again, or storage built for the wrong needs. Which part of Mo Robert wants to grow first. "Usable sooner" is not a reason, by the map's notes.

**What the council said, 2026-11-14.** Three models from three providers read this file, the map, the measurements and Mo's code. They were briefed without Claude's view and changed nothing. Their reviews are kept word for word in `raw/council-2026-11-14-which-half-first/`, and the record is on [Which half comes first?](issues/36-which-half-comes-first.md).

| Reviewer | Builds first | Its confidence |
| --- | --- | --- |
| GPT Sol | A small runnable sketch of the boundary between the halves, then one thin slice through both, with storage that writes only what changed | 85% |
| Gemini Carbon | A versioned collection with explicit identifiers for its nodes, in memory, behind a seam; then the upper half; storage on disk last | 75% |
| Claude Opus | The seam from the storage side: a versioned collection and a saved form that keeps sharing; then a thin slice of the upper half | 65% |

- **All three:** not the upper half on today's services, not the whole storage half, and an experiment before committing.
- **Two of three** put a versioned collection before the upper half. GPT Sol does not; its first step is the sketch.
- **Split on disk:** Gemini Carbon leaves it for last. The other two put a new way of saving in the first slice.
- **Split on whether storage's needs are known:** Claude Opus says the decisions of 2026-11-14 fix them. The other two say they depend on upper-half rules not yet settled.
- **Not settled by the reviews:** whether versions can be cheap in a library written in Mo, with explicit identifiers, or only after Mo's saving changes. One reviewer proposes the first and one says only the second works. A sketch can settle it.

**Claude's recommendation after the council.** Not decided by Robert.

1. Sketch a versioned collection in Mo today, with explicit identifiers for its nodes. The control shares nodes by reference and is predicted to cost a full copy for each kept version.
2. Measure the saved size with N kept versions, and the steps for an insert and a lookup against `Map`.
3. Run one workload on it: two worlds that overlap, a narrowed view, and a landing with the rule checked after every call.
4. Decide the order after that. The sketch is what tells a library apart from a change to Mo's runtime.

**Decided by Robert on 2026-11-14: the sketch comes before the order.** "I think you should open a prototype ticket and build that sketch. Before we choose the order." It is [Can a Mo library keep old versions cheaply today?](issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md), with its predictions written before any code.

**Robert's idea on 2026-11-14: vertical slices, not one half and then the other.** Raised while the sketch was being built, and kept for a follow-up at his request. He decided for it the same day, below.

- His words: "Instead of developing out the whole front half and then the storage." He would rather design part of the upper half and part of the storage together, as several small spikes and experiments, and see which seems to work best.
- A vertical slice is one small job carried the whole way down: something an agent does, the rule that guards it, and the way its data is kept.
- Claude's note: this is close to what GPT Sol recommended, one thin slice through both halves, and it removes the question of which half comes first. What it leaves open is which slices, in what order, and what each must show before the next. The workload in the sketch is a first small slice: worlds, a view and a landing on a collection that keeps versions.

**What the sketch found, 2026-11-14.** In full on [Can a Mo library keep old versions cheaply today?](issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md). Five of six predictions held; the sixth was right in outcome and wrong in cause.

- **Kept versions are cheap in space today.** A tree whose nodes sit in one map and name their children by number keeps a version for 778 bytes when saved, at 1,000, 10,000 and 50,000 rows, and the old versions are there after a restart. Mo needs no change for it.
- **The other ways cost a whole copy.** A tree by reference and a list of whole maps each add one full copy for every kept version, on disk and in memory. At 10,000 rows they were refused for memory after 19 and 13 kept versions; at 50,000 rows after 3 and 2.
- **A write is no cheaper.** In a service a write to the tree takes 1.1 to 1.5 times as long as a write to a plain `Map` of the same rows. The cost that grows with the state belongs to the service: it copies the map and encodes and decodes everything on every write.
- **Outside a service** the tree's lookup takes about 13 times a `Map` lookup and its insert 33 times. It is not tuned.
- **Worlds fit on it.** A world starts as one number. Two worlds that do not overlap both land. The second of two that asked about the same row is sent back, and nothing changes. A view narrows what a world may ask and change.
- **Three things Mo itself stands in the way of.** A map that sits in a record is copied every time it changes, so the tree had to be a bare map. A call's instruction limit is reached by a few hundred tree inserts. A service's state cannot hold a function, so a view is a named function.

What follows for the order: worlds, history and kept versions do not wait for the storage half. What the storage half must fix is that every write costs in proportion to all of the state, in time and in memory.

**Claude's recommendation after the sketch.** Not decided by Robert. Take up his vertical slices in place of choosing a half. The sketch removed the one reason to put storage first for the sake of versions, and it showed that a slice through both halves can be built and measured in one session.

**Decided by Robert on 2026-11-14: vertical slices.** "Yes to vertical slices." Neither half is built first, and the order of the halves is no longer a question ([Which half comes first?](issues/36-which-half-comes-first.md)).

**Claude's proposed slices.** Not decided by Robert. They are also on [Which vertical slices, in what order, and what must each show?](issues/38-which-vertical-slices-in-what-order.md). Replaced the same day by the revised proposal below, after the council.

| # | Slice | What an agent does | How the data is kept | What it must show | From Mo |
| --- | --- | --- | --- | --- | --- |
| 1 | A world over the wire | Opens a world on a running service, asks, acts and lands, while a second agent does the same | The tree by number, in a service's saved state | The worlds of the sketch survive being a real service that restarts; what the list of tools looks like to an agent; what an ask, an act and a landing each cost at 1,000 and 50,000 rows | Nothing |
| 2 | A rule and a view over many rows | Lands a transfer among many accounts, and reads only its own rows | Totals kept in the tree's branches, so a check reads one path and not every row | The rule check and the narrowed read cost the same at 1,000 and 50,000 rows | Nothing |
| 3 | A read program | Writes a small Mo function that answers its question, in place of a query, and runs it on a kept version | An exported state at first, run with `mo query` | Whether an agent with only Mo's guide writes a correct read program at the first try; what one costs; what Mo lacks to run one on a live service | Measured, not built |
| 4 | A write that costs what it changes | Changes one row | Only the changed nodes are written; the tree by number knows which they are | How much is written and how long it takes against saving everything; exactly what Mo's service would have to change | A change to Mo to build it; here it is measured and modelled |
| 5 | A proposal a person approves | Proposes a new kind of call; a person reads what becomes possible and approves it | The state carried across an upgrade of the service | The accountable write holds when the set of approved calls changes | Nothing known |

- **Each slice is one prototype ticket,** with its predictions written first and a control that must fail, as [Can a Mo library keep old versions cheaply today?](issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md) was.
- **Recommended first: slice 1.** Every other slice hangs on what an agent sees and does, and it needs nothing from Mo. Slice 2 comes next because slice 1 is only honest at size once a rule does not read every row.
- **Slice 4 is the storage half's real question.** The sketch showed that versions are not: every write costs in proportion to all of the state. Building slice 4 for real means changing Mo, which this map rules out, so here it can only be measured and modelled.
- **A stop rule.** Slices are experiments and the map's destination is a decision. Claude's worry is a string of sketches that never ends in one. After these five, or sooner if two in a row change nothing, the decision is written.

**Decided by Robert on 2026-11-14: the council and Jev before the slices are chosen.** "Use the council and jev before we decide and choose." Three reviewers from three providers read this repository as it stood before the proposal above was written. The full account, with every claim that was checked, is on [the ticket](issues/38-which-vertical-slices-in-what-order.md); the reviews are in [raw/council-2026-11-14-which-vertical-slices](raw/council-2026-11-14-which-vertical-slices/).

**What the council found.**

- **All three chose the same first slice, and it is not Claude's.** An agent's real questions (a sum, a filter, a count) are answered by read programs, recorded, and checked again when the world lands. Claude had put worlds on a running service first. The reason given: "every question counts, by its answer" is decided, and its only test asks for single keys, which cost almost nothing to ask again. Landing runs inside a call's limit of about a million instructions.
- **All three named the same risk:** slices that each pass alone and do not fit together. Their guard is one sketch carried through every slice. One reviewer adds a list of stand-ins at the end of each slice: whatever simpler thing stood in for the real one, and what would replace it.
- **All three tie the stop rule to the map's destination:** stop when each of its five items rests on a slice's result.
- **All three have a slice Claude did not:** what an agent is allowed to do changes while its world is open.
- **They split on real data.** Two put it in the first slice. One puts it in the second, once the choice of data is made.
- **A gap in these notes.** Mo's `mo query` was missing from them; see "What Mo has today".
- **Claude's predictions of the reviews were poor:** 7 of 22 came out as predicted, 7 differed and 8 were not settled.

**Claude's revised proposal.** Not decided by Robert.

| # | Slice | What it must show |
| --- | --- | --- |
| 1 | Questions asked again at landing | Whether asking a sum, a filter and a count again fits inside one call at 1,000, 10,000 and 50,000 made-up rows, and what the same questions cost through `mo query` |
| 2 | Two agents on real data through a running service | The share of send-backs that were needless. It waits for the choice of real data |
| 3 | What an agent may do changes while its world is open | A grant withdrawn or a proposed function approved between opening and landing; checking authority only at the opening must wrongly land withdrawn work |
| 4 | The kept log | Taking one agent's calls out and replaying the rest; a lost reply tried again without landing twice |
| 5 | Storage: writing only what changed, and freeing versions nobody holds | Measured or modelled, since a Mo service does neither today |

- **Only the first slice needs choosing now.** Its result reshapes the rest.
- **Keeping totals, Claude's old slice 2, is no longer a slice of its own.** It is one of three ways out if asking again does not fit in a call. The others are a write function that names the facts it relies on, and checking outside the call.
- **Guards:** one sketch through every slice; a list of stand-ins at the end of each; the decision cites only results whose stand-ins it names.
- **The stop rule:** the decision is written when each of the map's five items rests on a slice's result, or after five slices, whichever comes first.

**Decided by Robert on 2026-11-14: the first slice.** Asked whether the first slice should be "questions asked again at landing", on made-up rows, he answered "Yes". It is the ticket [Can a landing ask an agent's questions again inside one call?](issues/39-can-a-landing-ask-an-agents-questions-again.md). His answer covers the first slice only: slices 2 to 5, their order, the guards and the stop rule are still Claude's proposal, and are looked at again when the first slice reports.

## Deep dives for later

Robert on 2026-11-14: "Many of these ideas require their own deep dives later." This list keeps them from being lost. None is a ticket yet.

- **Request programs** (idea 1): limits on cost, what a read program may compute, how answers leave.
- **Grants as view functions** (ideas 1 and 7): how "only these rows" is written and checked.
- **Proposals** (idea 1): what a person is shown, as "what becomes possible".
- **Promises as the schema** (idea 2).
- **Upgrades as migrations** (idea 3), for data larger than memory.
- **The log** (idea 4): kept for good, erasing a person's data, replaying after code changes.
- **Simulation offered to users** (idea 6).
- **Unplanned questions** (idea 8).
- **Sensitivity in the types** (idea 9), and whether data that protects itself is in the first version.
- **Storage:** the tree of write-once nodes, what a change costs, clearing old versions, library or runtime.
- **Views the database keeps current,** and which form of view allows it.
- **Code stored by hash.**
- **Storage laid out by type,** and a key for each sensitive field.
- **Many agents:** the replay rule, which reads count as relied on, fairness, taking one agent's work out.
- **Worlds with more than one call:** modelled and decided on 2026-11-14. A world lands whole, with the rule checked after every call.
- **A rule checked at the end of a world,** marked rule by rule by a person.
- **A write function that names the facts it relies on.**
- **Counting needless send-backs,** so that the rule for reads is chosen from a number.
- **Promises that can be checked when a write lands,** so a rule is written once.
- **Calls as data,** made from the approved functions and not listed by hand.
- **How often real work needs a change whose middle breaks a rule,** which decides the price of checking after every call.
- **A long world sent back for ever,** since a world with more calls reads more.
- **Clearing old versions,** given how fast garbage grows.
- **The 10 ms on every call,** which is Mo's HTTP layer run as bytecode: whether the database lives with it, pays it once for many reads through a request program, or Mo makes it cheaper.
- **The saved copy on every write:** whether a state can be saved without encoding and decoding all of it, and what Mo's check "refuse a state it cannot save" would need in its place.
- **A read that waits behind a write,** measured at 91 ms beside back-to-back writes at 125,000 rows.
- **Vertical slices** (decided by Robert, 2026-11-14): which slices, in what order, and what each must show before the next. Now [a ticket](issues/38-which-vertical-slices-in-what-order.md), with a council's three slates and Claude's revised proposal. Robert chose the first slice on 2026-11-14; the rest waits for its result.
- **Asking a question again at landing,** when the question is a sum or a filter and not one key: what it costs, and what replaces it if it does not fit in a call. The first slice, [a ticket](issues/39-can-a-landing-ask-an-agents-questions-again.md) since 2026-11-14.
- **Authority that changes while a world is open:** a grant withdrawn, or approved code replaced, between a world's opening and its landing. Raised by all three reviewers on 2026-11-14.
- **A lost reply and a second try,** which must not land twice. Mo does not remove duplicate requests.
- **An agent that has never seen the database,** as the test of whether read programs can be written without help.
- **Read programs through `mo query`:** it runs a caller's function today, outside the service and on an exported copy.
- **Freeing the nodes of a version nobody keeps.** The tree by number never frees a node; a long-lived one grows until the library can.
- **A map in a record is copied on every change.** A matter for Mo: where it belongs, and whether a library should have to work around it.
- **A call's instruction limit against a library collection.** 400 tree inserts fit in one call and 1,000 do not.
- **The seam between the halves:** the collection the data lives in, and what a version costs.
- **How a write function reaches data that is not in memory:** fetching by name, paging by the runtime, or views kept ready. Each asks something different of Mo.
- **Recording reads,** which Mo does not log today.
- **Whether agents write correct read programs,** which `learnability/` in Mo could measure.
- **Running a read program without upgrading the whole service.**
- **The limit of about a million saved nodes,** which rows with several fields may reach before the memory ceiling.
- **One write at a time** in place of one operation at a time. This changes a settled rule.
- **What the runtime must gain:** bytes at an offset, forcing data to disk, a hash, a tree-shaped collection, running reads alongside the writer.
- **Batteries:** which, in what order, and what keeps the list short.
- **Components:** what one is and how they are shared.
- **Screens for people.**
- **Reaching the outside:** a web client, the encryption library, calling a model, outgoing effects that happen once.
- **Work that takes days.**
- **Whether the database is a separate product or Mo's first battery.**
- **Promises that are proved, not only tested,** as Bend2's laws are.
- **The framework and its batteries,** deferred by Robert on 2026-11-14.
- **The first real program** that pulls all of this.
- Parked on tickets: [How does Mo's runtime become memory safe?](issues/24-how-does-mos-runtime-become-memory-safe.md) and [Earlier work on purpose and approval](issues/25-earlier-work-on-purpose-and-approval.md).

## How these sit with what is already decided

- The accountable write stays the centre. Ideas 2, 4 and 7 are how it would be built; idea 1 extends it to reads.
- Every question an agent asked counts at landing, by its answer, and needless send-backs are counted ([decided on 2026-11-14](#which-reads-count-as-relied-on)).
- A world lands whole, with the rule checked after every call ([decided on 2026-11-14](#what-the-second-model-found)). This keeps the accountable write: a world can do only what approved calls can do one at a time.
- Robert accepted building the upper half first. Every idea above belongs to the upper half. He reopened the order on 2026-11-14 ([Which half first](#which-half-first)), decided that a sketch comes before the order, and after it chose vertical slices in place of choosing a half.
- [Mo with batteries included](#mo-with-batteries-included) would rename the effort: not a database beside Mo, but Mo's first battery. Robert has not decided this.
- The runtime questions under the storage engine are parked on [How does Mo's runtime become memory safe?](issues/24-how-does-mos-runtime-become-memory-safe.md).
