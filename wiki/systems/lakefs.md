# lakeFS

lakeFS gives Git-style branches and merges to files in object storage. It works at the level of whole files.

## What it is for

Version control for large data sets kept as files: reproducibility, review and safe experiments ([00](../../research/00-landscape-overview.md)).

## Core idea

- Creating a branch is a metadata-only operation; no data is copied (https://docs.lakefs.io/quickstart/branch/). See [Cheap branches that share storage](../ideas/copy-on-write-branches.md).
- Merge is a *three-way merge* that compares whole objects with their last common ancestor. A file changed on both sides is a conflict (https://docs.lakefs.io/v1.83/understand/how/merge/). See [Three-way merge of data](../ideas/three-way-merge-of-data.md).

## Strengths and what pays for each

- **Cheap branches of huge files.** Paid for by whole-file granularity: any change on both sides of one file is a conflict ([06](../../research/06-divergent-copies-and-merging.md)).
- **Checks before a merge.** A `pre-merge` hook can run checks and fail the merge. The docs say it "runs on the source branch" (https://docs.lakefs.io/guides/hooks/). Whether it sees the merged result or only the source branch is not confirmed ([06](../../research/06-divergent-copies-and-merging.md)).

## Weaknesses

- **A conflict is a whole file.** The merge fails unless the caller picks `source-wins` or `dest-wins` (https://docs.lakefs.io/v1.83/understand/how/merge/).

## Overlapping work

Each writer gets a branch; overlap shows up only at merge time. On a conflict lakeFS stops and asks by default, or picks a winner if a flag says so ([06](../../research/06-divergent-copies-and-merging.md)).

## What an agent struggles with

`source-wins` is a flag that makes a conflict disappear ([06](../../research/06-divergent-copies-and-merging.md)). Choosing a side needs both sides' intent, which a branch does not record ([06](../../research/06-divergent-copies-and-merging.md)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- https://docs.lakefs.io/quickstart/branch/
- https://docs.lakefs.io/v1.83/understand/how/merge/
- https://docs.lakefs.io/guides/hooks/
