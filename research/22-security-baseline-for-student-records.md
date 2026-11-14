Research run on 2026-11-14 by a subagent using Exa, for the ticket [The security baseline for student records](../issues/22-security-baseline-for-student-records.md). It builds on [20](20-keeping-sensitive-data-from-agents.md) (FERPA's "school official" route, de-identification) and [21](21-security-of-a-database-agents-use.md) (attacks on engines, defences for agents) and repeats neither. Vendor claims are marked. Reasoning with no source is marked "inference". **This is research, not legal advice.**

# The security baseline for student records (researched 2026-11-14)

Terms used below:

- **Education record**: a record directly about a student, kept by a school or someone acting for it. **PII**: personally identifiable information from it.
- **MFA** (multi-factor authentication): a login needing two kinds of proof, such as a password and a phone. **SSO** (single sign-on): the database trusts an outside identity provider to log people in.
- **Row-level security**: the database filters every query so each user sees only the rows a policy allows. **Masking** shows `XXX-XX-1234` instead of a column's value.
- **TDE** (transparent data encryption): the database encrypts its files on disk, invisibly to queries. **Per-field encryption** encrypts single values, ideally with keys the database never sees. **HSM**: hardware that holds keys apart from the data.
- **Tamper-evident log**: a log whose alteration can be detected afterwards. It does not prevent alteration.

## 1. What binds, and how

**Law** binds the school. **Contract terms** carry duties to the vendor. **Guidance** says how a regulator reads the law but does not bind by itself.

### FERPA (law: 34 CFR Part 99)

FERPA binds the school; a vendor is bound through the school's contract (inference from 99.31 and 99.33).

**School officials.** A school may disclose PII without consent to "other school officials, including teachers, … whom the agency or institution has determined to have legitimate educational interests". An outside party counts as a school official only if it "(1) Performs an institutional service or function for which the agency or institution would otherwise use employees; (2) Is under the direct control of the agency or institution with respect to the use and maintenance of education records; and (3) Is subject to the requirements of § 99.33(a) governing the use and redisclosure of personally identifiable information from education records" https://www.ecfr.gov/current/title-34/subtitle-A/part-99/subpart-D/section-99.31.

**The "reasonable methods" rule**, 99.31(a)(1)(ii), in full:

> "An educational agency or institution must use reasonable methods to ensure that school officials obtain access to only those education records in which they have legitimate educational interests. An educational agency or institution that does not use physical or technological access controls must ensure that its administrative policy for controlling access to education records is effective and that it remains in compliance with the legitimate educational interest requirement in paragraph (a)(1)(i)(A) of this section."

It names no technique. For a database it means restricting each official to the records their job needs: row and column authorisation (inference).

**Re-disclosure (99.33).** The school may disclose PII "only on the condition that the party to whom the information is disclosed will not disclose the information to any other party without the prior consent of the parent or eligible student". The recipient's staff "may use the information, but only for the purposes for which the disclosure was made" https://www.ecfr.gov/current/title-34/subtitle-A/part-99/subpart-D/section-99.33.

**The record of disclosures (99.32):**

> "(a)(1) An educational agency or institution must maintain a record of each request for access to and each disclosure of personally identifiable information from the education records of each student, as well as the names of State and local educational authorities and Federal officials and agencies listed in § 99.31(a)(3) that may make further disclosures of personally identifiable information from the student's education records without consent under § 99.33(b).
> (2) The agency or institution shall maintain the record with the education records of the student as long as the records are maintained.
> (3) For each request or disclosure the record must include: (i) The parties who have requested or received personally identifiable information from the education records; and (ii) The legitimate interests the parties had in requesting or obtaining the information."

The exceptions, 99.32(d): "Paragraph (a) of this section does not apply if the request was from, or the disclosure was to: (1) The parent or eligible student; (2) A school official under § 99.31(a)(1); (3) A party with written consent from the parent or eligible student; (4) A party seeking directory information; or (5) A party seeking or receiving records in accordance with § 99.31(a)(9)(ii)(A) through (C)." Parents and eligible students may inspect the record (99.32(c)) https://www.ecfr.gov/current/title-34/subtitle-A/part-99/subpart-D/section-99.32.

Consequences (inference): reads by school officials, including an agent acting for a teacher, need no disclosure record; 99.31(a)(1)(ii) governs them. Every other disclosure needs an entry naming the recipient and its purpose, kept as long as the student's record. An access log that omits purpose, or is rotated away, does not meet it.

**Pending change.** The regulatory agenda lists a FERPA rulemaking (RIN 1875-AA15) on "non-consensual disclosure … to third parties (including commercial vendors)", proposed rule dated "09/00/2026" https://www.reginfo.gov/public/do/eAgendaViewRule?RIN=1875-AA15&pubId=202510.

### Department of Education guidance (guidance)

The Privacy Technical Assistance Center's Data Security Checklist says "Role-based access is essential for protecting PII" and suggests two-factor authentication "for remote users or privileged 'super users'" https://studentprivacy.ed.gov/sites/default/files/resource_document/file/Data%20Security%20Checklist_0.pdf. It is advice, and weaker than GLBA.

### GLBA Safeguards Rule (law, applied through contract)

The FTC treats colleges as financial institutions. Every college in the federal aid programs "has agreed in its Program Participation Agreement (PPA) to comply with the GLBA Safeguards Rule", and the Department enforces it through audits and "administrative capability" findings https://fsapartners.ed.gov/knowledge-center/library/electronic-announcements/2023-02-09/updates-gramm-leach-bliley-act-cybersecurity-requirements. It covers aid information, not every grade, and not K-12 (inference). It is the most concrete source here (16 CFR 314.4) https://www.ecfr.gov/current/title-16/chapter-I/subchapter-C/part-314/section-314.4:

- (c)(1): "Authenticate and permit access only to authorized users"; "Limit authorized users' access only to customer information that they need to perform their duties and functions".
- (c)(3): "Protect by encryption all customer information held or transmitted by you both in transit over external networks and at rest", unless the named Qualified Individual approves "effective alternative compensating controls".
- (c)(5): "Implement multi-factor authentication for any individual accessing any information system", unless the Qualified Individual approves an equivalent in writing.
- (c)(6): disposal within two years of last use, with exceptions. (c)(8): "monitor and log the activity of authorized users and detect unauthorized access or use of, or tampering with, customer information".
- (d)(2): continuous monitoring, or yearly penetration tests. (f): safeguards required of service providers "by contract". (j): FTC notice within 30 days for 500 or more consumers.

### NIST SP 800-171 and 800-53 (guidance here; contract elsewhere)

The Department "strongly encourages institutions to review and understand the standards defined in the NIST SP 800-171" https://fsapartners.ed.gov/knowledge-center/library/dear-colleague-letters/2016-07-01/gen-16-12-subject-protecting-student-information, and has required nothing more since https://fsapartners.ed.gov/knowledge-center/topics/fsa-cybersecurity-announcements-and-guidance. 800-171 binds only through a contract; 800-53 governs federal systems.

Rev. 3 requirements a database must support https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-171r3.pdf: 03.05.01 "Uniquely identify and authenticate system users"; 03.05.03 MFA "for access to privileged and non-privileged accounts"; 03.01.05 least privilege; 03.03.02 audit records with what, when, where, source, outcome and identity; 03.03.08 "Protect audit information and audit logging tools from unauthorized access, modification, and deletion"; 03.13.08 encryption "during transmission and while in storage"; 03.13.10 key management; 03.08.09 encrypted backups; 03.04.06 no unneeded ports or services; 03.14.01 timely patching. The 800-53 parents are AC-3, AC-6, AU-9, IA-2, SC-8 and SC-28 https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final.

### State and K-12 rules (law)

- **New York, Part 121**: contractors must "adopt technologies, safeguards and practices that align with the NIST Cybersecurity Framework" https://www.counsel.nysed.gov/sites/counsel/files/rulesandregs/part-121-terms.pdf; the State Education Department says encryption is required "at rest and in transit" https://www.nysed.gov/data-privacy-security/frequently-asked-questions-dpos.
- **California, SOPIPA**: K-12 operators must keep "reasonable security procedures and practices" and impose them on their own providers https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=BPC&sectionNum=22584.
- **COPPA**: operators collecting from under-13s must keep "a written information security program" (16 CFR 312.8) https://www.ecfr.gov/current/title-16/chapter-I/subchapter-C/part-312/section-312.8, with compliance due 22 April 2026 https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule.

The pattern: FERPA governs **who may see what, and the record of it**. MFA, encryption and logging come from GLBA, state law and contracts.

## 2. What mainstream databases ship

Per-control detail is in the checklist. Sources:

- **PostgreSQL**: row-level security https://www.postgresql.org/docs/current/ddl-rowsecurity.html; listens on localhost by default https://www.postgresql.org/docs/current/runtime-config-connection.html; version 18 adds `oauth` login, so an identity provider's MFA can front it https://www.postgresql.org/docs/current/auth-oauth.html. No built-in encryption at rest: the docs point to disk encryption and `pgcrypto` https://www.postgresql.org/docs/current/encryption-options.html. Detailed audit needs the pgAudit extension https://github.com/pgaudit/pgaudit.
- **SQL Server** ships the most in one box: Entra ID logins since 2022 https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/azure-ad-authentication-sql-server-overview; row-level security https://learn.microsoft.com/en-us/sql/relational-databases/security/row-level-security; masking https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking; backup encryption https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/backup-encryption; TDE https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/transparent-data-encryption; Always Encrypted, with keys "outside of the database system" (vendor claim) https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/always-encrypted-database-engine; Audit https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine; ledger tables, with digests kept "outside the database in tamper-proof storage" (vendor claim) https://learn.microsoft.com/en-us/sql/relational-databases/security/ledger/ledger-overview.
- **Oracle**: Virtual Private Database row and column policies, and Entra ID or Active Directory login https://www.oracle.com/security/database-security/features/; unified auditing "enabled by default for Oracle Database 12c and above" (vendor claim) https://www.oracle.com/security/database-security/unified-auditing/faq/; native MFA "Starting with Oracle Database 23.9" https://docs.oracle.com/en/database/oracle/oracle-database/23/nfcoa/authentication.html. TDE and backup encryption are an "Extra cost option"; network encryption is free https://docs.oracle.com/en/database/oracle/oracle-database/21/dblic/Licensing-Information.html.
- **MongoDB**: binds to localhost by default https://www.mongodb.com/docs/manual/core/security-mongodb-configuration/, but access control must be switched on https://www.mongodb.com/docs/manual/administration/security-checklist/. Auditing https://www.mongodb.com/docs/manual/tutorial/configure-auditing/ and encryption at rest https://www.mongodb.com/docs/manual/core/security-encryption-at-rest/ are Enterprise or Atlas only, as is automatic field encryption https://www.mongodb.com/docs/v7.0/core/csfle/reference/compatibility/. Roles stop at the collection, not the document https://www.mongodb.com/docs/manual/core/authorization/.
- **Snowflake**: all data encrypted in every edition; row access policies, masking and `ACCESS_HISTORY` need Enterprise; customer-held keys need Business Critical https://docs.snowflake.com/en/user-guide/intro-editions. After the 2024 breaches it is ending password-only login, for all human users in "Aug. 2026 - Oct. 2026" (vendor schedule) https://docs.snowflake.com/en/user-guide/security-mfa-rollout.
- **SQLite**: no listener, no users, no audit. Encryption is the paid extension ("US $2000.00") https://sqlite.org/purchase/see. Its one control, the authoriser, runs only "as SQL statements are being compiled" https://sqlite.org/c3ref/set_authorizer.html.

## 3. How data is actually breached

Verizon's 2026 Data Breach Investigations Report counts more than 22,000 confirmed breaches in 145 countries, from Verizon's and partners' cases, "Oct 2024 through Nov 2025". It counts all breaches, not database breaches alone https://www.verizon.com/business/resources/Te26/reports/2026-dbir-data-breach-investigations-report.pdf.

- **Unpatched flaws**: 31% of breaches whose first step is known (n=20,023, error and misuse cases excluded), up from 20%. "Only 26%" of known-exploited flaws were fully fixed.
- **Stolen credentials**: "fallen steeply from 22% in the 2025 DBIR to 13%"; 16% like-for-like, since pretexting (social engineering with an invented story) is now counted separately.
- **Insiders**: "Internal actors appeared in 12% of breaches" (n=22,345), often "mistakes, Misconfigurations, or creative shortcuts" rather than malice.
- **Errors**: 1,750 breaches, about 8% (inference from counts). Misconfiguration, deploying "a data store on the internet without applying appropriate access controls", is a top-three error.

**Education** (1,252 breaches): exploitation 34%, phishing 22%, credential abuse 8% of first steps; stolen credentials appear "in 65% of breaches that involve Hacking actions"; insiders 22%.

**The largest student-records breach.** In December 2024 an attacker used one support account's stolen credentials to enter PowerSchool's support portal, then remote-support sessions into districts' student information systems, and copied their Students and Teachers tables https://www1.powerschool.com/wp-content/uploads/2025/03/PowerSchool-CrowdStrike-Final-Report.pdf. Alberta's privacy commissioner found "there was no multi-factor authentication used for this access", and privileged account management "falls below what constitutes 'reasonable security arrangements'" https://oipc.ab.ca/wp-content/uploads/2025/11/FINAL-Investigation-Report-Regarding-PowerSchool-Breach-FOIP2025-IR-02.pdf. One vendor credential without MFA reached every customer through a maintenance path; the database's own controls never came into play (inference).

## 4. The checklist

"Inside" means the database can enforce it. "Operator" means whoever runs it must. The last column is inference from the ticket: loopback only, one bearer token granting all tools and state, plain HTTP behind a proxy, an unencrypted SQLite file, a C virtual machine with fuzzing and partial proofs, no operating-system confinement.

| Control | Who requires it | Which databases ship it, and how | Usual failure in practice | Inside or operator | Where this project stands (inference) |
|---|---|---|---|---|---|
| **Unique identity per person or agent** | NIST 800-171 03.05.01; GLBA 314.4(c)(1)(i); FERPA 99.32(a)(3) needs to name "the parties" | PG, SQL Server, Oracle, MongoDB, Snowflake: named roles/users. SQLite: none | Shared service accounts. One support login reached all PowerSchool customers | Inside (identities); operator (issuing them) | **Missing.** One token, so every caller is the same caller |
| **MFA for people** | GLBA 314.4(c)(5) (law, colleges); 800-171 03.05.03; ED checklist (advice) | Oracle 23.9+ native (push or certificate). Snowflake: enforced for all humans by Oct 2026 (vendor). PG 18: through an OAuth identity provider. SQL Server: through Microsoft Entra ID. MongoDB, SQLite: none in the engine | Left off for "service" or support accounts; Snowflake 2024 and PowerSchool 2024 both lacked it | Mostly operator (identity provider) | **Missing.** A bearer token is one factor. It is not replay-resistant if sent over plain HTTP (800-171 03.05.04) |
| **SSO / federated login** | None directly; supports MFA and account removal | PG 18 OAuth; SQL Server Entra ID; Oracle Entra ID, Active Directory, Kerberos; MongoDB Enterprise/Atlas LDAP, Kerberos | Departed staff keep local database passwords outside SSO | Operator, with engine support | **Missing** |
| **Least privilege by row ("legitimate educational interest")** | FERPA 99.31(a)(1)(ii) (law); GLBA 314.4(c)(1)(ii); 800-171 03.01.05 | PG `CREATE POLICY`; SQL Server row-level security; Oracle VPD; Snowflake row access policies (Enterprise+). MongoDB: per collection only. SQLite: authoriser per table and column, at compile time | Application connects as one superuser and filters in code; one missed `WHERE` exposes everything | Inside | **Missing.** The token grants all state. A Mo program could filter per caller, but there is no caller identity to filter on |
| **Column restriction and masking** | Same as above; ED checklist "role-based access" | PG column `GRANT`; SQL Server column permissions and dynamic data masking; Oracle VPD column policies and Data Redaction (extra cost); Snowflake masking policies (Enterprise+); SQLite authoriser can blank a column | Masking bypassed by ad hoc queries (see [20](20-keeping-sensitive-data-from-agents.md)) | Inside | **Missing** |
| **Purpose limit on re-disclosure** | FERPA 99.33(a) (law, passed to vendor by contract); NY Part 121; SOPIPA | No engine enforces purpose. Contracts and policy do | Vendor reuses data for analytics or model training | Operator (contract) | Not a database property. A labelled-rows design ([21](21-security-of-a-database-agents-use.md)) could carry purpose |
| **Record of disclosures** (who, why, kept with the record) | FERPA 99.32 (law), except to parents, school officials, consented parties, directory requests and certain subpoenas | No engine has this as a feature. Audit logs record *who* and *what*, not the *legitimate interest*, and are rotated | Kept in a spreadsheet, or not at all; cannot answer a parent's 99.32(c) request | Operator today; could be inside | **Missing.** Inference: a write-ahead record with a required "purpose" field fits Mo's typed state well |
| **Activity log of authorised users** | GLBA 314.4(c)(8) (law); 800-171 03.03.01-02 | SQL Server Audit; Oracle unified auditing; Snowflake `ACCESS_HISTORY` (Enterprise+); MongoDB auditing (Enterprise/Atlas only); PG `log_statement` or pgAudit extension; SQLite none | Logging off by default or on a different edition; logs never read | Inside (generating); operator (reviewing) | **Missing.** Without identities a log could only say "the token did it" |
| **Tamper-resistant audit** | 800-171 03.03.08 | SQL Server ledger with digests stored off the database (vendor claim). The others keep the log where a database administrator can reach it, unless the operator ships it elsewhere | Attacker or insider with admin rights deletes their trail; Drift case in [21](21-security-of-a-database-agents-use.md) | Inside (hash chain); operator (copy off-host) | **Missing** |
| **Encryption in transit** | GLBA 314.4(c)(3) "over external networks"; 800-171 03.13.08; NY Part 121 | All network engines ship TLS. PG `ssl` must be enabled; Oracle network encryption free in all editions; Snowflake always TLS. SQLite: no network | TLS optional and clients connect without it; certificates not verified | Inside (TLS); operator (certificates) | **Operator-dependent.** Loopback plain HTTP is safe on one host only if the proxy or tunnel encrypts every external hop |
| **Encryption at rest** | GLBA 314.4(c)(3) (law, colleges); 800-171 03.13.08; NY Part 121 | SQL Server TDE; Oracle TDE (extra cost); MongoDB (Enterprise/Atlas); Snowflake always on. PG: none built in, use disk encryption. SQLite: paid SEE | Stops disk theft only; a stolen login still reads everything ([21](21-security-of-a-database-agents-use.md)) | Inside or operator (disk) | **Missing in the engine.** Disk encryption on the virtual machine could meet the letter (inference) |
| **Per-field encryption** (keys away from the server) | None requires it by name; the PostgreSQL docs name "unscrupulous administrators" as a threat it answers | SQL Server Always Encrypted; MongoDB client-side and Queryable Encryption (automatic only in Enterprise/Atlas); PG `pgcrypto` (key passes through the server); Oracle TDE column (server-held key) | Breaks search and sorting; keys end up stored beside the data | Client and inside | **Missing** |
| **Key management** | 800-171 03.13.10; GLBA via encryption duty | SQL Server and Oracle work with external key stores and HSMs; MongoDB KMIP; Snowflake Tri-Secret Secure (Business Critical) | Key in a config file next to the database or the backup | Operator | **Not applicable yet** (nothing encrypted). The token sits in an environment variable |
| **Minimal network exposure by default** | 800-171 03.04.06 and 03.13.01 | PG and MongoDB bind to localhost by default; Snowflake network policies (all editions); SQLite has no listener | Operators bind to all addresses to "make it work" and skip authentication; DBIR's misconfiguration class | Inside (default); operator (firewall) | **Good.** Loopback only, no address flag. Exposure moves to the proxy, which must also authenticate |
| **Protected backups** | 800-171 03.08.09; GLBA encryption duty | Oracle RMAN encryption (extra cost); SQL Server backup encryption; Snowflake Time Travel and Fail-safe (managed); PG and SQLite: dump files are plain unless encrypted by the operator | Backups unencrypted, or deletable with the same credential as the data | Operator | **Missing.** A copy of the SQLite file is a full, plain copy of all state |
| **Flaw remediation and engine hardening** | GLBA 314.4(d)(2) testing; 800-171 03.14.01 | Vendor security releases for all six | Exploitation is now the top breach vector (31%), and only 26% of known-exploited flaws were fully fixed | Vendor (fix); operator (apply) | **Partly.** Fuzzing and partial proofs reduce engine flaws. A C virtual machine with no OS confinement means one memory bug reaches the whole host |
| **Retention and secure disposal** | GLBA 314.4(c)(6) (two years after last use); 800-171 03.08.03; SOPIPA deletion on request | Deletion is SQL or API everywhere; history features (Time Travel, ledger) keep old copies on purpose | Copies in backups, logs and history outlive deletion | Both | **Unknown.** Depends on whether Mo's saved state keeps old versions |
| **Breach detection and notice** | GLBA 314.4(j): FTC notice within 30 days for 500+ consumers; NY Part 121; state breach laws | Engines supply logs only | Breach found months later by a third party | Operator | **Missing.** No log to detect from |

## 5. What the table shows

- **Engines can enforce identity, row and column limits, audit and encryption.** MFA, keys, backups, patching, contracts and notice are the operator's. Much of it is in paid editions (Oracle, MongoDB, Snowflake).
- **FERPA's two database-shaped duties are poorly served.** Row limits need someone to write the "legitimate educational interest" policy, and no engine keeps a 99.32 record with its "legitimate interests" field for the life of the record (inference from the vendor pages above).
- **The period's breaches were not engine failures** but credentials without MFA and unpatched software (inference from section 3).
- **This project fails the identity row, and the rest depends on it.** One all-powerful token means no per-user limits, no meaningful audit, no disclosure record. Identity comes before encryption (inference).

## Ideas worth borrowing

- **Disclosure as a write.** A read by anyone outside the school's officials writes a 99.32 entry (who, which student, why) in the same transaction, kept with the student's record. Cost: storage; reads without a purpose are refused.
- **Purpose-bound grants.** Join 99.33's purpose limit to the narrowed grants of [21](21-security-of-a-database-agents-use.md): a grant names its purpose and the disclosure record is written from it. Cost: a maintained vocabulary of purposes.
- **SQL Server's ledger pattern.** Hash-chain the log and push digests off the host, so deletion shows. Cost: a second store.
- **Localhost by default**, already Mo's choice. Refuse to bind wider without TLS and per-caller identity. Cost: harder first setup.
- **Snowflake's lesson**: optional MFA stays off. Require it from day one.

## What I could not confirm

- Whether the FERPA proposed rule listed for September 2026 has been published.
- Whether Snowflake's final MFA phase finished on schedule.
- SQL Server's default network protocols per edition, Oracle's default listener exposure, and whether Oracle's audit trail is tamper-evident on its own; I found no vendor page to quote.
- Any engine feature for FERPA's record of disclosures. I found none; that is not proof of absence.
- A breach count specific to databases. Verizon counts all breaches.
- The number of students in the PowerSchool breach, from a primary source.
- The text of 99.33(e), the five-year bar on improper re-disclosers; my fetch was cut short.
- Whether virtual-machine disk encryption meets GLBA's "at rest" duty for a given school; that is the Qualified Individual's judgment.
