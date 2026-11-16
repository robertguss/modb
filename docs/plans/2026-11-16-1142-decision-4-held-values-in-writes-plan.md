# Decision 4: may a write function open a held value?

Created: 2026-11-16

A plan for research and a decision. It builds nothing. It follows the shape of [the plan for Decision 3](2026-11-16-0238-decision-3-the-log-kept-whole-plan.md).

## 1. The question

The data store must be able to erase one person's data from every version (`design.md` section 4, need 8). Decision 3 made that harder. The record of calls is now kept for good, and each entry holds the call's arguments and its reply. So a person's data sits in three places that are never thrown away:

- the old versions of the tree;
- the arguments in the record;
- the replies in the record.

**The candidate answer is a held value,** idea 3 in [the ideation of 2026-11-14](../ideation/2026-11-14-mo-database-ideation.html). A field typed `Held(T)` is kept in history as a reference. The bytes live in a vault outside the tree and the record, keyed by the person they belong to. Opening the field gives the value or `Erased`, and the compiler asks for both arms. Erasing a person deletes their vault entries and touches nothing else.

**Robert has not accepted held values.** The ideation holds candidates. This plan takes them as the working answer and keeps one option that does without them.

**The question is what a write function may do with one.** A write that opens a held value and acts on it has put something of that value into the state. After the person is erased, running the record again gives a different state, or the state still holds what should be gone.

**What Decision 3 changed.** The ideation's worry was that a logged checksum would stop matching. Decision 3 made no promise that a run gives the same result for ever, and it already calls a run that is meant to differ "another history". So the question is no longer whether a run may differ. It is whether a run may differ because of an erasure, without anyone having asked for that.

## 2. The options

They run from the strictest to the loosest. Under each, code that only replies to a caller may open a held value.

| | Option | What it gives | What it asks |
| --- | --- | --- | --- |
| A | **Never open.** A write function may store a held value, move it, copy it and drop it. It may not look inside | The state, and every run of the record, are the same before and after an erasure | Every check on the value happens at the door, before it is held. "Is this email taken" needs a token kept beside the reference. No write may act on what a personal value says, such as an age or a country |
| B | **Facts at the door.** When a value is held, the program works out a few declared facts from it, such as "is an adult" or "which country". They are kept in the tree as ordinary data. Writes read the facts and never the value | A, and writes that act on the declared facts | Each fact is kept for good and is about the person. Someone must judge each one. A new fact is an upgrade |
| C | **Tests, with the answer in the record.** A write may put a small test to a held value and get a yes, a no or `Erased`. The entry in the record keeps each answer. A run of the record uses the kept answer and does not open the value | Writes that act on a personal value. A run of the record gives the same state after an erasure | The kept answers are about the person and are never erased. A run through corrected code may put a test that has no kept answer |
| D | **Open, and the `Erased` arm runs afterwards.** A write may open a held value. A run of the record after an erasure takes the `Erased` arm | Any write logic. Nothing worked out from the value is kept in the record | Every run after an erasure may differ from what happened, for other people too. What a write copied out of the value into the state stays there unless the types stop it |
| E | **No held values.** A person is erased by taking every entry that holds their data out of the record and the tree, and running the rest again | Nothing new in the types | History is rewritten. Other callers' replies change. A person's data also sits in entries that other callers made |

**Two things the options do not settle alone:**

- **The token.** A token that says "same email" is worked out from the email. In EU law data replaced by a stand-in is still personal data ([deleting personal data from history](../../wiki/ideas/deleting-personal-data-from-history.md)). If the token is erased with the person, "is this email taken" gives a different answer in a later run, and option A no longer gives the same state. This is inference. Experiment 20 tests it.
- **Replies.** The record keeps replies. A reply that shows an opened value would keep the bytes for good. So a reply in the record must hold the reference, under every option but E.

## 3. What is already settled

### Decided by Robert

- The record of calls is kept for good and can be run again through upgrades, with each version's code kept (2026-11-16, Decision 3).
- The record must be able to be run again with a different result on purpose: one caller's work taken out, or the state put right after a bug fix. A whole rebuild with the same result is not asked for (2026-11-16).
- A change to the stored format is made by writing the state out and reading it back. No run of the record is promised to give the same result for ever (2026-11-16).
- The data store is part of Mo's runtime (2026-11-16, Decision 2).
- At landing every question the agent asked counts, by its answer (`design.md` section 7).
- Not a limit: today's Mo, the cost of building, or how easy it is to learn.

### What the experiments and reading so far show

- **An entry that can be run again holds the call's arguments, its caller and its reply** (experiment 18).
- **A run with ten calls taken out changed the reply to 15 of the other 20 calls** (experiment 18). Option E is that run.
- **Mo's log today holds the arguments as they arrived.** It holds no reply and no caller (the reading for Decision 3).
- **Mo can already hide a type's insides.** `expose Order` gives the type without its fields, so code outside the module can only pass it to the module's functions (`~/code/mo/docs/reference/README.md`, section 10.2). A held value could be sketched that way.
- **Mo has nothing that says one function may open and another may not.** That is line 13 of `design.md` section 8, "carry a label on sensitive data in its type". This is from reading; experiment 20 tests what today's types can refuse.

### What earlier work settles

From the wiki and the two research panels.

- **Every store that keeps history treats erasing as a second-class step** ([deleting personal data from history](../../wiki/ideas/deleting-personal-data-from-history.md)). Datomic's excision is slow and lossy, and Datomic Cloud has none (panel of 2026-11-15, row 22).
- **Destroying a key is the usual answer for a kept history** (panel of 2026-11-15, row 23; only vendor pages were found).
- **The EU board's guidance points to keeping personal data outside the record, by reference.** It says clear, encrypted or hashed data in a record that cannot change is hard to erase (the same wiki page).
- **Taking one event out of the middle of a kept log is heavy or lossy** (panel of 2026-11-16, rows 13 and 25).
- **Labels on sensitive data with approved release functions is a known design** ([information-flow labels](../../wiki/ideas/information-flow-labels.md)). Choosing the release functions is where the judgement goes.

## 4. The questions that decide

| # | Question | Points to A or B if | Points to C or D if | Settled by |
| --- | --- | --- | --- | --- |
| Q1 | After a person is erased, what must a run of the record give? | The same state as before, but for that person's own bytes | Another history is acceptable when the changes are listed | Robert, one question (section 6, step 4) |
| Q2 | Does a run after an erasure differ under each option, and by how much? | A and B give the same state, and D changes other people's replies | D changes little, or A cannot hold once the token is erased | Experiment 20 |
| Q3 | How often does a write need what a personal value says, and for what? | Almost never, or only "is it taken" and checks that can sit at the door | Often, and for reasons nobody could declare ahead | Experiment 21 |
| Q4 | Is a kept token, fact or answer still the person's data? | It is not, or Robert accepts keeping it | It is, and it must go at erasure | Argument from the wiki, then Robert. Claude is not a lawyer and says so |
| Q5 | Can the types stop a write from copying an opened value into the state? | They cannot, so opening in a write must be refused whole | They can, by a label on what was opened | Argument, and experiment 20 for what Mo refuses today. A label is idea 9, which has no design |

## 5. The experiments

House rule for each: predictions with a confidence are written in `experiments.md` and committed before any run, and are never edited after. Code is committed before the full run. The result goes in a dated "Result of experiment N" section. The predictions below are Claude's drafts.

All runs use the frozen Mo binary at `build/enforcement-trial/mo`. None writes to `~/code/mo`.

| # | What it tests | How | Result that points which way | Draft prediction | Control that must fail | Cost | What the decision loses if cut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 20 | **A run of the record after an erasure (Q2, Q5).** What each option gives when one person is erased and the record is run again | A sketch in `sketches/held-values/`, on the pattern of experiment 18. A held value is a type with hidden insides, and the vault is a map handed to the run. A story of about 30 calls by three people: one write checks an email is not taken, one acts on a personal value, the rest only store. The writes are written four times, for options A to D. Each is run with a full vault, then with one person erased, then through corrected code that puts one new test. Option E is the same story with that person's entries taken out. The state, the replies and the record are compared, and searched for the erased bytes | The same state after erasure under A and C, with nothing of the person found, points to them. A change to other people's replies under D shows what D costs. A cannot be chosen as it stands if erasing the token changes a later reply | A with a kept token gives the same state and replies, at 85%. A with the token erased turns a later refusal into an acceptance, at 85%. C gives the same state in a faithful run, at 80%, and falls to `Erased` in the corrected-code run, at 75%. D changes at least one reply to another person, at 80%, and fewer than 5 of their replies, at 60%. Under E the erased bytes are still found in an entry another person made, at 90%. Today's Mo refuses code outside the module that reads a held value's insides, at 85%, and has no way to let a reply open while a write may not, at 80% | A write that copies the opened value into the state as plain text: the search must find the erased bytes. Erasing nobody must change nothing | Half a day | The options stay sentences. Nobody knows whether "never open" survives the token, or how far an erasure spreads under D |
| 21 | **What writes do with personal values (Q3).** How often a write needs what a personal value says | A census of the write functions agents wrote in experiment 14 (`sketches/write-trial/results/`, 36 functions in four files, a shop with customers who have a name and a city). Each function is sorted by what it does with a personal field: stores it, compares it for sameness, checks its form, or acts on what it says | Nearly all "stores it" or "compares for sameness" points to A. A fair share of "acts on what it says" points to C or D | Under one in five of the functions that touch a personal field do more than store it, at 60%. None acts on what the value says, at 55% | A planted function that branches on the city must be sorted as "acts on what it says" | 1 to 2 hours | Q3 is answered from Claude's guess at what applications do |

**Not experiments.** Q4 is argued from the wiki and is Robert's. Q1 is Robert's.

**The limits, said now.** The story and the four sets of writes in experiment 20 are Claude's own. There is no real vault to compare with, so the expected result of the option D run is worked out by hand and committed with the predictions. The census in experiment 21 is one shop, written by agents who were told nothing about personal data.

## 6. Order, and where Robert decides

1. **Robert accepts, changes or cuts this plan.**
2. Write "Decision 4" in `experiments.md` in the shape of Decision 3. Move its line out of "Decisions waiting". Commit.
3. **Optional research panel. Robert accepts or skips.** Claims about earlier work: what a reader gets after a key is destroyed in stores that replay events; whether workflow engines can replay a history whose payload can no longer be read; how "same email" is checked over values that are held apart; what the EU guidance says of a kept hash or token; how systems with labels on sensitive data choose their release functions. Claude recommends accepting, at 60%. Everything Claude knows about these is from memory and unchecked, and the panel for Decision 3 corrected five of 25 such claims and added a use nobody had listed. The reason to skip is cost.
4. **Robert answers Q1:** what a run of the record must give after an erasure. This comes before the experiments because "another history is acceptable" makes option D enough, and experiment 21 then matters little.
5. Experiment 21, then 20. Predictions are committed before each. Cheapest first.
6. **Robert decides between A, B, C, D and E.** Claude gives a recommendation and a confidence then.
7. Bring `design.md` section 4 (need 8 and "names by hash fight erasing"), section 8 line 13 and section 9 into line. Commit.

Robert can stop after any step. Each experiment stands alone.

## 7. Where Claude stands

These rest on reading and on argument. Nothing has been measured.

| Option | Confidence | Why |
| --- | --- | --- |
| C | 35% | It is the rule the design already has for an agent's world: a question counts by its answer. A faithful run stays the same after an erasure. A run through new code that asks something new gets `Erased`, and that can be listed like any other changed call |
| A | 25% | It is the only option where erasing leaves nothing behind. But the token is the weak point, and a write that must act on a personal value cannot be written |
| D | 25% | It asks least of the types, and Decision 3 already accepts runs that differ. But an erasure then changes history without anyone asking, and it mixes with the changes a run was made to find |
| B | 10% | It is A with the hard cases moved to the door. Each fact is still kept for good |
| E | 5% | It rewrites history, and experiment 18 showed how far that spreads |

- **A write that opens a value can copy it into the state,** where erasing does not reach. So C and D are safe only if the types stop that, or if what comes out of the value is small. That is why C offers a test and not the value.
- **The token decides more than it looks.** If a kept token is the person's data, option A cannot check "is it taken" and stay the same after an erasure. Then A needs C's kept answer for that one case.
- **The options can be mixed.** A could be the rule, with C for a write that declares its test.

What would move it:

- **Toward D:** Robert answers Q1 with "another history is acceptable"; experiment 20 shows an erasure changes few replies.
- **Toward A:** experiment 21 finds writes almost never need what a personal value says; Robert accepts a kept token.
- **Away from C:** experiment 20 shows kept answers are useless to a run through corrected code; Robert counts a kept answer as the person's data.

## 8. What was cut and why

| Cut | Why |
| --- | --- |
| Where an erased value's bytes remain in today's Mo store | It informs how a vault is built, not what a write may do. The record keeps arguments by decision, so holding must happen at the door whatever today's store does |
| A fresh trial where agents write writes under each rule | Half a day or more. The census of experiment 21 comes first; the trial is added only if the census is too thin to answer Q3 |
| How long a held value is kept, and opening many at once | They belong to sensitivity, need 5 of the layer for outside callers |
| Indexes and saved answers over held values | They belong to "views kept current and erasing inside the runtime", which has not been sketched |
| A vault on disk that truly destroys bytes | A build question. The sketch's vault is a map |
| Names by hash or by number | A separate waiting decision. This decision bears on it: with held values the tree holds references, so erasing no longer changes a hash |
| A legal reading of what counts as personal data | Claude is not a lawyer. The wiki's sources are quoted and Robert decides how strict to be |

## Not verified while writing this plan

- That today's Mo refuses, when compiling, code that reads the insides of a hidden type. Read in Mo's reference only. Experiment 20 finds out.
- Whether a Mo program can hand a map to a function as the sketch's vault and keep it out of a service's state. Experiment 20 finds out.
- Every claim listed under step 3. They are from Claude's memory.
- That the 36 write functions of experiment 14 touch a personal field often enough to count. The count of functions was read; their bodies were not.
