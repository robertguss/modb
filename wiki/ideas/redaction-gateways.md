# Redacting prompts before the model provider

A *redaction gateway* sits between an application and the model provider. It finds names, numbers and similar items in outgoing text, swaps them for placeholders, and can swap them back in the reply.

## What it is

LiteLLM runs Microsoft Presidio, a detector for names, numbers and similar, replaces hits with placeholders, and with `output_parse_pii` puts them back in the reply (https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2).

## The problem it solves

It works on free text with no schema ([20](../../research/20-keeping-sensitive-data-from-agents.md)), which [masked copies](masked-copies.md) and [dynamic masking](dynamic-masking.md) miss.

## What it costs

- **Statistical detection, so misses are silent** ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Indirect identifiers get through.** After entity masking, agents still re-identified most people in a 2026 study (https://arxiv.org/abs/2610.05586). See [how hidden data is recovered](re-identification-by-linking.md).
- **Invented values** have no placeholder to swap back ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Systems that use it

LiteLLM with Presidio (https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2). It lives beside the database, not in it.

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2
- https://arxiv.org/abs/2610.05586
