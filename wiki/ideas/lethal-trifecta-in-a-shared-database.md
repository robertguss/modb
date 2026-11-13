# The lethal trifecta inside a shared database (gap)

A database that many agents share supplies, by itself, all three things an attacker needs to steal data through an agent. Only the database knows enough to break the chain. Nothing found does so.

## What it is

Simon Willison's *lethal trifecta* is access to private data, exposure to untrusted content, and "the ability to externally communicate". An agent with all three can be tricked into sending the data to an attacker, because "LLMs are unable to reliably distinguish the importance of instructions based on where they came from" (https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/). *Prompt injection* is that trick: text the model reads, such as a row or a ticket, that it then obeys as if the user wrote it ([21](../../research/21-security-of-a-database-agents-use.md)).

A shared database supplies all three (inference, [21](../../research/21-security-of-a-database-agents-use.md)):

- **Private data** is what it stores.
- **Untrusted content** is any row written by a customer, a scraper or another agent. With many agents, each agent's output is untrusted input to the rest.
- **A way out** is any write that someone else can read. The July 2025 Supabase leak worked exactly so: the agent wrote secrets into a support ticket the attacker could read ([09](../../research/09-agents-and-databases-today.md), https://generalanalysis.com/blog/supabase-mcp-blog). Taking web access away from the agent does not close this channel.

## The problem it solves

Naming the gap shows what only the database can do (inference, [21](../../research/21-security-of-a-database-agents-use.md)):

1. Only the database knows, per value, **who wrote it and whether it is trusted**. The harness, the program that runs the agent, sees an unlabelled blob of results.
2. Only the database knows **who can read what is about to be written**, so only it can refuse a write of secret data into a widely readable place.
3. Since injection cannot be reliably detected, a session that has read untrusted rows should lose the right to touch secret rows, or to write where untrusted parties read, until a person or a fixed plan restores it. See [narrowing a session after it reads untrusted rows](session-tainting-after-untrusted-reads.md).

## What it costs

- **Row labels for writer, trust and readers**, checked on every read and write. [IFDB](../systems/ifdb.md) measured about 1% throughput; policies still have to be written ([21](../../research/21-security-of-a-database-agents-use.md)). See [labels that follow data](information-flow-labels.md).
- **Mixed tasks need a fixed plan or a person** ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Mo's capabilities do not cover it.** A write another agent reads is not an outside effect, so no Mo capability stops it (inference from `~/code/mo/docs/agent-guide.md`, [21](../../research/21-security-of-a-database-agents-use.md)).

## Systems that use it

None inside a database. [CaMeL](../systems/camel.md) and FIDES break the chain in the agent's planner (https://arxiv.org/abs/2503.18813, https://arxiv.org/abs/2505.23643); research 21 found nothing that does it inside a database. See [planning before reading untrusted data](plan-then-execute-agents.md).

## Sources

- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/
- https://generalanalysis.com/blog/supabase-mcp-blog
- https://arxiv.org/abs/2503.18813
- https://arxiv.org/abs/2505.23643
