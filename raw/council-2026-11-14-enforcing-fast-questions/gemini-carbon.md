1. Choice

Program's own code: A (Strict) and F (the review door). Any read on a stored Table without an index or view route is a compile error unless marked walk. Adding walk, or worsening a read's cost class (constant, log, key-fanout, walk), is a directional intent change held for human approval.

Why: B breaks Mo's no-warnings rule (docs/reference/README.md, Appendix A); exit-0 checks get ignored, while learnability/bench-v0-round-3/results.md showed agents fix errors carrying a Fix on the next attempt 97.4% of the time (37/38). C lets omitted fast markers scan silently. D is blinded by Mo's VM: C primitives in src/prim/collections.c run inside one MO_OP_PRIM in src/vm/execute.c uncounted. E drops plain Mo before testing it. F stops agents adding walk just to silence mo check, while upgrades removing walk pass freely.

Run-time agent read program: A (Strict with walk) plus work budget, without F. Unplanned questions have no human reviewer, so F cannot apply and walk must remain legal. Compiling under A catches accidental scans before touching state (without counting a service failure), suggests indexed shapes via Fix, and requires walk only when no fast route exists, marking scan cost and whole-table footprint.

2. Strongest argument against this choice

Strict recognition turns an optimisation into a brittle language boundary. Meaning-preserving edits — extracting a helper, binding a tuple, reordering boolean arms, or calling a pure function — cross an invisible cliff and fail compilation, forcing authors and agents to infer a hidden subset from errors rather than an explicit API like E. On run-time reads without F, agents may write walk on first try to skip a compile round-trip, recreating scans and inflating landing conflicts.

3. Experiments, in order

Experiment 1: Natural shape coverage (surface vs Mo Core).
Built/measured: Prompt Claude and GPT sessions (learnability/protocol.md) on 30 read tasks (equality, and/or, range, sort-take, join, group-sum) on a 4-table Shop in sketches/, unhinted. Run two Python recognisers on passing code: surface syntax vs mo check --emit=core (mo_core_print in src/core/core.h). Control: 10 obfuscated scans (recursive helpers, key math, field-to-field tests) must score 0/10 on both.
Result: Share of valid queries matched on surface syntax vs Mo Core.
Prediction (80%): Surface ~65%; Core <20% because loop in src/lower/expressions.c and filter in lib/list.mo lower to MO_CORE_MAP_OP_ENTRIES and CPS jumps.
Mo lacks: Map filter in MO_CORE_MAP_OPS (src/core/ops.def; lib/map.mo has only update), Core ops for filter/sort_by, and typed-AST output in src/tools/cli.c.

Experiment 2: Enforcement trial (A vs B vs C vs E).
Built/measured: Wrap mo check and the surface recogniser across the 30 tasks: (A) error + Fix, allowing walk on 6 unindexable tasks; (B) exit-0 warning; (C) opt-in fast prefix; (E) opaque Table module exposing lookup/range/walk. Control: A without walk on the 6 unindexable tasks must pass 0/6.
Result: Share of indexable tasks ending correct and fast-routed within 3 retries, plus A's walk-abuse rate.
Prediction (80%): A hits >=90% correct-and-fast with <=10% walk abuse; B and C stay ~65% fast; E hits >=95% fast on single keys but <60% correct on joins/compound filters.
Mo lacks: Warnings (docs/reference/README.md), walk/fast grammar (grammar/mo.y), and custom edits in mo fix (src/tools/fix.c).

Experiment 3: Instruction-scaling audit of D.
Built/measured: Sketch in sketches/ with Tree (sketches/kept-versions/tree.mo) and Map at N=100 and N=2,000 across 20 reads: 8 indexed/log-depth reads (including multi-row orders_of), 6 Mo-loop scans, and 6 C-primitive scans (values, sum, contains?, intersection), counted via mo query --max-work (asked-again.py). Control: all 6 Mo-loop scans must grow >=15x in instructions.
Result: False-negative rate on C-primitive scans and false-positive rate on log-depth/multi-row reads.
Prediction (95%): 6/6 C-primitive scans show zero instruction growth despite ~20x slower runtime; >=50% of tree/multi-row reads grow.
Mo lacks: Per-element charging under MO_OP_PRIM (src/vm/execute.c) in mo_prim_collection (src/prim/collections.c); extra parameters in query_inputs (src/check/services.c); sizes past MO_LIMIT_INPUT_ELEMENTS in mo_input_build (src/tools/inputs-build.c); instruction checks via mo_process_instructions_remaining (src/vm/process.c).

Experiment 4: Order equivalence and landing send-backs.
Built/measured: Add a secondary index to sketches/kept-versions/worlds.mo across 500 two-agent histories, measuring == mismatches between walks and index rewrites after mutations, and false land send-backs under key vs walk footprints. Control: skip read re-checks in land; conflicting worlds must falsely land.
Result: Rate of == mismatches and drop in false send-backs under key footprints.
Prediction (85%): Range/OR rewrites fail == in >=30% of histories; key footprints cut false send-backs >=80%.
Mo lacks: Budgets above MO_LIMIT_SERVICE_WORK without supervisor stops (src/vm/service.c), and ordered cost classes in difference and digest_order (src/tools/protocol-door.c).

4. First experiment and decision flip

Experiment 1: it needs zero Mo changes, reuses learnability and mo check --emit=core, and tests natural shape coverage and survival. Switch to E + A + F (closed Table combinators plus walk) if surface recognition is <40%, or if Experiment 2 shows >25% walk abuse or <75% completion under A. If --emit=core matches >=70%, run the pass on Mo Core instead of typed AST.

5. Flaw most likely to sink "plain Mo is the query language"

Mo's collections clash with query planning. Lowering erases query algebra before Core (loop in src/lower/expressions.c and lib/list.mo turn filters and Map loops into MO_CORE_MAP_OP_ENTRIES plus CPS jumps), while Mo mandates insertion/list order (docs/reference/README.md) and eager evaluation (sort_by in lib/list.mo sorts all rows before take). Exact == equivalence breaks when range, OR or join plans return key order instead of insertion order, and eager evaluation blocks index top-K without pipeline fusion. Table must drop insertion order and stay unlowered through planning.

6. Confidence

68%.
