# Council review, 2026-11-14: which vertical slices

Sources for [Which vertical slices, in what order, and what must each show?](../../issues/38-which-vertical-slices-in-what-order.md). Never edited.

- `brief.md`: the brief each reviewer was given, the same for all three.
- `gpt-sol.md`, `claude-opus.md`, `gemini-carbon.md`: the three reviews as delivered. The only change is that the home folder was cut from file paths, so `mo/...` is Mo and `modb/...` is this repository.
- `typesafe/evaluate.py`: the questions put to TypeSafe's Jev, the predictions, and the code that turns the answers into verdicts.
- `typesafe/evaluate.out`: what the run printed.
- `typesafe/results.json`: every request as sent and every reply. 23 requests, 26,267 input tokens, about $0.0011.

**What the reviewers read.** A copy of this repository at commit `28b9da6`. Claude's own proposal of five slices was written in the next commit, so no reviewer saw it. Mo was read in place and stood at commit `af246d7d` when the reviews were checked.

**When each part of `evaluate.py` was written** (UTC, 2026-11-14).

- 16:11, before any review arrived: the 22 statements, the options for the first slice, and the predictions for both.
- 16:17, after two reviews had been read: 16 citation checks, and five more statements that the script marks as carrying no prediction.
- 16:25, after the third: four more citation checks. No request was sent to Jev before this.

**What was sent to Jev.** The three reviews and short excerpts of Mo and of this repository. The script replaces the name "Robert" with "the owner" and refuses to send a payload that holds a home folder or an account name.

**Running it again.** `evaluate.py` reads its excerpts with `git show` at the two commits above, so it reads the same lines however the files have moved since. It differs from the script that ran only in where it finds the reviews and this repository; on 2026-11-14 it was checked to build the same 23 requests that `results.json` holds. It needs `TYPESAFE_API_KEY` in the environment, and Mo at `~/code/mo`.

Claude Opus's review is 1,172 words against a limit of 900.
