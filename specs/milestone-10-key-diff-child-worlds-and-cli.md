# Milestone 10 (`v0.2.0`): Key-Level `O(diff)` World Validation, Fairness Tickets, Nested Child Worlds & Standalone `modb` CLI

Builds directly on Milestone 9 (`v0.1.0`) while maintaining 100% disk and API backwards compatibility (existing `WorldRecord`, `LandingMetrics`, `LandResult`, `WorldError`, and all existing `.modb` database files remain unchanged; new state is stored in additive internal buckets `_modb_world_links`, `_modb_world_attrs`, `_modb_world_telemetry`, and `_modb_world_fairness`).

## Scope & Components

1. **Key-Level & Range-Level `O(diff)` World Read Validation (`src/modb/world.mo`, `design.md` §6)**
   - Adds `ReadScope` (`BucketScope`, `KeysScope`, `RangeScope`, `MultiScope`) and additive `Catalog` builders:
     - `with_key_scoped_query(cat, name, bucket, key_for_args, run)`
     - `with_keys_scoped_query(cat, name, bucket, keys_for_args, run)`
     - `with_range_scoped_query(cat, name, bucket, range_for_args, run)`
     - `with_dynamic_scoped_query(cat, name, read_buckets, resolve_scope, run)`
   - At landing, when a declared bucket changed externally (`ext_changed`), `compute_ext_changed_keys` runs Layer 1 `Modb.diff_bucket_roots` once per touched bucket and `classify_read_skip` skips re-running queries whose keys or half-open `[start_key, end_key)` range are disjoint from the concurrent edits (`WorldTelemetry.key_level_reads_skipped`).

2. **Starvation / Fairness Priority Tickets (`src/modb/world.mo`, `design.md` §6)**
   - Automatically tracks consecutive `StaleRead` rejections per principal (`PrincipalStarvation`).
   - `claim_priority(db, world_id, buckets, min_stale_threshold, hold_seconds, now)` issues a strictly bounded (`1..60s`) `PriorityTicket`.
   - `land_world_fair` checks active unexpired tickets on modified buckets: overlapping competitors receive `DeferredByFairness` (staying `Open` and pinned without rejection) while disjoint-bucket Worlds land immediately; landing or TTL expiry clears the ticket (`starved_worlds_rescued`).

3. **Nested Child Worlds (`src/modb.mo`, `src/modb/grants.mo`, `src/modb/world.mo`)**
   - `Modb.tx_pin_existing_root` and `Modb.diff_txs` in Layer 1; `Grants.tx_check_descendant_or_same` in Layer 4.
   - `open_child_world` forks a child World from an open Parent World at `parent_step_watermark` with non-widening TTL (`<= parent.expires_at`) and attenuated grant enforcement (`Grants.WideningDenied` otherwise).
   - `world_diff` isolates an unmerged child's changes relative to its Parent fork watermark.
   - `land_child_world` validates the child against Parent post-fork mutations using key/range `O(diff)` skipping and merges steps atomically into the Parent with per-step `StepAttribution` (`world_id`, `grant_id`, `principal`), so final `land_world` enforces downstream grant revocations, ancestor budget conservation, and Grant/World-scoped selective `Replay`.
   - `drop_world`, `expire_worlds`, and rejection cascade cleanly across descendant Child Worlds.

4. **Standalone `modb` CLI (`src/modb/ledger.mo`, `src/modb/cli.mo`)**
   - Adds schema-less store inspection and verification helpers (`verify_audit_store`, `verify_audit_window_store`, `audit_tail_store`, `meta_state_store`) in `Modb.Ledger`.
   - Implements `Modb.Cli` (`modb inspect`, `verify [--fast [N]]`, `dump`, `audit`, `worlds`, `backup`, `export`, `restore`, `compact`, `diff <a.modb> <b.modb>`, `diff <db.modb> --pin <id>`), installable via `mo install src/modb/cli.mo --name modb --bin-dir ~/.local/bin`.

## Verification Criteria
- Dedicated suite [tests/test-m10-worlds-cli.mo](../tests/test-m10-worlds-cli.mo) (5 tests covering key/range `O(diff)` skipping + negative controls, fairness tickets + expiry, multi-level Child Worlds + sibling conflicts + revocation + Replay excision, and end-to-end CLI operations).
- All 22 MoDB `mo test` targets and `tests/test_workbench_mcp_and_ui.py` pass, standalone `modb` CLI installs and passes smoke tests, and downstream `motet` (`store.mo`, `memory.mo`, `server.mo`) passes unchanged.
