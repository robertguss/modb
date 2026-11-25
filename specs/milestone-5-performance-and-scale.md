# Milestone 5 Spec: Storage, Codec & Concurrency Performance Optimization

**Status:** Active implementation spec (Option 3, 2026-11-25)  
**Constraint:** Preserve **100% on-disk v1 format compatibility** (zero file format migration required)
and **100% crash-safety / verification parity** across all existing unit, differential, crash-sim,
live 8-worker HTTP `SIGKILL`, and 100× `kill_loop` gates.

## Baseline (Pure-Rust `mo` `7d5186d1`, 100,000 rows, 64B values, ext4)

| Metric | Baseline MoDB | SQLite (C) | Baseline Ratio |
| --- | ---: | ---: | ---: |
| Bulk load 100k rows (`100 × 1k` synced) | 15,848 ms | 664 ms | 23.9× |
| Full overwrite 100k rows (`100 × 1k` synced) | 15,099 ms | 676 ms | 22.3× |
| `Modb.verify` (100k rows, cold SHA-256) | 1,290 ms | — | — |
| Warm point `get` (1,000×) | 138 ms | 8 ms | 17.3× |
| Cold point `get` (1,000×, empty cache) | 166 ms | — | — |
| 100-row range `scan` (100×) | 203 ms | 6 ms | 33.8× |
| Single-row synced `write_tx` (100×) | 442 ms | 75 ms | 5.9× |
| File size on disk (after overwrites) | 15.7 MiB (`3,933` pages) | 7.2 MiB | 2.2× |

## Targeted Pure-Mo Optimizations

1. **O(1) tracked node byte sizes (`DirtyLeaf` / `DirtyBranch`):**
   Eliminate O(M²) `leaf_body_size` / `branch_body_size` full-list rescans on every `put`, `delete`,
   and `maybe_merge_child`. Compute `body_bytes` during decode in a single pass.
2. **Right-edge sequential split (`98%` leaf / `90%` branch fill) + O(1) right-edge probe:**
   When inserting strictly past the last key of a leaf or branch (monotonic keys, `audit_seq`,
   `call_seq`, bulk loads), skip binary search in O(1) and split at the right edge instead of 50/50.
   Halves page count (~15.7 MiB → ~8.3 MiB), halves leaf splits, halves SHA-256 seals on load &
   overwrite, and doubles scan density while preserving classic 50/50 splits for random keys.
3. **Single-pass zero-copy page sealing (`seal_parts`):**
   Eliminate per-cell `Bytes.join` calls and 3 redundant 4 KiB page buffer copies inside
   `encode_leaf` / `encode_branch` / `seal_page`, packing `(vkind, klen)` and `(kind, count)` into
   single `u32_be` writes.
4. **Inlined hot binary-search reads & duplicate header-check elimination:**
   Remove the dead `Bool` tuple from `Tree.read_node_page`, inline `u16_be_at`/`i64_be_at` inside
   `branch_lookup_child_raw` and `leaf_lookup_entry_raw`, and dispatch directly on page `kind`
   without redundant `read_header_fast` / `PageHeader` allocations.
5. **Zero-decode raw branch & leaf range scans (`branch_scan_children_raw`, `leaf_scan_raw`):**
   Binary-search `start_key` directly in raw page bytes via `compare_slice_at`, returning only
   matching child page IDs (instead of decoding ~200 `BranchEntry` structs per branch) and slicing
   only entries inside `[start_key, end_key)` up to `limit`.
6. **Zero-value-allocation raw leaf verification (`verify_leaf_raw`):**
   Check slot offsets, strict key order, branch key bounds, and overflow references directly on raw
   bytes during `Modb.verify`, avoiding 100,000+ `LeafEntry` and inline value slice allocations
   (directly shrinking `/admin/verify` `LOCK_SH` hold times under multi-worker `mo serve`).
7. **Multi-worker `ShopApi` concurrency benchmark (`bench/bench_shop_api.py`):**
   Measure real 8-worker HTTP read/write throughput and latency under `mo serve --workers 8`.
