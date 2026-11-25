# Milestone 4 Spec: Audit Replay, Selective Undo, Bug-Fix Replay & Portable Export/Import

**Status:** Active implementation spec (requested 2026-11-25)  
**Scope:** Realizes `design.md` §4–§5 & §7 (Decision 3: upgrade-aware history replay with
proposal-first adoption; Q6: layout-independent portable export/import) and `experiments.md`
Experiment 18 parity on top of Milestones 1–3 (`Modb`, `Modb.Table`, `Modb.Ledger`, `Modb.Grants`,
`Modb.Claims`, `Modb.World`).

---

## 1. Goals & Non-Goals

### Goals
1. **Layout-independent portable export/import (`Modb.Export`):**
   - Serialize any MoDB `Store` (or any pinned historical `catalog_root`) into a canonical,
     layout-independent JSON `PortableSnapshot` with deterministic sorted bucket/entry ordering and
     a SHA-256 integrity digest — carrying zero page IDs, zero freelist entries, and zero `_modb_pins`
     layout coupling.
   - Strictly validate format version, canonical SHA-256 digest, and hex encoding on import; detect
     any single-byte tamper.
   - Rebuild a freshly compacted `.modb` database file from a `PortableSnapshot` preserving logical
     `txid` watermarks so imported databases pass full `Modb.verify` (0 fragmentation / 0 free
     entries) and full `Ledger.verify_all` (unbroken SHA-256 audit chain + invariants).
2. **Upgrade-aware replayable call log (`Modb.Replay` + `Modb.World` integration):**
   - Persist a monotonic replayable call record (`_modb_replay_calls` + principal index
     `_modb_replay_by_principal` + `_modb_replay_meta`) atomically inside the same `WriteTx` as
     accountable writes (`Replay.execute`, `ShopApi` mutations, and every `CallStep` landed by
     `Modb.World.land_world`).
   - Capture every field proven necessary by Experiment 18: `seq`, `audit_seq`, `schema_version`,
     `principal`, `grant_id`, `grant_chain`, `world_id`, `action`, `args`, `reason`, `at`, and
     `outcome` (`OrigOk(reply)` or `OrigRefused(error)`).
   - Recording refused calls (`OrigRefused`) writes only to `_modb_replay_calls`, touching neither
     user tables nor `_modb_audit`, enabling replay to surface `NowAccepted` outcomes when removing
     earlier bad work or fixing a bug unblocks a previously refused call.
3. **Purposeful divergent replay with proposal-first adoption (`Modb.Replay`):**
   - Support versioned `ReplayCatalog` handlers (`with_action`, `with_timed_action`,
     `with_versioned_action`, `with_override_action`, `with_override_for_version`,
     `with_version_invariants`) stepping through `Schema.migrations` at recorded `schema_version`
     boundaries.
   - Support `ReplayFilter` modes: `ReplayAll`, `ExcludePrincipal`, `ExcludeGrant` (automatically
     expanding to all delegated descendant grants via `Modb.Grants.grant_subtree_ids`),
     `ExcludeSeqs`, `ExcludeWorld`, and `StopBeforeSeq`.
   - Execute replay completely offline on an isolated in-memory `Modb.Pager.sim_empty()` store
     without mutating live state.
   - Produce a structured `ReplayProposal` (persisted in `_modb_replay_proposals`) containing:
     - Per-call `CallOutcome` (`Excluded`, `Unchanged`, `ReplyChanged`, `NowRefused`,
       `NowInvariantBlocked`, `StillRefused`, `NowAccepted`).
     - Aggregate `ReplaySummary` counts and migrations run.
     - Per-bucket `BucketRowDiff` (`added`, `removed`, `modified`) comparing current live user
       buckets against the proposed replayed state.
     - Verified `PortableSnapshot` of the proposed user-bucket state.
     - Freshness guards (`base_audit_seq`, `base_call_seq`) preventing stale proposal acceptance
       after concurrent main-line writes.
   - `accept_proposal` atomically replaces live user buckets with `proposed_state`, preserves all
     `_modb_*` historical/audit/coordination buckets intact, enforces all commit-time `Schema`
     invariants, and appends a hash-chained accountable `AuditEntry`.
4. **Live multi-worker HTTP exposure (`examples/shop-api.mo` + `tests/test_shop_api_live.py`):**
   - Expose read-only `GET /admin/export`, `GET /admin/replay/calls`,
     `GET /admin/replay/proposals`, `GET /admin/replay/proposals/:id` (`ReadFiles` + shared `flock`).
   - Expose Admin-only `POST /admin/replay/simulate`, `POST /admin/replay/proposals/:id/accept`,
     `DELETE /admin/replay/proposals/:id` (`Files` + exclusive `flock`).
   - Verify end-to-end under `mo serve --workers 8` with Wave 4 (rogue grant exclusion + bug-fix
     discount replay + export verification + `SIGKILL` survival).

### Non-Goals (deferred to later milestones)
- Decision 4 GDPR/held-value cryptographic erasure (`Held(T)` vault) — separate design decision.
- Performance/throughput optimization of B+Tree page encoding & multi-worker `flock` — Milestone 5.

---

## 2. Module Dependency Graph (Acyclic)

```
Modb.Errors, Modb.Codec, Modb.Pager, Modb.Tree
  └── Modb (+ buckets_at_root, build_from_buckets)
        └── Modb.Table
              └── Modb.Ledger
                    ├── Modb.Export (new)
                    ├── Modb.Grants (+ grant_subtree_ids)
                    ├── Modb.Claims
                    └── Modb.Replay (new; uses Modb, Pager, Table, Ledger, Export, Grants)
                          └── Modb.World (records landed CallSteps via Replay.tx_record_call)
```

---

## 3. Verification Gates

1. **Unit tests:** `mo test` passes on `src/modb.mo`, `src/modb/grants.mo`, `src/modb/export.mo`,
   `src/modb/replay.mo`, `src/modb/world.mo`, and all existing modules.
2. **Comprehensive suite (`tests/test-replay-export.mo`):**
   - Portable export/import round-trip (200+ rows + secondary indexes + audit chain + grants),
     single-byte tamper detection, zero-fragmentation compaction, historical pinned-root export.
   - Full Experiment 18 parity (`v1` buggy tally -> `v2` fixed tally -> `v3` tally + move_count):
     - Faithful rebuild matches live upgraded DB (`0` divergences).
     - `ExcludePrincipal("b")` matches oracle DB that never received `b`, surfacing `Excluded`,
       `ReplyChanged`, `NowRefused`, and `NowAccepted`.
     - Bug-fix replay (`with_override_for_version(1, "move", v2_move)`) matches oracle DB started on
       `v2`.
     - Negative control: running all calls through newest `v3` code produces a strictly different
       state.
   - Selective undo via `ExcludeGrant` across a 3-level delegation tree (excising root + children).
   - Proposal-first safety: simulation leaves live state untouched; concurrent write causes
     `ProposalStale` rejection on `accept_proposal`; Admin acceptance repairs live state, preserves
     the unbroken SHA-256 audit chain, and passes `Ledger.verify_all`.
   - 500-crash deterministic torn-write simulation across `Replay.execute` and
     `Replay.accept_proposal_and_crash`.
3. **Live HTTP + `SIGKILL` (`examples/shop-api.mo` + `tests/test_shop_api_live.py` Wave 4):**
   - `mo test examples/shop-api.mo` passes (including Milestone 4 `ApiTest.send` suite).
   - `python3 tests/test_shop_api_live.py` passes all 4 waves under `mo serve --workers 8` + `SIGKILL`.
   - `python3 bench/kill_loop.py ... 100` passes cleanly.
