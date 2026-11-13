# Access scoped to what an agent may do (gap)

An agent gets only the access its task needs, and can ask the database what it is allowed to do. Today access is still shaped for humans, and agent scoping is added through proxies.

## What it is

Capability-scoped, budgeted access for agents, as opposed to accounts and roles (inference, [00](../../research/00-landscape-overview.md)). It includes an agent being able to inspect its own permissions, not only the schema ([09](../../research/09-agents-and-databases-today.md)).

## The problem it solves

Every documented agent incident found came from credentials and least privilege ([09](../../research/09-agents-and-databases-today.md)):

- **Supabase MCP leak, July 2025.** An attacker put instructions in a support ticket. A developer's agent, connected with the all-powerful `service_role` key, read the ticket and copied the `integration_tokens` table into it where the attacker could see it (https://generalanalysis.com/blog/supabase-mcp-blog).
- **Anthropic's reference SQLite MCP server, 2025-06-24.** Trend Micro found SQL injection that allowed stored [prompt injection](lethal-trifecta-in-a-shared-database.md). The repository was archived with no patch after being forked more than 5,000 times (https://www.trendmicro.com/en/research/25/f/why-a-classic-mcp-server-vulnerability-can-undermine-your-entire-ai-agent.html).
- **PocketOS, 2026-04-25.** A Cursor agent used an unscoped Railway token found in an unrelated file to delete a production volume (https://swarmproof.github.io/agent-postmortems/2026-pocketos-cursor-db-deletion/).

Research 21 adds more cases from 2024 to 2026, each with a credential broader or longer-lived than its task ([21](../../research/21-security-of-a-database-agents-use.md)): stolen [Snowflake](../systems/snowflake.md) passwords with no second factor, stolen Salesloft Drift integration tokens, and a GitHub MCP token that covered public and private repositories alike. See [short-lived, narrowed grants](attenuated-capabilities.md). Its reading of all of them: a filter that reads text to judge an action is weaker than a limit on what the credential can do (inference).

## What it costs

- **Policies the agent can read.** MCP introspection shows schemas, not policies. [PostgreSQL](../systems/postgresql.md) row-level security is enforced but cannot be inspected by the agent (inference, medium-high confidence, [09](../../research/09-agents-and-databases-today.md)).
- **Less reach for the agent.** After its leak, Supabase added a read-only mode, scoping to one project, wrapping of query results, and advice to keep agents away from production data (https://supabase.com/blog/defense-in-depth-mcp, https://news.ycombinator.com/item?id=44502318).

- **Hiding values is weaker than withholding access.** [Dynamic masking](dynamic-masking.md) does not stop a reader who writes ad hoc queries, and [row security](row-and-column-security.md) leaks through constraint checks ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Scoping has to decide what an agent may reach, not only what it is shown.

## Systems that use it

None as a database feature. Pieces:

- [PostgreSQL](../systems/postgresql.md) and Supabase: row-level security ([09](../../research/09-agents-and-databases-today.md)).
- [Neon](../systems/neon.md) and Supabase MCP servers list tables and describe schemas. They show what is stored, not what the agent may do ([09](../../research/09-agents-and-databases-today.md)).
- [SQLite](../systems/sqlite.md)'s authoriser callback rejects any statement outside an allowed set (https://www.sqlite.org/security.html). See [a per-statement check inside the engine](statement-authoriser.md).
- The MCP specification says servers "MUST NOT accept any tokens that were not explicitly issued for the MCP server" (https://modelcontextprotocol.io/specification/draft/basic/authorization/security-considerations); that binds server authors, not attackers ([21](../../research/21-security-of-a-database-agents-use.md)).
- ScramDB claims each agent gets its own branch and token and can have rows hidden from it (vendor marketing, not verified, https://scramdb.com/blog/merge-branches).

## Disagreements

- **Do database MCP servers have guardrails?** [00](../../research/00-landscape-overview.md) reports Pavlo's view that MCP database servers are mostly thin proxies with no real guardrails (https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html). [09](../../research/09-agents-and-databases-today.md) describes Neon's MCP server testing a migration on a temporary branch and applying it only after the user confirms, and Supabase adding read-only mode and project scoping after the July 2025 leak. It agrees that MCP introspection shows schemas, not policies.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- https://www.sqlite.org/security.html
- https://modelcontextprotocol.io/specification/draft/basic/authorization/security-considerations
- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html
- https://generalanalysis.com/blog/supabase-mcp-blog
- https://supabase.com/blog/defense-in-depth-mcp
- https://news.ycombinator.com/item?id=44502318
- https://www.trendmicro.com/en/research/25/f/why-a-classic-mcp-server-vulnerability-can-undermine-your-entire-ai-agent.html
- https://swarmproof.github.io/agent-postmortems/2026-pocketos-cursor-db-deletion/
- https://scramdb.com/blog/merge-branches
- https://github.com/neondatabase/mcp-server-neon/
