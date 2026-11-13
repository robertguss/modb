Research run on 2026-11-13 by a subagent using Exa, for the ticket [Keeping sensitive data from agents and model providers](../issues/20-keeping-sensitive-data-from-agents.md). Lines marked "inference" are the researcher's reasoning. This is research, not legal advice. Personal data in histories, crypto-shredding and excision are in [05](05-databases-that-keep-history.md) and not repeated.

# Keeping sensitive data from agents and model providers (researched 2026-11-13)

## 1. Four words that are not the same

- **Masking** changes what a reader sees; the stored value is untouched. *Dynamic* masking rewrites query results; *static* masking rewrites a copy.
- **Pseudonymising** replaces an identifier with a stand-in (token, code). Whoever holds the key or table can reverse it.
- **De-identifying** is a US legal term: data that passes a named legal test falls outside the law (HIPAA, FERPA).
- **Anonymising** is the EU term for data that can no longer be linked to a person by means "reasonably likely" to be used. It falls outside the GDPR.

What the law recognises:

- **EU.** Pseudonymised data "remains information related to an identifiable natural person and is therefore still personal data", even when the key is held elsewhere or erased (EDPB Guidelines 01/2025, adopted for consultation 16 January 2025) https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf. The Court of Justice softened this in *EDPS v SRB* (C-413/23 P, September 2025): pseudonymised data is not personal "in all cases and for every person". For a recipient with no reasonable means to re-identify, it may not be. The sender keeps its duties as the data stood before transfer (paras 86, 110) https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A62023CJ0413. The anonymity test asks three things: can anyone be *singled out*, can records be *linked*, can attributes be *inferred*. Pseudonymisation fails all three https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2014/wp216_en.pdf.
- **US.** HIPAA and FERPA recognise de-identification (section 2). Masking has no legal standing of its own.

## 2. What HIPAA and FERPA require before records reach a model provider

**HIPAA** covers health data with identifiers (*PHI*, protected health information) held by a *covered entity* such as a hospital. Three paths:

1. **Business associate agreement (BAA).** A vendor that receives, stores or transmits PHI for a covered entity is a *business associate* and must sign one, "even if the CSP processes or stores only encrypted ePHI and lacks an encryption key" https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html. A model provider receiving PHI is in the same position (inference; I found no HHS page on model providers). Some providers sell BAA-covered products (vendor claim) https://help.openai.com/en/articles/20001069-hipaa-eligible-products-and-functionality.
2. **De-identify first** https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html:
   - *Safe Harbor:* remove 18 listed identifiers, among them names, places smaller than a state, all date parts but the year, and "any other unique identifying number, characteristic, or code". The entity must also lack "actual knowledge" that the rest identifies someone. Free text counts: a note that a patient is "Executive Vice President of the state university" must go.
   - *Expert Determination:* an expert documents that risk is "very small" for the anticipated recipient. HHS sets "no explicit numerical level", cites k-anonymity as one model, and notes time-limited certificates.
3. **Limited data set** under a data use agreement in which the recipient promises not to re-identify (45 CFR 164.514(e)) https://www.ecfr.gov/current/title-45/subtitle-A/subchapter-C/part-164/subpart-E/section-164.514.

Stand-ins are constrained. A kept re-identification code must not be "derived from or related to information about the individual" (164.514(c)). A hash of a name or patient number therefore fails Safe Harbor. HHS allows keyed hashes only under Expert Determination, "provided the keys … are not disclosed, including to the recipients".

**FERPA** covers student education records and their *PII* (personally identifiable information).

- A school may share PII without consent with a vendor acting as a "school official". The vendor must do work staff would otherwise do, stay "under the direct control" of the school over use and maintenance of records, and not re-disclose https://studentprivacy.ed.gov/sites/default/files/resource_document/file/Student%20Privacy%20and%20Online%20Educational%20Services%20%28February%202014%29_0.pdf.
- Data is de-identified when "a reasonable person in the school community" without personal knowledge cannot identify a student "with reasonable certainty" https://studentprivacy.ed.gov/faq/what-constitutes-de-identified-records-and-information. It is a judgment, not a checklist. States set minimum group sizes of 5 to 30, most often 10, and the Department warns hidden cells "can often be easily calculated by subtracting" https://studentprivacy.ed.gov/sites/default/files/resource_document/file/FAQs_disclosure_avoidance_0.pdf.
- The July 2025 letter on AI only restates that AI systems "must comply with" FERPA https://www.ed.gov/media/document/opepd-ai-dear-colleague-letter-7222025-110427.pdf.

## 3. What databases already ship

**Dynamic masking (SQL Server, Oracle, Snowflake, PostgreSQL Anonymizer).**

- *For:* hiding values from staff who use fixed application screens.
- *Core idea:* a column policy rewrites values on output by role.
- *Strength:* no copy to keep in sync. *Paid for by:* the real value stays live, and filters run on it.
- *Weakness, in the vendors' own words.* Microsoft: users "with ad hoc query permissions can apply techniques to gain access to the actual data" https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking?view=sql-server-ver17. Oracle: redaction puts no limit on "the WHERE clause", which can be used "in an iterative fashion to infer the actual data"; SYSDBA is exempt https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/security-considerations-for-using-oracle-data-redaction.html. PostgreSQL Anonymizer declares rules in the schema (`SECURITY LABEL … 'MASKED WITH FUNCTION …'`) and offers dynamic, static, replica and dump masking https://postgresql-anonymizer.readthedocs.io/en/stable/. Its docs warn noise falls to repeated queries plus `AVG()`, and generalisation (value to range) cannot be used dynamically https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/.
- Snowflake attaches policies to tags; a tag on a schema protects new columns of matching type https://docs.snowflake.com/en/user-guide/tag-based-masking-policies.
- *Agent struggle (inference):* an agent writes ad hoc SQL. It is the reader these features say they do not stop, and many agents probing in parallel only speed the search.

**Static masking on branches (Neon, Xata).** Neon makes an "anonymized branch" and runs PostgreSQL Anonymizer static masking on it, with rules per branch https://neon.com/docs/workflows/data-anonymization. Xata offers the same idea ([09](09-agents-and-databases-today.md)). *Strength:* no real values in the copy, so filters reveal nothing. *Paid for by:* a stale copy, protected only as well as hand-written rules. Untagged and free-text columns pass through.

**Row and column security.** PostgreSQL row policies hide rows, but unique and foreign-key checks "always bypass row security", a "covert channel" https://www.postgresql.org/docs/current/ddl-rowsecurity.html. `LEAKPROOF` functions may run before the policy for speed https://www.postgresql.org/docs/current/sql-createfunction.html. This hides; it does not transform.

## 4. Beside the database

**Tokenization vaults** such as Skyflow hold real values in a separate store; everything else holds tokens, which authorised callers swap back. It is marketed for prompts and RAG (vendor claim) https://www.skyflow.com/data-privacy-vault. *Strength:* neither the database nor the model holds the value. *Paid for by:* a lookup hop and key custody. Under the GDPR the tokens remain personal data.

**Redaction gateways** sit in front of the model provider. LiteLLM runs Microsoft Presidio, a detector for names, numbers and similar, swaps hits for placeholders, and with `output_parse_pii` swaps them back in the reply https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2. *Strength:* works on free text with no schema. *Paid for by:* statistical detection, so misses are silent (section 6).

## 5. Stronger techniques

- **Consistent pseudonyms.** Same person, same stand-in, so joins and counts work. Most useful for agents; also what makes linking possible.
- **k-anonymity.** Generalise or suppress until each record matches at least *k−1* others on fields an attacker could know. It stops singling out, not inference when a group shares one sensitive value (WP216 above).
- **Differential privacy (DP).** Noise sized so one person's presence barely moves an answer. Each query spends part of a fixed *privacy budget* (epsilon). OpenDP SmartNoise wraps a database connection and answers aggregate SQL this way https://docs.smartnoise.org/sql/. *Paid for by:* totals only, never rows, and the budget runs out. With many agents it is one shared resource the first greedy agent can drain (inference).
- **Synthetic data.** Generated rows with the same statistics. A USENIX Security 2022 study found it "either does not prevent inference attacks or does not retain data utility"; outliers stay linkable, and two common DP generators broke their own guarantees https://www.usenix.org/conference/usenixsecurity22/presentation/stadler.
- **Confidential computing.** Inference runs in a hardware enclave (*TEE*, trusted execution environment) the operator cannot read, which proves its code by *attestation*. Cohere sells this on NVIDIA H100s (vendor claim) https://cohere.com/blog/introducing-confidential-computing-on-cohere-model-vault. Anthropic has published a design it is "working on" https://www.anthropic.com/research/confidential-inference-trusted-vms. TEE.fail (October 2025) used cheap off-the-shelf equipment on DDR5 memory to extract attestation keys from Intel TDX and AMD SEV-SNP, then used them against NVIDIA GPU confidential computing https://tee.fail/. It needs physical access, which is exactly the operator a TEE excludes. A TEE hides data from the provider, never from the model.

## 6. How hidden data is recovered anyway

1. **Filtering on a masked column.** Documented by the vendors (section 3); each range query halves the candidates.
2. **Joining harmless fields.** A 2019 model estimates "99.98% of Americans would be correctly re-identified in any dataset using 15 demographic attributes" https://www.nature.com/articles/s41467-019-10933-3.
3. **Small groups in totals.** A count of one, or a hidden cell recovered by subtraction (FERPA guidance above). Only DP holds up across many combined queries.
4. **Names in free text, now with agents.** AgentDoxx (October 2026, 822 synthetic interview transcripts about real people): after entity masking, "at least one attacker" still re-identified 85.3% of a stratified sample. Privacy instructions stopped models *naming* the person but they still *retrieved* the subject in up to 62% of transcripts https://arxiv.org/abs/2610.05586. Agents with web search linked 6 of 24 published scientist interviews to their authors https://arxiv.org/abs/2601.05918. A 2026 pipeline re-identifies pseudonymous users "at high precision" from raw text https://arxiv.org/abs/2602.16800.

Inference: an agent is both the reader to guard against and a tireless linking engine. Masked data given to an agent with web access is far weaker than the same data given to a person.

## 7. What an agent can still do with stand-ins

- **Works:** counting, grouping and joining on consistent tokens; passing a token through a workflow while a trusted tool swaps it back at the edge (send the email); exploring schemas; debugging on a masked branch.
- **Breaks:**
  - Ranges, sorts and format checks on randomised values.
  - Tasks needing real-world knowledge of the entity. Retrieval tasks fell up to 47 points (0.80 to 0.32) on pseudonymised input, and stronger models lost most https://arxiv.org/abs/2609.11335. Consistent, realistic pseudonyms cut utility errors about fivefold versus blunt placeholders https://arxiv.org/abs/2510.27016.
  - A model that invents a value instead of copying the token leaves nothing to swap back.
  - A model can restate a sensitive fact it inferred, with no token to catch.

## 8. Sensitivity in the data's types

- **Shipped, partly.** PostgreSQL Anonymizer labels columns. Snowflake tags can *propagate*: a `data_sensitivity` tag on a table flows to views and tables built from it https://docs.snowflake.com/en/user-guide/object-tagging/propagation. That is the closest shipped thing to sensitivity following data through derivation, but it governs reads inside Snowflake, not what a permitted reader carries out.
- **Research.** IFDB (MIT, 2013) modified PostgreSQL so rows carry information-flow labels and results are tainted by what they read. It handles transactions and constraints "without introducing covert channels" at about 1% throughput cost https://pmg.csail.mit.edu/pubs/schultz13__ifdb_decentralized_ifc-abstract.html. For agents, CaMeL tags values with provenance and allowed readers and checks tool calls against policy https://arxiv.org/abs/2503.18813. FIDES propagates confidentiality labels through tool calls, but its authors say their confidentiality guarantee "does not prevent implicit flows" (leaks through which branch ran) https://arxiv.org/abs/2505.23643.
- **Answer.** I found no shipping database that types sensitivity and enforces it on *every* exit: results, errors, timing, constraint failures, logs, backups and the model call. IFDB came closest and never shipped.

## 9. "No database anonymises sensitive data": where it is wrong and where it holds

- **Wrong.** Databases ship tools that change what leaves. PostgreSQL Anonymizer, Neon and Xata produce masked copies; Snowflake masks by tag; DP query layers exist. A static, generalised copy checked by an expert can meet HIPAA de-identification. After *SRB*, a pseudonymised extract may not be personal data for a recipient who cannot re-identify.
- **Holds.** Nothing ships that makes data anonymous in the legal sense, automatically, for a reader who runs arbitrary queries. Dynamic masking is explicitly not built for that reader. Static rules miss free text and untagged columns. Pseudonyms stay personal data in the sender's hands. LLM agents defeat "remove the names" in most measured cases. Anonymity depends on the recipient and what else it can reach, so a database alone cannot certify it (inference, consistent with HHS's "anticipated recipient" and WP216).

## Summary table

| Mechanism | What it protects | What pays for it | How it is defeated |
| --- | --- | --- | --- |
| Dynamic masking | Casual sight of values | Real value live for filters | WHERE probing; admin roles; noise averaging |
| Static masking / masked branch | Copy holds no real values | Stale copy; hand-written rules | Untagged and free-text columns; joins |
| Row and column security | Whole rows or columns | Policy checks; LEAKPROOF exceptions | Constraint and timing side channels |
| Tokenization vault | Value never in DB or prompt | Lookup hop; key custody | Tokens still link records; swap-back abuse |
| Redaction gateway | Detected entities in prompts | Statistical detection | Misses; indirect identifiers; invented values |
| Consistent pseudonyms | Direct identifiers, keeps joins | Linkability by design | Linking on other fields; key leak |
| k-anonymity | Singling out | Coarser data | Uniform groups; repeated releases |
| Differential privacy | Each person's contribution | Totals only; finite budget | Budget exhaustion; buggy implementations |
| Synthetic data | Real rows not shipped | Unpredictable utility | Outlier linkage; membership inference |
| Confidential computing | Data from provider's operators | Hardware trust chain | Physical memory interposition (TEE.fail) |

## Ideas worth borrowing

1. **Sensitivity in a field's type, labels that propagate through derivation (Snowflake, IFDB), one exit point every result, error and log passes through.** Cost: every operator must define how labels combine, and side channels must be designed out from the start.
2. **Agents work on tokens; only trusted edge tools swap them back.** Cost: a key store, a second trust boundary, lost utility where entity knowledge matters.
3. **Totals for agents spend a DP budget held per dataset, not per agent.** Cost: noisy answers and a policy for who spends.
4. **Keyed pseudonyms whose key never leaves the database.** Cost: HIPAA treats them as Expert Determination, not Safe Harbor.
5. **Free-text fields sensitive by default.** Cost: agents lose most of their value unless cleared.

## What I could not confirm

- Whether the EDPB finalised Guidelines 01/2025, or revised them after *SRB*; and the judgment's exact day (sources show September 2025).
- Any HHS document on model providers specifically. A consultancy reports the OCR director said in September 2026 that AI vendors handling PHI are business associates; I found no primary source.
- Whether Neon's or Xata's masking reaches JSON and free text beyond user-written rules, and whether Snowflake tag propagation covers every derivation path (for example, unloads to files).
- When Anthropic's confidential inference reaches customers.
- Most agent re-identification papers cited are 2026 preprints, not peer-reviewed.
