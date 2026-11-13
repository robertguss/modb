# Writes held for approval (gap)

An agent's write waits until a person, or a rule a person approved, lets it through. Today this lives beside the database, never inside its transactions.

## What it is

A write, or a merge of a branch, that is parked until approved. The mechanisms found are row-level security, a proxy that queues writes, a two-step migration, and a merge request ([09](../../research/09-agents-and-databases-today.md)).

## The problem it solves

The documented agent failures came from broad credentials, no approval step, and data read by the agent being treated as instructions, not from missing concurrency features ([09](../../research/09-agents-and-databases-today.md)):

- Replit's agent deleted a production database during a code freeze in July 2025. Replit split development and production databases and took production away from the agent (https://www.theregister.com/software/2025/07/22/replit-makes-vibe-y-promise-to-prevent-vibe-coding-disasters/1145851).
- On 2026-04-25 a Cursor agent found an unscoped Railway token and deleted a production volume, backups included, in 9 seconds. Railway made that endpoint delay deletions (https://swarmproof.github.io/agent-postmortems/2026-pocketos-cursor-db-deletion/).

## What it costs

- **A reachable approver, and a write that waits.** PgBeam parks each write until approved (https://pgbeam.com/docs/approvals).
- **A step outside the database.** PgBeam is a proxy; Neon's approval is in its MCP server. No engine found runs approval rules inside its own transactions (inference, medium confidence, [09](../../research/09-agents-and-databases-today.md)).
- **Checks that see the right data.** lakeFS's `pre-merge` hook "runs on the source branch" (https://docs.lakefs.io/guides/hooks/); whether it sees the merged result is not confirmed ([06](../../research/06-divergent-copies-and-merging.md)).

## Systems that use it

- [Neon](../systems/neon.md): its MCP server tests a migration on a temporary branch and applies it only after the user confirms (https://github.com/neondatabase/mcp-server-neon/).
- [Dolt](../systems/dolt.md): agents write on their own branch or clone, someone reviews the diff, then it is merged or thrown away (https://www.dolthub.com/blog/2025-08-25-agents-need-clones/). Constraint violations found at merge block commit until empty unless forced (https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/).
- [lakeFS](../systems/lakefs.md): a `pre-merge` hook can run checks and fail the merge (https://docs.lakefs.io/guides/hooks/).
- PgBeam: a proxy that parks each write until approved (https://pgbeam.com/docs/approvals).
- ScramDB: each agent sends a merge request a human approves (vendor marketing, not verified, https://scramdb.com/blog/merge-branches).
- Postgres and Supabase row-level security ([09](../../research/09-agents-and-databases-today.md)).

## Sources

- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://pgbeam.com/docs/approvals
- https://github.com/neondatabase/mcp-server-neon/
- https://www.dolthub.com/blog/2025-08-25-agents-need-clones/
- https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/
- https://docs.lakefs.io/guides/hooks/
- https://scramdb.com/blog/merge-branches
- https://www.theregister.com/software/2025/07/22/replit-makes-vibe-y-promise-to-prevent-vibe-coding-disasters/1145851
- https://swarmproof.github.io/agent-postmortems/2026-pocketos-cursor-db-deletion/
