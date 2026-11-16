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

**Status:** decided on 2026-11-15, when Robert accepted the rule in [design.md](design.md), section 5. What is still open inside it is listed there. Experiments 1, 4 and 5 ran on 2026-11-14; their results are below the table of experiments. Option D is closed as a gate. Robert chose option I as the direction on 2026-11-14, and on 2026-11-15 decided that a slow read is first made fast by keeping its answer, and refused only when that cannot be done. Experiments 8 to 13 tested it on 2026-11-15; their results are below. Robert also decided on 2026-11-15 that a write is held to the same rule as a read. The rule those experiments led to is written as a draft in [design.md](design.md), section 5, for Robert to accept; experiments on kept answers stopped there at his word. At his request experiment 13 then ran the whole rule once: every write that grows was flagged, and writes to orders were flagged though they stay flat, because the write test sees a shape and not how many rows share it. Experiment 14 then tracked writes by field, with write functions agents wrote: the flag came off half of them, every ordinary update among them. What stays flagged is adding a row, which stays flat, and moving a customer or renaming a product, which grow and are flagged only by planted reads. On 2026-11-15 Robert accepted the write half of point 6, read field by field, with a row added under a new key named by no row because a field naming a row must name one that exists. He also decided that removing a row other rows still name is refused unless the code says to remove them too. And the word that allows a write to fan out goes on the kept read that causes it, with the cost shown in the write's report.

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
- **The shape may be gone before Mo Core.** Idea 1 says the compiler normalises over Mo Core. Gemini Carbon says loops and `filter` are lowered to entry lists and jumps before that, so recognition would have to happen earlier. Not checked. Checked in experiment 8: a loop is lowered to joins and jumps, and a call to `filter` is kept whole with its test.
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
| 9 | **Keeping answers that span tables.** The stand-in of experiment 8, widened: an answer is kept in parts, one for each row of the table the read goes over, and a part may read other tables. A write to another table redoes only the parts that read what it touched | Which reads stop being walks or lookups, what one ask costs, and what one write then costs at two store sizes | Written below, before the run | Upkeep skipped after a write to another table must spoil kept joins and no single-table answer; a loop that reads its own running list must not be kept; a loop with two running values must not be kept |
| 10 | **Adjusting a kept answer in one step.** The stand-in of experiment 9 with finer parts: a loop inside a loop gets one part for each pair of rows, and a test that only asks whether any row matches is answered from the index and told only when that flips | How much of a write's upkeep in experiment 9 came from working parts out again, and how much remains | Written below, before the run | Notices of a flip dropped must spoil only reads that ask whether any row matches; the controls of experiment 9 must still fail as before |
| 11 | **Doing the lookup when the read is asked.** The stand-in of experiment 10 with one change: a part no longer reads another table by key. Where the part is for a pair of rows, the pair is kept and the rest of the part runs when the read is asked. Where the part is for one row, nothing would be kept but the index, so the read is not kept | What a write to the looked-up table then costs, and what an ask costs against keeping the whole answer and against keeping nothing | Written below, before the run | Lookups that are never done again after the pair is made must spoil exactly the reads whose lookups moved; the controls of experiment 10 must still fail as before |
| 12 | **Grouping before the lookup.** The stand-in of experiment 11 with one change: parts that stop at a lookup are grouped by the fields the rest of the part reads, and each group is kept once with a count. An ask does the lookup and the rest once for each group. A list is grouped only where the code sorts it before any other use | Whether the compiler can find the grouping from Mo Core alone, and what an ask and a write then cost against experiments 10 and 11 | Written below, before the run | Grouping on no fields must spoil exactly the grouped reads; grouping a planted read whose order counts must spoil exactly that read; lookups never done again must spoil exactly the reads that wait at a lookup; the controls of experiment 10 must still fail as before |
| 13 | **The whole rule in one run.** The stand-in of experiment 12 run under the draft rule of [design.md](design.md), section 5: point 4 replaces doing the lookup at the ask where order counts, a read that walks without saying `walk` is refused, and a write that must redo one part for each row that refers to the row it changed is flagged, worked out from the plan alone | Whether the tables flagged from the plan are exactly the tables whose upkeep grows between the two store sizes | Written below, before the run | A planted walk that does not say `walk` must be refused and nothing else newly refused; a weakened write test must miss a write that grows; the controls of experiment 12 must still fail as before, or the change is named |
| 14 | **Writes tracked by field, with write functions agents wrote.** Four fresh agent sessions write the shop's write functions, choosing the changes themselves and told nothing of the rule. The stand-in of experiment 13 runs them. It works out from each function's Mo Core which fields of which tables it can change. It flags the function under point 6 only when the function removes a row, or changes a field that a kept read reads, of a row that a part depends on through the rows that name it. A write redoes a part only when it changed a field the read reads | Which ordinary writes keep the flag once writes are tracked by field, and whether any write that grows goes unflagged | Written below, before the sessions | Skipping upkeep when a write changes an order's customer must spoil reads that read an order's customer, and only those; the controls of experiment 13 must still fail as before |

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
6. Added after reading the Mo Core of six of the reads and before any run: when an index hands rows back in the opposite order, none of the 21 agent-written reads changes its answer, because each sorts at the end: 70%. A planted read that leans on the order does change: 95%.

**Limits known before the run.** The script is a stand-in, in Python, for a pass that would live in the compiler. It reads only the forms these 32 reads use. The agents had been told arm A's rule, so their code is tidier than code written with no rule. Speed is counted in rows touched, not timed.

### Experiment 9 as it will be run, written 2026-11-15 before the run

Robert agreed on 2026-11-15 to widen what can be kept, to joins and to reads across two tables.

**The rule being tried.** A read is kept when it goes over one table once, row by row, and what it does for each row is separate from what it does for every other row. The script finds that split in Mo Core in two forms: a chain of `filter` and `map` calls, or a `for` loop that only adds to a number or only appends to a list. The work for one row is its *part*. A part may read other tables, which is what makes a join. The script records what each part read. A write to the table the read goes over redoes that row's part. A write to another table redoes only the parts that read what it touched. What comes after the split, such as `sort`, `unique` or `take`, runs on the parts put together when the read is asked.

**What is run.** [`sketches/planner/`](sketches/planner/), with the 35 reads of experiment 8 and five more planted by Claude for this experiment: a sum across two tables by city, the buyers of a product across three tables, a product's revenue with the price read from another table, the orders with no lines, and the customer with the most orders. Every answer is again compared with real Mo.

**What Claude knew before writing the predictions.** The result of experiment 8, and the Mo text of nine of the 35 reads.

**Predictions, Claude:**

1. On the first run that completes, at least one answer differs from Mo's: 55%. There is more machinery than in experiment 8.
2. `idle_customers` from both agents becomes kept, and one ask reads under 5 rows at both sizes, down from about 300 and 1,140: 75%.
3. `bought` from GPT, which only appends, becomes kept. `bought` from Claude, which looks in its own list before it appends, does not: 80%.
4. Every `mentions` stays walked: 95%. `latest` and `large_orders` stay looked up: 90%.
5. The two reference sums written with `.map(...).sum` become kept numbers, one row an ask: 85%.
6. Of the 21 agent-written reads, those that walk fall from 4 to 2: 75%.
7. Of the five planted reads, four are kept and the customer with the most orders is not: 70%.
8. A write to a table that parts were read from costs more as the store grows. For the planted revenue read, a change to one product redoes about four times as many parts at 1,200 orders as at 300: 80%. Over all writes the mean number of rows read for upkeep stays under 30 at both sizes: 60%.

**Limits known before the run.** The parts are redone, not adjusted: when an order changes, the part of its customer is worked out again from that customer's orders. A real planner could adjust it in one step. So the cost of a write here is an upper bound for this rule. The rest of experiment 8's limits stand.

### Experiment 10 as it will be run, written 2026-11-15 before the run

Robert decided on 2026-11-15 that a write is held to the same rule as a read: upkeep that grows with the store is an error unless the code says so. This experiment asks how much of the growth seen in experiment 9 is real.

**What changes.** Two things, both in `sketches/planner/`.

- **A part for each pair of rows.** When a kept read has a loop inside its loop, and the running value changes only inside the inner loop, the script keeps one part for each pair of an outer row and an inner row. A write to an inner row then redoes one pair, not everything the outer row holds.
- **"Does any row match?" from the index.** When a test is covered exactly by its index, `any?` is answered by whether the index entry is empty. A part that asked is told only when the entry goes from empty to not empty or back.

Nothing else changes: the same 40 reads, the same writes, the same comparison with real Mo.

**Predictions, Claude:**

1. On the first run that completes, at least one answer differs from Mo's: 50%.
2. Exactly three reads get a part for each pair: the planted spend of a city, and `bought` from GPT and from the reference: 75%.
3. A write to orders stops growing with the store: its mean upkeep at 1,200 orders is within 1.3 times its mean at 300. In experiment 9 it was 2.5 times: 70%.
4. A write to products at 1,200 orders reads under 500 rows on average, down from 1,577, and still costs about four times what it costs at 300: 75%. A product is read by a part for every line that names it, and that number grows with the store.
5. A write to customers still more than doubles between the two sizes: 70%. The planted buyers read keeps a customer's name in a part for every line they bought.
6. Over all writes the mean upkeep at 1,200 orders falls from 206 rows to under 80: 60%.
7. What one ask costs stays within a tenth of experiment 9 for every read: 85%.

**Limits known before the run.** Neither change does arithmetic on a part. A price change still redoes the part of every line of that product, where multiplying a kept total of quantities by the change in price would be one step. So what remains after this experiment is still an upper bound.

### Experiment 11 as it will be run, written 2026-11-15 before the run

Experiment 10 left one cause of writes that grow with the store: a part that looks up a row of another table by key. Robert agreed on 2026-11-15 to test doing that lookup when the read is asked.

**What changes.** One rule, in `sketches/planner/`. A part does no lookup by key.

- **A part for a pair of rows keeps the pair.** The lookup and everything after it run when the read is asked. This is `bought` from GPT and from the reference: the pairs of a customer's orders and their lines are kept, and each product is looked up at the ask.
- **A part for one row keeps nothing.** With the lookup gone, what is left of such a part is the row itself, and the index already holds that. So the read is not kept. It is looked up. This is the planted revenue and buyers reads.
- **Two counts for an ask.** Rows read, as before. And rows read when a row looked up twice in one ask is counted once, which is what a real engine would pay.

The same 40 reads, the same writes and the same comparison with real Mo. Experiment 10's report is the baseline, because the writes are the same ones.

**What Claude expects, and said too little of when proposing this.** Claude told Robert an ask would cost as many rows as its answer is long. Working it through before the run, that is too kind. The kept pairs are not shorter than the lines they came from, and each needs a lookup. So an ask should cost about what it costs to keep nothing. If that is what the run shows, plain late lookup is a weak lever.

**Predictions, Claude:**

1. On the first run that completes, at least one answer differs from Mo's: 35%.
2. Exactly four reads change. The planted revenue and buyers reads go from kept to looked up. `bought` from GPT and from the reference stay kept, with their lookups at the ask: 85%.
3. A write to products reads under 5 rows for upkeep on average at both sizes. It was 183.8 and 675.4: 85%.
4. A write to customers reads under 100 rows at 1,200 orders, down from 191.1, and still more than doubles between the sizes: 70%. What is left is the planted spend of a city, where one customer has a part for each of their orders.
5. Over all writes the mean upkeep at 1,200 orders falls from 83.1 rows to under 25: 70%.
6. At 1,200 orders an ask of `bought` reads between 145 and 175 rows. It was 67.5 kept whole, and Claude's own `bought`, which keeps nothing, reads 189.0. An ask of the planted revenue reads between 230 and 260 rows, where it was 1.0. An ask of the planted buyers reads between 320 and 390, where it was 105.8. All three: 65%.
7. With a row looked up twice counted once, an ask of `bought` at 1,200 orders reads under 115 rows, and an ask of the planted revenue under 130: 65%.

**Limits known before the run.**

- The script keeps the pair of rows and runs the rest of the part over them at the ask. It counts the kept pair as one row and each lookup as one more. A real engine would keep only the fields the rest needs.
- Making a pair is counted as two rows read.
- Nothing is grouped. One kept entry for each distinct product, with a count, would shorten both the kept list and the lookups. So would a kept total of quantities for the revenue read. Neither is built.
- The store has about 40 customers and 25 products at both sizes. So lines for each product, and orders for each customer, grow with the store here. In a real shop they need not.

### Experiment 12 as it will be run, written 2026-11-15 before the run

Experiment 11 moved the lookup to the ask and found the ask then costs about what keeping nothing costs. Robert agreed on 2026-11-15 to test grouping before the lookup.

**What changes.** All in `sketches/planner/`.

- **A part stops at its first lookup by key.** When the part is made, it is run as far as that lookup and no further. A part that gets there is held waiting.
- **Waiting parts are grouped.** The planner reads from Mo Core which fields of the row the part reads, leaving out the tests that chose the row. Two parts that agree on those fields must give the same value, so they share one kept entry with a count. For `bought` that is one entry for each product a customer bought. For the planted revenue it is one for each quantity of a product.
- **An ask runs the rest once for each group.** It does the lookup and what follows over one row of the group. A number is multiplied by the count. A list is repeated that many times.
- **A list is grouped only where its order cannot matter.** The rule: after the loop the list is sorted before any other use, with or without `unique` first. A number is always grouped. Where a list's order counts, each pair of rows is kept in order, as in experiment 11.
- **So a part for one row is worth keeping again.** The planted revenue and buyers reads go back to kept.
- **One new planted read**, `bought_in_order`, which gives a customer's product names in the order of their lines and does not sort. It must not be grouped.

The other 40 reads, the writes and the comparison with real Mo are the same.

**What Claude expects, and where it said too much.** Claude told Robert the revenue read should cost about two rows an ask. This design will not reach that. It groups rows that agree on every field the part reads, and the part reads the quantity. It does not know that quantity times price can be totalled before the price is known. So revenue should cost one entry for each quantity, 1 to 9, and a lookup for each. Totalling first is a further step and is not built.

**Predictions, Claude:**

1. On the first run that completes, at least one answer differs from Mo's: 45%. The grouping rests on two things read from Mo Core for the first time, the fields a part reads and whether order counts.
2. Five reads wait at a lookup. `bought` from GPT and the reference are grouped by the line's product, the planted revenue by product and quantity, the planted buyers by the line's order, and the planted in-order read is not grouped. Classes over all 41 reads: kept 24, looked up 9: 80%.
3. An ask of `bought` reads between 45 and 60 rows at 1,200 orders and between 23 and 32 at 300: 70%. That is under the 67.5 it cost kept whole, and far under the 161.5 of experiment 11. It grows less than 2.3 times between the sizes, because a customer cannot have more entries than there are products.
4. An ask of the planted revenue reads between 14 and 20 rows at both sizes, and between 8 and 11 with a row looked up twice counted once: 75%. It was 248.4 in experiment 11 and 1.0 kept whole.
5. An ask of the planted buyers at 1,200 orders reads between 330 and 372 rows, against 369.8: 70%. Grouping buys almost nothing here, because nearly every line of a product belongs to a different order.
6. A write to products reads 0.0 rows at both sizes. Writes to lines and to orders stay within 1.3 times between the sizes, under 12 and under 28 rows. The mean over all writes at 1,200 orders is under 18: 70%. The new planted read adds its own upkeep, about 2 rows on a write to a line and 7 on a write to an order, so the figures sit a little above experiment 11.
7. An ask of the planted in-order read at 1,200 orders reads between 150 and 175 rows, like `bought` in experiment 11: 75%.

**Limits known before the run.**

- The script counts one row for each group an ask reads. It finds the groups by counting the waiting parts at the ask. A real engine would keep the count with the entry.
- At the ask the script runs the rest of a part over one whole row of the group. A real engine would keep only the fields that matter.
- No totalling before the lookup, as said above.
- Every lookup by key is treated alike. The script does not ask which lookup fans out.
- A part that sometimes ends with something to add and no lookup is not handled. The script stops if it meets one.
- The rule for order knows one shape, sorted before any other use. A list used in another way that does not lean on order is not grouped.

### Experiment 13 as it will be run, written 2026-11-15 before the run

The draft rule in [design.md](design.md), section 5, was drawn from experiments 8 to 12, and no single run used all of it. Experiment 10 kept every answer whole, which is point 4. Experiment 12 grouped where order does not count, which is point 3, and elsewhere did the lookup at the ask, which the rule does not say. No run raised either error of point 6. Robert asked on 2026-11-15 for one run of the whole rule before he decides whether to accept it.

**What changes.** All in `sketches/planner/`.

- **Point 3 stays as experiment 12 built it.** A part that looks a row up by key waits at the lookup and is grouped, where the answer is a number or a list sorted before any other use.
- **Point 4 replaces experiment 12's other branch.** Where order counts, the part does its own lookups and records them, and the whole answer is kept, as in experiment 10. A write to the looked-up table then redoes the parts that looked up the row it changed. In this corpus that is one read, the planted in-order read, which experiment 12 kept as pairs in order with the lookup at the ask. No read here has a part for one row whose order counts, so the case where experiment 12 kept nothing does not arise.
- **Point 6, the read error.** A read classed walked is refused when some table it walks is not passed through `walk` in its code. One planted read is added to test it: `noted`, which gives the ids of the orders whose note holds a word, smallest first, and does not say `walk`. It is the task of `mentions`, written without the word.
- **Point 6, the write error, worked out from the plan before any row is read.** The test Claude settles on, in plain words: *a write to a table must redo one part for each row that refers to the row it changed when some kept read holds a part for each row of another table, and that part depends on a row of the written table that its own row names by a field.* The plan shows two ways a part does that.
  1. The part looks the written table up by key, by a field of its own row, and does the lookup itself. A line looks up the product it names. A part that waits at the lookup does not count, because the lookup runs at the ask.
  2. The part is for a pair of rows and the written table is the outer one. The inner row is found by its field that names the outer row. An order names its customer, so the spend of a city has a part for every order of a customer.
- **What the test does not look at.** How many rows refer to one row. It cannot tell a customer with a hundred orders from an order with three lines.
- **Two shapes it does not look for,** because no read here has them: a part that reads an index of another table by something other than its own row's key, and a part that reads a whole table. Each would make a write fan out in the same way.
- **The report** gives, for each read, its class and whether it is refused. For writes to each table it gives what each kept read must keep up, in terms of rows, whether the rule flags it, which reads cause the flag, and the measured upkeep at 300 and 1,200 orders.
- **What counts as growing,** fixed before the run: a write grows when its mean upkeep at 1,200 orders is at least 1.5 times its mean at 300. The store grows four times. In experiment 12 writes to customers grew 2.2 times and the others at most 1.03 times.

The 41 reads, the writes, the seeds and the comparison with real Mo are the same as in experiment 12, with `noted` added.

**What Claude worked out from the plan before writing the predictions.** The test flags writes to customers, because of the planted spend of a city. It flags writes to products, because of the planted in-order read, which now does its lookups. It flags writes to orders, because `bought` from GPT and from the reference and the planted in-order read each hold a part for every pair of an order and one of its lines, so a write to an order redoes one part for each line that names it. Writes to lines are not flagged. In this store an order has about three lines at both sizes, because lines are three times the orders. So Claude expects the flag on orders to stand where nothing grows.

**Predictions, Claude.** Most of these can be worked out by hand before the run, because the script counts rows by fixed rules; experiments 11 and 12 showed that. They are marked "by hand". The ones marked "run" test what cannot be worked out: that every answer is still Mo's, and that each control fails where it should.

1. Run. On the first run that completes, at least one answer differs from Mo's: 20%. Point 4 brings back the way experiment 10 kept a pair whole, which matched Mo's every time.
2. By hand. Exactly one read is refused, the planted `noted`. All five reads that walked in experiment 12 say `walk`: 95%.
3. By hand. Classes over the 42 reads: by key 3, kept 24, looked up 9, walked 6. The 21 agent-written reads stay at by key 2, kept 12, looked up 5, walked 2: 90%.
4. By hand. The rule flags writes to customers, orders and products, and not to lines. The reads named as the cause: the spend of a city for customers; `bought` from GPT, `bought` from the reference and the in-order read for orders; the in-order read for products: 90%.
5. By hand, and the result that decides. Writes to customers and products grow; writes to orders and lines do not. So the flags and the growth do not match: orders is flagged and stays flat. No growing write goes unflagged: 80%.
6. By hand. Rows read for upkeep by one write, mean. Products: between 200 and 300 at 1,200 orders and between 50 and 85 at 300, growing 3.0 to 4.5 times. Customers: between 25 and 40 at 1,200 orders, growing at least 1.8 times. Orders: between 20 and 27 at both sizes. Lines: between 8.5 and 11 at both sizes. Any write at 1,200 orders: between 28 and 45: 65%. The in-order read adds about one row to each pair it redoes, because a pair now does its lookup.
7. By hand. An ask of the in-order read reads between 14 and 19 rows at 300 orders and between 60 and 75 at 1,200, as `bought` cost kept whole in experiment 10, 16.3 and 67.5: 75%.
8. Run. The controls. The eight controls of experiment 12 fail as before, with two named changes. Lookups never done again spoil four reads, not five, because the in-order read no longer waits at a lookup. Grouping a list whose order counts still spoils only the in-order read, but now by making that read wait and group, where before its waiting pairs were grouped: 80%.
9. By hand. The weakened write test counts only lookups by key, as experiment 10 put the cause. It flags products alone and misses customers, which grows: 90%.

**Controls that must fail.**

- The planted `noted` walks without saying so. It must be refused, and no other read may be refused.
- The weakened write test, lookups by key only, must miss a write that grows.
- The eight controls of experiment 12: rows in the opposite order, upkeep skipped, upkeep for another table skipped, the test dropped after the index, no notice when an index entry empties or fills, lookups never done again, a list grouped though its order counts, and grouping on no fields.

**Limits known before the run.**

- The writes are random writes to each table, not write functions. So a flag lands on a table, not on code someone wrote, and this run says nothing about where the word that accepts a growing write should go. It names the reads that cause each flag, which is the data for that question.
- The write test reads two shapes from the plan. The two it does not look for are named above.
- The line between flat and growing, 1.5 times, is Claude's.
- The store has about 40 customers and 25 products at both sizes, and about three lines to an order. So "grows" here means more orders for each customer and more lines for each product.
- The limits of experiment 12 stand.

### Experiment 14 as it will be run, written 2026-11-15 before any session

Experiment 13 flagged writes to orders, and those writes stayed flat. Its writes were random whole rows, so every write to an order counted as changing every field. Point 2 says a write redoes only the parts that read what it changed. `bought` reads an order only through its id and its customer, so paying or shipping an order should redo no part of it. The council of 2026-11-15 named this the first experiment to run before Robert decides on point 6 ([raw/council-2026-11-15-the-write-rule](raw/council-2026-11-15-the-write-rule/README.md)). Robert asked for it the same day.

**The sessions.** Four fresh agent sessions, two Claude and two GPT, each write `writes.mo`: between 6 and 10 functions that change the shop, one for each change its customers and staff make in an ordinary day. They choose the changes. They are told nothing of kept answers or of the rule. The materials are in [sketches/write-trial](sketches/write-trial/): the prompt, the task, and the same store and `STORE.md` as experiment 4. The task fixes only the form, so that a script can call the functions. Each takes the shop first and gives back the changed shop. It takes only `Int`, `Text` and `Status` after the shop. A parameter holding a row's id is named after its row type, and a new row's id is a parameter named `id`. Each session also writes tests of its functions on `Shop.sample` and must make them pass.

- **Claude:** a `general-purpose` subagent started with the Agent tool on `claude-fable-5-2`, as in experiment 4.
- **GPT:** `gpt-6.1-sol` through Codex, started with T3 Code's `delegate_task`, default settings, as in experiment 4.
- Every session counts. A session that ends without a `writes.mo` that checks adds no functions, and is reported.

**What changes in the planner.** All in `sketches/planner/`.

- **It runs write functions.** The script runs each function's Mo Core over the stored tables. A map's `set` and `remove` build a change to the table, and the script applies the change when the function returns. The arguments are random. A parameter named after a table gets the id of one of its rows. `id` gets a key no table holds. Other `Int`s get 1 to 29, a `Text` gets a city, a name or a note, and a `Status` gets one of the three. Each write calls one function, chosen with equal chance from all of them.
- **What a function can change, from its Mo Core.** The tables it calls `set` or `remove` on. For each table it sets, the fields its new rows do not copy from a row of the same type. A row built from nothing, as when a row is added, changes every field.
- **What a read reads, from its Mo Core.** For each table, the fields its code takes out of that table's rows.
- **Upkeep by field.** A write that changes a row's fields redoes a kept read's parts only when the read reads one of the fields that changed. A row added or removed counts as changing every field.
- **The write flag by field.** Experiment 13 flags a table: a write to it must redo one part for every row that names the row it changed. Now the flag is on a function. It is flagged for a table when experiment 13's test flags that table for some kept read, and the function either removes rows of it or changes a field of it that this read reads. A function that adds a row changes every field, so it is flagged wherever the table is flagged. The compiler cannot tell a new key from an old one, and nothing in the design promises that a row names only rows that exist.
- **The report** gives, for each function, who wrote it, what it changes, whether experiment 13's test flags it, whether the field test flags it and which reads cause that, and its mean upkeep at 300 and 1,200 orders. It says which of the reads that cause a flag were written by agents.
- **Two fixes the council asked for.** The count of parts in the upkeep lines now counts each part made or dropped, where experiment 13 counted one for each read. A dropped part is counted there, though it reads no row.

**What is kept from experiment 13.** The 42 reads. The random writes, now with upkeep by field, at both sizes, with the same seeds, the same comparison with real Mo, and the same controls. What counts as growing: mean upkeep at 1,200 orders at least 1.5 times the mean at 300. The function writes run on stores built the same way, at both sizes, and are compared with real Mo every 100 writes.

**One planted write.** `move_order` gives an order to another customer. Only the control needs it: no agent may write such a change, and the control has to make one. It is reported apart from the agents' functions.

**What Claude expects the agents to write, before seeing it.** Adding a customer, a product, an order and a line. Paying, shipping, and putting a note on an order. Changing a price, a quantity or a customer's city. Removing a line, and cancelling an order by removing it and its lines. Adding a line may also change the order's total.

**What Claude worked out from the plan before writing the predictions.** Experiment 13's test flags customers, orders and products. The field test then flags these:

- **Orders,** for any function that adds or removes an order or changes its customer. `bought` from GPT and from the reference, and the planted in-order read, read an order only through its id and its customer. Paying, shipping, a note or a new total is not flagged.
- **Customers,** for any function that adds or removes a customer or changes their city. Only the planted spend of a city causes it. It reads a customer's id and city, not their name.
- **Products,** for any function that adds or removes a product or changes its name. Only the planted in-order read causes it. It reads a product's name, not its price.
- **Lines** are not flagged, as in experiment 13.

**Predictions, Claude.** "Sessions" means it depends on what the agents write. "Run" means it depends on the run.

1. Sessions. All four sessions end with a `writes.mo` that checks and tests that pass: 75%.
2. Sessions. Every session writes a function that adds an order, and one that changes only an order's status: 85%.
3. Sessions. Experiment 13's test flags more than half of the agents' functions: 80%.
4. Sessions and run, the result that decides. No agent function is flagged by the field test if all it does is change an order's status, note, total or day, change a product's price, or add, change or remove lines without removing an order: 85%.
5. Sessions and run. Every agent function that adds an order, a customer or a product is flagged by the field test, and each is flat: 80%. That is the flag left standing where nothing grows.
6. Run. Every function whose upkeep grows is flagged by the field test. No growing function goes unflagged: 90%.
7. Run. A function that changes only an order's status reads at most 5 rows for upkeep on average, at both sizes. In experiment 13 a write to an order read 21: 75%.
8. Sessions and run. Of the agents' functions the field test flags, none is flagged by an agent-written read except for adding or removing an order. Every other flag comes from a planted read: 75%.
9. Run. Every answer is the same as Mo's, at every comparison, for both kinds of write: 75%. Running write functions and upkeep by field are both new.
10. Run. The control: skipping all upkeep for a write that changes an order's customer spoils `Planted.bought_in_order` and at least one `bought`. Every read it spoils reads an order's customer: 85%.
11. Run. The controls of experiment 13 fail as they did. Under the random writes, the tables experiment 13's test flags, and the ones that grow, are the same as in experiment 13: 85%.

**Controls that must fail.**

- Skipping all upkeep for a write that changes an order's customer must spoil some reads, and only reads that read an order's customer. In the control's run `move_order` makes one write in five, so the control has changes to miss.
- The controls of experiment 13, on the random writes: the planted walk that does not say `walk` is refused and nothing else is, the weakened write test misses a write that grows, and the eight controls of experiment 12.

**What it would mean.** If predictions 4 and 5 hold, tracking writes by field takes the flag off the ordinary writes. The flags left are on adding a row, removing one, and changing a field that parts are grouped or joined by or look up. Adding a row would stay flagged though it is flat, because nothing promises that a row names only rows that exist. A bound on the reference would not fix that; a promise like that would. Claude's 40% for the bound would fall, and the question for Robert would become whether point 6 should say that a new key fans out to nothing. If prediction 4 fails, ordinary writes keep the flag and the case for a bound comes back.

**Limits known before the run.**

- The agents chose the writes, but the task fixed their form and the script chose their arguments. Each function is called equally often, which no shop does.
- What a function can change is read from its Mo Core by copying of fields. A function that copies a field from another row of the same type would be read as leaving it unchanged. The comparison with Mo would catch a part left stale by that.
- The answers are compared with Mo at checkpoints, not after every write.
- The sessions run inside this repository, as in experiment 4, and are told to stay in their folders. Nothing stops one from reading elsewhere.
- The store is built as in experiment 13, with about three lines to an order, so a cancelled order drops about three pairs at both sizes.
- The limits of experiment 13 stand.

### Result of experiment 14, 2026-11-15

Run as committed in `91c7758`, with one fix after a void first run (below), at `aa0f07b`. The report is [sketches/planner/results/report-14.txt](sketches/planner/results/report-14.txt). The agents' functions are in [sketches/write-trial/results](sketches/write-trial/results/).

**Headline.** Tracking writes by field took the flag off half the agents' functions. Experiment 13's test flags all 30; the field test flags 15. Every function that only pays, ships, notes, reprices, renames a customer or changes lines is no longer flagged, and reads at most about 6 rows of upkeep at both sizes. Fifteen stay flagged. Nine add a row and stay flat. Six grow, and each is real fan-out: a customer who moves city redoes one part for every order they have, and a renamed product redoes one part for every line that names it. Every one of those six is flagged only because of a planted read. With the 21 agent-written reads alone, the field test flags three functions, all of them adding an order, and all flat.

**What the agents wrote.** All four sessions ended with a `writes.mo` that checks and tests that pass: 9, 6, 9 and 6 functions, 30 in all. They added customers (3), products (3), orders (3) and lines (2), removed lines (2), moved a customer to another city (4), renamed a product (2) or a customer (1), changed a price (3), an order's status (3) or its note (4). Adding or removing a line also changes the order's total. No agent removed an order, a customer or a product, and none gave an order to another customer.

| Functions | Field test | Rows read for upkeep, mean at 300 and 1,200 orders |
| --- | --- | --- |
| Add an order (3) | flagged: `bought` from GPT and from the reference, and the planted in-order read | 15.2 to 16.0, and 15.0 to 15.8; flat |
| Add a customer (3) | flagged: the planted spend of a city | 5.0 and 5.0; flat |
| Add a product (3) | flagged: the planted in-order read | 0 and 0; flat |
| Move a customer to another city (4) | flagged: the planted spend of a city | 10.5 to 14.3, and 20.7 to 40.0; grows 2.0 to 3.5 times |
| Rename a product (2) | flagged: the planted in-order read | 25.7 and 46.7, and 163.6 and 196.0; grows 3.5 and 7.6 times |
| Change an order's status (3) | not flagged | 1.4 to 2.3, and 1.0 to 2.3 |
| Change an order's note (4) | not flagged | at most 1.0 |
| Change a price (3) | not flagged | 0 |
| Rename a customer (1) | not flagged | 2.0 and 2.0 |
| Add a line (2) | not flagged | 4.0 to 4.6, and 5.3 to 5.9 |
| Remove a line (2) | not flagged | 0.6 and 0.7, and 0.8 and 1.1 |

Adding an order reads about 15 rows because about 15 kept reads hold a part for each order, and each makes one. No line names a new order, so no pair is made.

**Predictions.**

1. All four sessions end with a module that checks and tests that pass: held.
2. Every session writes a function that adds an order and one that changes only an order's status: failed. One GPT session added no order, and the other changed no status.
3. Experiment 13's test flags more than half of the agents' functions: held, all 30.
4. No function is flagged by the field test if all it does is change an order's status, note, total or day, change a price, or add, change or remove lines without removing an order: held, for all 15 such functions.
5. Every function that adds an order, a customer or a product is flagged by the field test, and each is flat: held, all nine.
6. No function that grows goes unflagged: failed, by the line fixed before the run. One of the two functions that remove a line read 0.7 rows at 300 orders and 1.1 at 1,200, which is 1.57 times. Its twin read 0.6 and 0.8. In the void first run the other one crossed the line, at 0.3 and 0.8. Claude reads this as noise in a mean under one row over 16 to 25 calls, but did not check it. Every function that grows by more than a row is flagged.
7. A function that changes only an order's status reads at most 5 rows on average at both sizes: held, at most 2.3.
8. No field flag comes from an agent-written read except for adding or removing an order: held. Adding an order is flagged by `bought` from GPT; every other flag comes from a planted read.
9. Every answer is the same as Mo's at every comparison, for both kinds of write: held, in both full runs.
10. Skipping upkeep for a write that changes an order's customer spoils the planted in-order read and at least one `bought`, and only reads that read an order's customer: held. It spoiled 11 reads, among them both `bought`s and the in-order read, all of which read an order's customer.
11. The controls of experiment 13 fail as they did, and under random writes the flags and the growth are the same: held. Every control line matches experiment 13's report. Customers and products grow and are flagged; orders are flagged and flat.

**Under random writes,** upkeep by field changed little, because a random write changes most fields. At 1,200 orders: customers 24.9 rows against 31.7 in experiment 13, products 237.5 against 252.3, orders 20.2 against 21.6, lines 9.3 against 9.3, any write 32.4 against 34.6. Under the agents' functions, any write read 6.8 rows at 300 orders and 21.3 at 1,200.

**What went wrong on the way.**

- The first parse of the functions read W3's `expose` as one line, though it spans nine, and found one function in place of nine. Claude fixed it before any run.
- The first full run is void. Mo Core names a map's `has?` as `has`, which the script did not know. All 11 functions that add a row check `has?` first, so each of their calls stopped with a fault and changed nothing. The script counted the faults but did not stop on them. Claude fixed the name, made the script stop on any fault, and ran again. Only the second run is recorded.
- The Claude sessions were started through T3 Code's `delegate_task` on `claude-fable-5-2`, not the Agent tool written above, so that they could run in the background. The prompt and the model are the same.

**What it means.** Claude's 40% for a bound on the reference falls to 10%. The flags left after tracking by field are of two kinds. The six that grow are true fan-out over references with no natural limit: orders for a customer, lines for a product. A bound there would be a guess with a number on it. The nine that do not grow are on adding a row. A bound does not touch those. They stand because the compiler cannot tell a new key from an old one, and nothing in the design promises that a field naming a row names one that exists. With such a promise, a row added under a new key is named by no row, and the flag would come off. Removing a row would then be refused or would take the rows that name it with it, which is a choice the rule would have to make.

**What it does not show.**

- No agent removed an order, a customer or a product, or gave an order to another customer. So no agent function tested the deletes that the council expected to keep the flag. The planted `move_order` ran only in the control.
- The task fixed the form of the functions. Telling agents to take a new row's id as a parameter is part of why the compiler cannot know the key is new. A store that makes its own keys would know.
- The arguments are random, and every function is called equally often. One GPT session named its parameters `value`, so the script gave its cities and names the words of a note.
- The answers are compared with Mo every 100 writes, not after each one.
- Which fields a function changes is read from its Mo Core by which fields it copies. Each of the 30 readings matches what the function's name says. Claude did not check each one against its code; the comparison with Mo is what would catch a part left stale.
- The store has about three lines to an order and about 40 customers at both sizes, as in experiment 13.

### Result of experiment 13, 2026-11-15

Run with `python3 sketches/planner/planner.py`. The full table is in [`sketches/planner/results/report-13.txt`](sketches/planner/results/report-13.txt). The script as it ran is at commit `9015185`.

**What it shows.**

- **Every answer matched Mo's, on the first run that completed.** 42 reads and 23,922 answers.
- **One read was refused, the planted `noted`.** It walks the orders and does not say `walk`. The five other reads that walk all say it, so nothing else was refused.
- **The write test can be worked out from the plan, and it catches every write that grows.** Writes to each table, against what was measured:

| A write to | What the flagged reads must keep up | Reads that cause the flag | Rows read for upkeep, mean, at 300 and 1,200 orders | Grows? | Flagged? |
| --- | --- | --- | --- | --- | --- |
| customers | One part for every order that names this customer | The planted spend of a city | 14.5 and 31.7, 2.2 times | Yes | Yes |
| products | One part for every line that names this product | The planted in-order read | 67.4 and 252.3, 3.7 times | Yes | Yes |
| orders | One part for every line that names this order | `bought` from GPT and from the reference, the planted in-order read | 21.0 and 21.6 | No | Yes |
| lines | One part for each kept read, nothing more | None | 9.3 and 9.3 | No | No |

- **The flags are not the growing writes.** Writes to orders are flagged and stay flat. Nothing that grows went unflagged. This is the result that decides, and it says the write half of point 6 flags a shape, not growth. An order has about three lines at both sizes, and a customer has four times as many orders at the larger size. In the plan the two look the same: a part for every row that names the written row. The compiler cannot tell a few from many, because that is a fact about the rows.
- **Grouping does not save the outer table of a pair.** `bought` from GPT and from the reference are grouped by point 3, and a write to a product costs them nothing. A write to an order still redoes a part for each of its lines, because the parts are pairs of an order and a line.
- **Point 4 behaved as in experiment 10.** The planted in-order read, kept whole, cost 16.3 and 67.5 rows an ask, as `bought` kept whole did, and it is the only read that makes a write to a product grow. Experiment 12 cost it 161.5 rows an ask and nothing on a write to a product.
- **What the rule costs over all writes.** At 1,200 orders a write reads 34.6 rows for upkeep on average, against 13.5 in experiment 12. Writes to products account for nearly all of the difference, through the one read point 4 keeps whole.

**Predictions against the result.** All nine held. Seven were of the kind that can be worked out by hand, so they show that Claude read the plan right, not that the rule is right. The two marked "run" are the real tests: every answer is still Mo's, and every control failed where it should.

| Prediction | Result |
| --- | --- |
| 1. Run: an answer differs from Mo's on the first complete run, 20% | Did not happen |
| 2. By hand: only `noted` is refused, 95% | Held |
| 3. By hand: classes by key 3, kept 24, looked up 9, walked 6; agent-written unchanged, 90% | Held |
| 4. By hand: customers, orders and products flagged, lines not, with the causes named, 90% | Held |
| 5. By hand, the deciding one: customers and products grow, orders and lines do not; orders flagged and flat; nothing growing unflagged, 80% | Held |
| 6. By hand: products 200 to 300 and 50 to 85, 3.0 to 4.5 times; customers 25 to 40 and at least 1.8 times; orders 20 to 27; lines 8.5 to 11; any write 28 to 45, 65% | Held: 252.3 and 67.4, 3.7 times; 31.7, 2.2 times; 21.0 and 21.6; 9.3 and 9.3; 34.6 |
| 7. By hand: the in-order read 14 to 19 and 60 to 75 rows an ask, 75% | Held: 16.3 and 67.5 |
| 8. Run: the eight controls of experiment 12 fail as before, with the two named changes, 80% | Held |
| 9. By hand: the weakened test flags products alone and misses customers, 90% | Held |

**Controls.**

- The planted walk that does not say `walk` was refused, and nothing else was.
- The weakened write test, lookups by key only, flagged products alone. It missed customers, which grows.
- Rows in the opposite order, upkeep skipped, upkeep for another table skipped, the test dropped after the index, and no notice when an index entry empties or fills each spoiled the same reads as in experiment 12.
- Lookups never done again spoiled four reads, not five, because the in-order read no longer waits at a lookup. Named before the run.
- A list grouped though its order counts spoiled the in-order read and nothing else. It now does so by making that read wait and group, as named before the run.
- Grouping on no fields spoiled the four grouped reads, as before.

**What went wrong on the way.** The first full run finished and its closing checks passed. Its summary line counted writes to lines as flagged, though the table above it said "not flagged". The cause was Claude's report code: asking a `defaultdict` for a table with no flag added an empty entry. The fix touched only the report. The run was done again at commit `9015185`, and that report is the one recorded. A trial on stores of 60 and 240 orders ran before the first full run and gave no difference from Mo.

**What it does not show.**

- **A bound on a reference.** The finding points to one missing input: how many rows can name one row. The code could state it, for example that an order has at most some number of lines, or the store could measure it. Neither was tried.
- **Write functions.** The writes are random writes to each table. A flag here lands on a table, not on code someone wrote. The reads named as causes are the data for where the accepting word should go, which is still open.
- **Point 4 for a part for one row.** No read here has a part for one row with a lookup where order counts. Point 4 was run only on pairs.
- **The two shapes the test does not look for:** a part that reads an index of another table by something other than its own row's key, and a part that reads a whole table. No read here has either.
- **The line between flat and growing,** 1.5 times, is Claude's. Every write was well clear of it: 1.0 or 1.03 times, or 2.2 times and more.
- The limits written before the run stand, and so do those of experiments 8 to 12.

### Result of experiment 12, 2026-11-15

Run with `python3 sketches/planner/planner.py`. The full table is in [`sketches/planner/results/report-12.txt`](sketches/planner/results/report-12.txt). The script as it ran is at commit `0782258`.

**What it shows.**

- **Every answer matched Mo's, on the first run that completed.** 41 reads and 23,877 answers.
- **The planner found the grouping from Mo Core alone.** It grouped `bought` by the line's product, the planted revenue by product and quantity, and the planted buyers by the line's order. It left the planted in-order read ungrouped. No new syntax was needed for these reads.
- **Rows read by one ask at 1,200 orders, under each way of keeping:**

| Read | Kept whole, experiment 10 | Lookup at the ask, experiment 11 | Grouped, experiment 12 | Nothing kept |
| --- | --- | --- | --- | --- |
| `bought`, GPT and reference | 67.5 | 161.5 | 51.5 | 189.0 |
| planted revenue | 1.0 | 248.4 | 17.4, or 9.7 with a row looked up twice counted once | 248.4 |
| planted buyers | 105.8 | 369.8 | 350.1 | 369.8 |

- **Rows read for upkeep by one write, mean, at 1,200 orders:**

| A write to | Kept whole, experiment 10 | Lookup at the ask, experiment 11 | Grouped, experiment 12 |
| --- | --- | --- | --- |
| lines | 10.9 | 5.5 | 8.5 |
| orders | 25.0 | 16.1 | 20.1 |
| customers | 191.1 | 31.7 | 31.7 |
| products | 675.4 | 0.0 | 0.0 |
| any table | 83.1 | 10.7 | 13.5 |

Experiment 12 has one more kept read than experiment 11, the planted in-order read, and two reads kept again. That is why its writes to lines and orders sit a little higher.

- **Grouping makes both sides cheap where the lookup key repeats.** A customer buys the same products again and again, so `bought` holds at most one entry for each product. At 1,200 orders it is cheaper to ask than the whole kept answer was, and a write to a product costs nothing. It grew 2.0 times between the sizes where the whole answer grew 4.1 times, and it cannot pass twice the number of products.
- **Revenue fell from 248 rows to 17, not to 2.** It holds one entry for each quantity of a product, 1 to 9. The last step needs the planner to know that quantity times price can be totalled before the price is known. That is not built.
- **Grouping does nothing where the key does not repeat.** The buyers read looks up an order from each line, and the lines of a product nearly all belong to different orders. The lookup that fans out there is the second one, of the customer. A part that kept through the order and waited at the customer would hold at most one entry for each customer. The script cannot do that: it waits at the first lookup.
- **A list whose order counts cannot be grouped.** The planted in-order read costs what `bought` cost in experiment 11, 161.5 rows.

**Predictions against the result.** All seven went as predicted.

| Prediction | Result |
| --- | --- |
| 1. An answer differs from Mo's on the first complete run, 45% | Did not happen |
| 2. Five reads wait at a lookup, grouped as named; kept 24, looked up 9, 80% | Held |
| 3. `bought` between 45 and 60 rows at 1,200 orders and 23 and 32 at 300, growing under 2.3 times, 70% | Held: 51.5 and 26.1, 2.0 times |
| 4. Revenue between 14 and 20 rows at both sizes, 8 to 11 counted once, 75% | Held: 17.0 and 17.4; 9.5 and 9.7 |
| 5. Buyers between 330 and 372 rows at 1,200 orders, 70% | Held: 350.1 |
| 6. Products 0.0; lines under 12 and orders under 28, both flat; mean at 1,200 orders under 18, 70% | Held: 8.5 and 8.5; 19.5 and 20.1; 13.5 |
| 7. The in-order read between 150 and 175 rows at 1,200 orders, 75% | Held: 161.5 |

The predictions of experiments 11 and 12 all held, and that says less than it seems. The script counts rows by fixed rules, so its costs can be worked out by hand before it runs. What the runs test is the part that cannot be worked out: that every answer is still Mo's, and that each control fails where it should.

**Controls.** Grouping on no fields spoiled the four grouped reads and nothing else. Grouping the planted in-order read spoiled that read and nothing else. Lookups never done again spoiled the five reads that wait at a lookup and nothing else. The five controls of experiment 10 failed as before.

**What it does not show.**

- Whether real programs sort their lists as often as these do. Three of the four list reads here end in `unique` and `sort`, because the task asked for sorted names. Where a program wants its rows in table order, grouping is closed.
- The rule for order knows one shape. A count, a set or a test for membership also does not lean on order, and none is recognised.
- Which lookup to wait at. The script waits at the first. The buyers read needs the second.
- Totalling before the lookup.
- The limits written before the run stand, and so do those of experiments 8 to 11. The store still has about 40 customers and 25 products at both sizes.

### Result of experiment 11, 2026-11-15

Run with `python3 sketches/planner/planner.py`. The full table is in [`sketches/planner/results/report-11.txt`](sketches/planner/results/report-11.txt). The script as it ran is at commit `8eda276`.

**What it shows.**

- **Every answer matched Mo's, on the first run that completed.** The same 40 reads and 23,499 answers.
- **A write got cheap.** Rows read for upkeep by one write, mean, experiment 10 against experiment 11:

| A write to | At 300 orders | At 1,200 orders | Grows with the store? |
| --- | --- | --- | --- |
| lines | 10.9, now 5.4 | 10.9, now 5.5 | No |
| orders | 24.8, now 15.6 | 25.0, now 16.1 | No |
| customers | 68.1, now 14.5 | 191.1, now 31.7 | Yes, 2.2 times |
| products | 183.8, now 0.0 | 675.4, now 0.0 | No |
| any table | 35.2, now 9.0 | 83.1, now 10.7 | Barely, 1.2 times |

- **An ask got dear, for the four reads that changed.** Rows read by one ask at 1,200 orders:

| Read | Kept whole, experiment 10 | Lookup at the ask | Lookup at the ask, a row looked up twice counted once | Nothing kept |
| --- | --- | --- | --- | --- |
| `bought`, GPT and reference | 67.5 | 161.5 | 106.5 | 189.0, or 134.1 counted once (Claude's `bought`) |
| planted revenue | 1.0 | 248.4 | 125.1 | the same: nothing is kept |
| planted buyers | 105.8 | 369.8 | 280.9 | the same: nothing is kept |

- **Plain late lookup is a weak lever, as Claude expected before the run.** For `bought` it saves 15% of what keeping nothing costs. For the two planted reads it is keeping nothing. The cost has moved from the write to the ask, and it has grown on the way: one write to a product cost 675 rows, and now every ask of revenue costs 248.
- **So which side should pay depends on how often each happens.** A product changes rarely and its revenue is asked often. For such a read keeping the whole answer is the better deal, with the growing write said in the code, as Robert decided. Late lookup suits the opposite case.
- **What is left of growing writes is one read.** A write to a customer still grows, because the planted spend of a city holds a part for each of that customer's orders. This store has about 40 customers at both sizes, so orders for each customer grow with it.

**Predictions against the result.** All seven went as predicted.

| Prediction | Result |
| --- | --- |
| 1. An answer differs from Mo's on the first complete run, 35% | Did not happen |
| 2. Exactly four reads change, 85% | Held: the two planted reads are looked up, the two `bought` keep pairs |
| 3. A write to products under 5 rows at both sizes, 85% | Held: 0.0 and 0.0 |
| 4. A write to customers under 100 rows at 1,200 orders, still more than doubling, 70% | Held: 31.7, and 2.2 times |
| 5. Mean upkeep at 1,200 orders under 25 rows, 70% | Held: 10.7 |
| 6. Asks at 1,200 orders: `bought` 145 to 175, revenue 230 to 260, buyers 320 to 390, 65% | Held: 161.5, 248.4, 369.8 |
| 7. Counted once: `bought` under 115, revenue under 130, 65% | Held: 106.5, 125.1 |

**Controls.** Pairs whose lookups were done once and never again spoiled `bought` from GPT and from the reference, and nothing else. The five controls of experiment 10 failed as before. The planted revenue and buyers reads no longer show in the two upkeep controls, because they are no longer kept.

**What it does not show.**

- Nothing is grouped. The revenue read needs one number for each product, a total of quantities, and one lookup of the price. That would make both sides cheap: about two rows an ask and nothing on a write to a product. The same idea for `bought` is one kept entry for each distinct product a customer bought. This is the lever not yet tried, and the sketch cannot do it as built, because it runs whole functions over one or two rows and cannot split a part at the lookup.
- The script moves every lookup by key, whatever it costs. The buyers read looks up an order from each line, and an order has about three lines, so that lookup never grew. Only the lookup of the customer did. Which lookup fans out is a fact about the rows, and the code does not show it.
- "Grows with the store" here means grows with the number of orders, in a store whose customers and products stay at about 40 and 25. A write rule needs to say what a write's cost is counted against. The compiler can say "one part for every line that names this product". It cannot say how many lines that is.
- The limits written before the run stand, and so do those of experiments 8, 9 and 10.

### Result of experiment 10, 2026-11-15

Run with `python3 sketches/planner/planner.py`. The full table is in [`sketches/planner/results/report-10.txt`](sketches/planner/results/report-10.txt).

**What it shows.**

- **Every answer matched Mo's, on the first run that completed.** The same 40 reads and 23,499 answers as experiment 9.
- **Rows read for upkeep by one write, mean, experiment 9 against experiment 10:**

| A write to | At 300 orders | At 1,200 orders | Grows with the store? |
| --- | --- | --- | --- |
| lines | 34.0, now 10.9 | 35.5, now 10.9 | No |
| orders | 54.5, now 24.8 | 137.1, now 25.0 | No longer |
| customers | 71.5, now 68.1 | 203.4, now 191.1 | Yes, 2.8 times |
| products | 412.3, now 183.8 | 1,577.2, now 675.4 | Yes, 3.7 times |
| any table | 78.1, now 35.2 | 206.0, now 83.1 | Yes, 2.4 times |

- **Part of experiment 9's cost was the shortcut, and part is real.** Working out a part again accounted for all the growth in writes to orders and for more than half the cost of a write to products. What is left has one cause. A product is looked up by key from a part for every line that names it, and a customer from a part for every line they bought. Change that one row and each of those parts must change. The number of them grows with the store.
- **So the rule for writes has a clear target.** A kept answer that reaches through a lookup by key into another table makes writes to that table grow. A kept answer that stays on its own table, or reaches the other way, from one row to its many, does not.
- **Three reads got a part for each pair of rows**: the planted spend of a city, and `bought` from GPT and from the reference.
- **What one ask costs did not change**, except for the reference `idle_customers`, which walks customers and asks `any?` for each. It fell from 300.3 and 1,096.5 rows to 73.3 and 82.0, because `any?` now reads one index entry.

**Predictions against the result.**

| Prediction | Result |
| --- | --- |
| 1. An answer differs from Mo's on the first complete run, 50% | Did not happen |
| 2. Exactly three reads get a part for each pair, 75% | Held, the three named |
| 3. A write to orders within 1.3 times between sizes, 70% | Held: 24.8 and 25.0 |
| 4. A write to products under 500 rows at 1,200 orders, and about four times its cost at 300, 75% | The number missed: 675.4. The growth held: 3.7 times |
| 5. A write to customers still more than doubles, 70% | Held: 2.8 times |
| 6. Mean upkeep at 1,200 orders under 80 rows, 60% | Missed narrowly: 83.1 |
| 7. Every ask within a tenth of experiment 9, 85% | Missed for one read, which got cheaper |

**Controls.** Dropping the notice when an index entry empties or fills spoiled the three kept reads that ask `any?` and nothing else. The four controls of experiment 9 failed as before, on the same reads.

**What it does not show.**

- The count of rows includes the one or two rows a part is run over, so a part that does one lookup counts as two or three rows. The figures for products and customers are high by about that factor.
- No arithmetic is done on a part, as said before the run. For the planted revenue read, a kept total of quantities for each product, multiplied by the price when asked, would make a price change cost nothing.
- Nothing here tries the other answer to a lookup that fans out: keep the answer up to the lookup, and do the lookup when asked.
- The limits of experiments 8 and 9 stand.

### Result of experiment 9, 2026-11-15

Run with `python3 sketches/planner/planner.py`. The full table is in [`sketches/planner/results/report-9.txt`](sketches/planner/results/report-9.txt). The script as it ran is at commit `595dca7`.

**What it shows.**

- **Every answer matched Mo's again.** 40 reads, 23,499 answers compared at 9 checkpoints, through 1,200 random writes, on stores of 300 and 1,200 orders. None differed, on the first run that completed.
- **Walks became rare.** Of the 21 agent-written reads, 12 are kept, 5 looked up, 2 read by key and 2 walked. In experiment 8 it was 6, 9, 2 and 4. The two that still walk are both `mentions`, whose test is `contains` on a word the caller gives.
- **What one ask costs, in rows read, at 300 orders and at 1,200:**

| Read | Experiment 8 | Experiment 9 |
| --- | --- | --- |
| `idle_customers`, customers with no orders | walked: 300.3 and 1,141.0 | kept: 1.7 and 7.5 |
| `bought` from GPT, a join of three tables | looked up: 44.2 and 190.0 | kept: 16.3 and 67.5 |
| `orders_of`, `city_customers` | looked up: 6.8 and 27.4 | kept: 6.9 and 27.6, no gain |
| Planted: spend of a city, across two tables | not run | kept: 1.0 and 1.0 |
| Planted: revenue of a product, price from another table | not run | kept: 1.0 and 1.0 |
| Planted: orders with no lines | not run | kept: 28.9 and 77.0, the size of the answer |
| Planted: buyers of a product, across three tables | not run | kept: 24.2 and 105.8 |

- **Keeping a plain pick gains nothing.** A kept list of a customer's orders is the index under another name.
- **A write pays, and for a join the price grows with the store.** Rows read for upkeep by one write:

| A write to | At 300 orders, mean and most | At 1,200 orders, mean and most |
| --- | --- | --- |
| lines | 34.0 and 84 | 35.5 and 79 |
| orders | 54.5 and 119 | 137.1 and 276 |
| customers | 71.5 and 149 | 203.4 and 425 |
| products | 412.3 and 776 | 1,577.2 and 2,810 |
| any table | 78.1 | 206.0 |

A change to one product redoes the part of every line that read that product, for each of the three kept reads that read products. At 1,200 orders that is more rows than a walk of the orders table. A write to lines stays flat because no kept answer reads lines from another table's side.

- **The rule refuses what it cannot show to be separate for each row.** `bought` from Claude looks in its own list before it appends, so it was not kept, though keeping it would have been right. The planted maximum, the sum that uses its total twice, and the customer with the most orders were not kept.
- **Mo writes `.sum` out as a loop in place.** It is not a call in Mo Core. So the two reference sums written `.map(...).sum` were kept as lists that are summed on each ask, at the cost of looking them up.

**Predictions against the result.**

| Prediction | Result |
| --- | --- |
| 1. An answer differs from Mo's on the first complete run, 55% | Did not happen. A trial on a store of 60 orders, before the full run, also gave no difference |
| 2. `idle_customers` kept, under 5 rows an ask at both sizes, 75% | Kept. 1.7 rows at 300 orders and 7.5 at 1,200, so the number missed at the larger size. The cost is the size of the answer |
| 3. `bought` from GPT kept, from Claude not, 80% | Held |
| 4. `mentions` stays walked, 95%; `latest` and `large_orders` stay looked up, 90% | Held |
| 5. The two reference sums become kept numbers at one row an ask, 85% | Missed. Kept, but as lists, at 2.3 to 124.2 rows an ask |
| 6. Agent-written walks fall from 4 to 2, 75% | Held |
| 7. Four planted reads kept, the customer with most orders not, 70% | Held |
| 8. A product change redoes about four times as many parts at 1,200 orders, 80%; mean upkeep under 30 rows at both sizes, 60% | First part held: 66.7 parts and entries against 243.3, and 412 rows against 1,577. Second part missed by a wide margin: 78.1 and 206.0 |

**Controls.** Updates that skip all upkeep spoiled 21 of the 23 kept answers and nothing that is not kept. Upkeep skipped after a write to another table spoiled the eight kept answers that span tables and no other. A dropped test spoiled only the planted read whose test goes beyond its index. The three planted reads that must not be kept were not.

**What went wrong on the way.** The first full run stopped at its last step on a mistake in Claude's own closing check, which named the answers that span tables wrongly. The report it had already written is identical to the second run's. A rule for a call to `sum` was removed before the full run, when the trial on 60 orders showed that Mo Core has no such call.

**What it does not show.**

- **The cost of a write is an upper bound for this rule, as said before the run.** A part is worked out again, not adjusted. When an order changes, its customer's part is redone from all of that customer's orders. Adjusting it in one step would cost one row.
- Three kept reads read products, two of them near copies. A program with one such read would pay about a third of the product figure.
- The five new reads were planted by Claude, who knew the rule. They show what the rule can keep, not how often code written without it would qualify.
- The mix of writes is Claude's: half to lines, a third to orders, a twelfth each to customers and products. Another mix gives another mean.
- The rest of experiment 8's limits stand: a script beside the compiler, rows counted and not timed, agents who had been told a rule, and tables that keep the order rows arrived in.

### Result of experiment 8, 2026-11-15

Run with `python3 sketches/planner/planner.py`, on the Mo binary frozen for experiment 4. The full table is in [`sketches/planner/results/report-8.txt`](sketches/planner/results/report-8.txt). The script as it ran is at commit `f55a416`; experiment 9 has since widened it.

**What it shows.**

- **All 21 agent-written reads were planned from Mo Core alone, and every answer matched Mo's.** With the 11 reference reads and 3 planted ones that makes 35 reads. The script compared 22,923 answers with real Mo at 9 checkpoints, through 800 random writes, on a store of 300 orders and one of 1,200. None differed.
- **The three classes came out by rule, with nobody declaring an index.**

| Task | Class | What the script kept | Rows read for one ask, at 300 orders and at 1,200 |
| --- | --- | --- | --- |
| `product_name` | by key | nothing | 1.0 and 1.0 |
| `open_count` | kept | one number | 1.0 and 1.0 |
| `paid_total` | kept | one number for each customer | 1.0 and 1.0 |
| `units_sold` | kept | one number for each product | 1.0 and 1.0 |
| `orders_of`, `latest` | looked up | orders by customer | 6.8 and 27.4 |
| `city_customers` | looked up | customers by city | 6.2 and 7.2 |
| `bought` | looked up | orders by customer, lines by order | 44.2 and 190.0 |
| `large_orders` | looked up | orders in order of total | 167.8 and 652.8 |
| `mentions` | walked | nothing | 306.1 and 1,209.0 |
| `idle_customers` | walked | orders by customer | 300.3 and 1,141.0 |

- **A kept read costs the same at both sizes. A looked-up read grows with its answer. A walked read grows with the table.**
- **A write pays for what is kept.** One write adjusted 7.1 index entries and kept answers on average at 300 orders and 6.9 at 1,200, and at most 16 at both.
- **Mo Core keeps a library call and its test whole.** `filter`, `count` and `any?` arrive as calls that take the test as a function. A `for` loop is lowered to joins and jumps. So Gemini Carbon's point in the council holds for loops and not for library calls. A loop over rows that a `filter` already picked was still planned, because the pick happens at the call.
- **Two of the 21 agent-written reads lean on the order of the table.** `orders_of` and `large_orders` from GPT return ids in the order `filter` gives them and never sort, though the task says smallest first. They passed experiment 4 because its rows sit in id order. They gave Mo's answers here for the same reason, and changed when the index handed rows back in the opposite order. A table with no order of its own would make such a read an error or a visible choice.
- **The rule for kept answers is narrow.** It takes a count, or a loop that only adds to one number, over rows picked by equality on every parameter. It kept all six agent-written sums and counts. It missed two of Claude's own reference reads, which sum with `.map(...).sum`; they were looked up instead.

**Predictions against the result.**

| Prediction | Result |
| --- | --- |
| 1. Mo Core keeps the library call and its test, 90% | Held for every read |
| 2. At least 14 of 21 understood, 65%; `for` loops not understood, 70% | 21 of 21. The loop part missed: every loop here runs over rows a `filter` had picked, and was planned |
| 3. Each read lands in the class listed, 75% | Held for all 21 agent-written reads. Missed for 2 of the 11 references, `paid_total` and `units_sold`, which were looked up and not kept |
| 4. A kept answer differs from Mo's on the first complete run, 50% | Did not happen. No answer the script gave was ever wrong. Earlier runs stopped short for other reasons, listed below |
| 5. A kept read touches one entry at any size, and a write's upkeep does not grow with the store, 90% | Held |
| 6. No agent-written read changes when an index reverses its rows, 70%; the planted one does, 95% | Missed: two changed. The planted one changed |
| Gemini Carbon, council: under 20% matched on Mo Core, at 80% | 21 of 21 on this corpus. The agents here had been told a rule, and Gemini Carbon's prediction was for agents told nothing |

**Controls.** Updates that skip the upkeep spoiled all seven kept answers and nothing else. A test dropped after the index spoiled the one read whose test goes beyond its index. Every `mentions` came out walked. The planted maximum and the planted sum that uses its total twice were not kept.

**What went wrong on the way.** Five runs, the last clean.

1. Mo refused the larger store written as one function: error E1153, "lowered body exceeds the Core path limit". About 1,270 rows in one function passed and about 3,000 did not. The rows are now split, 400 to a function.
2. The script lacked integer division, which Mo's library sort uses. Nine reads stopped. None gave a wrong answer.
3. The pilot's module took the name of session 01, so one read was missing from the second run.
4. The control that drops the test could not fail: no read in the corpus has a test that goes beyond its index. `gifts` was planted to give it one. This is a change to a control after seeing a result.
5. Index upkeep was not counted at 1,200 orders, because the indexes were first built after the writes. A checkpoint before the writes fixed the count.

**What it does not show.**

- The planner is a Python script beside the compiler, not a pass inside it. It handles only the forms these reads use.
- The agents had been told arm A's rule, so every test sits in a library call. A test written as an `if` inside a loop over the whole table would come out walked. Experiment 1 found that this is how agents write when told nothing.
- An answer is kept only for a sum or a count on one table. `idle_customers` needs two tables at once and `bought` is a join; neither is kept.
- Speed is counted in rows read, not timed. The kept answers and indexes live in Python, not in a store on disk.
- An index key is used only when working it out early cannot stop the program. That sidesteps the council's point about a value that stops; it does not test it.
- The rows keep the order they arrived in, as Mo's `Map` does. Tables with no order were not tried.

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
- **Tables in the language after experiment 8: 85% for I.** The thing that would have moved the 80% down was a common read whose plan changes the answer. On this corpus none did. The two reads that changed under a reversed index are reads that already lean on an order the task did not give them.
- **After experiment 9: keeping answers makes walks rare, and a write then needs a cost of its own.** The compiler can keep a join, and a read of it becomes cheap. The write that feeds it is then the slow part, and it can be slower than the walk it replaced. So the same rule that refuses an unmarked walk in a read should apply to a write: the compiler works out what a write must keep up, and a write whose upkeep grows with the store is an error unless the code says so. Claude holds this at 70%. What would move it: a way of adjusting a part in one step that covers the joins here, which would make the growth go away. Robert decided it on 2026-11-15: a write is held to the same rule as a read.
- **After experiment 10: what the write rule must catch is a lookup that fans out.** Finer parts made writes to orders and lines flat. Writes to products and customers still grow, because one of their rows is read by a part for every line that refers to it. Claude sees three answers and has tested none: refuse the read as kept, stop keeping at the lookup and do it when asked, or do arithmetic on the kept value.
- **After experiment 11: doing the lookup when asked is real and weak.** It made writes flat and cheap, 10.7 rows against 83.1. It made the four reads it touched cost about what keeping nothing costs. So it is a choice between who pays, and the compiler cannot make it, because it turns on how often a row changes against how often the read is asked. Claude's view, at 70%: keep the whole answer by default, report the write that grows, and let the code say which it wants. What would move it: grouping before the lookup, which should make both sides cheap for sums and for lists without repeats. That is untested.
- **After experiment 12: grouping before the lookup works where the key repeats and order does not count, and the compiler can find it.** That moves the 70% above. Claude's view now, at 75%: where a part looks up another table, the compiler groups before the lookup when it can show order does not count, and keeps the whole answer otherwise. It reports what each write must keep up, in the terms it knows: one part for every line that names this product. A write whose upkeep is one part for each row that refers to the written row is the growing kind, and is an error unless the code says so. What is still open is small beside that: which lookup to wait at, totalling before a lookup, and more shapes that do not lean on order.
- **After experiment 13: the rule runs whole, and the write half of point 6 is too coarse as written.** The read error refused exactly the one planted walk. The write test, worked out from the plan alone, flagged every write that grew and one that did not: a write to an order redoes a part for each of its lines, and an order has about three. The compiler sees "one part for every row that names this row" and cannot see how many rows that is. Claude's view, at 70%: keep the test as the compiler's report, and let the code state a bound on a reference, such as at most so many lines to an order, so a flagged write with a stated bound is not an error. Without that, every program with a pair of an order and its lines must say the word for writes that never grow. What would move it: a corpus where few-to-one references are rare, or a store that can measure the bound for itself.
- **After the council on the write rule, 2026-11-15: the bound is the wrong next step, at 60% against it.** [Three reviewers, two rounds](raw/council-2026-11-15-the-write-rule/README.md). In round 2 two of the three said keep the write half of point 6 as written, and one said add a bound that every write checks, at 62% to 72% each. All three named the same first experiment. The script redoes a part when any field of a row it read changes, but point 2 says a write redoes only the parts that read what it changed. `bought` reads an order only through its id and its customer, and the spend of a city reads a customer only through its id and city. So paying, shipping or editing an order should redo no line part, and the flag on orders may come from writes of whole rows, not from a need for a bound. Claude's 70% for the bound falls to 40%. What would move it back: the next experiment, with the planner tracking fields and the writes written as write functions by agents who were not told the rule, still flagging ordinary writes on references that have a real limit.
- **After experiment 14: no bound, at 90%.** Tracking writes by field took the flag off every ordinary update the agents wrote. The flags that grow are true fan-out over references with no natural limit, orders for a customer and lines for a product, so a bound there would be a guess with a number on it. The flags that stay flat are on adding a row, which a bound does not touch. What would bring the bound back: agent-written reads that fan out over a reference with a real limit, such as lines on an order, under writes that change what they read. What the rule still lacks: a way to know a new key is named by no row, from a promise that a field naming a row names one that exists, or from keys the store makes.
- **The growth test as a check: closed by experiment 5.** Before it ran Claude gave it 15%.

## Decision 2. Is the store a library written in Mo or part of the runtime?

**Status:** open. Robert accepted [the plan](docs/plans/2026-11-15-2037-decision-2-library-or-runtime-plan.md) on 2026-11-15, after [a research panel](docs/plans/2026-11-15-storage-research-panel.md) on earlier work, and skipped the council. Experiment 15 ran the same day: Mo has one real service, the task queue, and it keeps a collection that grows with every call and never falls. Experiment 16 ran on 2026-11-16: one policy of 90 lines of Mo ran unchanged over a map and over files, and never looked inside a node.

**The idea it belongs to.** "The store is the heap", idea 6 in [the ideation of 2026-11-14](docs/ideation/2026-11-14-mo-database-ideation.html), against the library that `design.md` section 9 leaned to. The lean came before Robert decided that tables are part of the language.

**Sources.** The research panel of 2026-11-15: three models checked 31 claims about earlier work against pages fetched that day.

### The options

Application code is the same under all three, because tables are part of the language and the compiler plans every read. The options differ in where the code that touches the disk lives, and in what Mo gains.

| | Option | Where it stands after the research panel |
| --- | --- | --- |
| L | Library. The whole store is Mo code over bytes at a place in a file and a hash. A service must be allowed to hold a capability | The stores still in wide use are libraries: SQLite, LMDB, Mnesia, Irmin. One capability for every disk step is what simulation testing wants. A pure library was also criticised for putting too much on the programmer |
| R | Runtime ("the store is the heap"). Large `Map`, `Set` and `List` values live on disk as trees of nodes named by hash, freed by counts | Weakened. The runtime's layout becomes a format kept for ever: PJama struggled with class evolution and was stopped, and Motoko needed a compatibility check at every upgrade. Counts kept on disk are fragile in Btrfs |
| S | Split. The runtime gives collections whose copies share nodes, and reading and writing a node by name with a hash. The log, roots, holders, views kept current, history and erasure are Mo code on top | Strengthened. Earlier work split it this way more than once: "Bulk Types: Built-In or Add-On?" (1991), E, ANU-OPJ, Unison's storage abilities |

### What earlier work settled without an experiment

- Counts kept on disk are fragile, and a sweep from the roots is the common alternative. Experiment 17 models only the sweep.
- A sweep nobody runs costs space, so retention and collection are explicit policy under every option.
- Forgetting has to be designed in. Datomic Cloud still cannot excise data.

### What reading Mo settled (Q8), 2026-11-15

Read in `~/code/mo` by a search agent; Claude checked five of its citations against the source.

- **Lean treats collections as values with no layout.** "`map` is an association list in insertion order, with distinct keys" (`formal/MoCore/Value.lean:63`). A tree on disk under R or S changes no meaning in Lean.
- **Lean does not model services, crashes or durability.** "Simulation is not modeled by mocore" (`formal/MoCore/Prim.lean:806`). Files are modelled as whole text, a list of path and contents, with no bytes at a place and no forcing to disk. So the cover Lean would give a library store is its pure code, not its disk steps. That takes most of L's "the Lean model covers it" away.
- **Lean is not proved to match the C runtime.** "the C code is not proved" (`formal/README.md:338`). Agreement is checked by running the same programs on both and comparing outcomes.
- **Today the runtime keeps a service's state in SQLite:** one file, a whole snapshot every 100 messages and a log of the messages since, with `synchronous=EXTRA` (`src/host/store.c:205`). The runtime already owns the durable mechanism and leaves the policy (what a message is, when to snapshot) to the service loop. That is the shape of S on a small scale.
- **A `Map` is one hash table in one block,** copied whole when it has more than one holder (`src/heap/table.c`). Nothing lets a value live outside memory. R and S both need a new kind of value in the heap.
- **`mo test` crashes only between steps, on a store in memory** (reference section 12.5). Crashes inside a commit are tested by C tests that kill the process after a statement (`tests/test_service_store.c`) and by killing a real server at random. Under every option the store's crash testing needs more than `mo test` has.

### What the experiments must decide

Whether the store's policy can be ordinary Mo over a narrow set of node operations (S), whether L's capability can reach the store without spreading through every function, and how many Mo programs other than the database would gain. Robert also answers two questions: must any large value live on disk, or only tables (Q7), and must the stored format be independent of the runtime's layout and readable outside Mo (Q9).

### The experiments

The reading for Q8 is done and recorded above. The draft predictions below come from the plan. Each experiment gets its own section with final predictions before it runs.

| # | What is built or measured | The result that decides | Draft predictions | Control that must fail |
| --- | --- | --- | --- | --- |
| 15 | **Who else gains.** A script labels each Mo program in `~/code/mo/examples/`, `services/` and `learnability/` by whether its state holds a collection that grows | A large share that grows favours R or S; a small share favours L | 60% or more hold a growing collection, at 70%. Fewer than a third of those want history, at 55% | A planted service with an `Int` state must count as not gaining, and one with a growing `Map` as gaining |
| 16 | **The policy in Mo over two node operations, with two backends.** Log, roots, holders and freeing written once over `put` and `get`. Backend A is a `Map` standing in for the runtime (S); backend B is a file for each node through a capability (L) | A small policy with a narrow boundary favours S; a capability needed on every function down to the read counts against L | The policy passes over both backends, at 75%. Freeing needs a third operation that lists a node's children, at 65%. Under B every read function carries the capability, at 90% | Freeing a node without asking the holders must break a promise; backend B in a service's state must be refused by `mo check` |
| 17 | **Freeing by holders and a sweep, through a crash.** A TLA+ model: write nodes, force the log, switch the root, drop a holder, sweep, free, with a crash between any two steps | Safe with nothing stored beyond the roots and the log favours freeing in Mo policy | The sweep holds with nothing stored beyond the roots and the log, at 80%. A sweep during a write must pin that write's new nodes until its root lands, at 70% | Switching the root before the log is forced must break crash safety; a sweep that ignores a write not yet landed must free a node a kept version later reaches |

### Experiment 15 as it will be run, written 2026-11-15 before the run

Robert's test for anything Mo gains is that other programs would use it. Under R and S, every service whose state holds a collection that grows gains large state and cheap versions with no code change. Under L, only a program that takes up the store library gains. This counts how many Mo services hold such state, and how many of those also want what the store's policy gives, a history.

**What Claude has seen before writing this.** The names of the folders, the count of files that declare a `service` block in each (none in `examples/`, 1 in `services/`, 47 in `learnability/`), the first lines of each example, and the service block in reference section 11.5. No service's state type or handlers.

**The sample.** Every `.mo` file under `~/code/mo/examples/`, `~/code/mo/services/` and `~/code/mo/learnability/` that declares a top-level `service` block. Each is one service. The report also counts distinct services: two count as the same when their state type, after expanding the types declared in the file, and their tool names are the same. The examples have no service blocks. Five of them keep state as a value that a service would hold (`account`, `rate-limit`, `job-queue`, `kv`, `todo`); they are labelled the same way, by their central state type, and reported apart.

**The labels, all made by a script, `sketches/store-census/census.py`.**

- **Holds a collection:** the state type, with every `struct` and `enum` declared in the same file expanded, contains `List(`, `Map(` or `Set(`.
- **Grows:** it holds a collection, and some tool or timer handler named in the block contains `.append(`, `.push(`, `.add(`, `.insert(`, `.set(`, `.concat(`, `++` or `+ [`.
- **Wants history:** it grows, and a tool name or a field of the state type matches `history`, `log`, `audit`, `undo`, `event`, `ledger`, `journal`, `revision` or `version`.

Claude then reads ten services the script labels "grows" and five it labels "does not grow", chosen by a fixed seed, and reports how many labels he would change. The labels are not changed.

**What counts.** A large share is half or more; a small share is under a quarter.

- A large share that grows favours R or S: Mo's other services would use the runtime's pieces. A small share favours L.
- If a large share grows but few want history, the runtime's shared collection is useful on its own, without the store's policy. That favours S over R, which puts the policy in the runtime too.

**Predictions, Claude.**

1. At least 60% of the services hold a collection that grows: 70%.
2. Fewer than a third of those that grow want history: 55%.
3. Counted as distinct services, the share that grows is within 15 points of the share over all files: 70%.
4. Of the five example state cores, at least four hold a collection that grows: 75%.
5. Of the fifteen labels Claude reads, he would change at most three: 70%.

**Controls that must fail.** Three planted services in `sketches/store-census/controls/`: one with an `Int` state must come out not holding a collection; one whose `Map` is only read must come out holding a collection that does not grow; one with a `Map` that a tool adds to and a tool named `history` must come out growing and wanting history. If any comes out otherwise, the script is wrong and the run does not count.

**Limits known before the run.**

- The services in `learnability/` were written by agents for tasks Mo's team set. Their share says what those tasks asked for, not what Mo's users will write.
- "Grows" is read from text. A `Map.set` that only replaces an existing key would count as growing. The hand check measures how often that misleads.
- Types imported from another module are not expanded.
- It counts which programs would gain, not how much.

### Result of experiment 15, 2026-11-15

Run as committed in `51c0f2d`. The report is [sketches/store-census/results/report-15.txt](sketches/store-census/results/report-15.txt). A second run after the result, with two fixes, is in [report-15-siblings.txt](sketches/store-census/results/report-15-siblings.txt).

**Headline.** Mo's own code is too thin to count. The 48 files that declare a service are three programs: Mo's task queue, written 46 times in the learnability trials, and two small services from a preflight check. The one real service, the task queue, does what Robert's test asks about. Its state holds every job in a `Map(Int, Job)`, `submit` adds one each time, and its note to agents says "the limit of 5,000 counts every job ever submitted, including Done and Dead, and never falls". A payload "is kept for good". So Mo's only real service keeps its whole history and stops at a fixed size. Under R or S it would gain large state with no change to its code. Under L it would have to be rewritten onto the store library.

**What the script found, as run.** 1 of 48 services holds a collection that grows. That is the preflight service `grow`, whose state is `List(Text)`. The script did not expand `Queue`, which is declared in a sibling module, `job-queue.mo`; that limit was written before the run. The second run expanded types from sibling modules: 34 of 48 then hold a collection, but still only 1 grows, because the queue's handlers pass the work to `JobQueue.submit` in the other module and the text check looks only at the handler's own body.

**By hand.** Claude read the three distinct programs. The task queue grows: `after.jobs = after.jobs.set(id, Job(...))` in `job-queue.mo`. `grow` grows. The third, `clients`, holds an `Int`. Of the five example state cores, four hold a collection that grows: `job-queue` and `kv`, and also `todo` (`List(Item)`) and `rate-limit` (`buckets: Map(Text, Bucket)`, one bucket per client), which the script misread as `List` and `Decimal`. `account` holds a balance and no collection.

**Predictions.**

1. At least 60% of the services hold a collection that grows: failed as run, at 2%. By hand, 47 of the 48 files do, but they are two programs.
2. Fewer than a third of those that grow want history: held as run, at 0 of 1, which says nothing. By hand the task queue keeps every job for good, which is a history in all but name.
3. Counted as distinct services, the share that grows is within 15 points of the share over all files: failed. The script found 5 distinct services and 20% growing, against 2% over all files.
4. At least four of the five example state cores hold a collection that grows: failed as run, at 2 of 5, because the script misread two state types. By hand, 4 of 5.
5. Of the fifteen labels Claude reads, he would change at most three: failed. Only six could be drawn, one labelled "grows" and five "does not grow". Claude would change four of the six, every copy of the task queue.

**Controls.** All three planted services came out as planted.

**What it means.** Q1 cannot be settled by counting Mo's code: there is one real service. That service fits the case for R and S. It keeps a collection that grows with every call, never forgets, and stops at a fixed limit. Why the limit is 5,000 is not stated. Section 8 line 3 records that a service's state is saved whole on every write and stops at about 125,000 small rows. That this is the reason is inference. Claude's lean does not move: S at 65%, L at 20%, R at 15%. One program is too few to move it.

**What went wrong.**

- The text check for "grows" looks only inside the handler's own body. Every real service in the sample passes the work to another module, so the check missed all of them. The controls passed because each planted service does the work in its handler.
- Choosing a core's state type by the type of the first parameter cut `List(Item)` down to `List`, and picked `Decimal` for `rate-limit`.
- The second run fixed sibling types and the state-type cut. It did not fix the check for growth, and Claude stopped there rather than tune the script to the answer.

**What it does not show.**

- How many programs Mo's users will write with state that grows. Mo has no users' services to count.
- Whether the task queue's limit comes from the whole-state save.

### Experiment 16 as it will be run, written 2026-11-16 before the run

Under S the runtime gives a collection whose copies share nodes, and the store's policy is Mo code on top. Under L the same policy reaches its nodes through a capability. This writes the policy once and runs it over both, to see how much must cross the line between the two, and what the capability version asks that the other does not.

**What Claude has seen before writing this.** Mo's reference sections 5.5, 5.6, 9, 11, 12 and 14, and `sketches/kept-versions/tree.mo` and `by-number.mo`. No code for this experiment is written. Nothing has been run, not even to find out whether Mo accepts a capability as a type argument.

**What is built, in `sketches/store-policy/`.** All of it runs on the frozen `mo` at `build/enforcement-trial/mo`.

| File | What it is | Whose it would be |
| --- | --- | --- |
| `nodes.mo` | The collection: numbered rows in a tree of nodes named by number. Every write copies the path to the row and gives a new root, so an old root still reads the old rows. It reaches its nodes only through a record of functions, `Ops(S)`, where `S` is the type of the store | The runtime's under S and R; the library's under L |
| `policy.mo` | The policy, written once: the root being written, kept versions, holders, a log of calls, a sweep that frees what no held version reaches, and a replay of the log | Mo code under S and L; the runtime's under R |
| `backend-a.mo` | `S` is `Map(Int, Node)`. A service holds the map and the policy's state, with a step promise | Stands in for S |
| `backend-b.mo` | `S` is `Files`. One text file for each node, and the log in a file. Tested with `Files.in_memory` | Stands in for L |

The tree differs from `kept-versions/tree.mo` in two ways: its head moves out into the policy, and it never writes a node in place.

**The promises, under `mo test`.**

- No held version reaches a freed node. Under A this is a step promise in the service, so Mo checks it after every generated call, clock advance and crash. Under B it is checked after a fixed story of calls, and on generated lists of calls if Mo can build them.
- Replaying the calls gives the same state. Under A this is Mo's own recovery check on the service. Under B the test forgets the policy's state, keeps the files, replays the log file over them, and compares.
- The same story of calls gives the same answers over A and over B.

**What is counted, by `count.py`.**

- Lines of code in each file: lines that are not blank, not a comment and not inside a `test`.
- The boundary: every name `policy.mo` calls from `nodes.mo`, and every field of `Ops` that either file calls.
- How many of the policy's functions match on a node's cases, which is the policy opening a node.
- Lines that only backend B needs and backend A has no counterpart for.

**What counts.**

- **Favours S:** one policy file serves both backends; the policy calls at most five names across the boundary; it opens a node in at most one function; its code is 150 lines or fewer.
- **Favours R:** the policy's code is under 40 lines, or more than half of its functions do nothing but pass their arguments to `nodes.mo`. Then so little is left in Mo that it may as well sit in the runtime.
- **Favours L:** more than half of the policy's functions open a node, so the line between policy and collection is not a real one; and B needs no more code than A.
- **Counts against L:** B cannot sit in a service, and B needs code of its own to keep its log and to recover.

**Predictions, Claude.**

1. `nodes.mo` and `policy.mo` serve both backends unchanged, with the store as a type parameter: 60%. The doubt is whether Mo takes a capability as a type argument, or a record of functions that take one.
2. Over A, in a service, Mo's recovery check passes and so does the step promise: 80%.
3. Over B, the story gives the same answers as over A, and replaying the log file over the surviving files gives the same state: 70%.
4. The policy calls exactly four things across the boundary: read a row at a root, write a row, list a node's children, and remove a node. It never calls the bare `get` or `put`: 60%. The draft prediction, that freeing needs an operation that lists a node's children, stays at 65%.
5. The policy opens a node in no function of its own; `children` in `nodes.mo` does it: 70%.
6. The policy's code is between 60 and 120 lines: 60%.
7. Backend B needs at least 40 lines that A has no counterpart for: turning a node and a call to text and back, the log file, and recovery: 70%.
8. Every function in `nodes.mo` and `policy.mo` that reads or writes a node takes the store as a parameter, over both backends alike: 95%. This is close to given by reference section 11.1. What differs is that under A the parameter is a value a service can hold, and under B it is a capability a service cannot.

**Controls that must fail.**

- **Freeing without asking the holders.** With the sweep changed to start from the root being written only, the step promise over A must fail, and the story over B must fail. `control.py` makes the change in a copy under `build/` and runs it.
- **Backend B in a service.** `control-b-service.mo`, a service whose state holds a `Files`, must be refused by `mo check`.

**Limits known before the run.**

- **Backend A is a `Map` in a service's state,** which Mo saves whole. It shows the shape of the boundary and not the cost. Nothing here pages a node to disk.
- **Nodes are named by number,** because Mo has no hash. The sweep walks the numbers from 1 to the next unused one. With names by hash it would need the runtime to list the names, which would be one more operation.
- **The fake files tear nothing.** A crash falls between calls, never inside a write. Experiment 17 covers the steps inside a write.
- **One writer.** No worlds, no views kept current, no erasure.
- **A read that fails.** `Files.read_text` gives a `Result`; a `Map` gives an `Option`. To write the policy once, B's `get` turns any error but "not found" into a `stop`. So this cannot show a policy that handles a failed read.
- **Lines of Mo are a coarse measure,** and the thresholds above are Claude's.
- **Claude writes both sides and leans to S.** The counts and the controls are the guard, and the hand judgement in "favours R" is the weakest part.

### Result of experiment 16, 2026-11-16

The Mo files were committed in `f2ffc51` before any run. Mo refused one line of the first draft, a trailing `if` after `+=`; the fix and the two scripts are in `2a57aa5`, and the run below is of that commit. The reports are in [sketches/store-policy/results/](sketches/store-policy/results/).

**What ran.** `mo test` on `backend-b.mo`, which also runs backend A: 7 passed, 0 failed, 0 stopped.

| Check | Backend | Result |
| --- | --- | --- |
| The story: held rows stay, and the sweep frees 6 of 16 nodes | A | passed |
| Replaying the log from an empty map gives the same state | A | passed |
| Step promise, no held version reaches a freed node, on Mo's generated sequences | A, in a service | passed |
| Mo's recovery check | A, in a service | passed |
| The story gives the same answers as over A | B | passed |
| Replaying the log file over the surviving files gives the same state | B | passed |
| No held version reaches a freed node, on generated lists of calls | B | passed |

**What was counted.**

| | Lines of code |
| --- | --- |
| `nodes.mo`, the collection | 56 |
| `policy.mo`, the policy | 90 |
| `backend-a.mo`, with its service | 56 |
| `backend-b.mo` | 88 |

- **The boundary.** The policy calls three names from `nodes.mo`, `read`, `write` and `children`, and one function through `Ops`, `remove`. It never calls `get` or `put`; only `nodes.mo` does.
- **Opening a node.** None of the policy's 9 functions matches on a node's cases.
- **Passing on.** One of the 9, `get`, only passes its arguments to `nodes.mo`.
- **Taking the store.** All 9 take the store as a parameter, over both backends.
- **Only B needs.** 51 lines in six functions. 38 turn a node and a call to text and back. 13 are `commit`, which writes the log file before it applies a call, and `recover`.
- **Both need.** The three node functions and the record that holds them: 12 lines over A, 22 over B, where each must turn a file error into a `stop`.

**The controls failed as they must.**

- **A sweep that ignores the holders:** 3 passed, 4 failed. Mo found the shortest case on its own, over both backends: put, hold, put, sweep. The test that only compares A with B still passed, because both were wrong alike.
- **Backend B in a service:** `mo check` refused it with E0104, "a service value holds a capability or function".

**Predictions.**

| # | Prediction | Result |
| --- | --- | --- |
| 1 | One policy serves both backends, with the store as a type parameter, 60% | Held. Mo takes `Files` as a type argument, and a record of functions that take it |
| 2 | Over A, the recovery check and the step promise pass, 80% | Held |
| 3 | Over B, the same answers, and the log replays to the same state, 70% | Held |
| 4 | The policy calls exactly four things across the boundary and never the bare `get` or `put`, 60% | Held |
| 5 | The policy opens a node in no function, 70% | Held |
| 6 | The policy is between 60 and 120 lines, 60% | Held, at 90 |
| 7 | B needs at least 40 lines that A does not, 70% | Held, at 51 |
| 8 | Every function that reads or writes a node takes the store, 95% | Held |

**How much that is worth.** Less than eight out of eight sounds. Predictions 4 to 8 are about code Claude then wrote, so they test little. The ones that could have gone wrong are 1, 2 and 3, and the controls.

**What went wrong, and what was decided after the predictions.**

- **`children` gives `None` for a node that is not there.** Claude chose this while writing the code. It lets the promise's check ride on `children`. Had `children` given an empty list, the check would have needed a fifth name, and prediction 4 would have failed.
- **Under A the policy's log does no work.** Mo's recovery check replays the service's own messages and never calls `Policy.replay`. Only B recovers through the policy's log. So on today's Mo, S needs no log in the policy at all; the service already keeps one. This is inference from one sketch.
- **38 of B's 51 extra lines come from today's Mo,** which has no way to turn a value to bytes and back. They are not a cost of L itself. What L itself asks here is the 13 lines of `commit` and `recover`, which is also where an error would lose data.

**What it shows.**

- **The split holds in Mo code.** A policy of 90 lines keeps roots, holders and a log, and frees by a sweep, without ever looking inside a node. Every condition written under "favours S" was met.
- **The policy is not thin.** It is 90 lines, and one function of nine only passes its arguments on. Both conditions under "favours R" failed.
- **The capability threads through cleanly.** The same two files run over `Files` with no change. So L's policy is no harder to write than S's. What was written beforehand as "favours L" still failed: no policy function opens a node, and B needs more code than A.
- **What L asks that S does not:** a change to reference section 11.5 so a service may hold a capability, which the option already says; its own log file and its own recovery; and a `stop` for a file error in every node function.
- **What crosses the line under S is not what the option says.** The option names "reading and writing a node by name". The policy used neither. It used the collection (`read` at a root, `write` giving a new root), a node's `children`, and `remove`.

**What it does not show.**

- Whether a function value that captures the store is refused over B. The policy uses loops, so it was never tried.
- A sweep done by the runtime from a list of roots, which would replace `children` and `remove` with one operation.
- Anything about cost. Backend A is a `Map` saved whole.
- A crash inside a write, names by hash, or more than one writer.

### Where Claude stands, with what would move it

- **S at 70%, L at 18%, R at 12%.** After experiment 16: the split held in Mo code, and the policy was not thin. The move is small because Claude wrote both sides. After the reading of Mo: 65%, 20% and 15%. After the research panel: 60%, 25% and 15%. Before it: 50%, 20% and 30%.
- **Toward R:** Robert answers Q7 "any value" and Q9 "no".
- **Toward L:** Robert answers Q9 "yes, and the format must be the library's own"; experiment 17 shows the sweep needs help the runtime cannot give.
- **Toward S:** experiment 17 shows the sweep needs only a list of a node's children from the runtime.

## Decisions waiting for options and experiments

These came out of the same ideation. None has an experiment designed.

- **Does the log run unbroken through an upgrade?** Idea 2. Today an upgrade deletes the log's tail.
- **Are nodes named by hash or by number?** `design.md` section 9. Decision 2 bears on it: erasing a person by destroying their key means their values no longer share nodes with anyone else's.
- **May a write function open a held value?** Idea 3. If it may, replay after an erasure gives a different state.
