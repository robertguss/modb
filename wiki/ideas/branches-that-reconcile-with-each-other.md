# Many branches that reconcile with each other

Many agents each work on their own branch, and the branches must be reconciled with one another, not only with the main copy. Berkeley researchers call this "multi-world isolation"; nothing ships it today.

## What it is

The Berkeley paper "Supporting Our AI Overlords" asks for branches "logically isolated, but may physically overlap", forks that "reconcile not just with the mainline, but with each other", and "ultra-fast rollbacks" (https://arxiv.org/html/2509.00997v2). It calls this "multi-world isolation" and describes it as "MVCC on steroids" ([09](../../research/09-agents-and-databases-today.md)). *MVCC* is multi-version concurrency control, where each transaction reads its own snapshot; see [Multi-version snapshots](multi-version-snapshots.md).

## The problem it solves

Agents explore. The Berkeley paper reports that at Neon, agents created 20× more branches and did 50× more rollbacks than humans (https://arxiv.org/html/2509.00997v2). Branches today reconcile only with their parent, if at all ([06](../../research/06-divergent-copies-and-merging.md)). Two agents' changes can each be fine alone but wrong together; merges that match on primary key and CRDTs that merge without coordination cannot tell (inference, [09](../../research/09-agents-and-databases-today.md)).

## What it costs

The researcher's inference from the sources together ([06](../../research/06-divergent-copies-and-merging.md)) is that it would need five things. Nothing found ships all five.

1. **Shared storage without slow reads.** BranchBench shows nobody has this yet (https://arxiv.org/abs/2604.17180). See [Cheap branches that share storage](copy-on-write-branches.md).
2. **Abort as the cheap path**, given how often agents roll back.
3. **A rule for siblings.** The simplest working one is first-commit-wins with sibling invalidation, from a 2026 OS paper on agent exploration (https://arxiv.org/abs/2602.08199). It is safe, but wastes work in losing branches. Anything richer needs what each branch read, its guard, and rules checked over the merged result. See [Writes that carry their assumptions](writes-that-carry-their-assumptions.md).
4. **Atomic merge across every store an agent touched**, as [Chronos](../systems/chronos.md) does (https://arxiv.org/abs/2609.14889).
5. **A final order.** A [Bayou](../systems/bayou.md)-style primary decides which of two committed worlds came first ([06](../../research/06-divergent-copies-and-merging.md)).

## Systems that use it

None in full. Pieces:

- [Neon](../systems/neon.md): many cheap branches, no merge (https://neon.com/docs/guides/reset-from-parent).
- [Dolt](../systems/dolt.md): branches merge back with a three-way merge, against a common ancestor ([06](../../research/06-divergent-copies-and-merging.md)).
- [Chronos](../systems/chronos.md): atomic merge across stores; conflict rules unclear ([06](../../research/06-divergent-copies-and-merging.md)).
- [Bayou](../systems/bayou.md): a primary fixes one total order of committed writes, and each write carries a check and a merge procedure ([06](../../research/06-divergent-copies-and-merging.md)). The Berkeley paper cites Bayou and TARDiS, a store with branches as a first-class part of weak consistency (https://www.cs.utexas.edu/lasr/paper.php?uid=96).

## Disagreements

- **Where the 50× rollback figure comes from.** [06](../../research/06-divergent-copies-and-merging.md) states that Neon saw 50× more rollbacks from agents, with no citation. [09](../../research/09-agents-and-databases-today.md) attributes the 20× branches and 50× rollbacks to the Berkeley paper, reporting Neon data, and treats Neon's agent figures as vendor numbers.
- **Can Neon merge a branch back?** [06](../../research/06-divergent-copies-and-merging.md) states as fact that it cannot. [09](../../research/09-agents-and-databases-today.md) reaches the same conclusion but marks it as its own reading of the docs.

## Sources

- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://arxiv.org/html/2509.00997v2
- https://arxiv.org/abs/2604.17180
- https://arxiv.org/abs/2602.08199
- https://arxiv.org/abs/2609.14889
- https://neon.com/docs/guides/reset-from-parent
- https://www.cs.utexas.edu/lasr/paper.php?uid=96
