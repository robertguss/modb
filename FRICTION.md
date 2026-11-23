# Mo Language Friction Log (MoDB Milestone 1)

Running ledger of every Mo compiler bug, VM/Perceus cliff, missing stdlib primitive, or ergonomics sharp edge hit while building MoDB Layer 1 in pure Mo (~1,600 lines of storage-engine code + tests/benchmarks). Kept honest and specific so it informs both Mo improvements and the deferred Rust runtime decision.

---

## Friction & Papercuts Hit

### 1. `Bytes.empty?` missing (stdlib inconsistency)
- **Where:** `src/modb.mo` (`prefix_scan`)
- **What happened:** `Text`, `List`, `Map`, and `Set` all expose `.empty?`, but `Bytes` only has `.size` (must write `bytes.size == 0`).
- **Severity:** Minor stdlib consistency papercut.

### 2. Confusing diagnostic when using `or` on `Result(T, E)`
- **Where:** Tests across `pager.mo`, `codec.mo`, `tree.mo`, `modb.mo`
- **What happened:** Writing `res or stop "failed"` on a `Result` emits `error E0074: a condition isn't a yes-or-no answer — expected Bool, found Result(...)` because `or` falls back to boolean OR whenever the LHS is not `Option(T)`. Either supporting `Result` fallback in `or` or emitting a targeted diagnostic (`or` unwraps `Option`, not `Result`; use `try`, `case`, or `assert ... is Ok(v)`) would save time.
- **Severity:** Moderate DX / diagnostic clarity.

### 3. `return` is not allowed inside `or` or single-line `if: ... else:`
- **Where:** `src/modb/codec.mo` (`leaf_lookup_entry`), `src/modb.mo` (`buckets`), `bench/kill-writer.mo` (`main`)
- **What happened:** `x = opt or return Error(...)` is a parse error (`E0007: a value is an expression`). You must expand each check into a 4-line `case opt / Some(v): v / None: return Error(...) / end` block (or convert via `.or_fail(...)` + `try`). Making `return` / `break` / `continue` diverging expressions (like Rust) or advertising `.or_fail` in the diagnostic would cut boilerplate sharply in systems code.
- **Severity:** Moderate ergonomics friction (hit ~8 times across ~1,600 lines).

### 4. `var` bindings cannot carry optional type annotations
- **Where:** `codec.mo`, `tree.mo`, `modb.mo`
- **What happened:** `var entries: List(LeafEntry) = []` fails to parse (`E0007: expected =, found :`). Local type inference did infer every single empty `[]`, `{}`, and `None` cleanly once used later, so this never blocked us—just surprised muscle memory.
- **Severity:** Minor ergonomics note.

### 5. `Files.File` / binary page encoding allocates per-field `Bytes` chunks
- **Where:** `src/modb/codec.mo` (`encode_leaf`, `encode_branch`, `leaf_lookup_entry`)
- **What happened:** Building a 4 KiB page constructs a `List(Bytes)` of small 2–8 byte pieces (`Bytes.from_u16_be`, `Bytes.from_i64_be`, slices) and flattens them with `Bytes.join`. On reads, comparing a key inside a 4 KiB page allocates a fresh `raw.slice(start, end)` copy per binary-search probe because `Bytes` has no slice comparison (`bytes.compare_slice_at(offset, len, other)`) or mutable `BytesBuilder`.
- **Impact:** Measurable—part of the 11×–21× gap vs C SQLite. Not a blocker for 100k rows (~10k gets/s, ~8k writes/s), and easy to optimize later with 2–3 `Bytes` primitives if binary workloads become a priority.
- **Severity:** Performance opportunity (non-blocking).

### 6. No `Result.unwrap` / `or` ergonomic bridge in `main` for mixed error types
- **Where:** `bench/bench-modb.mo`, `bench/kill-writer.mo`
- **What happened:** Combining `ModbError`, `FileError`, and `SqliteError` in one `Result(Unit, Text)` function required verbose `case ... Ok(v): v / Error(e): return Error(...) end` blocks (or explicit `.map_error(...)` wrappers). Works cleanly with `try res.map_error(...)`, just slightly noisy in CLI scripts.
- **Severity:** Minor ergonomics note.

### 7. `E0035` filename-to-module rule requires hyphen-case (`test-modb.mo`), not snake_case
- **Where:** `tests/test-modb.mo`, `bench/bench-modb.mo`, `bench/kill-writer.mo`
- **What happened:** Initially created `test_modb.mo` (`module TestModb`); `mo check` immediately gave an exact fix (`test-modb.mo`). Good, consistent convention—worth keeping in mind when scaffolding new projects.
- **Severity:** Non-issue (diagnostic was crystal clear).

---

## What Worked Surprisingly Well

- **Zero compiler bugs or VM crashes across the entire build.** Not a single ICE, segfault, wrong codegen, or memory corruption across ~1,600 lines of non-trivial CoW B+Tree + binary codec + crash-recovery code, 1,200 differential ops, 500 simulated crashes, 100 real `SIGKILL` kills, and 200,000 row inserts/overwrites.
- **Perceus in-place reuse actually held under heavy nested-struct mutation!** Unlike the Nov 14 v0.2 sketch (which had to pack a tree into a bare `Map` to avoid $O(N)$ struct-field copies), `Allocator` (`dirty_leaves`, `dirty_branches`, `staged`, `reusable`, `pending_free`) and `BlockStore` (`cache`) lived inside ordinary `struct`s and ran 100,000 rows + 100,000 overwrites in **69.8 MiB peak RSS** with linear scaling.
- **PR #416 (`Files.File` + `Bytes` packing) worked flawlessly on the very first try.** Not a single bug in `read_at`, `write_at`, `size`, `sync`, `Files.in_memory`, or big-endian `u16`/`u32`/`i64` codecs—including surviving 100 real OS `SIGKILL` crashes mid-write/mid-fsync with zero lost acknowledged commits.
- **Capability discipline forced a cleaner crash-simulator design.** Because closures cannot capture capabilities in Mo, we modeled `enum Disk { Real(file: Files.File), Sim(...) }` as an explicit value instead of hidden closure callbacks—producing a cleaner, zero-overhead deterministic torn-write simulator that runs identically under `mo test`.
- **Type inference & exhaustive choice checking caught real bugs at compile time** (`E0068` forcing explicit case arms, `E0093` catching unused imports, `E0044` keeping imports minimal).
