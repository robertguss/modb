I worked alone and read-only: I changed no file and started no agents. Here is the review.

**1. My choice**

*For the program's own code: A (strict), with D as the check on it.* On a stored table, a filter the compiler can't give a fast route is a compile error unless the code says `walk`. Every Mo error already carries a fix that `mo fix` can apply (reference, Appendix A). So the error can offer the two ways out: "add `index orders_by_buyer: orders by buyer`" or "write `walk`". Agents act on errors that come with a fix.

The other options fall away for these reasons:
- **B is out by Mo's own rule.** The reference says "There are no warnings: a problem is an error, or it isn't reported" (Appendix A).
- **C is opt-in.** A slow read in a function nobody marked still arrives unnoticed, which fails the question as posed.
- **F was already rejected.** Row 4 of the rejection table: an intent digest is equal or not, with no direction.

D stays as a test-time check that the recogniser told the truth. The plain walk is the oracle, and the instruction count is the measure.

*For a read program an agent sends at run time: D only, with no static gate.* An agent can't add an index, and design-ideas.md §8 needs unplanned questions to walk. Rejection row 5 already notes that the instruction limit bounds every walk. So run the program, refuse it over its budget, and return and log its exact instruction count. That log is what "the database proposes an index" needs.

**2. The strongest argument against A**

Strict makes the recogniser's coverage part of what the language means. Whether a program compiles then depends on which shapes the pass knows. Ordinary refactors can break the build: pulling the test out into a named function, using `count` or `find`, or writing a `for` loop. That is a query language in disguise, with grammar you can't see. E is the honest form of the same thing.

The learnability corpus points this way. Across its 368 `.mo` files I counted 817 `for … in` loops against 80 `.filter(` calls. In `lib/list.mo`, `filter` is itself a `for` loop with `append`. So agents may mostly write the shape the compiler would miss.

**3. Experiments, in the order I'd run them**

1. **Shape census.**
   - Built: a Python recogniser over the agent-written Mo in `learnability/` and the read functions in `sketches/kept-versions/worlds.mo`. It labels each piece of code that picks rows as *recognised shape* or *missed*.
   - Result to show: at least 60% of code that picks rows by one field is in a recognised shape.
   - Prediction: below 60%, at 75%.
   - Control that must fail: a planted file of `for`-loop filters must all come out *missed*.
   - Needs from Mo: nothing.
2. **Survival under refactor.**
   - Built: 20 recognised filters, each put through the rewrites agents actually make: a named test function, `count`, `find`, `any?`, a `for` loop, `and` across two fields, `!=`.
   - Result to show: at least 80% stay recognised under a pass of reasonable size.
   - Prediction: below 80%, at 70%.
   - Needs from Mo: nothing.
3. **Can D tell the two apart on Mo today?**
   - Built: a sketch service with a `Map` standing in for an index, plus one read through it and one walk. The cost of each is measured exactly with `mo query --max-work`, halving the limit as `asked-again.py` already does, at 1,000 and 4,000 rows.
   - Result to show: the index read's count grows by at most 1.2 times, the walk's by at least 3.5 times, and the counts match across two runs.
   - Prediction: holds, at 85%.
   - Control that must fail: the walk.
   - A second control: an index read whose answer grows with the store, such as `orders_by_buyer.all(buyer)` when a buyer's orders grow with it. It must not fail, or D needs the answer's size held fixed.
   - Limits in Mo: `mo query` needs an export, and `mo fetch` takes 28 s at 50,000 rows, so keep the sizes small. A native `Map.get` may count as one VM instruction whatever the map's size.
4. **Agents under A versus E.**
   - Built: 10 read questions over one schema, in two arms. In one, a script stands in for `mo check` and returns E-coded errors with fixes. In the other, the table has closed-form methods (`where(field, value)`). Several agents, Wilson intervals from `learnability/wilson.py`.
   - Result to show: within one round of fixes, arm A gets correct answers on the fast route at least as often as arm E.
   - Prediction: A is no better, at 55%.
   - Needs from Mo: nothing. The `Table` methods are mocks over `Map`.

**4. Run first, and what would change my choice**

Run experiment 1 first. It is the cheapest, needs nothing from Mo, and is the one most likely to sink the idea.

Two results would change my choice:
- If 1 and 2 both come out low (say under 40% coverage and under 50% survival), A becomes a tax on ordinary code. I'd switch to E with A's enforcement: a stored `Table` has no `filter` and no iteration except `walk`.
- If 4 shows A matching E after one round of fixes, I keep A.

**5. What is missing**

*An option you didn't list.* The type enforces it, not a pattern-matcher. A stored `Table` is not a `List`: it offers `get`, the index methods and one explicit `walk(fn)`. Nothing has to be recognised to catch a slow read, because a slow read can only be written as `walk`. Shape recognition then becomes an optimisation inside `walk`, not a gate.

*The flaw most likely to sink "plain Mo is the query language" has three parts:*
- **The compiler has to trust named library functions.** `filter` is plain Mo, not a primitive. Recognising it means special-casing `List.filter`, `count` and `find` by name. That is a query vocabulary, just not called one.
- **D measures the wrong cost once data lives on disk.** VM instructions are not node reads. An index lookup and a walk could cost the same instructions per call while differing a thousandfold in disk reads. That would need a node-read counter, which Mo doesn't have (design.md §8, lines 1 and 3).
- **Agents' habits.** The `for` loops outnumber `filter` calls about ten to one, though that count covers all code, not only read functions.

**6. Confidence**

I'm 60% confident in my choice in item 1.

I didn't read `src/`, so it's an assumption that a native `Map.get` counts as one instruction. The `for` versus `filter` count is a raw grep across all learnability code, not just read functions.
