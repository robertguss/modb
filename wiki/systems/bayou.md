# Bayou

Bayou is a replicated storage system from Xerox PARC, described at SOSP 1995. Its idea is that only the application knows what a conflict is, so every write carries its own conflict check and its own fix ([paper](https://www.cs.utexas.edu/~lorenzo/corsi/cs380d/papers/p172-terry.pdf); [research 06](../../research/06-divergent-copies-and-merging.md)).

## What it is for

Copies of data on machines that are often disconnected, such as laptops, mobile devices or offices on slow links. Each copy (a *replica*) must accept writes offline and catch up later ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Core idea

Every write carries three parts ([paper](https://www.cs.utexas.edu/~lorenzo/corsi/cs380d/papers/p172-terry.pdf)):

1. The update itself.
2. A *dependency check*: a query plus the result the writer expects, for example "room 5 is free at 10:00".
3. A *merge procedure*: code that produces an alternative write if the check fails, for example "book the next free slot".

Writes apply at once as *tentative*. A single primary server fixes the final order, in which they become *committed*. A write that belongs earlier in the order makes the server undo and redo the later ones. A merge procedure that finds no alternative records enough for a person to fix it later ([Recurse Center summary](https://www.recurse.com/blog/53-paper-of-the-week-managing-update-conflicts-in-bayou-a-weakly-connected-replicated-storage-system)). Research 06 notes the paper's PDF extracted as garbled text, so the manual-fallback and undo/redo details come from that summary, not the paper.

## Strengths and what pays for each

- **Conflicts are defined by meaning, not by which bytes changed.** Paid for by: every write carries hand-written check and merge code, and reads can show tentative data that later changes ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **One total order of committed writes.** Paid for by: a primary that delays commits while a replica is disconnected ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **It can catch merges that are clean row by row but wrong in meaning.** Two agents booking the last seat, a meeting edited so it ends before it starts, a discount computed from prices that have since changed: the dependency check is the one mechanism research 06 found that records what the writer assumed, so it can detect all three (inference, [research 06](../../research/06-divergent-copies-and-merging.md)). Paid for by: the writer having to state that assumption.

## Weaknesses

- The primary delays commits while disconnected.
- Readers can see tentative data that later changes.
- Every write needs its own check and merge code, written by hand ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Overlapping work

Like Lotus Notes and [CouchDB](couchdb.md), Bayou accepts every write locally and settles later, with no locks across replicas. When a check fails, it re-runs the write's merge procedure against the agreed order ([research 06](../../research/06-divergent-copies-and-merging.md)).

## What an agent struggles with

Bayou asks the writer to state its assumption up front, which agents rarely do ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Worth borrowing

- **A write that carries its assumption.** Cost: a guard per operation, and a database that stores and re-runs code ([research 06](../../research/06-divergent-copies-and-merging.md)). See [writes that carry their assumptions](../ideas/writes-that-carry-their-assumptions.md).
- **Merge by re-running a named operation against one authority.** [Zero](zero.md) does the same with its server as the primary. Cost: an authority that orders the operations ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **A primary that decides which of two committed worlds came first.** Research 06 lists this as one of five things that agent "multi-world isolation" would need (inference, [research 06](../../research/06-divergent-copies-and-merging.md)). The Berkeley "Supporting Our AI Overlords" paper cites Bayou ([arXiv 2509.00997v2](https://arxiv.org/html/2509.00997v2)). See [branches that reconcile with each other](../ideas/branches-that-reconcile-with-each-other.md).

## Disagreements

- **Whether anything merges by intent.** Research 00 says nobody merges by intent, for example "both branches added stock" (marked as its own inference) ([research 00](../../research/00-landscape-overview.md)). Research 06 describes Bayou's per-write checks and merge procedures as defining conflicts by meaning ([research 06](../../research/06-divergent-copies-and-merging.md)). See [merging by meaning](../ideas/merging-by-meaning.md).

## Sources

- [research 06: Divergent copies and merging](../../research/06-divergent-copies-and-merging.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- Terry et al., SOSP 1995: https://www.cs.utexas.edu/~lorenzo/corsi/cs380d/papers/p172-terry.pdf
- Recurse Center summary: https://www.recurse.com/blog/53-paper-of-the-week-managing-update-conflicts-in-bayou-a-weakly-connected-replicated-storage-system
- Supporting Our AI Overlords: https://arxiv.org/html/2509.00997v2
