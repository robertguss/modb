# Log

## [2026-11-13] source | research/00-landscape-overview.md

A first pass over every family of databases and the 2024 to 2026 wave. Ingested in the batch compilation of research/00 to 09 below.

## [2026-11-13] source | research/09-agents-and-databases-today.md

What exists for many agents working on the same data, the recorded failures, and the gaps. Ingested in the batch compilation of research/00 to 09 below.

## [2026-11-13] ingest | research/00 to research/09, batch compilation

Compiled research/00 to research/09 into 103 pages from one page plan: 50 in `systems/`, 43 in `ideas/`, 10 in `families/`. Each page cites the research files it rests on, and the places where those files disagree are recorded under Disagreements.

## [2026-11-13] ingest | research/20-keeping-sensitive-data-from-agents.md

Masking, pseudonyms, legal de-identification, re-identification by agents, and sensitivity labels.

- New ideas: [dynamic-masking](ideas/dynamic-masking.md), [masked-copies](ideas/masked-copies.md), [row-and-column-security](ideas/row-and-column-security.md), [tokenization-vaults](ideas/tokenization-vaults.md), [redaction-gateways](ideas/redaction-gateways.md), [consistent-pseudonyms](ideas/consistent-pseudonyms.md), [k-anonymity](ideas/k-anonymity.md), [differential-privacy](ideas/differential-privacy.md), [synthetic-data](ideas/synthetic-data.md), [confidential-computing](ideas/confidential-computing.md), [re-identification-by-linking](ideas/re-identification-by-linking.md), [legal-de-identification](ideas/legal-de-identification.md), [information-flow-labels](ideas/information-flow-labels.md).
- New systems: [postgresql-anonymizer](systems/postgresql-anonymizer.md), [ifdb](systems/ifdb.md).
- Updated: [snowflake](systems/snowflake.md), [neon](systems/neon.md), [oracle](systems/oracle.md), [postgresql](systems/postgresql.md), [scoped-access-for-agents](ideas/scoped-access-for-agents.md), [deleting-personal-data-from-history](ideas/deleting-personal-data-from-history.md), [relational-and-transactional](families/relational-and-transactional.md), [versioned-data-and-branching](families/versioned-data-and-branching.md).
- Disagreements recorded: EDPB guidelines against the *EDPS v SRB* judgment on pseudonymised data; whether AI vendors handling PHI are business associates.
- No new family: the file treats no group of databases as a family.

## [2026-11-13] ingest | research/21-security-of-a-database-agents-use.md

Incidents 2024 to 2026, the lethal trifecta, defences and where each lives, engine bugs, and what Mo's capabilities cover.

- New ideas: [lethal-trifecta-in-a-shared-database](ideas/lethal-trifecta-in-a-shared-database.md), [session-tainting-after-untrusted-reads](ideas/session-tainting-after-untrusted-reads.md), [plan-then-execute-agents](ideas/plan-then-execute-agents.md), [attenuated-capabilities](ideas/attenuated-capabilities.md), [statement-authoriser](ideas/statement-authoriser.md), [history-and-audit-the-agent-cannot-erase](ideas/history-and-audit-the-agent-cannot-erase.md), [memory-safe-engine](ideas/memory-safe-engine.md).
- New system: [camel](systems/camel.md).
- Updated: [confidential-computing](ideas/confidential-computing.md) (retitled to cover encryption at rest), [information-flow-labels](ideas/information-flow-labels.md), [ifdb](systems/ifdb.md), [writes-held-for-approval](ideas/writes-held-for-approval.md), [scoped-access-for-agents](ideas/scoped-access-for-agents.md), [recording-why-a-write-happened](ideas/recording-why-a-write-happened.md), [amazon-qldb](systems/amazon-qldb.md), [snowflake](systems/snowflake.md), [postgresql](systems/postgresql.md), [sqlite](systems/sqlite.md), [mongodb](systems/mongodb.md), [redis](systems/redis.md).
- Disagreement recorded: research 20 and 21 describe different targets for TEE.fail.
- Wrote [overview.md](overview.md) and [index.md](index.md) after both ingests. The wiki now has 126 pages: 53 systems, 63 ideas, 10 families.

## [2026-11-13] lint | First lint of the compiled wiki

Mechanical checks by script over all 129 files: no broken links, no page missing from the index, no page without Sources, no section out of order or misnamed.

Fixed:

- [confidential-computing](ideas/confidential-computing.md) had no inbound link except the index; linked from [tokenization-vaults](ideas/tokenization-vaults.md).
- [versioned-data-and-branching](families/versioned-data-and-branching.md) stated as fact that Neon and Xata cannot merge, while research 06 and 09 differ on how sure that is; it now says so and points to the disagreement.
- "Prompt injection" was named on three pages without a link to where it is explained; linked to [lethal-trifecta-in-a-shared-database](ideas/lethal-trifecta-in-a-shared-database.md).
- [redis](systems/redis.md): disagreement title formatted like the others.
- Checked that all 14 disagreements in the page plan appear under Disagreements on at least one page. They do, along with the Redis threading disagreement and three from research 20 and 21.

Left open:

- No pages for Xata (named on 9 pages), Turso (9), Supabase (7), FIDES (4), ScramDB (4) or Yjs (4). The sources give each too little for a page of their own, or mention them only.
- Raft and consensus (5 pages) and MCP (11 pages) have no page.
- A heuristic scan found about 160 paragraphs with no inline citation. Those checked sit under a lead line or parent bullet that cites ("From research 02:", "same page"); not every one was checked.
- Claims the sources could not confirm stay unconfirmed: whether the EDPB revised its pseudonymisation guidelines after *SRB*, whether MongoBleed was exploited, the Datadog write-up's date, how far Snowflake tag propagation reaches, and the other items in each file's "What I could not confirm".
- What TEE.fail broke cannot be settled from the research files alone.
