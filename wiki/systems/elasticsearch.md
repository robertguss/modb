# Elasticsearch (Lucene)

Elasticsearch is a full-text search engine built on the Lucene library. It finds documents by the words in them and ranks them by relevance. It belongs to the [time-series, search, vector and spatial family](../families/specialised-stores.md).

## What it is for

- Finding documents by words, ranked by relevance ([research 02](../../research/02-analytical-and-specialised.md)).

## Core idea

- **An inverted index** maps each word to the documents that contain it ([research 02](../../research/02-analytical-and-specialised.md)).
- **[Write-once pieces merged in the background](../ideas/immutable-pieces-with-background-merge.md).** Lucene stores the index as immutable **segments**. A document becomes searchable only after a **refresh** ([near-real-time search](https://www.elastic.co/docs/manage-data/data-store/near-real-time-search)).
- Elasticsearch refreshes every second, "but only on indices that have received one search request or more in the last 30 seconds" (same page).

## Strengths and what pays for each

- **Fast ranked search.** *Paid for by* **near-real-time** visibility (a write is not searchable at once) and by segment merging ([research 02](../../research/02-analytical-and-specialised.md)).

## Weaknesses

- **Writes are not visible at once** ([near-real-time search](https://www.elastic.co/docs/manage-data/data-store/near-real-time-search)).

## Overlapping work

- **[Optimistic concurrency](../ideas/optimistic-concurrency.md) per document.** A write carries `if_seq_no` and `if_primary_term` and fails if the document changed since it was read ([optimistic concurrency control](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/optimistic-concurrency-control)).

## What an agent struggles with

- **Write, search at once, find nothing** ([research 02](../../research/02-analytical-and-specialised.md)).

## Worth borrowing

From research 02:

- **Freshness in the interface.** Like Elasticsearch's refresh, an agent could ask "does this read include my write?" Cost: a wait on the read path. See [consistency reported to the caller](../ideas/consistency-reported-to-the-caller.md).
- **Derived indexes fed from one log.** Text, vector and column copies that never block a write and can be rebuilt. Cost: lag. See [derived copies fed from one log](../ideas/derived-copies-fed-from-one-log.md).

## Sources

- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- Primary links are given inline above.
