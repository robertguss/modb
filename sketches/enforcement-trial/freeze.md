# Freeze of the enforcement trial, 2026-11-14

Experiment 4 in [experiments.md](../../experiments.md). This file was committed before any session started. It follows `~/code/mo/learnability/protocol.md` where it can and says where it does not.

## What is frozen

- **Mo.** A `mo` built with gcc from commit `ce86860a` of `~/code/mo`, plus another session's uncommitted changes in that checkout. SHA-256 of the binary: `7db644fac0851743acb02c8e1f169fea801f84f2d8a19950d0ecb8b3ecab00ff`. A copy sits at `build/enforcement-trial/mo`; the sessions and the grading both use that copy.
- **The prompt.** `PROMPT.md`, word for word, with `WORK` replaced by the session's folder.
- **The tasks.** The ten in `tasks.py`, and an eleventh for the pilots.
- **The two stores.** `STORE-a.md` with `shop-a.head.mo`, and `STORE-g.md` with `shop-g.head.mo`. Both hold the rows in `rows.mo`.
- **The rule of arm A.** `rule.py`, which uses the recogniser in `../shape-census/census.py`.
- **The grading.** `trial.py grade`, with the references `reference-a.mo` and `reference-g.mo`.

## The two arms

- **Arm A, plain Mo.** A table is a `Map`. `rule.py` stands in for the compiler: it refuses a read of a stored table that is not by key, not a filter in a recognised shape on an indexed field, and not through `walk`. Its error names the table's indexed fields and gives a fix.
- **Arm G, a table type.** A table is a `Table` whose rows are hidden. It is read through `get`, seven index functions and `walk`. Mo's own compiler does the refusing, with error E0064.

Both arms have the same rows, the same indexed fields and the same tasks. Eight tasks can be answered through an index. Two cannot: `mentions` must read every order and `idle_customers` must read every customer.

The options B (warn) and C (a `fast` marker) are not run. The closed form E is run as G.

## Sessions

40 sessions: 10 tasks, 2 arms, 2 models, one session each. `trial.py setup` writes their folders under `build/enforcement-trial/sessions/`, numbered `01` to `40`.

- **Claude:** a `general-purpose` subagent started with the Agent tool from a Claude Code session on `claude-fable-5-2`.
- **GPT:** `gpt-6.1-sol` through Codex, started with T3 Code's `delegate_task`, default settings.

Every session counts. One that ends without `answer.mo` is a fail. A session is run again only if it failed before it saw its task.

Two pilots, `p1` and `p2`, run first on the eleventh task. They are not scored. The harness may change after the pilots. Once the first of the 40 has started, any change makes a new round.

## What is measured

Each `./mo check` and `./mo test` a session runs is recorded with a copy of `answer.mo`. A **version** is a distinct `answer.mo` among those copies, in order, with the file the session left as the last.

A version is **valid** when it is correct Mo apart from the arm's own rule: it passes `mo check`, or in arm G its only errors are E0064. A version is **good** when it passes `mo check`, the arm's rule accepts it, the hidden test passes, and it walks no table the task does not need.

- **Good within two repairs:** one of the first three valid versions is good. This is the measure the predictions are about.
- **Ended good:** the last version is good.
- **First valid version was accepted:** the arm's rule did not refuse the first valid version.
- **Needless walk at the end:** the last version walks a table the task does not need, counted over the eight index tasks.

Each share is reported with a 95% Wilson interval. With 20 sessions in an arm the interval is about 20 points wide each way, so the trial can show only a large gap between the arms.

## Where this departs from Mo's protocol

- **The sessions are not sealed.** They run on this machine inside this repository, and are told to stay in their folder and off the web. Nothing stops one from reading elsewhere. They also receive this repository's instruction files.
- **The rule of arm A is a script that reads text.** A real compiler would follow names and types. The script may refuse code a compiler would accept, which counts against arm A.
- **Nothing is made fast.** Arm A's filters and arm G's index functions both walk a `Map` underneath. The trial measures what agents write, not speed.
- **No model graders.** The compiler, the rule and the hidden tests decide.
