# PostgreSQL Anonymizer

PostgreSQL Anonymizer is an extension for [PostgreSQL](postgresql.md) that declares masking rules in the schema and applies them to query results, to copies, to replicas or to dumps.

## What it is for

Hiding or replacing sensitive values, either as they are read or in a copy made for others ([20](../../research/20-keeping-sensitive-data-from-agents.md)). [Neon](neon.md) runs its static masking on an "anonymized branch", with rules per branch (https://neon.com/docs/workflows/data-anonymization).

## Core idea

Rules sit in the schema as security labels, for example `SECURITY LABEL … 'MASKED WITH FUNCTION …'`. The same rules drive four modes: dynamic, static, replica and dump masking (https://postgresql-anonymizer.readthedocs.io/en/stable/). See [masking query results by role](../ideas/dynamic-masking.md) and [masked copies](../ideas/masked-copies.md).

## Strengths and what pays for each

- **One set of rules, declared with the data.** *Paid for by* rules written by hand, column by column; untagged and free-text columns pass through ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Static masking leaves no real value to probe.** *Paid for by* a stale copy ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Weaknesses

- **Noise falls to averaging.** Its docs warn that added noise falls to repeated queries plus `AVG()` (https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/).
- **Generalisation is static only.** Replacing a value with a range cannot be used dynamically (https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/).

## What an agent struggles with

Dynamic masking is not built for a reader who writes ad hoc SQL, and that is what an agent does (inference, [20](../../research/20-keeping-sensitive-data-from-agents.md)). See [how hidden data is recovered](../ideas/re-identification-by-linking.md).

## Worth borrowing

Sensitivity declared in the schema, as a first step toward [labels that follow data](../ideas/information-flow-labels.md). Cost: every operator must define how labels combine ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://postgresql-anonymizer.readthedocs.io/en/stable/
- https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/
- https://neon.com/docs/workflows/data-anonymization
