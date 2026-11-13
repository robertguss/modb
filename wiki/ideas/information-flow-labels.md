# Labels that follow data (gap)

Each value carries a label, such as how sensitive it is, and anything computed from it inherits the label. The database checks labels on every way out: results, errors, timing, constraint failures, logs, backups and the model call. No shipping database does this.

## What it is

*Information-flow control* (IFC): sensitivity declared in a field's type, labels that propagate through derivation, and one exit point that every result, error and log passes through ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

Research 21 extends the label from secrecy to trust: each row says who wrote it, from which input, whether it is trusted, and who may read it ([21](../../research/21-security-of-a-database-agents-use.md)).

## The problem it solves

[Masking](dynamic-masking.md) and [masked copies](masked-copies.md) protect columns someone remembered to tag. A label that follows the data also protects what is computed from it ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

Labels for writer and trust stop exfiltration through writes and agents trusting each other's output. Only the database knows, per value, who wrote it and who can read what is about to be written (inference, [21](../../research/21-security-of-a-database-agents-use.md)). See [the lethal trifecta inside a shared database](lethal-trifecta-in-a-shared-database.md).

## What it costs

- **Every operator must define how labels combine** ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- **Side channels must be designed out from the start** ([20](../../research/20-keeping-sensitive-data-from-agents.md)). [Row and column security](row-and-column-security.md) in PostgreSQL shows what happens otherwise: constraint checks bypass it.
- **Implicit flows are hard.** The FIDES authors say their confidentiality guarantee "does not prevent implicit flows", meaning leaks through which branch of a program ran (https://arxiv.org/abs/2505.23643).
- **Throughput.** [IFDB](../systems/ifdb.md) measured about 1% (https://pmg.csail.mit.edu/pubs/schultz13__ifdb_decentralized_ifc-abstract.html, https://dl.acm.org/doi/10.1145/2465351.2465357).
- **Labels must survive joins and travel with results**, and policies have to be written ([21](../../research/21-security-of-a-database-agents-use.md)).

## Systems that use it

None shipping enforces it on every exit ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Pieces:

- **Shipped, partly.** [PostgreSQL Anonymizer](../systems/postgresql-anonymizer.md) labels columns in the schema. [Snowflake](../systems/snowflake.md) tags can *propagate*: a `data_sensitivity` tag on a table flows to views and tables built from it (https://docs.snowflake.com/en/user-guide/object-tagging/propagation). That is the closest shipped thing to sensitivity following data through derivation, but it governs reads inside Snowflake, not what a permitted reader carries out ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Whether it covers every derivation path, such as unloads to files, is not confirmed.
- **Research.** [IFDB](../systems/ifdb.md) (MIT, 2013) modified PostgreSQL so rows carry labels and results are tainted by what they read, "without introducing covert channels". It came closest and never shipped ([20](../../research/20-keeping-sensitive-data-from-agents.md)).
- Research 21 also found no shipping database that enforces IFC labels for agents ([21](../../research/21-security-of-a-database-agents-use.md)).
- **In the agent, not the database.** [CaMeL](../systems/camel.md) tags values with provenance and allowed readers and checks tool calls against policy (https://arxiv.org/abs/2503.18813). FIDES propagates confidentiality labels through tool calls (https://arxiv.org/abs/2505.23643).

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- https://docs.snowflake.com/en/user-guide/object-tagging/propagation
- https://dl.acm.org/doi/10.1145/2465351.2465357
- https://pmg.csail.mit.edu/pubs/schultz13__ifdb_decentralized_ifc-abstract.html
- https://arxiv.org/abs/2503.18813
- https://arxiv.org/abs/2505.23643
