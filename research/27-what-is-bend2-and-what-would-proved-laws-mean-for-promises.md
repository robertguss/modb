Research run on 2026-11-14 by a subagent using Exa, for the ticket [What is Bend2, and what would proved laws mean for promises?](../issues/27-what-is-bend2-and-what-would-proved-laws-mean-for-promises.md).

# What is Bend2, and what would proved laws mean for promises? (researched 2026-11-14)

Words used below:

- **Law**: Bend's name for a stated property, such as "cancelling twice equals cancelling once".
- **Proof**: a piece of code whose type is the law. If it type-checks, the law holds for every input.
- **Promise**: Mo's name for a stated property. Today `mo test` checks it on generated inputs.
- **Kernel**: a small checker that rechecks proofs. A bug outside it cannot make a false proof pass.
- **SMT solver**: a program that searches for a proof by itself. Tools built on one need hints, not hand-written proofs.

## What Bend2 is

**Name and maker.** The language is called Bend. "Bend2" means major version 2. Bend 1 source does not carry over, and Bend 1's HVM runtime is not used (https://bend2.dev/notes/what-is-bend2/; README "Limitations", https://github.com/bendlang/bend). It is made by Higher Order Company in Rio de Janeiro. The README credits Victor Taelin as creator plus a team of six; the paper names the company (README "Credits"; `bend2/docs/BendTT/main.typ` in the repository).

**Which sites are official.**

| Site | Status |
| --- | --- |
| https://bend-lang.com | Official. It is the repository's homepage and the install script's host. I observed that https://higherorderco.com serves a page identical to it. |
| https://github.com/bendlang/bend | Official repository. The old `HigherOrderCO/Bend` address redirects there (observed with `gh api`). The `bendlang` organisation was created on 2026-09-16. |
| https://bend2.dev | **Third-party.** Its own footer says: "Unofficial. Not affiliated with Higher Order Company." It is made by "viridale / priormancer". Its notes cite the official repository at pinned commits, and they matched what I found. |
| https://deliberus.com/docs/research/bend-and-deliberus/bend-hvm-status-report-2026-09-29.md | **Third-party** status report. It says "Bend 2 (launched 2026-09-17 [19]) is a new affine, dependently typed language. Its runtime, BendRT, uses no interaction nets, and Bend 1 code does not carry over." I confirmed the date (CHANGELOG: "## 2.0.0 (2026-09-17)"). I also confirmed its claim that "Both papers state that Claude models wrote them". |

**Launch and licence.** Version 2.0.0 is dated 2026-09-17 in `CHANGELOG.md`. The licence is Apache-2.0 (GitHub API; bend2.dev: "Bend's compiler and standard library are published under Apache 2.0").

**What it is.** A typed functional language that "combines dependent types with parallel execution on CPUs and GPUs. Programs state specifications as laws and prove them in the same language; the compiler checks every proof before execution" (bend2.dev, third-party). The vendor's pitch is aimed at AI agents: "With **laws**, intents can be more precise than natural language. With **proofs**, we can mechanically verify the AI implemented our prompts correctly" (README, vendor claim). A project keeps the laws in `LAWS.bend`, which "the human writes", and the proofs in `PROOF.bend`, which "the AI writes" (`guide/GUIDE.md`, "Laws and Proofs").

**What it compiles to and runs on.** It checks types and proofs, erases them, then emits one C file. That file runs on CPU threads, and on the GPU through Metal or CUDA for calls marked `!`. A second backend emits JavaScript, which runs on one core (GUIDE "Under the Hood" and "Tooling"; README "Limitations"). Values are affine: a variable is used at most once unless it is marked `+` and holds copyable data. That is how the runtime frees memory without a garbage collector (GUIDE "Quantities").

**How proofs are written.** A law has the form `law name: for x: T ... {a == b : T}`. A `def` with the same name is its proof. "Bend has no tactics: a proposition is a type, and a proof is a def of that type." `{==}` closes a goal whose two sides compute to the same thing. A recursive call is the induction step. `%e : P` rewrites using an equation (GUIDE "Laws and Proofs"). Every function must terminate, and recursion must be on a smaller piece of an input. `@unsafe` turns the check off, and the checker then refuses any proof that depends on that function (bend2.dev; GUIDE).

**How proofs are checked.** There are two checkers:

1. The default checker, `bend2/bend.ts`, is fast and "has no proof and may have bugs" (README).
2. `bend FILE --verdict` rechecks the proof with BendTT, a small kernel in `bend2/bendtt.lean`. It is written in Lean 4 and carries proofs about itself. "--verdict builds its CLI once, with Lean v4.34.0" (`AGENTS.md` in the repository). The file states eight claims, among them `Claim.consistent` ("no checked def proves False"), `Claim.halts` ("live evaluation terminates") and `Claim.adequate` ("a checked law's proof on closed values makes its sides convert").

   I observed that on this machine, Lean 4.34.0 compiled the shipped `bendtt.lean` (4,043 lines, 235 theorems) without complaint. A grep found no `sorry` and no `axiom`, so Lean has checked those proofs.

   The theory allows `Type : Type`, which Lean, Rocq and Agda forbid because it can prove false. It stays consistent, the paper argues, because only code that runs is checked for termination and only that code counts as evidence ("BendTT allows both and is consistent. The reason is that the code that runs is affine", `bend2/docs/BendTT/main.typ`; vendor claim backed by the Lean proof).

**What the proof does not cover**, in the vendor's own words:

- "`--verdict` checks the translated terms, the parser and translation into the kernel are not proven" (README).
- "The compiler (not kernel) is 99% AI-written and not yet fully audited" (README).
- "a compiler bug can still miscompile a proved source program" (bend2.dev).
- Foreign C or JavaScript code "cannot appear in a proved law, nor does a source proof verify the external database or network" (bend2.dev).
- "F32 is axiomatic: nothing about floating point can be proven" (README).

## Maturity and limits

**Activity** (observed with `gh api` on 2026-11-14):

- 41 releases from 2.0.0 on 2026-09-17 to 2.0.40 on 2026-11-06.
- 1,296 commits since 2026-09-01, 265 of them since 2026-10-14. The last push was 2026-11-13.
- 585 issues opened since launch, 101 of them open.
- 25,031 stars. The repository was created in 2023 for Bend 1 (the third-party report says it "is now bendlang/bend and holds Bend 2"), so most of those stars are probably Bend 1's (inference).

**Age.** Eight weeks. The README ends: "BEND IS YOUNG. EXPECT BUGS AND REPORT THEM."

**Limits the vendor lists** (README "Limitations"; `WONTFIX.txt`), the ones that matter here:

- "Everything is annotated and nothing is inferred, so code is verbose."
- "Bend has no tactics or proof search; proving theorems takes extra effort."
- "Computed matches (`match f(x)`) aren't supported." There is no if-then-else. Mutual recursion is not allowed.
- Numbers are `Nat`, `U32` and `F32` only, with no 64-bit types. `Nat` is capped at 2^48−1 in native code.
- "Strings are linked lists of characters"; Base is small; there is "No TLS, HTTP library, JSON or regex".
- "No test framework", "no debugger, profiler or REPL".
- "One GPU per program, one event loop, and no multi-machine execution yet."

**AI authorship.** The BendTT paper's disclosure: "This paper was written by Claude Opus 5.5 from the author's code and design choices ... The Lean mechanization was human-specified, AI-proven, and verified by a computer." The BendRT paper names "Claude Fable 5.1" (`bend2/docs/*/main.typ`). The repository's `AGENTS.md` says the checker `bend.ts` "is human-written: do not edit it".

**Soundness record.** The team offers a bounty for a file where `--verdict` prints ALL PROOFS CHECK "but the file contains a proof of Empty". Empty is the type with no values, so such a file would prove something false. The bounty covers translation bugs as well as kernel bugs (maintainer comment on https://github.com/bendlang/bend/issues/1482).

Issue #1482 is instructive. A reporter got `--verdict` to accept `{(3n * 0n+0n + 5n : Nat) == 15n : Nat}`. The maintainers answered that it is not unsound: "Bend proves a true fact about the program as it was parsed". `0n+` glued without a space means "0 plus everything after it". A proof proves the law as the machine reads it, which may not be what the writer meant.

Issue #1167 records the two checkers disagreeing: the default checker accepted a recursion that the kernel refused.

**Independent reception.**

- A SPARK user rebuilt the vendor's flagship demo in SPARK/Ada. SPARK's tool proved the same two properties automatically ("Success: all checks proved (12 checks)"). The Bend demo needed 58 lines of laws and "442 lines of code to prove those simple properties" (https://blog.liampwll.com/posts/bend_vibe_coding/, 2026-09-18).
- A developer who ported a Rust tool found the proof gate rejected an injected off-by-one that the sample tests missed. It cost "93 lines of laws and proofs to guarantee two simple facts about a guard of some 30 lines ... because Base ships no Nat lemmas". The author also reports the vendor saying "We need a mathlib!" (https://akitaonrails.github.io/en/2026/09/19/new-ai-language-just-released-bend-2/).
- The same article reports a published critique: Bend's checker-speed comparison with Lean and Rocq is "misleading" because Bend skips the elaboration and inference those tools spend their time on. I did not read that critique itself.

## What happened when I tried it

Everything ran on this machine (Linux x86-64), inside the scratch folder.

**Install.** I read `https://bend-lang.com/install.sh` first (99 lines). It downloads a release archive from GitHub, checks it against a SHA-256 written into the script, and moves it under `$BEND_HOME` (default `~/.bend`). It uses no sudo and edits no shell file. It says the installed `bend` contacts bend-lang.com once a day unless `BEND_NO_TELEMETRY=1` is set. I ran:

```sh
BEND_HOME=$SCRATCH/bend-home BEND_NO_TELEMETRY=1 sh install.sh
```

It took 1.9 s and installed Bend 2.0.40: a 95 MB executable plus `bend2/` and `guide/`.

**One install problem, found and undone.** `bend FILE --verdict` ignores `BEND_HOME` and builds its kernel into `~/.bend/bendtt/<hash>/` (`kernel_bin()` in `bend2/safe.ts`, which uses `os.homedir()`). It found Lean 4.34.0 under `~/.elan`. That is the same Lean version Mo pins in `formal/lean-toolchain`, so it was already installed. On first use it compiled the kernel, which took 61 s. `~/.bend` did not exist before, so I deleted it.

After that I built the kernel by hand inside the scratch folder: `lean -c` took 43 s and `leanc -O3` took 10 s. Every later run set `BENDTT` to that binary and `HOME` to a scratch folder. I checked afterwards that `~/.bend` was gone. As a check that `--verdict` really calls the kernel, setting `BENDTT=/nonexistent` made it fail with "BendTT infrastructure: ENOENT".

**The documented example.** I ran the `cancel_idempotent` example, copied exactly from bend2.dev.

| Command | Output | Time |
| --- | --- | --- |
| `bend order.bend` | `ALL PROOFS CHECK` / `Use --verdict for mathematical validity.` | 0.27 s |
| `bend order.bend --check-only` | the same | 0.27 s |
| `bend order.bend --verdict` | `ALL PROOFS CHECK` | 61 s the first time (kernel build), 0.14 to 0.5 s afterwards |

The same page points out a weakness of this law: an identity function, or one that zeroes every order number, "also passes" (bend2.dev). A law only rules out what it says.

**Law (a), first form: `narrow` clears one field of a record.** Bend has no records of varying shape, so "removes a field" became "sets the field to None". Two runs, 6 s apart. The final code:

```python
import Base

type Student is Data:
  Student{id: U32, grade: U32, secret: +Maybe<U32>}

def narrow(s: Student) -> Student:
  match s:
    case Student{id, grade, secret}:
      Student{id, grade, None{}}

law narrow_idempotent:
  for s: Student
  {narrow(narrow(s)) == narrow(s) : Student}

def narrow_idempotent(s):
  match s:
    case Student{id, grade, secret}:
      {==}
```

The one error came from writing `Maybe<U32>`. That is a non-copyable kind, and a copyable record cannot hold it:

```
- expected : Data
- observed : Type
Location: Student
4>|   Student{id: U32, grade: U32, secret: Maybe<U32>}
```

The fix was `+Maybe<U32>`. The proof is one line, because both sides compute to the same record. `--verdict` passed in 0.16 s.

**Law (a), second form: `remove` drops a key from a list of (key, value) fields.** This is closer to a view that hides a field, and it needs a real proof by induction. Four runs over 16 s, then `--verdict` passed in 0.17 s. The final code:

```python
import Base

type Field is Data:
  Field{key: U32, val: U32}

def keep(b: Bool, p: Field, rest: +List<Field>) -> +List<Field>:
  match b:
    case True{}:
      rest
    case False{}:
      p <> rest

def remove(+k: U32, xs: +List<Field>) -> +List<Field>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{p, t}:
      match p:
        case Field{+key, val}:
          keep(U32.is_eq(k, key), Field{key, val}, remove(k, t))

law keep_step:
  for b: Bool
  for +k: U32
  for +key: U32
  for +val: U32
  for +r: +List<Field>
  for e: {U32.is_eq(k, key) == b : Bool}
  for ih: {remove(k, r) == r : +List<Field>}
  {remove(k, keep(b, Field{key, val}, r)) == keep(b, Field{key, val}, r) : +List<Field>}

def keep_step(b, k, key, val, r, e, ih):
  match b:
    case True{}:
      ih
    case False{}:
      %Equal.sym(Bool, U32.is_eq(k, key), False{}, e) : {keep(_, Field{key, val}, remove(k, r)) == Field{key, val} <> r : +List<Field>}
      %ih : {Field{key, val} <> remove(k, r) == Field{key, val} <> _ : +List<Field>}
      {==}

law remove_idempotent:
  for +k: U32
  for xs: +List<Field>
  {remove(k, remove(k, xs)) == remove(k, xs) : +List<Field>}

def remove_idempotent(k, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{p, +t}:
      match p:
        case Field{+key, val}:
          keep_step(U32.is_eq(k, key), k, key, val, remove(k, t), {==}, remove_idempotent(k, t))
```

The errors, in order:

1. `expected : a fresh name (duplicate declaration: Pair)`. Base already has `Pair`, so I renamed it.
2. `observed : key (consumed more than once)`. A value used twice needs `+`.
3. `observed : t (consumed more than once)`, the same rule, this time inside the proof.

How the proof had to be written: Bend cannot match on a computed value such as `U32.is_eq(k, key)`. So the comparison goes into a helper (`keep`) that matches on a parameter. The proof then needs a separate lemma (`keep_step`) that takes the comparison's result `b` together with an equation `e` saying what it equals. Inside, it rewrites twice. The function is 8 lines; the proof is 28. The two rewrites passed on their first attempt, once the copy markers were right.

A wrong version: I changed `remove` to drop only the first matching field, which is not idempotent when a key appears twice. The checker refused it, but the message describes a proof step that no longer fits:

```
- expected : {keep_first(Cmp.is_eq(U32.cmp(k, key)), Field{key, val}, r, k) == Field{key, val} <> r : List<&2, Field>}
- observed : {keep(Cmp.is_eq(U32.cmp(k, key)), Field{key, val}, remove(k, r)) == Field{key, val} <> r : List<&2, Field>}
```

It gives no input that breaks the law. A failed proof does not say whether the law is false or only the proof is wrong.

**Law (b): add an item only while the list is shorter than a limit; the result is never longer than the limit.** As worded, this law is false. A list that is already longer than the limit comes back unchanged, so the result is longer than the limit. Bend could not tell me so. With `?goal` it printed what had to be shown, and nothing more:

```
- expected : {Cmp.is_le(Nat.cmp(List.length(&2, U32, push(Cmp.is_lt(Nat.cmp(List.length(&2, U32, xs), limit)), x, xs)), limit)) == True{} : Bool}
- observed : ?goal
```

I added the assumption the law needs: the input list is already within the limit. The corrected file checked on its first run, 17 s after the false version, and `--verdict` passed in 0.16 s. Base has no lemma for "if n < m then n + 1 ≤ m", so I wrote one (`lt_succ_le`), together with a lemma that False is not True (`false_ne_true`). The function is 9 lines; the laws and proofs are 56. The final code:

```python
import Base

def push(b: Bool, x: U32, xs: +List<U32>) -> +List<U32>:
  match b:
    case True{}:
      x <> xs
    case False{}:
      xs

def add_bounded(limit: Nat, x: U32, +xs: +List<U32>) -> +List<U32>:
  push(Nat.is_lt(List.length(&2, U32, xs), limit), x, xs)

def BoolDisc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

law false_ne_true:
  for e: {False{} == True{} : Bool}
  Empty

def false_ne_true(e):
  %e : BoolDisc(_)
  Unit{}

law lt_succ_le:
  for +n: Nat
  for +m: Nat
  for e: {Nat.is_lt(n, m) == True{} : Bool}
  {Nat.is_le(1n+n, m) == True{} : Bool}

def lt_succ_le(n, m, e):
  match n m:
    case 0n 0n:
      Empty.absurd({Nat.is_le(1n, 0n) == True{} : Bool}, false_ne_true(e))
    case 1n+p 0n:
      Empty.absurd({Nat.is_le(2n+p, 0n) == True{} : Bool}, false_ne_true(e))
    case 0n 1n+q:
      match q:
        case 0n:
          {==}
        case 1n+r:
          {==}
    case 1n+p 1n+q:
      lt_succ_le(p, q, e)

law push_step:
  for b: Bool
  for +limit: Nat
  for x: U32
  for +xs: +List<U32>
  for e: {Nat.is_lt(List.length(&2, U32, xs), limit) == b : Bool}
  for h: {Nat.is_le(List.length(&2, U32, xs), limit) == True{} : Bool}
  {Nat.is_le(List.length(&2, U32, push(b, x, xs)), limit) == True{} : Bool}

def push_step(b, limit, x, xs, e, h):
  match b:
    case True{}:
      lt_succ_le(List.length(&2, U32, xs), limit, e)
    case False{}:
      h

law never_longer:
  for +limit: Nat
  for x: U32
  for +xs: +List<U32>
  for h: {Nat.is_le(List.length(&2, U32, xs), limit) == True{} : Bool}
  {Nat.is_le(List.length(&2, U32, add_bounded(limit, x, xs)), limit) == True{} : Bool}

def never_longer(limit, x, xs, h):
  push_step(Nat.is_lt(List.length(&2, U32, xs), limit), limit, x, xs, {==}, h)
```

A first-run pass made me suspicious, so I broke it three ways. All three were refused, in about 0.14 s each:

1. Claiming `{==}` where the assumption `h` was needed gave `expected : Cmp.is_le(Nat.cmp(List.length(&2, U32, xs), limit))`, `observed : True{}`.
2. Dropping the assumption from the law and leaving a hole gave `observed : ?h`, with the missing fact as `expected`.
3. Making the code wrong (`is_le` for `is_lt`, which allows one item too many) gave a message that the proof no longer matches the code. It gave no failing input.

**Times, honestly read.** From starting the install to the last passing law took about 6.5 minutes. One minute of that was the kernel build. The writing was done by an AI agent with the guide and Base open. A person new to this style of proof would take far longer (inference). Checking was always fast: 0.13 to 0.5 s per file, `--verdict` included, once the kernel was built.

**The same two promises in Mo, for comparison** (observed; `~/code/mo/build/gcc/debug/mo test`, files in the scratch folder, nothing in the Mo repo changed):

- `remove` written with `xs.filter(...)`, with the promise `remove(k, result) == result`, passed in 0.13 s.
- `add_bounded` with the promise `result.size <= limit` failed in 0.12 s with `input limit = -1`, `input xs = []`, `result: []`. That is a case I had not thought of; Bend's `Nat` type rules it out.
- Ruling out negative limits (`limit < 0 or result.size <= limit`), it failed again with `input limit = 0`, `input xs = [0]`, `result: [0]`. That is exactly the "already too long" case, as a concrete input.
- With the corrected promise (`xs.size > limit or result.size <= limit`), it passed.
- **The wrong "first match only" `remove` passed `mo test`.** An added example row with two fields of key 1 failed (`left: []`, `right: [Field(key: 1, val: 2)]`), so the function really is wrong. The generator never produced a list where the same key appears twice. `--seconds 20` did not help, because the plan is fixed. `--calls 100000` ended with E1404, "the promise's monotonic deadline expired", without a verdict. The proof refused this same bug.

## Tested promises against proved laws

**What a tested promise gives.** Mo's promise is checked on many generated inputs, "boundaries first", and a failure is shrunk to a small input (reference 12.2, `~/code/mo/docs/reference/README.md`). Its strengths, seen above:

- It costs nothing beyond the promise itself.
- It works on today's ordinary Mo code.
- A failure comes with a concrete input. For `add_bounded` it found two different problems in a quarter of a second, one of which I had missed.
- It checks the promise's own wording against its `allows` and `forbids` rows, "which catches a body that doesn't say what its sentence says".

Its weakness is what it never generates. Here a duplicate key slipped through. The project's own survey says the same of deterministic simulation: it "misses ... whatever the generator never produces" ([map.md](../map.md), decision on correctness-first databases).

**What a proof adds.**

- It holds for every input, not a sample. The duplicate-key bug cannot slip through.
- It forces every assumption into the open. Law (b) could not be proved until "the list starts within the limit" was written down. Testing found the counterexample, but did not make me write the assumption.
- Once written, it is checked again on every edit, in well under a second. An agent can be made to keep it.

**What a proof costs.**

- Writing it. Here a proof was 3 to 6 times the size of the function. That matches the outside reports: 442 proof lines for the game demo, 93 for a 30-line guard. Every missing lemma has to be proved by hand.
- No counterexample on failure. "Refused" can mean the law is false, the proof is wrong, or the proof no longer fits code that changed.
- Code has to be bent to suit the prover. There are no computed matches, helpers stand in for `if`, and copies are marked by hand.
- It proves the law as written and parsed. A weak law passes wrong code (the identity function passes `cancel_idempotent`). A surprising parse proves something other than what was meant (#1482).
- It trusts more than the kernel: the parser, the translation and the compiler, none of which is proved (README).

**Which kinds of promise could realistically be proved** (inference, from what I saw):

- Properties of a pure function over its inputs, like both laws here. Mo promises on ordinary functions have exactly this shape.
- Properties over *every sequence of steps* of a pure step function. Bend's flagship law quantifies over `moves: List<Game.Move>` and replays them from the start (README). A Mo service's tool is already such a function, "from the old state, the time and its arguments to a new state and a reply" ([design-ideas.md](../design-ideas.md)). So a step promise such as "the count never falls" is provable by induction over sequences, if it holds after every step on its own. Proving that every sequence keeps it is something tests cannot do.
- Claims about the language itself that hold for every program, which Mo already proves in Lean for Mo Core.

**Which could not, or not realistically.**

- Promises about data on disk, crashes and recovery. The disk, SQLite and the C host sit outside any proof, as foreign code does in Bend ("nor does a source proof verify the external database or network", bend2.dev). They can be modelled and the model proved, but the real code is then only compared with the model, as Cedar does (https://www.amazon.science/blog/how-we-built-cedar-with-automated-reasoning-and-differential-testing).
- Promises about time across interleaved callers, liveness ("eventually"), and protocols with crashes in the middle. Bend has no way to state these. Tools that do (TLA+, or Verus's TLA embedding used by Anvil) are built for it.
- Anything about floating point in Bend ("F32 is axiomatic", README), and anything about speed or memory.
- Whether the promise says what its owner means. No proof tool checks that, and Mo's `allows`/`forbids` rows and `--strength` aim at exactly that gap.

## Other languages with proved properties

| Language | What it proves | How automatic | Real use |
| --- | --- | --- | --- |
| Dafny | Code meets its pre- and postconditions | Mostly automatic: a solver finds the proof, the author adds hints | AWS authorization engine; Cedar's first model |
| Verus | Rust code meets its specification for every run | Mostly automatic, through solvers | Microsoft and Amazon (vendor claim); Anvil's Kubernetes controllers |
| F* | Code meets types that carry properties | "Automated proofs" plus manual steps | HACL* crypto in Firefox and Linux; EverParse in Hyper-V |
| Lean 4 | Anything stated as a theorem | Tactics search for proof steps; a kernel checks the result | Cedar at AWS; Mathlib; Mo Core's model |
| Idris 2 | Types that carry properties, plus use-counting like Bend's | Written by hand, with editor help | No production use found; version 0.8.0 |
| Liquid Haskell | Haskell types narrowed by conditions | Automatic, through a solver | Checked parts of popular Haskell libraries |
| SPARK (Ada) | No runtime errors; stated correctness properties | Automatic (GNATprove) | NVIDIA products; car software at ASIL D |
| Bend 2 | Laws as equality types over pure code | Written by hand; no tactics, no search | None known; eight weeks old |

**Dafny.** A "verification-aware programming language that has native support for recording specifications and is equipped with a static program verifier". It compiles to C#, Java, JavaScript, Go and Python (https://dafny.org/). Its style is called "auto-active": the author writes specifications and hints, and a solver does the rest (title of https://www.cs.uoregon.edu/research/summerschool/summer26/_lectures/Leino_lecture1_Notes.pdf; that the solver is Z3 is from memory, not confirmed). AWS rebuilt its authorization engine, "invoked 1 billion times per second", in Dafny over four years and compiled it to Java (https://www.amazon.science/publications/formally-verified-cloud-scale-authorization). Cedar's authorizer model in Dafny had "about one-sixth as many lines of code as the production code". It was compared with the Rust implementation by differential random testing (https://www.amazon.science/blog/how-we-built-cedar-with-automated-reasoning-and-differential-testing).

**Verus.** It "statically checks that the executable Rust code will always satisfy the specifications for all possible executions", relying "on powerful solvers to prove the code is correct". It covers "a subset of Rust" and is "under active development" (https://github.com/verus-lang/verus). Vendor claim: "it is already seeing industrial use at Microsoft and Amazon, and two of three best papers at OSDI 2024 are built on Verus" (https://verus-lang.github.io/event-sites/2024-sosp/). Anvil uses it to prove that Kubernetes controllers "eventually make the cluster state match its desired state", a liveness property, and the controllers "can be deployed in real-world Kubernetes clusters" (https://github.com/anvil-verifier/anvil).

**F\*.** "A proof-oriented language & verification framework" with "Dependent types. Refinements. Automated proofs." It extracts to OCaml, F# and C (https://fstar-lang.org/). That it uses an SMT solver plus tactics is from memory, not confirmed on that page. HACL* is "formally verified using the F* verification framework for memory safety, functional correctness, and secret independence" (https://github.com/hacl-star/hacl-star). F*'s site says "HACL* supplies verified cryptography for Firefox's NSS security engine", "HACL* supplies Curve25519 code used by WireGuard in the Linux kernel", and "EverParse-generated parsers validate messages in the Hyper-V virtual networking stack" (vendor claims). HACL* is now "in maintenance mode".

**Lean 4.** A proof assistant and programming language. Its `simp` tactic "searches a lemma database and constructs a kernel-checked proof term automatically" (bend2.dev, third-party, citing https://lean-lang.org/doc/reference/latest/The-Simplifier/). AWS: "Lean is the core verification technology behind Cedar, the open-source authorization language that powers cloud services like Amazon Verified Permissions and AWS Verified Access". Mathlib has "over a million lines of formalized mathematics" (https://lean-lang.org/). Mo already uses Lean: a model of Mo Core with 238 theorems, against which the C VM is tested ([design-ideas.md](../design-ideas.md)).

**Idris 2.** "A new version of the dependently typed language Idris, with a new core language based on QTT, supporting linear and dependent types". QTT, quantitative type theory, tracks how many times each value is used, as Bend's quantities do (https://arxiv.org/abs/2104.00480). Proofs are written as programs, with help from the editor; I found no automatic prover. The latest release is v0.8.0 (2025-10-31, observed with `gh api`). I found no production user.

**Liquid Haskell.** It "refines Haskell's types with logical predicates that let you enforce important properties at compile time" (https://ucsd-progsys.github.io/liquidhaskell/). It runs as a GHC plugin with the Z3 solver (https://github.com/ucsd-progsys/liquidhaskell). The authors used it on "over 10,000 lines of Haskell code from various popular libraries, including containers, ... bytestring, text, vector-algorithms and xmonad" (https://goto.ucsd.edu/~nvazou/real_world_liquid.pdf). It is the closest relative of a promise that is checked by a solver instead of by tests (inference).

**SPARK (Ada).** It lets developers "guarantee the absence of run-time errors as well as prove functional correctness for specific requirements", and is used on NVIDIA DRIVE "for DriveOS" at "ASIL D under ISO 26262" (https://www.adacore.com/nvidia-and-adacore, vendor claim). It matters here because of the outside rebuild of Bend's demo: the same two properties were proved automatically with no proof text (https://blog.liampwll.com/posts/bend_vibe_coding/). A commenter on that thread countered that solver-based proofs "don't scale to nearly anything of interest" (reported at https://akitaonrails.github.io/en/2026/09/19/new-ai-language-just-released-bend-2/). That is a contested opinion.

**Others, from memory, not confirmed in this run.** Rocq (formerly Coq), used for the CompCert C compiler. Isabelle/HOL, used for the seL4 microkernel. Agda, a research language close to Bend in style.

## Verdict

**As a tool to model or check the database design: no.**

- The design's hard claims are protocols with interleaving and crashes, and data on disk. Bend cannot state either.
- For pure pieces, Lean does the same job with tactics, a large library and years of use, and Mo already uses it at the same version (4.34.0).
- Using Bend would mean writing the pieces again in an eight-week-old language whose limits are serious: no computed match, `U32`/`Nat`/`F32` only, no test framework, compiler 99% AI-written and unaudited.
- This confirms the note already in [design-ideas.md](../design-ideas.md).

**As a source of ideas for Mo's promises: yes, a good one, with clear warnings.** Worth borrowing:

1. **The split of who writes what.** The human writes and freezes the law; the agent writes the code and the proof; a gate refuses the change until it holds. That is Mo's Phase 6 "approving and locking promises" (reference section 15) with a stronger check behind it. The outside reports point to the hole: the agent may edit the law, so laws need "a frozen tier" (https://siliconnoon.com/bend-2-wants-ai-agents-to-prove-their-code-not-promise-it/). Mo's approval door is that tier.
2. **Two checkers: a fast everyday one and a small, slow one that has been proved.** Bend's `--verdict` and Mo's "VM compared with the Lean model" are the same idea at different levels.
3. **Laws over every sequence of steps of a pure step function.** Mo services already have that shape, so service promises are the strongest candidates for proof later (inference).
4. **Marking which proofs rest on unchecked code.** `@unsafe` and foreign code taint every law that depends on them. For Mo, a promise whose function touches a capability could be labelled as tested, never proved (inference).
5. **A cache keyed by what each check read.** Mo's promise digests already do this.

The warnings, from the hands-on work:

- A failed proof gives no counterexample, and a weak law passes wrong code. So proof should add to generated inputs, not replace them. Mo's shrunk counterexamples and anchor rows did things here that the proof could not.
- Bend's hand-written proofs are the expensive way. Where Mo does get proofs, the solver-backed style of Dafny, Verus, Liquid Haskell and SPARK would prove promises like law (b) with no proof text at all. That is my inference; I did not run those tools.

## What this means for the project

- **Keep promises tested.** Generated inputs found a counterexample I had missed and cost nothing to write. They missed one bug, a duplicate key, that the proof caught. The reference already says "Proofs come in a later version" (section 12.2), so nothing has to change now.
- **When proofs come, aim them at three kinds of promise:** promises of pure functions; step promises of services, proved over every sequence of steps; and the database's few claims for every program ("a read program cannot change data", "a narrower view never shows more"). The last are Lean statements about Mo Core, as [design-ideas.md](../design-ideas.md) already proposes.
- **Two routes for proving a user's promise** (inference; neither checked here):
  1. Translate the function into Mo Core text, which Mo's Lean model already reads, and prove the promise in Lean. This is the Cedar method.
  2. Hand simple promises to a solver, which needs no proof text.

  Writing proofs in Mo itself, the way Bend does, is the costliest route.
- **The `narrow` result is directly relevant to view functions** (idea 1 in [design-ideas.md](../design-ideas.md)). A view's idempotence is easy to prove when the view is a fixed record type: one line. It needs real induction when fields are a list. This suggests views should be typed records, not key lists (inference).
- **Promises about data on disk, crash recovery and many callers stay with TLA+ and simulation.** No language in this survey proves them about the real storage code.

## What I could not confirm

- Whether BendTT's consistency argument (`Type : Type` made safe because only running code counts) is correct beyond what the Lean proof covers. Lean accepted the file, but I did not audit that its claims say what the README says.
- The critique of Bend's checker-speed benchmarks. I read only the summary in the AkitaOnRails article, not the critique.
- Who uses Bend 2 in production. I found nobody.
- Whether Dafny, Verus, Liquid Haskell or SPARK would prove law (b) with no hints. That is from memory and inference; I did not install them.
- That Dafny and F* use the Z3 solver. This is from memory; I did not confirm it on their pages.
- The Rocq/CompCert, Isabelle/seL4 and Agda notes, which are from memory.
- Why Mo's generator never produced a repeated key, or whether another setting would. I ran only the default plan, `--seconds 20` and `--calls 100000`.
- I could not read the third-party Deliberus report directly, because its page needs JavaScript. I relied on the Exa fetch of it.
