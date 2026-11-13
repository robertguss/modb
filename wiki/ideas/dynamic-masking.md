# Masking query results by role

*Dynamic masking* rewrites a value on its way out of the database, depending on who asks. The stored value is untouched. The vendors themselves say it does not stop a reader who can write their own queries, which is what an agent does.

## What it is

A column policy rewrites values in query results by role, for example showing `XXX-XX-1234` instead of a full number ([20](../../research/20-keeping-sensitive-data-from-agents.md)). It is one of four words often confused:

- **Masking** changes what a reader sees. *Dynamic* masking rewrites query results; *static* masking rewrites a copy (see [masked copies](masked-copies.md)).
- **Pseudonymising** replaces an identifier with a stand-in (see [consistent pseudonyms](consistent-pseudonyms.md)).
- **De-identifying** and **anonymising** are legal terms (see [what the law accepts as de-identified](legal-de-identification.md)). Masking has no legal standing of its own in the US ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## The problem it solves

Hiding values from staff who use fixed application screens ([20](../../research/20-keeping-sensitive-data-from-agents.md)). There is no copy to keep in sync.

## What it costs

- **The real value stays live, and filters run on it.** That is what pays for having no copy, and it is also the hole ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Ad hoc queries defeat it, in the vendors' own words.**
  - Microsoft SQL Server: users "with ad hoc query permissions can apply techniques to gain access to the actual data" (https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking?view=sql-server-ver17).
  - [Oracle](../systems/oracle.md) Data Redaction puts no limit on "the WHERE clause", which can be used "in an iterative fashion to infer the actual data". SYSDBA, the top administrator role, is exempt (https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/security-considerations-for-using-oracle-data-redaction.html).
  - [PostgreSQL Anonymizer](../systems/postgresql-anonymizer.md) warns that added noise falls to repeated queries plus `AVG()`, and that generalisation (replacing a value with a range) cannot be used dynamically (https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/).
- Each range query on a masked column halves the candidates ([20](../../research/20-keeping-sensitive-data-from-agents.md)). See [how hidden data is recovered](re-identification-by-linking.md).
- **Agents are the reader it does not stop** (inference, [20](../../research/20-keeping-sensitive-data-from-agents.md)). An agent writes ad hoc SQL, and many agents probing in parallel only speed the search.

## Systems that use it

- Microsoft SQL Server (https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking?view=sql-server-ver17).
- [Oracle](../systems/oracle.md) Data Redaction (https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/security-considerations-for-using-oracle-data-redaction.html).
- [PostgreSQL Anonymizer](../systems/postgresql-anonymizer.md), with rules declared in the schema (https://postgresql-anonymizer.readthedocs.io/en/stable/).
- [Snowflake](../systems/snowflake.md) attaches masking policies to tags; a tag on a schema protects new columns of matching type (https://docs.snowflake.com/en/user-guide/tag-based-masking-policies).

## Cannot be combined with

A reader allowed to run arbitrary queries, if the goal is that the reader never learns the value ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking?view=sql-server-ver17
- https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/security-considerations-for-using-oracle-data-redaction.html
- https://postgresql-anonymizer.readthedocs.io/en/stable/
- https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/
- https://docs.snowflake.com/en/user-guide/tag-based-masking-policies
