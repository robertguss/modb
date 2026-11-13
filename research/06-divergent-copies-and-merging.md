Research run on 2026-11-13 by a subagent using Exa, for the ticket [Divergent copies and merging](../issues/06-divergent-copies-and-merging.md). Sections 5 to 7 mix sourced facts with the researcher's inference; inference is marked.

# Divergent copies and merging (researched 2026-11-13)

The question throughout: when both copies changed, who decides the result, and what does that decider know?

## 1. Replication conflicts: Lotus Notes, Bayou, CouchDB

**What they are for.** Copies on machines that are often disconnected (laptops, mobile devices, offices on slow links) must accept writes offline and catch up later. A *replica* is one such copy.

**Lotus Notes / Domino.** When two replicas edit the same document, the copy "edited and saved the most times" wins; on a tie, the latest save wins. The loser is kept as a "Replication or Save Conflict" document for a person to sort out. A form can opt into field-level merging when no field changed on both sides https://help.hcl-software.com/domino/14.5.0/admin/admn_replicationorsaveconflicts_c.html.

- Strength: nothing is lost. Paid for by: a person cleaning up conflict documents by hand.
- Weakness: the winner rule (most saves) has nothing to do with meaning.

**Bayou (Xerox PARC, SOSP 1995).** The paper's idea is that only the application knows what a conflict is https://www.cs.utexas.edu/~lorenzo/corsi/cs380d/papers/p172-terry.pdf. Every write carries three parts: the update, a *dependency check* (a query plus the result it expects, for example "room 5 is free at 10:00"), and a *merge procedure* (code that produces an alternative write if the check fails, for example "book the next free slot"). Writes apply at once as *tentative*; a single primary server fixes the final order, in which they become *committed*. A write that belongs earlier makes the server undo and redo later ones. A merge procedure that finds no alternative records enough for a person to fix it later https://www.recurse.com/blog/53-paper-of-the-week-managing-update-conflicts-in-bayou-a-weakly-connected-replicated-storage-system.

- Strength: conflicts are defined by meaning, not by which bytes changed. Paid for by: every write carries hand-written check and merge code; reads can show tentative data that later changes.
- Strength: one total order of committed writes. Paid for by: a primary that delays commits while disconnected.

**CouchDB.** On conflict every node picks the same winner by a deterministic rule and keeps the losers. A plain `GET` returns the winner with "no indication" that others exist; the application must ask for `_conflicts` and "must always resolve conflicts" https://docs.couchdb.org/en/stable/replication/conflicts.html.

- Strength: all copies converge with no coordination. Paid for by: conflicts that are silent unless code asks.

**Many clients.** All three accept every write locally and settle later, with no locks across replicas.

**What an agent would struggle with.** CouchDB and Notes return a winner that looks normal; an agent that does not ask for conflicts builds on a value that silently replaced someone's work. Bayou asks the writer to state its assumption up front, which agents rarely do.

**Worth borrowing.** Bayou's write-with-its-assumption. Cost: a guard per operation, and a database that stores and re-runs code.

## 2. Version-controlled data: Dolt, lakeFS, Neon, Xata, Chronos

**What it is for.** Git's workflow (branch, change, review the diff, merge) for tables or files. *Copy-on-write* means a new branch shares storage with its parent until something changes.

**Dolt** does a *three-way merge*: it compares each side with their last common ancestor (the *merge base*) and keeps whichever side changed, matching rows by primary key. A conflict happens only when both sides set the same row and column to different values https://www.dolthub.com/docs/concepts/dolt/git/merge/. Conflicts land in `dolt_conflicts_<table>` (base, ours, theirs); foreign-key and unique-key breakages land in `dolt_constraint_violations`, which blocks commit until empty unless forced https://www.dolthub.com/blog/2021-07-20-merging-branches-with-foreign-keys/. Merge also verifies check constraints on the merged rows; Dolt calls its merge rules "one of the more complex product problems that we face" https://www.dolthub.com/blog/2023-07-19-three-way-diff-merge/.

In May 2026 Dolt reported that most users "experience conflicts very rarely" because they design them away: short branches, one writer per row. On agents: "Agents might help this process in the future but not yet" https://www.dolthub.com/blog/2026-05-27-conflicts-in-the-wild/ (vendor statement).

**lakeFS** merges files in object storage. The three-way merge compares whole objects; a file changed on both sides is a conflict, and the merge fails unless the caller picks `source-wins` or `dest-wins` https://docs.lakefs.io/v1.83/understand/how/merge/. A `pre-merge` hook can run checks and fail the merge; the docs say it "runs on the source branch" https://docs.lakefs.io/guides/hooks/.

**Neon and Xata** branch Postgres with copy-on-write but do not merge data. Neon's "reset from parent" is "a complete overwrite ... not a refresh or a merge" https://neon.com/docs/guides/reset-from-parent. Xata branches are "independent PostgreSQL instances" after creation https://xata.io/docs/platform/branch.

**Chronos** (MIT, 2026-09) adds branches over Postgres, SQLite, DuckDB and Qdrant unchanged, by query rewriting. For merging it adds "atomic cross-store visibility": a merge never appears in one store before another https://arxiv.org/abs/2609.14889.

**BranchBench** (2026-04) found "a fundamental tension": systems built for fast branching read up to 5 to 4000 times slower as branches deepen; systems built for fast reads branch 25 to 1500 times slower. "No current system supports the representative workloads at scale" https://arxiv.org/abs/2604.17180.

- Strength: cheap branches and a reviewable diff. Paid for by: shared storage that slows reads on deep branch chains.
- Strength (Dolt): merges usually finish without a person. Paid for by: stable primary keys, and "no conflict" meaning only "no cell changed on both sides".
- Weakness: Neon and Xata, the products agents use most, have no way back except overwrite or migrations.

**Many clients.** Each writer gets a branch; overlap shows up only at merge time.

**What an agent would struggle with.** Choosing between base, ours and theirs needs both sides' intent, which a branch does not record. lakeFS's `source-wins` is a flag that makes a conflict disappear.

**Worth borrowing.** Conflicts and violations as queryable tables that block commit. Cost: every rule checked over the merged result, not each side.

## 3. Data types that merge themselves: Automerge, Yjs

**What they are for.** Collaborative and offline-first apps where every device edits at once. A *CRDT* (conflict-free replicated data type) is a structure whose merge is defined so that copies which have seen the same edits are identical, in any order. Yjs updates are "commutative, associative, and idempotent" https://docs.yjs.dev/api/document-updates.

**Where they stop.** Automerge says the one case it "cannot handle automatically, because there is no well-defined resolution" is two writers setting the same property; it picks a winner that is the same everywhere and exposes the losers through `getConflicts` https://automerge.org/docs/reference/documents/conflicts/. Convergence is not usefulness: several published text CRDTs interleave two people's concurrent insertions character by character, "resulting in an unreadable jumble of letters" https://martin.kleppmann.com/2019/03/25/papoc-interleaving-anomalies.html. (The authors' errata, same page, says their own fix did not converge.)

- Strength: no conflicts to resolve, no server needed. Paid for by: the merge can never reject a write, so rules that need rejection (uniqueness, "never below zero") cannot be kept (section 5).
- Weakness: the winner of a same-field clash is arbitrary.

**Agents.** Electric runs an agent as a Yjs peer that "merges everything without coordination" (2026-04-08) https://electric.ax/blog/2026/04/08/ai-agents-as-crdt-peers-with-yjs. That suits text; it does not stop two agents claiming the last item.

**Worth borrowing.** For data whose rules are merge-safe (growing sets, unbounded counters, append-only logs), merge-by-construction removes conflicts. Cost: the type system must know which data is which.

## 4. Sync engines: Electric, Zero, PowerSync

**What they are for.** Fast local reads of server data in apps; writes show at once and are confirmed later.

**The shared idea.** The server is the authority; the client holds a guess. Electric syncs reads only and sends writes through "your existing API", warning that after a rejection "the original write context is much harder to reconstruct" https://electric.ax/docs/sync/guides/writes. Zero runs each *mutator* (a named write function) "optimistically on the client and authoritatively on the server"; when server state arrives, the client re-runs its pending mutators on top of it (a *rebase*) https://zero.rocicorp.dev/docs/mutators. PowerSync's default is per-field last-writer-wins, decided by arrival order at the server. Its upload queue is first-in-first-out and blocks while a write is unacknowledged, so the docs advise returning success and reporting validation errors through a synced table https://docs.powersync.com/handling-writes/handling-update-conflicts.

- Strength: merge by re-running the operation, not by combining states. Paid for by: a reachable server, and writes as code it can re-run.
- Weakness: a rejected write surfaces late, away from the code that made it.

**Worth borrowing.** Zero's named mutator re-run on authoritative state: Bayou's idea with the server as primary.

## 5. What a merge can decide by itself (deep dive)

*Invariant confluence* (I-confluence) draws the exact line. Operations are I-confluent for a rule (an *invariant*) if any two valid states grown from a common ancestor always merge into a valid state; only then can the rule be kept without coordination https://www.vldb.org/pvldb/vol8/p185-bailis.pdf. The paper's Table 2:

| Rule | Operation | Merge alone keeps it? |
|---|---|---|
| Uniqueness | insert with a chosen value | No |
| Uniqueness | insert with any fresh value | Yes |
| Auto-increment id | insert | No |
| Foreign key | insert | Yes |
| Foreign key | delete | No (cascading delete: yes) |
| Secondary index, materialised view | update | Yes |
| Counter > k | increment / decrement | Yes / No |

A merge decides by itself only for rules shaped like the "yes" rows. "Stock never below zero" and "this id is new" are "no" rows: one side must see the other, or something decides afterwards. The systems above answer "no" rows in one of four ways: pick a winner silently (Notes, CouchDB, Automerge, lakeFS flags, PowerSync), stop and ask (Dolt, lakeFS default), re-run the operation with its guard against a single authority (Bayou, Zero), or never merge (Neon, Xata).

## 6. Merges correct row by row but wrong in meaning

Inference, built from the sources above. A cell-level merge reports success whenever no cell changed on both sides. These pass cleanly:

- **Two agents book the last seat.** Each inserts a different booking row: different keys, no conflict, capacity exceeded. This is the "Counter > k, decrement" row.
- **A row neither side wrote.** One branch moves a meeting's start, the other its end. The cell-wise merge may produce a meeting that ends before it starts; Dolt catches it only if a check constraint was declared.
- **Stale reasoning.** Agent A reads prices and writes a discount table; agent B changes prices. No shared cell, so nothing flags that A's output came from data that no longer exists.

The common cause: the merge sees what was written, not what was read or assumed. Bayou's dependency check is the one mechanism here that records the assumption, so it can detect all three.

## 7. What "multi-world isolation" would require

The Berkeley paper asks for branches "logically isolated, but may physically overlap", forks that "reconcile not just with the mainline, but with each other", and "ultra-fast rollbacks" https://arxiv.org/html/2509.00997v2. It cites Bayou and TARDiS, a store with branches as a first-class part of weak consistency https://www.cs.utexas.edu/lasr/paper.php?uid=96.

Inference from the sources together: it would need

1. **Shared storage without slow reads.** BranchBench shows nobody has this yet.
2. **Abort as the cheap path**, since Neon saw 50× more rollbacks from agents.
3. **A rule for siblings.** The simplest working one is first-commit-wins with sibling invalidation, from a 2026 OS paper on agent exploration https://arxiv.org/abs/2602.08199: safe, but wasteful. Anything richer needs what each branch read, its guard, and rules checked over the merged result.
4. **Atomic merge across every store an agent touched**, as Chronos does.
5. **A final order**: a Bayou-style primary decides which of two committed worlds came first.

Nothing found ships items 1 to 5 together.

## Summary table

| System | Strength | What pays for it | Weakness |
|---|---|---|---|
| Lotus Notes | Loser kept, visible | Manual cleanup | Winner by save count, not meaning |
| Bayou | Conflicts defined by the app | Every write carries check + merge code; tentative reads | Primary delays commits |
| CouchDB | Converges with no coordination | Silent conflicts | Plain read hides losers |
| Dolt | Cell-level automatic merge; violations as tables | Stable keys; constraints declared | Clean merge can still be wrong in meaning |
| lakeFS | Cheap branches of huge files | Whole-file granularity | Conflict = whole file; win-flags hide it |
| Neon, Xata | Instant copy-on-write branches | No merge at all | Way back is overwrite or migrations |
| Chronos | Atomic merge across stores | Query rewriting; research only | Merge semantics beyond visibility unclear |
| Automerge, Yjs | No conflicts, no server | Merge can never reject | Rules needing rejection unenforceable |
| Zero | Re-runs named mutators on server | Server reachable; writes as code | Rejection arrives late |
| PowerSync, Electric | Simple write path (field-level last-writer-wins; your own API) | Arrival order decides, or you build it | Blocking queue; lost context on rejection |

## Ideas worth borrowing

- **Writes that carry their assumption** (Bayou). Cost: a guard per operation; stored code.
- **Merge by re-running named operations, not combining states** (Zero, Bayou). Cost: an authority that orders them.
- **Conflicts and broken rules as tables that block commit** (Dolt). Cost: checks over the merged result.
- **Merge-safe data marked by type** (I-confluence, CRDTs). Cost: types that know rule shapes.
- **First-commit-wins for siblings** as the starting rule. Cost: work lost in losing branches.

## What I could not confirm

- Founding years of Lotus Notes, CouchDB, Dolt and Automerge: no primary source found.
- The Bayou PDF extracted as garbled text; the manual-fallback and undo/redo details come from a summary.
- Whether lakeFS's `pre-merge` hook sees the merged result or only the source branch.
- Xata: I found no merge in its docs, but no explicit statement either.
- Chronos's conflict rules: the abstract covers visibility, not how clashing changes are decided.
- Dolt's "conflicts are rare" is a vendor statement about its own users.
