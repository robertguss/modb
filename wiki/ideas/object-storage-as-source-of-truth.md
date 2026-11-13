# Object storage as the only durable store

All durable data lives in cloud object storage, a cheap network store of whole files, and the machines that run queries keep at most a cache. Lakehouse table formats and some newer search systems are built this way.

## What it is

- **turbopuffer** is "not tiering": object storage is the source of truth ([turbopuffer blog](https://turbopuffer.com/blog/turbopuffer)).
- **Apache Iceberg** keeps a table as many files tracked by metadata files, and commits by swapping a metadata pointer ([Iceberg spec](https://iceberg.apache.org/spec/)).
- **DuckLake** keeps data as Parquet files but moves all metadata into a SQL database ([DuckLake 0.1](https://ducklake.select/2025/05/27/ducklake-01/); [manifesto](https://ducklake.select/manifesto/)).
- **lakeFS** adds branches over files in object storage. Creating a branch is a metadata-only operation ([lakeFS](https://docs.lakefs.io/quickstart/branch/)), and merges compare whole objects ([lakeFS merge](https://docs.lakefs.io/v1.83/understand/how/merge/)).

## The problem it solves

- **Cost.** Research 00 names the cost of object storage, with agents, as what drives the 2024 to 2026 wave ([research 00](../../research/00-landscape-overview.md)).
- **Any node can serve any data.** turbopuffer and DuckLake dropped the assumptions that data lives on local disks and that metadata lives in files, and got "cheap storage, any node can serve any data" ([research 00](../../research/00-landscape-overview.md)).
- **Open formats and separate compute.** Warehouse tables become open files that many engines can read ([research 02](../../research/02-analytical-and-specialised.md)).
- **The cloud's direction.** One reason given for the decline of HTAP is that the cloud favoured object storage over fast local disks ([Neon blog](https://neon.com/blog/htap-is-dead)).

## What it costs

- **Slow small writes.** Each change writes several files ([research 02](../../research/02-analytical-and-specialised.md)).
- **Retries under concurrent commits.** In Iceberg, if another commit won, the writer must retry on the new version; when retries run out the commit fails with `CommitFailedException` ([Iceberg spec](https://iceberg.apache.org/spec/); [AWS blog](https://aws.amazon.com/blogs/big-data/manage-concurrent-write-conflicts-in-apache-iceberg-on-the-aws-glue-data-catalog/)).
- DuckLake's authors name "small changes and many concurrent changes" as the two biggest performance problems of data lakes ([manifesto](https://ducklake.select/manifesto/)). Their answer is to make each commit one transaction in a SQL catalog and to store small changes in the catalog itself; the cost is throughput capped by that catalog ([research 02](../../research/02-analytical-and-specialised.md)).
- **Cleanup nobody owns.** Old files are kept until cleanup runs, and compaction and snapshot expiry need an owner ([research 02](../../research/02-analytical-and-specialised.md)).
- **Coarse conflicts.** lakeFS treats a file changed on both sides as a conflict, and the merge fails unless the caller picks `source-wins` or `dest-wins` ([lakeFS merge](https://docs.lakefs.io/v1.83/understand/how/merge/)).
- **Unconfirmed savings.** turbopuffer's "10x lower cost" is a vendor claim research 00 could not confirm.

## Systems that use it

- [Apache Iceberg](../systems/iceberg.md): table files and metadata in object storage.
- [DuckLake](../systems/ducklake.md): data files in object storage, metadata in a SQL database.
- [lakeFS](../systems/lakefs.md): branches and merges over object-storage files.
- turbopuffer (no page): object storage as the source of truth for search.

## Cannot be combined with

- **Fast small and concurrent commits, with metadata also in object storage.** DuckLake's authors call these the biggest data-lake problems, and DuckLake fixes them only by moving metadata into a SQL database ([manifesto](https://ducklake.select/manifesto/)).

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/02-analytical-and-specialised.md](../../research/02-analytical-and-specialised.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- Primary links are given inline above.
