Research run on 2026-11-14 by a subagent using Exa, for the ticket [Is Veil a good home for the protocol models?](../issues/26-is-veil-a-good-home-for-the-protocol-models.md).

# Is Veil a good home for the protocol models? (researched 2026-11-14)

Terms used below:

- **Model checker**: a program that visits every state a protocol model can reach, for a fixed small size (say two agents), and checks a property in each. TLC is the model checker for TLA+. A pass covers only that size.
- **Proof for any size**: a proof that the property holds for every number of agents and every run length, not only the sizes a checker visited.
- **Inductive invariant**: a statement that holds at the start and that every step keeps true. If one implies the property, the property holds for any size. Finding it is the human (or agent) part of the work.
- **SMT solver**: a program that decides logic questions automatically. Veil uses one called cvc5. It answers yes, no, or gives up.
- **CTI** (counterexample to induction): a state, often unreachable, in which the invariant holds but one step breaks it. It means the invariant is wrong or too weak, not that the protocol is.
- **Elaboration**: Lean reading and checking a file. In Veil, model checking and proofs run while a file is elaborated.

## What Veil is

Veil is a library for Lean 4. It adds a small language for writing a protocol as a state, a start, and named steps ("actions"), and commands that work on it: `#model_check` (a TLC-like checker), `#check_invariants` (a proof for any size through an SMT solver), `sat trace`/`unsat trace` (a symbolic search, for any size, for runs of up to a few steps), `#simulate`, `#temporal_check` (liveness), and `#updr` (a search for an invariant). The README calls it "a _foundational_ framework for (1) specifying, (2) implementing, (3) model-checking, and (4) proving safety and liveness properties of state transition systems, with a focus on distributed protocols" (https://github.com/verse-lab/veil, README at commit `1287c31d`, 2026-11-13).

It comes from the VERSE lab at the National University of Singapore and "was presented at CAV 2025. It is being actively developed and maintained" (https://lean-lang.org/use-cases/veil/, written by one of its authors, so a vendor claim). The current code is "Veil 2.0, the second major version"; Veil 1.0 is the tag `v1.0.0` (README).

The idea that matters for this project: one model is model checked like TLA+ and can also be proved for any number of agents, inside the same Lean that Mo already uses for Mo Core.

## What it needs

| Need | What I found | Source |
| --- | --- | --- |
| Lean version | `leanprover/lean4:v4.35.0` on `main` | `lean-toolchain` in the clone (observed) |
| Mo's Lean version | `leanprover/lean4:v4.34.0` | `~/code/mo/formal/lean-toolchain` (observed) |
| A Veil for Mo's version | None. Tags are `v4.22.0`, `v4.23.0`, `v4.24.0`, `v4.28.0`, `v4.35.0`; there is no `v4.34.0` | `git tag` in the clone (observed) |
| mathlib | Not needed. Veil uses a branch of lean-smt named `v4.35.0-veil-no-mathlib` | `lakefile.lean` (observed) |
| Other Lean packages | batteries, aesop, ProofWidgets4, Qq, lean-auto, lean-smt, lean-cvc5, and four from the same lab: Loom, VerifiedHAMT, Lasso, Lentil | `lake-manifest.json` (observed) |
| Solvers | cvc5 only, downloaded as a static binary by the lean-cvc5 package during the build. No z3 needed; the code has no z3 switch | observed in `.lake/packages/cvc5/` and a search of `Veil/` |
| System packages | README asks for `clang lld libc++-dev libc++abi-dev` through `sudo apt-get`. This machine has clang but not lld or libc++, and everything I tried still worked, including the compiled model checker | README; observed |
| Editor | Optional VS Code extension; everything also runs from the command line | README; observed |

Mo's `formal/` project is "Plain Lean 4 with its bundled library; no dependencies" (`~/code/mo/formal/lakefile.toml`, observed). Veil would bring eleven packages and a downloaded solver. Inference: Veil models would have to live in their own Lake project with their own Lean version, and would not share a build with `formal/` unless Mo moved to Lean 4.35 in step with Veil's tags.

## What happened when I tried it

Everything ran in the scratch folder, with elan's home set there (`ELAN_HOME=…/research-26/elan`), on an 8-core machine with 31 GB of memory.

### Install and build

```sh
git clone https://github.com/verse-lab/veil.git        # 2.5 s, 66 MB
elan toolchain install leanprover/lean4:v4.35.0        # 8 s download, 3.0 GB on disk
lake build                                             # 4 min 39 s wall, 1,120 s CPU, 1,289 jobs
```

- The build succeeded first time, with no errors. It built every dependency from source. The README says tagged releases fetch prebuilt files; I built `main`, which is not a tag, so I did not test that.
- Disk: the Lean toolchain is 3.0 GB, `.lake` is 1.8 GB (lean-auto 433 MB, own build 426 MB, cvc5 227 MB, the rest smaller). About 4.9 GB in all. TLC is one 4.5 MB jar plus Java.
- The README warns of "a sporadic issue in the build process for `lean-cvc5`". I did not hit it.

### Running an example

`lake env lean Examples/Tutorial/Ring.lean` crashed at once:

```
libc++abi: terminating due to uncaught exception of type lean::exception: Could not find native implementation of external declaration 'cvc5.TermManager.new' ...
```

`lake lean Examples/Tutorial/Ring.lean` (which loads the native solver library) worked: 36 s wall, 178 s CPU. It printed `✅ No violation (explored 256 states)`, three found traces, and a proof table with every line `✅`, then this warning:

```
warning: Trusting SMT solver for 12 goals. `set_option veil.smt.trust false` to enable proof reconstruction.
```

That warning matters; see [Checking the claims on veil.dev](#checking-the-claims-on-veildev).

### The protocol, two agents, model checked

The protocol from the ticket. `checked` is a constant the check passes in, so one file holds both the correct protocol and the one with the check at landing removed. This is the whole file:

```lean
module

public import Veil

veil module LostUpdate

enum agent = { a1, a2 }
enum phase = { idle, forked, done, gaveup }

immutable individual checked : Bool

individual balance : Int
function pc : agent → phase
function readv : agent → Int
function want : agent → Int
function retries : agent → Nat

#gen_state

after_init {
  balance := 2
  pc A := idle
  readv A := 0
  want A := 0
  retries A := 0
}

action fork (a : agent) {
  require pc a = idle
  readv a := balance
  want a := balance + (if a = a1 then 2 else 1)
  pc a := forked
}

action land (a : agent) {
  require pc a = forked
  if !checked || readv a = balance then
    balance := want a
    pc a := done
  else
    if retries a < 2 then
      pc a := idle
    else
      pc a := gaveup
    retries a := retries a + 1
}

safety [all_land_sum] (pc a1 = done ∧ pc a2 = done) → balance = 5

termination [finished] ∀ a, pc a = done ∨ pc a = gaveup

#gen_spec

#model_check { } { checked := true }

#model_check { } { checked := false }

end LostUpdate
```

It worked on the first run, `lake lean LostUpdate.lean`, 10 s wall (17 s once the file is a Lean `module`). With the check: `✅ No violation (explored 18 states)`. Without it, the lost update, exit status 1:

```
error: ❌ Violation: safety_failure (violates: all_land_sum)
  Theory:
    checked = false
  State 0 (via init):
    balance = 2
    pc = {a1 ↦ idle, a2 ↦ idle}
    readv = {a1 ↦ 0, a2 ↦ 0}
    want = {a1 ↦ 0, a2 ↦ 0}
    retries = {a1 ↦ 0, a2 ↦ 0}
  State 1 (via fork(a=a2)):
    balance = 2
    pc = {a1 ↦ idle, a2 ↦ forked}
    readv = {a1 ↦ 0, a2 ↦ 2}
    want = {a1 ↦ 0, a2 ↦ 3}
    ...
  State 2 (via fork(a=a1)):
    balance = 2
    pc = {a1 ↦ forked, a2 ↦ forked}
    readv = {a1 ↦ 2, a2 ↦ 2}
    want = {a1 ↦ 4, a2 ↦ 3}
    ...
  State 3 (via land(a=a1)):
    balance = 4
    pc = {a1 ↦ done, a2 ↦ forked}
    ...
  State 4 (via land(a=a2)):
    balance = 3
    pc = {a1 ↦ done, a2 ↦ done}
    ...
```

(`...` marks lines I cut; the tool prints every field in every state.) Without `module` at the top, the file still ran but warned "Compiled checks require Lean's module system".

### The same in TLA+

```tla
---- MODULE LostUpdate ----
EXTENDS Integers
CONSTANTS Agents, Delta, Checked, MaxRetries

VARIABLES balance, pc, readv, want, retries
vars == <<balance, pc, readv, want, retries>>

Init ==
  /\ balance = 2
  /\ pc = [a \in Agents |-> "idle"]
  /\ readv = [a \in Agents |-> 0]
  /\ want = [a \in Agents |-> 0]
  /\ retries = [a \in Agents |-> 0]

Fork(a) ==
  /\ pc[a] = "idle"
  /\ readv' = [readv EXCEPT ![a] = balance]
  /\ want' = [want EXCEPT ![a] = balance + Delta[a]]
  /\ pc' = [pc EXCEPT ![a] = "forked"]
  /\ UNCHANGED <<balance, retries>>

Land(a) ==
  /\ pc[a] = "forked"
  /\ IF ~Checked \/ readv[a] = balance
       THEN /\ balance' = want[a]
            /\ pc' = [pc EXCEPT ![a] = "done"]
            /\ UNCHANGED retries
       ELSE /\ IF retries[a] < MaxRetries
                 THEN pc' = [pc EXCEPT ![a] = "idle"]
                 ELSE pc' = [pc EXCEPT ![a] = "gaveup"]
            /\ retries' = [retries EXCEPT ![a] = @ + 1]
            /\ UNCHANGED balance
  /\ UNCHANGED <<readv, want>>

Finished == \A a \in Agents : pc[a] \in {"done", "gaveup"}

Next == (\E a \in Agents : Fork(a) \/ Land(a)) \/ (Finished /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars

Total == LET Sum[S \in SUBSET Agents] ==
               IF S = {} THEN 0 ELSE LET x == CHOOSE x \in S : TRUE IN Delta[x] + Sum[S \ {x}]
         IN Sum[Agents]

AllLandSum == (\A a \in Agents : pc[a] = "done") => balance = 2 + Total
====
```

`MC.tla` extends it with model values `a1`, `a2` and `DeltaVal == [a \in {a1, a2} |-> IF a = a1 THEN 2 ELSE 1]`; `MC.cfg` and `MCBad.cfg` differ only in `Checked = TRUE` or `FALSE`. TLC (version 2026.11.06, from the jar in the scratch folder) found 18 distinct states with the check, the same count as Veil, in about 1.4 s. Without the check it printed the same four-step lost update (a1 forks, a2 forks, a1 lands 4, a2 lands 3):

```
Error: Invariant AllLandSum is violated.
State 4: <Land(a1) line 23, col 3 to line 33, col 30 of module LostUpdate>
/\ balance = 4
/\ pc = (a1 :> "done" @@ a2 :> "forked")
...
State 5: <Land(a2) line 23, col 3 to line 33, col 30 of module LostUpdate>
/\ balance = 3
/\ pc = (a1 :> "done" @@ a2 :> "done")
```

Effort was about the same: 58 lines of Veil against 51 of TLA+. The Veil text reads more like code (assignments, `if`), the TLA+ like logic (primes, `UNCHANGED`). In TLA+ I had to write the sum of all deltas by hand; in Veil I wrote the target, 5, directly.

### More agents: speed

I made the agents a type of any size, `type agent`, with `delta a = a + 1` and the target total passed in, and ran both tools on 3 to 6 agents. State counts agree exactly, which is a good sign that the two models mean the same thing.

| Agents | Distinct states (both) | TLC, 8 workers | Veil, whole file |
| --- | --- | --- | --- |
| 3 | 239 | 0.5 s | 3, 4 and 5 agents plus one failing check in one file: 28 s |
| 4 | 5,652 | 0.6 s | (in the line above) |
| 5 | 189,317 | 1.4 s | 10 to 12.5 s (interpreted, compiled, or the default of both) |
| 6 | 7,909,534 | 18 s, 3.6 GB peak memory | 38 s compiled, 44 s default, about 1.4 to 1.6 GB peak |

An empty Veil file with this model and no checks takes 5.5 s, so that much of each Veil time is fixed. The compiled checker built a 120 MB program in `.lake/model_checker_builds/`. These are single runs on one machine (observed), not a benchmark.

### Proving it for any number of agents

"When all have finished, balance = 2 + the sum of every delta" is a sum over an unknown number of agents. Veil's automatic proofs work in "decidable fragments of first-order logic" (README), and such a sum is outside that (inference). So I added a ghost field, `expected`, which the landing step raises by the agent's delta, and proved `balance = expected` in every reachable state. When all agents are done, `expected` is 2 plus every delta by its construction, which gives the property. For two agents with deltas 2 and 1 that is 5.

The changes from the two-agent file: `type agent` instead of the enum, `immutable function delta : agent → Int`, `individual expected : Int` set to 2 at the start, `expected := expected + delta a` when landing, no `checked` flag (the check is always there), and this end:

```lean
safety [no_lost_update] balance = expected
invariant [want_is_read_plus_delta] pc A = forked → want A = readv A + delta A

#gen_spec

prove_veil_invariant_goal initializer want_is_read_plus_delta using wp by
  have h := phase_Enum.distinct; simp [distinctN, andN, distinctPairs] at h; simp_all

#check_invariants
```

What happened:

1. Without the hand proof, 8 of the 9 checks passed automatically in 5 s. One failed with an unhelpful message: `want_is_read_plus_delta ... 💥 Exceptions: ... cannot translate Type`. That was the start-state check, which is trivially true (every agent starts `idle`, so none is `forked`). Veil offered a stub to paste in, `prove_veil_invariant_goal initializer want_is_read_plus_delta using wp by sorry`.
2. `simp_all`, `grind` and `aesop` each failed. The goal left was `idle = forked → 0 = th.delta A`: Lean did not know that two enum values differ. I found the name of that axiom (`distinct`) by reading `Veil/Frontend/DSL/Module/Util/Enumeration.lean`; no document gave it. With it, the one-line proof above worked. Every check then showed `✅`. That file took 46 s instead of 5 s; I did not find out why.
3. By default the solver's answers for 4 goals were trusted, not checked. With `set_option veil.smt.trust false` at the top of the file, the warning went away and the run took the same 46 s (observed). I read that as all four answers being turned into Lean proofs and checked by Lean's kernel; I did not inspect the proof terms.
4. With the check at landing removed, the proof failed where it should, with a CTI:

```
  land
    no_lost_update ... ❌
      Counterexample (TR):
        Theory:
          delta = {0 ↦ -1}
        Pre-state:
          balance = 0
          expected = 0
          pc = {0 ↦ forked}
          readv = {0 ↦ 1}
          want = {0 ↦ 0}
        Action: land(a=0)
        Post-state:
          balance = 0
          expected = -1
```

This pre-state cannot happen (an agent's read is always a balance it saw). A CTI says the step does not keep the invariant, not that this run is reachable, so a reader has to be taught the difference.

5. I then tried a symbolic search for any number of agents, `sat trace [lost_update] { any 4 actions; assert (balance ≠ expected) }`, on the broken version. It failed with `Verification error` and `cannot translate 2` (with the start values set to 0 instead: `cannot translate 0`). Changing `retries` from `Nat` to `Int` did not help. The tutorial's own traces worked. Inference: the solver translation does not handle something in my model, perhaps the start values of the function fields. I stopped there, at the 30-minute limit.

How far I got: a kernel-checked proof that no update is lost for any number of agents, any deltas and any run length, in about 15 minutes, with one hand-written line that needed Veil's source code. The retry limit plays no part in that proof. Not done: the property written as a sum, and a symbolic bug search for any size.

## Checking the claims on veil.dev

| Claim on https://veil.dev/ (vendor claims) | What I saw |
| --- | --- |
| "specifying, model checking, and proving safety and liveness properties" | Safety: model checking and proof both worked. Liveness: not tried. |
| "Veil also ships agent skills for AI coding agents, for example to translate existing TLA+ specifications" | True. One skill, `.agents/skills/tla-to-veil/SKILL.md` (64 lines plus three reference files), on translating TLA+ to Veil and checking against TLC. None for writing a model from scratch. The repository's `.claude/CLAUDE.md` is for people changing Veil itself. |
| "Find bugs with concrete and symbolic model checking … or with random simulation" | Concrete: worked, and agreed with TLC on every state count. Symbolic: worked on the tutorial, failed on my model with `cannot translate`. Simulation: not tried. |
| "Visualise execution traces and counterexamples directly in the Lean InfoView" | Not tried (no editor). On the command line the traces are plain text and easy to read. |
| "Prove safety properties with push-button automation … When default automation isn't enough, use Lean's full tactic language" | 8 of 9 checks were push-button; the ninth needed one line of Lean, found by reading the source. |
| "Interactively discover inductive invariants with Veil's powerful counterexample to induction (CTI) generator, or synthesise them automatically with UPDR" | CTIs: yes, shown above. UPDR: not tried. |
| "Write and verify protocols directly in your browser" (https://try.veil.dev/) | Not tried. |
| "proofs produced by external solvers are checked by Lean's kernel" (https://lean-lang.org/use-cases/veil/) | Only if you ask. The default is `veil.smt.trust : Bool := { defValue := true` (`Veil/Base.lean`, observed), and the tool warns that it trusted the solver. With it off, my proof still went through. |

## Veil against TLA+ for this project

| | TLA+ with TLC | Veil |
| --- | --- | --- |
| Install | One 4.5 MB jar and Java; Mo's CI pins TLC v1.8.0 by digest (`~/code/mo/ci/check_models.py`) | Lean 4.35 (3.0 GB) plus 1.8 GB of packages; 4 min 39 s first build on 8 cores; solver downloaded during the build |
| Fits Mo's Lean | Not Lean | Needs Lean 4.35; Mo pins 4.34; no Veil tag for 4.34; would be a separate Lake project |
| Model check a fixed size | Yes; about 2 times faster here at 7.9 million states | Yes; same state counts; 5.5 s fixed start-up per file |
| Proof for any number of agents | Not with TLC. TLA+ has a separate prover, TLAPS (from memory, not confirmed in this run) | Yes, through cvc5, and checkable by Lean's kernel; worked here with one line by hand |
| Bug search for any size | No | `sat`/`unsat trace`; failed on my model |
| Counterexample | Numbered states, each with every variable and the action with its line number | Numbered states, each with every field as a map and the action with its arguments; also CTIs for failed proofs |
| Exit status for CI | Not checked in this run | 1 on a violation or an undischarged check, 0 when all pass (observed) |
| Same language as other Lean work | No | Yes; a model and a Lean theorem about Mo could, in principle, sit side by side (inference) |
| Age | First released in 1999 (from memory, not confirmed) | Repository created 2025-02-01; 2.0 is current; first GitHub release 2026-11-07 |
| What an agent knows already | A lot of public TLA+ (inference) | Little; leans on the shipped docs and examples (inference) |
| Error messages | Not tested for failures | Mostly clear; `cannot translate Type` and `cannot translate 0` were not |

## Maturity

- **Papers.** CAV 2025 ("Veil: A Framework for Automated and Interactive Verification of Transition Systems"); POPL 2026 on Loom, its foundation ("Foundational Multi-Modal Program Verifiers"); a Dafny Workshop 2026 paper; two more "In submission. 2026", including "Engineering a Certified Model Checker with Class" (https://veil.dev/publications/). The Lasso model checker, a Veil dependency, is described by its author as "built from the start to match TLC on performance", with "A paper on the work … currently under submission" (https://arbenitkamberi.github.io/projects/01_NUS/, vendor claim).
- **Releases.** Tags `v1.0.0` (2025-02-01), `cav25-artifact` (2025-04-14), then tags named after Lean versions: `v4.22.0` (2025-09-08), `v4.23.0` (2025-10-22), `v4.24.0` (2025-11-28), `v4.28.0` (2026-08-13), `v4.35.0` (2026-11-07). One GitHub release, `v4.35.0` (observed with `git` and `gh api repos/verse-lab/veil/releases`). It skipped Lean 4.25 to 4.27 and 4.29 to 4.34.
- **Activity.** 2,021 commits; 117 in the last three months; 45 in the last month, 30 of them by one person. 14 contributors on GitHub; the top two have 1,152 and 525 commits. 397 stars, 37 forks, 53 open issues and pull requests, last push 2026-11-13. Apache-2.0 (observed with `git log` and `gh api repos/verse-lab/veil`).
- **Users.** A GitHub code search for `verse-lab/veil` in Lake files found about 30 other repositories, among them `input-output-hk/rnd-midgard`, `katzenpost/cryptlib`, `leanprover/stref-veil`, `neuralmagic/crucible` and a Camunda configuration check (observed, `gh search code`). I did not open them, so I cannot say how much each uses it. The tutorial post that explains Veil end to end is by one of its authors (https://proofsandintuitions.net/2026/02/09/distributed-verification-veil/).
- **Help.** A Zulip channel on the Lean server (README).

Inference: an active, well-published research tool, about 21 months old, mostly built by one lab, with a second major version and a Lean-version tag only every few Lean releases. Not yet an industrial tool.

## How suited it is to being written by AI agents

- **Docs and examples.** Good. A 663-line DSL reference, a 279-line model checker guide, two heavily commented tutorials, and about 30 translations of TLA+ examples (Paxos, Raft, Two-Phase Commit, Percolator, an AWS DNS race). I wrote a working two-agent model on the first try from the Ring tutorial and the reference (observed).
- **Shipped skill.** One, for TLA+ to Veil. That fits this project's likely path: write in TLA+ first, port to Veil when a proof is wanted (inference).
- **Feedback.** Plain-text results with `✅`/`❌`, exit status 1 on failure, and pasteable proof stubs suit an agent loop. The weak spots were the two `cannot translate` errors, which gave no hint of the cause, and having to read Veil's source for an axiom name.
- **Traps I hit.** `lake env lean` crashes; use `lake lean`. Files need `module` and `public import Veil` for the compiled checker. The solver is trusted by default.

## Verdict

**Later.** Not now, and not never.

Reasons:

1. TLC already does the first job in the design (model check the replay rule, with predictions written first and settings that must fail) faster, with a 4.5 MB install that Mo's CI already pins. Veil found the same bug, with the same state counts, at about 1,000 times the install size.
2. Veil's real gain is the proof for any number of agents, and that worked here: a kernel-checked proof in about 15 minutes. The design does not need such proofs yet. Its plan puts Lean statements fourth and "prove them once the feature is in the reference".
3. It does not fit Mo's pinned Lean (4.35 against 4.34, with no 4.34 tag), so the hoped-for "one toolchain" would really be a second Lean project on its own schedule.
4. It is young and changing (2.0, about 21 months old, mostly one lab), and it has rough edges I hit within an hour: the symbolic search failed on a 60-line model, and a trivial proof step needed the source code.

Revisit when a TLA+ model of the replay rule passes and the project wants "for any number of agents" as a claim, or when Mo next moves its Lean pin and Veil has a matching tag.

## What this means for the project

- Keep TLA+ and TLC for the protocol models in `models/`, as `design-ideas.md` already proposes.
- When the replay-rule model is stable, one cheap trial is worth doing: port it with Veil's `tla-to-veil` skill, compare state counts with TLC (as I did here), and try `#check_invariants` with `veil.smt.trust false`. The lost-update proof above suggests the "recorded reads" part might be provable for any number of agents with a short invariant (inference).
- If that happens, give Veil its own Lake project with its own `lean-toolchain`, so Mo's `formal/` stays dependency-free.
- Write the property as something first-order (a ghost value such as `expected`) instead of a sum, if a proof is wanted.

## What I could not confirm

- Whether the prebuilt release files for tag `v4.35.0` make the first build much shorter. I built `main` from source.
- Liveness checking, `#simulate`, `#updr`, the VS Code extension, the InfoView display and the online playground: not tried.
- Why the symbolic search said `cannot translate 0` / `cannot translate 2` on my model, and why the start-state check said `cannot translate Type`.
- Why adding the one-line proof made the file take 46 s instead of 5 s.
- That the 4 solver answers were really rebuilt as Lean proofs when `veil.smt.trust` was off; I saw only that the warning went away and every check showed `✅`.
- How much the roughly 30 outside repositories actually use Veil.
- Veil's own TLC comparison (`scripts/tlc-vs-veil-mc-evaluation.py`) and the in-submission papers' speed claims: not run or read.
- That TLAPS can prove this protocol for any size, and the year TLA+ first appeared: from memory, not confirmed.
- TLC's exit status on a violation: not recorded.
- Whether my timings hold on other machines: single runs, one machine.
