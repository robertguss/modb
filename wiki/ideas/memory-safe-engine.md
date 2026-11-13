# A memory-safe engine that parses nothing before login

The database engine is written in a memory-safe language, and it reads as little as possible from a client before that client has proved who it is. A *memory-safety bug* is reading or writing memory the program does not own; it is common in C and C++.

## What it is

Two defences from research 21: a memory-safe engine, and no parsing before authentication, with the smallest possible pre-login protocol ([21](../../research/21-security-of-a-database-agents-use.md)).

## The problem it solves

An injected agent is an attacker holding a valid login and sending varied queries, so engine bugs reachable after login matter more than before (inference, [21](../../research/21-security-of-a-database-agents-use.md)). Recent engine bugs:

- **Before login.** MongoBleed (CVE-2025-14847, December 2025): mismatched length fields in zlib-compressed headers let "an unauthenticated client" read uninitialised heap memory in [MongoDB](../systems/mongodb.md) 3.6 to 8.2 (https://nvd.nist.gov/vuln/detail/CVE-2025-14847). Whether it was exploited in the wild is not confirmed ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Embedded scripting.** RediShell (CVE-2025-49844): a use-after-free in [Redis](../systems/redis.md)'s Lua interpreter leading to code execution on the host. It needs a login, but Wiz counts about 60,000 internet-facing Redis instances with no authentication (security vendor claim, https://www.wiz.io/blog/wiz-research-redis-rce-cve-2025-49844).
- **Dependencies.** The 2024 xz backdoor put a compression library on the server's path under a patient attacker's control (https://www.openwall.com/lists/oss-security/2024/03/29/4).

Memory-safe languages are the measured fix. On Android, memory-safety flaws fell from 76% of vulnerabilities in 2019 to 24% in 2024 as new code moved to memory-safe languages (vendor data, https://security.googleblog.com/2024/09/eliminating-memory-safety-vulnerabilities-Android.html). MongoBleed and RediShell are this class; [PostgreSQL](../systems/postgresql.md)'s quoting bug and the Postgres MCP read-only bypass are not (inference, [21](../../research/21-security-of-a-database-agents-use.md)).

## What it costs

- **A safe language, and fuzzing compute** ([21](../../research/21-security-of-a-database-agents-use.md)). [SQLite](../systems/sqlite.md) is the example of the fuzzing route: it says it "should never crash, overflow a buffer, leak memory … even when presented with maliciously malformed SQL inputs or database files", backed by heavy fuzzing (https://www.sqlite.org/security.html).
- **Mo.** Mo programs are memory-safe, but the C17 VM, verifier and primitives are not, so they are the engine's memory-safety boundary (inference, [21](../../research/21-security-of-a-database-agents-use.md)). Mo's capabilities also mean a parser bug or poisoned dependency cannot phone home without a network capability, the xz and postmark-mcp class (inference, [21](../../research/21-security-of-a-database-agents-use.md)).

## Systems that use it

Research 21 names none by language. [SQLite](../systems/sqlite.md) is its example of an engine hardened for hostile input (https://www.sqlite.org/security.html).

## Sources

- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- https://nvd.nist.gov/vuln/detail/CVE-2025-14847
- https://www.wiz.io/blog/wiz-research-redis-rce-cve-2025-49844
- https://www.openwall.com/lists/oss-security/2024/03/29/4
- https://security.googleblog.com/2024/09/eliminating-memory-safety-vulnerabilities-Android.html
- https://www.sqlite.org/security.html
