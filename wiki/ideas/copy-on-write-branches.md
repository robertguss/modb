# Cheap branches that share storage

A new branch of a database shares storage with its parent until something changes, so making one is nearly free. This is *copy-on-write* branching.

## What it is

- *Copy-on-write* means a new branch shares storage with its parent until something changes ([06](../../research/06-divergent-copies-and-merging.md), https://neon.com/docs/manage/branches).
- [Dolt](../systems/dolt.md) uses *prolly trees*, content-addressed B-trees that share structure between versions and give cheap diffs (https://www.dolthub.com/docs/architecture/storage-engine/).
- [lakeFS](../systems/lakefs.md) creates a branch as a metadata-only operation (https://docs.lakefs.io/quickstart/branch/).
- [Chronos](../systems/chronos.md) adds branches over unchanged databases by query rewriting (https://arxiv.org/abs/2609.14889).

## The problem it solves

Trying a change on a copy, then keeping or discarding it. The research calls this well served today, except for merging data back (inference, [09](../../research/09-agents-and-databases-today.md)). Agents use it heavily: Databricks says agents create 80% of Neon databases and 97% of branches (vendor claim, https://www.databricks.com/blog/enterprise-ai-agent-trends-top-use-cases-governance-evaluations-and-more). Pavlo names branching as the feature that matters to agents (https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html).

## What it costs

- **Slow reads on deep branches, or slow branching.** BranchBench found "a fundamental tension": systems built for fast branching read up to 5 to 4000 times slower as branches deepen; systems built for fast reads branch 25 to 1500 times slower. "No current system supports the representative workloads at scale" (https://arxiv.org/abs/2604.17180).
- **Getting the work back.** A cheap branch is only half the job. [Neon](../systems/neon.md) and Xata have no way back except overwrite or migrations ([06](../../research/06-divergent-copies-and-merging.md)). See [Three-way merge of data](three-way-merge-of-data.md).
- **Not true isolation for nested work.** BranchBench notes that nested transactions do not give the persistent isolation agents need (https://arxiv.org/abs/2604.17180).

## Systems that use it

[Neon](../systems/neon.md), [Dolt](../systems/dolt.md), [lakeFS](../systems/lakefs.md), [Chronos](../systems/chronos.md). Also Xata and Turso AgentFS, an agent filesystem whose writes land in a copy-on-write layer (https://turso.tech/blog/agentfs-overlay). HyPer once ran analytics on the operating system's copy-on-write snapshot of a forked process ([02](../../research/02-analytical-and-specialised.md)).

## Disagreements

- **Can Neon merge a branch back?** [06](../../research/06-divergent-copies-and-merging.md) states as fact that Neon and Xata do not merge. [09](../../research/09-agents-and-databases-today.md) reaches the same conclusion for Neon but marks it as its own reading of the docs. [06](../../research/06-divergent-copies-and-merging.md) is itself unsure about Xata: its text says it found no explicit statement, while its summary table says "No merge at all".

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- https://vldb.org/pvldb/vol4/p1367-funke.pdf
- https://neon.com/docs/manage/branches
- https://www.dolthub.com/docs/architecture/storage-engine/
- https://docs.lakefs.io/quickstart/branch/
- https://arxiv.org/abs/2609.14889
- https://arxiv.org/abs/2604.17180
- https://turso.tech/blog/agentfs-overlay
- https://www.databricks.com/blog/enterprise-ai-agent-trends-top-use-cases-governance-evaluations-and-more
- https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html
