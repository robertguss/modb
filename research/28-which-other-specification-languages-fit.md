Research run on 2026-11-14 by a subagent using Exa, for the ticket [Which other specification languages fit?](../issues/28-which-other-specification-languages-fit.md).

# Which other specification languages fit? (researched 2026-11-14)

Veil is left out; another agent is trying it. Release dates and activity come from the GitHub, npm, NuGet, PyPI and crates.io APIs, queried on this machine on 2026-11-14, unless another source is given. "Observed" means I saw it happen on this machine. "Inference" is my own reasoning. "From memory, not confirmed" means I did not find a source.

**Words used below.**

- A **model checker** runs every order of steps a model allows and looks for a state that breaks a rule.
- An **invariant** is a rule that must hold in every state ("balance is 5 once both agents are done").
- **Liveness** means something good eventually happens ("every agent eventually finishes"). Checking it needs **fairness**: an assumption that a step that stays possible is eventually taken.
- A **bounded** check covers every run up to a set length or size. A **proof** covers all lengths and sizes.
- An **inductive invariant** is a rule strong enough that if it holds before any step, it holds after. Checking that one step is enough to prove the rule for runs of any length.
- **Symbolic** checkers hand the question to a solver (SAT or SMT: programs that decide whether a logic formula can be true) instead of listing states one by one.
- A **counterexample** is the run that breaks the rule, printed step by step.
- **Trace validation** checks a log recorded from the real program against the model.
- **Model-based testing** goes the other way: the model generates runs and the real program is driven through them.

## Quint

- **What it is.** A specification language with "the robust theoretical basis of the Temporal Logic of Actions (TLA)" and "state-of-the-art type checking and development tooling" (https://github.com/quint-co/quint). In practice it is TLA+'s logic written like typed code. It has a random simulator and two exhaustive back ends: Apalache and TLC.
- **Who maintains it.** Quint was spun out of Informal Systems into its own company on 2026-04-16, with Gabriela Moreira as CEO (https://quint.sh/posts/new_era). The repository is now `quint-co/quint`, Apache-2.0.
- **Activity.** v0.33.1 on 2026-10-28, v0.33.0 on 2026-09-28, v0.32.0 on 2026-03-31; last push 2026-11-03. Active.
- **What it checks.** Interleaved steps: yes. Crashes: only those you model as steps (inference). Invariants: yes. Liveness: `quint verify --temporal` (observed in `--help`; I did not run it). Bounded checks by default. Unbounded proofs through Apalache's `--inductive-invariant` option (observed in `--help`; not run).
- **How it reads.** From my model below:

  ```
  action fork(a: int): bool = all {
    agents.get(a).phase == Idle,
    agents' = agents.setBy(a, ag => { ...ag, phase: Forked, read: balance, decided: balance + delta(a) }),
    balance' = balance,
  }
  ```

  `all { … }` means every line must hold. A primed name (`balance'`) is the value after the step. The rest looks like TypeScript.
- **How well agents write it.** There is official agent tooling: the Quint LLM Kit, with "MCP servers for Quint documentation and LSP integration" and "Specialized agents for Quint specification work", and standalone agent skills (https://github.com/quint-co/quint-llm-kit). The kit's modelling skill says: "**Use `quint run` only — never `quint verify`.**" (same repository). So its makers steer agents to random simulation, not exhaustive checking. Vendor claims: a refactor of a consensus engine "traditionally estimated at months of work" took "about 2 days for the spec modifications and validation, plus ~1 week for code generation and testing" (https://quint.sh/posts/llm_era). AI wrote most of a test driver for an EVM framework, which pushed "test coverage to about 80% at the application layer" and "surfaced a memory leak" (https://quint.sh/posts/quint_connect_emerald). I found no independent benchmark for Quint.
- **Install and run.** `npm install @informalsystems/quint` took 2.3 seconds and installed 79 packages with no install scripts (observed). The first `quint verify` downloaded Apalache 0.62.4 (188 MB) and a Rust evaluator (2.1 MB) into `~/.quint` (observed). It needs Java for those.
- **Tying to an implementation.** Quint Connect is "a Rust library for model-based testing (MBT) that connects a Quint specification with its implementation" (https://quint.sh/posts/quint_connect_emerald). It is Rust only. `quint run --out-itf` writes runs as JSON in the Informal Trace Format (ITF), and `--mbt` adds metadata for model-based testing (observed in `--help`). A Mo test could read those files (inference).

## P

- **What it is.** "A state machine based programming language for formally modeling and specifying complex distributed systems." Models are "a collection of communicating state machines" (https://p-org.github.io/P/). It is "A programming language — not a mathematical notation" (same page).
- **Who maintains it.** AWS, under `p-org`. Used on "storage (Amazon S3, EBS), to databases (Amazon DynamoDB, MemoryDB, Aurora)" (https://p-org.github.io/P/), and "in migrating Simple Storage Service (S3) from eventual to strong read-after-write consistency" (https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/).
- **Activity.** Compiler package 3.1.0 on NuGet, 2026-06-03. PeasyAI 1.0.0 on 2026-03-05. The last commit on the default branch was 2026-08-03. Active.
- **What it checks.** P's checker explores "interleavings of messages and failures" and gives "Reproducible error traces". It checks "both safety and liveness specifications" (https://p-org.github.io/P/). The default checker samples runs. The other back ends are PEx, "Exhaustive model checking", and PVerifier, "Deductive verification" giving a "Mathematical proof of correctness" (same site). Failures are machines you write, not built in (from memory, not confirmed).
- **How it reads.** Event handlers inside named states, close to C# or Java. I did not run P; the shape below is from memory and not confirmed:

  ```
  machine Store {
    var balance: int;
    start state Serving {
      on eLand do (req: tLand) { if (req.read == balance) { balance = req.decided; } }
    }
  }
  ```

- **How well agents write it.** PeasyAI is official agent tooling: an MCP server "providing 27 tools and 14 resources for generating P state machines from design documents, compiling them, and verifying correctness with PChecker" (https://p-org.github.io/P/getstarted/peasyai/). Vendor claim: "1,200+ RAG examples" (https://p-org.github.io/P/). I found no published measurement of how often its output is right.
- **Install and run.** It needs ".Net SDK 8.0" and "Java (`java` version 11 or higher)" (https://p-org.github.io/P/getstarted/install/). A Docker image bundles both (same page). .NET is not on this machine (observed), so I did not try it.
- **Tying to an implementation.** PObserve checks "formal correctness specifications on systems implementation using service logs" with no "additional instrumentation". You write a log parser and P monitors, and it runs on Java Streams (https://p-org.github.io/P/advanced/pobserve/pobserve/). This is trace validation, built in, but on the JVM.

## Alloy 6

- **What it is.** A language for structures and the relations between them, checked by a SAT solver within a size you choose. Alloy 6 added "a `var` keyword to specify that a signature or field is mutable", plus temporal operators, so it can also model steps over time (https://alloytools.org/alloy6.html).
- **Who maintains it.** The AlloyTools project (https://github.com/AlloyTools/org.alloytools.alloy). The optional unbounded back end, Electrod, is by Julien Brunel and David Chemouil (https://alloytools.org/alloy6.html).
- **Activity.** v6.2.0 on 2025-01-09. No release since. Last commit 2026-06-11. Maintained, but slow.
- **What it checks.** Shapes of data, its main strength: sets, relations, trees, "is this reachable from that". Interleaved steps: yes, since Alloy 6. Crashes: only as steps you write. Liveness: yes, through temporal formulas over looping traces. The data size is always bounded. The number of steps is bounded with `for M .. N steps`; `for 1.. steps` is unbounded but needs "a solver [that] must support complete model checking" (https://alloytools.org/alloy6.html). The bundled solvers cannot do that: "Bounded engines do not support complete model checking" (observed).
- **How it reads.** From my grant model below:

  ```
  sig Grant { parent: lone Grant, rights: set Right }
  fact madeNarrower { all g: Grant | some g.parent implies g.rights in g.parent.rights }
  assert neverWider { all g: Grant, a: g.^parent | g.rights in a.rights }
  ```

  `lone` means zero or one. `in` means "is a subset of". `^parent` means parent, grandparent and so on. Short, but the symbols take learning. Steps over time need every unchanged field restated by hand (a "frame condition"; observed in my model).
- **How well agents write it.** Academic studies exist. Anvil (2026): "Gemini 3.1 Pro produces correct formulas for all 11 properties", on 22 synthesis tasks about graph and relation properties (https://dl.acm.org/doi/10.1145/3822455.3830309). A 2025 study found GPT-4 models beat "traditional state-of-the-art Alloy repair tools" at fixing broken Alloy models (https://link.springer.com/article/10.1007/s10664-025-10687-1). These test formulas, not whole system models. I found no official agent tooling.
- **Install and run.** One 21 MB jar and Java. The download took 0.3 seconds (observed).
- **Tying to an implementation.** None built in. Results come out as JSON (`-t json`, observed in `--help`).

## FizzBee

- **What it is.** A model checker whose language is close to Python (it is based on Starlark, a Python dialect). The vendor calls it the "Easiest-ever formal methods language!" (vendor claim, GitHub description). It also draws diagrams and "Analyzes performance metrics" (https://fizzbee.io/).
- **Who maintains it.** The `fizzbee-io` organisation, Apache-2.0. I did not confirm who stands behind it.
- **Activity.** v0.5.4 on 2026-10-01; last push 2026-11-10. Active.
- **What it checks.** Interleaved steps: yes. Crashes are its distinctive feature: "Automatic fault injection at yield points". A role's fields can be marked `@state(durable=[...])` or `@state(ephemeral=[...])`, and "On crash: ephemeral fields reset to Init values" (https://fizzbee.io/reference/language/fault-injection/). Message loss is also injected automatically (same page). Liveness: I did not confirm. Bounded, exhaustive.
- **How it reads.** From its two-phase-commit example (https://fizzbee.io/):

  ```
  role Participant:
    action Init:
        self.status = "init"
    func placehold():
        vote = oneof ["accepted", "aborted"]
        self.status = vote
        return self.status
  ```

  This is the easiest of all the tools here for someone who knows code (inference).
- **How well agents write it.** It provides "skills for AI coding assistants (Claude Code, Cursor, Gemini CLI …)" covering the language, the checker and model-based tests (https://fizzbee.io/testing/). I found no measurement.
- **Install and run.** Homebrew or a release tarball. The Linux x86 tarball is 351 MB, against 33 MB for macOS (GitHub release assets). Model-based testing is a separate binary (https://fizzbee.io/testing/). I did not install it because of the size.
- **Tying to an implementation.** Model-based testing through an `Adapter` interface. The "guide currently shows examples in Go. Guides for Java and Rust are coming soon" (https://fizzbee.io/testing/).

## PlusCal

- **What it is.** A language that looks like pseudocode and is translated into TLA+. It ships inside the TLA+ tools (`pcal.trans`; observed). It is not a second tool: it is a friendlier way to write the TLA+ that is already in use.
- **Who maintains it, activity.** The TLA+ project. tla2tools v1.8.0 on 2026-11-06, the first stable release since v1.7.4 in 2024. The jar here reports `TLC2 Version 2026.11.06` (observed).
- **What it checks.** Everything TLC checks. I checked an invariant and a liveness property ("both agents eventually finish"): it passed with `fair process` and failed without, with a counterexample that ends in "Stuttering", meaning the system just stops (observed).
- **How it reads.**

  ```
  Land:
    if ~CheckRead \/ read = balance then
      balance := decided;
    elsif retries < 2 then
      retries := retries + 1;
      goto Fork;
    end if;
  ```

  Labels (`Land:`) mark the atomic steps. Everything between two labels happens at once.
- **How well agents write it.** Covered by TLA+'s evidence below. One trap I fell into: the process ends at the label `Done` whether it landed or gave up, so "Done" cannot tell the two apart. It did not matter with two agents. With three it would hide a failure (observed in my own model).
- **Tying to an implementation.** As for TLA+ (below).

## Apalache

- **What it is.** "The Symbolic Model Checker for TLA+" (https://apalache-mc.org/). It reads the same TLA+ files as TLC and translates them "into the logic supported by SMT solvers such as Microsoft Z3" (https://apalache-mc.org/docs/apalache/theory.html).
- **Who maintains it.** The `apalache-mc` organisation. Quint's README says Quint "was initially designed and developed by the Apalache team" (https://github.com/quint-co/quint). I did not confirm who funds Apalache today.
- **Activity.** v0.63.0 on 2026-11-10, with six releases since 2026-08-18. Very active.
- **What it checks.** Three modes: random symbolic runs, "Bounded model checking to reason about all executions up to length `k`", and "Inductiveness checking to reason about all executions of all lengths" (https://apalache-mc.org/docs/apalache/theory.html). It is the cheapest route here to a proof for unbounded runs, but you have to find the inductive invariant yourself. It needs type annotations on TLA+ (its type checker is "Snowcat", https://apalache-mc.org/docs/apalache/running.html). Liveness: `--temporal` (same page).
- **How it reads.** It is TLA+.
- **Install and run.** A Java distribution. Quint downloaded it automatically, 188 MB (observed). Through Quint, each run took 10 to 14 seconds against about 1 second for TLC, on this tiny model (observed).
- **Tying to an implementation.** Its trace format (ITF) is the one Quint writes (https://apalache-mc.org/docs/adr/015adr-trace.html, named in Quint's output; observed).

## Stateright

- **What it is.** "A model checker for implementing distributed systems", written in Rust (GitHub description). You write the system as Rust actors. The same code is model checked and can run outside the checker: "An actor runtime that can execute actors outside the model checker" (https://github.com/stateright/stateright).
- **Activity.** v0.31.0 on 2025-07-27. No commit since. 1,934 stars. Quiet for 15 months.
- **What it checks.** "Invariant checks via 'always' properties", "Nontriviality checks via 'sometimes' properties", "Liveness checks via 'eventually' properties (experimental/incomplete)", and a linearizability tester (https://github.com/stateright/stateright). Bounded.
- **How it reads.** Rust: `.property(Expectation::Always, "linearizable", |_, state| { … })` (https://github.com/stateright/stateright/blob/master/examples/linearizable-register.rs).
- **Agents, install.** Cargo. No agent tooling found.
- **Tying to an implementation.** The strongest of all, because the model is the implementation. That only helps if the implementation is in Rust, and here it is in Mo.

## Ivy

- **What it is.** A tool for proving protocols correct by keeping the proof questions in a "decidable" logic, one where a computer can always settle the answer: "using decidable logics makes proof automation more reliable and repeatable" (https://www.microsoft.com/en-us/research/project/ivy/). It has been used for "verified implementations of distributed consensus protocols, such as Paxos and Raft" (same page).
- **Who maintains it, activity.** Microsoft's repository was last pushed in 2021. The live line is `kenmcmil/ivy`, with commits on 2026-11-02. PyPI `ms-ivy` 1.8.26 came out on 2026-07-02 and needs Python ≥ 3.10.
- **What it checks.** Safety and liveness by "(1) deductive verification, (2) abstraction and model checking (3) manual proofs", plus "Compositional specification-based testing and bounded model checking" (https://slebok.github.io/proverb/ivy.html). Unbounded proofs, but "Ivy constructs inductive invariants interactively" (https://www.microsoft.com/en-us/research/project/ivy/): a person, or an agent, has to find them.
- **How it reads.** Imperative actions over relations. I did not write any.
- **Tying to an implementation.** It can "Extract executable distributed programs by translation to efficient C++ code" (https://slebok.github.io/proverb/ivy.html) and generate tests. That is no use for a Mo implementation.
- **Agents.** No tooling or evidence found.

## TLA+ with TLC, for comparison

- **Agent evidence.** TLA+ is the only language here with an independent benchmark. SysMoBench gives LLMs real systems and scores their TLA+ in four phases: syntax, runtime, conformance to the system's own traces, and invariants (https://arxiv.org/abs/2509.23130). On it, "even the latest leading LLMs average around 46% on conformance and 41% on invariant, compared to near-perfect scores on syntax". The same post says "frontier code agents such as Claude Code and Codex already have strong ability in TLA+ modeling" when they can read the repository (https://www.sigops.org/2026/can-llms-model-real-world-systems-in-tla/). The lesson applies to every tool here (inference): an agent writes a model that runs long before it writes one that matches the system.
- **Official agent tooling.** `tlaplus/AgentSkills` (https://github.com/tlaplus/AgentSkills). The VS Code extension has an MCP server with tools such as `tlaplus_mcp_tlc_check`, `tlaplus_mcp_tlc_explore` and `tlaplus_mcp_tlc_smoke` (https://github.com/tlaplus/vscode-tlaplus/blob/master/src/lm/MCPServer.ts).
- **Tying to an implementation.** Trace validation is published work. Traces from a running program are checked as "a constrained model checking problem, realized using the TLC model checker", and the method "discover[ed] serious bugs that had gone undetected by more traditional quality assurance" (https://arxiv.org/abs/2404.16075). TLC also writes counterexamples as JSON with action names (`-dumpTrace json`; observed).

## Others found

- **mCRL2.** A process-algebra language and toolset from TU Eindhoven with the University of Twente. Release 202607.0; site updated 2026-11-12 (https://www.mcrl2.org/web/index.html). Requirements are written in the "modal mu-calculus" (same page), which is hard for non-specialists. Not worth a look: it covers the same ground as TLA+ in a harder notation.
- **CADP.** From INRIA, released monthly, latest "2026-j" on 2026-10-13 (https://cadp.inria.fr/). Its licence is restricted, free for academic use (from memory, not confirmed). Not worth a look.
- **Maude.** Rewriting logic. Maude 3.5.1 on 2025-07-10. A research tool with no agent tooling found. Not worth a look.
- **Promela/SPIN.** From Bell Labs, BSD-licensed. The site says "The current Spin version is 6.5.1 (July 2020)" (https://spinroot.com/spin/whatispin.html); GitHub has a 6.5.2 tag, date not confirmed. Mature and fast for C-like concurrent code, but a 1990s notation that adds nothing over TLC here. Not worth a look.
- **Dafny.** Proves code correct, not designs. v4.11.0 on 2025-08-25, still actively committed. IronFleet used it to prove a Paxos library and a key-value store correct, with a "verified library of 40 fundamental TLA rules" (https://www.microsoft.com/en-us/research/wp-content/uploads/2015/10/ironfleet.pdf). For this project, Lean already holds the proof role. Not worth a look.

## What happened when I tried two of them

I chose Quint (installs from npm, same logic as TLA+) and Alloy 6 (one jar, and the only strong candidate for need 3). FizzBee was the other option. I skipped it because its Linux download is 351 MB. I also wrote the protocol in PlusCal for comparison. Everything lived in the scratch folder, with `HOME` and `TMPDIR` pointed there. One early Quint run wrote a temporary folder to `/tmp/quint-tlc-*` before I set `TMPDIR`; Quint removed it itself (observed).

**The protocol.** One integer `balance`, starting at 2. Two agents. Fork: record the balance read and decide `set(read + d)`, with d = 2 for agent 1 and 1 for agent 2. Land: if the recorded read still equals the balance, set the balance to the decided value and finish; otherwise fork again, at most twice. The rule: once both have finished, `balance = 5`.

### Quint

Commands (Q is the local `quint`):

```
npm install --prefix quint --ignore-scripts @informalsystems/quint@0.33.1     # 2.3 s
Q typecheck replay.qnt
Q run    replay.qnt --main=checked   --invariant=noLostUpdate --max-steps=12 --max-samples=10000
Q run    replay.qnt --main=unchecked --invariant=noLostUpdate --max-steps=12 --max-samples=10000 --seed=1
Q verify replay.qnt --main=checked   --invariant=noLostUpdate --backend=tlc
Q verify replay.qnt --main=unchecked --invariant=noLostUpdate --backend=tlc
Q verify replay.qnt --main=checked   --invariant=noLostUpdate --max-steps=10     # Apalache
Q verify replay.qnt --main=unchecked --invariant=noLostUpdate --max-steps=10
```

The final spec, in full:

```
module replay {
  const CHECK_READ: bool

  type Phase = Idle | Forked | Done | GaveUp
  type Agent = { phase: Phase, read: int, decided: int, retries: int }

  pure val AGENTS = Set(1, 2)
  pure def delta(a: int): int = if (a == 1) 2 else 1

  var balance: int
  var agents: int -> Agent

  action init = all {
    balance' = 2,
    agents' = AGENTS.mapBy(a => { phase: Idle, read: 0, decided: 0, retries: 0 }),
  }

  action fork(a: int): bool = all {
    agents.get(a).phase == Idle,
    agents' = agents.setBy(a, ag => { ...ag, phase: Forked, read: balance, decided: balance + delta(a) }),
    balance' = balance,
  }

  action land(a: int): bool = {
    val ag = agents.get(a)
    all {
      ag.phase == Forked,
      if (not(CHECK_READ) or ag.read == balance) all {
        balance' = ag.decided,
        agents' = agents.set(a, { ...ag, phase: Done }),
      } else all {
        balance' = balance,
        agents' = agents.set(a, if (ag.retries < 2) { ...ag, phase: Idle, retries: ag.retries + 1 }
                                else { ...ag, phase: GaveUp }),
      },
    }
  }

  val bothDone = AGENTS.forall(a => agents.get(a).phase == Done)
  val finished = AGENTS.forall(a => agents.get(a).phase.in(Set(Done, GaveUp)))

  action stop = all { finished, balance' = balance, agents' = agents }

  action step = any {
    nondet a = oneOf(AGENTS) any { fork(a), land(a) },
    stop,
  }

  val noLostUpdate = bothDone implies balance == 5
}

module checked {
  import replay(CHECK_READ = true).*
}

module unchecked {
  import replay(CHECK_READ = false).*
}
```

Results (observed):

| Run | Result | Time |
| --- | --- | --- |
| Simulator, check on | No violation in 10,000 runs; a sample run shows agent 2 refused once, re-forking at 4 and landing 5 | 1.6 s |
| Simulator, check off | Violation found | 1.4 s |
| TLC, check on | "No error has been found", 18 distinct states | 21 s the first time, including downloads |
| TLC, check off | Counterexample, 14 states explored | 10 s |
| Apalache, check on, 10 steps | "No violation found" | 10.6 s |
| Apalache, check off, 10 steps | "found a counterexample" | 13.7 s |

Extra checks, so that a pass does not mean the rule was empty: `--witnesses=bothDone` reported "bothDone was witnessed in 2000 trace(s) out of 2000". With TLC, `not(bothDone)` was violated, so the done state is reachable, and `neverGaveUp` held.

The counterexample (simulator, check off; agents written as phase/read/decided):

```
State 0  balance 2   agent1 Idle          agent2 Idle
State 1  balance 2   agent1 Idle          agent2 Forked read 2 decided 3
State 2  balance 2   agent1 Forked 2→4    agent2 Forked 2→3
State 3  balance 4   agent1 Done          agent2 Forked 2→3
State 4  balance 3   agent1 Done          agent2 Done
[violation] Found an issue
```

Agent 2 decided on a balance of 2 that was no longer true and overwrote agent 1's update. That is the lost update. TLC found the same run through Quint, in the other order (agent 1 forks first).

**Trouble met.**

- The first version had no step once both agents were done. Apalache reported "error: reached a deadlock" even for the correct model, but TLC through Quint did not. I added an explicit `stop` step. Quint has no option to switch the deadlock check off.
- The first `verify` was slow because it downloaded 190 MB.
- The model typechecked on the first try. Writing it took about 4 minutes.

### Alloy 6

Commands:

```
curl -sSLo alloy.jar https://github.com/AlloyTools/org.alloytools.alloy/releases/download/v6.2.0/org.alloytools.alloy.dist.jar   # 0.3 s
java -jar alloy.jar exec -f -o out -t text replay.als        # 6.8 s for all three commands
java -jar alloy.jar exec -f -o grants-out -t text grants.als # 1.0 s
```

The final spec, in full:

```
module replay

enum Phase { Idle, Forked, Done, GaveUp }

abstract sig Agent {
  delta: one Int,
  var phase: one Phase,
  var read: one Int,
  var decided: one Int,
  var retries: one Int
}
one sig A1, A2 extends Agent {}

one sig Store { var balance: one Int }

lone sig CheckRead {}

fact deltas { A1.delta = 2 and A2.delta = 1 }

fact init {
  Store.balance = 2
  all a: Agent | a.phase = Idle and a.read = 0 and a.decided = 0 and a.retries = 0
}

pred keep[a: Agent] {
  a.phase' = a.phase
  a.read' = a.read
  a.decided' = a.decided
  a.retries' = a.retries
}

pred fork[a: Agent] {
  a.phase = Idle
  a.phase' = Forked
  a.read' = Store.balance
  a.decided' = plus[Store.balance, a.delta]
  a.retries' = a.retries
  Store.balance' = Store.balance
  all b: Agent - a | keep[b]
}

pred land[a: Agent] {
  a.phase = Forked
  a.read' = a.read
  a.decided' = a.decided
  (no CheckRead or a.read = Store.balance) implies {
    Store.balance' = a.decided
    a.phase' = Done
    a.retries' = a.retries
  } else {
    Store.balance' = Store.balance
    a.retries < 2 implies {
      a.phase' = Idle
      a.retries' = plus[a.retries, 1]
    } else {
      a.phase' = GaveUp
      a.retries' = a.retries
    }
  }
  all b: Agent - a | keep[b]
}

pred skip {
  Store.balance' = Store.balance
  all a: Agent | keep[a]
}

fact transitions { always (skip or some a: Agent | fork[a] or land[a]) }

pred bothDone { all a: Agent | a.phase = Done }

assert checkedNoLostUpdate { some CheckRead implies always (bothDone implies Store.balance = 5) }
assert uncheckedNoLostUpdate { no CheckRead implies always (bothDone implies Store.balance = 5) }

check checkedNoLostUpdate for 5 Int, 1..12 steps
check uncheckedNoLostUpdate for 5 Int, 1..12 steps
run reachBothDone { some CheckRead and eventually bothDone } for 5 Int, 1..12 steps
```

Results (observed):

```
00. check checkedNoLostUpdate      0       UNSAT
01. check uncheckedNoLostUpdate     0    1/1     SAT
02. run   reachBothDone            0    1/1     SAT
```

UNSAT on a `check` means no counterexample within the bounds: integers from −16 to 15 and up to 12 steps. SAT means one was found. The `run` shows the done state is reachable, so the pass does not mean the rule was empty. The counterexample, cut down to the changing fields:

```
State 0          phase A1 Idle,   A2 Idle     read 0,0  decided 0,0  balance 2
State 1          phase A1 Idle,   A2 Forked   read 0,2  decided 0,3  balance 2
State 2          phase A1 Forked, A2 Forked   read 2,2  decided 4,3  balance 2
State 3          phase A1 Done,   A2 Forked   read 2,2  decided 4,3  balance 4
State 4 (loop)   phase A1 Done,   A2 Done     read 2,2  decided 4,3  balance 3
```

It is the same lost update. The full output prints every set in every state, 127 lines for 5 states. It is harder to read than Quint's or TLC's.

**Trouble met.**

- `fact steps { … }` is a syntax error because `steps` is a keyword. I renamed the fact.
- Every step must restate every unchanged field (`keep`). Forgetting one lets the solver change that field freely. I did not trip on it this time, but it is the classic Alloy mistake (inference).
- Integers wrap within the bit width. `5 Int` gives −16 to 15 (observed in the output). A larger balance would need a wider setting.
- Asking for an unbounded check failed: "Bounded engines do not support complete model checking." It needs an external Electrod and nuXmv install.
- Writing the model took about 5 minutes.

**Need 3, tried in Alloy as well.** A grant model, in full:

```
module grants

sig Right {}
sig Grant { parent: lone Grant, rights: set Right }
var sig Revoked in Grant {}
lone sig CheckAgainstTop {}

fact tree { no g: Grant | g in g.^parent }

fun top[g: Grant]: Grant { g.*parent - parent.Grant }

fact madeNarrower {
  all g: Grant | some g.parent implies
    (no CheckAgainstTop implies g.rights in g.parent.rights
                        else g.rights in top[g].rights)
}

fact revocation {
  no Revoked
  always (Revoked' = Revoked or some g: Grant | Revoked' = Revoked + g)
}

pred live[g: Grant] { no (g.*parent & Revoked) }

assert neverWider { no CheckAgainstTop implies all g: Grant, a: g.^parent | g.rights in a.rights }
assert neverWiderTopCheck { some CheckAgainstTop implies all g: Grant, a: g.^parent | g.rights in a.rights }
assert revokeEndsDescendants { always all g: Revoked, d: g.^(~parent) | not live[d] }

check neverWider for 5 but 1..2 steps
check neverWiderTopCheck for 5 but 1..2 steps
check revokeEndsDescendants for 5 but 1..6 steps
```

Results: `neverWider` UNSAT, `neverWiderTopCheck` SAT, `revokeEndsDescendants` UNSAT, in 1.0 s (observed). The SAT case is a realistic bug: each new grant is checked only against the top grant, not against its direct parent. The counterexample has a top grant with one right, a child with none, and a grandchild that has the right again. The grandchild is wider than its parent. `revokeEndsDescendants` passes because `live` is defined by walking up the chain. It checks that definition, not any implementation of it.

### PlusCal and TLC, for comparison

The algorithm is the 22 lines at the top of the file; the translation is generated. In full:

```
---- MODULE Replay ----
EXTENDS Integers
CONSTANT CheckRead

(* --algorithm Replay
variables balance = 2;

process agent \in {1, 2}
variables read = 0, decided = 0, retries = 0;
begin
Fork:
  read := balance;
  decided := read + (IF self = 1 THEN 2 ELSE 1);
Land:
  if ~CheckRead \/ read = balance then
    balance := decided;
  elsif retries < 2 then
    retries := retries + 1;
    goto Fork;
  end if;
end process;
end algorithm; *)
\* BEGIN TRANSLATION   (generated by pcal.trans)
\* END TRANSLATION

NoLostUpdate == (\A a \in {1, 2} : pc[a] = "Done") => balance = 5
====
```

With the check on, TLC reported "No error has been found", 18 distinct states, in 0.56 s. That is the same state count as Quint through TLC. With it off, TLC reported "Invariant NoLostUpdate is violated" with the same 5-state run (balance 2, 2, 2, 4, 3), in 0.60 s (observed). Writing it took about 2 minutes and needed no fixes.

## One table

Fit: ++ strong, + workable, − poor, 0 does not apply.

| Tool | What it checks | Bounded or proof | Maturity (2026) | 1 merge protocol | 2 disk writes, crash at every step | 3 shapes of data | 4 tie to implementation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TLA+ / TLC (in use) | Interleaving, invariants, liveness with fairness | Bounded (finite models) | High; v1.8.0 Nov 2026; benchmark and official agent tools | ++ | + crash written as a step | + small sets only (inference) | + trace validation; JSON traces |
| PlusCal | As TLC | As TLC | High; ships with TLA+ | ++ easier to read | + | − | as TLA+ |
| Apalache | As TLC, symbolic | Bounded, or proof via inductive invariant | High; v0.63.0 Nov 2026 | ++ when a proof is wanted | + | + | + ITF traces |
| Quint | As TLA+ | Bounded; proof via Apalache | Medium-high; v0.33.1 Oct 2026; new company | ++ | + crash written as a step | + | + ITF traces; Quint Connect is Rust only |
| P | Message interleaving, failures, liveness | Sampled; exhaustive (PEx); proof (PVerifier) | High at AWS; .NET + Java | + message-shaped | + | − | + PObserve, JVM logs |
| Alloy 6 | Relations and shapes; steps since v6 | Bounded; unbounded steps only with an external solver | Medium; last release Jan 2025 | + awkward, hand-written frames | − | ++ | − |
| FizzBee | Interleaving, automatic crashes and message loss | Bounded | Young; v0.5.4 Oct 2026; 351 MB on Linux | + | ++ durable versus ephemeral fields built in | − | + MBT in Go only |
| Stateright | Rust actors, linearizability | Bounded | Quiet since Jul 2025 | − needs Rust | − | − | 0 only for Rust code |
| Ivy | Protocol proofs | Proof, invariants found by hand | Research; one active fork | + at high cost | − | + | − C++ output |
| mCRL2, CADP, Maude, SPIN | Process behaviour | Bounded | Mature, academic | + in harder notation | + | − | − |
| Dafny | Code correctness | Proof | High | − | − | + | 0 code would have to be Dafny |

## Verdict

**Add Alloy 6, for need 3 only.** Grants made from grants, revocation down a chain, and the tree of write-once nodes (no cycles, shared parts, one root per version) are shapes of data, and Alloy is built for them. In this run it found a realistic narrowing bug in one second, from a 31-line model. It costs one 21 MB jar and the Java that TLC already needs. Its checks are bounded, so the Lean statement planned in design-ideas.md ("a helper's grant never shows more than the grant it was made from") is still the proof. Alloy is the cheap way to find a wrong rule before anyone tries to prove it.

**Keep TLA+ with TLC for needs 1 and 2.** Write new models in PlusCal where the protocol reads as steps. It did the merge protocol in 22 lines, first try, in under a second, with liveness too. It has the only independent agent benchmark and official agent tooling. Mo's `models/` folder and `ci/check_models.py` already run it.

**Keep Apalache in reserve for need 1.** If the replay rule ever needs a proof for any number of agents, Apalache can check an inductive invariant over the same TLA+ files. It needs type annotations, and someone has to find the invariant.

**For need 4, add no tool.** Every turnkey link between a model and an implementation is tied to another language: Quint Connect to Rust, FizzBee to Go, P's PObserve to the JVM, Stateright and Ivy to their own code. Mo already logs every call and repeats it exactly. The fitting method is TLA+ trace validation: the Mo service's call log, written as JSON, is checked by TLC (https://arxiv.org/abs/2404.16075). In the other direction, TLC's `-dumpTrace json` runs (observed) can become `mo test` cases.

**Do not add Quint.** It worked well and reads best of the TLA+ family. But it checks the same logic with the same back ends, so it would be a second notation for the same job. Its own agent kit tells agents not to use the exhaustive checker. Revisit only if a person must read many models and PlusCal is not enough.

**Look at FizzBee once, if the disk-writes model gets hard in TLA+.** Its durable and ephemeral fields match "which writes survive a crash" exactly. Its youth and its 351 MB Linux download count against it.

**Ignore:** P, which needs .NET and fits message passing between services, not a single writer. Stateright, which only helps Rust code and has been quiet since 2025. Ivy, a proof tool for experts. mCRL2, CADP, Maude and SPIN, which cover the same ground in older notations with no agent tooling. Dafny, whose proof role Lean already fills.

## What this means for the project

- design-ideas.md lists "Alloy (rules about shapes of data, such as whether one grant is narrower than another)" from Claude's knowledge. That is now confirmed and tried. A small Alloy model of grants and revocation could come before the Lean statements in step 4 of "Order proposed", and cost minutes.
- The TLA+ model of the replay rule (step 1) can be written in PlusCal. The lost update above is its smallest case, and a configuration with the recorded-read check off must fail, as this run showed.
- For the disk-write model (step 3), write the crash in TLA+ as a step that drops everything not yet on disk. Compare with FizzBee only if that model becomes hard to read (inference).
- SysMoBench's finding (high syntax scores, about 46% conformance) applies here: a model an agent writes can run and still not match the design. Each model needs its predictions written first and its must-fail settings, as Mo's models already have.
- Tying models to Mo code needs a stable JSON form of the service log. That is a Mo feature, not a tool choice.

## What I could not confirm

- Who funds or employs Apalache's maintainers in 2026, and who stands behind FizzBee.
- Whether FizzBee checks liveness. I did not install it.
- P's syntax as shown is from memory. I did not run P (no .NET here), and I found no measured success rate for PeasyAI.
- Any independent benchmark of agents writing Quint, P, FizzBee, Ivy or Alloy system models. The Alloy studies cover formulas only. Quint's and FizzBee's agent claims are their own.
- CADP's licence terms, and the release date of SPIN 6.5.2.
- Whether Alloy's unbounded mode works with current Electrod and nuXmv on Linux. I did not install them.
- Quint's liveness checking (`--temporal`) and Apalache's inductive-invariant mode: seen in the help text, not run.
- My times are for a toy model with 18 states. They say nothing about how any tool scales.
