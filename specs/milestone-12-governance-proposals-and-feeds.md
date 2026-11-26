# Milestone 12: Sensitivity/Taint Labels, Human-Reviewed Agent Proposals, and Reactive `txid`-Cursor Change Feeds

Builds directly on Milestone 11 (`v0.3.0`) while preserving 100% backwards compatibility with existing `.modb` databases, Layer 1-4 APIs, and downstream consumers (`motet`). Milestone 12 completes the remaining unbuilt Layer 4 pillars from `design.md` §6 (`Sensitivity` labels, non-widening clearance attenuation, and human-reviewed capability-diffed `Proposals`) together with Layer 1 CoW-pinned reactive `txid`-cursor `Feeds`.

---

## 1. Sensitivity / Taint Labels & Cross-Module Policy (`src/modb/policy.mo`)

### 1.1 Lattice & Clearances
- **`enum Sensitivity`:** `Public < Internal < Confidential < Secret` (ranks `0..3`), with total ordering (`permits?`, `max_sensitivity`, `min_sensitivity`, case-insensitive text parsing).
- **Grant Clearances (`_modb_clearances`):**
  - Persisted `ClearanceRecord(grant_id, max_sensitivity, granted_by, reason, updated_at)` in `_modb_clearances`.
  - **Strict Non-Widening Attenuation:** Setting clearance on a child grant requires `rank(requested) <= rank(parent_effective_clearance)`. Effective clearance walks the entire `Grants` ancestor chain and takes the minimum clearance along the chain (defaulting to `pol.default_clearance` when no ancestor overrides it, or `Secret` for admin calls without a grant). Downgrading or setting a cap on a parent grant immediately restricts every delegated descendant.

### 1.2 End-to-End Enforcement
1. **Sandboxed `ReadProgram`s (`execute_read_program_governed[_recorded|_locked]`):**
   - Validates view authorization and static `Views.validate_program` first, then enforces caller clearance BEFORE scanning any rows across all fields referenced in `where_clause`, `select`, `group_by`, `aggregates`, and `order_by` (eliminating hidden-field filter oracles).
   - Wildcard `select: None` automatically omits above-clearance view fields and reports them in `redacted_fields` (failing closed with `ClearanceDenied` if all fields are restricted).
2. **Approved k-Anonymous Declassification `Releases` (`execute_release_governed[_recorded|_locked]`):**
   - Enforces `ReleasePolicy(input_sensitivity, output_sensitivity, min_group_size)`.
   - Declassification (`output_sensitivity < input_sensitivity`) is permitted ONLY when `rdef.min_group_size >= rp.min_group_size` and `rdef.min_group_size >= 2` (blocking singleton declassification).
   - Caller clearance only needs to cover `output_sensitivity` after k-anonymous declassification passes; otherwise falls back to checking max sensitivity of `source_buckets`.
3. **FTS, Vector & Hybrid Search (`search_fts_governed`, `search_vec_governed`, `hybrid_search_governed`):**
   - Supplies a fail-closed `scope_filter_for_clearance(pol, clearance)` predicate to `Fts.search_filtered`, `Vec.search_filtered`, and `Vec.hybrid_search_filtered`, hiding `Confidential`/`Secret` scopes before top-K scoring.
4. **Governed Portable Export (`export_governed[_locked]`):**
   - `StrictFailClosed`: refuses export (`ExportBlocked`) if any included bucket exceeds caller clearance.
   - `RedactRestricted`: exports via `Export.export_filtered_store`, omitting restricted buckets before reading their B+Tree pages while producing a valid, SHA-256 verified `PortableSnapshot` compatible with `Export.verify_snapshot` and `Export.import_db`.

---

## 2. Human-Reviewed Agent Proposals & Capability Diffs (`src/modb/proposals.mo`)

### 2.1 Storage & Proposal Kinds
- Reserved internal buckets:
  - `_modb_gov_proposals` and `_modb_gov_proposals_by_status` (separate from `Modb.Replay`'s `_modb_replay_proposals`)
  - `_modb_dynamic_views`
  - `_modb_dynamic_releases`
  - `_modb_dynamic_invariants`
- Supported declarative `ProposalKind`s (agents propose structured data declarations, never arbitrary unverified code):
  - `ProposeView(DynamicViewSpec)`: narrows an existing base view to an explicit subset of fields with sensitivity labels `>= base_view` field sensitivity.
  - `ProposeReleasePolicy(DynamicReleaseSpec)`: registers/updates a k-anonymous release declassification policy (`min_group_size >= 2` required for declassification).
  - `ProposeClearance(grant_id, target_clearance, justification)`: requests clearance adjustment for a Grant (respecting parent Grant ceilings).
  - `ProposeInvariant(DynamicInvariantSpec)`: registers a declarative commit-time invariant (`FieldNonEmpty`, `IntRange`, `AllowedValues`) on a non-internal bucket.

### 2.2 Machine-Checked Capability Diff & Atomic Lifecycle
- Every `submit_proposal` computes a deterministic `CapabilityDiff`:
  - `widens_access`, `narrows_only`, `declassifies`, `risk_level` (`"low" | "medium" | "high"`), `affected_targets`, `newly_exposed_fields`, `max_sensitivity_before`, `max_sensitivity_after`, `existing_violations`, and a human-readable `summary`.
- Human-only review (`is_admin == true` required for `approve_proposal` and `reject_proposal`):
  - `approve_proposal` re-computes and re-verifies the `CapabilityDiff` against current state (blocking `ProposeInvariant` if `existing_violations > 0`), atomically persists the approved dynamic view / release policy / clearance / invariant alongside status `Approved` inside one `Ledger.write`, and records an audit entry in `_modb_audit`.
- Live materialization helpers:
  - `materialize_catalog(store, base_cat)` wraps approved `DynamicViewSpec`s into executable narrowed `Views.ViewDef`s.
  - `materialize_policy(store, base_pol)` merges approved dynamic view field sensitivities and release policies.
  - `apply_dynamic_invariants(store, base_schema)` attaches approved `DynamicInvariantSpec`s as $O(\text{touched})$ incremental `Ledger.invariant`s.

---

## 3. Reactive `txid`-Cursor Change Feeds (`src/modb/feeds.mo`)

### 3.1 Architecture (CoW Root Pins + $O(\text{diff})$ Structural Streaming)
- Each subscription `FeedSubscription` stored in `_modb_feeds` holds a dedicated Layer 1 persistent CoW root pin `pin_id = "feed:<id>"` protecting its acknowledged base root across commits and restarts.
- **`subscribe`:** Validates active Grant (if attached), atomically persists subscription + pins base root (with `from_beginning: false` for tailing from current `txid`, or `true` to bootstrap from root `0`).
- **`poll_feed` (pure read-only):**
  - Verifies active Grant (revoked/expired grants fail closed) and computes effective clearance.
  - **O(1) Idle Fast Path:** If bootstrapped and `pin.catalog_root == current_root`, returns an empty `FeedBatch` (`pages_read == 0`, `subtrees_skipped == 0`).
  - Uses `Modb.changed_buckets_between_roots` to identify only modified buckets, skips unwatched/restricted buckets (`_modb_pins` and `_modb_feeds` always excluded unless explicitly requested; sensitivity-restricted buckets recorded in `filtered_buckets` without reading a single page), and runs `Modb.diff_bucket_roots_with_stats` for key-level `Added` / `Modified` / `Removed` events (honoring `limit` + `truncated`).
- **`ack_feed` & `consume_feed`:**
  - `ack_feed` enforces optimistic `txid` compare-and-swap (`up_to_txid == current_txid`, returning `CursorStale` on concurrent writes so updates are never silently skipped), unpins the old `"feed:<id>"` root, pins the new root in the same `WriteTx`, and graduates deferred freelist pages `<= current_txid` directly via `Modb.commit` (avoiding `_modb_audit` feedback loops).
  - `consume_feed` executes `poll_feed` and `ack_feed` atomically inside a single exclusive lock when non-truncated.
  - `resync_feed` cleanly recovers after `Export.compact_db` or snapshot restore (which drop layout-dependent `_modb_pins`).

---

## 4. Product Integration & Verification
- **`AgentWorkbench` & `WorkbenchUi`:** REST endpoints (`/policy`, `/policy/clearances`, `/proposals`, `/proposals/:id/{approve,reject,withdraw}`, `/feeds`, `/feeds/:id/{poll,ack,consume}`), 11 new MCP tools on `POST /mcp` (54 tools total), and a **Governance & Feeds** inspector tab in `examples/workbench-ui.mo`.
- **Standalone CLI (`src/modb/cli.mo`):** `modb policy`, `modb proposals`, `modb feeds`, plus enriched `modb inspect` counts.
- **Verification:** `src/modb/{policy,proposals,feeds,cli}.mo`, `tests/test-governance-feeds.mo`, all existing Layer 1-4 unit/integration suites, `examples/agent-workbench.mo`, `tests/test_workbench_mcp_and_ui.py`, `tests/test_shop_api_live.py`, and downstream `/home/exedev/Projects/motet` tests (`store.mo`, `server.mo`) pass with 0 failures.
