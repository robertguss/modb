# Neon

Neon is hosted PostgreSQL with copy-on-write branches. Databricks bought it in 2025, and it is the database agents create most often by its own figures.

## What it is for

Postgres databases that can be branched instantly, so a change can be tried on a copy and kept or thrown away ([06](../../research/06-divergent-copies-and-merging.md), [09](../../research/09-agents-and-databases-today.md)). Databricks bought Neon for about $1B (https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html).

## Core idea

- *Copy-on-write branching*: a new branch shares storage with its parent until it changes (https://neon.com/docs/manage/branches). See [Cheap branches that share storage](../ideas/copy-on-write-branches.md).
- Neon offers a schema diff between branches and a way to reset a branch to its parent (https://neon.com/docs/guides/schema-diff, https://neon.com/docs/guides/reset-from-parent).
- Neon dropped the assumption that history is linear ([00](../../research/00-landscape-overview.md)).

## Strengths and what pays for each

- **Instant copy-on-write branches.** Paid for by having no merge at all ([06](../../research/06-divergent-copies-and-merging.md)), and by shared storage that slows reads on deep branch chains (https://arxiv.org/abs/2604.17180).
- **Used heavily by agents.** Neon said over 80% of its databases are created by AI agents (vendor claim, https://neon.com/blog/neon-and-databricks; 2025-05-14, https://www.databricks.com/company/newsroom/press-releases/databricks-agrees-acquire-neon-help-developers-deliver-ai-systems). A later Databricks post says agents create 80% of databases and 97% of branches (vendor claim, about 2026-01-27, https://www.databricks.com/blog/enterprise-ai-agent-trends-top-use-cases-governance-evaluations-and-more). The Berkeley paper reports that at Neon, agents created 20× more branches and did 50× more rollbacks than humans (https://arxiv.org/html/2509.00997v2).

- **Anonymized branches.** Neon makes a branch and runs [PostgreSQL Anonymizer](postgresql-anonymizer.md) static masking on it, with rules per branch (https://neon.com/docs/workflows/data-anonymization). Paid for by a stale copy protected only as well as hand-written rules; untagged and free-text columns pass through ([20](../../research/20-keeping-sensitive-data-from-agents.md)). See [masked copies](../ideas/masked-copies.md).

## Weaknesses

- **No way back except overwrite or migrations.** "Reset from parent" is "a complete overwrite ... not a refresh or a merge" (https://neon.com/docs/guides/reset-from-parent). See the disagreement below.
- **The 80% figure says little about sharing.** It is mostly agents provisioning short-lived, isolated databases: evidence for many small private databases, not for many agents sharing one (inference, [09](../../research/09-agents-and-databases-today.md)).

## Overlapping work

Each agent gets its own branch. Because branches do not merge, overlapping work on two branches never reconciles ([06](../../research/06-divergent-copies-and-merging.md)). See [Many branches that reconcile with each other](../ideas/branches-that-reconcile-with-each-other.md).

## What an agent struggles with

- Getting a branch's data back into the parent ([09](../../research/09-agents-and-databases-today.md)).
- Approval lives beside the database. Neon's MCP server tests a migration on a temporary branch and applies it only after the user confirms (https://github.com/neondatabase/mcp-server-neon/). No engine found runs approval rules inside its own transactions (inference, [09](../../research/09-agents-and-databases-today.md)). See [Writes held for approval](../ideas/writes-held-for-approval.md).
- Neon's MCP server lists tables and describes schemas. It shows what is stored, not what the agent is allowed to do ([09](../../research/09-agents-and-databases-today.md)). See [Access scoped to what an agent may do](../ideas/scoped-access-for-agents.md).

## Disagreements

- **Can Neon merge a branch back?** [06](../../research/06-divergent-copies-and-merging.md) states as fact that Neon does not merge, quoting reset-from-parent. [09](../../research/09-agents-and-databases-today.md) reaches the same conclusion but marks it as its own reading of the docs, not a statement in them.
- **Where the 50× rollback figure comes from.** [06](../../research/06-divergent-copies-and-merging.md) states that Neon saw 50× more rollbacks from agents, with no citation. [09](../../research/09-agents-and-databases-today.md) attributes the 20× branches and 50× rollbacks to the Berkeley "Supporting Our AI Overlords" paper, reporting Neon data, and treats Neon's agent figures as vendor numbers.
- **Do database MCP servers have guardrails?** [00](../../research/00-landscape-overview.md) reports Pavlo's view that they are mostly thin proxies with no real guardrails. [09](../../research/09-agents-and-databases-today.md) describes Neon's MCP server testing a migration on a temporary branch before applying it.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://neon.com/docs/workflows/data-anonymization
- https://neon.com/docs/manage/branches
- https://neon.com/docs/guides/schema-diff
- https://neon.com/docs/guides/reset-from-parent
- https://neon.com/blog/neon-and-databricks
- https://www.databricks.com/company/newsroom/press-releases/databricks-agrees-acquire-neon-help-developers-deliver-ai-systems
- https://www.databricks.com/blog/enterprise-ai-agent-trends-top-use-cases-governance-evaluations-and-more
- https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html
- https://arxiv.org/html/2509.00997v2
- https://arxiv.org/abs/2604.17180
- https://github.com/neondatabase/mcp-server-neon/
