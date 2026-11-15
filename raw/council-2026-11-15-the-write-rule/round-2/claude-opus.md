I read all three round-1 answers, design.md §5 and the write-path lines of design.md. I edited nothing and ran nothing.

## 1. Where the others are right, and where they are wrong

**I was wrong.** In round 1 I said customer upkeep "does not fit the claimed mechanism." Gemini found the cause (gemini-carbon.md:36): `planner.py` adds 1 to its count per `paired()` call, not per pair. So the mechanism holds and only the column's label was wrong. I withdraw that point.

**Gemini is right, and it matters more than I allowed.** Point 2 already says "a write redoes only the parts that read what it changed" (design.md:224). The script redoes the parts of a whole row on every write, so experiment 13 ran the rule more coarsely than design.md states it. The chair's check goes further than my round-1 point A: the growing flags have the same shape. `spend_by_city` reads a customer only through `id` and `city`. So working at field grain shrinks all three flags to two kinds of write: deletes, and writes that change a field a part reads. It does not only remove the false alarm on orders. In round 1 I treated field grain as a check to run before adopting the bound. It is really the question of whether the bound is needed at all.

**Gemini is wrong** in two places:
- One accepting word on the kept read does not "suffice" for the writes that still fan out. A customer who moves city really does redo one part per order they have, and nothing caps that.
- A bound on lines per order states a fact about the data. It is not tied to whichever reads exist today. Gemini's sweep of N treats rejected over-limit orders as failures; when N is a real domain limit, rejecting them is correct.

**GPT Sol is right** that a bound must be atomic and checked against every way of changing a reference, and that a bounded write is not therefore a cheap one. **GPT Sol is wrong** in two places:
- It backs the change at 75% without addressing field grain, which is the strongest reason the change may be unnecessary.
- Its first experiment, a Mo model of enforcement, mostly tests what the design already provides. A promise is checked on the new version, and an error changes nothing (design.md:183-191). A count kept on the existing `lines.order` index is a promise.

## 2. Verdict

My verdict moved. In round 1 I said: adopt the bound, after testing field grain. Now I say: keep the write half as written, and make the planner work at field grain, as point 2 already says. Add a bound only if the field-grain rerun still flags many writes on references that have a real domain limit.

What moved me is the chair's finding that the growing flags also rest on one or two fields. With writes tracked by field, the error should fire mostly where the fan-out is real, and an unneeded mechanism is the larger risk. Confidence: 62%.

## 3. Which experiments to run

**First: writes tracked by field, using real write functions.** This is my round-1 A and Gemini's A; they are the same experiment.
- Have fresh agents write the shop's write functions (pay, ship, edit a note, add a line, cancel, reassign). Do not write them ourselves, because whoever picks the writes picks the result.
- Then change `fans()` and `after()` so a write redoes only the parts that read a field it changed.
- **Lowers the 70%:** ordinary order writes lose the flag, and only deletes and reference changes stay flagged. The bound would then have little left to discharge.
- **Raises it:** agent-written writes often change fields that parts read (Gemini's `order.discount` case), so ordinary writes stay flagged.
- **Control that must fail:** skip the rebuild when `order.customer` changes. `S22.bought` and `Planted.bought_in_order` must then disagree with Mo at a checkpoint. If they still agree, field grain is dropping work it needs.

**Second: agents choose bounds,** run with field grain in place. This is my round-1 E and GPT's third experiment.
- I am deliberately not choosing the skew experiment (my B, GPT's "average vs maximum", Gemini's B; also one experiment under three names). All three of us predict its result at 80–95%, so it would tell us little.
- **Lowers the 70%:** agents write bounds of 100 times the real figure or more, or invent bounds on references that have no limit (a customer's orders). Then the bound is just the accepting word with a number attached.
- **Raises it:** agents choose bounds close to the domain's real limits, and leave the unbounded references unbounded.
- **Controls that must fail:**
  - A bound set too small must refuse an over-limit line and leave the kept answers unchanged.
  - A task with no natural limit must produce no bound.

## 4. An option none of us put forward

None that I would bet on. Dropping the write error and keeping only the report (point 5) breaks the decision of 2026-11-15 that a write is held to the same rule as a read (design.md:209).

I did not check which fields `Planted.bought_in_order` reads from a product, so the claim that field grain also shrinks the products flag is my inference. The main risk is that the first experiment comes out however its chosen writes make it come out.

Verdict: other: keep the write half as written, make the planner track writes by field as point 2 already says, and add an enforced bound only if the rerun leaves many flags on references with a real domain limit, 62%
