# Divergent copies and merging

Type: research
Status: resolved

## Question

Using the map's research template, what do systems that let copies of data diverge and then merge do well and badly, and what pays for each strength?

Cover replication conflicts from Lotus Notes, Bayou and CouchDB; version-controlled data (Dolt, lakeFS, Neon and Xata branching, and the research systems Chronos and BranchBench); automatically merging data types (Automerge, Yjs); and sync engines (Electric, Zero, PowerSync).

Go deepest on what a merge can and cannot decide by itself, on merges that are correct row by row but wrong in meaning, and on what the Berkeley paper's "multi-world isolation" would require. `research/09-agents-and-databases-today.md` has the starting sources.

## Answer

Findings: [research/06-divergent-copies-and-merging.md](../research/06-divergent-copies-and-merging.md)

- A merge of states can keep a rule by itself only when the rule is invariant-confluent (Bailis et al.): foreign-key inserts and fresh ids yes; uniqueness of a chosen value, auto-increment, deletes under foreign keys and "never below k" no.
- Every system answers the rest one of four ways: pick a winner silently (Notes, CouchDB, Automerge, lakeFS flags, PowerSync), stop and ask (Dolt, lakeFS), re-run the operation with its guard against one authority (Bayou, Zero), or never merge (Neon, Xata).
- Row-correct but meaning-wrong merges come from the merge seeing what was written, not what was read or assumed; Bayou's dependency check is the only mechanism found that records the assumption.
- Multi-world isolation would need shared storage without slow deep-branch reads (BranchBench: nobody has it), cheap abort, a sibling rule (first-commit-wins is the simplest working one), atomic cross-store merge (Chronos) and a final order. No system ships all five.
- Dolt reports conflicts are rare because users design them away, and that agents do not yet resolve them (vendor statement).
