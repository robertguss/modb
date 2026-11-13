# Bigtable

Bigtable (2006) is Google's sorted map from (row, column, time) to bytes, spread over many servers. It deliberately offered only single-row transactions.

## What it is for

Scale on sorted rows across many servers ([03](../../research/03-key-value-document-distributed.md)).

## Core idea

A sorted map from (row, column, time) to bytes, spread over many servers ([03](../../research/03-key-value-document-distributed.md)). "Bigtable supports single-row transactions ... does not currently support general transactions across row keys" (https://www.usenix.org/legacy/events/osdi06/tech/chang/chang_html/).

## Strengths and what pays for each

- **Scale on sorted rows.** Paid for by single-row atomicity only ([03](../../research/03-key-value-document-distributed.md)).
- **Restraint.** The team skipped general transactions until there was a clear use. They found "most applications require only single-row transactions", and that requests for more were mainly about secondary indexes (https://www.usenix.org/legacy/events/osdi06/tech/chang/chang_html/). Paid for by users coding around the gap meanwhile ([03](../../research/03-key-value-document-distributed.md)).

## Weaknesses

- Hard to use for evolving schemas. Spanner's authors reported "consistently received complaints" that Bigtable was hard to use "for ... complex, evolving schemas, or ... strong consistency in the presence of wide-area replication". Many teams chose Megastore "despite its relatively low performance" (https://doi.org/10.1145/2491245).
- Their conclusion: "it is better to have application programmers deal with performance problems due to overuse of transactions ... rather than always coding around the lack of transactions" (same source). That led to [Spanner](spanner.md).

## What an agent struggles with

Secondary indexes kept by hand across rows go stale after partial failures ([03](../../research/03-key-value-document-distributed.md), inference).

## Worth borrowing

**Bigtable's restraint.** Add a general feature only after real use demands it. Cost: some users code around the gap meanwhile, as Spanner's authors found ([03](../../research/03-key-value-document-distributed.md)).

## Sources

- [03-key-value-document-distributed.md](../../research/03-key-value-document-distributed.md)
- https://www.usenix.org/legacy/events/osdi06/tech/chang/chang_html/
- https://doi.org/10.1145/2491245
