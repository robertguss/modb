# Mo Pure-Rust Migration — Phase 3 Spec: Codegen, Unified Rust `mo` CLI & Deleting C

**Status:** Active implementation plan (Phase 1 PRs #418–#422 and Phase 2 PRs #423–#427 all merged)  
**Target repository:** `robertguss/mo` (`~/code/mo`, off `origin/main` after PR #427)  
**Rust toolchain & conventions:** `rustc 1.97+`, edition `2024`, `#![forbid(unsafe_code)]`, hardened `[workspace.lints]` + `clippy.toml`, strictly following `$writing-good-rust` (`/home/exedev/.agents/skills/writing-good-rust/SKILL.md`)

---

## 1. Strategic Context

Phases 1 and 2 are complete in pure safe Rust with zero C edits and zero C↔Rust FFI:
- **Phase 1 (PRs #418–#422):** Complete pure-Rust runtime across `.bc` v0.3 (`mo-def`, `mo-bytecode` reader/verifier, `mo-heap`, `mo-prim`, `mo-host`, `mo-vm`, `mo-rt`) — 59/59 hostops, 87/87 opcodes, 187/187 primitives, 0 `unsafe`, 0 `libssl`/`libcrypto`/`libsqlite3`, 0 diffs across all 238 goldens + 46 `lower-source` + 13 examples + 30 `lib/` + 16 tools/services + 29 MoDB tests, 1.09× C `-O2` wall time & 2.79× lower peak RSS on 100k `bench-modb.mo`.
- **Phase 2 (PRs #423–#427):** Complete pure-Rust front end across `.core` v0.11 (`mo-base`, `mo-core`, `mo-syntax`, `mo-check`, `mo-lower`, `mo-fe`) — 106/106 Bison grammar fixtures, 1,559/1,559 tracked `.mo` files byte-exact with C `mo format`, 85/85 `.diag` snapshots, 235/235 `tests/errors/` classified (212/212 full check+lower text+JSON byte-exact), 339 lowered programs + 21 MoDB files verified against `mo-core` & Lean `mocore` (210 Lean eval outcomes matched 100%).

**Phase 3** finishes the strangler migration to **zero C**:
1. Connects our Phase 2 Rust front end directly to our Phase 1 Rust runtime via **`crates/mo-codegen`** + **`mo-bytecode` binary writer/disassembler** (Slice 3A) — achieving the first **100% end-to-end pure-Rust `.mo` → `.core` → `.bc` → VM execution** with zero C binary in the loop!
2. Builds the unified pure-Rust **`mo`** CLI (`crates/mo-cli` + service runtime/store/HTTP/upgrade modules) passing **every** black-box CI harness in `ci/check.sh` (`drivers`, `bench`, `lean` differential, and MoDB) (Slices 3B–3E).
3. Performs final cutover and **deletes all C compiler/runtime files (`src/`, `vendor/sqlite/`, `Makefile`, C tests/fuzz/CBMC)** (Slice 3F).

**Hard discipline rules:**
- **Zero C files modified in `src/`** during Slices 3A–3E (C stays 100% green as our live differential oracle until cutover in 3F).
- **`#![forbid(unsafe_code)]`** and hardened `$writing-good-rust` `[workspace.lints]` across every crate.
- **Zero OpenSSL / zero system `libsqlite3`** (pure-Rust `rustls` + bundled `rusqlite` only).
- **Every thread writing Rust invokes `$writing-good-rust`.**

---

## 2. Remaining C Inventory (~38.9k LOC Across 4 Areas)

| Area | C Reference Files | C LOC | Target Rust Crates / Slices |
| --- | --- | ---: | --- |
| **Bytecode writer & disassembler** | `src/bytecode/{write,disassemble,names,signature}.c` | ~1.5k | `crates/mo-bytecode` (Slice 3A) |
| **Codegen (Core → `.bc` v0.3)** | `src/codegen/*.{c,h}` | 5,731 | `crates/mo-codegen` (Slice 3A) |
| **Core CLI (`check`, `run`, `format`, `fix`, `emit`, `guide`, `install`)** | `src/tools/{main,cli,execute,run,format,fix,install,render}.c` | ~4.4k | `crates/mo-cli` (Slice 3B) |
| **`mo test` engine (`promises`, `inputs`, `fakes`, `service-tests`, `recovery`, `mutants`, `gates`, `strength`, `builders`)** | `src/tools/{tests,promises,inputs*,fakes,service-tests,recovery,mutants,gates,strength,builders,deadline}.c` | ~9.3k | `crates/mo-test` + `crates/mo-cli` (Slice 3C) |
| **Durable service store, live service loop, `mo serve`, HTTP `api-server`, operator views, `fetch`, `export`** | `src/host/store*.c`, `src/vm/service*.c`, `src/tools/{serve,api-server,protocol*,history,fetch}.c` | ~11.0k | `crates/mo-service` + `crates/mo-cli` (Slice 3D) |
| **Typed upgrades, offline `replay`/`query`, `diff`, `push`** | `src/tools/{diff,offline*,upgrade*,push,protocol-upgrade}.c` | ~7.0k | `crates/mo-upgrade` + `crates/mo-cli` (Slice 3E) |

---

## 3. Six Independently Mergeable Vertical Slices (3A → 3F)

Every slice lands on a fresh worktree off `origin/main`, keeps `bash ci/check.sh gcc` and `CI=1 bash ci/check.sh rust` 100% green (Slices 3A–3E), and leaves its PR open for Robert's review.

| Slice | Scope | C Ref LOC | Concrete Exit Gate (Automated Oracles) |
| --- | --- | ---: | --- |
| **3A: `mo-bytecode` Writer/Disassembler + `mo-codegen` (Core → `.bc` v0.3) + End-to-End Pure-Rust Execution + `< 0.1 s` Check Latency Gate** | Extend `crates/mo-bytecode` with binary `.bc` v0.3 writer (`write.rs`, exact FNV-1a checksum & all 11 sections) and canonical disassembler (`disassemble.rs` for `--emit=bytecode`). Create `crates/mo-codegen` (`types`, `prepare`, `ownership` borrow inference + Perceus RC/reset/reuse placement, `registers`, `control`, `operations`, `bigint`, `generate`, `program`, `compile`; `E1013`–`E1015`, `E1200`–`E1299`). Add `mo-fe emit [--tests] FILE.mo -o OUT.bc`, `mo-fe check --emit=bytecode`, and end-to-end anchor evaluation (`e1405`, `e1405-forbids`, `e1013`). Add `< 0.1 s` `mo-fe check` latency gate across all 12 samples (`ci/check_check_time.py` contract). | ~7.2k | **End-to-End 100% Pure-Rust Compilation & Execution (Zero C `mo` in the loop!):** `mo-fe emit` → `mo-rt verify` → `mo-rt run`/`test`/`anchors` matches C `mo` byte-for-byte across all **238 goldens** (209 full + 24 promise/service `test`/`example` + 5 compile-only), **46 `lower-source`**, **13 `examples/`**, **30 `lib/`**, **17 `tools/`+`services/`**, and **MoDB (29/29 tests)**; deterministic double-compile codegen test matches `ci/check_codegen.py` on generated Core programs; **`215/215` check+lower+codegen+anchor `tests/errors/`** byte-exact (`e1013`, `e1405`, `e1405-forbids` now covered!); `mo-fe check` `< 0.1 s` on all 12 samples; 0 C files modified. |
| **3B: Unified Rust `mo` CLI Core (`crates/mo-cli`: `check`, `run`, `format`, `fix`, `emit`, `guide`, `install`)** | Create `crates/mo-cli` producing the unified `mo` binary (`target/release/mo`, `target/debug/mo`) embedding docs & protocol guide (`ci/embed_docs.py` / `embed_protocol.py` parity via `build.rs`). Implement full CLI argument parsing, exit codes, `--json`, `--root`, `--state-dir`, `--max-heap`/`--max-stack`/`--max-depth`, `check` (including anchor execution), `run` (`.mo` and `.bc` paths), `format` (in-place atomic rewrite + `--check` + `--stdin`), `fix` (multi-round non-overlapping single-fix application, `E1407`), `emit` (`--tests`, `-o`), `guide`, and `install`. | ~4.4k | Standalone Rust `mo` binary passes **`ci/check_format.py`** (all 1,559 files!), **`ci/check_errors.py`** (all non-`serve`/`upgrade` cases), **`ci/check_crypto.py`**, **`ci/check_network.py`**, **`ci/check_reference_examples.py`**, **`ci/check_check_time.py`** (`< 0.1 s`), **`bench/v0/grade.py`**, and **MoDB** `mo test` (29/29) + 100k `bench-modb.mo` + 100/100 `SIGKILL` — with zero C binary! |
| **3C: Complete `mo test` Engine (`crates/mo-test`: Promises, Generators/Shrinkers, Fakes, Service-Tests, Recovery, Mutants/Gates, Strength, Builders)** | Port `tests.c`, `promises.c`, `inputs*.c`, `fakes.c`, `service-tests.c`, `recovery.c`, `mutants.c`, `gates.c`, `strength.c`, `builders.c`, `deadline.c` into pure safe Rust `crates/mo-test` wired into `mo test` (`--only`, `--module`, `--list`, `--json`, `--mutants`, `--strength`, `--seed`, `--time`, etc.). | ~9.3k | Standalone Rust `mo` passes **100% of `ci/check_golden.py` (all 238/238!)**, **100% of `ci/check_lib.py` (all 30/30!)**, **100% of `ci/check_programs.py` (all 17/17!)**, **`ci/check_simulation.py`**, **`ci/check_tools.py`** (`linkcheck`, `tally`, `notioncopy` + frozen hidden tasks), and `tests/cli/{test,gates,strength*}`! |
| **3D: Durable Service Store, Live Service Loop, `mo serve`, HTTP `api-server`, Operator Views, `fetch`, `export`** | Create `crates/mo-service` (`#![forbid(unsafe_code)]`): SQLite durable `ServiceStore` (`src/host/store*.c` via bundled `rusqlite`), live multi-worker `ServiceLoop` (`src/vm/service*.c` incl. failure recording & live swap), `mo serve`, HTTP/JSON/MCP `api-server` (`src/tools/api-server.c`, `protocol*.c`, pure-Rust TLS via `rustls` — zero OpenSSL!), `history`, authenticated operator views, `fetch`, and immutable `export`. | ~11.0k | Standalone Rust `mo` passes **`ci/check_operator.py`**, **`ci/check_fetch.py`**, **`ci/check_export.py`**, **`ci/check_task_queue.py`**, and **`ci/check_kill_loop.py`** (15+ real `SIGKILL`s against live `mo serve` with client reconciliation!), zero OpenSSL linkage! |
| **3E: Typed Upgrades, Offline `replay`/`query`, `diff`, `push` & 100% `ci/check.sh` Driver Parity** | Create `crates/mo-upgrade`: structural schema/code `diff`, offline `replay` & `query`, typed `upgrade` bundles & checked restarts, recorded schema fallback, adoption replay, recorded-context checks, live `push`/streams/recovery, and remote proxy/tunnel/rate-retry. Wire into `crates/mo-cli`. | ~7.0k | Standalone Rust `mo` passes **100% of `ci/check_cli.py`**, **`ci/check_errors.py` (236/236!)**, **`ci/check_offline.py`**, **`ci/check_offline_core.py`**, **`ci/check_upgrades.py`**, **`ci/check_upgrade_{fallback,adoption,context,live,remote}.py`** — **every single black-box driver and benchmark check in `ci/check.sh` passes 100% on the pure-Rust `mo` binary!** |
| **3F: Final Cutover & Delete C** | Move contract tables (`prims.def`, `hostops.def`, `opcodes.def`, `codes.h`, `ops.def`, `limits.h`) into `crates/mo-def/defs/` (and update `docs/design/library.md` map check); switch `ci/check.sh` and GitHub workflows to Cargo-only pure-Rust `mo`; **delete `src/`, `vendor/sqlite/`, `Makefile`, C unit tests, C fuzzers, and `cbmc/`**; remove temporary `mo-rt`/`mo-fe` split binaries if superseded by `mo` (or keep internal test helpers cleanly). | Cutover | **Zero C compiler/runtime files remain in the repository!** `CI=1 bash ci/check.sh` passes 100% using only pure-Rust `mo` (plus Lean `MoCore` & Bison grammar); `#![forbid(unsafe_code)]`; zero `libssl`/`libcrypto`/`libsqlite3`; MoDB 29/29 + 100k `bench-modb.mo` + 100/100 `SIGKILL` pass on the single pure-Rust `mo` binary! |

---

## 4. Verification Discipline (Every Phase 3 Slice)

Every slice PR (3A–3E) must run and report:
1. `cargo fmt --all -- --check`
2. `cargo clippy --workspace --all-targets --all-features -- -D warnings` (hardened `$writing-good-rust` lints)
3. `cargo test --workspace --all-targets` and `cargo test --workspace --doc`
4. `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps`
5. `bash ci/check.sh gcc` → `check.sh finished: pass`
6. `CI=1 bash ci/check.sh rust` → `check.sh finished: pass`
7. `git diff --name-only origin/main..HEAD -- src/` empty (**0 C files modified** until Slice 3F cutover!)
