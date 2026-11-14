# The security baseline for student records, and what mainstream databases ship

Type: research
Status: claimed

## Question

What must a data system that holds US student education records satisfy, and what do mainstream databases ship against each requirement?

Cover:

- **The requirements.** FERPA's conditions for sharing with a "school official" and its "reasonable methods" rule on access (34 CFR 99.31), its limits on re-disclosure (99.33) and its record of disclosures (99.32); the Department of Education's own data security guidance; the GLBA Safeguards Rule as it applies to institutions that handle federal student aid; the NIST SP 800-171 and 800-53 controls a database has to support; and, briefly, what state student privacy laws and K-12 rules add. Say which are law, which are contract terms and which are guidance.
- **What databases ship.** For PostgreSQL, SQL Server, Oracle, MongoDB, Snowflake and SQLite: authentication (including multi-factor and single sign-on), authorisation down to the row and column, encryption in transit, at rest and per field, key management, audit logs and how tamper-resistant they are, what is exposed to the network by default, protection of backups, and secure defaults.
- **How databases are actually breached**, 2023 to 2026, by how often: stolen credentials, misconfiguration, unpatched flaws, insiders. Use breach reports with counts.

Go deepest on one checklist table: the control, who requires it, which databases ship it and how, and the usual way it fails in practice. Say for each control whether it lives inside the database or with whoever operates it.

Context, for a last column on where this project stands today (mark it inference): the database would run as a Mo service. That listens on the loopback address only, authenticates with one bearer token that grants every tool and all stored state, speaks plain HTTP behind a proxy or tunnel, keeps state in an unencrypted SQLite file, and runs on a virtual machine written in C with fuzzing and partial proofs and no operating-system confinement. `research/20-keeping-sensitive-data-from-agents.md` and `research/21-security-of-a-database-agents-use.md` cover agents and the law on de-identification; do not repeat them.

This is research, not legal advice.
