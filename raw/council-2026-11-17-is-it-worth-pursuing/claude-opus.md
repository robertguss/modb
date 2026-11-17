**Verdict: keep going, but change it. Stop designing MoDB on paper. Build section 8, line 3, inside Mo now, using the live task queue as its first real user. Confidence: 70%.**

## Why

1. **The project has already produced what its purpose asked for.** You said MoDB exists to drive what Mo gains next. Section 8 of `design.md` is that list: 15 abilities, each one something other programs would use too. More design will not improve the list. Building one line of it will test it.
2. **Your stated purpose cannot be met on paper.** The purpose is to design a language alongside a demanding project. The learning comes from the friction of building, and nothing has been built. The sketches add up to about 3,750 lines of Mo. All of them are throwaway, and they ran under a rule that Mo must not change.
3. **The decisions are now stacked on things nobody has built.** Decision 3 (the record of calls can be run again through upgrades) rests on a record nobody has built. Decision 4 (erasing one person from a kept record) rests on Decision 3. It is about personal data in a system that holds no data and has no user.
4. **I challenge one part of your rules.** You said the cost of building is not a limit, and I accept that. But your attention is a limit, and you never exempted it. Every decision here needs you. `experiments.md` is 1,550 lines, and you have not accepted `design.md` as a whole. Inference: some of your doubt may be that the paper is growing faster than you can take it in.
5. **The real user both outside reviews asked for now exists, but in the Mo repo.** Since 2026-11-16 the task queue runs live behind the review door, and agents use it for real work (`~/code/mo/docs/ops/live-service.md`). Experiment 15 found its job map "never falls" and is capped at 5,000 jobs. Line 3 says a service re-saves its whole state on every write, and writes stop at about 125,000 rows. So line 3 is not a database fantasy. It is the first wall your one real service will hit. That the cap exists because of this is the file's inference, not a measured fact.

## What the four days produced

**Has value:**
- Section 8 of `design.md`. This is the main output.
- The measurements of Mo today:
  - Ticket 11: a write costs 17 ms plus 0.66 ms per 1,000 rows, and writes stop at about 125,000 rows.
  - The 1,048,576-instruction limit on a call, and the rule that fifteen refused calls stop a service.
  - About 10 ms of every call spent in the HTTP layer.
  - A map inside a record is copied every time it changes.

  These are real Mo gaps whatever happens to MoDB.
- Ticket 37: a tree of shared nodes kept a version for 778 bytes.
- Experiments 8–14: the read classes, tested against 23,877 answers from real Mo with none different. This is a real result, though it ran in a Python script beside the compiler, not in Mo.
- Experiments 18–19: running the record again through upgrades.
- The habit of writing predictions before a run and planting a control that must fail. That is good method.

**Little value:**
- Most of the roughly 130 wiki pages. An agent can regenerate a literature survey on demand.
- Tickets 22 and 26–28 (FERPA, Veil, Bend2, the survey of specification languages). These were side trips.
- Decision 4 and the hash-or-number question, both premature.
- The repeated reframing: the map stopped, the slices stopped, the framework idea came and was deferred. Three changes of direction in four days.

## The strongest case against my verdict

Mo's roadmap says Phase 6 (intent and the review door) is now in progress, and its review door already guards the live queue. Pulling in disk-backed state now splits your attention across two big runtime changes in a C VM. Phase 7 ("Fast") is where storage naturally belongs. And the paper has a real use: decisions like "the store is part of the runtime" are cheap to change on paper and costly to change in a C runtime holding live data. Data outlives code, as Claude itself argued in Decision 2. So finish the design, then build once.

My answer: the design is already ahead of anything that could test it. A wrong first build of line 3 costs one rewrite. Another month of paper costs a month.

## The cheapest test for the next week

1. Spend 30 minutes and mark which of the 15 lines you would want in Mo even if MoDB never existed.
2. Have an agent build the smallest form of line 3 on a Mo branch: a `Map` in a service's state on disk, where a write saves only the nodes it touched. Measure the task queue's write time at 1,000 and 100,000 jobs.

- **Yes:** you mark at least 3 lines, the write cost stays roughly flat, and you want the next line.
- **No:** you mark none (the database was the point, not Mo, so first answer "what data goes in first"), or after the week you would still rather be drafting decisions than reviewing runtime code.

## If you stop

**Carry into Mo:**
- Section 8 as a list for Phase 7.
- The measurements in tickets 11, 37 and 39, and experiment 19.
- The read-class rule and its planner experiment, as a future Mo design note.
- The three TLA+ models in `models/`.
- The habit of predictions plus a control that must fail.

**Leave:** the wiki, layers 5 and 6 of the design, Decision 4, and the FERPA and security research.

## One question for you

"If Mo gained lines 3, 4 and 6 and you never built a database on them, would you feel the project had succeeded?"

- If yes: MoDB was the reason to find those lines, and its job is done.
- If no: the database itself is what you want, and the never-answered ticket 12 ("what real data of yours goes in first?") must be answered before any more design.

---

**What I checked against the files:**
- The commit count per day (16, 62, 41 and 30, which make 149).
- Sections 7–9 of `design.md`.
- The status of Decisions 2–4.
- Experiment 15's result.
- `map.md` Notes and the stop.
- Issue 15's Comments.
- Mo's `README.md`, `docs/ROADMAP.md`, `docs/ops/live-service.md` and recent commits.

I did not check the planner's figures or the wiki pages one by one. I ran no code and did no web search.
