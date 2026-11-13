Research run on 2026-11-13 by a subagent using Exa, for the ticket [Databases that keep history](../issues/05-databases-that-keep-history.md). "Vendor" marks a seller's own claim. The "Borrow" lines and the closing lists are the researcher's inference.

# Databases that keep history (researched 2026-11-13)

## 1. Immutable facts: Datomic

- **What.** Released 2012, free since 2023 (https://blog.datomic.com/2023/04/datomic-is-free.html). Built so a database can be held as a value frozen in time instead of a place that is overwritten.
- **Core idea.** Data is *datoms*: one fact each (entity, attribute, value, transaction, added or retracted). Changes add datoms; nothing is edited. One process, the *transactor*, applies every write in order, so writes are "strong serializable because they are fully serialized" (https://docs.datomic.com/transactions/acid.html).
- **Strength and price.** Any reader can query any past moment without locks. The price is one writer, capped by one machine.
- **Weakness.** Often-changing values grow the database forever; Datomic itself advises turning history off for "a counter or version incrementer" because of "database size or indexing performance" (https://docs.datomic.com/reference/best.html).
- **Overlapping work.** `:db/cas` (compare-and-swap) aborts a transaction if a value is no longer what the writer expected; longer checks run as transaction functions inside the transactor (https://docs.datomic.com/transactions/transaction-functions.html).
- **Agent trouble.** Deletion is a separate background process (section 7).
- **Borrow.** Reads against a frozen value while writes continue; costs a single writer.

## 2. Two timelines: XTDB, SQL:2011, PostgreSQL's original time travel

*Bitemporal* means two times per fact: *system time* (when the database learned it) and *valid time* (when it was true in the world). A correction today about last March keeps both what we believed and what we now know.

- **XTDB v2 (GA June 2025).** Every table is bitemporal. Writes are "serialized via a totally-ordered log" and applied one at a time; write transactions are not interactive, so a client cannot read, decide and write inside one (https://docs.xtdb.com/about/txs-in-xtdb.html). It sends `ASSERT` predicates instead, which roll the transaction back if false. `ERASE` "irrevocably erases documents ... for all valid-time, for all system-time". From v2.1, `METADATA` attaches free-form data to a transaction "to attach upstream request IDs, correlation IDs, or other data lineage information" (https://docs.xtdb.com/reference/main/sql/txs.html).
- **SQL:2011** standardised *system-versioned tables* and *application-time period tables* (https://sigmodrecord.org/2012/09/30/temporal-features-in-sql2011/). In SQL Server you "cannot directly delete rows from history table while SYSTEM_VERSIONING = ON"; to delete history you switch versioning off, and then anyone with enough permission can rewrite or drop it (https://learn.microsoft.com/en-us/sql/relational-databases/tables/modifying-data-in-a-system-versioned-temporal-table?view=sql-server-ver15, https://learn.microsoft.com/en-us/sql/relational-databases/tables/stopping-system-versioning-on-a-system-versioned-temporal-table?view=sql-server-ver17). Retention defaults to infinite (https://learn.microsoft.com/en-us/sql/relational-databases/tables/manage-retention-of-historical-data-in-system-versioned-temporal-tables?view=sql-server-ver17). MariaDB needs a separate `DELETE HISTORY` privilege (https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/system-versioned-tables).
- **PostgreSQL today.** Version 18 (2025-09-25) added valid-time keys (`WITHOUT OVERLAPS`, `PERIOD` foreign keys) but no system versioning (https://www.postgresql.org/about/featurematrix/detail/temporal-constraints/). `UPDATE/DELETE FOR PORTION OF` was reverted from PostgreSQL 19 on 2026-09-15 (https://www.postgresql.org/message-id/E1x6QRv-00000000QOV-0oQc%40gemulon.postgresql.org). A contributor's write-up gives the reason: updating part of a period splits a row in two, and a second writer waiting on that row wakes to find it shrunk, cannot see the new piece, and silently updates nothing (https://tapoueh.org/blog/2026/09/getting-ready-for-postgresql-19/). History and overlapping writes still collide.
- **POSTGRES time travel.** Berkeley POSTGRES never overwrote rows. The 6.3 manual: "As of Postgres v6.2, time travel is no longer supported", for "performance impact, storage size, and a pg_time file which grows toward infinite size" (https://www.postgresql.org/docs/6.3/c0503.htm). The no-overwrite storage survived as multi-version reads, with vacuum discarding versions nobody needs (https://dev.to/franckpachot/postgresql-multi-version-from-time-travel-to-concurrency-control-b5).
- **Agent trouble.** Two time axes double the ways a query can be wrong; "as of when?" is easy to forget.
- **Borrow.** Valid time for after-the-fact corrections; costs query complexity and care with writes that split periods.

## 3. Event sourcing and event stores (KurrentDB, formerly EventStoreDB)

- **What.** Store what happened, not current state; state comes from replaying events into *projections*, derived read models (https://martinfowler.com/eaaDev/EventSourcing.html).
- **Overlapping work.** Each append names the *expected revision* of the stream; if another writer got there first, the store throws `WrongExpectedVersionException` and the writer retries. This is *optimistic concurrency*: check for conflict only at the end (https://docs.kurrent.io/clients/node/v1.2/appending-events).
- **Why and who.** Standard metadata fields `$correlationId` and `$causationId` link an event to the request and the message that caused it (https://docs.kurrent.io/server/v26.0/features/streams). That gives "because of what", not a reason or an approver.
- **Deleting.** Deleted events stay readable via `$all` "until a scavenging process removes them"; "scavenging is destructive" (same page; https://docs.kurrent.io/server/v26.0/operations/scavenge).
- **Schema change.** A practitioner study found five techniques: versioned events, weak schema, *upcasting* (converting old events as read), in-place transformation, copy-and-transform. Only the last two break immutability and are kept for when performance or maintainability suffers (https://arxiv.org/html/2104.01146).
- **Agent trouble.** Agents read projections, which lag and can disagree with each other.
- **Borrow.** An expected-version check on append; costs one integer per stream.

## 4. Logs used as databases: Kafka

- **What.** A partitioned, replicated append-only log. *Log compaction* keeps the latest record per key; a *tombstone* (key with null value) deletes it (https://kafka.apache.org/43/design/design/).
- **Strength and price.** Huge write rates and replay by many readers; paid for with no queries and no conditional writes.
- **Weakness.** Compaction keeps only "the final state", and a reader lagging more than `delete.retention.ms` (default 24 hours) can miss deletes (same page).
- **Overlapping work.** None per key. KIP-27 proposed an "expected offset" so brokers refuse stale writes, citing "multiple competing tasks" creating "an inconsistent state" (https://cwiki.apache.org/confluence/spaces/KAFKA/pages/60623883/KIP-27+-+Conditional+Publish). A 2026 post says Kafka still "has no such mechanism" and suggests one owner per entity (vendor: https://docs.eventsourcingdb.io/blog/2026/07/20/kafka-is-not-an-event-store/).
- **Agent trouble.** "What is true now" needs a separate read model.
- **Borrow.** One owner per key instead of locks; costs routing.

## 5. Ledger databases: Amazon QLDB

- **What.** Announced 2018, GA 2019. A document store whose journal is chained by SHA-256 into a *Merkle tree*, a tree of hashes whose root (the *digest*) fingerprints all history, so a client can prove a revision was not altered (https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html). Conflicts raised `OccConflictException` for the application to retry (https://qldbguide.com/blog/concurrency-control-in-qldb/). Later redaction deleted a revision's data but kept its hash, so verification still held (https://qldbguide.com/blog/redacting-data-in-qldb/).
- **Who and why.** Metadata was `id`, `version`, `txTime`, `txId`: no user, no reason (https://docs.aws.amazon.com/qldb/latest/developerguide/working.metadata.by-clause.html).
- **Withdrawal.** AWS emailed customers that support ended 2025-07-31, without a formal announcement, and pointed them to Aurora PostgreSQL. Its migration guide concedes Aurora "does not keep a permanent, immutable record of changes", so history "must be generated as audit data and stored outside of the database" (https://www.infoq.com/news/2024/07/aws-kill-qldb/). AWS gave no reason. My inference: customers wanted history, but not a separate database and query language to get it.
- **Borrow.** A hash chain over the log, with redaction that keeps hashes; cheap.

## 6. Time travel in mainstream systems: Snowflake and Oracle

- **Snowflake.** `AT`/`BEFORE` reach back 1 day by default, up to 90 on Enterprise, then 7 days of Fail-safe only Snowflake can recover; storage is billed throughout (https://docs.snowflake.com/en/user-guide/data-time-travel, https://docs.snowflake.com/en/user-guide/data-cdp-storage-costs).
- **Oracle Flashback Query** reads *undo*, the old row images kept for rollback, and fails with "snapshot too old" once they are overwritten (https://docs.oracle.com/en/database/oracle/oracle-database/18/admin/managing-undo.html). **Flashback Time Travel** copies changes into history tables even a DBA cannot edit; some schema changes fail with ORA-55610 unless the archive is detached and reattached (https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html). **Flashback Transaction Query** shows `LOGON_USER` and an `UNDO_SQL` per change, though undo SQL "is not the exact opposite" in every case (https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/FLASHBACK_TRANSACTION_QUERY.html).
- **Borrow.** Bounded history windows are what mainstream users actually accept.

## 7. The cost of never forgetting

**Storage.** Every system with unbounded history added a way to forget: Datomic `noHistory`, SQL Server retention, KurrentDB `$maxAge` and scavenging, Snowflake's 90-day cap, Kafka compaction. PostgreSQL dropped time travel over it.

**Deleting personal data.** Always a second-class operation.
- Datomic excision "happens outside the timeline of Datomic history", runs at the next indexing job, and large ones cost indexing "proportional to the size of the entire database", reducing write availability; keep it to a few thousand datoms at a time. It is deliberately lossy: you cannot ask whether a datom ever existed (https://docs.datomic.com/operation/excision.html). `noHistory` exists "to conserve storage, not to make semantic guarantees about removing information" (https://docs.datomic.com/schema/schema-reference.html). A 2018 write-up found no excision in Datomic Cloud and advised keeping personal data in a separate store (https://vvvvalvalval.github.io/posts/2018-05-01-making-a-datomic-system-gdpr-compliant.html).
- Event stores use *crypto-shredding*: encrypt each person's data under their own key and delete the key (https://verraes.net/2019/05/eventsourcing-patterns-throw-away-the-key/).
- The EU data-protection board's blockchain guidelines (version 2, July 2026) weaken that answer: erasure is "technically demanding and often difficult" when "clear text, encrypted or hashed data" sits in an immutable record, so such data "should be stored off-chain" (https://www.edpb.europa.eu/system/files/2026-07/edpb_guidelines_202502_blockchain_v2_en.pdf). Written for blockchains, the reasoning fits any append-only store.

**Queries.** History makes "as of" possible and makes "now" pay unless current state is kept separately. QLDB warned that table scans caused "concurrency conflicts and transaction timeouts" (https://docs.aws.amazon.com/qldb/latest/developerguide/ql-reference.select.html). Datomic and XTDB default to the present.

**Schema across history.** Three options: never break, convert on read, or rewrite. Datomic forbids breaking ("You can never alter :db/valueType"; "grow your schema, and never break it") (https://docs.datomic.com/schema/schema-change.html, https://blog.datomic.com/2017/01/the-ten-rules-of-schema-growth.html). Event stores upcast. SQL Server and Oracle carry changes into history tables but refuse some, or need history switched off first.

## 8. Recording why and on whose instruction

No system makes *why* a required part of a write.
- **Datomic** comes closest: a transaction is an entity, and you "can add additional attributes ... such as the purpose of the transaction, the application that executed it, the provenance of the data ..., or the user who caused it" (https://docs.datomic.com/transactions/transaction-data-reference.html). It is optional and unchecked; teams invent attributes like "admin user working on behalf of another user" (https://cjohansen.no/annotating-datomic-transactions/).
- **XTDB**: free-form transaction `METADATA`. **KurrentDB**: correlation and causation IDs. **Oracle**: the logon user, usually a shared application account. **QLDB, Snowflake, SQL:2011**: time and transaction only.

None records a chain such as "agent A, acting for Robert, under rule R"; none rejects a write without a reason; none treats reasons as typed, queryable data. The slot exists (the transaction record); nothing fills it, checks it or gives it meaning.

## Summary table

| System | Strength | What pays for it | Weakness |
| --- | --- | --- | --- |
| Datomic | Query any past moment; lock-free reads | One transactor | Excision slow and outside history; schema can only grow |
| XTDB v2 | Two timelines everywhere; `ERASE`; transaction metadata | One writer; no interactive writes | Two-axis queries are easy to get wrong |
| SQL:2011 tables | Standard SQL history | History table beside the live one | Deleting history means switching it off; PostgreSQL reverted portion updates over overlapping writes |
| POSTGRES time travel | Old rows queryable | Never overwrite | Removed in 6.2 for performance and storage |
| Event stores | Causal record; expected-version checks | Reads through projections | Format changes painful; deletes wait for scavenging |
| Kafka | Huge write rates; replay | No queries, no conditional writes | Lagging readers miss deletes |
| QLDB | Provable, tamper-evident history | Separate database and language | Withdrawn 2025; no user or reason |
| Snowflake / Oracle | History inside mainstream databases | Bounded window and a storage bill | History expires; only a logon user |

## Ideas worth borrowing

1. **The transaction as a record with a required, typed reason, requester and approver.** Datomic shows the slot; the cost is designing a schema for intent and making every writer supply it.
2. **Expected-version checks on every write.** Cheap; turns overlapping work into a conflict an agent can see and retry.
3. **Valid time beside system time** for corrections; costs an "as of when?" on every query and care with period-splitting writes.
4. **Personal data outside the history from day one**, history holding references. Excision, crypto-shredding and the EDPB all point here; costs two stores and a join.
5. **A hash chain over the log, with redaction that keeps hashes.** Tamper-evidence for little cost.
6. **Grow-only schema with conversion on read**, so history is never rewritten.

## What I could not confirm

- Whether Datomic Cloud supports excision today; my only source is from 2018.
- AWS's reason for withdrawing QLDB; mine is inference.
- Whether XTDB's `ERASE` leaves a trace that an erase happened.
- KIP-27's formal status; it is not implemented, but I did not see its status line.
- Whether QLDB recorded caller identity anywhere outside CloudTrail.
- The `FOR PORTION OF` revert reason comes from a contributor's blog; the commit message I saw lists commits, not the reason.
