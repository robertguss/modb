I've read the snapshot and the Mo docs it depends on. I didn't run anything.

**The finding that most shapes my slate.** No file in the snapshot mentions `mo query`. design-ideas.md idea 1 calls the upgrade path "the nearest thing Mo has" to accepting a program. In fact Mo already runs a caller's own function over an exported state: `docs/agent-guide.md`, the `mo query` section, with export available through the `mo-export` MCP tool. It has a work limit (`MO_LIMIT_QUERY_WORK`, 2^30 instructions, in `src/base/limits.h`) and refuses capabilities or functions in parameters (E1411). It runs offline, not inside a live service. A call to a service gets only `MO_LIMIT_SERVICE_WORK`, 2^20 instructions, about a thousandth of that.

**1. Slate, in order**

**S1: questions asked again at landing.**
- **Agent does:** inside a world, runs two or three real read programs (a sum, a filter, a count by group) instead of the key lookups in `worlds.mo` `ask`. Each program's name, arguments and answer are recorded, and `land` runs them again on the main line.
- **Guard:** "every question counts, by its answer." Control: a world whose relied-on total changed must be sent back.
- **Data kept:** the tree by number (`tree.mo`).
- **Result, either way:** does re-running the recorded programs fit inside one landing call at 1k, 10k and 50k rows? The prediction gives the largest size at which it fits. Also measure the same programs through `mo query` on an export.
- **Mo in the way:** the 2^20 instruction limit per call; reference §11.5 forbids function values in state, so the programs must be a fixed set of named functions (a stand-in); new code arrives only by whole-service upgrade (`src/tools/protocol-upgrade.c`).

**S2: two real agents, one real dataset, through a running service.**
- **Agent does:** two model-driven agents work on the same data over MCP. Issue 12 must answer first which dataset.
- **Guard:** worlds land whole, with the rule checked after every call.
- **Data kept:** worlds as service state. Issue 37 "Not shown" says they have only run under `mo test`.
- **Result:** the needless send-back rate, the number design-ideas.md ("Which reads count as relied on") says the finer rule waits for. Prediction: above or below a threshold written in advance.
- **Mo in the way:** one token per service (`docs/design/services.md`), so callers are told apart only by an unauthenticated argument (a stand-in); `MO_LIMIT_MCP_RATE` of 20 calls a second; the 16 KiB request limit (I did not re-verify that number).

**S3: an agent proposes, a person approves, with a world open across it.**
- **Agent does:** proposes a new write function. It goes through the upgrade tools (`mo-upgrade-open/page/commit`) while another agent's world, recorded under the old code, is still open.
- **Guard:** "narrower is free, wider needs a person." Control: a widened view must not land without approval.
- **Result:** when the open world lands, does replaying it under the new code keep or break the replay rule? Either can happen.
- **Mo in the way:** upgrades replace the whole service; I did not check how a state migration interacts with the node map.

**S4: the kept log, and taking one agent's work out.**
- **Agent does:** every call carries a caller and a reason. Remove one agent's calls and replay what came after.
- **Guard:** the accountable write.
- **Data kept:** the log inside the state, because Mo deletes its own log at each snapshot, every 100 messages (`MO_LIMIT_SERVICE_SNAPSHOT_MESSAGES`).
- **Result:** the calls predicted to be refused or changed by the removal, against those actually found; and the log length at which the memory ceiling stops writes.
- **Mo in the way:** no caller identity; the log is not kept.

**S5: write only what changed (a measurement or model, not a build).**
- **Result:** with only changed nodes written, does a write's cost become flat as the state grows?
- **Mo in the way:** `encoded_copy` in `src/vm/service.c` encodes the whole state; §11.5 forbids capabilities in a handler; files have no byte writes, seek or sync (map.md, "Mo on 2026-11-13"). So this can only be measured outside a service.

**2. Run S1 first.** "Every question counts, by its answer" is decided and is the newest idea here. Yet the only test of it, `worlds.mo`, uses single-key questions, which are nearly free to ask again. Read programs are what make it expensive, and landing runs inside the smallest work limit. If S1 fails at modest sizes, the decided rule needs another mechanism, such as answer 6 or re-checking outside the call. That would change S2 through S4. S1 also builds directly on existing code and needs nobody's data.

**3. Stop rule.** Write the decision when all three hold:
- (a) each of the map's five destination items cites at least one slice result. Item 3 must come from a slice on Robert's real data; every gap under item 4 must have been hit by a slice, not inferred from reading.
- (b) two slices in a row have added no new Mo gap and have not changed the one-sentence statement of what is new (map.md "Not yet specified").
- (c) the library-or-runtime question for storage has a measured answer (S5).

If five slices run without meeting all three, write the decision anyway and list the gaps that are still open.

**4. Deliberately left out.**
- Sensitivity labels in types (idea 9): Mo has nothing for them, so they can't be sliced. They need a type-system design and Lean.
- Views kept current and indexes (ideas 8 and storage): left until S2 shows read programs are actually slow.
- Erasing data from history, and chains of helper grants: they need S4's log first.
- Fairness between fast and slow agents, and the 10 ms HTTP layer: the first is a later deep dive; the second is Mo's own matter.
- Batteries and memory safety: deferred and parked by Robert.

**5. Largest risk: stand-ins pile up until they become the design.** So far the slices have used:
- views written as key predicates;
- the rule written twice, as a promise and as `rule?`;
- a bare map in place of a record;
- named functions in place of submitted programs;
- self-declared callers.

Each slice passes on its own, and nobody runs them together. Guards:
- each slice extends the previous slice's code in one sketch, instead of starting fresh;
- a slice isn't done until its stand-ins are listed, each with what would replace it;
- the decision may only cite results whose stand-ins it names.

**6. Confidence that S1 should be first: about 65%.** I would change my mind if issue 12's answer names data that agents mostly append to and rarely re-read; S2 would then go first. I would also change it if one look at real agent transcripts shows their questions are nearly all single-key lookups, which would make S1's cost moot.

What I didn't check: I did not run the sketches or `mo query`, did not read `models/` or the council's raw files, and did not verify the 16 KiB request limit.
