# MoDB Layer 1 Benchmarks & Verification Record

Measured on **2026-11-23** against `mo` release build (`gcc -O2`, commit `dccb3f0d` — merged in [robertguss/mo#416](https://github.com/robertguss/mo/pull/416)), running on Linux ext4 with 64-byte values and 8-byte `i64_be` keys.

Reproduce:
```sh
mo test src/modb.mo
mo test tests/test-modb.mo
python3 bench/kill_loop.py <path-to-mo> 100
TMP=$(mktemp -d) && mo run --root "$TMP" bench/bench-modb.mo 100000 && rm -rf "$TMP"
```

---

## 1. Correctness & Crash-Safety Gates

| Gate | Command | Result |
| --- | --- | --- |
| Unit tests (all 5 `src/` modules) | `mo test src/modb.mo` | **8/8 passed** |
| Gate 1: Differential vs reference `Map` (1,200 random ops, overflows, aborts, snapshots) | `mo test tests/test-modb.mo` | **Pass** (0 mismatches, 0 page leaks) |
| Gate 2: Deterministic crash simulation (500 torn/dropped/reordered crashes + bit-flip detection) | `mo test tests/test-modb.mo` | **Pass** (500/500 clean atomic recovery) |
| Gate 3: Real OS `SIGKILL` (`kill -9`) crash loop on disk | `python3 bench/kill_loop.py <mo> 100` | **Pass** — 100/100 kills survived in 23.1s (`acked=506`, recovered `last_seq=507`, `verify` clean after every kill) |
| Gate 4: 100k load + 100k overwrites freelist stability | `bench/bench-modb.mo 100000` | **Pass** — page count flat at **3,933 pages (`45` free)** across overwrite batches 26, 51, 76, and 100; final `verify: OK` |

---

## 2. Scaling & Head-to-Head vs Mo's Built-In `Sqlite`

Both engines run inside the same Mo process on the same disk (`Sqlite`: `PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL`; `MoDB`: 4 KiB pages, full SHA-256 checksum on every page, 2 `fsync`s per commit).

### MoDB (Pure Mo Bytecode VM)

| Metric | 1,000 rows | 10,000 rows | 100,000 rows | Scaling (1k → 100k) |
| --- | ---: | ---: | ---: | --- |
| Bulk load (`1,000`-row synced batches) | 111 ms | 1,243 ms | 13,815 ms | ~7,240 rows/sec |
| Full overwrite (`1,000`-row synced batches) | 99 ms | 1,068 ms | 11,796 ms | ~8,480 rows/sec |
| Warm point `get` (1,000×) | 68 ms (68 µs) | 88 ms (88 µs) | 104 ms (104 µs) | $O(\log N)$ |
| Cold point `get` (1,000×, empty cache + SHA-256) | 101 ms (101 µs) | 130 ms (130 µs) | 152 ms (152 µs) | $O(\log N)$ |
| 100-row ordered range `scan` (100×) | 109 ms | 149 ms | 144 ms | Flat |
| Single-row synced `write_tx` (100×) | 250 ms | 334 ms | 399 ms | ~3.99 ms/commit |
| File size on disk (after overwrites) | 336 KiB | 1.8 MiB | 16 MiB | 3,933 × 4 KiB pages |
| Peak process RSS (combined MoDB + SQLite run) | — | — | **69.8 MiB** | Bounded (`4,096`-page cache) |

### Head-to-Head at 100,000 Rows: MoDB (Pure Mo) vs SQLite (C)

| Workload | MoDB (Mo bytecode) | SQLite (C) | Ratio |
| --- | ---: | ---: | ---: |
| Load 100k rows (100 × 1k batches) | 13,815 ms | 644 ms | 21.5× |
| Overwrite 100k rows (100 × 1k batches) | 11,796 ms | 618 ms | 19.1× |
| Point `get` (1,000×, warm) | 104 ms | 9 ms | 11.6× |
| 100-row range `scan` (100×) | 144 ms | 5 ms | 28.8× |
| Single-row synced write (100×) | 399 ms | 55 ms | 7.3× |
| Disk file size | 16 MiB | 7.2 MiB | 2.2× |

---

## 3. Impact of Dirty-Node Buffering (10,000 Rows, Before vs. After)

The initial naive CoW implementation re-encoded, re-hashed (SHA-256), and updated the catalog page on every individual `tx_put`, and ran `verify_header` twice per read hop. Buffering dirty decoded nodes inside `WriteTx` (sealing once at `commit`), caching dirty bucket roots, switching leaf/branch search to binary search, and verifying SHA-256 once on cold disk load gave an immediate **13–14.5× write speedup**:

| Metric (10,000 rows) | Naive CoW | Dirty-Node Buffered | Speedup |
| --- | ---: | ---: | ---: |
| Load 10k rows (10 × 1k batches) | 16,394 ms | 1,243 ms | **13.2×** |
| Overwrite 10k rows | 15,525 ms | 1,068 ms | **14.5×** |
| Warm point `get` (1,000×) | 138 ms | 88 ms | **1.6×** |
| Cold point `get` (1,000×) | 172 ms | 130 ms | **1.3×** |

---

## 4. Impact of PR #417 (`Bytes.compare_slice_at` + DX Improvements)

Measured on **2026-11-23** against `mo` release build (`gcc -O2`, commit `067fc6ae` — merged in [robertguss/mo#417](https://github.com/robertguss/mo/pull/417)) after adopting `Bytes.compare_slice_at`, `Bytes.empty?`, bare `_ = expr`, and local `var` in anonymous functions across MoDB (all 5 suites / 29 tests passing).

Controlled back-to-back A/B runs (`BEFORE = raw.slice + ==/<` vs `AFTER = Bytes.compare_slice_at`, same `mo` binary, `/dev/shm` tmpfs to isolate CPU/VM cost from disk `fsync` jitter):

| Controlled A/B Benchmark (same `mo` binary, `/dev/shm`) | Before (`raw.slice`) | After (`compare_slice_at`) | Delta |
| --- | ---: | ---: | --- |
| 10k DB warm `get` (1,000×, median of 3 alternating trials) | 96 ms | 82 ms | **~15% faster** |
| 10k DB cold `get` (1,000×, median of 3 alternating trials) | 145 ms | 133 ms | **~8% faster** |
| 20k DB true warm-cache `get` (10,000×, 8B keys, median of 3) | 1,297 ms | 1,187 ms | **~8.5% faster** |
| 100k DB load + overwrite + freelist stability (`/dev/shm`) | 13,627 ms / 10,998 ms | 13,134 ms / 11,515 ms | Flat (within host jitter); `3,933` pages (`45` free), `70.0 MiB` RSS, `verify: OK` |

**Two diagnostic findings from microbenchmarking `compare_slice_at` (200,000 probes/round):**
1. **Nested `case` pattern matching overhead:** Matching `Some(Equal)` / `Some(Greater)` / `Some(Less)` / `None` directly compiled to sequential tag checks (~`258–274 ms` on misses), whereas splitting `Some(ord)` and placing common binary-search arms (`Less`/`Greater`) before `Equal` cut ~12–16% (`217–250 ms`).
2. **Allocation wasn't the main bottleneck on 8-byte keys:** Mo's Perceus allocator reuses short-lived `raw.slice` buffers cheaply (~20–30 ns), while `Option(Ordering)` still boxes a choice cell (`mo_value_case`) and each `get` executes ~60 Mo helper calls (`read_u16`/`read_i64` + `try`) plus bytecode loop dispatch (~800–1,000 ns/probe).

---

## 5. Pure-Rust `mo` Baseline (Post-Cutover, PR #433)

Measured on **2026-11-25** against the unified pure-Rust `mo` release binary (`rustc 1.97.1 --release`, `#![forbid(unsafe_code)]`, `robertguss/mo` commit `22369508` — merged in [robertguss/mo#433](https://github.com/robertguss/mo/pull/433)), running on the same Linux ext4 machine (8 vCPUs; host load average ~4.5–5.8 during 1k/10k runs due to background work, ~5.1 at 100k with zero `rustc` active during the 100k run).

### Correctness & Crash-Safety Gates on Pure-Rust `mo`

| Gate | Command | Result |
| --- | --- | --- |
| All 5 MoDB test suites (`modb`, `table`, `test-modb`, `test-table`, `shop`) | `mo test ...` | **29/29 passed** (`8 + 10 + 5 + 5 + 1`, 0 failed, 0 stopped) |
| `examples/shop.mo` end-to-end CLI run | `mo run --root "$TMP" examples/shop.mo` | **Pass** (`txid=9, buckets=6, pages=26`, `Modb.verify` OK) |
| Gate 3: 100× real OS `SIGKILL` (`kill -9`) crash loop | `python3 bench/kill_loop.py <rust-mo> 100` | **Pass** — 100/100 kills survived in **8.9s** (`acked=282`, recovered `txid=284`, `last_seq=283`, `pages=77`, `free=6`) |
| Gate 4: 100k load + 100k overwrites freelist stability | `bench/bench-modb.mo 100000` | **Pass** — page count flat at **3,933 pages (`45` free)** across batches 26, 51, 76, and 100; final `verify: OK` |

### Scaling Across 1k / 10k / 100k Rows (Pure-Rust `mo` `22369508`)

| Metric | 1,000 rows | 10,000 rows | 100,000 rows |
| --- | ---: | ---: | ---: |
| Bulk load (`1,000`-row synced batches) | 170 ms | 1,946 ms | 19,246 ms |
| Full overwrite (`1,000`-row synced batches) | 148 ms | 1,702 ms | 14,212 ms |
| Warm point `get` (1,000×) | 125 ms | 151 ms | 138 ms |
| Cold point `get` (1,000×, empty cache + SHA-256) | 175 ms | 215 ms | 179 ms |
| 100-row ordered range `scan` (100×) | 207 ms | 231 ms | 225 ms |
| Single-row synced `write_tx` (100×) | 428 ms | 756 ms | 462 ms |
| File size on disk (after overwrites) | 336 KiB | 1.8 MiB | 16 MiB (`3,933` pages) |
| Peak process RSS (combined MoDB + SQLite run) | 44.2 MiB | 44.4 MiB | **52.4 MiB** (`53,668 KiB`) |

*(Note: 1k and 10k rows ran while another worktree was finishing a Rust build, which also inflated SQLite's 100× single-row sync to 290–312 ms; the 100k column ran after `rustc` finished, where SQLite single-row sync returned to 54 ms — matching Nov 23's 55 ms.)*

### C `mo` (`gcc -O2`, PR #416) vs. Pure-Rust `mo` (PR #433) vs. SQLite at 100,000 Rows

| Workload (100,000 rows, ext4) | C `mo` (`gcc -O2`) | Pure-Rust `mo` (`22369508`) | Rust / C | SQLite (same Rust run) |
| --- | ---: | ---: | ---: | ---: |
| Load 100k rows (100 × 1k batches) | 13,815 ms | 19,246 ms | 1.39× | 704 ms |
| Overwrite 100k rows (100 × 1k batches) | 11,796 ms | 14,212 ms | 1.20× | 864 ms |
| Warm point `get` (1,000×) | 104 ms | 138 ms | 1.33× | 8 ms |
| Cold point `get` (1,000×, empty cache + SHA-256) | 152 ms | 179 ms | 1.18× | — |
| 100-row range `scan` (100×) | 144 ms | 225 ms | 1.56× | 5 ms |
| Single-row synced `write_tx` (100×) | 399 ms | 462 ms | 1.16× | 54 ms |
| File size on disk (after overwrites) | 16 MiB | 16 MiB | 1.00× | 7.2 MiB |
| Peak process RSS (combined run) | 69.8 MiB | **52.4 MiB** | **0.75× (25% less)** | — |
| 100× real OS `SIGKILL` crash loop | 23.1 s | **8.9 s** | **0.39× (2.6× faster)** | — |

---

## 6. What These Numbers Tell Us

1. **Pure safe Rust (`#![forbid(unsafe_code)]`) is immediately viable for real systems code:** ~7.2k warm point lookups/sec, ~7.0k overwrites/sec, 100k rows in **52.4 MiB peak RSS** (25% lower than C `mo`), ~4.6 ms durable commits, **2.6× faster `SIGKILL` recovery loop** (lower process startup/reopen latency), and 1.16×–1.56× of C `-O2` VM wall time — with zero memory-safety hazards and zero C compiler/runtime code.
2. **Where the ~17×–27× gap to C SQLite actually lives:**
   - **Bytecode dispatch & Mo function-call overhead** (confirmed by PR #417's A/B: eliminating `raw.slice` copies only saves ~8–15% because tight loop instruction count and helper calls dominate).
   - Full SHA-256 over every 4 KiB page (vs. SQLite's unchecksummed default / CRC32C).
   - 2× `fsync` per commit (CoW shadow paging) vs. SQLite WAL's 1× append `fsync`.
   - 50/50 split on sequential appends (leaves ~50% page fill = 16 MiB vs. SQLite's 7.2 MiB; right-edge 90/10 splitting would halve disk footprint and page writes).
3. **Implication for future Phase 4 optimization (Cranelift JIT/AOT):** The pure-Rust VM already holds its own against the deleted C `-O2` VM (1.2×–1.5×) while cutting RSS by 25%. Closing the remaining order-of-magnitude gap to C SQLite requires reducing bytecode dispatch/call overhead (e.g., Cranelift JIT/AOT over `.bc` plus compact `Value` representation), which should wait until Milestone 2's real `api`/service workloads show where end-to-end latency actually goes.

---

## 7. Milestone 5 Pure-Mo Storage, Invariant & Concurrency Optimizations (2026-11-25)

Measured on the same pure-Rust `mo` binary (`7d5186d1`, ext4, 64-byte values, 8-byte `i64_be` keys) before and after six pure-Mo engine optimizations (100% on-disk v1 format compatible):

1. **O(1) tracked node byte sizes** (`DirtyLeaf` / `DirtyBranch`) replacing O(M²) `leaf_body_size` / `branch_body_size` scans on every `put`, `delete`, and merge.
2. **Right-edge sequential splitting (~98% leaf / ~90% branch fill) + O(1) right-edge & sequential-overwrite hints** (`DirtyLeaf.hint`, Perceus unique-ownership pop on `dirty_leaves` for in-place `List.append`/`List.set`).
3. **Single-pass zero-copy page sealing** (`Codec.seal_parts` with packed `u32_be` headers, eliminating per-cell `Bytes.join` and 3 redundant 4 KiB copies per encoded page).
4. **Inlined raw binary-search reads & zero-decode range scans** (`Codec.branch_lookup_child_raw`, `leaf_lookup_entry_raw`, `branch_scan_children_raw`, `leaf_scan_raw`, `verify_leaf_raw`).
5. **Lock-free optimistic CoW snapshot reads** in `Modb.with_shared_lock` (seqlock `start_txid == end_txid` verification with `lock_shared` fallback), eliminating BSD `flock` writer starvation under heavy concurrent HTTP readers.
6. **O(touched) incremental commit-time invariants** (`Modb.begin_write_tracked`, `Ledger.row_invariant`, `Replay.preview_replay`, `ShopApi.order_referential_integrity`), turning O(N²) multi-call replay invariant checks into O(N).

### 100,000-Row Storage Engine: Before vs. After Milestone 5 (ext4)

| Metric (100,000 rows, 64B values) | Before M5 (`d73494b`) | After M5 | Improvement | SQLite (same run) |
| --- | ---: | ---: | --- | ---: |
| Bulk load 100k (`100 × 1k` synced) | 15,848 ms | **5,781–6,823 ms** | **2.3–2.7× faster** | 643 ms |
| Full overwrite 100k (`100 × 1k` synced) | 15,099 ms | **8,806–8,845 ms** | **1.71× faster** | 630 ms |
| `Modb.verify` (100k cold SHA-256) | 1,290 ms | **764–783 ms** | **1.65× faster** | — |
| Warm point `get` (1,000×) | 138 ms | **98–111 ms** | **1.24–1.41× faster** | 8 ms |
| 100-row range `scan` (100×) | 203 ms | **137–173 ms** | **1.17–1.48× faster** | 5 ms |
| Disk file size (after overwrites) | 15.7 MiB (`3,933` pages) | **8.2 MiB (`2,041` pages)** | **48% smaller** | 7.2 MiB |
| 100× real OS `SIGKILL` (`kill_loop.py`) | 496 acked / 10.7 s | **589 acked / 11.0 s** | **+19% commit throughput** | — |

### Live 8-Worker HTTP Concurrency (`bench/bench_shop_api.py`, `mo serve --workers 8`)

| Workload | Result | Latency |
| --- | --- | --- |
| Pure 8-thread reads (400× `GET /products/:sku`) | **386.0 req/s** (0 errors) | p50 = `20.1 ms`, p95 = `24.7 ms` |
| Mixed 6 readers + 2 synced writers (`565` reads + `100` audited orders in `2.06 s`) | **323.1 req/s** (0 errors, zero writer starvation) | reads p50 = `21.9 ms` / p95 = `36.6 ms`; writes p50 = `38.3 ms` / p95 = `63.2 ms` |
| Live offline Replay Simulate (`111` calls, 15% discount override) | **716.3 ms** (was 500 budget exhaustion at 1,791 ms) | — |
| Full `/admin/verify` (`113` audit entries, `64` pages) | **141.8 ms** | — |

---

## 8. Milestone 6 Real-World Multi-Agent Workbench Simulation (2026-11-25)

Measured end-to-end against `examples/agent-workbench.mo` (`AgentWorkbench`, an 8-worker `mo serve` multi-agent engineering workbench with projects, budgets, tasks, artifacts, attenuated Grants, Claims, speculative Worlds, upgrade-aware Replay, and SHA-256 Export) via `python3 bench/real_world_agent_sim.py`:

| Phase / Scenario (`mo serve --workers 8`) | Wall Time / Latency | Key Empirical Result |
| --- | --- | --- |
| **Phase 1A** — Uncoordinated coarse-query swarm (`list_project_tasks`, 6W + 2R, 18 tasks) | **9.51 s** (`land p50 = 145.4 ms`, `p95 = 344.7 ms`; `618` reads `p50 = 28.0 ms`) | **`49` `StaleRead` retries**, **`7` `needless_send_backs`** (agents re-sent identical calls after false sibling-task conflicts) |
| **Phase 1B** — Fine-query + Claims swarm (`get_task`, 6W + 2R, 18 tasks) | **2.25 s** (`land p50 = 165.8 ms`, `p95 = 223.4 ms`; `127` reads `p50 = 27.8 ms`) | **`0` `StaleRead` retries**, **`0` `needless_send_backs`** (**4.2× faster** end-to-end under identical concurrency) |
| **Phase 2** — Rogue delegated sub-agent excision (`exclude_grant` Replay over `82` calls) | `sim = 589.4 ms`, `accept = 330.0 ms` | Parent revoke cascaded mid-flight (`403`); replay excised `2` rogue calls and unblocked **`2` `NowAccepted`** SRE tasks atomically |
| **Phase 3** — Retroactive 10%→0% overhead bug-fix Replay (`82` calls) | `sim = 690.9 ms`, `accept = 456.3 ms` | **`36` `ReplyChanged`** across all completed tasks + `2` `NowAccepted`; all 3 project budgets updated accurately |
| **Phase 3** — Portable SHA-256 `GET /admin/export` (`19` buckets, `916` entries) | **46.7 ms** (cured `1,321.7 ms` 500 budget exhaustion via `Export.encode_snapshot_json`) | Canonical RFC 8259 JSON snapshot verified (`format_version = 1`, 64-char SHA-256 digest) |
| **Post-`SIGKILL` recovery** (`GET /admin/verify` after hard OS kill + 8-worker restart) | **296.7 ms** | `ok = true`, `txid = 451`, `pages = 305`, `audit_entries = 137`; zero lost or corrupted state |

---

## 9. Post-`robertguss/mo#437` Native Rust JSON Speedups (2026-11-25)

Measured after installing `mo` with native RFC 8259 `Json.quote_raw` and `Json.parse_raw` (`robertguss/mo#437`, commit `893e9638`) into `~/.local/bin/mo`:

| Benchmark (`mo serve --workers 8` / `mo run`) | Before (`7d5186d1`) | After (`893e9638`) | Speedup |
| --- | ---: | ---: | --- |
| 422 KiB JSON render (`doc.to_text`, 200 entries + escapes + UTF-8) | `1,176 ms` | **`4 ms`** | **294× faster** |
| 422 KiB JSON parse (`Json.parse`) | `65 ms` | **`4 ms`** | **16× faster** |
| `ShopApi` Mixed 6R + 2W (`bench/bench_shop_api.py`) | `323.1 req/s` (`write p50 = 38.3 ms`) | **`333.6 req/s`** (`write p50 = 34.3 ms`) | **+3.3% req/s, -10% write p50** |
| `ShopApi` 111-call Replay Simulate (`bench/bench_shop_api.py`) | `716.3 ms` | **`259.7 ms`** | **2.8× faster** |
| `ShopApi` Full `/admin/verify` (`113` audit entries, `64` pages) | `141.8 ms` | **`71.3 ms`** | **2.0× faster** |
| `AgentWorkbench` Phase 1A Coarse Swarm (`18` tasks + `55` retries) | `9.51 s` (`p95 = 344.7 ms`) | **`4.59 s`** (`p95 = 178.0 ms`) | **2.1× faster** |
| `AgentWorkbench` Phase 1B Fine Swarm + Claims (`18` tasks, `0` retries) | `2.25 s` (`p95 = 223.4 ms`) | **`1.38 s`** (`p95 = 162.9 ms`) | **1.6× faster** |
| `AgentWorkbench` Phase 2 Rogue-Undo Replay (`82` calls) | `sim 589.4 ms`, `accept 330.0 ms` | **`sim 132.6 ms`, `accept 64.3 ms`** | **4.4× / 5.1× faster** |
| `AgentWorkbench` Phase 3 Bug-Fix Replay (`82` calls) | `sim 690.9 ms`, `accept 456.3 ms` | **`sim 183.2 ms`, `accept 116.1 ms`** | **3.8× / 3.9× faster** |
| `AgentWorkbench` Portable Export (`19` buckets, `922` entries) | `46.7 ms` (was `1,321.7 ms` 500) | **`31.6 ms`** | **1.5× faster** (**>41×** vs pre-fix) |
| `AgentWorkbench` Post-`SIGKILL` `/admin/verify` (`475` tx, `312` pages) | `296.7 ms` | **`157.3 ms`** | **1.9× faster** |

---

## 10. Milestone 8 & 9: Incremental Worlds, Views, Online Backup & Atomic Compaction (2026-11-26)

Measured on disk via pure-Rust `mo` (`4 KiB` synced B+Tree pages) after `398` audited Replay calls (`200` inserts, `150` deletes, `50` overwrites) and in the Milestone 8/9 verification suites:

| Operation / Benchmark | Scope / Workload | Observed Latency & Result |
| --- | --- | --- |
| `Ledger.verify_all` (cold full scan) | `398` audit entries, `110` B+Tree pages | **`245 ms`** |
| `Ledger.verify_fast(..., 100)` (`VerifyCheckpoint`) | Tail window check + invariant check (`398` entries) | **`9 ms`** (**27.2× faster** vs `verify_all`) |
| Online `Export.backup_db` (`include_internal: false`) | `txid = 400`, `50` live entries (`1` bucket) | **`22 ms`** |
| Atomic `Replay.compact_with_baseline_default` | `before_pages = 110`, `after_pages = 13` (**-88%** pages) | **`49 ms`** (`free: 14 → 3`, `audit: 398 → 0`, `baseline_pinned = true`, `checkpoint = true`) |
| `Views.execute_read_program_recorded` | `items_public` (`50` scanned, `25` returned, `_modb_read_log`) | **`17 ms`** |
| `Views.execute_release_recorded` (`k >= 5`) | Aggregate release over `cohort = 50` rows | **`23 ms`** |
| `World.land_world` (O(1) CoW read re-validation) | `9` scoped reads on `items` + concurrent unrelated `notes` commit | **`16 ms`** (`reads_verified = 9`, `reads_skipped = 9`) |
| `mo test tests/test-views-incremental.mo` | `5` tests (Views, Releases, `ReadLog`, O(1) World skip, negative control) | **`1,125.6 ms`** (`5 passed, 0 failed`) |
| `mo test tests/test-compact-backup.mo` | `4` tests (`backup_db`, `compact_db`, `compact_with_baseline` + delta replay, rollback) | **`6,259.6 ms`** (`4 passed, 0 failed`) |
| `tests/test_workbench_mcp_and_ui.py` (`AgentWorkbench` M7+M8 E2E) | `mo serve --workers 8`, `35` MCP tools, Inspector UI, `130` export entries | **PASS** (`reads_skipped = 1`, `txid = 32`, hash verified) |
