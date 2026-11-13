# A per-statement check inside the engine

The engine checks every statement an agent sends against what that agent is allowed to do, and rejects any statement outside an allowed set. Low limits on query size and depth go with it.

## What it is

[SQLite](../systems/sqlite.md)'s advice for untrusted SQL: a defensive mode, far lower limits (expression depth 10 instead of 1,000; no attached databases), and an *authoriser* callback that rejects any statement outside an allowed set (https://www.sqlite.org/security.html). That authoriser is a per-statement capability check inside the engine ([21](../../research/21-security-of-a-database-agents-use.md)).

## The problem it solves

Query-language injection and "read-only" modes that are not ([21](../../research/21-security-of-a-database-agents-use.md)):

- Anthropic's reference Postgres MCP server ran agent SQL in a read-only transaction but accepted several statements at once, so `COMMIT;` followed by a write escaped it (https://securitylabs.datadoghq.com/articles/mcp-vulnerability-case-study-SQL-injection-in-the-postgresql-mcp-server/).
- In LangChain applications, all seven models tested could be led to generate harmful SQL (https://arxiv.org/abs/2308.01990).
- Snowflake's Cortex Code agent judged `cat` safe by reading command text and missed commands hidden in process substitution (https://www.promptarmor.com/resources/snowflake-ai-escapes-sandbox-and-executes-malware).

Research 21's reading: a filter that reads text to judge an action is weaker than a limit on what the credential can do (inference, [21](../../research/21-security-of-a-database-agents-use.md)). An authoriser checks the parsed statement, not its text.

## What it costs

- **Fewer allowed statement forms** ([21](../../research/21-security-of-a-database-agents-use.md)).
- **A grant language small enough** for an agent to read and a person to approve ([21](../../research/21-security-of-a-database-agents-use.md)).

## Systems that use it

[SQLite](../systems/sqlite.md) (https://www.sqlite.org/security.html). Research 21 proposes it as the shape of an agent grant. See [short-lived, narrowed grants](attenuated-capabilities.md).

## Sources

- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- https://www.sqlite.org/security.html
- https://securitylabs.datadoghq.com/articles/mcp-vulnerability-case-study-SQL-injection-in-the-postgresql-mcp-server/
- https://arxiv.org/abs/2308.01990
- https://www.promptarmor.com/resources/snowflake-ai-escapes-sandbox-and-executes-malware
