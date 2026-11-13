# Real values kept in a separate vault

A *tokenization vault* holds the real sensitive values in a separate store. Everything else, the database and the model's prompts included, holds only tokens, which authorised callers swap back.

## What it is

Real values live in the vault; every other system stores a token in their place. Skyflow is the example found; it is marketed for prompts and RAG (retrieval-augmented generation, feeding stored text into a model's prompt) (vendor claim, https://www.skyflow.com/data-privacy-vault).

## The problem it solves

Neither the database nor the model holds the value ([20](../../research/20-keeping-sensitive-data-from-agents.md)). An agent can pass a token through a workflow while a trusted tool swaps it back at the edge, for example when sending an email ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## What it costs

- **A lookup hop and key custody** ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **The law still counts tokens as personal data.** Under the GDPR, pseudonymised data "remains information related to an identifiable natural person" (EDPB, https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf). See [what the law accepts as de-identified](legal-de-identification.md).
- **Tokens still link records**, and the swap-back can be abused ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **A model that invents a value** instead of copying the token leaves nothing to swap back ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Systems that use it

Skyflow (vendor claim, https://www.skyflow.com/data-privacy-vault). The research's borrowable version: agents work on tokens and only trusted edge tools swap them back, at the cost of a key store, a second trust boundary, and lost usefulness where knowing the real entity matters ([20](../../research/20-keeping-sensitive-data-from-agents.md)). See [consistent pseudonyms](consistent-pseudonyms.md). [Confidential computing](confidential-computing.md) is the other way to keep values from a model provider: it hides them from the provider's operators, but never from the model ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://www.skyflow.com/data-privacy-vault
- https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf
