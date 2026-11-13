# Guarantees checked by a tool, not stated by a name

A database's guarantees, such as its isolation level, are shown by a checker that tests recorded histories against a named model, rather than taken on trust from the level's name ([research 01](../../research/01-relational-and-transactional.md); [research 08](../../research/08-correctness-first-databases.md)).

## What it is

*Isolation levels* are the named promises a database makes about what concurrent transactions can see, such as "repeatable read" or "serializable". The same name means different things in different databases. [PostgreSQL](../systems/postgresql.md)'s "repeatable read" is *snapshot isolation* (each transaction sees one consistent past moment); [MySQL](../systems/mysql.md)'s is weaker than that; [Oracle](../systems/oracle.md)'s "serializable" is snapshot isolation and allows *write skew* (two transactions each read x and y, each check that x + y stays positive, and each write a different one of the two; both commit, and the rule is broken) ([research 01](../../research/01-relational-and-transactional.md); [Hermitage](https://github.com/ept/hermitage/blob/master/oracle.md)).

A checker such as [Jepsen](../systems/jepsen.md) runs the system, records every operation, and checks that history against the model the vendor claims ([research 08](../../research/08-correctness-first-databases.md)). Research 01 names Jepsen's Elle and Hermitage as such tools ([research 01](../../research/01-relational-and-transactional.md)).

## The problem it solves

"The name of an isolation level is a weak promise; only a checker shows the guarantee" ([research 01](../../research/01-relational-and-transactional.md)). Examples:

- **MySQL 8.0.34.** Repeatable read allows lost updates: "MySQL Repeatable Read transactions cannot safely read a value and then write it" ([Jepsen](https://jepsen.io/analyses/mysql-8.0.34)).
- **PostgreSQL 12.3.** Serializable let write skew through because of a bug in conflict detection; a fix followed ([Jepsen](https://jepsen.io/analyses/postgresql-12.3)).
- **Amazon RDS for PostgreSQL** clusters violate snapshot isolation, showing "Long Fork" even when healthy ([Jepsen, 2025-04-29](https://jepsen.io/analyses/amazon-rds-for-postgresql-17.4)).
- **[MongoDB](../systems/mongodb.md) 4.2.6.** Transactions violated snapshot isolation under default settings and "appeared to lose acknowledged writes", because they fell back to `w: 1` ([Jepsen, 2020](https://jepsen.io/analyses/mongodb-4.2.6); [research 03](../../research/03-key-value-document-distributed.md)). Since 5.0 the default write concern is `majority` ([vendor PDF](https://webassets.mongodb.com/mongodb_whats_new_5.0.pdf)).
- **[TigerBeetle](../systems/tigerbeetle.md).** Jepsen found multi-filter queries that "often omitted results, even in healthy clusters"; after fixes it found TigerBeetle consistent with strong serializability ([Jepsen](https://jepsen.io/analyses/tigerbeetle-0.16.11)).

For agents: an agent trusting the name "repeatable read" on MySQL will lose updates. The guarantee lives in Jepsen reports, not in the schema (inference, [research 01](../../research/01-relational-and-transactional.md)). On MongoDB the guarantee is a setting passed with each call, and the old defaults were unsafe (inference, [research 03](../../research/03-key-value-document-distributed.md)).

## What it costs

- Building a checker for every guarantee the database claims ([research 01](../../research/01-relational-and-transactional.md)).
- Testing from outside, Jepsen cannot replay a run exactly, and it finds only what its workload exercises ([research 08](../../research/08-correctness-first-databases.md)).

## Systems that use it

These are systems that were checked, not systems that ship a checker:

- [Jepsen](../systems/jepsen.md): the checker.
- [MySQL](../systems/mysql.md), [PostgreSQL](../systems/postgresql.md), [MongoDB](../systems/mongodb.md), [TigerBeetle](../systems/tigerbeetle.md): checked by Jepsen, with the findings above. Research 00 notes that TigerBeetle was tested independently by Jepsen ([research 00](../../research/00-landscape-overview.md)).

## Sources

- [research 01: Relational and transactional](../../research/01-relational-and-transactional.md)
- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- [research 03: Key-value, document and distributed](../../research/03-key-value-document-distributed.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- Hermitage (Oracle): https://github.com/ept/hermitage/blob/master/oracle.md
- Jepsen analyses: https://jepsen.io/analyses/mysql-8.0.34, https://jepsen.io/analyses/postgresql-12.3, https://jepsen.io/analyses/amazon-rds-for-postgresql-17.4, https://jepsen.io/analyses/mongodb-4.2.6, https://jepsen.io/analyses/tigerbeetle-0.16.11
