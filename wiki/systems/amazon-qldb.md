# Amazon QLDB

Amazon QLDB was a ledger database: a document store whose history could be proven unaltered. AWS announced it in 2018, made it generally available in 2019, and ended support on 2025-07-31.

## What it is for

Provable, tamper-evident history ([05](../../research/05-databases-that-keep-history.md)).

## Core idea

The journal was chained by SHA-256 into a *Merkle tree*: a tree of hashes whose root, the *digest*, fingerprints all history. A client could prove a revision was not altered (https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html).

## Strengths and what pays for each

- **Tamper-evident history.** Paid for by a separate database and query language ([05](../../research/05-databases-that-keep-history.md)).
- **Redaction that keeps verification.** Later versions could delete a revision's data but keep its hash, so verification still held (https://qldbguide.com/blog/redacting-data-in-qldb/). See [Deleting personal data](../ideas/deleting-personal-data-from-history.md).

## Weaknesses

- **Withdrawn.** AWS emailed customers that support ended 2025-07-31, without a formal announcement, and pointed them to Aurora PostgreSQL. Its migration guide concedes Aurora "does not keep a permanent, immutable record of changes", so history "must be generated as audit data and stored outside of the database" (https://www.infoq.com/news/2024/07/aws-kill-qldb/). AWS gave no reason. The researcher's inference: customers wanted history, but not a separate database and query language to get it ([05](../../research/05-databases-that-keep-history.md)).
- **No user, no reason.** Metadata was `id`, `version`, `txTime` and `txId` (https://docs.aws.amazon.com/qldb/latest/developerguide/working.metadata.by-clause.html). Whether QLDB recorded caller identity anywhere outside CloudTrail is not confirmed ([05](../../research/05-databases-that-keep-history.md)).
- **Reading "now" was costly.** QLDB warned that table scans caused "concurrency conflicts and transaction timeouts" (https://docs.aws.amazon.com/qldb/latest/developerguide/ql-reference.select.html).

## Overlapping work

Conflicts raised `OccConflictException` for the application to retry (https://qldbguide.com/blog/concurrency-control-in-qldb/). See [Optimistic concurrency](../ideas/optimistic-concurrency.md).

## Worth borrowing

A hash chain over the log, with redaction that keeps hashes. Tamper-evidence for little cost (researcher's inference, [05](../../research/05-databases-that-keep-history.md)).

## Disagreements

- **Who made a change.** [00](../../research/00-landscape-overview.md) says bitemporal stores record when a fact changed and who wrote it, but not why. [05](../../research/05-databases-that-keep-history.md) says QLDB recorded only time and transaction, with no user.

## Sources

- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html
- https://docs.aws.amazon.com/qldb/latest/developerguide/working.metadata.by-clause.html
- https://docs.aws.amazon.com/qldb/latest/developerguide/ql-reference.select.html
- https://qldbguide.com/blog/concurrency-control-in-qldb/
- https://qldbguide.com/blog/redacting-data-in-qldb/
- https://www.infoq.com/news/2024/07/aws-kill-qldb/
