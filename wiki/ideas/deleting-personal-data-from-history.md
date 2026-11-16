# Deleting personal data from a store that keeps history

A store that never forgets still has to forget a person when the law requires it. In every system the research looked at, this is a second-class operation.

## What it is

The set of ways a history-keeping store removes data for good: *excision* (removing facts outside the normal timeline), *scavenging* (a background pass that drops deleted events), tombstones, redaction, switching history off, and *crypto-shredding* (encrypting each person's data under their own key, then deleting the key) ([05](../../research/05-databases-that-keep-history.md), https://verraes.net/2019/05/eventsourcing-patterns-throw-away-the-key/).

## The problem it solves

Data-protection law can require erasure, and an append-only history is built never to erase ([05](../../research/05-databases-that-keep-history.md)).

## What it costs

Each system pays differently:

- **[Datomic](../systems/datomic.md).** Excision "happens outside the timeline of Datomic history" and runs at the next indexing job. Large ones cost indexing "proportional to the size of the entire database" and reduce write availability; keep each to a few thousand datoms. It is deliberately lossy: you cannot ask whether a datom ever existed (https://docs.datomic.com/operation/excision.html). `noHistory` exists "to conserve storage, not to make semantic guarantees about removing information" (https://docs.datomic.com/schema/schema-reference.html). A 2018 write-up found no excision in Datomic Cloud and advised a separate store for personal data (https://vvvvalvalval.github.io/posts/2018-05-01-making-a-datomic-system-gdpr-compliant.html); whether Cloud supports it today is not confirmed ([05](../../research/05-databases-that-keep-history.md)).
- **[XTDB](../systems/xtdb.md).** `ERASE` "irrevocably erases documents ... for all valid-time, for all system-time" (https://docs.xtdb.com/reference/main/sql/txs.html). Whether it leaves a trace that an erase happened is not confirmed ([05](../../research/05-databases-that-keep-history.md)).
- **[KurrentDB](../systems/kurrentdb.md).** Deleted events stay readable via `$all` "until a scavenging process removes them"; "scavenging is destructive" (https://docs.kurrent.io/server/v26.0/operations/scavenge).
- **[Apache Kafka](../systems/kafka.md).** A tombstone deletes a key at compaction, but a reader lagging more than `delete.retention.ms` (24 hours by default) can miss it (https://kafka.apache.org/43/design/design/).
- **[Amazon QLDB](../systems/amazon-qldb.md).** Redaction deleted a revision's data but kept its hash, so verification still held (https://qldbguide.com/blog/redacting-data-in-qldb/).
- **[SQL:2011 temporal tables](../systems/sql-temporal-tables.md).** SQL Server will not delete history rows while versioning is on; you switch versioning off, and then anyone with enough permission can rewrite or drop history (https://learn.microsoft.com/en-us/sql/relational-databases/tables/stopping-system-versioning-on-a-system-versioned-temporal-table?view=sql-server-ver17). MariaDB needs a separate `DELETE HISTORY` privilege (https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/system-versioned-tables).
- **[Snowflake](../systems/snowflake.md).** History expires on its own: 1 day by default, up to 90, then 7 days of Fail-safe only Snowflake can recover (https://docs.snowflake.com/en/user-guide/data-time-travel).
- **Crypto-shredding** is the event-store answer (https://verraes.net/2019/05/eventsourcing-patterns-throw-away-the-key/). The EU data-protection board's blockchain guidelines (version 2, July 2026) weaken it: erasure is "technically demanding and often difficult" when "clear text, encrypted or hashed data" sits in an immutable record, so such data "should be stored off-chain" (https://www.edpb.europa.eu/system/files/2026-07/edpb_guidelines_202502_blockchain_v2_en.pdf). They were written for blockchains; the researcher argues the reasoning fits any append-only store ([05](../../research/05-databases-that-keep-history.md)).

The researcher's suggestion (inference): keep personal data outside the history from day one, with history holding references. Excision, crypto-shredding and the EDPB all point there. The cost is two stores and a join ([05](../../research/05-databases-that-keep-history.md)).

Replacing names with stand-ins does not get a store out of this. In the EU, pseudonymised data stays personal data in the sender's hands, even when the key is held elsewhere or erased (https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf, [20](../../research/20-keeping-sensitive-data-from-agents.md)). The board's final blockchain guidelines give one condition under which a keyed hash stops being linkable: "after deletion of the secret key or salt, the hash should not be linkable to the original data, provided that the algorithm has not been broken, the keys have not been compromised or leaked, and the salt was not leaked or poorly chosen" (paragraph 52, https://www.edpb.europa.eu/system/files/2026-07/edpb_guidelines_202502_blockchain_v2_en.pdf). So "or erased" above holds for the pseudonymisation guidelines and not for a keyed hash whose secret is gone. See [consistent pseudonyms](consistent-pseudonyms.md) and [what the law accepts as de-identified](legal-de-identification.md).

## Systems that use it

[Datomic](../systems/datomic.md), [XTDB](../systems/xtdb.md), [KurrentDB](../systems/kurrentdb.md), [Apache Kafka](../systems/kafka.md), [Amazon QLDB](../systems/amazon-qldb.md), [SQL:2011 temporal tables](../systems/sql-temporal-tables.md), [Snowflake](../systems/snowflake.md).

## Cannot be combined with

A record that is both immutable and holds personal data in any form, clear, encrypted or hashed, per the EDPB reasoning above (inference from those guidelines). [Facts that are added, never changed](append-only-facts.md) has to give way somewhere.

## Disagreements

- **Does Datomic ever remove data?** [00](../../research/00-landscape-overview.md) says Datomic never updates in place. [05](../../research/05-databases-that-keep-history.md) describes `noHistory` and excision, which delete datoms outside the timeline.

## Sources

- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf
- https://docs.datomic.com/operation/excision.html
- https://docs.datomic.com/schema/schema-reference.html
- https://vvvvalvalval.github.io/posts/2018-05-01-making-a-datomic-system-gdpr-compliant.html
- https://docs.xtdb.com/reference/main/sql/txs.html
- https://docs.kurrent.io/server/v26.0/operations/scavenge
- https://kafka.apache.org/43/design/design/
- https://qldbguide.com/blog/redacting-data-in-qldb/
- https://learn.microsoft.com/en-us/sql/relational-databases/tables/stopping-system-versioning-on-a-system-versioned-temporal-table?view=sql-server-ver17
- https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/system-versioned-tables
- https://docs.snowflake.com/en/user-guide/data-time-travel
- https://verraes.net/2019/05/eventsourcing-patterns-throw-away-the-key/
- https://www.edpb.europa.eu/system/files/2026-07/edpb_guidelines_202502_blockchain_v2_en.pdf
