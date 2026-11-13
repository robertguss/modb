# Versioned data: branch, diff and merge

These systems bring Git's workflow to data: make a branch, change it, review the diff, and merge it or throw it away. Most branches share storage with their parent until something changes.

## What they are for

Reproducibility, review and safe experiments ([00](../../research/00-landscape-overview.md)). They dropped the assumption that history is linear ([00](../../research/00-landscape-overview.md)). For agents, a branch is a place to try a change on a copy and then keep or discard it ([09](../../research/09-agents-and-databases-today.md)). See [Cheap branches that share storage](../ideas/copy-on-write-branches.md).

## Members

- [Dolt](../systems/dolt.md): a SQL database with cell-level [three-way merge](../ideas/three-way-merge-of-data.md) and conflicts kept as tables.
- [lakeFS](../systems/lakefs.md): branches and merges for files in object storage, at whole-file granularity.
- [Neon](../systems/neon.md): Postgres with instant copy-on-write branches and no merge.
- [Chronos (MIT research system)](../systems/chronos.md): branches over unchanged Postgres, SQLite, DuckDB and Qdrant, with merges visible in every store at once.

Mentioned in the research without a page:

- Xata: Postgres with copy-on-write branches that include data and remove personal data; branches become independent instances and no merge was found ([06](../../research/06-divergent-copies-and-merging.md), [09](../../research/09-agents-and-databases-today.md)).
- Supabase branching: copies the schema but not the data by default, per a third-party comparison ([09](../../research/09-agents-and-databases-today.md)).
- PlanetScale branching: also copies schema but not data by default, per the same third party ([09](../../research/09-agents-and-databases-today.md)).
- ScramDB: a 2026 launch giving each agent a branch and token, with human-approved merge requests; vendor marketing, not verified ([09](../../research/09-agents-and-databases-today.md)).
- Turso AgentFS: a SQLite-backed filesystem where an agent's writes land in a copy-on-write layer ([09](../../research/09-agents-and-databases-today.md)).
- TARDiS: a research store with branches as a first-class part of weak consistency ([06](../../research/06-divergent-copies-and-merging.md)).
- BranchBench: a 2026 benchmark of branching systems, including Neon and Dolt ([06](../../research/06-divergent-copies-and-merging.md), [09](../../research/09-agents-and-databases-today.md)).
- Yugabyte Meko: a 2026 launch of shared memory for multi-agent systems; vendor marketing, not verified ([09](../../research/09-agents-and-databases-today.md)).
- Contextbase: a 2026 agent-memory launch with only announcements found ([00](../../research/00-landscape-overview.md)).

## Shared tradeoffs

- **Fast branching or fast reads, not both.** BranchBench found "a fundamental tension": systems built for fast branching read up to 5 to 4000 times slower as branches deepen; systems built for fast reads branch 25 to 1500 times slower. "No current system supports the representative workloads at scale" (https://arxiv.org/abs/2604.17180).
- **Overlap shows up only at merge time.** Each writer gets a branch ([06](../../research/06-divergent-copies-and-merging.md)).
- **Merge is structural.** Dolt matches rows by primary key and cells; lakeFS compares whole files. "No conflict" means only that no cell (or file) changed on both sides ([06](../../research/06-divergent-copies-and-merging.md)). See [Merging by meaning](../ideas/merging-by-meaning.md).
- **The products agents use most do not merge.** Neon and Xata have no way back except overwrite or migrations. Of the branching tools agents use, only Dolt and Chronos document merging data back ([06](../../research/06-divergent-copies-and-merging.md), [09](../../research/09-agents-and-databases-today.md)).
- **A branch does not record intent.** Choosing between base, ours and theirs needs both sides' intent ([06](../../research/06-divergent-copies-and-merging.md)).
- **Branches reconcile with the main copy, not with each other.** The Berkeley paper asks for forks that "reconcile not just with the mainline, but with each other" (https://arxiv.org/html/2509.00997v2). See [Many branches that reconcile with each other](../ideas/branches-that-reconcile-with-each-other.md).
- **Approval sits beside the database.** See [Writes held for approval](../ideas/writes-held-for-approval.md).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://arxiv.org/abs/2604.17180
- https://arxiv.org/html/2509.00997v2
