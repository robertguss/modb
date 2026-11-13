# Consistent and keyed pseudonyms

*Pseudonymising* replaces an identifier with a stand-in, such as a token or code. A *consistent* pseudonym gives the same person the same stand-in every time, so joins and counts still work. A *keyed* pseudonym is computed with a secret key.

## What it is

Same person, same stand-in ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Whoever holds the key or the lookup table can reverse it ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## The problem it solves

It hides direct identifiers while keeping the data useful to an agent ([20](../../research/20-keeping-sensitive-data-from-agents.md)):

- **Works:** counting, grouping and joining on consistent tokens; passing a token through a workflow while a trusted tool swaps it back at the edge; exploring schemas; debugging on a [masked branch](masked-copies.md).
- **Usefulness depends on realism.** Consistent, realistic pseudonyms cut utility errors about fivefold compared with blunt placeholders (https://arxiv.org/abs/2510.27016).

## What it costs

- **Linkability by design.** What makes joins work also makes linking possible ([20](../../research/20-keeping-sensitive-data-from-agents.md)). See [how hidden data is recovered](re-identification-by-linking.md).
- **Tasks that need the real entity break.** Retrieval tasks fell by up to 47 points (0.80 to 0.32) on pseudonymised input, and stronger models lost most (https://arxiv.org/abs/2609.11335).
- **Ranges, sorts and format checks** on randomised values break ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **A model can restate a sensitive fact it inferred**, with no token to catch ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Legal limits.**
  - In the EU, pseudonymised data stays personal data (EDPB, https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf), though perhaps not for a recipient with no reasonable means to re-identify (*EDPS v SRB*, https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A62023CJ0413).
  - Under HIPAA, a kept re-identification code must not be "derived from or related to information about the individual", so a hash of a name or patient number fails Safe Harbor (https://www.ecfr.gov/current/title-45/subtitle-A/subchapter-C/part-164/subpart-E/section-164.514). HHS allows keyed hashes only under Expert Determination, "provided the keys … are not disclosed, including to the recipients" (https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html).
  - See [what the law accepts as de-identified](legal-de-identification.md).

## Systems that use it

[Tokenization vaults](tokenization-vaults.md) and [redaction gateways](redaction-gateways.md) issue stand-ins. Research 20 suggests keyed pseudonyms whose key never leaves the database; the cost is that HIPAA treats them as Expert Determination, not Safe Harbor ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Disagreements

- **Is a pseudonymised extract personal data?** The EDPB's 2025 guidelines say it "remains information related to an identifiable natural person", even when the key is held elsewhere or erased. The Court of Justice in *EDPS v SRB* (C-413/23 P, September 2025) said it is not personal "in all cases and for every person"; for a recipient with no reasonable means to re-identify, it may not be. Research 20 could not confirm whether the EDPB revised its guidelines after the judgment ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://arxiv.org/abs/2510.27016
- https://arxiv.org/abs/2609.11335
- https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf
- https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A62023CJ0413
- https://www.ecfr.gov/current/title-45/subtitle-A/subchapter-C/part-164/subpart-E/section-164.514
- https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html
