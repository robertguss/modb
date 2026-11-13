# Dynamo and DynamoDB

Dynamo (2007) was Amazon's key-value store built never to refuse a write, at the price of isolation. DynamoDB (2012) is the managed service that later added transactions back, in a narrowed single-request form.

## What it is for

Dynamo's problem was the shopping cart, which "must allow customers to add and remove items ... even amidst network and server failures" ([03](../../research/03-key-value-document-distributed.md), https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf). The 2012 year for DynamoDB comes from memory in the research file, not a fetched page ([03](../../research/03-key-value-document-distributed.md), not confirmed).

## Core idea

- **Gave up ACID on purpose.** "Data stores that provide ACID guarantees tend to have poor availability ... Dynamo does not provide any isolation" guarantees. It allows only single-key updates and has no relational schema (Dynamo paper).
- A *sloppy quorum* writes to the first N *healthy* nodes, so writes are never refused. A *quorum* means a write or read counts once some minimum number of copies answer ([03](../../research/03-key-value-document-distributed.md)).
- *Vector clocks* (a per-node counter attached to each version) detect concurrent versions. Conflict resolution is pushed "to the reads" and to the application (Dynamo paper). See [Keeping conflicts as data](../ideas/conflicts-kept-as-data.md).

## Strengths and what pays for each

- **Dynamo never refuses a write.** Paid for by no isolation and merging in the application. The cart merge never loses an add, but "deleted items can resurface", and every application must expect several versions of the same item ([03](../../research/03-key-value-document-distributed.md), https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf).
- **DynamoDB has scalable ACID transactions (since 2018).** Customers "asked for full ACID transactions" across items and tables. AWS found long transactions "were not required" and workloads "not highly contentious", so it built *single-shot* transactions (all reads and writes sent in one request) with optimistic timestamp ordering (https://www.usenix.org/conference/atc23/presentation/idziorek). Paid for by: only single-shot transactions, and assuming low contention ([03](../../research/03-key-value-document-distributed.md)). See [Transactions whose reads and writes are known up front](../ideas/read-and-write-sets-known-up-front.md).

## Weaknesses

- In Dynamo, deleted items can resurface (Dynamo paper).
- **Across Regions, two modes** (https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html):
  - Eventual mode (MREC): a transaction is atomic only in its own Region, and other Regions may see part of it.
  - Strong mode (MRSC, generally available 2025-06-30, https://aws.amazon.com/about-aws/whats-new/2025/06/amazon-dynamo-db-global-tables-multi-region-strong-consistency-generally-available/): exactly three Regions (https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DocumentHistory.html), "do not support transaction operations", and a write to an item being changed elsewhere fails with `ReplicatedWriteConflictException` and must be retried.
- Whether MRSC still lacks transactions after mid-2025 was not confirmed; the developer guide said so when fetched ([03](../../research/03-key-value-document-distributed.md)).

## Overlapping work

- A plain write to an item inside a running transaction is rejected with `TransactionConflictException` (https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis.html). See [Optimistic concurrency and version-checked writes](../ideas/optimistic-concurrency.md).
- **Design checked with formal models.** On DynamoDB's replication, 939 lines of TLA+ (a language for describing a design as states and steps) "found three bugs requiring traces of up to 35 steps". The worst could lose data, and had "passed unnoticed through extensive design reviews, code reviews, and testing" ([08](../../research/08-correctness-first-databases.md), https://cacm.acm.org/research/how-amazon-web-services-uses-formal-methods/). AWS now also uses P on DynamoDB (https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/). See [Checking designs with formal models](../ideas/formal-design-models.md).

## What an agent struggles with

The guarantee depends on the mode, the API and the Region. An agent cannot read it from the data ([03](../../research/03-key-value-document-distributed.md), inference). See [Telling the caller what a read or write guarantees](../ideas/consistency-reported-to-the-caller.md).

## Worth borrowing

- **Keep conflicts as data**, as Dynamo does. Cost: every reader must handle more than one version ([03](../../research/03-key-value-document-distributed.md)).
- **Single-shot transactions with optimistic checks.** The whole read and write set is declared up front, which suits a database that wants to analyse what it runs. Cost: no back-and-forth inside a transaction, and retries under contention ([03](../../research/03-key-value-document-distributed.md)).

## Sources

- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf
- https://www.usenix.org/conference/atc23/presentation/idziorek
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis.html
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html
- https://aws.amazon.com/about-aws/whats-new/2025/06/amazon-dynamo-db-global-tables-multi-region-strong-consistency-generally-available/
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DocumentHistory.html
- https://cacm.acm.org/research/how-amazon-web-services-uses-formal-methods/
- https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/
