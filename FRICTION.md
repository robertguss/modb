# Mo Language Friction Log (MoDB Milestone 1)

Running ledger of every Mo compiler bug, VM/Perceus cliff, missing stdlib primitive, or ergonomics sharp edge hit while building MoDB Layer 1 and Layer 2 (`Modb` + `Modb.Table`) in pure Mo. Kept honest and specific so it informs both Mo improvements and the deferred Rust runtime decision.

---

## Friction & Papercuts Hit

### 1. ~~`Bytes.empty?` missing (stdlib inconsistency)~~ — Fixed in [robertguss/mo#417](https://github.com/robertguss/mo/pull/417)
- **Where:** `src/modb.mo` (`prefix_scan`)
- **What happened:** `Text`, `List`, `Map`, and `Set` all exposed `.empty?`, while `Bytes` only had `.size`.
- **Resolution:** Added `Bytes.empty?` (`fn(Bytes) : Bool`) in PR #417; adopted in `src/modb.mo` (`prefix.empty?`).

### 2. ~~Confusing diagnostic when using `or` on `Result(T, E)`~~ — Fixed in [robertguss/mo#417](https://github.com/robertguss/mo/pull/417)
- **Where:** Tests across `pager.mo`, `codec.mo`, `tree.mo`, `modb.mo`
- **What happened:** Writing `res or stop "failed"` on a `Result` emitted `error E0074: a condition isn't a yes-or-no answer — expected Bool, found Result(...)`.
- **Resolution:** PR #417 kept `or` semantics and `E0074` unchanged while emitting a targeted message (`"or unwraps Option or combines Bool, not Result"`) with help suggesting `try`, `case`, or `assert ... is Ok(v)`.

### 3. `return` is not allowed inside `or` or single-line `if: ... else:`
- **Where:** `src/modb/codec.mo` (`leaf_lookup_entry`), `src/modb.mo` (`buckets`), `bench/kill-writer.mo` (`main`)
- **What happened:** `x = opt or return Error(...)` is a parse error (`E0007: a value is an expression`). You must expand each check into a 4-line `case opt / Some(v): v / None: return Error(...) / end` block (or convert via `.or_fail(...)` + `try`). Making `return` / `break` / `continue` diverging expressions (like Rust) or advertising `.or_fail` in the diagnostic would cut boilerplate sharply in systems code.
- **Severity:** Moderate ergonomics friction (hit ~8 times across ~1,600 lines).

### 4. `var` bindings cannot carry optional type annotations
- **Where:** `codec.mo`, `tree.mo`, `modb.mo`
- **What happened:** `var entries: List(LeafEntry) = []` fails to parse (`E0007: expected =, found :`). Local type inference did infer every single empty `[]`, `{}`, and `None` cleanly once used later, so this never blocked us—just surprised muscle memory.
- **Severity:** Minor ergonomics note.

### 5. `Files.File` / binary page encoding allocates per-field `Bytes` chunks *(read-side addressed in [robertguss/mo#417](https://github.com/robertguss/mo/pull/417))*
- **Where:** `src/modb/codec.mo` (`encode_leaf`, `encode_branch`, `branch_lookup_child_with_header`, `leaf_lookup_entry_with_header`)
- **What happened:** Building a 4 KiB page constructs a `List(Bytes)` of small 2–8 byte pieces (`Bytes.from_u16_be`, `Bytes.from_i64_be`, slices) and flattens them with `Bytes.join`. On reads, comparing a key inside a 4 KiB page previously allocated a fresh `raw.slice(start, end)` per binary-search probe.
- **PR #417 update:** Adopted `Bytes.compare_slice_at` across `decode_meta`, `verify_header`, `branch_lookup_child_with_header`, and `leaf_lookup_entry_with_header`, eliminating all per-probe `Bytes.slice` allocations and avoiding re-slicing keys on leaf hits. Controlled A/B benchmarks (see [BENCHMARKS.md](BENCHMARKS.md)) showed a modest **~8–15% warm-`get` gain** on 8-byte keys (and revealed that nested `case` matching `Some(Equal)/Some(Greater)/Some(Less)` costs ~12–16% vs splitting `Some(ord)` and placing `Less`/`Greater` first). The bigger lesson: Perceus makes short-lived `Bytes.slice` very cheap, while **bytecode dispatch + ~60 per-`get` Mo helper calls (`read_u16`/`read_i64`)** dominate the remaining ~11–20× gap to C SQLite. Write-side `BytesBuilder` packing remains open if needed later.
- **Severity:** Performance insight (non-blocking).

### 6. No `Result.unwrap` / `or` ergonomic bridge in `main` for mixed error types
- **Where:** `bench/bench-modb.mo`, `bench/kill-writer.mo`
- **What happened:** Combining `ModbError`, `FileError`, and `SqliteError` in one `Result(Unit, Text)` function required verbose `case ... Ok(v): v / Error(e): return Error(...) end` blocks (or explicit `.map_error(...)` wrappers). Works cleanly with `try res.map_error(...)`, just slightly noisy in CLI scripts.
- **Severity:** Minor ergonomics note.

### 7. `E0035` filename-to-module rule requires hyphen-case (`test-modb.mo`), not snake_case
- **Where:** `tests/test-modb.mo`, `bench/bench-modb.mo`, `bench/kill-writer.mo`
- **What happened:** Initially created `test_modb.mo` (`module TestModb`); `mo check` immediately gave an exact fix (`test-modb.mo`). Good, consistent convention—worth keeping in mind when scaffolding new projects.
- **Severity:** Non-issue (diagnostic was crystal clear).

### 8. ~~Anonymous functions forbid *local* `var` bindings inside their own body (`E0090`)~~ — Fixed in [robertguss/mo#417](https://github.com/robertguss/mo/pull/417)
- **Where:** `tests/test-table.mo`, `examples/shop.mo` (inside `Table.write_tx(db, fn(tx) ... end)` and `Table.transact(...)` callbacks)
- **What happened:** `E0090` rejected `var` declarations and mutations even when declared *locally inside* an anonymous function, forcing manual record reconstruction and extracted helper functions (`apply_batch_ops`).
- **Resolution:** PR #417 allows local `var` bindings, loops, and field updates inside anonymous functions while keeping `E0090` (`"an anonymous function can't assign an outer var"`) for outer `var` writes and preserving `E0092` capture safety. Adopted in `examples/shop.mo` (`place_order`, `mark_shipped`) and `tests/test-table.mo` (inlined the `apply_batch_ops` loop directly into `Table.write_tx`).

### 9. `E1150` when a top-level constant captures a function reading another module constant
- **Where:** `src/modb/table.mo` (`encode_int_key` / `decode_int_key`) triggered from `examples/shop.mo` (`customers = Table.int_key[Customer]("customers")`)
- **What happened:** `encode_int_key` originally wrote `n.wrapping_add(int64_min)` referencing the module constant `int64_min = -9223372036854775808`. Calling `Table.int_key` inside functions or `test` blocks compiled and ran fine, but declaring `customers = Table.int_key[Customer]("customers")` as a module-level schema constant in `examples/shop.mo` hit `error E1150: this constant's deferred function needs globals not yet initialized` because `KeyCodec` stores `encode_int_key` as a function value inside a constant. Inlining literal `-9223372036854775808` directly inside `encode_int_key` and `decode_int_key` eliminated the global read and let top-level declarative table/index constants work out of the box.
- **Severity:** Moderate compiler limitation (`E1150`) with a simple library-side workaround.

### 10. ~~Bare `_ = expr` discard fails with misleading `E0010` (`assignment changes a var`)~~ — Fixed in [robertguss/mo#417](https://github.com/robertguss/mo/pull/417)
- **Where:** `src/modb/table.mo` (`snapshot_scan`, `snapshot_range_by`), `src/modb/tree.mo` (`read_node_page`)
- **What happened:** Writing `_ = try Modb.snapshot_scan(...)` failed with `E0010`, requiring dummy names like `_probe` and `_hdr`.
- **Resolution:** PR #417 enabled bare `_ = expr` discard bindings (evaluating once and preserving `E0412` on unhandled `Result`). Adopted across `src/modb/table.mo` and `src/modb/tree.mo`.

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

### 13. ~~`actor` is a hard keyword in struct fields, parameters, and `api` query parameters (`E0013` / cascading `E0007`)~~ — Fixed in [robertguss/mo#436](https://github.com/robertguss/mo/pull/436)
- **Where:** `src/modb/ledger.mo` (`WriteMeta`, `AuditEntry`), `examples/shop-api.mo` (`Caller`, `get_audit`)
- **What happened:** Naming a field or parameter `actor: Text` (a standard audit-log / RBAC domain word) failed with `E0013: expected snake_case name, found actor`, and parser error recovery mis-synchronized into `actor` block parsing and flooded dozens of cascading `E0007` diagnostics.
- **Resolution:** PR #436 kept `actor` reserved (preserving zero-conflict `grammar/mo.y`) and added clean in-place parser recovery in struct fields, enum named fields, and function parameter lists so reserved-keyword misuse emits one crisp diagnostic with zero `E0007` cascade.

### 14. Struct field names shadow UFCS builder functions of the same name (`E0072`)
- **Where:** `src/modb/ledger.mo` (`Schema.require_reason` vs `fn require_reason(sc: Schema, required?: Bool)`)
- **What happened:** Calling `schema(1).require_reason(true)` resolved `.require_reason` to the `Bool` struct field rather than the UFCS function (`E0072: expected fn, found Bool`). Resolved cleanly by naming all fluent builders `with_*` (`with_require_reason`, `with_migration`, `with_invariant`).
- **Severity:** Minor convention note.

### 15. ~~CLI directory flag inconsistency (`--root` / `--state-dir` vs `--data`) and missing subcommand `--help`~~ — Fixed in [robertguss/mo#436](https://github.com/robertguss/mo/pull/436)
- **Where:** `tests/test_shop_api_live.py`, `mo serve` vs `mo run`
- **What happened:** `mo run` accepted `--root` and `--state-dir`, whereas `mo serve` required `--data` and rejected `--root`, `--state-dir`, and `--help` (`unknown flag: "--help"`).
- **Resolution:** PR #436 added top-level and per-subcommand `--help` / `-h` (derived from `FLAGS_TABLE`, exiting `0`) and a concise `(hint: mo serve uses --data DIR)` hint when `--root` or `--state-dir` is passed to `mo serve`.

### 16. ~~Multi-worker `mo serve` concurrency gap for pure-Mo file-backed stores~~ — Fixed in [robertguss/mo#436](https://github.com/robertguss/mo/pull/436)
- **Where:** `examples/shop-api.mo` under `mo serve` (`~/code/mo/crates/mo-service/src/api_server.rs`, `crates/mo-def/defs/hostops.def`)
- **What happened:** `mo serve` defaults to 8 concurrent HTTP worker threads, each receiving an isolated `Files` capability per request. Without advisory file locking (`Files.File.lock_shared` / `lock_exclusive` / `unlock`) or read-only random-access handles (`ReadFiles.open`), Phase 2A had to run `mo serve --workers 1`.
- **Resolution:** PR #436 added safe BSD `flock` advisory locks (`File.lock_shared`, `File.lock_exclusive`, `File.unlock` via `rustix::fs::flock` with auto-unlock on drop and `Files.in_memory` parity) plus host-attenuated `ReadFiles.open` (and `ApiTest.send` `ReadFiles` derivation from supplied `Files`). Adopted across `src/modb.mo`, `src/modb/ledger.mo`, `examples/shop-api.mo`, and verified under `mo serve --workers 8` with an 8-thread concurrent HTTP + mid-flight `SIGKILL` stress test in `tests/test_shop_api_live.py`.

### 17. ~~BSD `flock` `LOCK_SH` reader starvation of `LOCK_EX` writers under continuous heavy reads & per-request VM instruction budget~~ — Resolved in Milestone 5
- **Where:** `src/modb.mo` (`with_shared_lock`), `src/modb/ledger.mo` (`row_invariant`), `src/modb/replay.mo` (`preview_replay`), `examples/shop-api.mo`
- **What happened:**
  1. Under Linux BSD `flock`, 4–6 tight-loop HTTP reader threads overlapping `LOCK_SH` continuously renewed shared ownership and starved pending `LOCK_EX` writers.
  2. Replaying ~100 calls inside one HTTP request hit `bug: internal error: instruction budget exhausted` (~1.8 s), first from per-call `Modb.commit` page sealing and then from O(N²) full-table `row_invariant` / `order_referential_integrity` scans.
- **Resolution:**
  1. Upgraded `Modb.with_shared_lock` to lock-free optimistic CoW snapshot reads (verified by `start_txid == end_txid` on alternating SHA-256 meta-pages, since pages live at `txid` are immutable until commit `txid + 2`, with `lock_shared` fallback under continuous write storms). Verified with 6 tight-loop readers + 2 writers in `bench/bench_shop_api.py` (**323.1 req/s**, zero writer starvation) and unthrottled Wave 3 `/admin/verify` readers in `tests/test_shop_api_live.py`.
  2. Switched `Replay.preview_replay` to a single pure in-memory `WriteTx` with O(1) immutable rollback, and added `Modb.begin_write_tracked` + O(touched) incremental invariant checks in `Ledger.row_invariant` and `ShopApi.order_referential_integrity`, cutting 111-call HTTP replay simulation from 1,791 ms (budget exhaustion) down to **716.3 ms**.

---

## What Worked Surprisingly Well

- **Zero compiler bugs or VM crashes across Layers 1, 2, and 3 (now running on pure-Rust `mo` #433).** Not a single ICE, panic, wrong codegen, or memory corruption across ~3,500+ lines of CoW B+Tree + binary codec + generic typed tables + hash-chained audit ledger + declarative `api` server, 1,800+ differential ops, 1,000 simulated crashes (500 Layer 1 + 500 Layer 3), 100 real `SIGKILL` kills, live `mo serve` `SIGKILL` recovery, and 200,000 row inserts/overwrites.
- **Zero-socket `ApiTest.send` ran the full `ShopApi` server identically against `Files.in_memory({})` and `Clock.fixed(...)`.** Auth, RBAC, mandatory `X-Reason` accountability, schema migrations, commit-time invariant rollbacks, secondary-index queries, hash-chained audit queries, `/admin/verify`, and `/docs` all tested in milliseconds in memory, and the exact same file served live HTTP traffic under `mo serve --workers 1` and survived a hard `SIGKILL` with zero lost state.
- **Perceus in-place reuse actually held under heavy nested-struct mutation!** Unlike the Nov 14 v0.2 sketch (which had to pack a tree into a bare `Map` to avoid $O(N)$ struct-field copies), `Allocator` (`dirty_leaves`, `dirty_branches`, `staged`, `reusable`, `pending_free`) and `BlockStore` (`cache`) lived inside ordinary `struct`s and ran 100,000 rows + 100,000 overwrites in **69.8 MiB peak RSS** with linear scaling.
- **PR #416 (`Files.File` + `Bytes` packing) worked flawlessly on the very first try.** Not a single bug in `read_at`, `write_at`, `size`, `sync`, `Files.in_memory`, or big-endian `u16`/`u32`/`i64` codecs—including surviving 100 real OS `SIGKILL` crashes mid-write/mid-fsync with zero lost acknowledged commits.
- **Capability discipline forced a cleaner crash-simulator design.** Because closures cannot capture capabilities in Mo, we modeled `enum Disk { Real(file: Files.File), Sim(...) }` as an explicit value instead of hidden closure callbacks—producing a cleaner, zero-overhead deterministic torn-write simulator that runs identically under `mo test`.
- **Automatic `Json` + `Decimal` + closure-captured codecs made Layer 2 feel remarkably native.** Ordinary Mo `struct` and `enum` types (including exact `Decimal` money and `Option` fields) worked in `examples/shop.mo` with zero annotations and without even importing `use Json` in caller modules. Capturing `Json.encode` and `Json.decode[V]` inside `Table(K, V)` at construction time kept all 25+ query/mutation functions free of viral `where V: Json` bounds, and single-variant `try` auto-wrapping (`ModbError -> TableError -> ShopError`) lifted errors across layers with almost zero boilerplate.
- **Value-typed `WriteTx` gave free statement-level savepoints.** Because `WriteTx` is an immutable Perceus value, returning `Error(UniqueConflict(...))` mid-transaction discards uncommitted index writes automatically without rollback logs.
- **Type inference & exhaustive choice checking caught real bugs at compile time** (`E0068` forcing explicit case arms, `E0093` catching unused imports, `E0044` keeping imports minimal).
