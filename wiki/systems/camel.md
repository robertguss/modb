# CaMeL (agent defence, research)

CaMeL is a 2025 research design for running an AI agent so that untrusted data it reads cannot change what it does. It is not a database, but it is the clearest shape for a database feature research 21 proposes.

## What it is for

Defending an agent against [prompt injection](../ideas/lethal-trifecta-in-a-shared-database.md): text in its data that it would otherwise obey (https://arxiv.org/abs/2503.18813, [21](../../research/21-security-of-a-database-agents-use.md)).

## Core idea

- A privileged model writes a plan from the user's request alone, and CaMeL runs that plan in its own interpreter (https://arxiv.org/abs/2503.18813).
- A quarantined model reads untrusted data, which "can never impact the program flow" (https://arxiv.org/abs/2503.18813).
- Values carry tags for where they came from and who may read them, and tool calls are checked against policy (https://arxiv.org/abs/2503.18813, [20](../../research/20-keeping-sensitive-data-from-agents.md)).

See [planning before reading untrusted data](../ideas/plan-then-execute-agents.md) and [labels that follow data](../ideas/information-flow-labels.md).

## Strengths and what pays for each

- **Provable security under stated assumptions.** It solved 77% of AgentDojo tasks "with provable security", against 84% undefended (https://arxiv.org/abs/2503.18813). *Paid for by* about 7 points of task success and a custom interpreter ([21](../../research/21-security-of-a-database-agents-use.md)).

## Weaknesses

- **It does not prove the policy is right**, only that it is enforced ([21](../../research/21-security-of-a-database-agents-use.md)).
- **It lives in the harness**, so it cannot see which rows other agents wrote or who can read a write ([21](../../research/21-security-of-a-database-agents-use.md), inference). See [the lethal trifecta inside a shared database](../ideas/lethal-trifecta-in-a-shared-database.md).

## Worth borrowing

The split of plan and data, as a database feature: an agent submits a fixed plan with holes that untrusted values fill but cannot change. Cost: less flexible agents ([21](../../research/21-security-of-a-database-agents-use.md)).

## Sources

- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://arxiv.org/abs/2503.18813
