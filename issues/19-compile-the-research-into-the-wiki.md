# Compile the research into the wiki

Type: task
Status: resolved
Blocked by: [Relational and transactional databases](01-relational-and-transactional.md), [Analytical and specialised stores](02-analytical-and-specialised.md), [Key-value, document and distributed stores](03-key-value-document-distributed.md), [Models that lost or stayed niche](04-models-that-lost-or-stayed-niche.md), [Databases that keep history](05-databases-that-keep-history.md), [Divergent copies and merging](06-divergent-copies-and-merging.md), [Code inside the database, and databases inside a language](07-code-inside-the-database.md), [Correctness-first databases](08-correctness-first-databases.md)

## Question

AFK. Ingest `research/00` to `research/09`, then `research/20` and `research/21` once they exist, into the wiki, one file at a time, by the Ingest workflow in `AGENTS.md`: a page for every system and idea, the family pages, `wiki/overview.md`, the index and the log. Then run one Lint pass.

The answer records how many pages exist, and every disagreement between sources that the ingest found.

## Answer

The wiki holds 126 pages, plus [overview](../wiki/overview.md), [index](../wiki/index.md) and [log](../wiki/log.md):

| Folder | Pages |
| --- | --- |
| `wiki/systems/` | 53 |
| `wiki/ideas/` | 63 |
| `wiki/families/` | 10 |

Research 00 to 09 gave 103 pages (50 systems, 43 ideas, 10 families). Research 20 added 13 ideas and 2 systems; research 21 added 7 ideas and 1 system. One lint pass followed; the [log](../wiki/log.md) lists what it fixed and what it left open.

Disagreements between sources, each with a page that records it:

1. TigerBeetle's simulator running "24/7 on 1024 cores": a vendor claim 00 could not confirm, stated as a strength in 08. [tigerbeetle](../wiki/systems/tigerbeetle.md)
2. Whether history-keeping stores record who made a change: 00 says they record who wrote it; 05 says QLDB, Snowflake and SQL:2011 record no user, Oracle a shared logon, Datomic and XTDB only optional metadata. [recording-why-a-write-happened](../wiki/ideas/recording-why-a-write-happened.md)
3. Whether anything merges by intent: 00 says nothing does; 06 describes Bayou and 04 GemStone's reduced-conflict classes. [merging-by-meaning](../wiki/ideas/merging-by-meaning.md)
4. Whether any general system enforces declared invariants across transactions: 00 says no; 05, 06 and 04 describe Datomic, XTDB, Dolt and TypeDB checks. [invariants-the-database-enforces](../wiki/ideas/invariants-the-database-enforces.md)
5. Evidence that agents hold transactions open: 01 found no study; 08 and 09 cite a 2026 workshop paper. [transaction-time-limits](../wiki/ideas/transaction-time-limits.md)
6. Whether Neon can merge a branch back, and whether Xata can: 06 states it as fact, 09 marks it as its own reading, and 06 is unsure about Xata. [copy-on-write-branches](../wiki/ideas/copy-on-write-branches.md)
7. Turso's concurrent writes: beta in 00, no caveat in 09. [sqlite](../wiki/systems/sqlite.md)
8. Durable Objects query latency: unmarked in 00, a vendor claim in 07. [cloudflare-durable-objects](../wiki/systems/cloudflare-durable-objects.md)
9. Graph databases against relational systems on traversal: 00 from a Neo4j vendor page, 04 from a 2024 survey it did not fully read. [neo4j](../wiki/systems/neo4j.md)
10. How DuckDB's in-process design is sourced: 00 only through DuckLake, 02 from DuckDB's docs. [duckdb](../wiki/systems/duckdb.md)
11. Whether Datomic ever removes data: 00 says never; 05 describes `noHistory` and excision. [datomic](../wiki/systems/datomic.md)
12. Whether database MCP servers have guardrails: 00 reports thin proxies; 09 describes Neon's and Supabase's gates. [scoped-access-for-agents](../wiki/ideas/scoped-access-for-agents.md)
13. Agents as CRDT peers for conflicting writes: a best mechanism in 09; unable to reject a write in 06. [electric](../wiki/systems/electric.md)
14. Source of Neon's 50x rollback figure: uncited in 06, the Berkeley paper in 09. [neon](../wiki/systems/neon.md)
15. How much of Redis runs on its one thread: all command work in 03; worker and I/O threads too in 00. [redis](../wiki/systems/redis.md)
16. What TEE.fail broke: Intel TDX, AMD SEV-SNP and NVIDIA GPUs in 20; Intel SGX and TDX and AMD SEV-SNP in 21. [confidential-computing](../wiki/ideas/confidential-computing.md)
17. Whether pseudonymised data stays personal data: the EDPB's 2025 guidelines say yes; the *EDPS v SRB* judgment says not for every recipient (both in 20). [legal-de-identification](../wiki/ideas/legal-de-identification.md)
18. Whether AI vendors handling PHI are business associates: inferred in 20, reported by a consultancy with no primary source. [legal-de-identification](../wiki/ideas/legal-de-identification.md)
