# MongoDB

MongoDB is a document database: it stores JSON-like documents and embeds data that is used together. It began with single-document atomicity and added joins, schema validation and multi-document transactions step by step.

## What it is for

Avoiding joins and the mismatch between objects and tables: "data accessed together is stored together", in nested JSON-like documents ([00](../../research/00-landscape-overview.md), https://www.mongodb.com/docs/manual/data-modeling/). The 2009 start year comes from memory in the research file ([03](../../research/03-key-value-document-distributed.md), not confirmed).

## Core idea

JSON-like documents. Data used together is embedded together. "An operation on a single document is atomic" ([03](../../research/03-key-value-document-distributed.md), https://www.mongodb.com/docs/manual/core/write-operations-atomicity/).

## Strengths and what pays for each

- **Documents read in one go.** Paid for by embedding instead of joins ([03](../../research/03-key-value-document-distributed.md)).
- **Features added back step by step** ([03](../../research/03-key-value-document-distributed.md)):
  - `$lookup`, a left outer join (https://www.mongodb.com/docs/v7.0/reference/operator/aggregation/lookup/).
  - JSON Schema validation from 3.6 (https://www.mongodb.com/docs/v5.0/core/schema-validation/). See [Rules the database enforces across transactions](../ideas/invariants-the-database-enforces.md).
  - Multi-document transactions in 4.0 (2018) for replica sets, extended to sharded clusters in 4.2 (vendor blog, https://www.mongodb.com/company/blog/product-release-announcements/mongodb-multi-document-acid-transactions-general-availability). Paid for by cost: the docs warn that transactions cost more and "should not be a replacement for effective schema design" (https://www.mongodb.com/docs/manual/core/transactions/).

## Weaknesses

- **Unsafe defaults in the past.** Jepsen found that 4.2.6 transactions violated snapshot isolation under default settings. They "appeared to lose acknowledged writes" because transactions ignored safer client settings and fell back to `w: 1` (https://jepsen.io/analyses/mongodb-4.2.6). Since 5.0 the default write concern is `majority` (vendor PDF, https://webassets.mongodb.com/mongodb_whats_new_5.0.pdf). See [Replying only after a write is durable](../ideas/reply-only-after-durable-write.md).
- **On a partition:** one primary per replica set. With `majority`, writes on the minority side fail; with weaker settings, they can be rolled back later ([03](../../research/03-key-value-document-distributed.md)).
- **Spec and code did not match.** MongoDB tried to check that real server traces matched its TLA+ specification. "This whole experiment failed. Our traces never matched our specification." Generating tests from the spec did work for a smaller algorithm ([08](../../research/08-correctness-first-databases.md), https://vldb.org/pvldb/vol13/p1346-davis.pdf, https://www.mongodb.com/company/blog/engineering/conformance-checking-at-mongodb-testing-our-code-matches-our-tla-specs). See [Checking designs with formal models](../ideas/formal-design-models.md).
- A one-minute default limit on transaction runtime was seen only in a secondary source ([03](../../research/03-key-value-document-distributed.md), not confirmed).

## Overlapping work

Multi-document transactions since 4.0/4.2, and a write concern chosen per call ([03](../../research/03-key-value-document-distributed.md)).

## What an agent struggles with

The guarantee is a setting passed with each call, and the old defaults were unsafe ([03](../../research/03-key-value-document-distributed.md), inference). See [Telling the caller what a read or write guarantees](../ideas/consistency-reported-to-the-caller.md).

## Worth borrowing

**State the guarantee in the reply.** MongoDB, like the rest of its family, hides its consistency level in configuration. Saying "durable on a majority" in each answer would cost bytes and design effort ([03](../../research/03-key-value-document-distributed.md), inference).

## Sources

- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- [08-correctness-first-databases.md](../../research/08-correctness-first-databases.md)
- https://www.mongodb.com/docs/manual/data-modeling/
- https://www.mongodb.com/docs/manual/core/write-operations-atomicity/
- https://www.mongodb.com/docs/v7.0/reference/operator/aggregation/lookup/
- https://www.mongodb.com/docs/v5.0/core/schema-validation/
- https://www.mongodb.com/company/blog/product-release-announcements/mongodb-multi-document-acid-transactions-general-availability
- https://www.mongodb.com/docs/manual/core/transactions/
- https://jepsen.io/analyses/mongodb-4.2.6
- https://webassets.mongodb.com/mongodb_whats_new_5.0.pdf
- https://vldb.org/pvldb/vol13/p1346-davis.pdf
- https://www.mongodb.com/company/blog/engineering/conformance-checking-at-mongodb-testing-our-code-matches-our-tla-specs
