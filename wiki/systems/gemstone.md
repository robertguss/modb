# GemStone/S

GemStone/S is an object database: a shared, transactional, persistent Smalltalk in which programming-language objects are stored directly. It uses optimistic concurrency, with special classes that let some concurrent changes combine instead of conflict.

## What it is for

Object databases appeared in the mid-1980s, aimed at engineering and design software. The goal was to store programming-language objects directly instead of writing load and unload code ([04](../../research/04-models-that-lost-or-stayed-niche.md), https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf). GemStone/S is a shared, transactional, persistent Smalltalk ([07](../../research/07-code-inside-the-database.md)).

## Core idea

- Persistent Smalltalk objects with *optimistic concurrency*: "read and write objects as if you were the only user", and the server checks for conflicts only at commit (https://downloads.gemtalksystems.com/docs/GemStone64/3.6.x/GS64-ProgGuide-3.6.pdf). At commit it compares "your write set with those of all other transactions that committed since your transaction began" (https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/9-Transactions.htm). See [Optimistic concurrency and version-checked writes](../ideas/optimistic-concurrency.md).
- A failed commit cannot be retried as is; "you must abort the transaction in order to get a new view" (3.6 guide).
- *Reduced-conflict* (Rc) classes, such as counters and bags, replay their changes at commit, so two sessions adding to the same bag do not conflict (3.6 guide).
- **Code and data together.** Each class keeps a *class history* of versions. Old instances "continue to access the old class's methods" until migrated, one, some or all at a time ([07](../../research/07-code-inside-the-database.md), https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/11-ClassHistory.htm).

## Strengths and what pays for each

- **No mismatch between program and storage, near-memory speed.** GemStone paid with aborts that grow with transaction length ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Rc classes avoid false conflicts.** Paid for by merge rules written per class ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Per-instance migration when code changes.** Paid for by image-only tooling and optimistic conflicts ([07](../../research/07-code-inside-the-database.md)).

## Weaknesses

- Retry means abort and redo ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **Why object databases lost** (2005 paper, via [04](../../research/04-models-that-lost-or-stayed-niche.md)): no leverage, since saving a load program "is not a major service"; no standards; and "relink the world": changing a method on stored objects meant relinking every program that used it.
- Smalltalk images share data poorly between applications; weak collaboration has been "blamed for the limited commercial success of Smalltalk", and version control "cannot even comprehend schema change" ([07](../../research/07-code-inside-the-database.md), https://book.seaside.st/book/advanced/persistency/image-based-persistency, https://arxiv.org/pdf/2110.08993).

## Overlapping work

Optimistic: write sets compared at commit; Rc classes help where collisions are likely ([07](../../research/07-code-inside-the-database.md)).

## What an agent struggles with

Two of the three reasons object databases lost are market reasons. The third, schema and code changing together, is real and sharper for agents, which change code often. Mo's typed live upgrades already face it ([04](../../research/04-models-that-lost-or-stayed-niche.md), inference).

## Worth borrowing

- **Rc-style semantic conflict classes.** Counters and bags declare how concurrent changes combine, a mechanism for merging by intent. Cost: merge semantics written and proved per type ([04](../../research/04-models-that-lost-or-stayed-niche.md)). See [Merging by meaning, not by cell](../ideas/merging-by-meaning.md) and [Data types that merge themselves](../ideas/data-types-that-merge-themselves.md).

## Disagreements

- **Whether anything merges by intent.** [00](../../research/00-landscape-overview.md) says nobody merges by intent (its own inference). [04](../../research/04-models-that-lost-or-stayed-niche.md) presents GemStone's reduced-conflict classes as a mechanism for merging by intent. [06](../../research/06-divergent-copies-and-merging.md) describes Bayou's per-write checks and merge procedures as defining conflicts by meaning. All agree that mainstream branch merges (Dolt) are cell-level.
- Current owner and status were not checked ([04](../../research/04-models-that-lost-or-stayed-niche.md), not confirmed). The 1980s founding date in [07](../../research/07-code-inside-the-database.md) is from memory.

## Sources

- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- [07-code-inside-the-database.md](../../research/07-code-inside-the-database.md)
- [00-landscape-overview.md](../../research/00-landscape-overview.md)
- https://people.csail.mit.edu/tdanford/6830papers/stonebraker-what-goes-around.pdf
- https://downloads.gemtalksystems.com/docs/GemStone64/3.6.x/GS64-ProgGuide-3.6.pdf
- https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/9-Transactions.htm
- https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/11-ClassHistory.htm
- https://book.seaside.st/book/advanced/persistency/image-based-persistency
- https://arxiv.org/pdf/2110.08993
