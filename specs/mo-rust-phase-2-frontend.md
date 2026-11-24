# Mo Pure-Rust Migration — Phase 2 Spec: Rust Front End Across the `.core` Seam

**Status:** Active implementation plan (Phase 1 runtime 1A–1E merged in PRs #418–#422)  
**Target repository:** `robertguss/mo` (`~/code/mo`, off `origin/main` after PR #422)  
**Rust toolchain & conventions:** `rustc 1.97+`, edition `2024`, `#![forbid(unsafe_code)]`, following the `writing-good-rust` skill (`/home/exedev/.agents/skills/writing-good-rust/SKILL.md`)

---

## 1. Strategic Context

Phase 1 (PRs #418–#422) replaced the entire C runtime (`bytecode`, `heap`, `prim`, `host`, `vm` — 43.9k LOC of C + OpenSSL) with pure safe Rust (`mo-rt`, 43k LOC, 0 `unsafe`, 0 `libssl`/`libcrypto`/`libsqlite3`, 0 diffs across all 238 goldens + 46 `lower-source` + 13 examples + 30 `lib/` + 16 tools/services + 29 MoDB tests, 1.09× C `-O2` wall time and 2.79× lower peak RSS on 100k `bench-modb.mo`).

**Phase 2** replaces the entire C compiler front end (`base` compiler facilities, `syntax`, `core`, `check`, `lower` — ~43.3k LOC of C) across Mo's second serialized IR seam (**Mo Core `.core` text**, defined in Lean under `formal/`), still with **zero C↔Rust FFI** and **zero edits to C files in `src/`**:

1. **Phase 1 (done):** Pure-Rust Runtime across `.bc` v0.3 (`mo-def`, `mo-bytecode`, `mo-heap`, `mo-prim`, `mo-host`, `mo-vm`, `mo-rt`).
2. **Phase 2 (this spec):** Pure-Rust Front End across `.core` (`mo-base`, `mo-core`, `mo-syntax`, `mo-check`, `mo-lower`, `mo-fe`), verified directly against:
   - The **370k-LOC Lean `MoCore` oracle** (`formal/`, `lake`, `tests/core`, `fuzz/corpus/fuzz_core_text`, `ci/check_core_*.py`, `ci/check_lower*.py`)
   - The **Bison executable grammar** (`grammar/mo.y`, 106 `grammar/tests/` cases)
   - **C `mo format`** across every tracked `.mo` file (`ci/check_format.py` + `tests/test_format.c` fixed points)
   - **All 236 `tests/errors/` diagnostic suites** (exact text + JSON parity, including fixes, spans, labels, secondary spans, and limit generators)
   - **All 238 goldens, 46 `lower-source`, 13 `examples/`, 30 `lib/**/*.mo`, 16 `tools/`+`services/`, and MoDB**
3. **Phase 3 (next):** Pure-Rust `mo-codegen` (`src/codegen/`, 5.7k LOC C → `.bc` v0.3 writer connecting `mo-lower` directly to `mo-bytecode`/`mo-vm`) + unified `mo` CLI (`check`, `run`, `test` with promises/recovery, `format`, `fix`, `emit`, `serve`/HTTP/API/MCP, `replay`, `query`, `upgrade`), passing all 50+ `ci/check_*.py` harnesses + MoDB, then deleting `src/` C files and `Makefile`.
4. **Phase 4 (optional, post-cutover):** Cranelift JIT/AOT over verified `.bc` IR.

**Hard discipline rules:**
- **Zero C files modified in `src/`** across Phase 2.
- **`#![forbid(unsafe_code)]`** in every Rust crate.
- **Zero C↔Rust FFI** — all cross-verification runs over `.core` text, JSON/text diagnostic output, and formatted `.mo` output.

---

## 2. The Zero-FFI Front-End Contracts

Everything Phase 2 implements is pinned by authoritative specification files already in `robertguss/mo`:

| Contract file | Contents | Oracle / Verification |
| --- | --- | --- |
| `src/base/codes.h` + `tests/cli/render-{text,json}.golden` | All stable error codes (`E0001`–`E14xx`), headlines, reference sections, text & JSON diagnostic formats | `tests/errors/` (236 cases), `tests/test_diag.c`, `ci/check_errors.py` |
| `src/base/limits.h` + `tests/module_paths.tsv` | Every compiler arena/work/depth/count limit + CapCase-to-kebab module path rules | `ci/check_errors.py` limit generators, `tests/test_path.c` |
| `formal/MoCore/Syntax.lean` + `formal/TEXT.md` + `src/core/{ops.def,text_schema.def,core.h}` | Mo Core IR, 14 capabilities, 32 type tags, 16 op families, compiler metadata envelope, S-expression `.core` text schema | Lean `mocore` + `ci/check_core_fixtures.sh` (15 runs + 20 fuzz seeds) + `ci/check_core_check.py` + `ci/check_core_generated.py` |
| `grammar/mo.y` + `docs/design/architecture.md` §3.1 | Executable grammar, comment anchors (`OWN_LINE`/`TOKEN`/`ITEM`), `blank_before`, 100-col Wadler formatter | 106 `grammar/tests/`, C `mo format` on every tracked `.mo` file (`ci/check_format.py`) |
| `src/base/{prims.def,hostops.def}` + `lib/**/*.mo` | Native function/capability signatures & embedded standard library (`on_use` lazy list: `Http`, `Json`, `Unicode16`, etc.) | `mo-def` build-time generation (zero hand-copied tables!) |
| `formal/TRANSLATION.md` + `docs/design/architecture.md` §3.2–4.3 | Bidirectional typing, Maranget exhaustiveness, abilities, captures, constants, specs, services/APIs, monomorphization, CPS lowering | `ci/check_lower.py`, `ci/check_lower_source.py` (46 suites), C `mo check --json` & `mo check --emit=core` |

---

## 3. Cargo Workspace Layout & `writing-good-rust` Lints

Add 6 new pure-Rust crates mirroring the exact acyclic dependency DAG in `docs/design/architecture.md` §2:

```text
Cargo.toml                    # Root workspace + hardened [workspace.lints]
clippy.toml                   # allow-unwrap/expect/dbg-in-tests = true
crates/
  # Existing Phase 1 runtime crates
  mo-def/                     # Extended build.rs: also parses src/base/codes.h,
                              # src/core/ops.def, src/core/text_schema.def
  mo-bytecode/                # .bc v0.3 reader/verifier (Phase 1)
  mo-heap/                    # Runtime heap & Perceus RC (Phase 1)
  mo-prim/                    # 187 primitives incl. bit-exact Unicode16 display_width
  mo-host/                    # 59 hostops across 15 capabilities (Phase 1)
  mo-vm/                      # 87-opcode VM + Simulation (Phase 1)
  mo-rt/                      # Phase 1 runtime CLI (verify/run/test/anchors)

  # New Phase 2 front-end crates (strict DAG, #![forbid(unsafe_code)])
  mo-base/                    # Depends only on: mo-def
                              # SourceMap, Span, LineCol, Diagnostic/Code/Label/Fix,
                              # text & JSON renderers, ModulePath, WorkBudget, numeric/UTF-8 helpers
  mo-core/                    # Depends only on: mo-def, mo-base
                              # Core IR (types, literals, ops, exprs, decls, programs, metadata),
                              # S-expression `.core` text parser & printer (byte-exact w/ Lean),
                              # Core typechecker & metadata validator (E1016–E1036+)
  mo-syntax/                  # Depends only on: mo-def, mo-base (+ display-width fn callback)
                              # Lexer, recursive-descent parser w/ recovery + fragments + headers,
                              # arena/indexed AST w/ comment anchors & blank_before,
                              # 100-column Wadler formatter (alignment runs, += rewrite)
  mo-check/                   # Depends only on: mo-def, mo-base, mo-syntax
                              # Program loader (embedded lib/ + lazy on_use + root confinement),
                              # module interfaces & exposure, signature prep, native sigs,
                              # bidirectional inference, Maranget exhaustiveness, abilities,
                              # captures/var-writes/capability flow, polymorphic recursion,
                              # constants, specs (test/example/promise/anchor), services/actors/APIs,
                              # unused-import audit, main contract
  mo-lower/                   # Depends only on: mo-def, mo-base, mo-check, mo-core
                              # Monomorphization, CPS join-point lowering, pattern decision trees,
                              # derived Text/Order helpers, interpolation, exact scalar/float conv,
                              # constants init ordering & prefixes, capability main wrapper,
                              # specs/anchors/structural failure envelopes, service/API descriptors,
                              # full compiler metadata envelope
  mo-fe/                      # Thin Phase 2 CLI driver for differential testing & CI:
                              #   mo-fe core-check FILE.core
                              #   mo-fe core-print FILE.core
                              #   mo-fe parse [--fragment|--header] FILE.mo
                              #   mo-fe format [--check|--stdout] FILE.mo
                              #   mo-fe check [--json] [--emit=core] [--library DIR] FILE.mo
                              #   mo-fe lower [--tests] [--library DIR] FILE.mo
```

### Workspace Lint Policy (`writing-good-rust` §9)
Enforced starting in **Slice 2A** via root `Cargo.toml` + `clippy.toml`, with `[lints] workspace = true` in every crate:

```toml
[workspace.lints.rust]
unsafe_code = "forbid"
unsafe_op_in_unsafe_fn = "deny"

[workspace.lints.clippy]
unwrap_used = "deny"
expect_used = "warn"
panic = "warn"
todo = "deny"
unimplemented = "deny"
dbg_macro = "deny"
allow_attributes = "deny"
allow_attributes_without_reason = "deny"
await_holding_lock = "deny"
let_underscore_future = "deny"
or_fun_call = "warn"
undocumented_unsafe_blocks = "deny"
large_futures = "warn"
```

```toml
# clippy.toml
allow-unwrap-in-tests = true
allow-expect-in-tests = true
allow-dbg-in-tests = true
```

### Engineering Conventions for Every Phase 2 Slice
- **Types and signatures first (H7):** Define public AST/Type/Core enums, typed `thiserror` error enums (E2), and arena/index representations before implementing complex passes.
- **Arena / index representation (O1):** Use `Vec`-backed typed indices (`NodeId`, `TypeId`, `SymId`, `ExprId`) for syntax trees, shared type DAGs, and Core expressions—giving zero lifetime sprawl (O3), zero `Rc<RefCell<_>>`, and trivial explicit-stack traversals that match C's iterative bounds without stack overflows!
- **Exhaustive matching (T3):** Match internal AST, Type, Core, and Diagnostic enums exhaustively without `_ =>` catch-alls.
- **Explicit limits & work budgets:** Enforce every limit in `src/base/limits.h` (`MO_LIMIT_FILE_SIZE`, `MO_LIMIT_SOURCE_TYPE_DEPTH`, `MO_LIMIT_SOURCE_CHECK_WORK`, `MO_LIMIT_PROGRAM_CHECK_WORK`, `MO_LIMIT_LOWER_WORK`, `MO_LIMIT_CORE_NODES`, etc.) with exact error codes (`E1001`–`E1153`), never panicking on adversarial input.
- **Check locked dependency APIs (H3):** Prefer `std` (Phase 2 front-end crates need almost zero third-party deps beyond `thiserror` and `serde_json` or hand-written deterministic JSON matching `render-json.golden` byte-for-byte!).

---

## 4. Six Independently Mergeable Vertical Slices (2A → 2F)

Every slice lands on a fresh worktree off `origin/main`, leaves `bash ci/check.sh gcc` and `bash ci/check.sh rust` 100% green, and modifies **0 C files in `src/`**.

| Slice | Scope | C Ref LOC | Concrete Exit Gate (Automated Oracles) |
| --- | --- | ---: | --- |
| **2A: Workspace Lint Hardening, `mo-base` & `mo-core` (IR + `.core` Codec + Core Checker)** | Apply `writing-good-rust` `[workspace.lints]` + `clippy.toml` across workspace (clean up the 8 `#[allow]` and non-test `unwrap()` sites in existing crates); extend `mo-def/build.rs` with `src/base/codes.h`, `src/core/ops.def`, `src/core/text_schema.def`; build `mo-base` (`SourceMap`, `Diagnostic`/`Code`/`Label`/`Fix`, exact text & JSON renderers, `ModulePath`, `WorkBudget`); build `mo-core` (Core IR + metadata envelope, S-expression `.core` parser/printer, full Core typechecker `E1016–E1036+`); build `mo-fe` (`core-check`, `core-print`). | ~9.2k (`base` + `core`) | `tests/cli/render-text.golden` & `render-json.golden` byte-exact; `tests/module_paths.tsv` 100%; **15/15 `tests/core` runs + 20/20 `fuzz/corpus/fuzz_core_text`** round-trip byte-for-byte with Lean exporter; Rust `mo-fe core-check` matches **Lean `mocore`** & C `test_core_check` across `tests/core`, `fuzz/corpus/fuzz_core_text`, and generated Core programs (`ci/check_core_check.py` / `ci/check_core_generated.py` logic); 0 clippy warnings under hardened workspace lints; 0 C files modified. |
| **2B: `mo-syntax` — Lexer, Recursive-Descent Parser, Trivia/Comments & Wadler Formatter** | Build `mo-syntax`: full lexer (UTF-8 validation, escapes, triple text, nested interpolations, lambda-param `)` disambiguation, all lexical limits); recursive-descent parser with exact error recovery, source counts/nesting bounds, fragment & header-only modes; indexed AST with comment attachment (`OWN_LINE`/`TOKEN`/`ITEM` anchors, `blank_before`); 100-column Wadler formatter (display width callback supplied via `mo-prim::unicode16`, alignment runs, `+=` rewrite); add `mo-fe parse` & `mo-fe format`. | ~5.0k (`syntax`) | **106/106 `grammar/tests/`** (`good`, `bad`, `bad-files`) match Bison grammar acceptance/rejection 100%; **every tracked `.mo` file in the repo** matches C `mo format` **byte-for-byte** (fixed-point + idempotent, 0 diffs); all syntax/lexer error cases in `tests/errors/` match C `mo check` stderr byte-for-byte; parser/formatter fuzz smoke (0 panics). |
| **2C: `mo-check` Part 1 — Loader, Module Interfaces, Signatures, Native Tables & Abilities** | Build `mo-check` foundations: whole-program loader (`load.c` parity — root derivation, embedded `lib/**/*.mo` via build-time table, `on_use` lazy library modules, symlink-under-root confinement, nonblocking regular-file read, cycle diagnostics); module interface resolution & exposure (`T` vs `T(..)`, overloads, clash fixes); signature prep (shared type DAG, nonregular generic data `E0084`, field indexing); native signatures parsed from `mo-def` (`prims.def` + `hostops.def`); ability proofs & customizers (`Equal`, `Order`, `Hash`, `Text`, `Number`, `E0082`). | ~7.5k (first ~40% of `check`) | Every loader, module, visibility, import, signature, nonregular-data, and ability error case in `tests/errors/` matches C `mo check` stderr byte-for-byte (text & `--json`); `mo-fe check --stage=signatures` succeeds across all 30 `lib/**/*.mo`, 13 `examples/`, 238 `tests/golden/`, 16 `tools/`+`services/`, and MoDB with 0 diffs vs C. |
| **2D: `mo-check` Part 2 — Bidirectional Inference, Exhaustiveness, Captures, Constants, Specs, Services & APIs** | Complete `mo-check`: bidirectional body inference (numeric literal constraints, dot dispatch, delayed overload selection, contextual lambdas, `is`/`and`/`implies`/`assert` narrowing, earliest-error selection, all work/depth limits); iterative Maranget pattern-matrix exhaustiveness + bounded witness previews; anonymous-function capture & later-`var`-write CFG analysis; capability containment & spec-only enforcement (`E0098`); polymorphic recursion SCC check; map-literal duplicate keys (`E0094`); constants dependency ordering & cycle check (`E0089`); specs (`test`/`example`/`promise`/`anchor`); `service`/`actor` & `api` checking + service-promises + service-fixes; unused-import audit (`E0093`); `main` entry contract (`E0079`); `mo-fe check [--json]`. | ~12.0k (remaining ~60% of `check`) | **100% of front-end `tests/errors/`** (~235 message-test cases, including generated limit cases) match C `mo check` **byte-for-byte** in both text and `--json`; all 238 goldens, 30 `lib/**/*.mo`, 13 `examples/`, 16 `tools/`+`services/`, 46 `lower-source`, and MoDB pass `mo-fe check --json` with **0 diffs** vs C `mo check --json`. |
| **2E: `mo-lower` — Monomorphization, CPS Lowering, Derived Abilities, Specs, Services & APIs** | Build `mo-lower`: concrete type/function/data instance memoization; CPS join-point lowering (`var`, loops, `break`/`continue`/`return`, `try`, `or`); decision-tree pattern lowering; derived `Text` & `Order` helper generation; interpolation & exact decimal/float/text literal conversion; constants init order & reachable prefixes; `main` capability wrapper (`Unit`/`Int`/`Result`); specs (`test`/`example`/`promise`/`anchor` + `Text.%structural` failure envelopes); service & API descriptor lowering; full compiler metadata envelope (`formal/TEXT.md`); `mo-fe lower [--tests]` & `mo-fe check --emit=core`. | ~9.6k (`lower`) | `mo-fe lower` produces Core accepted by BOTH `mo-core` AND **Lean `mocore`** across all **46 `tests/lower-source`**, **238 goldens**, **30 `lib/**/*.mo`**, **13 `examples/`**, **16 `tools/`+`services/`**, and **MoDB**; Lean `mocore` evaluation results on Rust-lowered Core match C `lower-source` / `mo check --emit=core` 100%; all lowering error codes (`E1150–E1153`) match C byte-for-byte. |
| **2F: Full Phase 2 Parity CI Gate (`ci/check_rust_frontend.py`), Fuzz Smoke & Latency Check** | Add `ci/check_rust_frontend.py` wired into `ci/check.sh rust`: verifies 106/106 grammar tests, formatting byte-parity on every tracked `.mo` file, 100% of front-end `tests/errors/` (text + JSON), 15+20 Lean Core fixtures/seeds, Lean `mocore` differential checking & evaluation on all 46 `lower-source` + 238 goldens + 30 `lib/` + 13 `examples/` + 16 `tools/`+`services/` + optional `--modb-dir`; deterministic lexer/parser/checker/lowerer fuzz smoke (zero panics); benchmark `mo-fe check` latency vs C `0.1 s` budget (`ci/check_check_time.py`). | ~1.5k (CI + fuzz + polish) | **Phase 2 Exit Gate:** `bash ci/check.sh gcc` & `bash ci/check.sh rust` pass 100%; 0 diffs vs C front end & Lean `MoCore`; `mo-fe check` stays under `0.1 s` on all samples; `#![forbid(unsafe_code)]`; hardened `writing-good-rust` lints clean; 0 C files modified. Ready for Phase 3 (`mo-codegen` + unified `mo` CLI + delete C!). |

---

## 5. Verification Discipline (Every Phase 2 Slice)

Every slice PR must run and report:
1. `cargo fmt --all -- --check`
2. `cargo clippy --workspace --all-targets -- -D warnings` (with hardened `writing-good-rust` `[workspace.lints]` and `clippy.toml`)
3. `cargo test --workspace --all-targets` + `cargo test --workspace --doc`
4. `bash ci/check.sh gcc`
5. `bash ci/check.sh rust` (growing from Phase 1 parity to full Phase 1 + Phase 2 parity!)
6. `git diff --name-only origin/main..HEAD` confirming **0 C files modified in `src/`**
