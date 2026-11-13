# Code inside the database, and databases inside a language

Type: research
Status: resolved

## Question

Using the map's research template, what do systems that put code and data together do well and badly, and what pays for each strength?

Cover stored procedures and triggers; object prevalence (Prevayler) and image persistence (Smalltalk, GemStone); Erlang's Mnesia and ETS; actor state stores (Orleans, Cloudflare Durable Objects, Akka Persistence); Convex and SpacetimeDB; and incrementally maintained views (Materialize, differential dataflow).

Go deepest on what the database gains when it can see or constrain the code (determinism, knowing what a function reads and writes), what went wrong with stored procedures, and how each system changes code and stored data together.

Context: a Mo service is already state, a log, snapshots, and a typed migration when the state's type changes, so this family is the closest to what Mo has.

## Answer

Findings: [research/07-code-inside-the-database.md](../research/07-code-inside-the-database.md).

- Almost every gain comes from two properties of the code: determinism, which allows retry, replay and subscriptions, and known read and write sets, which allow lock-free conflict checks and exact subscriptions. Convex shows both together.
- Only sandboxed systems (Convex, SpacetimeDB reducers) enforce the no-side-effects rule. Prevayler, Mnesia and Akka leave it to discipline, and PostgreSQL trusts volatility labels without checking them.
- No system found derives read and write sets from the code before it runs. A whole-program compiler like Mo's could, conservatively. This is an inference, not a sourced fact.
- Stored procedures failed mainly because the code lived outside version control, testing and deployment, not because the code sat next to the data. Convex and SpacetimeDB fix that by keeping the functions in the app repository.
- Mo already writes a snapshot at each upgrade and never reruns a migration. That avoids Akka-style event adapters and Prevayler's problem of replaying old commands through new code.
