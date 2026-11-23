# Mo Language Friction Log (MoDB Milestone 1)

Running ledger of every Mo compiler bug, VM/Perceus cliff, missing stdlib primitive, or ergonomics sharp edge hit while building MoDB Layer 1 and Layer 2 (`Modb` + `Modb.Table`) in pure Mo. Kept honest and specific so it informs both Mo improvements and the deferred Rust runtime decision.

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

### 8. Anonymous functions forbid *local* `var` bindings inside their own body (`E0090`)
- **Where:** `tests/test-table.mo`, `examples/shop.mo` (inside `Table.write_tx(db, fn(tx) ... end)` and `Table.transact(...)` callbacks)
- **What happened:** Reference 5.6 forbids anonymous functions from assigning captured outer `var`s, which protects value semantics. However, `error E0090: an anonymous function can't assign a var` also rejects `var` bindings declared *locally inside* the anonymous function itself (e.g. `var cur = tx; for k in keys ... cur = try Table.put(...)` or `var updated = prod; updated.stock -= qty`). We worked around this cleanly by constructing record values directly, extracting named helpers, and adding `Table.put_many` / `Table.delete_many` batch helpers. Allowing purely local `var` bindings inside anonymous functions (while still rejecting assignment to outer `var`s) would make callback-scoped transactions much more natural.
- **Severity:** Moderate ergonomics friction for callback-based APIs.

### 9. `E1150` when a top-level constant captures a function reading another module constant
- **Where:** `src/modb/table.mo` (`encode_int_key` / `decode_int_key`) triggered from `examples/shop.mo` (`customers = Table.int_key[Customer]("customers")`)
- **What happened:** `encode_int_key` originally wrote `n.wrapping_add(int64_min)` referencing the module constant `int64_min = -9223372036854775808`. Calling `Table.int_key` inside functions or `test` blocks compiled and ran fine, but declaring `customers = Table.int_key[Customer]("customers")` as a module-level schema constant in `examples/shop.mo` hit `error E1150: this constant's deferred function needs globals not yet initialized` because `KeyCodec` stores `encode_int_key` as a function value inside a constant. Inlining literal `-9223372036854775808` directly inside `encode_int_key` and `decode_int_key` eliminated the global read and let top-level declarative table/index constants work out of the box.
- **Severity:** Moderate compiler limitation (`E1150`) with a simple library-side workaround.

### 10. Bare `_ = expr` discard fails with misleading `E0010` (`assignment changes a var`)
- **Where:** `src/modb/table.mo` (`snapshot_scan`, `snapshot_range_by`)
- **What happened:** Writing `_ = try Modb.snapshot_scan(...)` to discard an `Ok` value after validating a snapshot fails with `error E0010: assignment changes a var or its fields`. `_` is valid in tuple destructuring (`(_, v) = ...`) and `for _ in ...`, whereas single-target `=` requires a named binding (`_probe = ...`) when not mutating a `var`. Either treating bare `_ = expr` as a discard binding or tailoring `E0010` to suggest `_unused = expr` would prevent confusion.
- **Severity:** Minor syntax/diagnostic papercut.

### 11. Single-letter type parameters, alphabetical `[...]` brackets, and heterogeneous index erasure
- **Where:** `src/modb/table.mo` (`Index(K, V, I)`, `text_index[Int, User]`, `IndexSpec(K, V)`)
- **What happened:**
  1. Only single capital letters (`K`, `V`, `I`) are type parameters in Mo (`IK` parses as a concrete type name), and explicit bracketed type arguments `[...]` are supplied in alphabetical order of the function's type parameters (`text_index[Int, User]` maps cleanly to `[K, V]`, whereas a function introducing `I`, `K`, `V` orders them `[I, K, V]`).
  2. Because Mo has no existential types or user-defined traits, a homogeneous `List` cannot hold `Index(Int, Account, Text)` alongside `Index(Int, Account, Int)` directly. Erasing `I` into a closure-backed `IndexSpec(K, V)` via `table.with_index(idx)` solved this cleanly in pure Mo while keeping `I` statically typed on `lookup`, `lookup_unique`, and `range_by`.
- **Severity:** Minor design constraint (cleanly solved with closure erasure).

### 12. `Bytes` lacks `Json`, and capability-backed `Store` removes `Equal` on `Result(Store, E)`
- **Where:** `tests/test-table.mo` (`BlobItem`, `assert Table.write_tx(...) is Error(...)`)
- **What happened:**
  1. Domain structs with a `Bytes` field (tags, digests, keys) cannot use automatic `Json` derivation (`E0080: type Bytes doesn't have Json`) and need a short custom `to_json` / `from_json` wrapper using `to_hex`/`from_hex` or `to_base64url`/`from_base64url`.
  2. Because `Modb.Store` wraps `Files.File` (a capability), `Result(Store, TableError)` does not implement `Equal`, so tests must match errors with `is Error(...)` rather than `== Error(...)`.
- **Severity:** Minor stdlib / testing ergonomics notes.

---

## What Worked Surprisingly Well

- **Zero compiler bugs or VM crashes across both Layer 1 and Layer 2.** Not a single ICE, segfault, wrong codegen, or memory corruption across ~2,700 lines of CoW B+Tree + binary codec + generic typed table/index code, 1,800+ differential ops, 500 simulated crashes, 100 real `SIGKILL` kills, and 200,000 row inserts/overwrites.
- **Perceus in-place reuse actually held under heavy nested-struct mutation!** Unlike the Nov 14 v0.2 sketch (which had to pack a tree into a bare `Map` to avoid $O(N)$ struct-field copies), `Allocator` (`dirty_leaves`, `dirty_branches`, `staged`, `reusable`, `pending_free`) and `BlockStore` (`cache`) lived inside ordinary `struct`s and ran 100,000 rows + 100,000 overwrites in **69.8 MiB peak RSS** with linear scaling.
- **PR #416 (`Files.File` + `Bytes` packing) worked flawlessly on the very first try.** Not a single bug in `read_at`, `write_at`, `size`, `sync`, `Files.in_memory`, or big-endian `u16`/`u32`/`i64` codecs—including surviving 100 real OS `SIGKILL` crashes mid-write/mid-fsync with zero lost acknowledged commits.
- **Capability discipline forced a cleaner crash-simulator design.** Because closures cannot capture capabilities in Mo, we modeled `enum Disk { Real(file: Files.File), Sim(...) }` as an explicit value instead of hidden closure callbacks—producing a cleaner, zero-overhead deterministic torn-write simulator that runs identically under `mo test`.
- **Automatic `Json` + `Decimal` + closure-captured codecs made Layer 2 feel remarkably native.** Ordinary Mo `struct` and `enum` types (including exact `Decimal` money and `Option` fields) worked in `examples/shop.mo` with zero annotations and without even importing `use Json` in caller modules. Capturing `Json.encode` and `Json.decode[V]` inside `Table(K, V)` at construction time kept all 25+ query/mutation functions free of viral `where V: Json` bounds, and single-variant `try` auto-wrapping (`ModbError -> TableError -> ShopError`) lifted errors across layers with almost zero boilerplate.
- **Value-typed `WriteTx` gave free statement-level savepoints.** Because `WriteTx` is an immutable Perceus value, returning `Error(UniqueConflict(...))` mid-transaction discards uncommitted index writes automatically without rollback logs.
- **Type inference & exhaustive choice checking caught real bugs at compile time** (`E0068` forcing explicit case arms, `E0093` catching unused imports, `E0044` keeping imports minimal).
