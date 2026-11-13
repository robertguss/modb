# Data types that merge themselves, and the rules they can keep

Data types whose merge is defined in advance, so that copies changed concurrently can always be combined without asking anyone. The catch is that such a merge can never reject a write, so some rules cannot be kept this way ([research 06](../../research/06-divergent-copies-and-merging.md)).

## What it is

A *CRDT* (conflict-free replicated data type) is a structure whose merge is defined so that copies which have seen the same edits are identical, in any order. Yjs updates are "commutative, associative, and idempotent" ([Yjs](https://docs.yjs.dev/api/document-updates); [research 06](../../research/06-divergent-copies-and-merging.md)). CRDTs merge concurrent changes without a server ([Automerge](https://automerge.org/); [research 00](../../research/00-landscape-overview.md)).

An older form of the same idea is [GemStone](../systems/gemstone.md)'s *reduced-conflict* (Rc) classes, such as counters and bags. They replay their changes at commit, so two sessions adding to the same bag do not conflict ([GemStone guide 3.6](https://downloads.gemtalksystems.com/docs/GemStone64/3.6.x/GS64-ProgGuide-3.6.pdf); [research 04](../../research/04-models-that-lost-or-stayed-niche.md)). GemStone uses them where collisions are likely ([GemStone Transactions](https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/9-Transactions.htm); [research 07](../../research/07-code-inside-the-database.md)).

## The problem it solves

Concurrent edits with no conflicts to resolve and no server needed: collaborative and offline-first apps where every device edits at once ([research 06](../../research/06-divergent-copies-and-merging.md)).

**Which rules a merge can keep by itself.** *Invariant confluence* (I-confluence) draws the exact line. Operations are I-confluent for a rule (an *invariant*) if any two valid states grown from a common ancestor always merge into a valid state; only then can the rule be kept without coordination ([Bailis et al., VLDB](https://www.vldb.org/pvldb/vol8/p185-bailis.pdf)). The paper's Table 2, as given in [research 06](../../research/06-divergent-copies-and-merging.md):

| Rule | Operation | Merge alone keeps it? |
|---|---|---|
| Uniqueness | insert with a chosen value | No |
| Uniqueness | insert with any fresh value | Yes |
| Auto-increment id | insert | No |
| Foreign key | insert | Yes |
| Foreign key | delete | No (cascading delete: yes) |
| Secondary index, materialised view | update | Yes |
| Counter > k | increment / decrement | Yes / No |

Data whose rules are merge-safe includes growing sets, unbounded counters and append-only logs ([research 06](../../research/06-divergent-copies-and-merging.md)).

## What it costs

- **The merge can never reject a write.** So rules that need rejection, such as uniqueness or "never below zero", cannot be kept ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **Same-field clashes get an arbitrary winner.** [Automerge](../systems/automerge.md) says the one case it "cannot handle automatically, because there is no well-defined resolution" is two writers setting the same property; it picks a winner that is the same everywhere and exposes the losers through `getConflicts` ([Automerge conflicts](https://automerge.org/docs/reference/documents/conflicts/)).
- **Converging is not the same as being useful.** Several published text CRDTs interleave two people's concurrent insertions character by character, "resulting in an unreadable jumble of letters"; the authors' errata says their own fix did not converge ([Kleppmann, 2019](https://martin.kleppmann.com/2019/03/25/papoc-interleaving-anomalies.html)).
- **The type system must know which data is which** ([research 06](../../research/06-divergent-copies-and-merging.md)). For GemStone's Rc classes, the merge semantics must be written and proved per type ([research 04](../../research/04-models-that-lost-or-stayed-niche.md)).
- **It cannot see meaning across changes.** CRDTs merge without coordination, so they cannot tell that two agents' changes are each fine alone but wrong together (inference, [research 09](../../research/09-agents-and-databases-today.md)).

## Systems that use it

- [Automerge](../systems/automerge.md): a CRDT library for documents.
- [Electric](../systems/electric.md): runs an agent as a Yjs peer that "merges everything without coordination" ([Electric, 2026-04-08](https://electric.ax/blog/2026/04/08/ai-agents-as-crdt-peers-with-yjs)).
- [GemStone](../systems/gemstone.md): reduced-conflict classes for counters and bags.
- Yjs: a CRDT library ([Yjs](https://docs.yjs.dev/api/document-updates)).
- Letta, an agent memory store, shows the opposite case: a full rewrite of a shared memory block is last-writer-wins with no merge, and appending is the only safe concurrent operation ([Letta](https://docs.letta.com/v1-sdk/memory/shared-memory/index.md); [research 09](../../research/09-agents-and-databases-today.md)).

## Cannot be combined with

Rules that need a write to be rejected, such as uniqueness of a chosen value, auto-increment ids, or a counter that must stay above a limit when decremented. Those need coordination: one side must see the other, or something must decide afterwards ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Disagreements

- **Agents as CRDT peers for conflicting writes.** Research 09's table lists Electric's agent-as-Yjs-peer as a best existing mechanism for conflicting writes ([research 09](../../research/09-agents-and-databases-today.md)). Research 06 says the same approach suits text but cannot stop two agents claiming the last item, because a CRDT merge can never reject a write ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **Whether anything merges by intent.** Research 00 says nobody merges by intent, for example "both branches added stock" (inference, [research 00](../../research/00-landscape-overview.md)). Research 04 presents GemStone's reduced-conflict classes as a mechanism for exactly that kind of merging ([research 04](../../research/04-models-that-lost-or-stayed-niche.md)), and research 06 describes Bayou defining conflicts by meaning ([research 06](../../research/06-divergent-copies-and-merging.md)). See [merging by meaning](merging-by-meaning.md).

## Sources

- [research 06: Divergent copies and merging](../../research/06-divergent-copies-and-merging.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 04: Models that lost or stayed niche](../../research/04-models-that-lost-or-stayed-niche.md)
- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- [research 09: Agents and databases today](../../research/09-agents-and-databases-today.md)
- I-confluence (Bailis et al.): https://www.vldb.org/pvldb/vol8/p185-bailis.pdf
- Yjs document updates: https://docs.yjs.dev/api/document-updates
- Automerge conflicts: https://automerge.org/docs/reference/documents/conflicts/
- Interleaving anomalies: https://martin.kleppmann.com/2019/03/25/papoc-interleaving-anomalies.html
- GemStone programming guide 3.6: https://downloads.gemtalksystems.com/docs/GemStone64/3.6.x/GS64-ProgGuide-3.6.pdf
- Electric agents as CRDT peers: https://electric.ax/blog/2026/04/08/ai-agents-as-crdt-peers-with-yjs
