# Keeping sensitive data from agents and model providers

Type: research
Status: resolved

## Question

Using the map's research template where it fits, what exists today for letting an AI agent work with data while the sensitive parts never reach the agent or its model provider, and where does each mechanism fail?

Cover what databases already ship (dynamic masking in SQL Server, Oracle, Snowflake and the PostgreSQL Anonymizer extension; masking on branches in Xata and Neon; row and column security), what sits beside the database (tokenization vaults, redaction proxies and gateways in front of model providers), and the stronger techniques (pseudonyms that stay consistent across queries, k-anonymity, differential privacy, synthetic data, confidential computing).

Go deepest on:

- the difference between masking, pseudonymising, de-identifying and anonymising, and which the law recognises;
- what HIPAA and FERPA require before records may be sent to a model provider, and what counts as de-identified under each;
- how hidden data is recovered anyway: filtering on a masked column, joining harmless fields, small groups in totals, names inside free text;
- what an agent can still usefully do with stand-ins in place of real values, and what breaks;
- whether any system declares sensitivity in the data's types and enforces it on everything that leaves the database.

Say plainly where Robert's starting belief, that no database anonymises sensitive data, is wrong and where it holds.

## Answer

Findings: [research/20-keeping-sensitive-data-from-agents.md](../research/20-keeping-sensitive-data-from-agents.md).

- Masking, pseudonymising, de-identifying and anonymising differ. The EU treats pseudonyms as personal data (EDPB 2025), softened for recipients who cannot re-identify (CJEU *SRB*, September 2025). HIPAA and FERPA recognise only de-identification, and HIPAA bars stand-in codes derived from the person except under Expert Determination.
- Sending PHI to a model provider needs a BAA, de-identification or a limited data set. FERPA needs the vendor under the school's direct control, or a "reasonable person" de-identification judgment.
- Dynamic masking (SQL Server, Oracle, Snowflake, PostgreSQL Anonymizer) is documented by its vendors as not stopping ad hoc queries, which is what agents write. Static masked copies (Neon, Xata) are stronger but miss free text and untagged columns.
- LLM agents re-identify masked text in most measured cases (85.3% after entity masking in AgentDoxx, 2026). Only differential privacy holds up across many combined queries, at the cost of answering totals only.
- No shipping database types sensitivity and enforces it on every exit. Snowflake tag propagation and the IFDB research system come closest. The starting belief holds for automatic anonymity under arbitrary queries and is wrong that databases ship nothing.
