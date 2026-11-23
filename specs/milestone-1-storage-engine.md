# MoDB Milestone 1: Pure-Mo Copy-on-Write B+Tree Storage Engine

**Status:** Approved direction (2026-11-23). Replaces the paused Nov 14 wayfinder plan as the active build track.

## 1. Purpose

Build a real, crash-safe, disk-backed embedded storage engine in **pure Mo** as a driver project to stress-test Mo's binary I/O, binary encoding, VM throughput, Perceus in-place reuse, and deterministic fault-injection testing.

- **Non-goals for Milestone 1:** Replacing PostgreSQL or SQLite in production; SQL or a custom query planner; multi-agent worlds/replay ([design.md](../design.md) §6 stays parked); rewriting Mo's runtime in Rust (deferred until Milestone 1's benchmarks and friction log tell us whether a Rust runtime should be a bytecode VM or a JIT/native backend).
- **Mo rule:** Mo gains only minimal, general-purpose `Files` and `Bytes` primitives specified in [mo-pr-files-and-bytes.md](mo-pr-files-and-bytes.md). No database-specific syntax or runtime hooks.

## 2. Two-Layer Architecture

1. **Layer 1 — Ordered KV Engine (`Bytes -> Bytes`):** Single-file 4 KiB paged Copy-on-Write (CoW) B+Tree with dual checksummed meta-pages, named buckets, atomic `read_tx`/`write_tx`, O(1) snapshots, prefix/range scans, and freelist page reclamation.
2. **Layer 2 — Typed Mo Tables & Secondary Indexes (built right after Layer 1 passes all gates):** Thin pure-Mo wrapper using Mo's `Json` ability for values, big-endian order-preserving codecs for `Int`/`Text` keys, and secondary indexes updated atomically inside the same `write_tx`.

## 3. On-Disk Format (Layer 1)

One file divided into fixed **4,096-byte pages** (`page_id: Int`, byte offset `page_id * 4096`). All multi-byte integers are **big-endian**. Every page carries a checksum verified on read.

### 3.1 Dual Meta-Pages (Pages 0 and 1)

Two alternating superblocks eliminate the need for a separate WAL. Commit `txid` writes to meta-page `txid % 2` (`0` for even, `1` for odd). On open, MoDB reads both Page 0 and Page 1, verifies each page's magic and SHA-256 digest, and picks the valid one with the higher `txid`.

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0 | 8 | `magic` | ASCII `"MODB0001"` |
| 8 | 4 | `format_version` | `1` |
| 12 | 4 | `page_size` | `4096` |
| 16 | 8 | `txid` | Monotonic commit counter (`>= 1`) |
| 24 | 8 | `catalog_root` | Page ID of root B+Tree mapping `bucket_name -> bucket_root_page_id` (`0` = empty) |
| 32 | 8 | `freelist_root` | Page ID of head page of persisted freelist (`0` = none) |
| 40 | 8 | `page_count` | Total allocated pages in file (`>= 2`) |
| 48 | 32 | `checksum` | `Crypto.sha256(bytes[0..48])` |
| 80 | 4016 | `reserved` | Zero-filled |

### 3.2 Common Page Header (Pages >= 2, 48 bytes)

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0 | 2 | `kind` | `1` = Branch, `2` = Leaf, `3` = Overflow, `4` = Freelist |
| 2 | 2 | `entry_count` | Number of keys/cells (or page IDs for Freelist) |
| 4 | 4 | `flags` | Reserved (`0`) |
| 8 | 8 | `page_id` | Self page ID (detects misdirected writes) |
| 16 | 32 | `checksum` | `Crypto.sha256(bytes[0..16] ++ bytes[48..4096])` |

### 3.3 Page Kinds

- **Branch (`kind = 1`):** `entry_count` sorted separator keys + `entry_count + 1` child page IDs (leftmost child `c0`, then pairs `(sep_key_i, c_{i+1})`). Fixed slot offset table after the 48-byte header pointing to variable-length key payloads packed from the end of the page (slotted-page layout).
- **Leaf (`kind = 2`):** `entry_count` sorted `(key, value_ref)` entries using the same slotted-page layout.
  - Inline values up to **1,024 bytes** live directly in the leaf cell (`inline_flag = 0`).
  - Values larger than **1,024 bytes** live in a linked chain of **Overflow (`kind = 3`)** pages (`next_page_id: 8B`, `chunk_len: 4B`, `payload` up to `4036B`), referenced from the leaf by `(first_overflow_page_id: 8B, total_len: 8B)`.
  - Max key size in Milestone 1: **512 bytes** (guarantees at least 4 keys fit in any branch/leaf page so B+Tree splits always succeed).
- **Freelist (`kind = 4`):** Linked list of pages (`next_page_id: 8B`, followed by up to `505` free `page_id`s per page).

## 4. Transactions, Snapshots, and Crash Safety

### 4.1 Atomic Commit Order

Inside `write_tx`:

1. Every modified B+Tree node is written to a **fresh page ID** (allocated from reusable freelist pages or by extending `page_count`). Committed pages are **never overwritten** in place.
2. Old replaced page IDs are recorded in a pending-free list tagged with `txid`.
3. Write all newly allocated pages (data, overflow, branch, updated freelist) via `File.write_at`.
4. Call **`File.sync`** — guarantees every page reachable from the new root is durable before the root flips.
5. Write the new meta-page to slot `new_txid % 2` via `File.write_at`.
6. Call **`File.sync`** — commits the transaction atomically.

**Crash invariant:** If power fails or the process is killed (`kill -9`) at *any* point:
- Before step 5: both meta-pages still point to `txid` and `txid - 1`; newly written unreferenced pages are harmless dead space reclaimed/overwritten on subsequent runs.
- During step 5 (torn meta-page): the active slot's SHA-256 fails verification; recovery falls back to the intact previous meta-page (`txid`).
- After step 6: the new meta-page (`txid + 1`) passes verification and all of its reachable pages were already synced in step 4.

### 4.2 Snapshots & Deferred Page Reclamation (Freelist Safety)

Because meta-page `txid - 1` must remain valid until meta-page `txid` is safely on disk—and because open `Snapshot`s / `read_tx`s pin older roots—pages freed during commit `T` may **only** be reused once:

1. `T < current_txid` (so the previous meta-page `current_txid - 1` no longer references them), **and**
2. No open `Snapshot` has `snapshot.txid <= T`.

When no snapshots are open, pages freed at commit `T` become reusable starting at commit `T + 2`.

## 5. Pure-Mo Package & API Sketch

`modb` becomes a standard `mo.toml` package (`src/` modules) usable via path dependency.

### 5.1 Pager Seam (Enables Deterministic Fault Simulation)

Layer 1 talks to storage through a tiny explicit `BlockStore` record of closures (or real-file vs. fault-sim enum) with 5 operations: `read_page`, `write_page`, `sync`, `page_count`, `truncate`.
- **Production adapter:** wraps Mo's `Files.File` handle (`read_at`/`write_at`/`sync`/`size`/`truncate`).
- **Deterministic crash-fault adapter (`mo test`):** holds a `durable: Map(Int, Bytes)` disk image and a `pending: Map(Int, Bytes)` unsynced buffer. On simulated `crash(seed)`, randomly drops subsets of `pending`, applies partial/torn byte prefixes of pages, reorders unsynced pages, and reopens the DB from scratch to verify zero corruption and exact atomic rollback/commit.

### 5.2 Layer 1 API (`Modb`)

```mo
db = try Modb.open(files, "data.modb")

## Atomic write transaction (rolls back cleanly on Error)
db = try db.write_tx(fn(tx)
  tx = try tx.put("users", key_bytes, val_bytes)
  tx = try tx.delete("users", old_key)
  Ok(tx)
end)

## Point lookup & ordered range scan
val = try db.get("users", key_bytes)                  # Option(Bytes)
rows = try db.scan("users", start_key, end_key, 100)  # List((Bytes, Bytes))

## O(1) immutable snapshot (pins root page ID until released)
(db, snap) = db.snapshot
old_val = try snap.get("users", key_bytes)
db = db.release_snapshot(snap)
```

### 5.3 Layer 2 API (`Modb.Table` — Built After Layer 1 Passes)

```mo
users = Table.int_key[User]("users")
by_email = Table.text_index[Int, User]("users_by_email", fn(u) u.email end)

db = try db.write_tx(fn(tx)
  Table.put_indexed(tx, users, [by_email], 42, User(email: "ada@ex.org", name: "Ada"))
end)

user = try Table.get(db, users, 42)                         # Option(User)
matches = try Table.lookup(db, users, by_email, "ada@ex.org") # List((Int, User))
```

*(Exact ergonomics—e.g. method chaining vs. module functions, error types, and multi-index helpers—will be refined directly against Mo's type checker while building Layer 2.)*

## 6. Milestone 1 Verification Gates & Deliverables

Layer 1 is done only when every gate below passes on a release (`-O2`) build of `mo`:

1. **Differential correctness (`mo test`):** 1,000+ seeded random sequences of `put`, `delete`, `get`, `scan`, `snapshot`, and multi-op `write_tx` (including forced aborts and large >1 KiB overflow values) match a reference in-memory sorted `Map` byte-for-byte.
2. **Deterministic crash simulation (`mo test`):** 500+ seeded crash injections (dropped unsynced pages, reordered writes, torn mid-page writes, torn meta-page writes, corrupted checksum bit-flips) recover cleanly to either `txid` or `txid - 1` with every committed key intact.
3. **Real OS `kill -9` loop:** A driver spawns a writer doing real synced commits on disk and kills it with `SIGKILL` at random intervals (100+ kills), reopening and verifying full tree integrity and exact monotonic prefix of committed transactions.
4. **Scale & freelist stability:** Load **100,000 rows** (64-byte values), then run **100,000 overwrites**; verify file size stabilizes rather than growing monotonically.
5. **Head-to-head benchmark vs. Mo's `Sqlite`:** On the same machine and disk (`synchronous=FULL` / `EXTRA`), measure and record:
   - Point `get` (cold cache & warm cache) at 1k, 10k, 100k rows.
   - 100-row range `scan` at 100k rows.
   - Single-row synced `write_tx` and 1,000-row batched `write_tx`.
   - File size and RSS memory.
6. **Language Friction Log (`FRICTION.md`):** Running ledger of every Mo compiler bug, VM/Perceus cliff, missing stdlib primitive, or ergonomics sharp edge discovered while writing real systems code in Mo—used afterward to inform both Mo improvements and the deferred Rust runtime decision.
