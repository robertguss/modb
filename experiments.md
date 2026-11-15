# Open decisions, their options, and the experiments that would settle them

Robert's rule of 2026-11-14: "keep a list of some options and then do small tests and spikes and experiments so that all decisions are based in reality and data."

How this file works:

- A decision stays open here with every option still standing, until an experiment or Robert closes it.
- An experiment is small: a Mo program under `sketches/`, a script that stands in for a compiler pass, a measurement of agents writing code, or a model under `models/`.
- Every experiment has its prediction written here before it runs, and a control that must fail.
- A result is written under the experiment with the date and a link to what was run. A prediction is never edited after its result is in.
- An option is judged by where Mo should end up, not by what Mo does today. Robert, 2026-11-14: "I'm not interested in finding out how to make it work with what it does today. I'm all about potentially rewriting it or changing it or doing whatever we need to do to make it the best that it possibly can be." What an option asks of Mo is listed, and is not a reason against it. An experiment still runs on today's Mo or on a stand-in, and its result says so.
- How easy an option is for an agent to learn comes second. Robert, 2026-11-14: "What matters is designing and creating whatever we need to make it do what we want. Teaches the agents the language is secondary to that." Experiments 1, 2, 4 and 6 below measure what agents write by habit or after one page of rules. Their results stay as records and no longer decide between options.

## Decision 1. How is a fast read enforced?

**Status:** open. Experiments 1, 4 and 5 ran on 2026-11-14; their results are below the table of experiments. Option D is closed as a gate. Robert chose option I as the direction on 2026-11-14, and on 2026-11-15 decided that a slow read is first made fast by keeping its answer, and refused only when that cannot be done. Experiment 8 tests it.

**The idea it belongs to.** "Plain Mo is the query language", idea 1 in [the ideation of 2026-11-14](docs/ideation/2026-11-14-mo-database-ideation.html): the compiler turns certain shapes of ordinary collection code into index lookups. Robert agreed on 2026-11-14 to try it with no new query syntax, and asked how the fast shapes are enforced.

**Sources.** [The council of 2026-11-14](raw/council-2026-11-14-enforcing-fast-questions/README.md): three reviewers, one brief, and what each review contains as judged by TypeSafe's Jev.

### The options

| | Option | Where it stands after the council |
| --- | --- | --- |
| A | Strict. A filter on a stored table with no fast route is a compile error unless the code says `walk` | Chosen by all three reviewers for the program's own code. All three also say it can turn ordinary Mo into a hidden query language |
| B | Warn only | Ruled out. Mo has no warnings: "a problem is an error, or it isn't reported" |
| C | Demand. A `fast` marker makes the compiler refuse a function it cannot make fast | No reviewer chose it for the program's own code, because an unmarked function still walks unnoticed. GPT Sol makes it mandatory for a read program an agent sends |
| D | Measure. `mo test` compares instruction counts at two store sizes | Doubted by all three. A primitive that goes over a whole collection may count as one instruction, and an indexed read with a growing answer looks like a walk. Experiment 5 found both and closed it as a gate |
| E | A closed form. The table has a fixed set of methods that take a field and a value | Nobody's first choice. All three name it as the fallback if recognising shapes is brittle |
| F | The review door holds an upgrade that makes a read slower, by ranked cost class | Gemini Carbon chose it, with A. The other two did not |
| G | The type enforces it. A stored `Table` is not a `List`: it has `get`, the index methods and one `walk`, so a slow read can only be written as `walk`. Recognising shapes is then a convenience, not a gate | Added by Claude Opus. Close to E plus A |
| H | An access-plan report: every table access, the index it needs, whether that index is ready, every walk | Added by GPT Sol. It goes with any other option |
| I | Tables are part of the language. A table is its own kind of value with no insertion order. It is read with ordinary Mo expressions, which the compiler plans. The indexes are worked out from the reads the program contains. Each read function carries its checked cost. A read with no fast route is an error unless it says `walk`, and the runtime counts rows read | Added by Claude on 2026-11-14 after Robert's steer. Not seen by the council and not tested. It is A with Mo changed so that A's faults go away, and with H built in. Robert chose it on 2026-11-14 as the direction to design and test. The wider form, where the compiler also keeps answers up to date, is [idea 10](design-ideas.md#10-the-compiler-is-the-planner) |

### What the council settled without an experiment

- A warning is not available in Mo.
- The promise should be narrow: no walk of a whole table goes unacknowledged. An indexed read that returns a thousand rows still does a thousand rows of work.
- A read program an agent sends needs a different rule from the program's own code. The three disagree on which: no compile-time gate and a logged cost (Claude Opus), a mandatory demand with approval for a walk (GPT Sol), or strict with `walk` allowed under a work budget (Gemini Carbon).

### What the council raised that the idea had not faced

- **A rewrite can change the answer.** Mo keeps insertion order, and an index gives key order, so the walk and the index lookup can return the same rows in a different order. A value computed before the lookup can stop a program that the walk, on an empty table, would have let finish.
- **A recognised shape still needs an index that exists and is current.** Building one reads the whole table once.
- **Agents may not write the shapes.** Mo's recorded agent sessions hold about ten `for` loops for every `.filter(` call. That count covers all code, not only reads.
- **The shape may be gone before Mo Core.** Idea 1 says the compiler normalises over Mo Core. Gemini Carbon says loops and `filter` are lowered to entry lists and jumps before that, so recognition would have to happen earlier. Not checked.
- **`sort_by` sorts everything before a `take`,** so "the first ten by date" cannot use an ordered index without the compiler fusing the two.

### What the experiments must decide

Whether fast reads come from **recognising plain Mo** (A) or from **a table type with its own methods** (E or G). Two reviewers gave thresholds for switching to the table type: recognition of natural code under 40%, or more than 25% of `walk` uses being unjustified, or fewer than 75% of tasks completed under A.

### The experiments

Merged from the three reviews. The order is Claude's: cheapest and most likely to change the decision first.

| # | What is built or measured | The result that decides | Predictions written before it runs | Control that must fail |
| --- | --- | --- | --- | --- |
| 1 | **Shape census.** A script over the agent-written Mo in `~/code/mo/learnability/` and the read functions in `sketches/`. It labels each piece of code that picks rows from a collection as a recognised shape or a miss | The share of row-picking code in a recognised shape | Claude Opus: under 60%, at 75%. Claude: under 40% if only library calls such as `filter` count, at 70%; 60% or more if a `for` loop holding one `if` on a field also counts, at 60% | A planted file of filters hidden in helpers and key arithmetic must all come out as misses |
| 2 | **Natural shapes from fresh agents.** New agent sessions write 30 read tasks over a four-table shop with no hint. Two recognisers run on the code that passes: one over the source, one over `mo check --emit=core` | The share matched on the source and the share matched on Mo Core | Gemini Carbon: about 65% on source and under 20% on Core, at 80%. Claude: source between 50% and 75%, at 60%; Core under 30%, at 70% | Ten deliberately obscured walks must score 0 of 10 on both |
| 3 | **Does a rewrite keep the answer?** Hand-written index versions of recognised filters, compared with the plain walk on generated data: duplicates, order, empty tables, tests that stop, ranges, `or` | Every accepted rewrite gives the same ordered answer and stops in the same cases | GPT Sol: a restricted recogniser passes and unrestricted hoisting fails, at 85%. Gemini Carbon: range and `or` rewrites differ under `==` in 30% or more of histories, at 85%. Claude: equality on one field passes and ranges fail on order, at 80% | A value that stops, moved in front of a filter on an empty table, must be caught |
| 4 | **Enforcement trial.** Agents do the read tasks under A (an error with a fix) and under E (table methods), with a script standing in for `mo check` | The share of tasks that end correct and on a fast route within two repairs, and the share of `walk` uses that were not needed | GPT Sol: A reaches 90% within two repairs, at 65%. Gemini Carbon: A reaches 90% with 10% or less `walk` abuse, and E falls under 60% on joins, at 80%. Claude Opus: A is no better than E, at 55%. Claude: A reaches 85% or more, at 65% | One suggested fix is replaced with a rewrite that changes the answer; hidden tests must reject it |
| 5 | **Does the instruction count separate a walk from an indexed read?** A sketch with a `Map` as an index, measured with `mo query --max-work` at two sizes: indexed reads, walks written as Mo loops, walks through primitives such as `values` and `sum`, and an indexed read whose answer grows | Walks grow with the store and indexed reads with a fixed answer do not | Claude Opus: holds for Mo loops, at 85%. GPT Sol: option D as stated fails, at 95%. Gemini Carbon: walks through primitives show no growth, at 95%. Claude: Mo loops grow, at 95%; walks through primitives show little or no growth, at 80%; so D as stated fails, at 90% | A walk written as a Mo loop must grow in step with the store |
| 6 | **Survival under refactor.** Twenty recognised filters, each put through the edits agents make: a named test function, `count`, `find`, `any?`, a `for` loop, `and` over two fields | The share still recognised | Claude Opus: under 80%, at 70%. Claude: under 80% for a recogniser that does not look inside helpers, at 75% | A filter rewritten to compare two fields of the row must be a miss |
| 7 | **Index readiness.** A model of an index that is absent, being built, ready or out of date, with recognised reads arriving in each state | No read is admitted that then silently builds or walks | GPT Sol: recognition alone fails this and readiness-aware admission passes, at 95%. Claude: the same, at 90% | An absent index labelled ready must show an admitted read with no fast route |
| 8 | **A stand-in for the planner, on what the compiler itself emits.** A script reads `mo check --emit=core` for the plain-Mo reads of experiment 4, sorts each into looked up, kept or walked, keeps the answers up to date through random writes, and compares them with real Mo running the same code on the same rows | The share of reads it understands from Mo Core, and whether every answer it keeps equals Mo's | Written below, before the run | A kept answer whose upkeep skips one kind of write must be caught; a plan with its test dropped must be caught; a read whose test is `contains` must come out walked |

Experiments 1, 3, 5, 6 and 7 need nothing but Mo as it stands and a script. Experiments 2 and 4 need agent sessions, which cost money.

### Experiment 4 as it will be run, written 2026-11-14 before any session

The design is frozen in [sketches/enforcement-trial/freeze.md](sketches/enforcement-trial/freeze.md): 40 sessions, 10 read tasks over a four-table shop, two arms (A, and the table type G standing for E), two models. The measure the predictions above are scored on is "good within two repairs": one of the first three valid versions is correct, accepted by the arm's rule, and walks nothing it need not.

Claude's further predictions, added before any session ran:

- Arm G reaches 85% or more, at 75%.
- The two arms end within 15 points of each other, at 65%.
- Under arm A, 2 or fewer of the 16 sessions on index tasks end with a needless walk, at 70%.
- Under arm A, the rule accepts the first valid version in 60% or more of sessions, at 60%. The store's page states the rule, so most agents should write the shape first time.

With 20 sessions in an arm, a 95% interval is about 20 points each way. The trial can show a large gap and cannot show a small one.

### Experiment 8 as it will be run, written 2026-11-15 before the run

Robert decided on 2026-11-15 that the compiler should first try to make a slow read fast by keeping its answer up to date, and refuse only when it cannot. This experiment is the first test of [idea 10](design-ideas.md#10-the-compiler-is-the-planner).

**What is run.** [`sketches/planner/`](sketches/planner/). The reads are the 21 that agents wrote in plain Mo in experiment 4 (arm A, with the pilot) and the 11 of `reference-a.mo`. None was written for this experiment. For each, the script reads the function from `mo check --emit=core`, finds the table it reads, the test and what is done with the rows, and gives it a class. It then applies random writes to the four tables one at a time, adjusting what it keeps on each write and never rebuilding. At checkpoints it writes the rows out as a Mo program, runs the agents' own functions with real Mo, and compares.

**What Claude had seen before writing the predictions.** The Mo Core of one function, session 01's `orders_of`: the `filter` call and its test were both there. Nothing else.

**Predictions, Claude:**

1. Mo Core keeps the library call and its test, as a function, in every read that uses library calls: 90%. Gemini Carbon predicted in the council that under 20% would be matched on Core, at 80%, and Claude wrote "under 30%, at 70%" for experiment 2. Those were about agents given no rule, so this corpus is kinder.
2. The script understands at least 14 of the 21 agent-written reads from Mo Core alone: 65%. The reads written as `for` loops are not understood by the first version: 70%.
3. The classes come out as: `product_name` by key; `orders_of`, `large_orders`, `latest`, `bought`, `city_customers` looked up; `paid_total`, `open_count`, `units_sold` kept; `mentions` walked; `idle_customers` walked, because keeping it needs two tables at once and the script handles one: 75% that every understood read lands in the class listed.
4. On the first complete run at least one answer the script keeps differs from Mo's: 50%. Whatever still differs after repair is reported as failing.
5. A kept read touches one entry at every store size, and the upkeep of a write is bounded by the number of things kept on its table, not by the size of the store: 90%.

**Limits known before the run.** The script is a stand-in, in Python, for a pass that would live in the compiler. It reads only the forms these 32 reads use. The agents had been told arm A's rule, so their code is tidier than code written with no rule. Speed is counted in rows touched, not timed.

### Result of experiment 4, 2026-11-14

Run as frozen in commit `28916e0`. The two pilots needed no change to the harness. All 40 sessions ran and each reported `done`. The grading output, every verdict and the 42 answers are in [sketches/enforcement-trial/results](sketches/enforcement-trial/results/grade.txt).

| Measure | Arm A, plain Mo | Arm G, table type |
| --- | --- | --- |
| Good within two repairs | 20 of 20 (interval 84% to 100%) | 20 of 20 (84% to 100%) |
| Ended good | 20 of 20 | 20 of 20 |
| The rule accepted the first valid version | 19 of 20 | 20 of 20 |
| Needless walk at the end, on the 16 index tasks | 0 | 0 |
| Walked the right table, on the 4 tasks that need it | 4 of 4 | 4 of 4 |

- **The trial cannot tell the arms apart.** Both are at the top of the scale. Claude and GPT each scored 10 of 10 in each arm.
- **Agents told the rule wrote the shape at once.** `STORE.md` states arm A's rule in about ten lines with one example. 17 of the 20 answers under A read tables only through library calls and 3 used a `for` loop.
- **The one refusal under A was the stand-in script's fault.** Session 14 wrote a correct filter on two indexed fields, with the test wrapped onto its own line. `rule.py` joined the lines with a space after the bracket and then failed to see the test. The agent took one more version to get past it, by moving one test into a loop, and did not reach for `walk`.
- **The compile errors the sessions did meet were ordinary Mo errors,** such as an unused import or a case imported without its type. They came in both arms alike.

How the predictions did:

- GPT Sol, A reaches 90% within two repairs: right.
- Gemini Carbon, A reaches 90% with 10% or less needless walks: right. That the table type falls under 60% on joins: wrong. The four join and compound tasks came out 8 of 8 under G.
- Claude Opus, A is no better than the table type: right.
- Claude, all five: right. A and G both at 85% or more, within 15 points, no more than 2 needless walks, and the first valid version accepted in 60% or more.

What it means:

- **Experiment 1 measured habit; this measured what agents do once told.** 13% of the row-picking code agents wrote unprompted was in a shape. Told the rule in one page, they wrote the shape first time in 19 sessions of 20. The fear that agents cannot write the shapes is answered for simple reads.
- **Neither arm costs agents anything measurable here.** So the choice between them rests on what each costs to build and what can go wrong in it, not on which agents handle better.
- **A brittle recogniser showed up even in a script of 100 lines.** A compiler reads a syntax tree and would not make this mistake, but equivalent code being refused is the risk experiment 6 is about.

What it does not show:

- **Hard reads.** No task needed `or`, a negation, a top ten over a whole table, a group-by, or a read buried in a long function that does other work. The census found most real row-picking in exactly that last form.
- **Agents not told the rule,** or told it only by the error.
- **Sealed sessions.** The sessions ran inside this repository and were asked to stay in their folders. Whether each did was not checked.
- **A real compiler pass, or any speed.** Arm A's rule is a script and nothing was made fast.

### Result of experiment 1, 2026-11-14

Run with [sketches/shape-census](sketches/README.md#shape-census) over `~/code/mo/learnability` at Mo commit `ce86860a`. The script and its controls were committed (`12f889d`) before the first run. Controls: 10 planted misses found and none recognised; 8 planted hits, all recognised.

| Measure, over 188 distinct sites in 228 distinct files | Recognised |
| --- | --- |
| Library calls only (`filter`, `find`, `count`, `any?`) | 24, or 13% |
| With a `for` loop holding one `if` on a field | 24, or 13% |
| By equality alone | 17, or 9% |
| Leaving out the 76 sites that go over text: 112 sites | 20, or 18% |
| Counting every copy: 258 sites | 53, or 21% |
| Ceiling: any loop with some test in a shape counts | 72, or 38% |

- **121 of the 188 sites are loops and 67 are library calls.** No loop is in the one-`if` shape. 106 loops do more than one `if`. The other 15 are a single `if` whose test is a call, a negation or a computed value.
- **Of the 67 library calls, 24 are in a shape, which is 36%.** The misses are a call or computed value on the row, `not` or `!=`, a named function, and `or`.
- **The sketches in this repository hold two sites.** That is too few to say anything.

How the predictions did:

- Claude Opus, under 60%: right.
- Claude, under 40% for library calls only: right.
- Claude, 60% or more once one-`if` loops count: wrong. It is 13%, and the ceiling for any loop recogniser is 38%.

What it means: a recogniser of plain Mo would miss about seven in eight of the places where agents pick rows today. Under option A almost every read would first meet a compile error. The two reviewers' threshold for moving to a table type was under 40%.

What it does not show:

- **This is not database code.** The tasks are text tools, a job queue, a cart and the like, over local collections. No agent was told an index existed or was refused a walk. It measures habit, not what agents write once a compiler pushes back. Experiments 2 and 4 measure that.
- **The script is not a compiler.** It reads text by indentation. About 70 of the 188 sites were read by hand and looked right; the rest were not checked.
- **Two things changed after the first run.** The ceiling row was added once the first result was seen. The first run also counted the planted control files as part of the sketches; the second run left them out. The numbers for `learnability` were the same in both.

### Result of experiment 5, 2026-11-14

Run with [sketches/instruction-counts](sketches/README.md#instruction-counts) on a `mo` built from commit `ce86860a` plus another session's uncommitted changes. The sketch was committed (`9d03d3d`) before the first run. The store grew four times, from 1,000 orders to 4,000.

| Read | At 1,000 | At 4,000 | Times | The count says | It is |
| --- | --- | --- | --- | --- | --- |
| One row by key | 48 | 48 | 1.00 | indexed | indexed |
| A buyer's ten orders through an index | 879 | 879 | 1.00 | indexed | indexed |
| A band's orders through an index; the answer grows | 7,989 | 31,689 | 3.97 | walk | indexed |
| Walk as a Mo `for` loop | 59,182 | 236,182 | 3.99 | walk | walk |
| Walk as `values`, `filter`, `map`, `sum` | 78,183 | 309,183 | 3.95 | walk | walk |
| `values` then `size` | 27 | 27 | 1.00 | indexed | walk |
| `keys` then `size` | 27 | 27 | 1.00 | indexed | walk |
| `contains?` for a value that is not there | 26 | 26 | 1.00 | indexed | walk |
| `reverse` then `size` | 26 | 26 | 1.00 | indexed | walk |
| `unique` then `size` | 26 | 26 | 1.00 | indexed | walk |

The count is wrong about 6 of the 10. The control held: the Mo loop grew 3.99 times.

How the predictions did: all four right. Option D as stated fails (GPT Sol, Claude). A walk inside a built-in shows no growth at all (Gemini Carbon, Claude). A walk written in Mo grows in step and an indexed read with a fixed answer does not (Claude Opus, Claude). Claude Opus's second control, that an indexed read with a growing answer must not be flagged, failed.

What it means:

- **Option D is closed as a gate.** It would pass five walks and refuse one indexed read.
- **The count is exact where it works.** A lookup with a fixed answer cost the same to the instruction at both sizes, and a Mo loop grew in step. A repaired check would need Mo to charge for each element a built-in goes over, and would need to measure the cost for each row returned.
- **Mo's instruction limit does not bound a walk done by a built-in.** `contains?` on a list of any length costs 26 instructions. The built-in loops over the list in C (`src/prim/collections.c`). Any rule for agents' read programs that relies on the limit alone, such as Claude Opus's, has this hole.

What it does not show: time. The run counted instructions and did not time the built-ins. It did not test `sum` alone, `intersection`, or a read through the tree in `sketches/kept-versions`.

### Where Claude stands, with what would move it

- **Strict in some form, for the program's own code: 85%.** All three reviewers chose it and Mo has no warnings.
- **Strict by recognising plain Mo, against a table type with its own methods: 35% for plain Mo after experiment 4.** Before the council Claude gave plain Mo 80%, about even after it, and 30% after the census. Experiment 4 removed the reason for the drop: agents told the rule write the shape. It did not restore plain Mo, because the table type did exactly as well. Claude then leaned to the table type because it asks less of Mo. Robert set that reason aside on 2026-11-14, so the 35% no longer stands.
- **Tables in the language (I), against a table type in a library (G): 80% for I after Robert's second steer, with nothing measured.** The 55% below held back for a reason Robert has since set aside, that the writer must learn which expressions are fast. Experiment 4 also speaks against that worry: agents learned either rule from one page, 40 of 40. What would move the 80% is a finding that planning cannot keep the answer the same for a common kind of read. The reasoning as first written, at 55%: Experiment 4 does not choose between them. It gave arm G the seven index functions its tasks needed, and gave arm A the indexed fields. It never asked a question whose index did not exist yet. That is where the two differ: under G somebody must write a new function in the store for each new question, and under I the read itself says which index is needed. What the council held against plain Mo was insertion order, eager evaluation, the shape being lost before Mo Core, and built-ins the instruction count cannot see. Each is a fact about Mo today, so under Robert's steer each is a thing to change in Mo, not a reason against. What still counts against I: which expressions are fast is a rule the writer must learn, and all three reviewers warned of a hidden query language. A trial with questions that need a new index would move this number either way.
- **The growth test as a check: closed by experiment 5.** Before it ran Claude gave it 15%.

## Decisions waiting for options and experiments

These came out of the same ideation. None has an experiment designed.

- **Does the log run unbroken through an upgrade?** Idea 2. Today an upgrade deletes the log's tail.
- **Is the store a library written in Mo or part of the runtime?** Idea 6, and `design.md` section 9.
- **Are nodes named by hash or by number?** `design.md` section 9.
- **May a write function open a held value?** Idea 3. If it may, replay after an erasure gives a different state.
