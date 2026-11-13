# Databases that keep history

Type: research
Status: claimed

## Question

Using the map's research template, what do databases that keep history do well and badly, and what pays for each strength?

Cover immutable facts (Datomic), two timelines (XTDB, SQL:2011 temporal tables, PostgreSQL's original time travel), event sourcing and event stores, logs used as databases (Kafka), ledger databases (Amazon QLDB and why it was withdrawn), and time travel in mainstream systems (Snowflake, Oracle Flashback).

Go deepest on the cost of never forgetting (storage, deleting personal data, queries, changing the schema across history), and on how far any of them goes toward recording why a change was made and on whose instruction.
