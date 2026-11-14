1. SLATE (FOUR SLICES, IN ORDER)

Slice 1: Cold-agent read programs, narrowed views, and answer-checked landing.
Agent: Cold agents (given types, signatures, and examples) write pure Mo read functions over a narrowed View on issues/12-what-real-data-goes-in-first.md ("Candidate datasets") data, concurrently asking, calling writes, and landing (design-ideas.md, "1. The request is a program").
Guard/control: mo_check_query_entry (src/check/services.c) rejects effects/hidden fields; land replays reads in place (issues/35-what-lands-together-when-a-world-holds-more-than-one-call.md, "Answer") and checks rules per call. Control: expose hidden fields or skip replay; bad reads compile or races land.
Kept: sketches/kept-versions/tree.mo (put, keep, open) plus in-state log, queried via mo fetch (src/tools/fetch.c) and query (src/tools/offline.c).
Result: Cold agents pass a pre-set validity bar without SQL AND coarse-read send-backs (design-ideas.md, "Which reads count as relied on") stay below ceiling, OR one fails.
Mo blockers: Offline-only query (src/tools/offline.c); whole-service mo_live_start (src/tools/upgrade-live.c); mo_check_service_purity (src/check/services.c; docs/reference/README.md, "11.5 Purity") barring function values; struct-Map copy in borrow_walk (src/codegen/ownership.c; sketches/kept-versions/in-place.mo).

Slice 2: Delegated helper worlds, O(log N) checks, and selective undo on mo serve.
Agent: Over mo serve MCP, parents mint narrower grants (view, writes, call cap, Time expiry) for helpers, and an operator undoes one misled agent's calls by replay (design-ideas.md, "Many agents working together", "4. The log is the truth").
Guard/control: Helpers only narrow parent grants and die on revocation; rules read summaries instead of O(N) Tree.entries in sketches/kept-versions/worlds.mo (total); undo flags later calls with broken guards or changed answers. Control: omit narrowing or undo checks; escalation or drift lands.
Kept: service.sqlite (src/host/store.c) with tree.mo nodes, summaries, grants, and in-state call/read log.
Result: Delegation, O(log N) checks, and undo fit mo serve, OR hit MO_LIMIT_SERVICE_WORK (1,048,576), MO_LIMIT_MCP_RATE (20/s), 16/32 KiB MCP caps (src/base/limits.h), ~10 ms HTTP CPU (authenticate/plan, src/tools/protocol-request.c; issues/11-how-fast-and-large-is-a-mo-service.md, "Added later"), or 56 MiB call memory (mo_service_limits, src/vm/service.c).
Mo blockers: Single token (token_source, src/check/services.c; MO_LISTENER_AUTH, src/tools/protocol-request.c); no capabilities in state/messages (mo_check_service_purity); MO_STORE_SNAPSHOT (mo_store_call, src/host/store.c) deleting log; mo_service_step (src/vm/service.c) blocking reads behind writes.

Slice 3: Agent write/schema proposal, replay rehearsal, and human intent gate.
Agent: Blocked by a mid-world rule (issues/35-what-lands-together-when-a-world-holds-more-than-one-call.md, "Answer"), an agent proposes a composite write and migration, rehearses on Simulation and kept history, and submits an intent diff (design-ideas.md, "The ideas").
Guard/control: Must pass mo check --upgrade-from, mo test promises/recovery (src/tools/recovery.c), replay, and mo intent --against (src/tools/intent.c) gated on mo review (docs/agent-guide.md, "Review intent"). Control: push an unapproved or promise-weakening bundle; gate refuses.
Kept: service.sqlite via mo push --migrate (mo_live_admit, src/tools/upgrade-live.c) and program digests (src/host/store-programs.c).
Result: Phase 6 intent diffs and promises support human approval without duplicated rules, OR show test/runtime promise drift (sketches/land-whole/main.mo, rule? vs promise) and opaque diffs.
Mo blockers: Promises run only in mo test (src/tools/recovery.c), not mo_service_step (src/vm/service.c; docs/design/intent.md, "Service promises"); mo_live_admit ignores mo review (src/host/store-review.c); MO_LIMIT_UPGRADE_PREVIOUS=2 (src/base/limits.h); closed enum Call (sketches/README.md, "land-whole").

Slice 4: Path-only persistence, dead-world reclamation, and faulted-disk recovery versus service.sqlite.
Agent: Agents churn 90%-abandoned worlds and 10%-landed writes over 50k-500k records under sweeps and injected torn/lost writes (design-ideas.md, "Storage underneath"; issues/11-how-fast-and-large-is-a-mo-service.md, "Answer"; issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md, "Not shown").
Guard/control: Recovery restores the last synced root with valid checksums, zero leaked nodes, and intact pinned roots. Control: write root before path sync or sweep live worlds; recovery or reads fail.
Kept: mo run sketch plus fault-injecting page/log harness writing dirty path nodes, beside yardstick.py and sketches/kept-versions/by-number.mo.
Result: Path-only writes and reclamation hold latency/memory near yardstick.py's ~3 ms floor, backing a custom engine, OR reclamation/hop costs favor fixing encoded_copy (src/vm/service.c) over service.sqlite.
Mo blockers: Files (src/base/hostops.def) lacks write_bytes, pread/pwrite, atomic rename, fsync; Files.in_memory and Simulation (docs/reference/README.md, "12.5 Simulation") inject no torn writes; src/base/prims.def lacks byte hash; services bar capabilities and force encoded_copy (MO_LIMIT_SAVED_BYTES 16 MiB, MO_LIMIT_SAVED_NODES 1,048,576, src/base/limits.h).

2. FIRST SLICE AND WHY
Run Slice 1 first. sketches/kept-versions/worlds.mo (ask, land) proved versioned trees in memory (issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md, "Answer"), and TLA+ settled multi-call landing (issues/35-what-lands-together-when-a-world-holds-more-than-one-call.md, "Answer"). The sharpest untested bet is agent-facing: whether cold agents write pure Mo read functions over narrowed views without SQL, and whether answer-checked landing hits the 92-95% needless send-back rate in design-ideas.md ("What the first model and the research found"). (I listed mo/learnability/ folders without reading prompts; this snapshot has no DB query evals.) Failing either reshapes Slices 2-4.

3. STOP RULE
Stop once every map.md ("Destination", "Not yet specified") item has measured answers: query learnability and send-backs (Slice 1); multi-agent grants, O(log N) checks, and undo (Slice 2); human-gated proposals beside Phase 6 (Slice 3; issues/13-does-phase-6-finish-first.md, issues/18-how-does-it-sit-beside-phases-6-to-8.md); and saved-state versus custom storage plus general Mo additions passing issues/14-what-rule-keeps-the-database-from-bending-mo.md and issues/17-what-must-mo-gain.md (Slice 4)—stopping early if any core bet fails.

4. LEFT OUT AND WHY
Multi-machine replication (non-goal: design-ideas.md, "Open questions" #8); query optimizers/auto-indexes (premature before seeing agent read programs, unneeded at issues/12-what-real-data-goes-in-first.md scale); and re-testing HTTP parsing in src/tools/protocol-request.c (~10 ms CPU already isolated in issues/11-how-fast-and-large-is-a-mo-service.md, "Added later").

5. LARGEST SLICE RISK AND GUARD
Risk: toy-scale illusions where slices pass alone while hiding cross-slice breaks (O(N) rules in sketches/kept-versions/worlds.mo hitting MO_LIMIT_SERVICE_WORK at 1,000 inserts in issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md, duplicated rules in sketches/land-whole/main.mo, or snapshot log deletion in src/host/store.c breaking undo). Guard: carry one issues/12-what-real-data-goes-in-first.md schema across all slices, pre-write numeric thresholds and controls, and vet each Mo ask against issues/14-what-rule-keeps-the-database-from-bending-mo.md.

6. CONFIDENCE IN FIRST SLICE
82%. I would run Slice 4 first if the chosen issues/12-what-real-data-goes-in-first.md dataset ("Candidate datasets") immediately exceeds encoded_copy's ~125,000-row / 16 MiB MO_LIMIT_SAVED_BYTES ceiling (issues/11-how-fast-and-large-is-a-mo-service.md, "Answer"), or if uninspected learnability/ runs already prove cold-agent Mo query fluency.
