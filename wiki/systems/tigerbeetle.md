# TigerBeetle

TigerBeetle is a ledger database: it stores only accounts and debit/credit transfers between them. It runs on one thread, allocates all its memory at startup, and is tested by a deterministic cluster simulator called the VOPR ([ARCHITECTURE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md); [research 08](../../research/08-correctness-first-databases.md)).

## What it is for

Financial transfers, with correctness under faults and high throughput. Transfers concentrate on a few hot accounts, so they contend whatever you do ([ARCHITECTURE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md)). Research 08 could not confirm its start year.

## Core idea

A fixed schema, one thread, and no memory allocated after startup. It sizes all memory from command-line arguments at startup and never allocates again ([ARCHITECTURE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md)). Research 00 notes that it is not only the state machine that runs on one thread: ARCHITECTURE.md says "TigerBeetle is single-threaded" ([research 00](../../research/00-landscape-overview.md)). The designers argue that a single core "can easily scale to 1mil TPS" ([ARCHITECTURE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md)).

## Strengths and what pays for each

- **Bugs replay exactly.** The VOPR runs a whole cluster on one thread, injects network, disk and process faults, and speeds time up. It is "deterministic based on a seed number and the Git commit" ([vopr.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md)). The vendor says it runs "24/7 on 1024 cores" ([safety](https://docs.tigerbeetle.com/concepts/safety/)); see Disagreements. Paid for by: stubbing out "the clock, network, and disk", and by one thread ([research 08](../../research/08-correctness-first-databases.md)). See [deterministic simulation testing](../ideas/deterministic-simulation-testing.md).
- **No memory bugs of the usual kinds.** Static allocation "designs away memory fragmentation, out-of-memory errors and use-after-frees" ([safety](https://docs.tigerbeetle.com/concepts/safety/)). Paid for by: fixed limits chosen at startup, and giving up a general-purpose data model.
- **No locks.** Paid for by: one thread and a fixed domain ([research 00](../../research/00-landscape-overview.md)).
- **Rich domain rules enforced by the database.** Research 00 says TigerBeetle is the only system that enforces rich domain invariants, and only by hard-coding a single domain (inference, [research 00](../../research/00-landscape-overview.md)). See Disagreements and [invariants the database enforces](../ideas/invariants-the-database-enforces.md).
- **Strong serializability, confirmed independently.** After fixes, Jepsen found it consistent with *strong serializability* (every transaction appears to happen at one instant, in real-time order) through crashes, partitions, clock errors and disk corruption ([Jepsen](https://jepsen.io/analyses/tigerbeetle-0.16.11)).

## Weaknesses

[Jepsen](jepsen.md) found ([Jepsen report](https://jepsen.io/analyses/tigerbeetle-0.16.11)):

- Queries with several filters "often omitted results, even in healthy clusters".
- The client "does not time out".
- Killing one node raised client latency "by three to five orders of magnitude".

TigerBeetle's own analysis: the query bug "only occurs when there are multiple iterators and one of them probes the other". The four fuzzers that ran queries never produced that case, a "blind spot" in their generated workload ([TigerBeetle blog](https://tigerbeetle.com/blog/2025-06-06-fuzzer-blind-spots-meet-jepsen/)). The latency collapse was found by Jepsen, not the VOPR ([research 08](../../research/08-correctness-first-databases.md)).

## Overlapping work

Batched requests run one after another on the one thread, with no locks ([ARCHITECTURE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md)). See [one writer at a time](../ideas/one-writer-at-a-time.md).

## What an agent struggles with

Its fixed schema: only accounts and transfers ([research 08](../../research/08-correctness-first-databases.md)).

## Worth borrowing

- **Fixed limits allocated at startup, with assertions in production.** Cost: every limit becomes a setting the user must choose ([research 08](../../research/08-correctness-first-databases.md)).
- **Disk faults with a moving crash point**, shared with SQLite. Cost: storage becomes an interface of countable writes ([research 08](../../research/08-correctness-first-databases.md)).

## Disagreements

- **The simulator running "24/7 on 1024 cores".** Research 00 lists it among vendor claims it could not confirm ([research 00](../../research/00-landscape-overview.md)). Research 08 states it as a strength and puts "VOPR on 1,024 cores" in its summary table without a vendor mark ([research 08](../../research/08-correctness-first-databases.md)).
- **Whether any general system enforces declared invariants across transactions.** Research 00 says only TigerBeetle enforces rich domain invariants and that no general system lets users declare invariants across transactions; it marks this as inference ([research 00](../../research/00-landscape-overview.md)). Research 05 describes Datomic transaction functions running checks on its single writer and XTDB `ASSERT` predicates that roll a transaction back ([research 05](../../research/05-databases-that-keep-history.md)). Research 06 describes Dolt checking constraints over a merged result ([research 06](../../research/06-divergent-copies-and-merging.md)), and research 04 lists TypeDB constraints in the schema ([research 04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Sources

- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 04](../../research/04-models-that-lost-or-stayed-niche.md), [research 05](../../research/05-databases-that-keep-history.md), [research 06](../../research/06-divergent-copies-and-merging.md) (for the invariants disagreement)
- ARCHITECTURE.md: https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/ARCHITECTURE.md
- VOPR: https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md
- Safety: https://docs.tigerbeetle.com/concepts/safety/
- Jepsen, TigerBeetle 0.16.11: https://jepsen.io/analyses/tigerbeetle-0.16.11 (PDF: https://jepsen.io/analyses/tigerbeetle-0.16.11.pdf)
- Fuzzer blind spots meet Jepsen: https://tigerbeetle.com/blog/2025-06-06-fuzzer-blind-spots-meet-jepsen/
