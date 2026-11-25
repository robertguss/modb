# Milestone 8 Spec: Grant-Scoped Views, Approved Releases, Zero-Approval Read Programs, Agent Self-Onboarding & CoW-Diff Incremental World Re-Validation

Implements the remaining core pillars of `design.md` §6 ("The layer for outside callers: agents") in pure Mo on top of MoDB Layers 1–4:

1. **CoW-Diff Incremental World Read Re-Validation (`src/modb/world.mo`, `src/modb.mo`)**
   - `design.md` §6: *"Asking again costs what changed. The store lists the rows that differ between the version a question was asked on and the main line. A question whose answer those rows cannot have changed needs no second reading. A world opened on the version that is still the main line has nothing to ask again."*
   - Adds `Modb.changed_buckets_between_roots(store, root_a, root_b)` (O(catalog diff)) and `Modb.tx_bucket_dirty?(tx, bucket)`.
   - Adds `World.with_scoped_query(cat, name, read_buckets, run)` alongside backward-compatible `World.with_query`.
   - Sound skip rule during `land_world`: skips re-executing a `ReadStep` iff either (a) zero non-world-bookkeeping buckets changed between `base_pin.catalog_root` and `live.catalog_root`, or (b) `qdef.read_buckets` is non-empty, disjoint from external changed buckets, and (if any `CallStep` ran earlier in this World) disjoint from `cur_tx`'s dirty buckets.
   - Exposes `reads_skipped` on `World.LandResult` and `total_reads_verified` / `total_reads_skipped` on `World.LandingMetrics`, preserving 100% `Replay.tla` / `Worlds.tla` parity.

2. **Grant-Scoped View & Release Attenuation (`src/modb/grants.mo`)**
   - `design.md` §6: *"Helpers get less, never more... a view on top of its view, fewer functions, a limit on calls and an end time."*
   - Persists `allowed_views: Option(List(Text))` and `allowed_releases: Option(List(Text))` on `Grants.Grant`.
   - Enforces non-widening delegation (`tx_delegate_scoped`) with hierarchical view-narrowing support (`view_narrows`: e.g., `tasks_public` narrows `tasks_finance`, so a parent with `tasks_finance` can delegate `tasks_public`, while a child with `tasks_public` is rejected with `WideningDenied` if it tries to claim `tasks_finance`).
   - Enforces active ancestor-chain verification (`verify_view`, `verify_release`) so cascading revocation immediately blocks Views, Releases, and Read Programs.

3. **Zero-Approval Sandboxed Ad-Hoc Read Programs, k-Anonymous Releases & Read Provenance (`src/modb/views.mo`)**
   - `ViewDef`: projects raw MoDB tables into narrowed typed field maps (`fields: List(ViewField)`, optional `narrows: Option(Text)`).
   - `ReleaseDef`: human-approved statistical / aggregate functions with mandatory `min_group_size` (k-anonymity threshold guard refusing small cohorts with `ReleaseThresholdBlocked`).
   - `ReadProgram`: declarative read-only query AST (`view`, composable `Pred` boolean/comparison/string/membership `where_clause`, `select`, `group_by`, `aggregates` (`count`/`sum`/`min`/`max`/`avg`), `order_by`, `limit`):
     1. **Authorize** via Grant (`verify_view`) or Admin role.
     2. **Static Check** every referenced field & numeric aggregate type against `view.fields` *before scanning a single row* (`FieldNotInView` / `InvalidAggregateType`).
     3. **Bounded Sandboxed Execution** on the committed read-only `Store` snapshot under `ReadLimits(max_rows_scanned, max_ops, max_result_rows)` (`WorkBudgetExceeded`).
     4. **Provenance Log** (`_modb_read_log`): records `(seq, txid, principal, grant_id, kind, target, program, rows_scanned, result_count, answer_hash, at)`.

4. **Stateless Agent Self-Onboarding (`Modb.Views.describe_for_caller` — `design.md` §6 `Need 6`)**
   - Returns a structured `OnboardingManifest` tailored to the caller's exact role & optional Grant: database status, caller/grant chain & remaining budget, permitted write actions, permitted Views (showing *only* visible fields — never leaking hidden columns), permitted Releases, active Claims (to avoid stepping on peers), open Worlds, commit-time invariant descriptions, and `ReadLimits`.

5. **Workbench Integration, 35-Tool MCP Server & Live Inspector UI (`examples/agent-workbench.mo`, `examples/workbench-ui.mo`, `tests/test-views-incremental.mo`, `tests/test_workbench_mcp_and_ui.py`)**
   - Adds 4 hierarchical Views (`projects_public` -> `projects_finance`, `tasks_public` -> `tasks_finance`), 2 k-anonymous Releases (`project_budget_summary`, `task_cost_by_status`), scoped World queries for O(diff) skipping, HTTP routes (`GET /describe`, `POST /views/query`, `POST /releases/:name`, `GET /reads`), 4 new MCP tools (`modb_describe`, `modb_read_program`, `modb_release`, `modb_read_log` — **35 tools total**), and a **Views, Reads & Onboarding** tab in `WorkbenchUi`.
