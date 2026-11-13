# What the law accepts as de-identified

What US and EU law require before records with personal data reach someone else, such as a model provider. This is a summary of research 20, which is research, not legal advice.

## What it is

- **EU: anonymising.** Data that can no longer be linked to a person by means "reasonably likely" to be used falls outside the GDPR ([20](../../research/20-keeping-sensitive-data-from-agents.md)). The test asks whether anyone can be singled out, records linked, or attributes inferred; pseudonymisation fails all three (WP216, https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2014/wp216_en.pdf).
- **US: de-identifying.** Data that passes a named legal test falls outside HIPAA or FERPA. Masking has no legal standing of its own ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **HIPAA** covers *PHI* (protected health information) held by a *covered entity* such as a hospital. Three paths before PHI reaches a vendor:
  1. **A business associate agreement (BAA).** A vendor that receives, stores or transmits PHI must sign one, "even if the CSP processes or stores only encrypted ePHI and lacks an encryption key" (https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html). A model provider receiving PHI is in the same position (inference; research 20 found no HHS page on model providers). Some providers sell BAA-covered products (vendor claim, https://help.openai.com/en/articles/20001069-hipaa-eligible-products-and-functionality).
  2. **De-identify first** (https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html). *Safe Harbor* removes 18 listed identifiers, including names, places smaller than a state, all date parts but the year, and "any other unique identifying number, characteristic, or code", and requires no "actual knowledge" that the rest identifies someone. Free text counts. *Expert Determination* has an expert document that risk is "very small" for the anticipated recipient, with "no explicit numerical level".
  3. **A limited data set** under a data use agreement in which the recipient promises not to re-identify (https://www.ecfr.gov/current/title-45/subtitle-A/subchapter-C/part-164/subpart-E/section-164.514).
- **FERPA** covers student records. A vendor acting as a "school official" may receive them without consent if it stays "under the direct control" of the school and does not re-disclose (https://studentprivacy.ed.gov/sites/default/files/resource_document/file/Student%20Privacy%20and%20Online%20Educational%20Services%20%28February%202014%29_0.pdf). Data is de-identified when "a reasonable person in the school community" cannot identify a student "with reasonable certainty"; it is a judgment, not a checklist (https://studentprivacy.ed.gov/faq/what-constitutes-de-identified-records-and-information). The July 2025 letter on AI only restates that AI systems "must comply with" FERPA (https://www.ed.gov/media/document/opepd-ai-dear-colleague-letter-7222025-110427.pdf).

## The problem it solves

It sets what a database must do before data can leave for a model provider without consent or a contract ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## What it costs

- **No database can certify anonymity alone.** Anonymity depends on the recipient and what else it can reach (inference, consistent with HHS's "anticipated recipient" and WP216, [20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Stand-ins are constrained.** A hash of a name fails Safe Harbor; keyed hashes need Expert Determination. See [consistent pseudonyms](consistent-pseudonyms.md).
- **Where the claim "no database anonymises" is wrong and where it holds.** Wrong: [PostgreSQL Anonymizer](../systems/postgresql-anonymizer.md), [Neon](../systems/neon.md) and Xata produce [masked copies](masked-copies.md), [Snowflake](../systems/snowflake.md) masks by tag, and [differential privacy](differential-privacy.md) layers exist; a static, generalised copy checked by an expert can meet HIPAA. Holds: nothing ships that makes data anonymous in the legal sense, automatically, for a reader who runs arbitrary queries ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Disagreements

- **Does pseudonymised data stay personal data?** The EDPB's Guidelines 01/2025 (adopted for consultation 16 January 2025) say it "remains information related to an identifiable natural person and is therefore still personal data", even when the key is held elsewhere or erased (https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf). The Court of Justice in *EDPS v SRB* (C-413/23 P, September 2025) held it is not personal "in all cases and for every person"; for a recipient with no reasonable means to re-identify it may not be, while the sender keeps its duties (paras 86, 110) (https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A62023CJ0413). Not confirmed: whether the EDPB finalised or revised its guidelines after the judgment, and the judgment's exact day ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Are AI vendors handling PHI business associates?** Research 20 infers yes. A consultancy reports the HHS civil-rights office director said so in September 2026; research 20 found no primary source ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf
- https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A62023CJ0413
- https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2014/wp216_en.pdf
- https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html
- https://help.openai.com/en/articles/20001069-hipaa-eligible-products-and-functionality
- https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html
- https://www.ecfr.gov/current/title-45/subtitle-A/subchapter-C/part-164/subpart-E/section-164.514
- https://studentprivacy.ed.gov/sites/default/files/resource_document/file/Student%20Privacy%20and%20Online%20Educational%20Services%20%28February%202014%29_0.pdf
- https://studentprivacy.ed.gov/faq/what-constitutes-de-identified-records-and-information
- https://www.ed.gov/media/document/opepd-ai-dear-colleague-letter-7222025-110427.pdf
