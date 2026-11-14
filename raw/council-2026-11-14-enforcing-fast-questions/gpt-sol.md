1. Choice

For application code: A, applied to every traversal of a stored table, including through helpers. An unrecognised operation requires an explicit walk acknowledgement. Local collections remain ordinary Mo. Diagnostics must explain the missed shape and show a supported rewrite.

For runtime read programs: mandatory C at the entry point, checked through everything it calls. The host requires the demand; the caller cannot omit it. A walk requires separate approval with a work ceiling. Read-only code can still consume excessive resources.

Define the guarantee narrowly: no unacknowledged full-table traversal. An indexed read returning K rows necessarily spends work on K rows; it is not constant-cost. Recognition must also require an existing, current index. Otherwise refuse admission and explain what is missing.

Use measurements as supporting evidence. B permits unnoticed regressions. Optional C leaves uncovered functions. F detects changes between versions, but cannot establish that the original was acceptable. E is the strongest fallback if recognition proves brittle.

2. Strongest argument against

A can turn ordinary Mo into a hidden query language: equivalent expressions receive different treatment, helpers break recognition, and agents learn to silence errors with walk. Worse, recognising a filter does not bound the work surrounding it. Nested indexed lookups can still be expensive.

This choice depends on conservative checks, useful diagnostics and evidence that agents repair rejected code without changing its meaning.

3. Experiments, in order

Each experiment must record its prediction and acceptance criterion before running.

Experiment 1: Can a small recogniser preserve semantics?

Build an external recogniser for field equality, reversed equality, captured constants and simple helpers. Compare hand-lowered indexed versions against ordinary Mo List.filter using generated lists and prebuilt Map buckets. Include duplicates, order, empty inputs, row-dependent comparisons and predicates that stop. In particular, hoisting a row-independent expression must not introduce a stop on an empty collection.

Required result: every accepted rewrite preserves the ordered answer and stopping behaviour; every unsafe case is rejected.

Prediction: a restricted recogniser passes, but unrestricted hoisting fails, 85%.

Failing control: deliberately hoist a stopping expression before an empty filter.

Missing Mo: none for the experiment. Real implementation needs typed recognition, helper summaries and index lowering; List.filter and List.group_by currently execute ordinary loops.

Experiment 2: Does strict enforcement teach the shapes?

Run fresh agent sessions on matched read-writing and refactoring tasks under A, B, optional C and an E-style library API. All produce executable Mo over mock collections; an external checker supplies the proposed diagnostics. Include held-out tasks and legitimate scans explicitly identified in the task.

Required result: under A, at least 90% of tasks become semantically correct, supported reads within two repair attempts, with no unjustified walk acknowledgements.

Prediction: A meets this threshold, 65%. Existing Mo learnability measurements justify trying compiler feedback, but do not establish query-shape learnability.

Failing control: replace one correct diagnostic suggestion with a rewrite that changes the answer; hidden semantic tests must reject it.

Missing Mo: none. Markers and table rules are simulated outside Mo.

Experiment 3: Can D distinguish unwanted work?

Use exported mock service states and binary-search mo query --max-work, as the existing sketches do. Measure several sizes, zero/one/many matches, early and late matches, skew, and a branch activated only beyond the initial sizes. Compare scans, prebuilt bucket lookups and expensive native collection operations. Exclude fixture construction from query counts.

Required result: the proposed detector rejects scans while accepting indexed reads whose growth comes from results.

Prediction: literal D fails, 95%.

Failing control: replace an indexed lookup with a full filter; the revised detector must reject it.

Missing Mo: none for instruction counts. Physical storage work cannot be measured without a store. mo_vm_execute counts instructions; work inside native primitives is not a separate instruction per unit of work. Determinism does not make that count a complete cost model.

Experiment 4: Does recognition survive missing views?

Build a script modelling absent, building, ready and invalid indexes. Submit recognised predicates before creation, after eviction and after a schema change.

Required result: admission never silently builds or scans when the required view is unavailable.

Prediction: recognition alone violates this requirement; readiness-aware admission passes, 95%.

Failing control: label an absent view ready; the model must expose an accepted read with no executable fast route.

Missing Mo: none for the model. Real enforcement needs index lifecycle metadata and a runtime admission rule.

4. First experiment and reversal condition

Run experiment 1 first: enforcing an unsound rewrite makes wrong answers mandatory. If ordinary helper-based expressions cannot be recognised conservatively without frequent rejection, prefer E-style ordinary Mo methods. Experiment 2 determines whether that fallback is necessary in practice.

5. Missing option or likely fatal flaw

Add an access-plan explanation: identify every table access, required index, readiness and acknowledged scan.

The largest gap is confusing "recognisable" with "available cheaply." A novel recognised predicate may require an O(N) index build. Plain Mo solves expression syntax; it does not settle view creation, maintenance, eviction or result-size costs.

6. Confidence

Application choice: 75%. Runtime choice: 80%.
