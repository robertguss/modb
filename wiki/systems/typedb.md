# TypeDB

TypeDB is a database with a typed entity-relation-attribute model. Version 3.0 (2024-12-20), rewritten in Rust, replaced its rule-based inference with functions the caller asks for by name.

## What it is for

Typed relations, with constraints kept in the schema ([04](../../research/04-models-that-lost-or-stayed-niche.md)). The research file groups it with Datomic and Soufflé as a logic-based (Datalog-family) system. *Datalog* is a query language made of rules, which may call themselves recursively.

## Core idea

- A typed entity-relation-attribute model ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- Version 3.0 (2024-12-20), rewritten in Rust, replaced rule-based inference with functions, which are "easier to reason about" (https://github.com/typedb/typedb/releases/tag/3.0.0).
- Under 2.x an "inference switch" changed what a query returned; 3.0 makes the caller ask for inferred results explicitly (https://typedb.com/fundamentals/functions).

## Strengths and what pays for each

- **Typed relations, constraints in the schema.** Paid for by a rewrite and dropping rule inference ([04](../../research/04-models-that-lost-or-stayed-niche.md)). See [Rules the database enforces across transactions](../ideas/invariants-the-database-enforces.md).
- **Explicit inference:** derived facts asked for by name. Paid for by longer queries ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Weaknesses

- Small ecosystem ([04](../../research/04-models-that-lost-or-stayed-niche.md)). Datalog-style systems in general lack training data and tooling ([04](../../research/04-models-that-lost-or-stayed-niche.md)).
- Adoption and the company's state after 3.0 were not checked ([04](../../research/04-models-that-lost-or-stayed-niche.md), not confirmed).

## Overlapping work

Transactions are ACID "up to snapshot isolation", where each transaction reads one consistent snapshot ([04](../../research/04-models-that-lost-or-stayed-niche.md)). See [Multi-version snapshots](../ideas/multi-version-snapshots.md).

## What an agent struggles with

Small composable rules suit agents; hidden inference does not, as TypeDB's retreat from the 2.x inference switch shows ([04](../../research/04-models-that-lost-or-stayed-niche.md), inference).

## Worth borrowing

**Explicit inference (TypeDB 3.0):** derived facts asked for by name. Cost: longer queries ([04](../../research/04-models-that-lost-or-stayed-niche.md)).

## Sources

- [04-models-that-lost-or-stayed-niche.md](../../research/04-models-that-lost-or-stayed-niche.md)
- https://github.com/typedb/typedb/releases/tag/3.0.0
- https://typedb.com/fundamentals/functions
