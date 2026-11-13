# Spanner

Spanner is Google's relational database spread over many machines and data centres, described at OSDI 2012. It buys globally ordered transactions with synchronised clocks. It belongs to the [relational and transactional family](../families/relational-and-transactional.md).

## What it is for

- Spreading the relational model over many machines ([Spanner, OSDI 2012](https://www.usenix.org/system/files/conference/osdi12/osdi12-final-16.pdf)).
- It answered complaints about [Bigtable](bigtable.md). Spanner's authors "consistently received complaints" that Bigtable was hard to use "for ... complex, evolving schemas, or ... strong consistency in the presence of wide-area replication". Many teams chose Megastore "despite its relatively low performance" ([Spanner, TOCS](https://doi.org/10.1145/2491245)).
- Their conclusion: "it is better to have application programmers deal with performance problems due to overuse of transactions ... rather than always coding around the lack of transactions" (same paper).

## Core idea

- **Locks in read-write transactions, with wound-wait.** An older transaction aborts ("wounds") a younger one that holds a lock it needs; a younger one waits. This avoids deadlock ([concurrency control](https://docs.cloud.google.com/spanner/docs/concurrency-control)). See [locks held until commit](../ideas/locks-held-until-commit.md).
- **Read-only transactions take no locks and never abort** (same page).
- **TrueTime.** Each commit waits out the clock's uncertainty bound, "generally less than 10ms", kept small by GPS and atomic clocks. That buys **external consistency**: if T1 commits before T2 starts, T1's timestamp is smaller ([OSDI paper](https://www.usenix.org/system/files/conference/osdi12/osdi12-final-16.pdf)).
- **[Serializable by default](../ideas/serializable-by-default.md)** ([research 01](../../research/01-relational-and-transactional.md)).

## Strengths and what pays for each

- **External consistency across the globe.** *Paid for by* TrueTime hardware and a commit wait on every write ([research 01](../../research/01-relational-and-transactional.md)).
- **Reads that never block or abort.** *Paid for by* keeping old versions; the oldest reader holds up cleanup ([research 01](../../research/01-relational-and-transactional.md)).
- **No deadlocks.** *Paid for by* wound-wait aborts of younger transactions ([concurrency control](https://docs.cloud.google.com/spanner/docs/concurrency-control)).
- **Serializable by default.** *Paid for by* a retry path on every write and more aborts under contention ([research 01](../../research/01-relational-and-transactional.md)).

## Weaknesses

- **Idle transactions are aborted.** Spanner may abort a read-write transaction that has issued no read for 10 seconds "so that they don't hold on to locks indefinitely". Clients send `SELECT 1` to keep it alive ([transactions](https://docs.cloud.google.com/spanner/docs/transactions)). See [transaction time limits](../ideas/transaction-time-limits.md).
- **The weaker level allows write skew.** Spanner's repeatable read is snapshot reads with optimistic locking ([docs](https://docs.cloud.google.com/spanner/docs/use-repeatable-read-isolation)). It defers locks to commit and does not check reads. Google says to switch only "after you have audited your transactions to ensure they are safe from write-skew" ([Google Cloud community post, vendor](https://medium.com/google-cloud/spanner-repeatable-read-isolation-14262ee60709)). It was announced in preview in 2025 and is now listed as generally available ([release notes](https://docs.cloud.google.com/spanner/docs/release-notes)); research 01 did not find the GA date.

## Overlapping work

- Read-write transactions lock and use wound-wait. Read-only transactions read a snapshot without locks ([research 01](../../research/01-relational-and-transactional.md)).
- **Schema changes in stages.** F1, built on Spanner, moves each new schema element through internal states, **delete-only** and then **write-only**, before it can be read. Every server is at most one state apart, so no server corrupts data another server's schema expects ([F1, VLDB 2013](https://www.vldb.org/pvldb/vol6/p1045-rae.pdf)). See [staged schema changes](../ideas/staged-schema-changes.md).

## What an agent struggles with

- **Thinking inside a transaction.** An agent that calls a model for 30 seconds before writing is aborted as idle (inference, [research 01](../../research/01-relational-and-transactional.md)).

## Worth borrowing

From research 01, each with its cost:

- **Serializable by default.** Cost: every write needs a retry path, unless the database replays the transaction itself.
- **Snapshot reads that never block or abort.** Cost: old versions must be kept.
- **A hard limit on how long a transaction stays open.** Cost: long work must be split or moved outside the transaction.
- **Schema change as staged states run by a background job** (F1). Cost: a change takes several steps and is not atomic.

## Disagreements

- **Whether agents really hold transactions open.** Research 01 found no study and marks its agent reasoning as inference; research 08 and 09 cite a 2026 workshop paper saying agents do ([SAO workshop](https://bauplanlabs.github.io/SAO-workshop/papers/9.pdf)).

## Sources

- [research/01-relational-and-transactional.md](../../research/01-relational-and-transactional.md)
- [research/03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- Primary links are given inline above.
