# How does Mo's runtime become memory safe?

Type: grilling
Status: open
Blocked by: [What does porting Mo's bytecode loader and verifier to Rust cost?](23-what-does-porting-the-loader-and-verifier-to-rust-cost.md)

## Question

A database for student records runs on Mo's runtime, which is C. One memory bug there reaches the whole host. Which route does Mo take, and when?

- **Confine only.** Add operating-system confinement to `mo serve` (the sandbox design lists its absence as a gap) and keep hardening the C.
- **A memory-safe C build.** Fil-C's October 2026 trial failed (29 of 46 test programs passed, 3 of 211 golden fixtures). One reproduced cause: a pointer stored in a runtime cell and read back by value keeps its address but loses its Fil-C capability; the trial did not establish why (`~/code/mo/docs/status/mo167-filc-trial.md`). The others were stack overflows in recursive compiler paths and how `abort()` is reported.
- **The runtime in the Safe C subset.** `robertguss/safe-c` (v0.2.0) is a lint-enforced subset of C (rules R1 to R14) and a library of arenas, slices and generation-checked handles proved with Frama-C. It stays C: no second language and no boundary between two. Its lint, run on 2026-11-14 (safe-c `eebb980`, Mo `7e6bfce1`) over `src/base`, `bytecode`, `vm`, `heap`, `prim` and `host`, found 3,485 rule breaks in 115 of 133 files (40,188 lines); 2,388 of them are array subscripts. These are places to rewrite, not bugs. What it leaves open: the lint is a list of bans with no rule for unions, pointer casts, pointers to locals that escape, or uninitialised reads; only the library is proved, not the code that uses it; files under `adapters/` are not linted; no project has adopted it yet.
- **The runtime in Rust, module by module.** Loader and verifier, VM, heap, primitives, host and base are about 38,800 lines of C; the serving parts of the `mo` command add to that. The compiler (about 32,100 lines) can wait, because the VM does not trust it.
- **Everything in Rust.** About 92,100 lines of C, plus 50,200 lines of C unit tests.

Context: decision D207 chose C on 11 October 2026 for fast iteration and direct control of memory, replacing an earlier plan in Rust, and left a port open (`~/code/mo/docs/design/implementation.md`). The Lean model, the golden corpus and the black-box drivers check any implementation. Every runtime feature the database adds in C is more to port later, so this is decided before [What must Mo gain to build it?](17-what-must-mo-gain.md).

## Comments

2026-11-14: the Safe C lint count above, by module. Command, from the safe-c tree, once per module: `SAFEC_LINT_CPPFLAGS="-I<mo>/src -I<mo>/build/generated -I<mo>/vendor/sqlite -D_POSIX_C_SOURCE=200809L" python3 scripts/lint.py --verbose <mo>/src/<module>/*.c <mo>/src/<module>/*.h` (semgrep 1.185.0, clang 18.1.3; `lint.py --selftest` passed first).

| Module | Lines | Files failing | Rule breaks | Per 100 lines |
| --- | ---: | ---: | ---: | ---: |
| `base` | 4,335 | 35 of 51 | 282 | 6.5 |
| `bytecode` | 8,455 | 27 of 29 | 1,257 | 14.9 |
| `vm` | 4,394 | 10 of 10 | 476 | 10.8 |
| `heap` | 5,494 | 17 of 17 | 589 | 10.7 |
| `prim` | 11,820 | 11 of 11 | 378 | 3.2 |
| `host` | 5,690 | 15 of 15 | 503 | 8.8 |

By rule: R1 subscript 2,388; R3 `char *` 337; R6 raw array 242; R2 pointer arithmetic 223; R9 `errno` 99; R8 `goto` 89; R13 unchecked result 68; R5 `malloc`/`free` 30; R10 recursion 7; one each for R4 and narrowing. R13 matches any field named `value`, so its 68 were not inspected and may not be real.
