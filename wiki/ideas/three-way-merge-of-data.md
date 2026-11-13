# Three-way merge of data

To merge two branches, compare each with their last common ancestor and keep whichever side changed. This is how Git merges code, applied to rows or files.

## What it is

A *three-way merge* compares each side with their last common ancestor, the *merge base*, and keeps whichever side changed ([06](../../research/06-divergent-copies-and-merging.md)).

- [Dolt](../systems/dolt.md) matches rows by primary key. A conflict happens only when both sides set the same row and column to different values (https://www.dolthub.com/docs/concepts/dolt/git/merge/).
- [lakeFS](../systems/lakefs.md) compares whole objects. A file changed on both sides is a conflict, and the merge fails unless the caller picks `source-wins` or `dest-wins` (https://docs.lakefs.io/v1.83/understand/how/merge/).

## The problem it solves

Bringing work done on a branch back, without a person, when the two sides touched different things ([06](../../research/06-divergent-copies-and-merging.md)). Most merges finish on their own: Dolt reported that most users "experience conflicts very rarely" (vendor statement, https://www.dolthub.com/blog/2026-05-27-conflicts-in-the-wild/).

## What it costs

- **Stable keys.** Dolt matches rows by primary key ([06](../../research/06-divergent-copies-and-merging.md)).
- **"No conflict" means only "no cell changed on both sides"** ([06](../../research/06-divergent-copies-and-merging.md)). Clean merges can still be wrong in meaning; see [Merging by meaning](merging-by-meaning.md).
- **Rules checked over the merged result.** Dolt puts foreign-key and unique-key breakages in `dolt_constraint_violations`, which blocks commit until empty unless forced (https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/), and verifies check constraints on merged rows (https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/). Dolt calls its merge rules "one of the more complex product problems that we face" (same page). See [Conflicts kept as data](conflicts-kept-as-data.md).
- **Coarse granularity in lakeFS.** Any change to one file on both sides conflicts ([06](../../research/06-divergent-copies-and-merging.md)).
- **Users design conflicts away.** Dolt users keep branches short and have one writer per row (vendor statement, https://www.dolthub.com/blog/2026-05-27-conflicts-in-the-wild/).

## Systems that use it

[Dolt](../systems/dolt.md), [lakeFS](../systems/lakefs.md). ScramDB, a 2026 launch, claims a merge stops and lists conflicts when the same primary key changed on both sides (vendor marketing, not verified, https://scramdb.com/blog/merge-branches).

The systems in [06](../../research/06-divergent-copies-and-merging.md) answer a conflict in one of four ways: pick a winner silently (lakeFS flags), stop and ask (Dolt, lakeFS default), re-run the operation with its guard against a single authority (Bayou, Zero), or never merge (Neon, Xata). An agent struggles to choose between base, ours and theirs because that needs both sides' intent, which a branch does not record ([06](../../research/06-divergent-copies-and-merging.md)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://www.dolthub.com/docs/concepts/dolt/git/merge/
- https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/
- https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/
- https://www.dolthub.com/blog/2026-05-27-conflicts-in-the-wild/
- https://docs.lakefs.io/v1.83/understand/how/merge/
- https://scramdb.com/blog/merge-branches
