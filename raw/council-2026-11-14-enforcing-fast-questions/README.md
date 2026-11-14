# Council review, 2026-11-14: enforcing fast questions

Sources for decision 1 in [experiments.md](../../experiments.md). Never edited.

- `brief.md`: the brief each reviewer was given, the same for all three. It lists six options and does not say which Claude preferred.
- `gpt-sol.md`, `claude-opus.md`, `gemini-carbon.md`: the three reviews as delivered.
- `typesafe/evaluate.py`: the questions put to TypeSafe's Jev, the predictions, and the code that turns the answers into counts.
- `typesafe/evaluate.out`: what the run printed.
- `typesafe/results.json`: every request as sent and every reply. 3 requests, 11,328 input tokens.

**What the reviewers read.** This repository at commit `a10153e`, which is `883df2c` plus the brief. Mo was read in place and stood at commit `1aa5d0cc` when the reviewers started; another session was editing it.

**When `evaluate.py` was written.** At 21:01 UTC on 2026-11-14, before any review arrived: all 18 statements, the options for the first experiment, the predicted counts and Claude's own position. Nothing was added after a review was read. No request was sent to Jev until all three reviews were in.

**What was sent to Jev.** The three reviews, six one-line options and six definitions of terms. The script replaces the name "Robert" with "the owner", cuts the home folder from paths, and refuses to send a payload that holds either.

**How the predictions did.** Badly. Of 18 predicted counts, 3 matched cleanly, 8 differed and 7 had an answer between the thresholds. Of 3 predicted first experiments, 1 matched.

**Where Jev's answers need a person.** The five options for the first experiment overlap: Gemini Carbon's first experiment has agents write read functions and then runs a recogniser over what they wrote, so two options fit it. Jev chose the recogniser. That is a fault in the options, not in the answer.

**Claims checked against Mo's source by Claude**, each found as the review says:

- "There are no warnings: a problem is an error, or it isn't reported" (`docs/reference/README.md`, Appendix A).
- `filter` in `lib/list.mo` is a `for` loop with `append`.
- Agents fixed an error on the next attempt 37 times in 38 (`learnability/bench-v0-round-3/results.md`).
- `mo query --max-work` and `mo check --emit=core` exist (`src/tools/cli.c`).
- A program stops on overflow, on dividing by zero and at a `stop` (`docs/reference/README.md`).
- A primitive runs inside one `MO_OP_PRIM` (`src/vm/execute.c`), and collection primitives are in `src/prim/collections.c`.
- Maps and sets keep insertion order (`docs/reference/README.md`).
- `MO_LIMIT_INPUT_ELEMENTS` is 4096 (`src/base/limits.h`).

**Claims not checked.** That `filter` and loops lower to `MO_CORE_MAP_OP_ENTRIES` and jumps before Mo Core, so that the shape is gone by then. That work inside a primitive is not counted at all. Experiments 2 and 5 in `experiments.md` measure both.

**A count that differs.** Claude Opus counted 817 `for ... in` loops in `learnability/`. Claude's own count with `grep -E '^\s*for .* in '` was 986. Both found 80 uses of `.filter(` in 368 files.

**Running it again.** `evaluate.py` reads the three reviews from this folder. It needs `TYPESAFE_API_KEY` in the environment.

Claude Opus's review is 1,116 words against a limit of 900.
