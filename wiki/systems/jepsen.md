# Jepsen

Jepsen is an independent tester of databases, not a database. It runs real clusters under network partitions, crashes and clock skew, records every operation, and checks that history against the consistency model the vendor claims ([research 08](../../research/08-correctness-first-databases.md)).

## What it is for

Finding out whether a database delivers the guarantees its documentation names. Research 01 puts it as: the name of an isolation level is a weak promise; only a checker shows the guarantee ([research 01](../../research/01-relational-and-transactional.md)). See [guarantees checked by a tool](../ideas/guarantees-checked-by-a-tool.md).

## Core idea

Test from the outside. Drive a running cluster with a workload, inject faults, record the full history of operations and results, then check that history against a named model such as *snapshot isolation* (each transaction sees one consistent past moment) or *strong serializability* (every transaction appears to happen at one instant, in real-time order) ([research 08](../../research/08-correctness-first-databases.md)). Research 01 names Jepsen's checker Elle as the tool for this ([research 01](../../research/01-relational-and-transactional.md)).

## Strengths and what pays for each

**It finds what vendors claim but do not deliver.** Paid for by: real clusters and an outside view, with no exact replay of a run ([research 08](../../research/08-correctness-first-databases.md)). Recurring findings:

- **The documentation promises more than the system gives.**
  - MySQL 8.0.34: "MySQL Repeatable Read transactions cannot safely read a value and then write it". The usual load, change and save pattern "may find that MySQL silently discards those committed changes". AWS RDS MySQL "routinely" broke serializability ([Jepsen, 2023-12-19](https://jepsen.io/analyses/mysql-8.0.34); [research 01](../../research/01-relational-and-transactional.md)).
  - Amazon RDS for PostgreSQL clusters violate snapshot isolation, showing "Long Fork" even when healthy ([Jepsen, 2025-04-29](https://jepsen.io/analyses/amazon-rds-for-postgresql-17.4)).
  - PostgreSQL 12.3: serializable let write skew through because of a bug in conflict detection; a fix followed ([Jepsen, 2020-06-12](https://jepsen.io/analyses/postgresql-12.3); [research 01](../../research/01-relational-and-transactional.md)).
  - MongoDB 4.2.6: transactions violated snapshot isolation under default settings and "appeared to lose acknowledged writes", because transactions ignored safer client settings and fell back to `w: 1` ([Jepsen, 2020](https://jepsen.io/analyses/mongodb-4.2.6); [research 03](../../research/03-key-value-document-distributed.md)).
- **Acknowledged writes are lost.** A write is confirmed, then gone ([lost write](https://jepsen.io/consistency/phenomena/lost-write)). The usual cause is acknowledging before *fsync* (the call that forces data from memory onto disk). NATS JetStream fsyncs "only once every two minutes, but acknowledges messages immediately"; simulated power failures lost 131,418 of 930,005 messages ([Jepsen, 2025-12-08](https://jepsen.io/analyses/nats-2.12.1)).
- **Bugs appear without faults.** MariaDB Galera Cluster allowed lost updates "even in healthy clusters" and appeared "weaker than Read Uncommitted" ([Jepsen](https://jepsen.io/analyses/mariadb-galera-cluster-12.1.2)). [TigerBeetle](tigerbeetle.md)'s multi-filter query bug also needed no faults ([Jepsen](https://jepsen.io/analyses/tigerbeetle-0.16.11)).
- **It catches what simulation misses.** TigerBeetle's latency collapse under one killed node was found by Jepsen, not by TigerBeetle's own simulator ([research 08](../../research/08-correctness-first-databases.md)).

## Weaknesses

- Testing from outside, it cannot replay a run exactly ([research 08](../../research/08-correctness-first-databases.md)).
- It finds only what its workload exercises ([research 08](../../research/08-correctness-first-databases.md)).

## What an agent struggles with

The guarantee lives in Jepsen reports, not in the schema. An agent trusting the name "repeatable read" on MySQL will lose updates (inference, [research 01](../../research/01-relational-and-transactional.md)).

## Worth borrowing

**Name the consistency model and check histories against it.** Cost: writing the checker ([research 08](../../research/08-correctness-first-databases.md)); research 01 adds that a checker is needed for every guarantee the database claims ([research 01](../../research/01-relational-and-transactional.md)).

## Sources

- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- [research 01: Relational and transactional](../../research/01-relational-and-transactional.md)
- [research 03: Key-value, document and distributed](../../research/03-key-value-document-distributed.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md) (notes Jepsen tested TigerBeetle independently: https://jepsen.io/analyses/tigerbeetle-0.16.11.pdf)
- MySQL 8.0.34: https://jepsen.io/analyses/mysql-8.0.34
- Amazon RDS for PostgreSQL 17.4: https://jepsen.io/analyses/amazon-rds-for-postgresql-17.4
- PostgreSQL 12.3: https://jepsen.io/analyses/postgresql-12.3
- MongoDB 4.2.6: https://jepsen.io/analyses/mongodb-4.2.6
- Lost write: https://jepsen.io/consistency/phenomena/lost-write
- NATS 2.12.1: https://jepsen.io/analyses/nats-2.12.1
- MariaDB Galera Cluster 12.1.2: https://jepsen.io/analyses/mariadb-galera-cluster-12.1.2
- TigerBeetle 0.16.11: https://jepsen.io/analyses/tigerbeetle-0.16.11
