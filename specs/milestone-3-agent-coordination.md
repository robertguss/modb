# MoDB Milestone 3: Multi-Agent Coordination (`Worlds`, `Grants`, `Claims`, Persistent Pins & CoW Diff)

**Status:** Complete & verified (2026-11-25). Builds directly on Milestones 1 & 2 (`Modb`, `Modb.Table`, `Modb.Ledger`, `ReadFiles` + advisory `flock`, 8-worker `ShopApi`), running on pure-Rust `mo` (`robertguss/mo#436`, `7d5186d1`). Required **zero changes to `~/code/mo`**.

---

## 1. Purpose

Milestones 1 and 2 delivered the base case of [design.md](../design.md) (§3–§5): a crash-safe CoW B+Tree, typed tables with atomic secondary indexes, a tamper-evident SHA-256 accountable write ledger, commit-time invariants, atomic schema migrations, and a least-privilege 8-worker HTTP API.

Milestone 3 builds **Layer 4 — Coordination for Overlapping Work by Many Agents** ([design.md](../design.md) §4, §6, §7; [GLOSSARY.md](../GLOSSARY.md)), implementing and verifying in pure Mo the exact protocols previously checked only in TLA+ ([models/README.md](../models/README.md) — closing `"There is no implementation to compare the model with"` for both `Replay.tla` and `Worlds.tla`):

1. **Persistent O(1) Pinned Roots & O(diff) Structural CoW Diff** in Layer 1 (`Modb`).
2. **Attenuated Grants & Cascading Revocation** (`Modb.Grants` — *"helpers get less, never more"*).
3. **Agent Claims / Leases** (`Modb.Claims` — *"agents see each other through data"*, preventing slow-agent starvation).
4. **Speculative Worlds with Whole-or-Nothing Replay, Per-Call Invariants & In-Place Answer Validation** (`Modb.World` — Robert's Option 3 from `Worlds.tla` + Answers 1 & 3 from `Replay.tla` + needless send-back telemetry).
5. **Live 8-Worker Multi-Agent `ShopApi`** exercising overlapping Worlds, delegated helper grants, mid-flight grant revocation, stale-read rejection, claims, and hard `SIGKILL` recovery.

**Explicit Non-Goals for Milestone 3 (deferred to later milestones / `~/code/mo` runtime work):**
- Compiling arbitrary untrusted Mo read programs at runtime inside `mo serve` ([design.md](../design.md) §8 line 7) — Milestone 3 uses an explicit application-registered `QueryHandler` / `ActionHandler` catalog in pure Mo.
- Compiler-level automatic query planning ([design.md](../design.md) §5 & §8 line 14).
- Type-level information-flow sensitivity labels ([design.md](../design.md) §8 line 13).

---

## 2. Layer 1 Storage Upgrades (`src/modb.mo` & `src/modb/tree.mo`)

### 2.1 Crash-Safe Persistent Root Pins (Zero On-Disk `MetaPage` Format Break)
Today `Modb.Snapshot` pins a `catalog_root` only in memory inside a single `Store`. For an agent's World to span multiple HTTP requests (and survive process restarts / `SIGKILL`) at **O(1) copy cost**, Layer 1 adds persistent pins:

- Reserved internal buckets:
  - `_modb_pins`: `pin_id (UTF-8) -> (txid: i64_be, catalog_root: i64_be)`
  - `_modb_deferred`: `txid (i64_be) -> list of page_ids freed at commit txid`
- **Commit & reclamation invariant:**
  - `min_pin = min(all in-memory Snapshot.txid, all persisted _modb_pins.txid, new_txid)`.
  - Pages freed at commit `T > min_pin` are stored in `_modb_deferred` (NOT in `freelist_root`), so on reopen / crash recovery `load_freelist` loads **only** genuinely reusable `ready_free` pages while `_modb_deferred` restores deferred-free tags intact.
  - When `unpin_root(tx, pin_id)` commits and `min_pin` advances past `T`, all `df.txid <= min_pin` graduate cleanly from `_modb_deferred` to `ready_free` and are reused automatically.
- **Exact page-accounting proof in `Modb.verify`:**
  - `{0, 1} U current_trees U freelist_chain U ready_free U deferred_frees == {0 .. page_count - 1}` remains a 100% disjoint partition.
  - `Modb.verify` additionally traverses every `catalog_root` in `_modb_pins`, asserting every page passes SHA-256 verification and belongs to `current_trees U deferred_frees` (never `ready_free`).
- **New `Modb` APIs:** `pin_root`, `unpin_root`, `list_pins`, `get_at_root`, `scan_at_root`, `begin_write_from_root` (constructs a speculative `WriteTx` rooted at a pinned `catalog_root` for in-world execution without touching the main line).

### 2.2 O(diff) Structural CoW Tree Diff (`Modb.diff_roots` / `Modb.diff_bucket`)
Because two CoW roots share identical page IDs for every unmodified subtree:
- `diff_tree(pager, root_a, root_b)` short-circuits immediately when `root_a == root_b` without reading child pages.
- Returns sorted `List(KeyDiff)` where `enum KeyDiff { Added(key: Bytes, value: Bytes), Removed(key: Bytes, value: Bytes), Modified(key: Bytes, old_value: Bytes, new_value: Bytes) }`.
- `diff_roots(store, root_a, root_b)` compares catalogs first, skipping untouched buckets in O(1) and descending only buckets whose root page ID changed.
- Layer 2 (`Modb.Table`) wraps this with typed `Table.diff(store, tbl, root_a, root_b)`.

---

## 3. Layer 4 Modules (100% Pure Mo on `Modb.Ledger`)

### 3.1 Attenuated Grants & Delegation Chains (`src/modb/grants.mo` — `module Modb.Grants`)
Implements *"helpers get less, never more"* ([design.md](../design.md) §6):

- Stored in reserved table `_modb_grants` (`id: Text -> Grant`), indexed by `principal` and `parent_id`:
  ```mo
  struct Grant
    id: Text
    parent_id: Option(Text)
    principal: Text
    allowed_actions: List(Text)   ## sorted, deduplicated action names
    max_calls: Int                ## 0 = read-only; > 0 = total write calls allowed
    used_calls: Int
    expires_at: Time
    revoked: Bool
    chain: List(Text)             ## [root_issuer, ..., parent_principal, principal]
  end
  ```
- **Operations (all atomic inside `WriteTx` + recorded in `_modb_audit`):**
  - `issue_root`: Admin issues a top-level grant.
  - `delegate(tx, parent_id, child_spec, now)`: Creates a child grant iff:
    1. `parent` and every ancestor in its `parent_id` chain are active (`not revoked`, `now <= expires_at`).
    2. `child.allowed_actions ⊆ parent.allowed_actions`.
    3. `child.max_calls >= 0` and `child.max_calls <= parent.max_calls - parent.used_calls`.
    4. `child.expires_at <= parent.expires_at`.
    - Any violation fails with `GrantError.WideningDenied(field, detail)`.
  - `authorize(tx, grant_id, action, now)`: Walks the full ancestor chain (catching parent revocation atomically at commit/landing time), enforces `action in allowed_actions`, `used_calls < max_calls`, `now <= expires_at`, and increments `used_calls` inside the committing transaction.
  - `revoke(tx, grant_id)`: Marks `revoked = true`; immediately invalidates the grant and all descendant helper grants on their next `authorize` / `land_world`.

### 3.2 Agent Claims / Leases (`src/modb/claims.mo` — `module Modb.Claims`)
Implements *"agents see each other through data"* and slow-agent fairness ([design-ideas.md](../design-ideas.md)):

- Stored in reserved table `_modb_claims` (`resource: Text -> Claim`):
  ```mo
  struct Claim
    resource: Text
    holder: Text
    grant_id: Text
    world_id: Option(Text)
    reason: Text
    acquired_at: Time
    expires_at: Time
  end
  ```
- **Operations:** `acquire` (succeeds if unheld, expired at `now`, or already held by the same `holder`), `heartbeat` (extends TTL), `release`, `get_active`, `list_active`. Expired claims are ignored lazily using `Clock.now` so crashed agents never leak permanent locks.

### 3.3 Speculative Worlds & Landing Replay (`src/modb/world.mo` — `module Modb.World`)
Implements Robert's exact decided semantics from `Replay.tla` and `Worlds.tla`:

- **Approved Catalog (`Catalog`):**
  - `QueryDef(name: Text, run: fn(WriteTx, Json) : Result(Json, Text))`
  - `ActionDef(name: Text, run: fn(WriteTx, Json) : Result((WriteTx, Json), Text))`
- **Persisted State (`_modb_worlds`, `_modb_world_metrics`):**
  ```mo
  enum WorldStep
    ReadStep(query: Text, args: Json, answer_hash: Text, answer: Json)
    CallStep(action: Text, args: Json, reason: Text)
  end

  enum WorldStatus
    Open
    Landed(commit_txid: Int)
    Rejected(reason: Text)
    Dropped
  end

  struct WorldRecord
    id: Text
    grant_id: Text
    principal: Text
    base_txid: Int
    base_pin_id: Text
    steps: List(WorldStep)
    status: WorldStatus
    created_at: Time
    expires_at: Time
  end

  struct LandingMetrics
    total_landed: Int
    stale_read_rejections: Int
    invariant_rejections: Int
    action_rejections: Int
    grant_rejections: Int
    needless_send_backs: Int      ## floor: next world by same principal lands identical CallSteps
  end
  ```
- **Exact Lifecycle:**
  1. **`open_world`:** Under `lock_exclusive`, validates grant, pins current `catalog_root` via `Modb.pin_root`, stores `WorldRecord(status: Open, steps: [])`, unlocks. Zero data copied; zero locks held while the agent thinks.
  2. **`world_query`:** Replays the World's own `CallStep`s atop its pinned `base_catalog_root` in an isolated speculative `WriteTx`, runs `QueryDef`, computes `answer_hash = sha256(Json.encode(answer))`, appends `ReadStep`, and returns `answer`.
  3. **`world_call`:** Replays the World's own `CallStep`s atop `base_catalog_root`, executes `ActionDef`, **runs all schema invariants immediately** (fast fail inside the World), appends `CallStep`, and returns the speculative reply — main line untouched.
  4. **`world_diff`:** Computes exact `Modb.diff_roots` / staged changes for inspection before landing.
  5. **`land_world` (Whole-or-Nothing + Per-Call Rules + In-Place Answer Validation):**
     Under `lock_exclusive`, inside a single atomic main-line `WriteTx`:
     - Verify World is `Open` and `now <= world.expires_at`.
     - Replay `world.steps` in exact interleaved order:
       - **`ReadStep`:** Re-run `query(replay_tx, args)` **in place** (seeing the World's own earlier replayed `CallStep`s — `Worlds.tla` finding #4). If `sha256(new_answer) != expected_hash`, abort and roll back main line cleanly, record `stale_read_rejections += 1` (and stash the call signature to detect needless send-backs on the agent's next landing), and return `Error(StaleRead(query, args, expected, actual))`.
       - **`CallStep`:** Call `Grants.authorize(replay_tx, grant_id, action, now)`, run `action(replay_tx, args)`, and **check ALL schema invariants immediately after this step** (`Worlds.tla` Option 3). Any failure aborts and rolls back the entire World cleanly.
     - On success: update `LandingMetrics` (incrementing `total_landed` and `needless_send_backs` if the call sequence matches a prior stale-read rejection for the same principal), mark `WorldRecord` as `Landed(commit_txid)`, **unpin `base_pin_id`**, append an accountable SHA-256 hash-chained audit entry recording `world_id`, `base_txid`, `grant_id`, and `grant.chain`, and commit atomically!
  6. **`drop_world` / `expire_worlds`:** Marks World `Dropped` and unpins `base_pin_id`, immediately releasing deferred pages for freelist reclamation.

---

## 4. `ShopApi` Multi-Agent Upgrade (`examples/shop-api.mo`)

Extend `ShopApi` (keeping all existing direct routes 100% compatible!) with multi-agent endpoints:
- `POST /grants`, `POST /grants/:id/delegate`, `POST /grants/:id/revoke`, `GET /grants/:id` (`ReadFiles`)
- `POST /claims`, `POST /claims/:resource/heartbeat`, `DELETE /claims/:resource`, `GET /claims` (`ReadFiles`)
- `POST /worlds`, `POST /worlds/:id/query`, `POST /worlds/:id/call`, `GET /worlds/:id/diff` (`ReadFiles`), `POST /worlds/:id/land`, `DELETE /worlds/:id`, `GET /worlds/metrics` (`ReadFiles`)

---

## 5. Verification Gates

1. **Layer 1 Pins & Diff (`tests/test-pins-diff.mo`):**
   - Pinned root survives 500 commits + 500 deterministic simulated power-cuts; `Modb.verify` proves exact page partition and intact pinned subtrees; unpinning reclaims 100% of deferred pages.
   - `Modb.diff_roots` differential test vs naive full-scan diff + subtree-skip verification.
2. **Full TLA+ Model Parity Suite (`tests/test-worlds.mo`):**
   - Reproduces and passes **all 6 `Replay.tla` cases** (`seat`, `meeting`, `skew`, `discount`, `lost_update`, `intent` with needless send-back metric) and **all 6 `Worlds.tla` cases** (`transfer`, `budget`, `audit`, `stuck`, `ownread`, `apart`), including negative controls verifying that disabling read validation lets `discount` & `lost_update` slip through and checking invariants only at the end lets `budget` slip through!
   - Full `Modb.Grants` widening-denial + cascading-revocation tests and `Modb.Claims` lease/expiry/fairness tests.
   - 500-crash deterministic torn-write simulation across open Worlds, landings, grants, and claims.
3. **Live 8-Worker Multi-Agent Stress & `SIGKILL` Test (`tests/test_shop_api_live.py`):**
   - Under `mo serve --workers 8`: concurrent agents open Worlds, delegate narrower helper grants, race to land overlapping orders, catch stale-price discount calculations cleanly (`409 StaleRead`), observe parent revocation blocking an in-flight helper World, survive hard `SIGKILL` with open Worlds intact across restart, and pass `GET /admin/verify` (100% intact B+Tree + pinned roots + SHA-256 audit hash chain + invariants).

---

## 6. Suggested Delivery Split

- **Phase 3A (Layer 1 Foundations):** Persistent root pins (`_modb_pins` / `_modb_deferred` + `Modb.verify` partition & pin checks) and O(diff) structural `Modb.diff_roots` / `Table.diff`, verified in `tests/test-pins-diff.mo`.
- **Phase 3B (Layer 4 Coordination):** `Modb.Grants`, `Modb.Claims`, and `Modb.World` + full 12-case `Replay.tla`/`Worlds.tla` parity & 500-crash suite in `tests/test-worlds.mo`.
- **Phase 3C (Live 8-Worker Multi-Agent API):** Wire Worlds, Grants, and Claims into `examples/shop-api.mo` and upgrade `tests/test_shop_api_live.py` for concurrent multi-agent Worlds + revocation + `SIGKILL`.
