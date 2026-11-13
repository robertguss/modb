# Databases that keep history

Type: research
Status: resolved

## Question

Using the map's research template, what do databases that keep history do well and badly, and what pays for each strength?

Cover immutable facts (Datomic), two timelines (XTDB, SQL:2011 temporal tables, PostgreSQL's original time travel), event sourcing and event stores, logs used as databases (Kafka), ledger databases (Amazon QLDB and why it was withdrawn), and time travel in mainstream systems (Snowflake, Oracle Flashback).

Go deepest on the cost of never forgetting (storage, deleting personal data, queries, changing the schema across history), and on how far any of them goes toward recording why a change was made and on whose instruction.

## Answer

Findings: [research/05-databases-that-keep-history.md](../research/05-databases-that-keep-history.md)

- History is paid for with a single writer (Datomic, XTDB) or a bounded window (Snowflake, Oracle undo). Every system that kept unbounded history later added a way to forget, and PostgreSQL dropped time travel in 6.2 over storage and performance.
- Deleting personal data is always second-class: Datomic excision runs outside history and can stall writes, and event stores rely on crypto-shredding. The EDPB's 2026 blockchain guidelines say even encrypted or hashed personal data should stay out of an immutable record.
- History and overlapping writes still collide: PostgreSQL reverted `FOR PORTION OF` from version 19 in September 2026 over a lost-update case.
- No system makes "why" or "on whose instruction" a required, checked part of a write. Datomic's transaction entity and XTDB's transaction `METADATA` provide an unchecked slot; KurrentDB has correlation and causation IDs; Oracle has only the logon user.
- QLDB (hash-chained, provable history) was withdrawn in July 2025, and AWS's replacement keeps history outside the database.
