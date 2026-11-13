# Index

Every page in the wiki, with one line on each. Start with the [overview](overview.md); the [log](log.md) records each operation.

## Families (10)

- [Analytical stores and lakehouse formats](families/analytical-and-lakehouse.md): Databases and file formats built for few, large reads over many rows rather than many small writes.
- [Code inside the database, and databases inside a language](families/code-inside-the-database.md): Systems where the database runs the application's functions, or a language's own objects become the database.
- [Correctness-first databases and the tools that test them](families/correctness-first.md): Databases tested in a simulated world one random seed controls, and the outside tools that check their promises.
- [Databases that keep history](families/databases-that-keep-history.md): These databases keep old versions of data instead of overwriting them, so they can answer "what was true then?" and "what changed?".
- [Diverging replicas, self-merging data and sync engines](families/replication-and-sync.md): Systems in which several copies of the same data accept writes separately and are brought back together later.
- [Key-value, document and distributed stores](families/key-value-document-and-distributed.md): These stores gave up parts of the relational database (multi-item transactions, schemas, joins) to gain speed, scale or availability, and most later took some of it back.
- [Models that lost to relational or stayed niche](families/models-that-lost-or-stayed-niche.md): These are the data models that competed with relational databases and either lost (hierarchical, network, object, XML) or kept a niche (graph, triple stores, Datalog).
- [Relational and transactional databases](families/relational-and-transactional.md): Databases that store data as tables, answer questions in a declarative language (SQL), and group reads and writes into **transactions**: units that succeed or fail as a whole.
- [Time-series, search, vector and spatial stores](families/specialised-stores.md): Stores and indexes built for one kind of question: metrics over time, documents by their words, items nearest in meaning, or shapes near a place.
- [Versioned data: branch, diff and merge](families/versioned-data-and-branching.md): These systems bring Git's workflow to data: make a branch, change it, review the diff, and merge it or throw it away.

## Systems (53)

- [Amazon QLDB](systems/amazon-qldb.md): Amazon QLDB was a ledger database: a document store whose history could be proven unaltered.
- [Antithesis](systems/antithesis.md): Antithesis sells deterministic simulation testing as a service.
- [Apache Cassandra](systems/cassandra.md): Cassandra puts Bigtable's table layout on Dynamo's leaderless replication.
- [Apache Iceberg](systems/iceberg.md): Apache Iceberg is an open table format.
- [Apache Kafka](systems/kafka.md): Kafka is a partitioned, replicated, append-only log.
- [Automerge](systems/automerge.md): Automerge is a library of data types that merge themselves (CRDTs), for collaborative and offline-first apps.
- [Bayou](systems/bayou.md): Bayou is a replicated storage system from Xerox PARC, described at SOSP 1995.
- [Berkeley DB](systems/berkeley-db.md): Berkeley DB is a key-value store that is a library linked into the program, not a server.
- [Bigtable](systems/bigtable.md): Bigtable is Google's sorted map from (row, column, time) to bytes, spread over many servers.
- [CaMeL (agent defence, research)](systems/camel.md): CaMeL is a 2025 research design for running an AI agent so that untrusted data it reads cannot change what it does.
- [Chronos (MIT research system)](systems/chronos.md): Chronos is a 2026 research system from MIT that adds branches on top of existing databases without changing them.
- [ClickHouse](systems/clickhouse.md): ClickHouse is a column-oriented analytical database.
- [Cloudflare Durable Objects](systems/cloudflare-durable-objects.md): Durable Objects are Cloudflare's single-threaded actors, each with its own private SQLite database running in the same thread as the object's code (Cloudflare, 2024-09-26; research 07).
- [CockroachDB](systems/cockroachdb.md): CockroachDB is a distributed SQL database that spreads the relational model over many machines.
- [Convex](systems/convex.md): Convex is a database that is also the application server.
- [CouchDB](systems/couchdb.md): CouchDB stores JSON documents with revision IDs and can replicate between any two copies, including offline ones.
- [Datomic](systems/datomic.md): Datomic is a database that stores facts and never edits them in place, so any past moment can be queried.
- [Dolt](systems/dolt.md): Dolt is a SQL database with Git's workflow for tables: branch, change, review the diff, merge.
- [DuckDB](systems/duckdb.md): DuckDB is an analytical SQL database that runs as a library inside one process, not as a server.
- [DuckLake](systems/ducklake.md): DuckLake is a lakehouse format that keeps table data as Parquet files but puts all metadata in a SQL database.
- [Dynamo and DynamoDB](systems/dynamodb.md): Dynamo was Amazon's key-value store built never to refuse a write, at the price of isolation.
- [Elasticsearch (Lucene)](systems/elasticsearch.md): Elasticsearch is a full-text search engine built on the Lucene library.
- [Electric](systems/electric.md): Electric is a sync engine that copies parts of a Postgres database, called "Shapes", into apps for fast local reads (Electric docs; research 00).
- [Erlang ETS and Mnesia](systems/mnesia.md): ETS is Erlang's built-in in-memory table, and Mnesia is a replicated database built on it and queried from Erlang.
- [FoundationDB](systems/foundationdb.md): FoundationDB is an ordered key-value store with transactions across keys.
- [GemStone/S](systems/gemstone.md): GemStone/S is an object database: a shared, transactional, persistent Smalltalk in which programming-language objects are stored directly.
- [IFDB (MIT research system)](systems/ifdb.md): IFDB is a 2013 research version of PostgreSQL from MIT in which every row carries an information-flow label, and every result carries the labels of what it read.
- [Jepsen](systems/jepsen.md): Jepsen is an independent tester of databases, not a database.
- [KurrentDB (formerly EventStoreDB)](systems/kurrentdb.md): KurrentDB is an *event store*: a database that keeps the list of things that happened, not the current state.
- [lakeFS](systems/lakefs.md): lakeFS gives Git-style branches and merges to files in object storage.
- [Materialize](systems/materialize.md): Materialize is a database that keeps query results up to date as the input data changes, instead of computing them when they are read.
- [MongoDB](systems/mongodb.md): MongoDB is a document database: it stores JSON-like documents and embeds data that is used together.
- [MySQL (InnoDB)](systems/mysql.md): MySQL is a widely used relational database; InnoDB is its transactional storage engine.
- [Neo4j](systems/neo4j.md): Neo4j is a property-graph database: it stores nodes and relationships, both carrying key-value properties, and queries them with the Cypher language.
- [Neon](systems/neon.md): Neon is hosted PostgreSQL with copy-on-write branches.
- [Oracle Database](systems/oracle.md): Oracle Database is a commercial relational row store.
- [pgvector (HNSW indexes)](systems/pgvector.md): pgvector adds similarity search over embeddings to PostgreSQL, using approximate indexes such as HNSW.
- [PostGIS (R-tree indexes)](systems/postgis.md): PostGIS adds spatial data to PostgreSQL: shapes that overlap, or lie near a point or region.
- [PostgreSQL](systems/postgresql.md): PostgreSQL is an open-source relational database: tables queried with SQL, and transactions that succeed or fail as a whole.
- [PostgreSQL Anonymizer](systems/postgresql-anonymizer.md): PostgreSQL Anonymizer is an extension for PostgreSQL that declares masking rules in the schema and applies them to query results, to copies, to replicas or to dumps.
- [Prevayler](systems/prevayler.md): Prevayler is a Java library that keeps all business objects in memory and makes them durable by logging every change as a command.
- [RDF triple stores (SPARQL)](systems/rdf-triple-stores.md): A triple store holds every fact as a *triple*: subject, predicate, object.
- [Redis](systems/redis.md): Redis is an in-memory store of typed data structures such as lists, sets and hashes.
- [RocksDB and LevelDB](systems/rocksdb.md): LevelDB and RocksDB are embedded key-value stores built on log-structured merge trees: writes land in a log and an in-memory table, then in sorted files that background work merges.
- [Snowflake](systems/snowflake.md): Snowflake is a cloud data warehouse.
- [SpacetimeDB](systems/spacetimedb.md): SpacetimeDB is a database that runs application code inside itself.
- [Spanner](systems/spanner.md): Spanner is Google's relational database spread over many machines and data centres, described at OSDI 2012.
- [SQL:2011 temporal tables (SQL Server, MariaDB)](systems/sql-temporal-tables.md): SQL:2011 is the SQL standard that added tables which keep their own history.
- [SQLite](systems/sqlite.md): SQLite is an embedded SQL database: a library inside the application, with no server.
- [TigerBeetle](systems/tigerbeetle.md): TigerBeetle is a ledger database: it stores only accounts and debit/credit transfers between them.
- [TypeDB](systems/typedb.md): TypeDB is a database with a typed entity-relation-attribute model.
- [XTDB](systems/xtdb.md): XTDB is a database in which every table keeps two timelines for each fact.
- [Zero](systems/zero.md): Zero is a sync engine that keeps in each client the subset of rows the app's queries need (Zero docs; research 00).

## Ideas (63)

- [A memory-safe engine that parses nothing before login](ideas/memory-safe-engine.md): The database engine is written in a memory-safe language, and it reads as little as possible from a client before that client has proved who it is.
- [A per-statement check inside the engine](ideas/statement-authoriser.md): The engine checks every statement an agent sends against what that agent is allowed to do, and rejects any statement outside an allowed set.
- [Access scoped to what an agent may do (gap)](ideas/scoped-access-for-agents.md): An agent gets only the access its task needs, and can ask the database what it is allowed to do.
- [Cheap branches that share storage](ideas/copy-on-write-branches.md): A new branch of a database shares storage with its parent until something changes, so making one is nearly free.
- [Checking designs with formal models](ideas/formal-design-models.md): Writing a system's design as a small formal model and letting a tool explore every possible interleaving of it, to find design bugs before or apart from the code.
- [Consistent and keyed pseudonyms](ideas/consistent-pseudonyms.md): *Pseudonymising* replaces an identifier with a stand-in, such as a token or code.
- [Data types that merge themselves, and the rules they can keep](ideas/data-types-that-merge-themselves.md): Data types whose merge is defined in advance, so that copies changed concurrently can always be combined without asking anyone.
- [Deleting personal data from a store that keeps history](ideas/deleting-personal-data-from-history.md): A store that never forgets still has to forget a person when the law requires it.
- [Derived copies fed from one log](ideas/derived-copies-fed-from-one-log.md): One ordered log of changes is the source of truth, and every other form of the data (search indexes, column copies, read models, live query results) is derived by replaying that log.
- [Deterministic functions as transactions](ideas/deterministic-functions-inside-transactions.md): The transaction is a function that the database itself runs, and the function must give the same result every time it runs on the same data.
- [Deterministic simulation and fault-injection testing](ideas/deterministic-simulation-testing.md): *Deterministic simulation testing* (DST) runs the real program in a fake world (clock, network, disk) where every choice comes from one number, the *seed*, so a seed replays its run exactly.
- [Differential privacy](ideas/differential-privacy.md): *Differential privacy* (DP) adds noise to answers, sized so that one person's presence barely moves any answer.
- [Encryption at rest and confidential computing](ideas/confidential-computing.md): Computation runs in a hardware enclave, a *TEE* (trusted execution environment), whose memory the machine's operator cannot read.
- [Facts that are added, never changed](ideas/append-only-facts.md): The database never edits a stored value.
- [Guarantees checked by a tool, not stated by a name](ideas/guarantees-checked-by-a-tool.md): A database's guarantees, such as its isolation level, are shown by a checker that tests recorded histories against a named model, rather than taken on trust from the level's name.
- [History and audit the agent cannot erase](ideas/history-and-audit-the-agent-cannot-erase.md): Undo and audit protect only if the agent whose actions they record cannot delete or edit them.
- [How hidden data is recovered anyway](ideas/re-identification-by-linking.md): Masked, pseudonymised or summarised data can often be tied back to people.
- [k-anonymity](ideas/k-anonymity.md): Values are made coarser, or records dropped, until each record matches at least *k−1* others on every field an attacker could know.
- [Keeping conflicts as data](ideas/conflicts-kept-as-data.md): When two copies change the same thing, the store keeps every conflicting version, or records the conflict in a table, instead of silently dropping one.
- [Labels that follow data (gap)](ideas/information-flow-labels.md): Each value carries a label, such as how sensitive it is, and anything computed from it inherits the label.
- [Last writer wins](ideas/last-writer-wins.md): When two writes clash, last writer wins (LWW) keeps one of them, usually the one with the later timestamp or the later arrival, and silently drops the other.
- [Locks held until commit](ideas/locks-held-until-commit.md): A transaction takes locks on what it reads and writes and holds them until it ends, so no other transaction can change that data in between.
- [Long transactions and time limits](ideas/transaction-time-limits.md): What happens when a transaction stays open for seconds or minutes, and the hard limits some databases put on how long one may run.
- [Many branches that reconcile with each other](ideas/branches-that-reconcile-with-each-other.md): Many agents each work on their own branch, and the branches must be reconciled with one another, not only with the main copy.
- [Masked copies and anonymised branches](ideas/masked-copies.md): *Static masking* rewrites a copy of the data, so the copy holds no real values.
- [Masking query results by role](ideas/dynamic-masking.md): *Dynamic masking* rewrites a value on its way out of the database, depending on who asks.
- [Merging by meaning, not by cell (gap)](ideas/merging-by-meaning.md): A merge that knows what the changes mean, such as "both branches added stock", instead of only which cells changed.
- [Multi-version snapshots](ideas/multi-version-snapshots.md): Each write makes a new version of a row instead of overwriting it, and each reader sees a **snapshot**: the committed state at one moment.
- [Narrowing a session after it reads untrusted rows (gap)](ideas/session-tainting-after-untrusted-reads.md): After a session reads untrusted rows, it loses the right to touch secret rows or write where untrusted parties read.
- [Object storage as the only durable store](ideas/object-storage-as-source-of-truth.md): All durable data lives in cloud object storage, a cheap network store of whole files, and the machines that run queries keep at most a cache.
- [One writer at a time](ideas/one-writer-at-a-time.md): All writes go through one writer, one thread, one process or one owner, in order.
- [Optimistic concurrency and version-checked writes](ideas/optimistic-concurrency.md): Optimistic concurrency runs a transaction without locks, then checks at commit whether someone else changed the same data; if so, the transaction fails and is retried.
- [Planning before reading untrusted data](ideas/plan-then-execute-agents.md): The agent fixes its plan from the user's request alone, before it reads any untrusted data.
- [Query results kept fresh as data changes](ideas/continuously-updated-query-results.md): The database keeps a query's result up to date as the underlying data changes, and pushes the new result to whoever is watching, instead of computing it again each time it is read.
- [Reading the database as it was](ideas/time-travel-queries.md): A *time-travel query* reads the data as it stood at an earlier moment.
- [Real values kept in a separate vault](ideas/tokenization-vaults.md): A *tokenization vault* holds the real sensitive values in a separate store.
- [Recording why a write happened (gap)](ideas/recording-why-a-write-happened.md): Storing the reason for each write, and who asked for it, as part of the write.
- [Redacting prompts before the model provider](ideas/redaction-gateways.md): A *redaction gateway* sits between an application and the model provider.
- [Replying only after a write is durable](ideas/reply-only-after-durable-write.md): The database sends "done" only once the write is safely stored, on disk or on enough copies, so an acknowledged write cannot vanish in a crash or failover.
- [Row and column security](ideas/row-and-column-security.md): The database hides whole rows, or whole columns, from a reader according to a policy.
- [Rules the database enforces across transactions](ideas/invariants-the-database-enforces.md): An *invariant* is a rule that must always hold, such as "stock never below zero" or "this id is unique".
- [Schema changes in stages on a live database](ideas/staged-schema-changes.md): Changing the shape of tables while other transactions use them, by moving each new element through intermediate states run by a background job instead of one locked step.
- [Schemas that only grow, with conversion on read](ideas/grow-only-schema.md): The schema may add things but never break old data, and old records are converted as they are read instead of being rewritten.
- [Serializable by default](ideas/serializable-by-default.md): The database's default isolation level is serializable: concurrent transactions give the same result as if they had run one at a time.
- [Serving schema and worked examples to agents](ideas/schema-and-examples-for-agents.md): The database itself hands an agent its schema, hints about the data, and worked example queries, so an agent with no memory can learn what exists and how to ask for it.
- [Set-at-a-time queries and data independence](ideas/set-at-a-time-queries.md): A set-at-a-time query says *what* result is wanted, and the database's optimiser decides how to fetch it.
- [Short-lived, narrowed grants per agent task](ideas/attenuated-capabilities.md): Each agent task gets its own credential, cut down to the rows and rights the task needs, and it expires soon.
- [Simulating the user's own workload (gap)](ideas/simulating-the-users-own-workload.md): Deterministic simulation testing applied to the application's own operations, not just to the database's internals: the user's workload replayed exactly, with faults injected.
- [Stored procedures and triggers](ideas/stored-procedures-and-triggers.md): A *stored procedure* is a function stored and run inside the database server.
- [Storing data by column](ideas/column-storage.md): A **column store** keeps each column's values together on disk; a **row store** keeps each row's fields together.
- [Storing events instead of current state](ideas/storing-events-instead-of-state.md): Instead of storing what is true now, the database stores the list of changes, and current state is rebuilt by replaying them.
- [Synthetic data](ideas/synthetic-data.md): Generated rows with the same statistics as the real ones, shipped instead of the real rows.
- [Telling the caller what a read or write guarantees](ideas/consistency-reported-to-the-caller.md): Each reply says what it actually guarantees, such as durable on a majority or including the caller's own write.
- [The database inside the application process](ideas/database-inside-the-application-process.md): An embedded database is a library linked into the program, not a separate server.
- [The lethal trifecta inside a shared database (gap)](ideas/lethal-trifecta-in-a-shared-database.md): A database that many agents share supplies, by itself, all three things an attacker needs to steal data through an agent.
- [Three-way merge of data](ideas/three-way-merge-of-data.md): To merge two branches, compare each with their last common ancestor and keep whichever side changed.
- [Transactions and analytics in one system](ideas/transactions-and-analytics-together.md): One database that serves both many small transactional writes (OLTP) and large analytical reads (OLAP) on the same live data.
- [Transactions whose reads and writes are known up front](ideas/read-and-write-sets-known-up-front.md): A transaction sent as one request that already names everything it will read and write.
- [Two timelines: valid time and system time](ideas/valid-time-and-system-time.md): Each fact carries two times: when it was true in the world, and when the database learned it.
- [What the law accepts as de-identified](ideas/legal-de-identification.md): What US and EU law require before records with personal data reach someone else, such as a model provider.
- [Write-once pieces merged in the background](ideas/immutable-pieces-with-background-merge.md): Data is written as pieces that are never edited (parts, segments, files).
- [Writes held for approval (gap)](ideas/writes-held-for-approval.md): An agent's write waits until a person, or a rule a person approved, lets it through.
- [Writes that carry their assumptions](ideas/writes-that-carry-their-assumptions.md): Each write states what the writer believed when it made the change, such as "room 5 is free at 10:00" or "this value is still 7".

## Comparisons (1)

- [The ten families compared](comparisons/families.md): One table of all ten families, the ideas worth borrowing ranked by the gaps they help close, the ideas that cannot be combined, the gaps no family fills, and the limits of the evidence.
