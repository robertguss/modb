# Narrowing a session after it reads untrusted rows (gap)

Once an agent's session has read rows from untrusted writers, the database takes away its right to touch secret rows, or to write where untrusted parties can read, until a person or a fixed plan restores it. Research 21 proposes this; nothing found does it inside a database.

## What it is

A session is *tainted* by what it reads. The rule behind it, from a twelve-author paper on agent design patterns: once untrusted input is read, it must not be able to trigger consequential actions (https://arxiv.org/abs/2506.08837).

## The problem it solves

Injected instructions acting on secret data ([21](../../research/21-security-of-a-database-agents-use.md)). It closes the [lethal trifecta](lethal-trifecta-in-a-shared-database.md) without having to detect the injection, which the measurements say defenders lose:

- NIST's AI institute raised agent-hijack success on held-out tasks from 11% to 81% with tuned attacks, and retrying each attack 25 times raised the average from 57% to 80% (https://www.nist.gov/news-events/news/2025/01/technical-blog-strengthening-ai-agent-hijacking-evaluations).
- Adaptive attacks bypassed 12 published defences, most "with attack success rate above 90%", where "the majority of defenses originally reported near-zero" (https://arxiv.org/abs/2510.09023).

## What it costs

- **Mixed tasks need a fixed plan or a person** ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Labels on rows** saying who wrote them and whether they are trusted. See [labels that follow data](information-flow-labels.md).

## Systems that use it

None inside a database ([21](../../research/21-security-of-a-database-agents-use.md)). The same rule lives in the agent's planner in [CaMeL](../systems/camel.md) and FIDES. See [planning before reading untrusted data](plan-then-execute-agents.md).

## Sources

- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- https://arxiv.org/abs/2506.08837
- https://www.nist.gov/news-events/news/2025/01/technical-blog-strengthening-ai-agent-hijacking-evaluations
- https://arxiv.org/abs/2510.09023
