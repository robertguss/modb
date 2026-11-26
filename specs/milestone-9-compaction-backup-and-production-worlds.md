# Milestone 9 Spec: First-Class Compaction, Online Backup, Production `Worlds`, Hierarchical `Views`/`Releases`, and `v0.1.0`

Builds on Milestones 1–8 (`src/`, `examples/`) and brings speculative CoW `Worlds`, hierarchical `Views`/`Releases`, and first-class compaction/backup into both MoDB core and production [`motet`](../motet):

1. **First-Class Online Backup & Compaction (`src/modb/export.mo`)**
   - `Export.backup_db(rf, src_path, dst_files, dst_path, sc, include_internal, now)`: takes a consistent lock-coordinated online snapshot (`Export.export_locked`), materializes & verifies a compacted copy via a staging `.backup.tmp` file, and swaps it atomically (refusing overwrite with `TargetNotEmpty`).
   - `Export.compact_db_with_hook` / `Export.compact_db`: exports live state & metrics under `Ledger.read_locked`, compacts into `*.compact.tmp`, runs `after_import(ldb)` and optional `Ledger.record_verify_checkpoint`, verifies everything with `Ledger.verify_all`, and atomically swaps `*.compact.tmp` -> `path` (cleaning up `*.compact.tmp` on any failure).
   - Fixes `Export.import_db` for `include_internal: false` when `snap.schema_version > 0`: pre-seeds `_modb_meta["state"]` at `snap.schema_version` (`next_audit_seq: 1`, `genesis_hash`) so historical seed migrations never overwrite compacted user data.

2. **Replay-Safe Compaction (`src/modb/replay.mo`)**
   - `Replay.compact_with_baseline(files, path, sc, now, after_import)` and `Replay.compact_with_baseline_default`: run `Export.compact_db_with_hook(..., include_internal: false, record_checkpoint?: true, ...)` while running `after_import` (e.g., re-provisioning root grants) and pinning `_modb_replay_baseline` atomically before verification and swap, returning `Export.CompactReport` (`baseline_pinned?: true`, `checkpoint_recorded?: true`).

3. **Production Integration in Motet (`../motet`) & Benchmark Refresh**
   - Motet adopts `Replay.compact_with_baseline` + `Export.backup_db` (`motet backup`), atomic speculative CoW `Worlds` for Overnight Dreaming preview/landing (`ReadsSkipped` with O(1) CoW-diff skipping), hierarchical narrowing `Views` (`bots_public -> bots`, `memories_shared -> memories`), k-anonymous `Releases` (`memory_scope_summary`, `bot_activity_summary`), Read Provenance Log Explorer (`_modb_read_log`), and bot-accessible `modb_describe` / `modb_query` tools gated by each bot's Grant.
   - [`BENCHMARKS.md`](../BENCHMARKS.md) refreshed with Milestone 8/9 measurements and [`tests/test-compact-backup.mo`](../tests/test-compact-backup.mo) verifying all 4 compaction/backup/replay/atomicity contracts, followed by `modb` `v0.1.0` tag.
