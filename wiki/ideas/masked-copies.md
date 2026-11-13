# Masked copies and anonymised branches

*Static masking* rewrites a copy of the data, so the copy holds no real values. Branching databases now make such a copy as a branch, for developers and agents to work on.

## What it is

A copy, or a branch, in which sensitive columns have been rewritten by rules before anyone reads it ([20](../../research/20-keeping-sensitive-data-from-agents.md)). [Neon](../systems/neon.md) makes an "anonymized branch" and runs [PostgreSQL Anonymizer](../systems/postgresql-anonymizer.md) static masking on it, with rules per branch (https://neon.com/docs/workflows/data-anonymization). Xata offers the same idea ([09](../../research/09-agents-and-databases-today.md), [20](../../research/20-keeping-sensitive-data-from-agents.md)).

## The problem it solves

[Dynamic masking](dynamic-masking.md) leaves the real value live, so filters can probe it. A masked copy has no real values, so filters reveal nothing ([20](../../research/20-keeping-sensitive-data-from-agents.md)). An agent can debug or explore on it ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## What it costs

- **A stale copy** ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Protection only as good as hand-written rules.** Untagged and free-text columns pass through ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Joins can still link people** on the fields left in clear ([20](../../research/20-keeping-sensitive-data-from-agents.md)). See [how hidden data is recovered](re-identification-by-linking.md).
- A static, generalised copy checked by an expert can meet HIPAA de-identification ([20](../../research/20-keeping-sensitive-data-from-agents.md)). See [what the law accepts as de-identified](legal-de-identification.md).

## Systems that use it

- [Neon](../systems/neon.md) (https://neon.com/docs/workflows/data-anonymization).
- Xata ([09](../../research/09-agents-and-databases-today.md)).
- [PostgreSQL Anonymizer](../systems/postgresql-anonymizer.md): static, replica and dump masking (https://postgresql-anonymizer.readthedocs.io/en/stable/).

Not confirmed: whether Neon's or Xata's masking reaches JSON and free text beyond user-written rules ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://neon.com/docs/workflows/data-anonymization
- https://postgresql-anonymizer.readthedocs.io/en/stable/
