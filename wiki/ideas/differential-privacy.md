# Differential privacy

*Differential privacy* (DP) adds noise to answers, sized so that one person's presence barely moves any answer. It is the only technique in the research that holds up when many queries are combined.

## What it is

Each query spends part of a fixed *privacy budget* (called epsilon). OpenDP SmartNoise wraps a database connection and answers aggregate SQL this way (https://docs.smartnoise.org/sql/).

## The problem it solves

It protects each person's contribution ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Small groups in totals, and hidden cells recovered by subtraction, defeat other methods; only DP holds up across many combined queries ([20](../../research/20-keeping-sensitive-data-from-agents.md)). See [how hidden data is recovered](re-identification-by-linking.md).

## What it costs

- **Totals only, never rows** ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **The budget runs out.** With many agents, the budget is one shared resource the first greedy agent can drain (inference, [20](../../research/20-keeping-sensitive-data-from-agents.md)). Research 20 suggests a budget held per dataset, not per agent; the cost is noisy answers and a policy for who spends ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Buggy implementations** break the guarantee. Two common DP generators of [synthetic data](synthetic-data.md) broke their own guarantees (https://www.usenix.org/conference/usenixsecurity22/presentation/stadler).
- Added noise that is not DP falls to repeated queries plus `AVG()` ([PostgreSQL Anonymizer](../systems/postgresql-anonymizer.md) docs, https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/).

## Systems that use it

OpenDP SmartNoise, a query layer beside the database (https://docs.smartnoise.org/sql/).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://docs.smartnoise.org/sql/
- https://www.usenix.org/conference/usenixsecurity22/presentation/stadler
- https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/
