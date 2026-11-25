# Mo Pure-Rust Migration — Phase 1 Spec: Rust Runtime Across the `.bc` Seam

**Status:** Draft specification for Robert's review  
**Target repository:** `robertguss/mo` (`~/code/mo`, off `origin/main` after PR #417 `067fc6ae`)  
**Rust toolchain verified on host:** `rustc 1.97.1` / `cargo 1.97.1`

---

## 1. Strategic Context (3-Phase Strangler to Zero C)

The overarching goal is to **eliminate C maintenance in `mo` altogether** while preserving Mo's language semantics, black-box verification corpus (238 golden suites, 235 error suites, 85 diagnostic snapshots, 46 Lean `MoCore` differential tests, 106 grammar tests, 30 `lib/*.mo` modules, and MoDB), and git history.

We migrate bottom-up across Mo's **two existing serialized IR seams** with **zero C↔Rust FFI**:

1. **Phase 1 (this spec) — Rust Runtime across `.bc` v0.3:** C `mo emit` produces `.bc` → Rust loads, verifies ownership, and executes it (`mo-rt`), replacing OpenSSL and the entire C runtime (`bytecode`, `heap`, `vm`, `prim`, `host` — 43.9k LOC of C) with safe Rust.
2. **Phase 2 — Rust Front End across `.core`:** Rust compiles `.mo` → `.core` text form (`syntax`, `format`, `check`, `core`, `lower`), verified directly against the 370k-LOC Lean `MoCore` oracle and all 235 error / 85 diagnostic / 106 grammar suites.
3. **Phase 3 — Rust Codegen, CLI & Delete C:** Rust compiles `.mo` → `.core` → `.bc` → Rust VM in one binary, passes all 50+ `ci/check_*.py` harnesses + MoDB, and deletes `src/` C files and `Makefile`.
4. **Phase 4 (optional, post-cutover) — Cranelift JIT/AOT:** Drops directly onto the verified `.bc` IR (static monomorphic types + Perceus RC = zero GC stack maps) to close the ~11–21× speed gap to C SQLite down to ~2–3×.

**Hard discipline rule:** Freeze new features in the C compiler once Phase 1 starts (bugfixes + the single tiny `mo emit --tests` enabler in Slice 1A only).

---

## 2. The Zero-FFI `.bc` v0.3 Contract

Everything Phase 1 implements is pinned by four existing contract files in `robertguss/mo`:

| Contract file | Contents | Count |
| --- | --- | ---: |
| `src/bytecode/bytecode.h` + `docs/design/bytecode.md` | Binary format `MOBC` v0.3, 20-byte header + FNV-1a checksum, 11 sections (`STRINGS`..`SERVICES`), 7 function kinds | 11 sections |
| `src/bytecode/opcodes.def` | Stable 1-based instruction set (`MOVE`..`SIM`) with operand kinds & ownership access modes | **87 opcodes** |
| `src/heap/types.h` | 22 type kinds, 15 capabilities, 4 layout kinds, `mo_case_shape` (`EMPTY`/`INLINE`/`REF`/`BOXED`) | **22 types, 15 caps** |
| `src/base/prims.def` | All pure stdlib primitives + parameter ownership (`o`/`b`) + bug names | **187 prims** |
| `src/base/hostops.def` | All capability operations (real + fake, `spec_only` flag) + 5 `SIMOP`s | **59 hostops, 5 simops** |
| `src/base/limits.h` | Exact load limits, runtime limits (`--max-stack`, `--max-depth`, `--max-heap`), open-handle/IO caps | All named constants |

### Required tiny C enabler (Slice 1A)
Currently `mo emit FILE -o OUT` refuses files without `main` or `service` (`E0079`), even though `mo test` compiles `MO_FUNCTION_TEST` / `MO_FUNCTION_EXAMPLE` into the exact same `.bc` wire buffer (`src/tools/tests.c`).

- Add `mo emit --tests FILE -o OUT` (~15 lines in `src/tools/cli.c` + `src/tools/execute.c`) so the differential test harness can emit `.bc` for test-only modules (including `src/modb.mo`, `tests/test-modb.mo`, `tests/test-table.mo`, `lib/*.mo`, and test-only golden suites) without touching any compiler internals.

---

## 3. Cargo Workspace Layout (`~/code/mo`)

Live inside `~/code/mo` alongside `src/` during the strangler transition (so `build.rs` reads `src/base/*.def` directly with zero drift, and Phase 3 deletes `src/` cleanly in place).

```text
Cargo.toml                    # Workspace root (edition = "2024", resolver = "3")
Cargo.lock
crates/
  mo-def/                     # Single source of truth generated at build time from:
                              #   src/base/prims.def, src/base/hostops.def,
                              #   src/bytecode/opcodes.def, src/base/limits.h
                              # Exports typed Rust enums + metadata tables (zero hand-copying!)
  mo-bytecode/                # .bc v0.3 binary reader & writer, FNV-1a checksum,
                              # structural validator (validate.c), full ownership/borrow/token
                              # dataflow verifier (verify.c + verify-instruction.c),
                              # and register readability replay for defect reports
  mo-heap/                    # TypeTable, mo_case_shape, Value + Rc<HeapObj> Perceus RC,
                              # reuse tokens, HeapBudget (--max-heap), immortal constants,
                              # insertion-ordered Map/Set, List, Text, Bytes, BigInt,
                              # exact Decimal (i128 + 256-bit ties-to-even mul/div),
                              # structural equality, ordering, hashing, and printing
  mo-prim/                    # All 187 primitives from prims.def:
                              #   Int/Byte/Float/Decimal/BigInt/Char/Text/Bytes/
                              #   List/Map/Set/Range/Time/Duration/Unicode16/Crypto
  mo-host/                    # All 59 hostops across all 15 capabilities (real + fake):
                              #   Args, Env, Console, Files/ReadFiles/Files.File,
                              #   Clock, Random, SecureRandom, Network/Connection (rustls),
                              #   Sqlite (rusqlite bundled), Command
  mo-vm/                      # Image init (globals + immortalization), Process, call stack
                              # (--max-stack, --max-depth), 87-opcode interpreter, tail calls,
                              # stops & formatted defect reports, Simulation (SIM opcode)
  mo-rt/                      # Thin CLI binary for Phase 1 testing & differential harness:
                              #   mo-rt run [--root DIR] [--max-heap ...] FILE.bc [-- args...]
                              #   mo-rt test [--root DIR] FILE.bc
                              #   mo-rt verify FILE.bc
```

### Safety & dependency policy
- **`#![forbid(unsafe_code)]`** in `mo-def`, `mo-bytecode`, `mo-heap`, `mo-prim`, `mo-vm`, and `mo-rt` (and everywhere in `mo-host` except minimal POSIX `openat`/fd-confinement or `pre_exec` rlimit setup if needed—isolated behind audited helpers or safe crates like `cap-std`/`rustix`).
- **Zero OpenSSL.** Pure-Rust crypto & TLS stack:
  - TLS: `rustls` + `webpki-roots` (or `rustls-native-certs` matching C `tls.c` trust behavior)
  - Crypto primitives (`src/prim/crypto.c` parity): `sha2` (SHA-256), `hmac` (HMAC-SHA256), `aes-gcm` (AES-256-GCM 32B key / 12B nonce / 16B tag), `scrypt` (PHC password format), `subtle` (constant-time eq), `zeroize` (buffer wiping on drop)
- **Unicode 16.0 bit-exact parity:** Generate `crates/mo-prim/src/unicode16_data.rs` from Mo's existing `ci/generate_unicode16.py` (or a small Rust emitter mode in it) so `Unicode16` matches Mo's exact pinned Unicode 16.0.0 tables instead of drifting with crate upgrades.
- **BigInt:** `num-bigint` (little-endian magnitude serialization matches `mo_bytecode_bigint` directly).
- **SQLite:** `rusqlite` with `bundled` feature (behind a `sqlite` Cargo feature enabled by default; keeps C SQLite completely encapsulated in one crate and trivial to disable later if desired).
- **No async runtime bloat in Phase 1A–1E:** Keep `mo-host` synchronous std/blocking I/O matching Mo's synchronous capability semantics (`Network`, `Files`, `Command`, `Clock.sleep`).

---

## 4. Core Runtime Design Invariants

1. **Single source of truth (`mo-def`):**
   - `crates/mo-def/build.rs` parses `src/base/prims.def`, `src/base/hostops.def`, `src/bytecode/opcodes.def`, and `src/base/limits.h` (with `cargo:rerun-if-changed=` directives) and emits Rust enums (`Opcode`, `PrimId`, `HostOpId`, `SimOpId`) with exact 0-based / 1-based discriminants, ownership strings (`"ob"`), `spec_only` flags, and bug messages.
   - Any edit to `.def` files automatically updates Rust at compile time—zero table drift.

2. **Safe Rust Perceus RC + Reuse (`mo-heap`):**
   - `Value` represents immediates (`Unit`, `Bool(bool)`, `Byte(u8)`, `Int(i64)`, `Float(f64)`, `Char(char)`, `Time(i64)`, `Duration(i64)`, `Decimal(i128)`, `Range(i64, i64)`, `ChoiceInline { tag: u32, payload: u64 }`), heap references (`Ref(Rc<HeapObj>)`), and reuse tokens (`Token(Option<ReuseSlot>)`).
   - Because verified bytecode enforces linear ownership on owned registers, **`Rc::get_mut` / `Rc::try_unwrap` achieves O(1) in-place Perceus reuse** for `List`, `Map`, `Set`, `Text`, `Bytes`, `Record`, `CaseBlock`, and `SET_FIELD` / `RESET` / `REUSE` with zero `unsafe`.
   - Constants and initialized globals are marked `immortal: bool` (and retained in `Image`), ensuring `can_mutate_in_place` is always `false` for constants/globals and anything reachable from them (`bytecode.md` §2.4).
   - `HeapBudget` tracks logical bytes allocated per process and enforces `--max-heap` (default 1 GiB) cleanly by returning `VmStop::OutOfMemory` rather than panicking.

3. **Exact Semantic Parity Traps (Explicitly Pinned):**
   - **`Map` and `Set` iteration order:** `src/heap/table.c` preserves insertion order (compacting on removal while keeping surviving order). `mo-heap` MUST preserve insertion order on `keys`, `values`, `entries`, `to_list`, and structural printing (e.g., dense entry `Vec` + open-addressing hash index or `indexmap::IndexMap` with `shift_remove`).
   - **`Decimal` arithmetic:** Port `src/base/decimal.c`'s exact 94-line `u128` + 256-bit multiplication/division with ties-to-even rounding and `-(2^127 - 1) .. +(2^127 - 1)` bounds (rejecting `i128::MIN`).
   - **`Float` semantics:** Match `src/heap/float.c` formatting (`Float.to_text`), `CMP_FLOAT` / `LT_FLOAT` / `EQ_FLOAT` NaN/signed-zero rules, and `Float.to_decimal`.
   - **`Files` / `ReadFiles` / `Files.File` confinement:** Match `src/host/confine.c` + `path.c` + `real-files.c` — symlink traversal bound (`MO_LIMIT_PATH_LINKS = 40`), open-folder cap (`256`), open-file cap (`64`), `16 MiB` single-I/O cap, root-directory confinement (never escape `--root` via `..` or symlinks), and full `Files.in_memory` raw-bytes parity (including PR #416's `Files.File` handle ops: `open`, `read_at`, `write_at`, `size`, `truncate`, `sync`, `write_bytes`, `rename`).
   - **`Bytes.compare_slice_at` & `Bytes.empty?`:** Include all PR #416 and PR #417 primitives from day 1 (guaranteed automatically via `mo-def`).
   - **Defect reports & stack traces:** Implement `mo_image_registers_readable` replay in `mo-bytecode` and source-span + variable-name rendering in `mo-vm` so `stop` / `fail` / runtime bug output matches C `mo` golden `stderr` tests.

---

## 5. Six Independently Mergeable Vertical Slices

Every slice lands as its own clean PR on a fresh worktree off `origin/main`, with `ci/check.sh` remaining 100% green throughout.

| Slice | Scope | Est. Rust LOC | Concrete Exit Gate |
| --- | --- | ---: | --- |
| **1A: Seam & Core Vertical Slice** | Tiny C `mo emit --tests` flag (~15 LOC); Cargo workspace + `mo-def` (`build.rs`); `mo-bytecode` binary reader + header/FNV-1a/structural checks; `mo-heap` core types/scalars/tuples/records/choices/closures/printing; `mo-vm` core 87-opcode dispatch (except `SIM`) + stack/depth limits; `mo-host` `Args`/`Env`/`Console` (real + fake); `mo-rt run` & `mo-rt test`. | ~4.5k | `cargo test --workspace` green; differential check passes on first ~50 pure-compute + `Console`/`Args`/`Env` golden suites (exact stdout/stderr/exit-code match vs C `mo`). |
| **1B: Ownership Verifier, Perceus Reuse, Collections & Numbers** | Complete `mo-bytecode` ownership/borrow/token dataflow verifier + `registers_readable` replay + verifier negative tests & `cargo-fuzz` harness; `RESET`/`REUSE`/`FREE_TOKEN`; exact `Decimal` (256-bit) + `BigInt` + `Float` + `Time`/`Duration` + `Range`; insertion-ordered `Map`/`Set`, `List`, `Text`, `Bytes`; all non-Crypto/non-Unicode16 primitives in `mo-prim` (~173 of 187 prims). | ~7.5k | All pure-language golden suites + Lean `lower-source` pure suites match C `mo` 100%; verifier rejects every malformed/use-after-move/double-drop `.bc` test case; `cargo-fuzz` 0 crashes; Perceus in-place reuse verified by O(1) mutation unit tests. |
| **1C: Crypto, Unicode16 & `Files`/`Clock`/`Random` (MoDB Gate)** | Pure-Rust `Crypto` (7 prims via `sha2`/`hmac`/`aes-gcm`/`scrypt`); pinned `Unicode16` (7 prims); real + fake `Files`/`ReadFiles`/`Files.File` (full path confinement, symlink bounds, handle limits, `Files.in_memory` raw-bytes parity), `Clock`, `Random`, `SecureRandom`. | ~5.0k | **MoDB Milestone Gate:** `mo-rt test` passes all 5 MoDB suites (29/29 tests: 1,200 + 600 differential ops, 500 simulated crashes, `examples/shop.mo`); `bench/kill_loop.py` passes **100/100 real `SIGKILL` crashes** under `mo-rt`; 100k-row `bench-modb.mo` passes with flat freelist (`3,933` pages) and bounded RSS! |
| **1D: `Network` (`rustls`), `Sqlite`, `Command`, `Simulation` & Defect Reports** | Real + fake `Network`/`Connection` using **`rustls`** (zero OpenSSL!) + host allowlist + timeouts; `Sqlite` via bundled `rusqlite` + fake; `Command` (allowlist, timeout, output cap) + fake; `SIM` opcode (87) & service simulation runtime; full defect report parity (`stderr` stack traces + register values). | ~6.5k | All remaining capability golden suites (`cap-network-*`, `cap-sqlite-*`, `cap-command-*`, `http-fake`, `fail-bug-*`, simulation tests) match C `mo` 100%. |
| **1E: Full Phase 1 Parity & CI Gate** | Add `ci/check_rust_runtime.py`: compiles every test via C `mo emit` and diffs C `mo` vs Rust `mo-rt` across all **238 golden suites**, **46 `lower-source` Lean suites**, **14 examples**, and **30 `lib/*.mo` modules**; wire optional `rust` target into `ci/check.sh`; `cargo clippy --workspace --all-targets -- -D warnings`; `cargo-fuzz` smoke on `mo-bytecode` + `mo-vm`; benchmark `mo-rt` vs C `mo` on MoDB 100k. | ~1.5k | **Phase 1 Exit Gate:** 100% parity (0 diffs) across 238 golden + 46 Lean + 14 examples + 30 `lib/` + MoDB; 0 `clippy` warnings; 0 `unsafe` in core crates; zero OpenSSL linkage (`ldd target/release/mo-rt` confirms no `libssl`/`libcrypto`). |
| **1F: Service / HTTP / API / MCP Runtime *(deferred or bridge into Phase 3)*** | `mo serve`, HTTP/API multi-worker server (`hyper`/`rustls`), durable service store (`STOREOP`/`FAILUREOP`), MCP views, live upgrades. | ~6–8k | All `cli_serve.py` / `check_upgrade_*.py` / `tests/runtime/*.mo` pass on Rust runtime. (Can run right after 1E or alongside Phase 3 CLI cutover.) |

**Total Phase 1A–1E estimate:** ~25k lines of idiomatic safe Rust replacing ~44k lines of C (including 8.9k generated Unicode data) + OpenSSL.

---

## 6. Verification & Workflow Discipline

- **Every slice PR must run:**
  1. `cargo fmt --check`
  2. `cargo clippy --workspace --all-targets -- -D warnings`
  3. `cargo test --workspace`
  4. `python3 ci/check_rust_runtime.py` (growing coverage slice-by-slice from 1A → 100% at 1E)
  5. Existing C suite (`CI=1 bash ci/check.sh ...`) whenever any C file is touched (only Slice 1A touches C for `mo emit --tests`).
- **Benchmark checkpoint at Slice 1C and 1E:** Run MoDB `bench/bench-modb.mo 100000` on `target/release/mo-rt` vs C `build/gcc/release/mo` to track safe-Rust interpreter performance and RSS (and confirm whether any hot-path tuning like compact 16-byte `Value` is worthwhile before Phase 2).
- **Zero drift guarantee:** `mo-def` test asserts exact 1-to-1 count and order match with `src/base/prims.def`, `src/base/hostops.def`, and `src/bytecode/opcodes.def`.
