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

## 4. What These Numbers Tell Us (Including for a Future Rust Runtime)

1. **Bytecode interpretation + Perceus already clears the bar for real systems code:** ~10k point lookups/sec, ~8k writes/sec, 100k rows in 69.8 MiB RSS, and ~4 ms durable commits—with zero compiler changes and zero memory blowup.
2. **Where the 11×–21× gap to C SQLite lives:**
   - Tight bytecode loops in page serialization/deserialization (`encode_leaf`, `decode_leaf`, binary search slicing `Bytes`).
   - Full SHA-256 over every 4 KiB page (vs. SQLite's unchecksummed default / CRC32C).
   - 2× `fsync` per commit (CoW shadow paging) vs. SQLite WAL's 1× append `fsync`.
   - 50/50 split on sequential appends (leaves ~50% page fill = 16 MiB vs. SQLite's 7.2 MiB; right-edge 90/10 splitting would halve disk footprint and page writes).
3. **Implication for a future Rust runtime:** A clean safe-Rust bytecode VM (plus `rustls`) would give memory safety at roughly the same ~10–20×-of-C performance profile; closing the remaining gap to ~2–4× of C would require a JIT/native backend (e.g., Cranelift) rather than just porting the interpreter.
