# Zero

Zero is a sync engine that keeps in each client the subset of rows the app's queries need ([Zero docs](https://zero.rocicorp.dev/docs/when-to-use); [research 00](../../research/00-landscape-overview.md)). Its writes are named functions that run on the client first and again on the server. Version 1.0 shipped in 2026 ([InfoQ, 2026-06](https://www.infoq.com/news/2026/06/zero-version-1/)).

## What it is for

Fast local reads of server data in apps, with writes that show at once and are confirmed later ([research 06](../../research/06-divergent-copies-and-merging.md)). Research 00 says sync systems drop the assumption that clients fetch data by request and response, and get local reads and offline use ([research 00](../../research/00-landscape-overview.md)).

## Core idea

The server is the authority; the client holds a guess. Each *mutator* (a named write function) runs "optimistically on the client and authoritatively on the server". When server state arrives, the client re-runs its pending mutators on top of it. This is a *rebase*, as in git ([Zero mutators](https://zero.rocicorp.dev/docs/mutators)).

## Strengths and what pays for each

- **Merging by re-running the operation, not by combining states.** Paid for by: a server that can be reached, and writes written as code it can re-run ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Weaknesses

- A rejected write surfaces late, away from the code that made it ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Overlapping work

Concurrent writes are ordered by the server. The authoritative run of each mutator decides the result, and clients rebase their pending mutators onto it ([Zero mutators](https://zero.rocicorp.dev/docs/mutators)).

## Worth borrowing

The named mutator re-run on authoritative state. Research 06 calls it "Bayou's idea with the server as primary" (see [Bayou](bayou.md)). Cost: an authority that orders the operations ([research 06](../../research/06-divergent-copies-and-merging.md)). See [writes that carry their assumptions](../ideas/writes-that-carry-their-assumptions.md) and [deterministic functions as transactions](../ideas/deterministic-functions-inside-transactions.md).

## Sources

- [research 06: Divergent copies and merging](../../research/06-divergent-copies-and-merging.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- Zero, when to use: https://zero.rocicorp.dev/docs/when-to-use
- Zero mutators: https://zero.rocicorp.dev/docs/mutators
- Zero 1.0: https://www.infoq.com/news/2026/06/zero-version-1/
