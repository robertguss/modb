# Apache Iceberg

Apache Iceberg is an open table format. A table is many data files in object storage, tracked by metadata files, and a commit swaps one pointer. It belongs to the [analytical and lakehouse family](../families/analytical-and-lakehouse.md).

## What it is for

- Warehouse tables kept as open files in cheap object storage, readable by many engines ([research 02](../../research/02-analytical-and-specialised.md)). See [object storage as the only durable store](../ideas/object-storage-as-source-of-truth.md).

## Core idea

- **A table is many files tracked by metadata files.** A writer prepares new metadata, then "commits by swapping the table's metadata file pointer". If another commit won, it must retry on the new version ([Iceberg spec](https://iceberg.apache.org/spec/)). This is [optimistic concurrency](../ideas/optimistic-concurrency.md): no locks, and a check at commit.
- **When retries run out** the commit fails with `CommitFailedException` ([AWS blog](https://aws.amazon.com/blogs/big-data/manage-concurrent-write-conflicts-in-apache-iceberg-on-the-aws-glue-data-catalog/)).
- Each change writes several new files, and old files are kept until cleanup runs, which is what makes reading an earlier commit possible ([research 02](../../research/02-analytical-and-specialised.md)). See [write-once pieces merged in the background](../ideas/immutable-pieces-with-background-merge.md).

## Strengths and what pays for each

- **Open format and separate compute.** *Paid for by* slow small writes: each change writes several files ([research 02](../../research/02-analytical-and-specialised.md)).
- **[Time travel](../ideas/time-travel-queries.md)**, reading an earlier commit. *Paid for by* keeping old files until cleanup runs ([research 02](../../research/02-analytical-and-specialised.md)).

## Weaknesses

- **Slow small writes and concurrent writes; retries** ([research 02](../../research/02-analytical-and-specialised.md)). DuckLake's authors name "small changes and many concurrent changes" as the two biggest performance problems of data lakes ([DuckLake manifesto](https://ducklake.select/manifesto/)).

## Overlapping work

- Writers race to swap the metadata pointer. The loser retries on the new version, and fails after its retries run out ([Iceberg spec](https://iceberg.apache.org/spec/); [AWS blog](https://aws.amazon.com/blogs/big-data/manage-concurrent-write-conflicts-in-apache-iceberg-on-the-aws-glue-data-catalog/)).

## What an agent struggles with

From research 02:

- **Commit failures that need a retry policy.**
- **Compaction and snapshot expiry that nobody owns.**

## Sources

- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- Primary links are given inline above.
