# Overview

The current synthesis of research files 00 to 09, 20 and 21. It states what the sources say, marks inference, and recommends nothing.

## The families and what separates them

Each family dropped one assumption and pays for it somewhere ([00](../research/00-landscape-overview.md)).

- [Relational and transactional](families/relational-and-transactional.md): tables, SQL, transactions. Engines differ in keeping transactions apart, by [locks](ideas/locks-held-until-commit.md) or [multi-version snapshots](ideas/multi-version-snapshots.md) ([01](../research/01-relational-and-transactional.md)).
- [Analytical and lakehouse](families/analytical-and-lakehouse.md): [columns](ideas/column-storage.md) and [write-once pieces merged later](ideas/immutable-pieces-with-background-merge.md) ([02](../research/02-analytical-and-specialised.md)).
- [Specialised stores](families/specialised-stores.md): speed for one question, with a weaker or later answer ([02](../research/02-analytical-and-specialised.md)).
- [Key-value, document and distributed](families/key-value-document-and-distributed.md): dropped transactions, schemas and joins for scale, then took some back ([03](../research/03-key-value-document-distributed.md)).
- [Models that lost or stayed niche](families/models-that-lost-or-stayed-niche.md): hierarchical, object, graph, triples, Datalog ([04](../research/04-models-that-lost-or-stayed-niche.md)).
- [Databases that keep history](families/databases-that-keep-history.md): no change in place ([05](../research/05-databases-that-keep-history.md)).
- [Versioned data and branching](families/versioned-data-and-branching.md) dropped linear history; [replication and sync](families/replication-and-sync.md) lets copies write apart and merge later ([06](../research/06-divergent-copies-and-merging.md)).
- [Code inside the database](families/code-inside-the-database.md): code and data in one place ([07](../research/07-code-inside-the-database.md)).
- [Correctness-first](families/correctness-first.md): tested in a simulated world one seed controls ([08](../research/08-correctness-first-databases.md)).

## Tradeoffs that recur

- Full isolation costs blocking, retries or clock waits, and level names cannot be trusted without a [checker](ideas/guarantees-checked-by-a-tool.md) ([01](../research/01-relational-and-transactional.md)).
- A client thinking inside an open transaction harms every engine ([01](../research/01-relational-and-transactional.md), [time limits](ideas/transaction-time-limits.md)).
- Every attempt to [join analytics and transactions](ideas/transactions-and-analytics-together.md) keeps two copies ([02](../research/02-analytical-and-specialised.md)).
- Stores that stay writable in a network split settle conflicts later, out of sight, and keep the guarantee in settings, not [in the reply](ideas/consistency-reported-to-the-caller.md) ([03](../research/03-key-value-document-distributed.md)).
- [Determinism](ideas/deterministic-functions-inside-transactions.md) and [known reads and writes](ideas/read-and-write-sets-known-up-front.md) pay for most gains of code beside data ([07](../research/07-code-inside-the-database.md)).
- Every store with unlimited history added a way to [forget](ideas/deleting-personal-data-from-history.md) ([05](../research/05-databases-that-keep-history.md)).
- A merge decides alone only when any two valid copies combine into a valid one ([data types that merge themselves](ideas/data-types-that-merge-themselves.md)), and [branching](ideas/copy-on-write-branches.md) speed trades against read speed ([06](../research/06-divergent-copies-and-merging.md)).
- Hiding data from a reader who writes queries fails: [masking](ideas/dynamic-masking.md) falls to filtering, agents [re-identify](ideas/re-identification-by-linking.md) masked text, and only [differential privacy](ideas/differential-privacy.md) survives combined queries, for totals only ([20](../research/20-keeping-sensitive-data-from-agents.md)).
- Detecting injected instructions loses to adaptive attacks; [narrowing what a credential can do](ideas/attenuated-capabilities.md) holds ([21](../research/21-security-of-a-database-agents-use.md)).

## Gaps no system fills

Each lists the files for it and against it.

1. [Merging by meaning](ideas/merging-by-meaning.md), between [branches that reconcile with each other](ideas/branches-that-reconcile-with-each-other.md). For: 00, 06, 09. Against: [Bayou](systems/bayou.md)'s merge procedures (06) and [GemStone](systems/gemstone.md)'s reduced-conflict classes (04).
2. [Recording why a write happened](ideas/recording-why-a-write-happened.md). For: 00, 05, 09, 21. Against, partly: [Datomic](systems/datomic.md) and [XTDB](systems/xtdb.md) allow optional, unchecked transaction metadata (05); [Dolt](systems/dolt.md) commit messages are free text (09).
3. [Rules enforced across transactions](ideas/invariants-the-database-enforces.md). For: 00, as inference; only [TigerBeetle](systems/tigerbeetle.md) enforces rich rules, for one domain. Against: Datomic and XTDB checks (05), Dolt's merge-time constraints (06), [TypeDB](systems/typedb.md) schema constraints (04).
4. [Writes held for approval](ideas/writes-held-for-approval.md) inside the engine. For: 09, 21. Against, partly: [Neon](systems/neon.md)'s MCP server and Dolt and [lakeFS](systems/lakefs.md) merge checks, all beside the engine (06, 09).
5. [Access scoped to what an agent may do](ideas/scoped-access-for-agents.md), readable by the agent. For: 00, 09, 21. Against, partly: [SQLite](systems/sqlite.md)'s [statement authoriser](ideas/statement-authoriser.md) (21); Supabase's read-only mode (09).
6. [Simulating the user's own workload](ideas/simulating-the-users-own-workload.md). For: 00, 08. Against, partly: [FoundationDB](systems/foundationdb.md)'s client testing (00).
7. [Read and write sets](ideas/read-and-write-sets-known-up-front.md) derived from code before it runs. For: 07, as inference.
8. [Labels that follow data](ideas/information-flow-labels.md) on every exit. For: 20, 21. Against, partly: [Snowflake](systems/snowflake.md) tag propagation and [PostgreSQL Anonymizer](systems/postgresql-anonymizer.md) (20); [IFDB](systems/ifdb.md) did it in 2013 and never shipped.
9. Breaking the [lethal trifecta inside a shared database](ideas/lethal-trifecta-in-a-shared-database.md), for example by [narrowing a session after untrusted reads](ideas/session-tainting-after-untrusted-reads.md). For: 21, as inference. Against, partly: [CaMeL](systems/camel.md) does it [in the agent's planner](ideas/plan-then-execute-agents.md) (21).

## Evidence against building a new database

- Every agent incident found came from credentials, least privilege or text filters, none from a missing concurrency feature; better permissions and gates might be enough ([09](../research/09-agents-and-databases-today.md), [21](../research/21-security-of-a-database-agents-use.md)).
- Neon's figure that agents create 80% of its databases (vendor claim) is mostly short-lived private databases, not agents sharing one ([09](../research/09-agents-and-databases-today.md)).
- The Berkeley paper expects agent query volume to be the bottleneck, against putting speed second ([09](../research/09-agents-and-databases-today.md)).
- "Model Eats the Stack" argues layers built for agents get absorbed by models ([09](../research/09-agents-and-databases-today.md)).
- Features layer onto existing engines: [Chronos](systems/chronos.md) adds branches over [PostgreSQL](systems/postgresql.md) ([09](../research/09-agents-and-databases-today.md)); IFDB added labels to PostgreSQL at about 1% cost ([21](../research/21-security-of-a-database-agents-use.md)); approval and scoping ship as proxies ([09](../research/09-agents-and-databases-today.md)).
- A new query language starts weak with models: correct SPARQL 3.3% of the time against 47% for SQL, though [worked examples](ideas/schema-and-examples-for-agents.md) lifted it to 76% ([04](../research/04-models-that-lost-or-stayed-niche.md)).
- [Amazon QLDB](systems/amazon-qldb.md) was withdrawn; research 05 infers customers wanted history without a separate database and query language ([05](../research/05-databases-that-keep-history.md)).
- [Stored procedures](ideas/stored-procedures-and-triggers.md) failed on version control, testing and deployment ([07](../research/07-code-inside-the-database.md)).
- A new engine is new attack surface. Injected agents hold valid logins, so engine bugs like [MongoDB](systems/mongodb.md)'s MongoBleed and [Redis](systems/redis.md)'s RediShell matter more, and Mo's C VM is its memory-safety boundary (inference, [21](../research/21-security-of-a-database-agents-use.md), [memory-safe engine](ideas/memory-safe-engine.md)).
