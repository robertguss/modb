# Synthetic data

Generated rows with the same statistics as the real ones, shipped instead of the real rows.

## What it is

A generator learns the statistics of the real data and produces new rows ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## The problem it solves

Real rows are never shipped ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## What it costs

- **Unpredictable usefulness.** A USENIX Security 2022 study found synthetic data "either does not prevent inference attacks or does not retain data utility" (https://www.usenix.org/conference/usenixsecurity22/presentation/stadler).
- **Outliers stay linkable** (https://www.usenix.org/conference/usenixsecurity22/presentation/stadler), and *membership inference* (telling whether a person was in the source data) is listed as a way it is defeated ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Two common [differentially private](differential-privacy.md) generators broke their own guarantees** in the same study (https://www.usenix.org/conference/usenixsecurity22/presentation/stadler).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://www.usenix.org/conference/usenixsecurity22/presentation/stadler
