# Milestone 13 (`v0.5.0`): Database-Native Lethal Trifecta Defense (`Modb.Taint`) & Crypto-Verifiable Historical Erasure (`Modb.Erasure`)

Closes the remaining foundational research gaps identified in [`wiki/overview.md`](../wiki/overview.md) and [`design.md`](../design.md):
- **Gap #9 ([`lethal-trifecta-in-a-shared-database.md`](../wiki/ideas/lethal-trifecta-in-a-shared-database.md), [`session-tainting-after-untrusted-reads.md`](../wiki/ideas/session-tainting-after-untrusted-reads.md)):** Database-enforced dynamic session tainting and Lethal Trifecta circuit breaker inside `Modb.Taint` (`src/modb/taint.mo`), wired into `AgentWorkbench` and Motet's live tool loop (`brain.mo`).
- **Right to Be Forgotten ([`design.md`](../design.md) §4.8, [`deleting-personal-data-from-history.md`](../wiki/ideas/deleting-personal-data-from-history.md)):** Dual-layer AES-256-GCM crypto-shredding + physical CoW/index/audit/replay scrubbing + verifiable `ErasureReceipt`s inside `Modb.Erasure` (`src/modb/erasure.mo`).

Preserves 100% backwards compatibility with existing `.modb` files (same `Ledger.AuditEntry` wire schema; lazy internal `_modb_*` tables).

---

## 1. Dynamic Session Tainting & Lethal Trifecta Defense (`src/modb/taint.mo`)

### 1.1 Provenance & Monotonic Session Taint
- `_modb_provenance`: optional `RowProvenance(bucket, key_hex, writer, trust, recorded_txid, updated_at)` (`Owner < InternalAgent < Untrusted`) recorded via `tx_mark_provenance`.
- `_modb_taint_sessions`: `TaintSession` tracking monotonically:
  - `untrusted_tainted: Bool` + `untrusted_sources: List(Text)`
  - `max_sensitivity_read: Policy.Sensitivity` + `sensitive_sources: List(Text)`
  - `blocked_attempts: Int`, `parent_session_id: Option(Text)`, `cleared_by` / `cleared_at`, `closed: Bool`.
- **No child laundering:** `fork_session` inherits `untrusted_tainted`, `untrusted_sources`, `max_sensitivity_read`, and `sensitive_sources` monotonically from parent to child.
- **Human-only reset:** `clear_session_taint` rejects non-admin callers with `ClearDenied` and records `"taint_session_cleared"` in `_modb_audit`.

### 1.2 Enforced Barriers
1. **Post-Untrusted Read Escalation Blocking (`execute_read_program_tainted`, `search_*_tainted`):**
   - Once `session.untrusted_tainted == true`, effective clearance is capped at `min(effective_clearance, tpol.max_sensitivity_when_tainted)`.
   - Subsequent queries touching restricted fields or FTS/Vec scopes fail closed with `TaintedReadEscalationBlocked` before scanning restricted data (and record `"taint_read_escalation_blocked"` in `_modb_audit`).
2. **Two-Way Lethal Trifecta Circuit Breaker (`authorize_write`, `authorize_action`):**
   - Refuses `LethalTrifectaBlocked` and records `"taint_trifecta_blocked"` in `_modb_audit` whenever:
     - a tainted session invokes an `external_actions` effect or writes an `exfil_sinks` bucket;
     - a tainted session writes to a lower-sensitivity bucket (`block_write_down?`, blocking the July 2025 Supabase ticket/exfil attack); or
     - `strict_no_write_down?` blocks `exfil_sinks` writes after reading `Confidential+` data.

---

## 2. Dual-Layer Verifiable Subject Erasure (`src/modb/erasure.mo`)

### 2.1 Layer A — $O(1)$ Per-Subject AES-256-GCM Crypto-Shredding
- `_modb_erasure_keys`: per-subject 32-byte keys provisioned via `SecureRandom` (`provision_subject_key`).
- `seal_for_subject` / `open_for_subject`: domain-separated AES-256-GCM (`aad = "modb:erase:v1:<subject_id>:<field_aad>"`).
- `shred_subject_key`: admin-only atomic overwrite of `key_b64 = ""`, `shredded? = true` — rendering all historical ciphertext unreadable in $O(1)$ even across uncompacted backups.

### 2.2 Layer B — Physical Multi-Store Scrubbing, Hash-Chain Re-Anchoring & Compaction
- `_modb_subject_refs` & `ErasureRequest`: deletes live subject rows, secondary index entries (via `extra_bucket_keys` / `tx_register_subject_ref`), FTS documents (`Fts.tx_remove_document`), Vec documents (`Vec.tx_remove_vector`), `_modb_replay_calls` PII, and `_modb_read_log` PII atomically.
- **Audit-Chain Redaction + Deterministic Re-Chaining:** scrubs matching `_modb_audit` entries' payloads and reasons into `[erased:sha256=<prefix>]` tombstones and recomputes `prev_hash` / `entry_hash` via `Ledger.compute_entry_hash` from the first touched `seq` through tip (updating `_modb_meta` and `_modb_checkpoints`), then appends an `"erasure_executed"` entry referencing only SHA-256 of `subject_id` (zero PII) and persists `ErasureReceipt` in `_modb_erasure_receipts`.
- **`compact_after_erasure`:** rebuilds via `Export.compact_db` to physically evict all stale CoW pages from disk and marks `receipt.compacted? = true`.
