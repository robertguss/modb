# Council review, 2026-11-17: is the project still worth pursuing?

Sources for the question Robert put on 2026-11-17: "I am not sure how worthwhile this project really is anymore. Ask the council to help me decide if this is worth pursuing still." He gave no reason for the doubt. Never edited.

- `claude-opus.md`, `gpt-sol.md`, `gemini-carbon.md`: the three reviews as delivered, each written alone from the same brief. The only change is that the home folder was cut from file paths, so a bare path is this repository and `~/code/mo` is Mo.

One round was run. The reviewers were Claude Opus 5.5, GPT-6.1 Sol and Gemini 4 Carbon, each at high reasoning effort, each working read-only. They read the repository at commit `b03c8c3`. Line numbers are those of that commit.

**The brief** gave the purpose of the effort as recorded in `map.md` under Notes, where the work stood after four days, and the two outside reviews of 2026-11-14. It held no opinion of the chair's. It asked for a verdict out of four (keep going as it is, keep going but change it, pause, stop) with a confidence, the reasons, what the four days produced, the strongest case against the verdict, the cheapest test for the next week, what to keep on stopping, and one question for Robert.

**The verdicts.** Claude Opus: keep going but change it, at 70%. GPT Sol: keep going but change it, at 80%. Gemini Carbon: stop, at 75%.

**Facts the chair checked in the files, all of which held:**

- Mo's task queue has served live since 2026-11-16, with a minimum of 14 days of running, and four of its eight access checks are not yet run (`~/code/mo/docs/ops/live-service.md`).
- The task queue keeps every job and stops at 5,000; that the limit comes from the whole-state save is inference (`experiments.md`, result of experiment 15).
- The sketches hold 3,750 lines of Mo.
- A kept version cost 778 bytes (`issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md`).
- 9 of 32 settings in experiment 17 differed from the predictions.
- Taking ten calls out changed the reply to 15 of the other 20 (experiment 18).
- Experiment 16 met every condition written under "favours S", and Robert then chose R (`experiments.md`, "How it was decided" under Decision 2).
- Today's Mo at 50,000 rows needs 58 hours for a million calls (experiment 19).
- The runtime is about 38,800 lines of C (`issues/24-how-does-mos-runtime-become-memory-safe.md`).

Not checked by the chair: the counts in `models/README.md` that Gemini Carbon cites, and the tickets Claude Opus calls side trips.
