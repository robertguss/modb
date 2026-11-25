# Mo PR Contract: High-Leverage DX & `Bytes` Fixes from MoDB Milestone 1

**Target repo:** `~/code/mo` (implement in a clean worktree/branch off `origin/main`, after PR #416).
**Source:** Real papercuts recorded in [FRICTION.md](../FRICTION.md) while building MoDB Layers 1 and 2 (~2,700 lines of pure Mo). Every item is general-purpose and improves all Mo programs.

---

## 1. `Bytes.empty?` (`FRICTION.md` #1)

Add `.empty?` to `Bytes` for parity with `Text.empty?`, `List.empty?`, `Map.empty?`, and `Set.empty?`.

```c
PRIM(BYTES_IS_EMPTY, "Bytes", "empty?", "fn(Bytes) : Bool", "b", "")
```

- Returns `true` iff `bytes.size == 0`.
- Update `src/base/prims.def`, `src/prim/prim.c`, `src/prim/text.c`, `formal/MoCore/` (`Prim.lean`, `PrimSafety.lean`, `Builtins.lean`, `Text/Prim.lean`), `docs/design/library.md`, `docs/reference/README.md`, `tests/test_prim.c`, and `ci/check_primitives.py`.

---

## 2. `Bytes.compare_slice_at` (`FRICTION.md` #5)

Zero-allocation slice comparison primitive for binary parsers, protocol frames, archives, and B+Tree slotted pages (avoids allocating a temporary `Bytes.slice` copy on every binary-search probe).

```c
PRIM(BYTES_COMPARE_SLICE_AT, "Bytes", "compare_slice_at",
     "fn(Bytes, Int, Int, Bytes) : Option(Ordering)", "bbbb", "")
```

- Semantics for `bytes.compare_slice_at(offset, len, other)`:
  - If `offset < 0` or `len < 0` or `(uint64_t)offset > bytes.size` or `bytes.size - (size_t)offset < (uint64_t)len`, return `None` (overflow-safe bounds check, matching `u16_be_at`/`i64_be_at`).
  - Otherwise compare the `len` bytes starting at `bytes + offset` lexicographically (unsigned byte order) against `other` using `memcmp(bytes + offset, other.data, min(len, other.size))`, breaking ties by `len` vs `other.size`, and return `Some(Less | Equal | Greater)`.
- Update `src/base/prims.def`, `src/prim/prim.c`, `src/prim/text.c`, `formal/MoCore/`, `docs/design/library.md`, `docs/reference/README.md`, `tests/test_prim.c`, `fuzz/fuzz_prim.c`, and `ci/check_primitives.py`.

---

## 3. Allow Local `var` Inside Anonymous Functions (`FRICTION.md` #8)

Currently `src/check/infer.c` rejects *all* `var` assignments when `p->lambda != 0` with `E0090` (`MO_CODE_LAMBDA_WRITE`), even when the `var` was declared *locally inside* the anonymous function itself. That makes callback-scoped APIs (`Table.write_tx(db, fn(tx) ... end)`, `Sqlite.transaction`, folds, builders) unnecessarily awkward.

- **New rule (updates Reference §5.6 & §6.2):**
  - An anonymous function **may** declare and assign its own local `var` bindings (including `+=`, `-=`, and record field updates `s.field = ...`) when `variable->function == p->lambda`.
  - An anonymous function **still cannot** assign any `var` declared in an enclosing function (`variable->function != p->lambda` when `p->lambda != 0`): that case reports **`E0090` (`MO_CODE_LAMBDA_WRITE`)** (for both direct assignment and field assignment), preserving `E0090`'s code meaning in `src/base/codes.h` and `tests/errors/e0090/`.
  - Capture safety remains unchanged: an outer `var` read inside an anonymous function still cannot be assigned later in the outer function (`MO_CODE_CAPTURE_ASSIGNMENT`).
- **Verify lowering, codegen, Perceus reuse, and Lean:** Ensure local `var` scalars, loops, and struct field updates inside anonymous functions lower and execute identically to named functions under `gcc`, `clang`, `sanitize`, and `lean`.
- Update `tests/errors/e0090/main.mo` (to test assigning an *outer* `var` inside an anonymous function), add positive tests for local `var` + loops + field updates inside anonymous functions, and update `docs/reference/README.md` §5.6 and `docs/agent-guide.md`.

---

## 4. Support Bare `_ = expr` Discard Binding (`FRICTION.md` #10)

`src/check/infer.c:123` already handles `MO_S_UNDERSCORE` on `MO_S_BIND`, and tuple destructuring `(_, b) = pair` already supports `_`, but `src/syntax/parser.c:1653` (`validate`) rejects bare `_ = expr` with misleading `E0010: assignment changes a var or its fields`.

- Allow `MO_S_UNDERSCORE` as the left-hand target of `MO_S_BIND` (`_ = expr`) in `src/syntax/parser.c` and `grammar/mo.y` (still rejecting `_ += expr` and `_ -= expr` with `E0010`, and still rejecting `var _ = expr`).
- Verify `src/check/infer.c` and `src/lower/` handle bare `_ = expr`:
  - Evaluates `expr` once for its effects/validation (`_ = try verify_snapshot(...)`).
  - Still enforces `MO_CODE_FAILURE_IGNORED` (`E0089`) if `expr` produces an unhandled `Result` (only `_ = try expr` or non-`Result` values succeed — double-check existing `E0089` tests for `_` rules so we stay consistent with Reference §8.2!).
- Verify `make grammar`, `mo format`, `tests/errors/e0010/`, and add unit + golden tests.

---

## 5. Clearer Diagnostic for `or` on `Result(T, E)` (`FRICTION.md` #2)

In `src/check/infer-dispatch.c:204`, writing `result_val or fallback` falls through to the `Bool` branch and reports `E0074: a condition isn't a yes-or-no answer — expected Bool, found Result(...)`, which misleads authors who expect `or` to work on `Result` like it does on `Option`.

- Keep `or` semantics unchanged (`Option(T)` unwrap or `Bool` logical OR — do NOT change language semantics or error code numbers).
- When `or`'s left-hand side is `Result(T, E)`, keep `MO_CODE_CONDITION_TYPE` (`E0074`) or emit a tailored message/help note explaining: *"`or` unwraps `Option` or combines `Bool`, not `Result`; use `try`, `case`, or `assert ... is Ok(v)`."*
- Add a diagnostic test pinning the improved message without breaking existing `e0074` cases.

---

## 6. Verification Gates

Run per `~/code/mo/AGENTS.md`:
- `bash ci/check.sh gcc clang sanitize drivers static lean` (zero skips)
- `make grammar` and `make library-map`
- Fuzz smoke on `fuzz_prim`, `fuzz_syntax`, `fuzz_check`, `fuzz_lower` (5s each, 0 failures)
- Do not merge — commit cleanly and open a PR for Robert's review (or summarize exact changes and test results).
