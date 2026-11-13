# Short-lived, narrowed grants per agent task

Each agent task gets its own credential, cut down to the rows and rights the task needs, and it expires soon. A *capability* is an unforgeable value that names a resource and grants a right over it; *attenuation* is cutting a capability down to fewer rights.

## What it is

- **Least privilege and short-lived credentials** ([21](../../research/21-security-of-a-database-agents-use.md)).
- **No ambient authority**: a program reaches nothing unless it is handed the capability ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Offline attenuation.** Eclipse Biscuit tokens let a holder add restrictions, written in the small logic language Datalog, without asking the issuer (https://www.biscuitsec.org/). A grant can be cut to "these rows, read only, ten minutes" before an agent gets it ([21](../../research/21-security-of-a-database-agents-use.md)).

## The problem it solves

Every incident research 21 studied had a credential broader or longer-lived than its task ([21](../../research/21-security-of-a-database-agents-use.md)):

- **Stolen passwords, no second factor.** In 2024 attackers logged into [Snowflake](../systems/snowflake.md) customer accounts with passwords taken by infostealer malware; the first account "did not have multi-factor authentication (MFA) enabled"; about 165 organisations were notified (https://cloud.google.com/blog/topics/threat-intelligence/unc5537-snowflake-data-theft-extortion).
- **Stolen integration tokens.** In August 2025 OAuth tokens stolen from the Salesloft Drift integration were used to export Salesforce data and search it for AWS keys, passwords and Snowflake tokens (https://cloud.google.com/blog/topics/threat-intelligence/data-theft-salesforce-instances-via-salesloft-drift).
- **Trusted tool, untrusted data.** A public GitHub issue made an agent using the official GitHub MCP server copy private repositories into a public pull request. The token covered public and private repositories alike (https://invariantlabs.ai/blog/mcp-github-vulnerability).
- **PocketOS**, where an unscoped token deleted a production volume ([09](../../research/09-agents-and-databases-today.md)).

## What it costs

- **Issuing and renewing grants**, and tasks that fail when a grant expires ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Offline tokens are harder to revoke** ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Enforcement must sit where the data is** ([21](../../research/21-security-of-a-database-agents-use.md)). The harness can request a grant; only the database can enforce it.
- **The grant language must be small enough** for an agent to read and a person to approve ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Unmeasured.** Research 21 found no measurement of how much least privilege reduces harm from agents.

## Systems that use it

- Biscuit tokens (https://www.biscuitsec.org/).
- The MCP specification now says servers "MUST NOT accept any tokens that were not explicitly issued for the MCP server" (https://modelcontextprotocol.io/specification/draft/basic/authorization/security-considerations). That binds server authors, not attackers ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Mo.** Every outside effect goes through a capability passed in, which can be narrowed and faked in tests (`~/code/mo/docs/agent-guide.md`, sections 11 and 12.4). Narrowing is attenuation, Biscuit's idea in the language. But Mo's capabilities govern the program's effects on its host; which agent may read which row is the database's own policy, built as data (inference, [21](../../research/21-security-of-a-database-agents-use.md)).
- Beside the database: MFA and network allow lists stop stolen passwords, at the cost of client friction ([21](../../research/21-security-of-a-database-agents-use.md)).

See [access scoped to what an agent may do](scoped-access-for-agents.md) and [a per-statement check inside the engine](statement-authoriser.md).

## Sources

- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://www.biscuitsec.org/
- https://cloud.google.com/blog/topics/threat-intelligence/unc5537-snowflake-data-theft-extortion
- https://cloud.google.com/blog/topics/threat-intelligence/data-theft-salesforce-instances-via-salesloft-drift
- https://invariantlabs.ai/blog/mcp-github-vulnerability
- https://modelcontextprotocol.io/specification/draft/basic/authorization/security-considerations
