# Planning before reading untrusted data

The agent fixes its plan from the user's request alone, before it reads any untrusted data. Untrusted values can fill the plan's holes but cannot change its steps.

## What it is

- **[CaMeL](../systems/camel.md)** has a privileged model write a plan from the user's request and runs it in its own interpreter. A quarantined model reads untrusted data, which "can never impact the program flow", and capabilities on values block forbidden flows at tool calls (https://arxiv.org/abs/2503.18813).
- **FIDES** (Microsoft) tracks confidentiality and integrity labels and "deterministically enforces security policies" (https://arxiv.org/abs/2505.23643).
- A twelve-author paper gives six such patterns resting on one rule: once untrusted input is read, it must not be able to trigger consequential actions (https://arxiv.org/abs/2506.08837).

## The problem it solves

Untrusted data choosing actions ([21](../../research/21-security-of-a-database-agents-use.md)). CaMeL and FIDES guarantee, under stated assumptions, that untrusted data cannot choose actions. That is the only *proven* defence research 21 found ([21](../../research/21-security-of-a-database-agents-use.md)).

## What it costs

- **Task success.** CaMeL solved 77% of AgentDojo benchmark tasks "with provable security", against 84% undefended (https://arxiv.org/abs/2503.18813): about 7 points.
- **A custom interpreter** ([21](../../research/21-security-of-a-database-agents-use.md)).
- **The policy is not proven right**, only enforced ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Implicit flows.** FIDES's authors say its confidentiality guarantee "does not prevent implicit flows", leaks through which branch ran (https://arxiv.org/abs/2505.23643).
- **As a database feature**, an agent would submit a fixed plan with holes that untrusted values fill but cannot change. Cost: less flexible agents ([21](../../research/21-security-of-a-database-agents-use.md)). Compare [transactions whose reads and writes are known up front](read-and-write-sets-known-up-front.md).

## Systems that use it

[CaMeL](../systems/camel.md) and FIDES, both in the agent harness, not in a database ([21](../../research/21-security-of-a-database-agents-use.md)).

## Sources

- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://arxiv.org/abs/2503.18813
- https://arxiv.org/abs/2505.23643
- https://arxiv.org/abs/2506.08837
