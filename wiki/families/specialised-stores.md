# Time-series, search, vector and spatial stores

Stores and indexes built for one kind of question: metrics over time, documents by their words, items nearest in meaning, or shapes near a place. Each buys speed for its question with a weaker or later answer.

## What they are for

- **Time series:** metrics and events that arrive in time order and rarely change ([research 02](../../research/02-analytical-and-specialised.md)).
- **Full-text search:** finding documents by words, ranked by relevance ([research 02](../../research/02-analytical-and-specialised.md)).
- **Vector search:** finding items nearest an **embedding**, a list of numbers standing for meaning ([research 02](../../research/02-analytical-and-specialised.md); [TigerData](https://www.tigerdata.com/blog/vector-database-basics-hnsw)).
- **Spatial:** shapes that overlap or lie near a point or region ([research 02](../../research/02-analytical-and-specialised.md)).

## Members

- [Elasticsearch (Lucene)](../systems/elasticsearch.md): inverted index in immutable segments; writes become searchable only after a refresh.
- [pgvector (HNSW indexes)](../systems/pgvector.md): approximate nearest-neighbour search in PostgreSQL; filters and deletes cut results silently.
- [PostGIS (R-tree indexes)](../systems/postgis.md): spatial indexes over bounding boxes; needs an exact second test.

Mentioned in the sources without a page of their own:

- Prometheus: keeps the current block in memory behind a write-ahead log and compacts two-hour blocks; may refuse out-of-order data ([storage](https://prometheus.io/docs/prometheus/latest/storage/)).
- TimescaleDB (TigerData): tables partitioned automatically by time ("hypertables"), whose cooling chunks convert to a compressed column store ([Pavlo](https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html); [Timescale docs](https://github.com/timescale/docs/blob/latest/use-timescale/compression/modify-compressed-data.md)).
- Apache Lucene: the search library under Elasticsearch, storing its index as immutable segments ([Elastic docs](https://www.elastic.co/docs/manage-data/data-store/near-real-time-search)).
- Weaviate: a vector database whose HNSW delete code shows how tombstones work ([delete.go](https://github.com/weaviate/weaviate/blob/master/adapters/repos/db/vector/hnsw/delete.go)).
- turbopuffer: vector search with object storage as the source of truth, "not tiering"; its "10x lower cost" is an unconfirmed vendor claim ([blog](https://turbopuffer.com/blog/turbopuffer)).
- Redis Query Engine: runs queries on a pool of worker threads, unlike Redis's single command thread ([Redis 8.4](https://redis.io/blog/redis-8-4-open-source-ga/)).
- Qdrant: a vector store that the Chronos research system branches over without changing it ([arXiv 2609.14889](https://arxiv.org/abs/2609.14889)).

## Shared tradeoffs

Research 02's summary, each with what pays for it:

| Kind | Strength | What pays for it | Weakness |
|---|---|---|---|
| Time series (Prometheus, TimescaleDB) | Cheap appends, compression | In-order arrival | Late writes and backfills are costly |
| Search (Lucene, Elasticsearch) | Ranked text search | Immutable segments, periodic refresh | Writes not visible at once |
| Vector (HNSW, pgvector) | Fast similarity search | Approximate answers | Filters and deletes cut recall silently |
| Spatial (R-tree, PostGIS) | Fast spatial candidates | Bounding boxes only | Needs an exact second test |

- **The weak answer is silent.** A search right after a write finds nothing; a filtered vector search returns too few rows with no error; a box test over-counts ([research 02](../../research/02-analytical-and-specialised.md)).
- **Agents do the expensive thing.** Backfilling or fixing past values is the costly path for time series, and agents do exactly that ([research 02](../../research/02-analytical-and-specialised.md)).
- **Ideas research 02 suggests borrowing:**
  - [Derived copies fed from one log](../ideas/derived-copies-fed-from-one-log.md): text, vector and column indexes that never block a write and can be rebuilt. Cost: lag.
  - [Freshness reported to the caller](../ideas/consistency-reported-to-the-caller.md): "does this read include my write?" Cost: a wait on the read path.
  - An approximate index plus an exact check. Cost: a second pass; vectors have no cheap exact check.
- **The vector boom has cooled.** "The buzz around vector databases has muted" ([Pavlo, Jan 2026](https://www.cs.cmu.edu/~pavlo/blog/2026/01/2025-databases-retrospective.html)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- Primary links are given inline above.
