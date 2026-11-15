### 1. Verdict

**Accept the rule as written** ([design.md:213](design.md:213)), at **68%** confidence.

Claude's bound proposal adds schema and promise machinery to cure an artifact of random whole-row writes. Point 2 ([design.md:224](design.md:224)) already says a write redoes only parts that read what it changed. In `S22.bought` ([22-a-gpt-bought.mo:5](sketches/enforcement-trial/results/answers/22-a-gpt-bought.mo:5)), `Reference.bought` ([reference-a.mo:26](sketches/enforcement-trial/reference-a.mo:26)), and `Planted.bought_in_order` ([planted.mo:81](sketches/planner/controls/planted.mo:81)), parts read only `order.id` and `order.customer`, so ordinary write functions (`place_order`, `pay`, `ship`, `edit_note`) need not redo any line parts. Where fan-out is real (deleting an order, reassigning `order.customer`), one accepting word on the kept read suffices: across 21 agent reads ([report-13.txt:2](sketches/planner/results/report-13.txt:2)), only `S22.bought` flagged any write.

### 2. Strongest case against Claude's recommendation

- **Who enforces the bound, and what violation does:** Under [design.md:183](design.md:183), invariants are promises checked before commit; violations abort the write ([design.md:190](design.md:190)). Making `lines per order <= N` a checked promise adds an index check to every `Line` write and turns a compile-time cost hint into a runtime failure when a customer adds item `N + 1`. Leaving it unchecked lets broken promises silently hide growing upkeep.
- **Accepting word with a number attached:** Because per-part work varies, the compiler has no principled cap separating `N = 10` from `N = 1_000_000`. Without an arbitrary compiler limit, authors and agents will write huge `N` to silence the error while avoiding runtime rejections — recreating the accepting word with a misleading number.
- **Store self-measurement:** Experiment 5 closed dynamic growth checks ([experiments.md:702](experiments.md:702)); at compile time a fresh store has no rows to measure. At runtime, equality indexes ([core.py:74](sketches/planner/core.py:74)) already hold exact group sizes, so the store can report observed fan-out without source-level guesses.
- **Where it goes:** A reference bound lives on the type (`Line.order`), coupling data definitions to whichever kept reads exist today and forcing schema edits when new reads arrive. Putting the word on the write blames write authors for someone else's read ([design.md:254](design.md:254)). Putting the accepting word on the **kept read** places the choice where the ask-vs-upkeep trade-off is made.
- **Store artifact:** [planner.py:215](sketches/planner/planner.py:215) hardcodes `[40, 25, orders, orders * 3]`. In a B2C store where customers grow with orders (~3 orders/customer), `customers` is also flat; in B2B bulk ordering, `orders` grows. "Orders flat, customers growing" is an artifact of those four constants.

### 3. What would lower Claude's 70%

- **Experiment A — Field-sensitive write functions:** Replace random [`fresh`](sketches/planner/planner.py:98) overwrites with Mo write functions (`place_order`, `add_line`, `pay_order`, `ship_order`, `edit_note`, `cancel_order`), and refine [`fans`](sketches/planner/plan.py:162) and [`after`](sketches/planner/planner.py:337) so outer-row updates rebuild pairs only when fields read by the cut (`cut["fields"]`, `cut["needs"]`) change or a row is deleted.
  - *Counts against:* `place_order`, `pay_order`, `ship_order`, and `edit_note` fan out to 0 lines without any bound; only `cancel_order` flags `orders`.
  - *Prediction:* Only `cancel_order` (1 of 5 order writes) is flagged and mean order upkeep drops below 12 rows, at **85%**.
  - *Control that must fail:* Skipping [`paired`](sketches/planner/planner.py:294) when `order.customer` changes must spoil `S22.bought`, `Reference.bought`, and `Planted.bought_in_order`.
- **Experiment B — Skewed carts under enforced bounds:** Give `lines.order` ([planner.py:106](sketches/planner/planner.py:106)) a heavy tail (mean 3 lines, 1% wholesale orders with 60–100 lines), enforce `lines_per_order <= N` in [`Table.put`](sketches/planner/core.py:41), and sweep `N` over `10, 25, 100, 500`.
  - *Counts against:* Tight `N` rejects valid orders; loose `N` permits >700-row upkeep spikes (exceeding `products` mean 252.3).
  - *Prediction:* No `N` achieves both 0 rejected writes and `most` order upkeep under 500 rows, at **80%**.
  - *Control that must fail:* Inserting line `N + 1` on one order must abort and leave kept answers unchanged.

### 4. What would raise it

- A census across 4–5 diverse Mo applications showing few-to-one references are pervasive and carry genuine domain caps programmers already want enforced as business promises.
- Real write functions that routinely mutate parent fields read inside child parts (e.g. `order.discount` in kept line totals), leaving common writes flagged even under field-level tracking.
- A principled compiler rule (`N * part_cost <= budget`) preventing huge-`N` loopholes.

### 5. What is wrong, overclaimed, or untested in Experiment 13

- **Zero agent reads grew on writes:** In [report-13.txt:64](sketches/planner/results/report-13.txt:64), `customers` (`Planted.spend_by_city`) and `products` (`Planted.bought_in_order`) are flagged solely by planted reads ([planted.mo:26](sketches/planner/controls/planted.mo:26), [planted.mo:81](sketches/planner/controls/planted.mo:81)). Among the 21 agent reads, 0 caused growing writes and 1 (`S22.bought`) caused a flat flag — 100% false positives on natural code.
- **Unconditional outer rebuilds and pre-seeded orphan lines:** [`after`](sketches/planner/planner.py:337) calls [`paired`](sketches/planner/planner.py:294) on every write to `cut["table"]` without checking changed fields; [`fresh`](sketches/planner/planner.py:104) randomizes `order.customer` on updates; and [planner.py:106](sketches/planner/planner.py:106) generates `line.order` up to `orders + 20`, attaching orphan lines even to brand-new order inserts.
- **Miscounted adjustments and zero-cost deletes:** [planner.py:339](sketches/planner/planner.py:339) increments `done += 1` per `paired` call regardless of inner pairs rebuilt, so [report-13.txt:51](sketches/planner/results/report-13.txt:51) and [report-13.txt:57](sketches/planner/results/report-13.txt:57) report `adjusted: mean 5.0, most 5` for `customers` at both 300 and 1,200 orders while pair work quadrupled. Meanwhile [`drop`](sketches/planner/planner.py:263) and [`by_equal`](sketches/planner/core.py:74) never increment `machine.touched`, so deletes (20% of writes, [planner.py:393](sketches/planner/planner.py:393)) record 0 rows read during `O(fan-out)` teardowns.
- **Gaps in [`refused`](sketches/planner/plan.py:157) and [`fans`](sketches/planner/plan.py:162):** [plan.py:159](sketches/planner/plan.py:159) checks `class_of == "walked"`, so omitting `walk` on a `kept` whole-table read (`S37.idle_customers`, `Planted.unlined`, [plan.py:321](sketches/planner/plan.py:321)) is silently accepted. In [plan.py:170](sketches/planner/plan.py:170), `(outer, inner)[row]` misreports outer-field lookups inside pairs (`row == 0`) as one part per `outer` row instead of `inner`. Single-row Point 4 (e.g. `.filter().map()` lookups where `free` is `False`, [plan.py:397](sketches/planner/plan.py:397)) went untested.

Verdict: accept as written, 68%
