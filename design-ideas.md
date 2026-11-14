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
- **Needs:** a way to accept, check and run a program that arrives while the database is running, holding only what its caller holds (the upgrade path is the nearest thing Mo has); a snapshot to run it on.
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

**Two ways to build it.** As a library written in Mo, where a tree's nodes are loaded by name through a capability: everything is ordinary Mo that `mo test` can simulate and the Lean model covers. Or inside the runtime, where any Mo value can quietly live on disk: more powerful, but it hides which step touches the disk. Claude's lean is the library first.

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
- **The promises are the rule over the merged result.** They are checked after every replayed call, so two changes that are each fine alone and wrong together stop at the second.
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

**Take one agent's work back out.** The log holds every call with its caller. To remove what one agent did, because injected text misled it or because it was wrong, replay the log from before its first call and leave its calls out. The later calls that are now refused, or whose recorded answers now differ, are the ones that depended on the removed work. This is an answer to the open question under idea 4. It cannot recall anything that already left through a release function.

**Agents see each other through data.**

- A claim such as "I am working on form 42" is an ordinary record written by an ordinary write function, as `lease` and `heartbeat` are in Mo's task queue today. No lock manager is needed.
- "Tell me when this answer changes" is a view the database keeps current (see [Storage underneath](#storage-underneath)).

**The first-version rule, made narrower.** Settled earlier: one operation runs at a time. The survey's evidence against that rule is that agents' exploring, not their writing, becomes the bottleneck. Under this design only writes to the main line must run one at a time. A read program or a world works on a root that never changes, so it could run alongside. Robert has not accepted this change to a settled rule. Mo today runs one thing at a time.

**Mo today.** One caller for each service, with one token. One call at a time. Calls are logged and repeat exactly. Simulation controls time, randomness and the order of events.

**Needs.** Telling callers apart. Grants for each caller, and grants made from grants. Worlds, which need the tree from the storage section. A record of what each world read. Running reads alongside the one writer.

**What would be checked, and with what.** The replay rule is a protocol, so a TLA+ model. "A helper's grant never shows more than the grant it was made from" is a claim about the language, so Lean. Many agents in random orders, checked against the promises, is simulation, and it could be offered to users for their own data ([simulating the user's own workload](wiki/ideas/simulating-the-users-own-workload.md)).

**Earlier work.** In the survey: [Bayou](wiki/systems/bayou.md) and [Zero](wiki/systems/zero.md) replay named writes against an authority that orders them; [Datomic](wiki/systems/datomic.md) and [XTDB](wiki/systems/xtdb.md) send a check with the write; [Chronos](wiki/systems/chronos.md) merges across several stores at once; [Neon](wiki/systems/neon.md) reports that agents made 20 times more branches than people and rolled back 50 times more often; Biscuit tokens narrow a grant without asking its issuer ([narrowed grants](wiki/ideas/attenuated-capabilities.md)). From Claude's own knowledge and not in the survey: Macaroons (2014) narrow a credential the same way; Retro (2010) repaired a system after a break-in by re-running everything except the attacker's actions.

**Costs and limits.**

- **Flagging too much.** An agent reads many things it does not rely on. Comparing answers, not the data under them, helps. Whether that is enough is unknown.
- **A failed replay costs a new round of thinking,** which costs money. An agent that works for a long time keeps losing to agents that work fast. Claims held as data ease this and do not remove it.
- **A world shows an agent its own changes before they are real.** Anything that leaves the database must run on the main line only, or data that never became real gets out.
- **What nobody declared, nothing catches.** Two changes that break a rule nobody wrote as a promise both land. The log makes this findable and removable afterwards.
- **Taking an agent's work out costs a replay of everything after it.**
- **Reads through a tree of shared nodes are slower.** The survey found no system with shared storage and fast reads.
- **The main line's order is what keeps rules such as "never below zero".** Without an order, only rules where any two valid copies always combine into a valid one can be kept ([Divergent copies and merging](issues/06-divergent-copies-and-merging.md)).

**Open.**

- Which of an agent's reads count as relied on.
- Whether a helper's world must pass through the agent's world or may go straight to the main line.
- What an agent gets back when its replay fails, so that it can plan again without reading everything again.
- Fairness between fast and slow agents.

## How these sit with what is already decided

- The accountable write stays the centre. Ideas 2, 4 and 7 are how it would be built; idea 1 extends it to reads.
- Robert accepted building the upper half first. Every idea above belongs to the upper half.
- The runtime questions under the storage engine are parked on [How does Mo's runtime become memory safe?](issues/24-how-does-mos-runtime-become-memory-safe.md).
