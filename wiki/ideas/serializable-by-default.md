# Serializable by default

The database's default isolation level is serializable: concurrent transactions give the same result as if they had run one at a time. Most databases instead default to a weaker level and leave serializable as an option.

## What it is

- An **isolation level** says which effects of concurrent transactions one transaction may see. **Serializable** is the strongest common level ([research 01](../../research/01-relational-and-transactional.md)).
- [CockroachDB](../systems/cockroachdb.md) and [Spanner](../systems/spanner.md) default to serializable. PostgreSQL and Oracle default to read committed; MySQL to repeatable read ([research 01](../../research/01-relational-and-transactional.md)).
- Some systems get it by running writes strictly one after another:
  - Datomic sends every write through one *transactor*, so writes are "strong serializable because they are fully serialized" ([Datomic ACID](https://docs.datomic.com/transactions/acid.html)).
  - XTDB serializes writes "via a totally-ordered log" and applies them one at a time ([XTDB txs](https://docs.xtdb.com/about/txs-in-xtdb.html)).
  - TigerBeetle runs batched requests one after another on one thread, with no locks ([ARCHITECTURE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md)).

## The problem it solves

- **Weaker levels move the cost into application bugs** ([research 01](../../research/01-relational-and-transactional.md)).
  - Snapshot isolation allows **write skew**: two transactions each check a rule over two values, each change a different one, and together break it ([Berenson et al.](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf)).
  - Names hide anomalies. Oracle's "serializable" is snapshot isolation ([Hermitage](https://github.com/ept/hermitage/blob/master/oracle.md)); MySQL's repeatable read "silently discards" committed changes in a load, change and save pattern ([Jepsen](https://jepsen.io/analyses/mysql-8.0.34)).
- **Users code around weaker guarantees badly.** Spanner's authors concluded "it is better to have application programmers deal with performance problems due to overuse of transactions ... rather than always coding around the lack of transactions" ([Spanner, TOCS](https://doi.org/10.1145/2491245)).

## What it costs

Serializability is paid for with blocking, aborts or clock waits ([research 01](../../research/01-relational-and-transactional.md)):

- **Aborts and retries.** PostgreSQL's SSI aborts a transaction when an anomaly is *possible*, giving false aborts; every serializable transaction must be retried on SQLSTATE `40001` ([PG docs](https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html)). CockroachDB pushes retries onto the client ([retry reference](https://docs.cockroachlabs.com/docs/stable/transaction-retry-error-reference)), and offers read committed precisely so clients need no retry loops ([docs](https://docs.cockroachlabs.com/docs/stable/read-committed)).
- **Clock waits.** Spanner waits out TrueTime's uncertainty, "generally less than 10ms", on each commit, using GPS and atomic clocks ([research 01](../../research/01-relational-and-transactional.md)).
- **Aborts under contention.** As a default, every write needs a retry path, and aborts rise under contention, unless the database replays the transaction itself ([research 01](../../research/01-relational-and-transactional.md)).
- **One writer.** Fully serial writes cap throughput at one machine (Datomic) ([research 05](../../research/05-databases-that-keep-history.md)). TigerBeetle pays with one thread and a fixed schema ([research 08](../../research/08-correctness-first-databases.md)).
- **No interactive writes.** XTDB's write transactions are not interactive: a client cannot read, decide and write inside one. It sends `ASSERT` predicates that roll the transaction back if false ([XTDB txs](https://docs.xtdb.com/about/txs-in-xtdb.html)).
- **Correct retries are hard for agents.** After a `40001` the agent must replay the *whole* transaction and re-read data; if its reasoning depended on what it read, the retry must re-run the reasoning too (inference, [research 01](../../research/01-relational-and-transactional.md)).
- **The promise still needs checking.** PostgreSQL 12.3's serializable let write skew through because of a bug ([Jepsen](https://jepsen.io/analyses/postgresql-12.3)). TigerBeetle was found consistent with **strong serializability** (every transaction appears to happen at one instant, in real-time order) only after Jepsen's fixes ([Jepsen](https://jepsen.io/analyses/tigerbeetle-0.16.11)).

## Systems that use it

- [CockroachDB](../systems/cockroachdb.md): serializable default; read committed opt-in.
- [Spanner](../systems/spanner.md): serializable default with external consistency; repeatable read opt-in.
- [PostgreSQL](../systems/postgresql.md): offers true serializability (SSI), but not as the default.
- [Datomic](../systems/datomic.md): one transactor; strong serializable.
- [XTDB](../systems/xtdb.md): one totally ordered log; non-interactive writes.
- [TigerBeetle](../systems/tigerbeetle.md): one thread; strong serializability confirmed by Jepsen.

## Cannot be combined with

- **Interactive transactions in a fully serial design.** XTDB's ordered log rules out reading, deciding and writing inside one write transaction ([research 05](../../research/05-databases-that-keep-history.md)).
- **Clients with no retry path**, in the optimistic and SSI designs. That is why CockroachDB offers read committed ([research 01](../../research/01-relational-and-transactional.md)).

## Sources

- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- Primary links are given inline above.
