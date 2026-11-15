1. **Claude and Gemini identify an omission in my answer: field sensitivity could remove much of the practical case for bounds.** [S22.bought](sketches/enforcement-trial/results/answers/22-a-gpt-bought.mo:5) uses only `order.customer` and `order.id`. Point 2 already promises upkeep only for what changed. I should have tested that distinction before recommending additional machinery.

Claude’s customer-mechanism objection was wrong. [paired()](sketches/planner/planner.py:294) creates the order parts; the adjustment counter undercounts them. His inference that the agent-written order flag was a “false alarm” also goes too far. Flat averages under this generator establish no bound.

Gemini correctly separates ordinary status updates from reassignment and deletion. But their rarity does not establish that explicit acceptance beats an enforced bound. A bound can express a useful domain restriction even when expensive writes are uncommon. Conversely, my recommendation understated that restriction’s cost: legitimate data may become inadmissible. Gemini’s warning about huge bounds is fair; a numeric guarantee is not a speed guarantee.

Gemini’s refusal gap limits the implementation’s evidence, but no corpus read exercises it. It does not decide the write-rule question.

2. **Change as proposed, with the bound declared on the reference and enforced as an invariant: 65%, down from 75%.** Field sensitivity weakens the demonstrated need. It does not remove the distinction between bounded and unbounded fan-out when relevant fields actually change. Keep reporting the dependency and its bound; one bound discharges only the dependency it covers.

3. **First: the field-sensitive experiment.** Claude’s A and Gemini’s A are the same experiment; Gemini proposes a larger implementation. Start with one kept read, `S22.bought`, and two updates: status only, then `order.customer`. Include deletion. Compare affected parts and answers after each operation.

- **Lowers 70%:** ordinary writes avoid pair upkeep, leaving only exceptional operations needing acceptance. That weakens the reason to add bounds.
- **Raises 70%:** representative ordinary writes still change fields read by many parts, so precise tracking leaves a recurring problem that natural bounds could resolve.
- **Control that must fail:** deliberately skip upkeep when changing `order.customer`; an affected customer’s answer must disagree with fresh evaluation. A status-only success without this control proves too little.

**Second: the enforced-bound mutation experiment.** My enforcement trial and Claude’s D are substantially the same experiment. Add the concentrated-order case from my skew proposal; Gemini’s B extends this into a bound sweep, which can wait.

Choose one candidate domain cap, N. Test insertion, reassignment into a full order, deletion freeing capacity, and a batch crossing N. Count removed and rebuilt parts as well as reads.

- **Lowers 70%:** enforcement needs scans, misses a mutation path, leaves partial changes, or the candidate cap rejects required operations.
- **Raises 70%:** indexed checks preserve the invariant atomically, and targeted upkeep stays bounded under concentrated data and increasing store size.
- **Control that must fail:** disable the destination check; reassignment into a full order must violate the invariant. With checking enabled, rejection must preserve both data and kept answers.

4. **No fourth option I would currently bet beats these.** Precise dependencies plus existing promise enforcement may make the amendment small; that combines proposals already present.

This review was read-only. I ran no sketches or planner; the proposed experiments remain untested.

Verdict: change as proposed, 65%
