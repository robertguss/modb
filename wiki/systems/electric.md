# Electric

Electric is a sync engine that copies parts of a Postgres database, called "Shapes", into apps for fast local reads ([Electric docs](https://electric.ax/docs/sync/); [research 00](../../research/00-landscape-overview.md)). Writes do not go through Electric; they go through the app's own API.

## What it is for

Fast local reads of server data in apps, with writes that show at once and are confirmed later ([research 06](../../research/06-divergent-copies-and-merging.md)). Research 00 says sync systems drop the assumption that clients fetch data by request and response, and get local reads and offline use in return ([research 00](../../research/00-landscape-overview.md)).

## Core idea

The server is the authority; the client holds a guess. Electric syncs reads only. It sends writes through "your existing API" and warns that after a rejection "the original write context is much harder to reconstruct" ([Electric writes guide](https://electric.ax/docs/sync/guides/writes)).

For agents, Electric published a way to run an agent as a Yjs peer (Yjs is a library of [data types that merge themselves](../ideas/data-types-that-merge-themselves.md)). The agent "merges everything without coordination" ([Electric, 2026-04-08](https://electric.ax/blog/2026/04/08/ai-agents-as-crdt-peers-with-yjs)).

## Strengths and what pays for each

- **A simple write path: your own API.** Paid for by: you build the write handling yourself ([research 06](../../research/06-divergent-copies-and-merging.md)).
- **Local reads and offline use.** Paid for by: the client holds a guess that the server may later overrule ([research 00](../../research/00-landscape-overview.md); [research 06](../../research/06-divergent-copies-and-merging.md)).

## Weaknesses

- A rejected write surfaces late, away from the code that made it ([research 06](../../research/06-divergent-copies-and-merging.md)).
- After a rejection the context of the original write is lost ([Electric writes guide](https://electric.ax/docs/sync/guides/writes)).

## Overlapping work

Reads are synced; conflicting writes are settled by whatever the app's own API does. In the agent-as-Yjs-peer design, concurrent edits merge automatically ([research 06](../../research/06-divergent-copies-and-merging.md); [research 09](../../research/09-agents-and-databases-today.md)).

## What an agent struggles with

Running an agent as a Yjs peer suits text. It cannot stop two agents claiming the last item, because a CRDT merge can never reject a write ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Disagreements

- **Agents as CRDT peers for conflicting writes.** Research 09's table lists Electric's agent-as-Yjs-peer as the best existing mechanism for conflicting writes, next to Dolt's row merge ([research 09](../../research/09-agents-and-databases-today.md)). Research 06 says the same approach suits text but cannot stop two agents claiming the last item ([research 06](../../research/06-divergent-copies-and-merging.md)).

## Sources

- [research 06: Divergent copies and merging](../../research/06-divergent-copies-and-merging.md)
- [research 00: Landscape overview](../../research/00-landscape-overview.md)
- [research 09: Agents and databases today](../../research/09-agents-and-databases-today.md)
- Electric sync docs: https://electric.ax/docs/sync/
- Electric writes guide: https://electric.ax/docs/sync/guides/writes
- AI agents as CRDT peers with Yjs: https://electric.ax/blog/2026/04/08/ai-agents-as-crdt-peers-with-yjs
