# Decision 3: does the log of calls run unbroken through a snapshot and an upgrade?

Created: 2026-11-16

A plan for research and a decision. It builds nothing. It follows the shape of [the plan for Decision 2](2026-11-15-2037-decision-2-library-or-runtime-plan.md).

## 1. The question

`design.md` says the log is the truth: audit is reading it, undoing a caller's work is running it again without that caller's calls, and the tree of nodes can be rebuilt from it. Mo's log today does none of that. It is a tail kept for recovery after a crash. A snapshot deletes it, and so does an upgrade.

Two things now rest on the answer:

- **The stored format (Q9 of Decision 2).** Robert put it off on 2026-11-16. The store is in the runtime, so the runtime's layout is the format on disk. If the whole state can be rebuilt from the log, that layout is free to change. If it cannot, something else must carry the data across a change of layout.
- **Section 8 line 9 of `design.md`,** "keep a log the program owns", and need 7 of the data store, "keep the log of calls for good".

Since Decision 2, a snapshot is cheap: it is a root. So the question is no longer how to afford snapshots. It is whether the calls are kept after one, and what can be done with them.

## 2. The options

Each option holds everything in the one above it.

| | Option | What it gives | What it asks |
| --- | --- | --- | --- |
| A | **A tail only,** as today. Calls are kept back to the last snapshot and no further | Recovery after a crash | Nothing new. History is whatever old values the program keeps |
| B | **A record that is read, not run.** Every committed call is kept for good, through snapshots and upgrades: the function's name, its arguments, the caller, the time, the code it ran under, and the root after | Audit. "Who changed this, and when" | Room for the record to grow. An entry that names its function and its caller, which today's does not |
| C | **A record that can be run back to the last upgrade.** Within one version of the program the calls can be run again from that version's first state. Older versions' calls are a record only | B, and taking one caller's work out, and checking the state against the record, back to the last upgrade | B, and the first state of each version kept |
| D | **A record that can be run from the first call.** Every call can be run again with the code that ran it, and every upgrade's function from old state to new is run again in its place | C through every upgrade. The whole state can be rebuilt from nothing, so the format on disk is free | C, and every past version of the code kept and runnable for ever, and every later runtime giving the same result for an old call |

**Two ways to free the stored format,** which the options do not settle alone:

- **Rebuild from the record.** Only D gives this.
- **Write the whole state out in a form that does not depend on the layout, and read it back.** Mo already has such a form, MOSV, and it is how a snapshot is saved today. This works under A, B and C.

## 3. What is already settled

### Decided by Robert

- The data store is part of Mo's runtime (2026-11-16, Decision 2).
- Any `Map`, `Set` or `List` in a service's state can live on disk. A version is kept while a value still refers to it (2026-11-16).
- Nodes nothing refers to are freed by a sweep (2026-11-16).
- The stored format is not decided now. Stored data carries a format version number. This decision is what brings the question back (2026-11-16).
- A world lands whole or not at all, and at landing every question the agent asked counts (`design.md` section 7).
- Not a limit: today's Mo, the cost of building, or how easy it is to learn.

### What reading Mo settled, 2026-11-16

Read in `~/code/mo` by a search agent. Claude checked five of its citations against the source: the two deletes, the three limits, the fields of a log row, the code check at replay, and the schema check at decoding.

- **A snapshot is taken every 100 logged calls and deletes every log row in the same step** (`src/base/limits.h:365`, `src/host/store.c:471-476`). One snapshot is kept.
- **A log row holds little.** The handler's number, not its name; the arrival time; the arguments; a checksum of the state the call produced; and a hash of the compiled program (`src/base/log-record.h:6-28`). It holds no caller and no state before.
- **Calls that only read are not logged.** A call that returns an error is not logged either.
- **Recovery runs the handlers again** on the logged arguments and compares the checksum. A row written under a different compiled program is refused (`src/vm/service.c:298`).
- **An upgrade runs the tail under the old code, turns the old state into the new with one function, saves a snapshot and deletes the log** (`src/host/store-programs.c:304-312`). A changed state type with no such function is refused.
- **Mo keeps a record of each upgrade for good:** the old and new source hashes, the old and new types, and the name of the function used (`store-programs.c:18-21`). It keeps the two snapshots before the last two upgrades, up to 32 MiB.
- **Saved values carry their own description.** MOSV writes the type's names and field names before the value, and decoding refuses bytes whose description differs from the current type (`src/heap/saved.c:439-442`, `:552`). So old bytes can always be read for what they are, and never silently read as something else.
- **There is no limit on the log's size,** because it never holds more than 100 rows.
- **Mo's own plan says not to keep old rows in this log:** "never retain pre-snapshot rows in the recovery log, whose readers expect a post-snapshot tail", and history "requires ... a separate compatible archive if selected" (`docs/plans/2026-11-03-1704-feat-phase4-see-inside-plan.md:154`).

What follows from the reading:

- **The recovery tail and a kept record are two things.** Mo's team already expects a separate archive. Options B, C and D are about that archive. The tail can stay as it is.
- **Option B is closer than it looked.** The arguments can already be read without the old types, and the upgrades are already recorded. What is missing is the function's name, the caller, and keeping the rows.
- **The code a row ran under is named by a hash of the compiled program.** A new compiler would give the same source a new hash. An entry that is to be run years later needs a name for its code that a new compiler does not change. `design.md` already says "the hash of its checked form". This is inference; nothing was run.

### What earlier work settles

From the wiki and the research panel of 2026-11-15.

- **Old entry formats live for ever.** Stores that keep events translate old ones each time they are read ([storing events instead of state](../../wiki/ideas/storing-events-instead-of-state.md)).
- **Running a log again needs calls that repeat exactly.** Mo has this: a handler holds no capability and gets the time as an argument.
- **Surviving a crash is not surviving an upgrade.** The E language's paper on persistence says so in those words (panel, prior work).
- **Erasing collides with a kept record.** Datomic's excision is slow and lossy, and Datomic Cloud has none ([deleting personal data from history](../../wiki/ideas/deleting-personal-data-from-history.md); panel rows 20 and 22).

### What the research panel of 2026-11-16 added

Step 3 of section 6 was run. [The record](2026-11-16-log-replay-research-panel.md) has 25 claims, each with a quote from a page fetched that day. Three were outdated in part and two were refuted in part; none of the five changes what follows.

- **Nobody runs a kept log through freely changed code.** Engines that replay across a code change keep the old code alive: both paths in the code behind a marker, or each run held on the build that started it (rows 1, 2, 3, 7, 8). Option D is the second way.
- **They keep old code only until its runs are finished.** D asks for it for good. The one system that does that is Ethereum, and its clients have begun to drop old history so they can stop (rows 2, 23, 24).
- **A log run again for recovery is a tail everywhere** (rows 4, 9, 19, 20, 21). Temporal now previews starting a fresh history at an upgrade, which is the shape of option C. An upgrade by a function from old state to new, with no replay, is the common way (rows 9, 10, 11). Both are what Mo does today.
- **Records kept whole hold what was decided. Logs of calls are kept only to the next snapshot** (rows 12, 14, 16 against 15, 20, 21). Mo's log holds calls. Inference: an entry could also hold what its call changed. A record of changes can be read and rebuilt from with no old code. Taking a caller's work out still needs the calls.
- **There is a use Q1 does not list: running old calls through corrected code on purpose,** so that a fixed bug also puts the state right (Fowler 2005, under row 16). It is the opposite of D, which wants the same result as before. It is the same kind of run as taking a caller's work out: the calls are run again and the result is meant to differ.

## 4. The questions that decide

| # | Question | Points to A or B if | Points to C or D if | Settled by |
| --- | --- | --- | --- | --- |
| Q1 | What must the record be able to do: be read, give back one caller's work, rebuild everything? Since the panel, also: put the state right after a bug is fixed | Being read is enough | Taking a caller's work out, or rebuilding, is wanted | Robert, one question (section 6, step 4) |
| Q2 | Can a record be run across an upgrade, and what must be kept for it? | It needs more than the code of each version and the upgrade functions | Those are enough, and they can sit together in one program | Experiment 18 |
| Q3 | What does keeping every call cost, in bytes and in time to run it all again? | Running a real history again takes hours | It takes minutes, and a row is small beside the state | Experiment 19 |
| Q4 | Does a later runtime give the same result for an old call? | It cannot be promised | It can, or a difference is always caught | Argument. Mo Core is defined in Lean, so the meaning is fixed. A fixed bug still changes a result. Each row's checksum catches that, and the rule for what happens then is part of D. Claude holds "always caught" at 80% |
| Q5 | Can a person's data be erased from a kept record? | Erasing must leave no trace and still allow a rebuild | A hole in the record is acceptable, and running starts again from a kept state after it | Argument, and the waiting decision "May a write function open a held value?". A hole means D cannot be absolute. Not settled here |
| Q6 | What frees the stored format: a rebuild from the record, or writing the state out and reading it back? | Writing out and reading back is enough | Only a rebuild will do | Argument, after Q3. A rebuild costs the time of every call ever made. Writing out costs one pass over the state. Robert, after the experiments |

## 5. The experiments

House rule for each: predictions with a confidence are written in `experiments.md` and committed before any run, and are never edited after. Code is committed before the full run. The result goes in a dated "Result of experiment N" section. The predictions below are Claude's drafts.

All runs use the frozen Mo binary at `build/enforcement-trial/mo`. None writes to `~/code/mo`.

| # | What it tests | How | Result that points which way | Draft prediction | Control that must fail | Cost | What the decision loses if cut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 18 | **Running a record across an upgrade (Q2).** What must be kept so that calls made under three versions of a program give the same state when run again | A small service in three versions in `sketches/log-through-upgrade/`. Version 2 changes what one handler does. Version 3 changes the shape of the state, with a function from old to new. A record of calls, each marked with its version. A rebuild runs each call with its own version's code and runs the upgrade functions in their places. The comparison is a real service upgraded with the frozen `mo`, if its upgrade commands work in a folder under `build/`; if they do not, the comparison is a state worked out by hand, and the result says so | A rebuild that needs only each version's code and the upgrade functions points to D being possible. Anything more is listed, and each item is something Mo would have to keep | The rebuild gives the same state, at 75%. Three versions of one module cannot sit in one program under one name, so each must be renamed, at 85%. The old types must be kept as well as the old code, at 80% | Running every call with the newest code must give a different state. Leaving out an upgrade function must fail to compile or give a different state | Half a day | Option D stays a sentence in `design.md`, and nobody knows what "code kept by hash" asks of Mo |
| 19 | **What a kept record costs (Q3).** Bytes for each call, and time to run each call again | Measure Mo's own store with the harness in `sketches/service-timing/`. Send updating calls to the plain map service used there. Read the bytes of the log rows just before a snapshot, and the time recovery takes for a tail of 99 rows. Work out bytes and seconds for a million calls, beside the size of the state those calls built | Hours to run a million calls again points away from D as the way to change the stored format, and toward writing the state out. Minutes leaves D open | A row for a call with small arguments is under 200 bytes, at 70%. Running a million calls again takes under five minutes, at 55% | A call that only reads must add no bytes. A call that returns an error must add none | 2 to 3 hours | Q6 is answered by guessing at the cost of a rebuild |

**Not experiments.** Q4 and Q5 are argued in section 4. Q1 and Q6 are Robert's.

## 6. Order, and where Robert decides

1. **Robert accepts, changes or cuts this plan.**
2. Write "Decision 3" in `experiments.md` in the shape of Decision 2. Move its line out of "Decisions waiting". Commit.
3. **Optional research panel. Robert accepts or skips.** Robert accepted on 2026-11-16 and it was run; see section 3. Claims about earlier work on running a history again after the code changed: how workflow engines version code that is replayed, how stores that keep events read old ones, how other durable runtimes upgrade a running program, and what stores that keep a log as the truth do at a change of format. Claude recommends accepting, at 60%. Everything Claude knows about these is from memory and unchecked, and the panel on Decision 2 refuted two of 31 such claims, one of them in part. The reason to skip is cost, and that experiment 18 tests the central point directly.
4. **Robert answers Q1:** what must the record be able to do. This comes before the experiments because "being read is enough" makes experiment 18 unnecessary.
5. Experiment 19, then 18. Predictions are committed before each. Cheapest first.
6. **Robert decides between A, B, C and D.** Claude gives a recommendation and a confidence then.
7. **Q9 of Decision 2 comes back, as Q6 here:** is the stored format freed by a rebuild, by writing the state out, or not at all for now. Robert decides.
8. Bring `design.md` section 4, section 8 line 9 and section 9 into line. Commit.

Robert can stop after any step. Each experiment stands alone.

## 7. Where Claude stands

These rest on the reading and on argument. Nothing has been measured.

| Option | Confidence | Why |
| --- | --- | --- |
| C | 40% | It gives audit, and taking a caller's work out, within one version of the program. That is where an agent's mistake is most likely to be found and undone. It asks nothing of old code |
| B | 30% | It is nearly there in Mo today, and it is enough if the record only has to be read |
| D | 20% | It is what `design.md` describes. But it asks every later runtime to run every old version of the code and get the same answer, and one erased entry breaks it |
| A | 10% | It throws the calls away |

- **Throwing data away is the one choice here that cannot be undone.** A record kept can be deleted later. A record not kept cannot be got back. So by Robert's own test, B is safer than A whatever else is decided.
- **How far back the record can be run can be decided later,** if each entry holds enough from the start: the function's name, the arguments, the caller, the time, a name for the code that a new compiler does not change, and the root after. So the part that has to be right first is what an entry holds.
- **The stored format is probably freed by writing the state out, not by a rebuild.** That is a guess until experiment 19 says what a rebuild costs.

What would move it:

- **Toward D:** experiment 18 needs only the code of each version and the upgrade functions; experiment 19 shows a rebuild takes minutes; Robert wants taking a caller's work out to reach across upgrades.
- **Toward B:** Robert answers Q1 with "being read is enough".
- **Toward A:** nothing found so far.

**After the panel, 2026-11-16: C 40%, B 35%, D 15%, A 10%.** D went down because the engines that do what D does drop old code when its runs end, and the one system that keeps it for good is moving away. B went up because a record kept to be read is the well-worn way. Still nothing measured.

## 8. What was cut and why

| Cut | Why |
| --- | --- |
| Reads in the record | Section 8 line 9 asks for them, for the layer's "asked again at landing". That is about what an entry holds, not whether entries are kept. It follows this decision |
| An experiment on erasing from the record | It belongs to the waiting decision "May a write function open a held value?". Section 4 argues only that a hole means D cannot be absolute |
| A model of a crash while the record is written | Experiment 17 modelled recovery from a snapshot and a tail. The record is added to at the same point as the tail |
| Recording under one build of `mo` and recovering under another | It would show that a new compiler changes the hash a row carries. It needs a second build of Mo, and the reading already shows how the hash is made |
| Names by hash or by number | A separate waiting decision |

## Not verified while writing this plan

- Whether the frozen `mo` can upgrade a service in a folder under `build/`. Experiment 18 finds out, and says how its comparison was made.
- Whether the harness in `sketches/service-timing/` can read the log's bytes before a snapshot. Experiment 19 finds out.
- `src/tools/recovery.c`, `upgrade-live.c` and `store-history.c` were not read in full by the search agent.
- What the panel left open, listed under "Not settled" in [its record](2026-11-16-log-replay-research-panel.md).
