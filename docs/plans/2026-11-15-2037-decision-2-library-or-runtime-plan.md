# Plan to settle Decision 2: is the store a library written in Mo or part of the runtime?

Created: 2026-11-15

Status: a plan for Robert to accept, change or cut. Nothing runs until he does. It writes no database code and changes nothing in `~/code/mo`.

## 1. The question, and why it is next

**The question.** The data store keeps a tree of nodes that are written once, the roots that name versions, the log of calls, and the freeing of old versions (`design.md` section 4). A node is one block of the tree on disk. A root is the name of the top node of one version. The question is where that code lives. It can be Mo code that loads nodes through a capability, which is a value that grants access to something such as files. It can be part of the C runtime, so that any large Mo value lives on disk. Or it can be split between the two. `design.md` section 9 leaves this open, and `experiments.md` lists it under "Decisions waiting" with no experiment designed.

**Why it is next.**

- Robert closed Decision 1 on 2026-11-15 by accepting the rule for reads and writes. Under that rule the compiler plans every read and keeps answers current as writes land. That pushes the store toward the compiler and the runtime.
- The other three waiting decisions depend on where the store lives: the log through an upgrade, names by hash or by number, and whether a write may open a held value.
- Claude recommended taking it next at 65%. The doubt was that the rule's smaller open items could be closed first. Robert answered "Yes" and asked for this plan.

## 2. The options

Under every option the application code is the same, because tables are part of the language and the compiler plans the reads. The options differ in what the planned code calls, and in what Mo gains.

| | Option | What it is, precisely | What it gives | What it costs |
| --- | --- | --- | --- | --- |
| L | Library | The whole store is Mo code: tree, node cache, log, roots, freeing. Mo gains only general abilities: bytes at a place in a file, a hash, and a way for a service to hold the store (section 8, lines 1 to 3). The compiler's planned reads call this library | Every disk step is Mo code, so `mo test` can simulate it and Mo Core's Lean definition gives it a meaning. A failed read can be a typed error inside the store | A service must be allowed to hold a capability, which Mo forbids today (reference section 11.5). The node on disk and the Mo value in memory are two things, so each visit decodes or goes through a cache. Only tables gain; other Mo values do not. Freeing is the library's work |
| R | Runtime (idea 6, "the store is the heap") | A large `Map`, `Set` or `List` has a tree form. Its nodes are written once and named by hash. The runtime reads a node in when code touches it. A service's saved state is the tree. The log, roots and freeing are in the runtime too | Every Mo service gains large state and cheap versions with no library. A read needs no capability and stays pure, because a hash always names the same bytes. Freeing can be exact by counting holders, because Mo values have no cycles | The disk steps are C, outside Mo code and outside the Lean definition. A failed read must fail the whole message. Counts kept on disk must survive a crash. Policy (history, erasure, worlds) is fixed in C or needs hooks |
| S | Split | The runtime gives two things: a collection whose copies share nodes (line 4), and node reading and writing by name, with a hash (lines 1 and 2). The store's policy is Mo code on top: the log of calls, roots, holders, views kept current, history, erasure | Other programs gain the shared collection and large state. The policy stays Mo code that `mo test` checks. The C part is small and has one job | The boundary must be designed. One side must own freeing. The runtime's disk steps still need their own crash testing |

Notes on the option set:

- **No fourth option is added.** "Library first, runtime later" is a build order and not a design. The steer is to design for where Mo should go, so it is cut (section 8).
- **L is narrower than when it was first written.** Section 8 line 4 already asks Mo for a shared collection "for the tree". If that collection is a runtime type, L and S differ on one point only: whether the runtime's collection knows about the disk.

## 3. What is already settled and constrains the options

| Settled | Source | What it does to the options |
| --- | --- | --- |
| Tables are part of the language and the compiler plans every read | `design.md` section 7, decided by Robert | Application code never names a capability or a node. L's "the disk step is visible" holds only inside the store's own code |
| The accepted rule: the compiler keeps indexes and answers current, and reports every plan | `design.md` section 5, accepted 2026-11-15 | The compiler emits store operations under every option. Some of the database is in the compiler whatever is chosen |
| Robert's test: anything Mo gains is an ability other programs would also use | `design.md` section 8 | Each piece an option puts in the runtime must pass it. It is the main test between R and S |
| Do not narrow by today's Mo, build cost or learnability | Robert's steer, `experiments.md` header | "R needs more C" and "L is cheaper to build" are not reasons. Today's interpreter speed decides nothing |
| The store runs in the application's process, and the whole application runs under `mo test` with a fake disk and clock | `design.md` section 3 (Claude's draft, not marked decided) | Every option must say how its disk steps are simulated |
| The order of writes: nodes, then the log forced, then the root switch | `design.md` section 4 | The same in all three. It does not choose between them |
| Mo promises what operations cost, not how values are stored | Mo reference section 13.3 | A tree form for a large `Map` is allowed by the language as written. This helps R and S |
| A service's state, inputs and results hold no capability | Mo reference section 11.5 | L needs this rule changed. R and S do not |
| Mo's recovery check crashes "between steps, never inside a commit", on an in-memory store | Mo reference section 12.5 | Today the runtime's own disk steps are not crash-tested by `mo test`. Line 11 is needed under every option |

## 4. The questions that decide

| # | Question | Favours L if | Favours R if | Favours S if | Settled by |
| --- | --- | --- | --- | --- | --- |
| Q1 | Who else gains? | Few Mo programs hold growing state | Most services hold a growing collection and would gain with no code change | The same as R, and those programs need none of the store's policy | Experiment 15 |
| Q2 | Can the policy be Mo code over two node operations? | The policy needs to see inside nodes all the time, so the boundary is wide | The Mo part is tiny or awkward, so it may as well be in the runtime | The policy is small, clear Mo and needs only "put a node" and "get a node" | Experiment 16 |
| Q3 | What does L ask of a service? | The capability threads through cleanly and replay stays exact | Every function down to the node read must carry the capability, and the compiler would have to hide it | The same as R | Experiment 16, second backend |
| Q4 | Is freeing by counts on disk safe through a crash with a simple protocol? | No. Holders with a sweep are simpler | Yes, with no extra log | No. Freeing then belongs to the Mo policy | Experiment 17 |
| Q5 | What does a failed read mean? | Programs need a typed error from a table read | A failed message is enough | A failed message is enough | Argument. Under tables in the language `shop.stock.get(item)` gives an `Option`, so even L must fail the message or change the type of every read. Claude holds this at 80% |
| Q6 | Does the inherent cost differ? | | | | Argument. The planner is in the compiler under every option, so nodes read and written are the same by construction. Prefetch from knowing the loop is open to all three. Only constant factors differ, and those may not decide |
| Q7 | Must any large value live on disk, or only tables? | Only tables | Any value, such as a large list inside a row or a service state with no table | Either; S can stop at collections | Robert, one question (section 6, step 6) |
| Q8 | What do the Lean definition and `mo test` cover today? | They cover Mo's file and service steps but not collections' storage | Collections are abstract in Lean, so a tree form changes no meaning | The same as R | Reading `~/code/mo/formal/` and `runtime/`, before any experiment |

## 5. The experiments

House rule for each: predictions with a confidence are written in `experiments.md` and committed before any run, and are never edited after. Code is committed before the full run. The result goes in a dated "Result of experiment N" section. The predictions below are Claude's drafts.

All runs use the frozen Mo binary at `build/enforcement-trial/mo`, recorded in `sketches/enforcement-trial/freeze.md`, and Python stand-ins. None writes to `~/code/mo`. None times anything.

| # | What it tests | How | Result that favours which | Draft prediction | Control that must fail | Cost | What the decision loses if cut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 15 | **Who else gains (Q1).** How many existing Mo programs hold state that grows | A Python script reads the service blocks and state types in `~/code/mo/examples/`, `~/code/mo/services/` and the agent-written Mo in `~/code/mo/learnability/`. It labels each program: state holds a collection that grows with use, or not. It lists by hand which would also want the store's policy (history, a log they own) | A large share that grows and wants no policy favours R or S. A small share favours L. A large share that also wants history favours R over S | 60% or more of services hold a growing collection, at 70%. Fewer than a third of those want history, at 55% | A planted service with an `Int` state must count as not gaining. A planted one with a growing `Map` must count as gaining | 2 to 3 hours | Robert's test is applied by assertion only. This is the cheapest experiment and speaks to his own test |
| 16 | **Policy in Mo over two node operations, with two backends (Q2, Q3).** Whether log, roots, holders and freeing can be Mo code that `mo test` checks, and what L asks that S does not | Extend `sketches/kept-versions/` (which does not yet free anything). Write the policy once in Mo over `put(node)` and `get(name)`. Backend A is a bare `Map` standing in for the runtime (S). Backend B is one text file for each node through the `Files` fake (L). Nodes are named by number, as Mo has no hash. Promises under `mo test`: no kept version reaches a freed node; replaying the calls gives the same root. Count the lines of policy, the operations that cross the boundary, and the functions that must carry the capability under B | A small policy with a narrow boundary favours S. A policy that must open nodes on most operations favours R or L. Under B, a capability on every function down to the read counts against L, because the compiler would have to hide it | The policy passes over both backends, at 75%. Freeing needs a third operation that lists a node's children, at 65%. Under B every read function carries the capability, at 90% | Free a node without asking the holders: a promise must fail. Put backend B in a service's state: `mo check` must refuse it under section 11.5 | 1 to 1.5 days | S stays a drawing, and L's cost to a service stays a reviewer's remark |
| 17 | **Freeing through a crash: holders against counts on disk (Q4).** Whether idea 6's "garbage is exact" survives a crash inside a commit | A TLA+ model in `models/` (TLA+ is a language for checking every ordering of steps in a protocol). Steps: write nodes, force the log, switch the root, free. Two schemes: holders with a sweep from kept roots, and a count of holders stored on disk for each node. A crash may fall between any two disk steps. Properties: no kept version reaches a freed node; after recovery nothing unreachable stays for ever. The TLC jar must be fetched again; `models/README.md` records the release and the SHA-256 | Counts safe with no extra durable state favours R. Counts that need their own log, or a rebuild from the roots at recovery, favour freeing in Mo policy (S or L) | Counts on disk break under a crash unless count changes are logged or rebuilt, at 75%. Holders with a sweep hold with no extra state, at 80% | The root switched before the log is forced must break crash safety. A count update dropped must show a freed node that a kept version reaches | 1 day | Idea 6's strongest claim for R stays untested, and so does the kept downside that "counts on disk took Btrfs years" |

**Not experiments, done first by reading (Q8):** what `~/code/mo/formal/` defines for collections and for services, and how `runtime/` saves state today. About 2 hours. The answer goes into the Decision 2 section as "settled without an experiment".

## 6. Order, and where Robert decides

1. **Robert accepts, changes or cuts this plan.**
2. Write "Decision 2" in `experiments.md` in the shape of Decision 1: Status, the options, what is settled without an experiment, what the experiments must decide, the table of experiments, and "Where Claude stands". Remove its line from "Decisions waiting". Commit.
3. Do the reading for Q8. Commit.
4. **Optional council. Robert accepts or skips.** One brief with the three options, three reviewers, one round, saved to `raw/council-2026-11-15-library-or-runtime/`. Claude recommends accepting, at 60%. The main risk here is a missing option or a wrong boundary for S, and the council on Decision 1 named the right first experiment. The reason to skip is cost in tokens, and that experiments 15 to 17 are cheap enough to run blind.
5. Experiment 15, then 16, then 17. Predictions are committed before each. This order is cheapest first.
6. **After 15 and 16, Robert decides whether L is dropped,** and answers Q7: must any large value live on disk, or only tables? Claude will give a recommendation and a confidence then.
7. **After 17, Robert decides between what is left.** Claude writes its position and what would move it.
8. Bring `design.md` section 9 and section 8 line 3 into line with his decision. Commit.

Robert can stop after any step. Each experiment stands alone.

## 7. Where Claude stands

| Option | Confidence | Why |
| --- | --- | --- |
| S, split | 50% | It passes Robert's test piece by piece, keeps the policy in Mo where `mo test` checks it, and needs no change to section 11.5 |
| R, runtime | 30% | The plainest form of "built into the language". Every service gains. It falls back if counts on disk are hard and if the policy is better in Mo |
| L, library | 20% | Its two main advantages were the visible disk step and the typed read error. Both shrink once the compiler hides the store behind tables |

- **The earlier lean to the library no longer stands.** It was written in `design.md` section 9 and `design-ideas.md` before Robert decided that tables are part of the language. It also rested partly on asking less of Mo, a reason Robert has set aside.
- **These numbers rest on argument and nothing measured.**

What would move it:

- **Toward R:** experiment 17 shows counts on disk are safe with a simple protocol; experiment 16 shows the Mo policy is thin or awkward; Robert answers Q7 with "any value".
- **Toward L:** experiment 16 shows the capability threads cleanly and the policy must see inside nodes constantly; the reading shows the Lean definition gives real cover to file steps that a runtime store would lose; experiment 15 shows few programs hold growing state.
- **Toward S:** experiment 16 passes with a boundary of two or three operations; experiment 17 shows counts need their own log.

## 8. What was cut and why

| Cut | Why |
| --- | --- |
| A timing or node-count comparison of the three options | The compiler plans the reads under every option, so nodes read and written are equal by construction. What is left is constant factors, which today's interpreter would dominate, and that may not decide |
| "Library first, runtime later" as an option | It is a build order. Build cost is not a limit Robert set |
| An agent trial of how programs handle a failed read | Under tables in the language a read returns its plain type. The question is answered by argument (Q5); a council reviewer can attack it |
| Simulating a tearing disk under each option | Mo cannot do it today under any option (section 8 line 11; reference section 12.5). It is a requirement on all three and does not choose between them |
| Names by hash or by number, erasure, the log through an upgrade | These are the other waiting decisions. They follow this one. Experiment 16 names nodes by number only because Mo has no hash |
| A stand-in runtime in C or Python that pages nodes | It would test the stand-in and not Mo. Experiment 16's backend A is the smallest honest version |
| Web research | Idea 6's basis already cites the earlier work (Btrfs, Napier88, Motoko, Datomic). The council step can ask for more |

## Not verified while writing this plan

- `~/code/mo/formal/`, `runtime/` and `src/heap/table.c` were not read. Q8 is that reading.
- `~/code/mo/learnability/` and the number of services in Mo were not counted. Experiment 15's sample may be small, and its result must say so.
- `sketches/kept-versions/` was checked through `sketches/README.md` and ticket 37 only. Its Mo files were not opened.
