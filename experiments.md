# Open decisions, their options, and the experiments that would settle them

Robert's rule of 2026-11-14: "keep a list of some options and then do small tests and spikes and experiments so that all decisions are based in reality and data."

How this file works:

- A decision stays open here with every option still standing, until an experiment or Robert closes it.
- An experiment is small: a Mo program under `sketches/`, a script that stands in for a compiler pass, a measurement of agents writing code, or a model under `models/`.
- Every experiment has its prediction written here before it runs, and a control that must fail.
- A result is written under the experiment with the date and a link to what was run. A prediction is never edited after its result is in.

## Decision 1. How is a fast read enforced?

**Status:** open. No experiment has run.

**The idea it belongs to.** "Plain Mo is the query language", idea 1 in [the ideation of 2026-11-14](docs/ideation/2026-11-14-mo-database-ideation.html): the compiler turns certain shapes of ordinary collection code into index lookups. Robert agreed on 2026-11-14 to try it with no new query syntax, and asked how the fast shapes are enforced.

**Sources.** [The council of 2026-11-14](raw/council-2026-11-14-enforcing-fast-questions/README.md): three reviewers, one brief, and what each review contains as judged by TypeSafe's Jev.

### The options

| | Option | Where it stands after the council |
| --- | --- | --- |
| A | Strict. A filter on a stored table with no fast route is a compile error unless the code says `walk` | Chosen by all three reviewers for the program's own code. All three also say it can turn ordinary Mo into a hidden query language |
| B | Warn only | Ruled out. Mo has no warnings: "a problem is an error, or it isn't reported" |
| C | Demand. A `fast` marker makes the compiler refuse a function it cannot make fast | No reviewer chose it for the program's own code, because an unmarked function still walks unnoticed. GPT Sol makes it mandatory for a read program an agent sends |
| D | Measure. `mo test` compares instruction counts at two store sizes | Doubted by all three. A primitive that goes over a whole collection may count as one instruction, and an indexed read with a growing answer looks like a walk. Experiment 5 |
| E | A closed form. The table has a fixed set of methods that take a field and a value | Nobody's first choice. All three name it as the fallback if recognising shapes is brittle |
| F | The review door holds an upgrade that makes a read slower, by ranked cost class | Gemini Carbon chose it, with A. The other two did not |
| G | The type enforces it. A stored `Table` is not a `List`: it has `get`, the index methods and one `walk`, so a slow read can only be written as `walk`. Recognising shapes is then a convenience, not a gate | Added by Claude Opus. Close to E plus A |
| H | An access-plan report: every table access, the index it needs, whether that index is ready, every walk | Added by GPT Sol. It goes with any other option |

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

Experiments 1, 3, 5, 6 and 7 need nothing but Mo as it stands and a script. Experiments 2 and 4 need agent sessions, which cost money.

### Where Claude stands, with what would move it

- **Strict in some form, for the program's own code: 85%.** All three reviewers chose it and Mo has no warnings.
- **Strict by recognising plain Mo, against a table type with its own methods: about even.** Before the council Claude gave this 80% for plain Mo. The `for`-loop count and the order problem brought it down. Experiments 1, 2 and 3 move it.
- **The growth test as a check: 15% that it works as first described.** Experiment 5 settles it.

## Decisions waiting for options and experiments

These came out of the same ideation. None has an experiment designed.

- **Does the log run unbroken through an upgrade?** Idea 2. Today an upgrade deletes the log's tail.
- **Is the store a library written in Mo or part of the runtime?** Idea 6, and `design.md` section 9.
- **Are nodes named by hash or by number?** `design.md` section 9.
- **May a write function open a held value?** Idea 3. If it may, replay after an erasure gives a different state.
