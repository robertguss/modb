# Keeping sensitive data from agents and model providers

Type: research
Status: claimed

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
