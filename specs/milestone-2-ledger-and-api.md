# MoDB Milestone 2: Accountable Ledger, Commit-Time Invariants, Migrations & Concurrent HTTP API

**Status:** Active implementation plan (2026-11-25). Builds directly on Milestone 1 (`Modb` Layer 1 CoW B+Tree + `Modb.Table` Layer 2 typed tables & atomic secondary indexes), running on the pure-Rust `mo` compiler and runtime (`robertguss/mo#433`).

---

## 1. Purpose

Milestone 1 proved pure Mo can build a crash-safe embedded storage engine as a single-process CLI library (`examples/shop.mo`). Milestone 2 moves MoDB into the core database layer of [design.md](../design.md) (§5 & §8 lines 3, 6, 9, 10) by putting it behind a real Mo `api` server (`mo serve`):

1. **Accountable write log (atomic & tamper-evident):** Every write records *who*, *what action*, *why*, *when*, and structured payload inside the **exact same `WriteTx`** as the data mutation, linked by a SHA-256 hash chain and indexed by actor and action.
2. **Commit-time invariant checks:** Application-declared invariants run over the uncommitted `WriteTx` *before* `Modb.commit` flips the meta-page — rolling back data, indexes, and audit entries cleanly on any violation.
3. **Atomic schema versioning & migrations:** Track schema version on disk, refuse opening databases newer than the running code, and execute ordered migrations atomically on startup with full audit records.
4. **Real Mo `api` server (`examples/shop-api.mo`):** Expose `Shop` as a typed REST + OpenAPI 3.1 service with caller authentication, mandatory `X-Reason` write accountability, invariant enforcement, audit queries, zero-socket `ApiTest.send` tests, and live `mo serve` + `SIGKILL` recovery verification.

---

## 2. Two-Phase Delivery (2A → 2B)

### Phase 2A — Pure Mo (Zero `~/code/mo` Changes)
Runs cleanly alongside ongoing `~/code/mo` post-cutover hardening:

1. **Layer 3 (`src/modb/ledger.mo` — `module Modb.Ledger`):**
   - Reserved internal buckets:
     - `_modb_meta` — persists `SchemaState(version, next_audit_seq, last_audit_hash)`
     - `_modb_audit` — append-only `Table(Int, AuditEntry)` keyed by strictly monotonic `seq` (`1, 2, ...`)
     - `_modb_audit_by_principal` — secondary `Text` index on `AuditEntry.principal`
     - `_modb_audit_by_action` — secondary `Text` index on `AuditEntry.action`
   - Tamper-evident hash chain: each `AuditEntry` stores `prev_hash` and `entry_hash = Crypto.sha256(...)` covering `seq`, `txid`, `schema_version`, `principal`, `action`, `reason`, `at`, `summary`, `payload`, and `prev_hash`.
   - Commit-time invariants: `Invariant(name, check: fn(WriteTx) : Result(Option(Text), TableError))` plus `row_invariant(name, tbl, pred)` helper. Evaluated before finalizing the audit entry and calling `Modb.commit`; any violation aborts with `LedgerError.InvariantViolation(name, detail)`.
   - Atomic schema migrations: `Migration(version, description, apply)` executed in strict ascending order inside one atomic `WriteTx` on `Ledger.open` / `Ledger.open_disk`, verifying invariants before commit and logging each migration step in `_modb_audit`.
   - Full verification: `Ledger.verify_audit` (monotonic `seq`, strictly increasing `txid <= store.txid`, intact SHA-256 hash chain, index consistency) and `Ledger.verify_all` (`Modb.verify` + `verify_audit` + all declared invariants on committed state).
2. **Layer 3 Verification Suite (`tests/test-ledger.mo`):**
   - Accountable write atomicity (business errors, unique conflicts, and invariant violations leave zero data changes and zero audit entries).
   - Hash-chain tamper detection (flipping a single field or deleting an entry in `_modb_audit` fails `verify_audit`).
   - Multi-step atomic migrations (`v0 -> v1 -> v2`), idempotent re-open, failed-migration rollback, and `SchemaTooNew` rejection.
   - Indexed audit queries (`audit_by_actor`, `audit_by_action`, `audit_since`, `audit_tail`, `snapshot_audit_tail`).
   - **Deterministic crash-fault simulation (500 seeded crashes):** Verifies that after every torn/dropped/reordered write on `Modb.Pager.sim_empty()`, `Ledger.verify_all` succeeds and committed row state matches the recovered audit log prefix 1-for-1.
3. **Shop HTTP API Server (`examples/shop-api.mo`):**
   - Real declarative Mo `api ... end` server over `Modb.Ledger` + `Modb.Table` with role-based bearer auth (`Admin`, `Clerk`, `Agent`), mandatory `X-Reason` header on mutations, schema migration `v1 -> v2`, 3 commit-time invariants (`stock_non_negative`, `price_positive`, `order_referential_integrity`), REST routes for customers/products/orders/audit/verify, automatic `/openapi.json` & `/docs`, and comprehensive `ApiTest.send` tests.
   - Live `mo serve --workers 1` end-to-end + `SIGKILL` crash-recovery verification (`tests/test_shop_api_live.py`).
4. **Friction Log Update (`FRICTION.md`):**
   - Record every new Mo `api`, `Json`, `Time`, `Files`, or compiler rough edge discovered during 2A so Phase 2B addresses them all in one consolidated Mo PR.

### Phase 2B — Multi-Worker Concurrency PR in `~/code/mo` (Queued After Mo Hardening)
Once `robertguss/mo` finishes its post-cutover hardening pass:
- Add minimal general-purpose concurrency support in `~/code/mo` (candidate: advisory file locks `File.lock_shared` / `File.lock_exclusive` / `File.unlock` via `rustix::fs::flock` with `Files.in_memory` parity, plus `ReadFiles.open` for read-only snapshots, or capability-holding `actor`s) and any high-value 2A friction fixes.
- Wire locking/snapshot readers into `Modb` / `Modb.Ledger` and stress-test `examples/shop-api.mo` under `mo serve --workers 8` concurrent readers and writers.

---

## 3. Phase 2A Exit Gates

Phase 2A is complete when all gates pass on the pure-Rust `mo` release binary:
1. `mo test src/modb.mo` (8/8) and `mo test src/modb/table.mo` (10/10) and `mo test src/modb/ledger.mo` — all pass.
2. `mo test tests/test-modb.mo` (5/5), `mo test tests/test-table.mo` (5/5), and `mo test tests/test-ledger.mo` (incl. 500-crash deterministic simulation) — all pass.
3. `mo test examples/shop.mo` and `mo test examples/shop-api.mo` (full `ApiTest.send` suite) — all pass.
4. `python3 tests/test_shop_api_live.py` — live `mo serve --workers 1` HTTP suite + `SIGKILL` crash + restart + `GET /admin/verify` passes.
5. `mo format` passes cleanly on all modified/created `.mo` files, and `FRICTION.md` records every newly surfaced Mo friction item.
