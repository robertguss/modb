# k-anonymity

Values are made coarser, or records dropped, until each record matches at least *k−1* others on every field an attacker could know.

## What it is

Generalise (for example, an age becomes a range) or suppress until each record is one of at least *k* look-alikes on the fields an attacker could know ([20](../../research/20-keeping-sensitive-data-from-agents.md)). HHS cites it as one model an expert may use for HIPAA Expert Determination (https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html). FERPA practice is similar: US states set minimum group sizes of 5 to 30, most often 10 (https://studentprivacy.ed.gov/sites/default/files/resource_document/file/FAQs_disclosure_avoidance_0.pdf).

## The problem it solves

*Singling out*: picking one person from the data (https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2014/wp216_en.pdf).

## What it costs

- **Coarser data** ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **It does not stop inference** when every member of a group shares one sensitive value (WP216, https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2014/wp216_en.pdf).
- **Repeated releases** break it ([20](../../research/20-keeping-sensitive-data-from-agents.md)). The US Department of Education warns hidden cells "can often be easily calculated by subtracting" (https://studentprivacy.ed.gov/sites/default/files/resource_document/file/FAQs_disclosure_avoidance_0.pdf).
- [PostgreSQL Anonymizer](../systems/postgresql-anonymizer.md) cannot apply generalisation dynamically (https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html
- https://studentprivacy.ed.gov/sites/default/files/resource_document/file/FAQs_disclosure_avoidance_0.pdf
- https://ec.europa.eu/justice/article-29/documentation/opinion-recommendation/files/2014/wp216_en.pdf
- https://postgresql-anonymizer.readthedocs.io/en/stable/masking_functions/
