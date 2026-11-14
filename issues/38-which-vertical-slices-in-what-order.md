# Which vertical slices, in what order, and what must each show?

Type: grilling
Status: open
Blocked by: [Can a landing ask an agent's questions again inside one call?](39-can-a-landing-ask-an-agents-questions-again.md)

## Question

HITL. Robert chose vertical slices on 2026-11-14 ([Which half comes first?](36-which-half-comes-first.md)). A vertical slice is one small job carried the whole way down: something an agent does, the rule that guards it, and the way its data is kept.

Which slices are run, and in what order? What must each show before the next? When are there enough of them to write the decision this map is for?

## Comments

**Claude's proposal, 2026-11-14.** Not decided by Robert. Replaced the same day by the revised proposal at the end of this ticket, after the council.

| # | Slice | What an agent does | How the data is kept | What it must show | From Mo |
| --- | --- | --- | --- | --- | --- |
| 1 | A world over the wire | Opens a world on a running service, asks, acts and lands, while a second agent does the same | The tree by number, in a service's saved state | The worlds of the sketch survive being a real service that restarts; what the list of tools looks like to an agent; what an ask, an act and a landing each cost at 1,000 and 50,000 rows | Nothing |
| 2 | A rule and a view over many rows | Lands a transfer among many accounts, and reads only its own rows | Totals kept in the tree's branches, so a check reads one path and not every row | The rule check and the narrowed read cost the same at 1,000 and 50,000 rows | Nothing |
| 3 | A read program | Writes a small Mo function that answers its question, in place of a query, and runs it on a kept version | An exported state at first, run with `mo query` | Whether an agent with only Mo's guide writes a correct read program at the first try; what one costs; what Mo lacks to run one on a live service | Measured, not built |
| 4 | A write that costs what it changes | Changes one row | Only the changed nodes are written; the tree by number knows which they are | How much is written and how long it takes against saving everything; exactly what Mo's service would have to change | A change to Mo to build it; here it is measured and modelled |
| 5 | A proposal a person approves | Proposes a new kind of call; a person reads what becomes possible and approves it | The state carried across an upgrade of the service | The accountable write holds when the set of approved calls changes | Nothing known |

- **Each slice is one prototype ticket,** with its predictions written first and a control that must fail, as [Can a Mo library keep old versions cheaply today?](37-can-a-mo-library-keep-old-versions-cheaply-today.md) was.
- **Recommended first: slice 1.** Every other slice hangs on what an agent sees and does, and it needs nothing from Mo. Slice 2 comes next because slice 1 is only honest at size once a rule does not read every row.
- **Slice 4 is the storage half's real question.** The sketch showed that versions are not: every write costs in proportion to all of the state. Building slice 4 for real means changing Mo, which this map rules out, so here it can only be measured and modelled.
- **A stop rule.** Slices are experiments and the map's destination is a decision. Claude's worry is a string of sketches that never ends in one. After these five, or sooner if two in a row change nothing, the decision is written.

**The council, 2026-11-14.** Robert asked for it, and for Jev, before he chooses: "Use the council and jev before we decide and choose." Three reviewers from three providers each read a copy of this repository at commit `28b9da6`, before the proposal above was written, so their slates owe nothing to it. The brief, the three reviews and the Jev files are in [raw/council-2026-11-14-which-vertical-slices](../raw/council-2026-11-14-which-vertical-slices/).

| | GPT Sol | Claude Opus | Gemini Carbon |
| --- | --- | --- | --- |
| 1 | An agent asks an unplanned question through a narrowed view; the answers are recorded and checked at landing. An extract of real data | In a world an agent asks a sum, a filter and a count; `land` asks them again. At 1,000, 10,000 and 50,000 rows | An agent that has never seen the database writes read functions over a narrowed view of real data; the answers are checked at landing |
| 2 | What an agent may do changes while it thinks: a grant is withdrawn, or an approved function replaced, before landing | Two real agents on one real dataset through a running service, counting needless send-backs | Helpers with narrower grants, rule checks that do not read every row, and undoing one agent's calls, on a running service |
| 3 | A reply is lost and the agent tries again: the landing must not happen twice | An agent proposes and a person approves, while another agent's world is open across the change | An agent proposes a write and a migration; a person approves through Phase 6's review of intent |
| 4 | Worlds are abandoned: versions nobody holds are freed under a stated rule | The kept log, and taking one agent's work out | Writing only the changed path, freeing dead worlds, and recovering from a faulted disk |
| 5 | | Writing only what changed, measured or modelled | |

**Where all three agree.**

- **The first slice, and it is not Claude's.** An agent's real questions are answered by read programs, recorded, and checked again when the world lands. Claude proposed worlds on a running service first and predicted all three would. Opus gives the reason: "every question counts, by its answer" is decided, and its only test asks for single keys, which cost almost nothing to ask again. A sum or a filter is what makes the rule expensive, and landing runs inside the smallest limit Mo has, about a million instructions for one call.
- **The largest risk:** slices that each pass alone and do not fit together. All three give the same guard: carry one sketch, or one scenario, through every slice. Opus adds that a slice is not done until its stand-ins are listed, each with what would replace it. A stand-in is something simpler used in place of the real thing, such as a named function where an agent would send a program. None of the three named Claude's worry, sketches that never end in a decision.
- **The stop rule:** stop when each of the five items of [the map's](../map.md) destination rests on a slice's result.
- **A slice Claude did not have:** what an agent is allowed to do changes while its world is open.
- **A slice in which a person approves.** In Sol's slate approval sits inside other slices and has none of its own.
- At least one slice cannot be built in Mo today, and is measured or modelled.
- Nobody assumes SQL. Sol and Gemini do not argue from being usable sooner. Jev was unsure about Opus (0.33); Claude reads its reason, that the first slice builds on code that exists, as convenience and not as that argument.

**Where they split.**

- **Real data.** Sol and Gemini put it in the first slice. Opus says the first slice "needs nobody's data" and puts real data second, once [What real data of yours goes in first?](12-what-real-data-goes-in-first.md) is answered.
- **Worlds on a running service:** Opus and Gemini. Sol only models.
- **Storage:** Opus measures writing only what changed. Gemini adds freeing versions and a faulted disk. Sol has freeing versions alone.
- **A rule that does not read every row:** Gemini, and Claude's slice 2. Opus leaves it out until read programs are shown to be slow.
- **A lost reply and a second try:** Sol alone.
- **An agent that has never seen the database:** Gemini makes it the test of the first slice. Sol asks for "a small agent exercise".

**Claude's five slices against the three slates,** as Jev read them.

| Claude's slice | Sol | Opus | Gemini | |
| --- | --- | --- | --- | --- |
| 1. A world over the wire | no | yes | yes | Shared, and nobody's first |
| 2. A rule and a view over many rows | no | no | yes | Contested |
| 3. A read program | unsure | yes | yes | Shared. All three put it first, joined to the check at landing |
| 4. A write that costs what it changes | no | yes | yes | Shared |
| 5. A proposal a person approves | yes | yes | yes | Shared |

Missing from Claude's list: authority that changes while a world is open (all three), and freeing versions (Sol and Gemini).

**What the reviewers got right and wrong.** Checked against Mo at commit `af246d7d` and this repository at `28b9da6`.

- **Opus found a gap in these notes.** Mo already runs a caller's own function over an exported copy of a service's state, with `mo query`. It runs outside the service, under a limit of 2^30 instructions, 1,024 times what a call to a service gets. No file here mentioned it, and `design-ideas.md` called the upgrade path "the nearest thing Mo has" to accepting a program. Claude had used `mo query` while building the sketch and did not write it down. Corrected in `design-ideas.md` and the map the same day.
- **Sol:** every claim checked held.
- **Opus:** one slip. It lists "self-declared callers" among the stand-ins the sketches already use, and no sketch has a caller. Not checked: that new code reaches a service only by upgrading the whole service.
- **Gemini:** all 12 functions and 9 files it names exist. Its errors:
  - It says the 16 MiB limit on saved state is what stops a service at about 125,000 rows. [The measurement](11-how-fast-and-large-is-a-mo-service.md) says the opposite: the memory one call may use stops it, at about 9 MiB saved.
  - It cites a section "Candidate datasets" in [What real data of yours goes in first?](12-what-real-data-goes-in-first.md) and "Open questions" number 8 in `design-ideas.md`. Neither exists.
  - It calls two sections of Mo's reference "11.5 Purity" and "12.5 Simulation". They are "11.5 Service blocks" and "12.5 Recovery checks".
  - It says a rule that reads every row reached the instruction limit at 1,000 inserts. The limit was reached by 1,000 inserts in one call. The rule has never run in a service.
  - It says `mo_check_query_entry` rejects "hidden fields". Mo has no such thing. The function refuses a generic function, a capability or a function in the parameters or the result, the wrong state type and the wrong inputs.
  - Not checked: that an upgrade is admitted without a review being consulted, and that `borrow_walk` is where a map in a record comes to be copied.

**Jev.** TypeSafe's Jev was asked what each review contains; the counts and verdicts were made in code. It was sent the three reviews, with Robert's name replaced, and short excerpts of Mo and of this repository: 23 requests, 26,267 tokens, about $0.0011, with Robert's key.

- **Claude's predictions were poor.** Of 22 statements predicted before any review arrived, 7 came out as predicted, 7 differed and 8 were not settled, meaning Jev gave a probability between 0.3 and 0.7 for at least one reviewer. For the first slice Claude predicted worlds on a running service three times. Jev chose a read program for Opus (0.87) and Gemini (0.90), and split evenly for Sol (0.38 each way).
- **The seven that differed:** worlds on a running service (2 slates, predicted 3), a proposal and its approval (3, predicted at most 1), freeing versions (2, predicted at most 1), what an agent may read or change (3, predicted at most 2), the risk of never deciding (0, predicted at least 2), the risk that slices do not join (3, predicted at most 2), and real data (2, predicted at most 1).
- **Citations:** 20 checks, 18 as predicted. Gemini's claim about the 16 MiB limit was marked contradicted at 1.00. One real claim, that most of a read's time goes to `authenticate` and `plan`, was marked supported at 0.74, under the bar of 0.8; the measurement gives 47% and 26%, and Claude counts it as supported.
- **One control did not settle.** Shown `#define MO_LIMIT_SERVICE_WORK (1 << 20)`, Jev marked the false claim that a call may run 1,073,741,824 instructions as contradicted at only 0.36. Jev does not do arithmetic, so the numbers above were checked by Claude in the code.
- **Where Claude reads a review differently from Jev:** Sol's first slice is about read programs (Jev 0.38). Sol asks for real data (0.58). Gemini's first slice tests an agent that has never seen the database (0.64). Gemini knows of `mo query` and names it as a blocker for running only outside a service (0.13).

**Claude's revised proposal, 2026-11-14.** Not decided by Robert. It replaces the table at the top.

| # | Slice | What it must show | Came from |
| --- | --- | --- | --- |
| 1 | Questions asked again at landing | In a world an agent asks a sum, a filter and a count by group over the tree, and `land` asks them again on the main line. At 1,000, 10,000 and 50,000 made-up rows: does asking again fit inside one call to a service, and what do the same questions cost through `mo query`? Two controls: a world whose relied-on total changed must be sent back, and with the check removed a stale decision must land | The first slice of all three reviewers. Claude's old slice 3, joined to the landing rule Robert decided |
| 2 | Two agents on real data through a running service | The share of send-backs that were needless. It waits for [What real data of yours goes in first?](12-what-real-data-goes-in-first.md) | Opus 2, Gemini 2, Claude's old slice 1 |
| 3 | What an agent may do changes while its world is open | A grant is withdrawn, or a proposed function approved, between a world's opening and its landing. A control that checks authority only at the opening must wrongly land withdrawn work | Sol 2, Opus 3, Gemini 3, Claude's old slice 5 |
| 4 | The kept log | One agent's calls are taken out and the rest replayed. A lost reply is tried again without landing twice | Sol 3, Opus 4, Gemini 2 |
| 5 | Storage: writing only what changed, and freeing versions nobody holds | Measured or modelled, since a Mo service does neither today | Claude's old slice 4, Opus 5, Sol 4, Gemini 4 |

- **Only the first slice needs choosing now.** All three reviewers say its result reshapes the rest.
- **Claude's old slice 2 is no longer a slice of its own.** Keeping totals, so that a rule does not read every row, is one of three ways out if asking again does not fit in a call. The other two are a write function that names the facts it relies on, and checking outside the call. Slice 1 says whether any is needed.
- **Claude's guess, before any prediction is written:** asking a sum again will not fit in one call at 10,000 rows. 400 inserts into the tree fit in a call and 1,000 did not.
- **Real data starts at slice 2,** as Opus has it. Slice 1 asks what a rule costs, which made-up rows answer, and it should not wait for a choice of data. Sol and Gemini would put real data in slice 1.
- **Guards taken from the council.** One sketch is carried through every slice, starting from `sketches/kept-versions`. Each slice ends with its list of stand-ins and what would replace each. The decision cites only results whose stand-ins it names.
- **The stop rule, replacing Claude's.** The decision is written when each of the five items of the map's destination rests on at least one slice's result, or after five slices, whichever comes first. Whatever is still open is listed in it.

**Decided by Robert on 2026-11-14: the first slice.** Asked "Shall the first slice be 'questions asked again at landing', on made-up rows?", he answered "Yes". It is [Can a landing ask an agent's questions again inside one call?](39-can-a-landing-ask-an-agents-questions-again.md), opened the same day with its predictions written before any code.

His answer covers the first slice only. The other four slices, their order, the guards and the stop rule are still Claude's proposal. This ticket waits for the first slice's result, which all three reviewers said reshapes the rest.
