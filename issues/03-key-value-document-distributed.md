# Key-value, document and distributed stores

Type: research
Status: resolved

## Question

Using the map's research template, what do key-value, document and distributed stores do well and badly, and what pays for each strength?

Cover dbm and Berkeley DB, Redis, log-structured stores (LevelDB, RocksDB), Dynamo and DynamoDB, Bigtable, Cassandra, MongoDB and CouchDB.

Go deepest on what they gave up from relational databases (joins, transactions, schema), which of those they later added back and why, and the consistency choice each makes when the network fails.

## Answer

Findings: [research/03-key-value-document-distributed.md](../research/03-key-value-document-distributed.md)

- Most systems that dropped multi-item transactions took them back in a narrowed form; Redis (no rollback) and CouchDB did not. Examples: DynamoDB's single-shot transactions in 2018, MongoDB 4.0/4.2, and Cassandra 6's Accord, still alpha. Spanner's authors explain why: programmers were "always coding around the lack of transactions".
- The usual answer to a network split is to keep accepting writes and settle later. Dynamo merges in the application, so deleted items resurface. Cassandra uses last write wins on clocks, so writes vanish silently. CouchDB keeps conflict branches but shows only the winner.
- Strong consistency across sites is opt-in and costs features: DynamoDB's strong multi-Region mode (GA 2025-06) does not support transactions.
- Guarantees live in settings passed per call or per table. That is how MongoDB 4.2.6 lost acknowledged writes under defaults (Jepsen, 2020).
- Worth borrowing: conflicts kept as data, single-shot transactions with declared read and write sets, check-and-set on a version token, and replies that state the guarantee they met.
