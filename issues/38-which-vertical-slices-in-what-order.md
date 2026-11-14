# Which vertical slices, in what order, and what must each show?

Type: grilling
Status: open

## Question

HITL. Robert chose vertical slices on 2026-11-14 ([Which half comes first?](36-which-half-comes-first.md)). A vertical slice is one small job carried the whole way down: something an agent does, the rule that guards it, and the way its data is kept.

Which slices are run, and in what order? What must each show before the next? When are there enough of them to write the decision this map is for?

## Comments

**Claude's proposal, 2026-11-14.** Not decided by Robert.

| # | Slice | What an agent does | How the data is kept | What it must show | From Mo |
| --- | --- | --- | --- | --- | --- |
| 1 | A world over the wire | Opens a world on a running service, asks, acts and lands, while a second agent does the same | The tree by number, in a service's saved state | The worlds of the sketch survive being a real service that restarts; what the list of tools looks like to an agent; what an ask, an act and a landing each cost at 1,000 and 50,000 rows | Nothing |
| 2 | A rule and a view over many rows | Lands a transfer among many accounts, and reads only its own rows | Totals kept in the tree's branches, so a check reads one path and not every row | The rule check and the narrowed read cost the same at 1,000 and 50,000 rows | Nothing |
| 3 | A read program | Writes a small Mo function that answers its question, in place of a query, and runs it on a kept version | An exported state at first, run with `mo query` | Whether an agent with only Mo's guide writes a correct read program at the first try; what one costs; what Mo lacks to run one on a live service | Measured, not built |
| 4 | A write that costs what it changes | Changes one row | Only the changed nodes are written; the tree by number knows which they are | How much is written and how long it takes against saving everything; exactly what Mo's service would have to change | A change to Mo to build it; here it is measured and modelled |
| 5 | A proposal a person approves | Proposes a new kind of call; a person reads what becomes possible and approves it | The state carried across an upgrade of the service | The accountable write holds when the set of approved calls changes | Nothing known |

- **Each slice is one prototype ticket,** with its predictions written first and a control that must fail, as [Can a Mo library keep old versions cheaply today?](37-can-a-mo-library-keep-old-versions-cheaply-today.md) was.
- **Recommended first: slice 1.** Every other slice hangs on what an agent sees and does, and it needs nothing from Mo. Slice 2 comes next because slice 1 is only honest at size once a rule does not read every row.
- **Slice 4 is the storage half's real question.** The sketch showed that versions are not: every write costs in proportion to all of the state. Building slice 4 for real means changing Mo, which this map rules out, so here it can only be measured and modelled.
- **A stop rule.** Slices are experiments and the map's destination is a decision. Claude's worry is a string of sketches that never ends in one. After these five, or sooner if two in a row change nothing, the decision is written.
