# Dolt

Dolt is a SQL database with Git's workflow for tables: branch, change, review the diff, merge. It calls itself "the perfect database for agents" (vendor claim).

## What it is for

Version control for data: reproducibility, review and safe experiments ([00](../../research/00-landscape-overview.md)). Dolt pitches itself to agents because it gives databases what Git gives code: version control and tests (vendor claim, 2025-09-08, https://www.dolthub.com/blog/2025-09-08-agentic-ai-three-pillars/). Agents write on their own branch or clone, someone reviews the diff, then it is merged or thrown away (2025-08-25, https://www.dolthub.com/blog/2025-08-25-agents-need-clones/).

## Core idea

- Storage is built on *prolly trees*: content-addressed B-trees that give cheap diffs and share structure between versions (https://www.dolthub.com/docs/architecture/storage-engine/). See [Cheap branches that share storage](../ideas/copy-on-write-branches.md).
- Merge is a *three-way merge*. Dolt compares each side with their last common ancestor (the *merge base*) and keeps whichever side changed, matching rows by primary key. A conflict happens only when both sides set the same row and column to different values (https://www.dolthub.com/docs/concepts/dolt/git/merge/). See [Three-way merge of data](../ideas/three-way-merge-of-data.md).
- Dolt dropped the assumption that history is linear ([00](../../research/00-landscape-overview.md)).

## Strengths and what pays for each

- **Cheap branches and a reviewable diff.** Paid for by shared storage that slows reads on deep branch chains ([06](../../research/06-divergent-copies-and-merging.md), https://arxiv.org/abs/2604.17180).
- **Merges usually finish without a person.** Paid for by stable primary keys, and by "no conflict" meaning only "no cell changed on both sides" ([06](../../research/06-divergent-copies-and-merging.md)).
- **Conflicts and broken rules are tables.** Conflicts land in `dolt_conflicts_<table>` (base, ours, theirs). Foreign-key and unique-key breakages land in `dolt_constraint_violations`, which blocks commit until empty unless forced (https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/). Merge also verifies check constraints on the merged rows. Paid for by every rule being checked over the merged result, and by constraints having to be declared (https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/). See [Conflicts kept as data](../ideas/conflicts-kept-as-data.md).
- **Who changed what.** Dolt records it in a commit log with author and message ([09](../../research/09-agents-and-databases-today.md)).

## Weaknesses

- **A clean merge can still be wrong in meaning.** Two agents can each insert a different booking for the last seat; different keys, no conflict, capacity exceeded. A check constraint catches a meeting that ends before it starts only if someone declared it (inference, [06](../../research/06-divergent-copies-and-merging.md)). See [Merging by meaning](../ideas/merging-by-meaning.md).
- **Merge rules are hard.** Dolt calls them "one of the more complex product problems that we face" (https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/).
- **The reason for a change is free text.** Commit messages are not tied to the agent's task, inputs, or the rule that allowed the write (inference, [09](../../research/09-agents-and-databases-today.md)). See [Recording why a write happened](../ideas/recording-why-a-write-happened.md).

## Overlapping work

Each writer gets a branch. Overlap shows up only at merge time ([06](../../research/06-divergent-copies-and-merging.md)). In May 2026 Dolt reported that most users "experience conflicts very rarely" because they design them away: short branches, one writer per row. On agents: "Agents might help this process in the future but not yet" (vendor statement, https://www.dolthub.com/blog/2026-05-27-conflicts-in-the-wild/).

## What an agent struggles with

Choosing between base, ours and theirs needs both sides' intent, which a branch does not record ([06](../../research/06-divergent-copies-and-merging.md)). The merge sees what was written, not what was read or assumed (inference, [06](../../research/06-divergent-copies-and-merging.md)).

## Worth borrowing

Conflicts and violations as queryable tables that block commit. Costs every rule being checked over the merged result, not each side (researcher's inference, [06](../../research/06-divergent-copies-and-merging.md)).

## Disagreements

- **Does anything merge by intent?** All sources agree Dolt merges cell by cell. [00](../../research/00-landscape-overview.md) says nobody merges by intent; [06](../../research/06-divergent-copies-and-merging.md) and [04](../../research/04-models-that-lost-or-stayed-niche.md) point to Bayou and GemStone as mechanisms that do. See [Merging by meaning](../ideas/merging-by-meaning.md).
- **Cross-transaction invariants.** [00](../../research/00-landscape-overview.md) says no general system lets users declare invariants across transactions (marked inference). [06](../../research/06-divergent-copies-and-merging.md) describes Dolt checking constraints over the merged result.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://www.dolthub.com/docs/architecture/storage-engine/
- https://www.dolthub.com/docs/concepts/dolt/git/merge/
- https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/
- https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/
- https://www.dolthub.com/blog/2026-05-27-conflicts-in-the-wild/
- https://www.dolthub.com/blog/2025-09-08-agentic-ai-three-pillars/
- https://www.dolthub.com/blog/2025-08-25-agents-need-clones/
- https://arxiv.org/abs/2604.17180
