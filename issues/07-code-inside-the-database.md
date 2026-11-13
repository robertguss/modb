# Code inside the database, and databases inside a language

Type: research
Status: claimed

## Question

Using the map's research template, what do systems that put code and data together do well and badly, and what pays for each strength?

Cover stored procedures and triggers; object prevalence (Prevayler) and image persistence (Smalltalk, GemStone); Erlang's Mnesia and ETS; actor state stores (Orleans, Cloudflare Durable Objects, Akka Persistence); Convex and SpacetimeDB; and incrementally maintained views (Materialize, differential dataflow).

Go deepest on what the database gains when it can see or constrain the code (determinism, knowing what a function reads and writes), what went wrong with stored procedures, and how each system changes code and stored data together.

Context: a Mo service is already state, a log, snapshots, and a typed migration when the state's type changes, so this family is the closest to what Mo has.
