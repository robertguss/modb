# How does Mo's runtime become memory safe?

Type: grilling
Status: open
Blocked by: [What does a safe-Rust slice of Mo's heap and VM cost?](23-what-does-a-safe-rust-slice-of-the-heap-and-vm-cost.md)

## Question

A database for student records runs on Mo's runtime, which is C. One memory bug there gives an attacker everything the server process can reach. Which route does Mo take, and when?

- **Confine only.** Add operating-system confinement to `mo serve` (the sandbox design lists its absence as a gap) and keep hardening the C. Two stronger forms: run the runtime as its own process that receives only bytecode, or run the C inside an established sandbox. Confinement does not protect records from a compromised process that is allowed to read them.
- **A memory-safe C build.** Fil-C's October 2026 trial failed (29 of 46 test programs passed, 3 of 211 golden fixtures). One reproduced cause: a pointer stored in a runtime cell and read back by value keeps its address but loses its Fil-C capability; the trial did not establish why (`~/code/mo/docs/status/mo167-filc-trial.md`). The others were stack overflows in recursive compiler paths and how `abort()` is reported. Of the 208 golden failures, 207 were that one trap, so one fix may clear most of them; the cheapest next step is rerunning the trial's cell round trip on a current Fil-C.
- **The runtime in the Safe C subset.** `robertguss/safe-c` (v0.2.0) is a lint-enforced subset of C (rules R1 to R14) and a library of arenas, slices and generation-checked handles proved with Frama-C. It stays C: no second language and no boundary between two. Its lint, run on 2026-11-14 (safe-c `eebb980`, Mo `7e6bfce1`) over `src/base`, `bytecode`, `vm`, `heap`, `prim` and `host`, found 3,485 rule breaks in 115 of 133 files (38,637 non-blank lines); 2,388 of them are array subscripts. These are places to rewrite, not bugs. What it leaves open: the lint is a list of bans with no rule for unions, pointer casts, pointers to locals that escape, or uninitialised reads; only the library is proved, not the code that uses it, and its slice proofs assume storage that is valid, which the lint does not establish (`include/safec/slice.h`: "it does not validate arbitrary or dangling C pointers"); files under `adapters/` are not linted; no project has adopted it yet.
- **The runtime in Rust, module by module.** Loader and verifier, VM, heap, primitives, host and base are about 38,800 lines of C; the serving parts of the `mo` command add to that. The compiler (about 32,100 lines) can stay in C only if its process is confined: the VM verifies its bytecode, but the compiler child keeps the server's user and environment (`src/host/compile.c`), so a compromised compiler has the server's access to the operating system.
- **One Rust runtime, cut at the bytecode file.** The compiler stays C and runs as a separate confined process that writes a bytecode file; a Rust program loads, verifies and runs it. No code crosses between the two languages. The whole runtime and the serving parts of `src/tools` move at once. The case for it over module by module: about 1,050 calls reach into the heap from `tools`, `prim`, `host` and `vm`, passing untagged 16-byte cells, and each would be an unsafe crossing.
- **Everything in Rust.** About 92,100 lines of C, plus 50,200 lines of C unit tests.

Context: decision D207 chose C on 11 October 2026 for fast iteration and direct control of memory, replacing an earlier plan in Rust, and left a port open (`~/code/mo/docs/design/implementation.md`). The Lean model, the golden corpus and the black-box drivers check any implementation. Every runtime feature the database adds in C is more to port later, so this is decided before [What must Mo gain to build it?](17-what-must-mo-gain.md).

## Comments

2026-11-14: the Safe C lint count above, by module. Command, from the safe-c tree, once per module: `SAFEC_LINT_CPPFLAGS="-I<mo>/src -I<mo>/build/generated -I<mo>/vendor/sqlite -D_POSIX_C_SOURCE=200809L" python3 scripts/lint.py --verbose <mo>/src/<module>/*.c <mo>/src/<module>/*.h` (semgrep 1.185.0, clang 18.1.3; `lint.py --selftest` passed first).

| Module | Lines, blanks included | Files failing | Rule breaks | Per 100 lines |
| --- | ---: | ---: | ---: | ---: |
| `base` | 4,335 | 35 of 51 | 282 | 6.5 |
| `bytecode` | 8,455 | 27 of 29 | 1,257 | 14.9 |
| `vm` | 4,394 | 10 of 10 | 476 | 10.8 |
| `heap` | 5,494 | 17 of 17 | 589 | 10.7 |
| `prim` | 11,820 | 11 of 11 | 378 | 3.2 |
| `host` | 5,690 | 15 of 15 | 503 | 8.8 |

By rule: R1 subscript 2,388; R3 `char *` 337; R6 raw array 242; R2 pointer arithmetic 223; R9 `errno` 99; R8 `goto` 89; R13 unchecked result 68; R5 `malloc`/`free` 30; R10 recursion 7; one each for R4 and narrowing. R13 matches any field named `value`, so its 68 were not inspected and may not be real. `prim` looks low only because 8,877 of its lines are the generated table `unicode16-data.h`; the hand-written 2,943 lines break the rules 12.6 times per 100 lines.

2026-11-14, later: Robert asked for an outside opinion from a model of another provider (GPT-6 Astra, given the routes without any recommendation). Its answer: confine the server and the compiler now; run the prototype on a heap-and-VM slice, not the loader; no full rewrite yet; Safe C is not a demonstrated route to memory safety today; Fil-C deserves a small retry; keep identifiable student records off the system until the institution authorises it and an outside review is done. Its corrections were checked against the code and are folded into the routes above and into the prototype ticket.

2026-11-14, third view: a second outside model (Gemini 4 Carbon) reviewed the same question after reading the first review. Its claims below were checked against the code unless marked.

- Its answer: confine now; skip the Rust prototype; port the whole runtime to Rust at Phase 7, cut at the bytecode file, and only after the first slice is in daily use and before any student records; no Safe C, no module-by-module port.
- Why skip the prototype: Mo's values are immutable and the heap never holds a cycle (`~/code/mo/docs/design/bytecode.md`, "the heap stays acyclic"), the case safe Rust's shared pointer already covers. What is unknown is speed and memory, and what the boundary costs, which a small slice does not measure.
- Why Phase 7: that phase adds machine-code generation (`docs/design/implementation.md`), so the runtime's execution changes then anyway.
- The C the ticket left out: vendored SQLite runs in the server's process, 271,131 lines in `sqlite3.c`, about seven times the runtime. Mo sends it only fixed statements, so less of it is reachable than that count suggests, but a Rust runtime alone does not make the server memory safe.
- Reachable without a token: the request's headers are parsed by Mo code in the VM before the token is checked (`src/tools/protocol-request.c`, `authenticate` calls `headers` first).
- Tokens are read with `getenv` and never removed from the environment, and the compiler child is started with `execv`, which passes the environment on.
- Fuzz targets added since 18 October 2026 have had only smoke runs (`docs/design/architecture.md`).
- Not checked by anyone: its explanation of the Fil-C failure, that a cell made of 16 bytes is returned in integer registers and so loses the pointer's capability, and its proposed test of a cell that holds a real pointer field.
- Safe C's handle table retires a slot for good after 65,535 reuses and finds a free slot by scanning (`stdlib/handle.c`), and its arena cannot free one object, so Mo's heap would not fit it.

The three views agree on confining now, on no rewrite now, on not using Safe C and on keeping student records off. They differ on whether to prototype and on the shape and timing of a port.

2026-11-14, reopened by Robert: with no hurry, and with the database's own storage engine now certain, he asked whether the Rust rewrite is back on the table. What that changes:

- The engine is written in Mo, so its own logic is memory safe on any runtime. What it adds to the runtime is the support under it: writing bytes, reading and writing at an offset, forcing data to disk, and a fake disk that injects faults for testing. Today Mo has only whole-file `read_text`, `read_bytes`, `write_text` and `append_text` (`~/code/mo/src/base/hostops.def`). That support is offset arithmetic over raw buffers, the kind of C where memory bugs live.
- Once the engine replaces SQLite, a Rust runtime leaves no C in the server's process. With SQLite kept, a Rust runtime still left 271,131 lines of C there.
- "Usable sooner" no longer counts against a port.

What it does not change: the port is about 38,600 lines of runtime C plus the serving parts of `src/tools`, with their unit tests, fuzz targets and CBMC proofs to rebuild; its speed and memory are unmeasured; and the middle of Phase 6 is the wrong moment.
