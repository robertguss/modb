Research run on 2026-11-13 by a subagent using Exa, for the ticket [Security of a database that agents use](../issues/21-security-of-a-database-agents-use.md). It builds on the incidents in [09](09-agents-and-databases-today.md) and the testing methods in [08](08-correctness-first-databases.md), and repeats neither. Vendor claims are marked. Reasoning with no source is marked "inference".

# Security of a database that agents use (researched 2026-11-13)

Terms used below:

- **Prompt injection**: text the model reads (a row, a ticket, a README) that it then obeys as if the user wrote it.
- **Exfiltration**: sending private data where an attacker can read it.
- **Capability**: an unforgeable value that names a resource and grants a right over it. **No ambient authority** means a program reaches nothing unless it is handed the capability. **Attenuation** is cutting a capability down to fewer rights.
- **Information-flow control (IFC)**: every value carries a label (secret, untrusted, written by whom), and the system checks labels before the value may leave or cause an action.
- **Memory-safety bug**: reading or writing memory the program does not own. Common in C and C++.

## 1. What went wrong, 2024 to 2026 (beyond 09)

- **Stolen passwords, no second factor.** In 2024 attackers logged into Snowflake customer accounts with passwords taken by infostealer malware. "Every incident Mandiant responded to … was traced back to compromised customer credentials"; the first account "did not have multi-factor authentication (MFA) enabled"; about 165 organisations were notified https://cloud.google.com/blog/topics/threat-intelligence/unc5537-snowflake-data-theft-extortion.
- **Stolen integration tokens.** In August 2025 OAuth tokens stolen from the Salesloft Drift integration were used to export Salesforce data. The aim was to "harvest credentials": the attacker searched the rows for AWS keys, passwords and Snowflake tokens, and deleted its query jobs, but "logs were not impacted" https://cloud.google.com/blog/topics/threat-intelligence/data-theft-salesforce-instances-via-salesloft-drift.
- **Trusted tool, untrusted data.** A public GitHub issue made an agent using the official GitHub MCP server copy private repositories into a public pull request. The tools were sound; the token covered public and private repositories alike https://invariantlabs.ai/blog/mcp-github-vulnerability.
- **"Read-only" that was not.** Anthropic's reference Postgres MCP server ran agent SQL in a read-only transaction but accepted several statements at once, so `COMMIT;` followed by a write escaped it https://securitylabs.datadoghq.com/articles/mcp-vulnerability-case-study-SQL-injection-in-the-postgresql-mcp-server/.
- **Poisoned tools.** An npm package impersonating Postmark's MCP server was clean for 15 versions; version 1.0.16 quietly copied every sent email to the attacker https://postmarkapp.com/blog/information-regarding-malicious-postmark-mcp-package. A malicious change to the Amazon Q Developer extension told the agent to delete files and cloud resources https://aws.amazon.com/security/security-bulletins/AWS-2025-015/.
- **A database vendor's own agent, 2026.** Snowflake's Cortex Code agent treated `cat` as safe to run without approval but did not check commands hidden in process substitution. A malicious README could run a script outside the sandbox that used the agent's cached Snowflake tokens to read and drop tables. Fixed 2026-02-28 https://www.promptarmor.com/resources/snowflake-ai-escapes-sandbox-and-executes-malware.

Approval rules, read-only modes and sandboxes all failed the same way: **a filter that reads text to judge an action is weaker than a limit on what the credential can do** (inference).

## 2. The lethal trifecta, applied to a database

Simon Willison's "lethal trifecta" is access to private data, exposure to untrusted content, and "the ability to externally communicate". An agent with all three can be tricked into sending the data to an attacker, because "LLMs are unable to reliably distinguish the importance of instructions based on where they came from" https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/.

A shared database supplies all three by itself (inference):

- **Private data** is what it stores.
- **Untrusted content** is any row written by a customer, a scraper or another agent. With many agents, each agent's output is untrusted input to the rest.
- **A way out** is any write that someone else can read. The Supabase leak in 09 worked exactly so: the agent wrote secrets into a ticket the attacker could read. Taking web access away from the agent does not close this channel.

Consequences for the design (inference):

1. Only the database knows, per value, **who wrote it and whether it is trusted**. The harness sees an unlabelled blob of results.
2. Only the database knows **who can read what is about to be written**, so only it can refuse a write of secret data into a widely readable place.
3. Since injection cannot be reliably detected (section 5), a session that has read untrusted rows should lose the right to touch secret rows or write where untrusted parties read, until a person or a fixed plan restores it. CaMeL and Fides do this in the agent's planner; I found nothing that does it inside a database.

## 3. Defences, and where each can live

**Least privilege and short-lived credentials.** Every incident above had a credential broader or longer-lived than its task. The MCP specification now says servers "MUST NOT accept any tokens that were not explicitly issued for the MCP server" https://modelcontextprotocol.io/specification/draft/basic/authorization/security-considerations. That binds server authors, not attackers.

**Capabilities.** Eclipse Biscuit tokens support "offline attenuation": a holder adds restrictions, written in the small logic language Datalog, without asking the issuer https://www.biscuitsec.org/. A grant can be cut to "these rows, read only, ten minutes" before an agent gets it. Enforcement must sit where the data is.

**Keeping untrusted data from steering actions.** CaMeL has a privileged model write a plan from the user's request alone and runs it in its own interpreter; a quarantined model reads untrusted data, which "can never impact the program flow", and capabilities on values block forbidden flows at tool calls. It solved 77% of AgentDojo benchmark tasks "with provable security", against 84% undefended https://arxiv.org/abs/2503.18813. Microsoft's Fides tracks confidentiality and integrity labels and "deterministically enforces security policies" https://arxiv.org/abs/2505.23643. A twelve-author paper gives six patterns resting on one rule: once untrusted input is read, it must not be able to trigger consequential actions https://arxiv.org/abs/2506.08837.

**IFC inside a database** already exists in research. IFDB (2013) added row labels to PostgreSQL, caught real leaks in two ported web applications, and measured throughput equal to PostgreSQL on a real application and "about 1% lower" on a TPC-C-like benchmark https://dl.acm.org/doi/10.1145/2465351.2465357. It predates agents and I found no adoption.

**Approval, undo and audit.** Cortex Code shows approval decided by reading command text can be dodged; approval should bind to a computed change ("these 40 rows"), not a description of it (inference). Undo protects only if the agent's credential cannot also delete the history; PocketOS lost backups with the volume (inference from 09). Audit helps only if the audited actor cannot edit it; the Drift theft was traceable because logs survived. Amazon's ledger database with cryptographic verification, QLDB, reached end of support on 2025-07-31 https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html.

**Encryption.** At rest, it stops theft of disks and backups, not theft of a login, since the database decrypts for whoever logs in. In use, it relies on trusted execution environments (TEEs), hardware enclaves that hide memory from the machine's owner. TEE.fail (2025) used a cheap DDR5 memory-bus interposer to extract attestation keys from Intel SGX and TDX and to break AMD SEV-SNP https://tee.fail/. Vendors exclude physical attacks from their threat model, so this marks the edge of the promise.

## 4. Attacks on the engine itself

An injected agent is an attacker holding a valid login and sending varied queries, so engine bugs reachable after login matter more than before (inference).

- **Wire protocol, before login.** MongoBleed (CVE-2025-14847, December 2025): mismatched length fields in zlib-compressed headers let "an unauthenticated client" read uninitialised heap memory, MongoDB 3.6 to 8.2 https://nvd.nist.gov/vuln/detail/CVE-2025-14847.
- **Embedded scripting.** RediShell (CVE-2025-49844): a use-after-free in Redis's Lua interpreter leading to code execution on the host. It needs a login, but Wiz counts about 60,000 internet-facing Redis instances with no authentication (security vendor claim) https://www.wiz.io/blog/wiz-research-redis-rce-cve-2025-49844.
- **Quoting.** PostgreSQL's libpq escaping functions missed quotes in text with invalid encoding (CVE-2025-1094) https://www.postgresql.org/support/security/CVE-2025-1094/; Rapid7 tied it to real attacks via BeyondTrust https://www.rapid7.com/blog/post/2025/02/13/cve-2025-1094-postgresql-psql-sql-injection-fixed/.
- **Prompt to SQL.** In LangChain applications, all seven models tested could be led to generate harmful SQL https://arxiv.org/abs/2308.01990.
- **Found by an AI first.** Google says its Big Sleep agent found SQLite CVE-2025-6965, "known only to threat actors", before it was used (vendor claim) https://cloud.google.com/blog/products/identity-security/cloud-ciso-perspectives-our-big-sleep-agent-makes-big-leap.
- **Dependencies.** The 2024 xz backdoor put a compression library on the server's path under a patient attacker's control https://www.openwall.com/lists/oss-security/2024/03/29/4.

**What the safest engines do.** SQLite says it "should never crash, overflow a buffer, leak memory … even when presented with maliciously malformed SQL inputs or database files", backed by heavy fuzzing. For untrusted SQL it advises a defensive mode, far lower limits (expression depth 10 instead of 1,000; no attached databases), and an authoriser callback that rejects any statement outside an allowed set https://www.sqlite.org/security.html. That authoriser is a per-statement capability check inside the engine.

**Memory-safe languages are the measured fix.** On Android, memory-safety flaws fell from 76% of vulnerabilities in 2019 to 24% in 2024 as new code moved to memory-safe languages (vendor data) https://security.googleblog.com/2024/09/eliminating-memory-safety-vulnerabilities-Android.html. MongoBleed and RediShell are this class; the quoting bug and the read-only bypass are not (inference).

## 5. Proven, measured, and advice

**Proven:** CaMeL and Fides guarantee, under stated assumptions, that untrusted data cannot choose actions. They do not prove the policy is right.

**Measured:**

- NIST's AI institute raised agent-hijack success on held-out tasks from 11% to 81% with tuned attacks, and retrying each attack 25 times raised the average from 57% to 80% https://www.nist.gov/news-events/news/2025/01/technical-blog-strengthening-ai-agent-hijacking-evaluations.
- Adaptive attacks bypassed 12 published defences, most "with attack success rate above 90%", where "the majority of defenses originally reported near-zero" https://arxiv.org/abs/2510.09023.
- IFDB's row labels cost about 1% throughput.

**Advice only:** the OWASP Top 10 for Agentic Applications (December 2025) puts goal hijack, tool misuse, identity and privilege abuse, and agentic supply chain first https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/. NIST's May 2026 summary of responses on agent security found agreement that existing principles "will require adaptation", and no standard yet https://www.nist.gov/publications/summary-analysis-responses-request-information-regarding-security-considerations-ai. I found no measurement of how much least privilege, approval or undo reduces harm from agents.

The measurements point one way: **detecting injection is a race the defender loses; limiting what an injected agent can do holds.**

## 6. What Mo's capability model covers, and what it does not

In Mo every outside effect goes through a capability passed in, which can be narrowed and faked in tests (`~/code/mo/docs/agent-guide.md`, sections 11 and 12.4). Inference from that:

**Covers.** The database program cannot reach a file, socket or process it was not handed, so a parser bug or poisoned dependency cannot phone home without a network capability (the xz and postmark-mcp class). Narrowing is attenuation, Biscuit's idea in the language. Fakes make every effect testable under simulation (see 08).

**Does not cover.**

- **Agents' authority over data.** Mo's capabilities govern the program's effects on its host. Which agent may read which row is the database's own policy, built as data: row labels and per-agent grants.
- **The trifecta through the database.** A write another agent reads is not an outside effect, so no Mo capability stops it.
- **Prompt injection**, which happens in the model, and **credential theft** from clients.
- **Bugs below the language.** Mo programs are memory-safe; the C17 VM, verifier and primitives are not, so they are the engine's memory-safety boundary.

## Summary table

| Defence | What it stops | What pays for it | Where it must live |
|---|---|---|---|
| Short-lived, narrowed grants per agent task | Over-broad tokens (GitHub MCP, PocketOS); damage from stolen tokens | Issuing and renewing grants; tasks that fail when a grant expires | Inside (enforcing); harness (requesting) |
| Row labels: writer, trust, readers | Trifecta exfiltration through writes; agents trusting each other's output | A check per read and write (IFDB: about 1%); policies to write | Inside |
| Session tainting after untrusted reads | Injected instructions acting on secret data | Mixed tasks need a fixed plan or a person | Inside, with planner in harness |
| Plan-then-execute planner (CaMeL, Fides) | Untrusted data choosing actions | About 7 points of task success (CaMeL); a custom interpreter | Harness |
| Approval bound to a computed change, plus delay | Destructive operations; disguised commands | Human time; latency | Inside (holding the change); beside (the person) |
| History the agent cannot delete | Lost data and backups (PocketOS, Replit) | Storage; a second authority | Inside, with copies beside |
| Append-only audit tied to agent and task | Hidden theft (Drift); unexplained changes | Storage; privacy of the log | Inside |
| Statement authoriser and low input limits | Query-language injection; read-only bypass | Fewer allowed statement forms | Inside |
| Memory-safe engine; no parsing before login | MongoBleed and RediShell class | A safe language; fuzzing compute | Inside |
| MFA and network allow lists | Stolen passwords (Snowflake 2024) | Client friction | Beside |
| Encryption at rest / in use | Stolen disks / curious operators | Key management / hardware, still open to physical attack | Inside / beside |

## Ideas worth borrowing

- **SQLite's authoriser** as the shape of an agent grant: each statement checked against the agent's capability. Cost: the grant language must be small enough for an agent to read and a person to approve.
- **IFDB's row labels**, extended with "written by which agent, from which input". Cost: labels must survive joins and travel with results.
- **CaMeL's split of plan and data** as a database feature: an agent submits a fixed plan with holes that untrusted values fill but cannot change. Cost: less flexible agents.
- **Biscuit-style attenuation** mapped onto Mo's narrowed capabilities. Cost: offline tokens are harder to revoke.
- **No parsing before authentication**, with the smallest possible pre-login protocol.

## What I could not confirm

- Whether MongoBleed was exploited in the wild; one search result says so, with no primary source found.
- The publication date of the Datadog Postgres MCP write-up.
- Whether any shipping database enforces IFC labels for agents; I found none.
- Any measurement of how much least privilege, approval or undo reduces harm from agents.
- Snowflake's own Cortex Code advisory needs an account; I relied on PromptArmor's report.
- That CVE-2025-6965 was "known only to threat actors" rests on Google alone.
