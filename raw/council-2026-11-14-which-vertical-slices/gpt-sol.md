I recommend four slices, each extending the same small job. These are proposed experiments, not database implementation. Before each run, freeze predictions, expected answers, workload bounds and a control that must fail. A failed result should narrow the candidate or trigger one targeted follow-up before proceeding.

1. Ask, decide, land.

An agent asks an unplanned question through a restricted view, then proposes approved calls in its world. Use a small, representative extract of the owner’s data, expressed as ordinary Mo records and collections.

Guard: read programs only compute; every answer is recorded; landing replays questions in their original positions, checks the rule after each call, and publishes the whole world atomically. Keep data in the existing numbered-node collection.

Experiment: test point reads, absence, aggregates, an intervening own write, and a concurrent change that alters underlying data while preserving the answer. Include a small agent exercise with answers written independently beforehand.

Required result: does this job work with correct answers and landings without widening the view or adding an operation for every question? Removing answer validation must admit a deliberately stale decision.

Mo today: use separately compiled read functions over exported snapshots; [the reference, §13.4](mo/docs/reference/README.md) documents offline queries. Live submission remains modelled: [design-ideas.md, “The request is a program”](modb/design-ideas.md) identifies accepting programs while running as missing. The existing [worlds.mo, ask and land](modb/sketches/kept-versions/worlds.mo) records only keyed integer answers.

2. Authority changes while an agent thinks.

An agent delegates a narrower task; a person withdraws its grant or replaces an approved function before landing.

Guard: explicitly model which current authority must authorize each replayed call and release. Keep grant ancestry, approval identities, program versions and world roots as data beside the proposed changes.

Required result: can revocation prevent every subsequent unauthorized landing and release while unrelated authorized work still succeeds? The control checks authority only when the world opens and must wrongly accept withdrawn work.

Mo today: model the protocol; do not claim caller separation from a simulated caller identifier. [Design-ideas.md, “Many agents working together”](modb/design-ideas.md) names caller identity and derived grants as needs. [The reference, §11.5](mo/docs/reference/README.md) prohibits capabilities and functions in service state, inputs and results, so store identifiers rather than executable grants.

3. Lose the reply, recover the accountable change.

An agent lands, loses its connection, retries, and later asks what happened—even after an approved function changes.

Guard: one durable outcome binds request identity, caller, approval, questions, calls and relevant code version. Model an append record plus published root, with failures between every persistence step.

Required result: does recovery produce a complete accountable landing or none, with retries unable to repeat its effect? Include historical replay under the original definition. Publishing success before durability must fail the control.

Mo today: ordinary service recovery is a baseline, not this experiment’s proof. [The reference, §12.5](mo/docs/reference/README.md) says generated crashes occur between steps, never inside commits. [Saved-state.md, “Ownership and transactions”](mo/docs/design/saved-state.md) documents uncertain commit outcomes, absent request deduplication, unlogged successful reads and snapshot deletion of covered recovery logs. Model these stronger requirements without changing Mo.

4. Keep working, then forget abandoned worlds.

Run the same job repeatedly with fast and slow agents, abandoned worlds, retained history and increasing data sizes.

Guard: reclaim only unreachable versions; preserve every retained answer and approved landing. Compare today’s numbered-node representation with a model of fetching immutable nodes by identifier.

Required result: does a declared retention policy keep space and work within the chosen workload budget, including retries and slow-agent completion? Disabling reclamation must breach the budget; reclaiming a pinned version must corrupt a checked answer.

Mo today: [issue 37, “Not shown”](modb/issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md) leaves reclamation and service-hosted worlds untested. Measure against MO_LIMIT_SERVICE_WORK, MO_LIMIT_SERVICE_MESSAGE_MEMORY and MO_LIMIT_SAVED_NODES in [limits.h](mo/src/base/limits.h). Paging needs modelling because service handlers cannot receive storage capabilities (§11.5); whole-state copying remains in [service.c, encoded_copy](mo/src/vm/service.c).

Run slice 1 first. It tests the distinctive agent experience and whether useful questions produce a tractable replay record. Cheap roots alone cannot answer that.

Stop when the evidence supports all five fields in [map.md, “Destination”](modb/map.md): database kind and novelty, borrowed ideas and costs, first real-data job, general Mo capabilities required, and relationship to Phases 6–8. Failures count if the decision explicitly excludes the failed promise. Continue only for an uncertainty that could reverse that decision.

I deliberately omit distribution, optimizers, framework packaging and general information-flow proofs. None is necessary to decide this bounded candidate. Retention experiments must not become claims of complete personal-data erasure.

The largest risk is separately successful slices hiding incompatible assumptions. Reuse one recorded scenario across all four, including authority changes, recovery and retention.

Confidence in slice 1 first: 80%. I would move recovery first if losing an answer makes the selected real-data job unacceptable even experimentally.

I read the specified snapshot and inspected Mo sources; I ran no experiments, independently reproduced no timings, and changed no files.
