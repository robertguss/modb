# How hidden data is recovered anyway

Masked, pseudonymised or summarised data can often be tied back to people. Agents make this easier: an agent is both the reader to guard against and a tireless linking engine (inference, [20](../../research/20-keeping-sensitive-data-from-agents.md)).

## What it is

*Re-identification*: recovering who a record is about, or the hidden value, from what was left visible. The EU anonymity test asks three things: can anyone be *singled out*, can records be *linked*, can attributes be *inferred* (https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2014/wp216_en.pdf).

## The problem it solves

None; it is the failure that [masking](dynamic-masking.md), [masked copies](masked-copies.md), [pseudonyms](consistent-pseudonyms.md) and [k-anonymity](k-anonymity.md) each have to survive. Four routes are documented ([20](../../research/20-keeping-sensitive-data-from-agents.md)):

1. **Filtering on a masked column.** The vendors document it; each range query halves the candidates. See [masking query results by role](dynamic-masking.md).
2. **Joining harmless fields.** A 2019 model estimates "99.98% of Americans would be correctly re-identified in any dataset using 15 demographic attributes" (https://www.nature.com/articles/s41467-019-10933-3).
3. **Small groups in totals.** A count of one, or a hidden cell recovered by subtraction (https://studentprivacy.ed.gov/sites/default/files/resource_document/file/FAQs_disclosure_avoidance_0.pdf). Only [differential privacy](differential-privacy.md) holds up across many combined queries.
4. **Names in free text, now with agents.**
   - AgentDoxx (October 2026, 822 synthetic interview transcripts about real people): after entity masking, "at least one attacker" still re-identified 85.3% of a stratified sample. Privacy instructions stopped models *naming* the person, but they still *retrieved* the subject in up to 62% of transcripts (https://arxiv.org/abs/2610.05586).
   - Agents with web search linked 6 of 24 published scientist interviews to their authors (https://arxiv.org/abs/2601.05918).
   - A 2026 pipeline re-identifies pseudonymous users "at high precision" from raw text (https://arxiv.org/abs/2602.16800).

## What it costs

For a defender (inference, [20](../../research/20-keeping-sensitive-data-from-agents.md)):

- Masked data given to an agent with web access is far weaker than the same data given to a person.
- Anonymity depends on the recipient and what else it can reach, so a database alone cannot certify it. This matches HHS's "anticipated recipient" and WP216.
- Research 20 suggests treating free-text fields as sensitive by default; the cost is that agents lose most of their value unless the field is cleared.

Most of the agent re-identification papers are 2026 preprints, not peer-reviewed ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2014/wp216_en.pdf
- https://www.nature.com/articles/s41467-019-10933-3
- https://studentprivacy.ed.gov/sites/default/files/resource_document/file/FAQs_disclosure_avoidance_0.pdf
- https://arxiv.org/abs/2610.05586
- https://arxiv.org/abs/2601.05918
- https://arxiv.org/abs/2602.16800
