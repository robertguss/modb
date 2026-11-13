# Agents and databases today

Type: research
Status: resolved

## Question

What exists today for many AI agents working on the same data, for each coordination problem (overlapping work, conflicting writes, who changed what and why, try on a copy, guarded writes, discovery by an agent with no memory), what has gone wrong in practice, and what is missing?

## Answer

Findings: [research/09-agents-and-databases-today.md](../research/09-agents-and-databases-today.md).

- **Well served:** trying a change on a copy (copy-on-write branches in Neon, Xata, Dolt), and work that stays open for minutes (retry on conflict, branches).
- **Served beside the database, not inside it:** holding a write for approval (proxies and MCP servers), and telling an agent what it may do (schemas are listed, permissions are not).
- **Not served:** recording why a change was made, and reconciling changes by several agents that are each fine alone and wrong together.
- **Failures in practice** came from broad credentials and injected instructions, never from a missing concurrency feature.
- **Evidence against coordination-first:** the Berkeley paper says the volume of exploratory agent queries becomes the bottleneck, and the Chronos paper adds branching on top of existing databases without a new engine.
