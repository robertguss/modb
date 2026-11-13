# Erlang ETS and Mnesia

ETS is Erlang's built-in in-memory table, and Mnesia is a replicated database built on it and queried from Erlang. In Mnesia a transaction is an ordinary Erlang function ([ets](https://www.erlang.org/doc/apps/stdlib/ets.html); [mnesia](https://www.erlang.org/doc/apps/mnesia/mnesia.html); [research 07](../../research/07-code-inside-the-database.md)).

## What it is for

Storing native Erlang terms, in memory or replicated across nodes, without leaving the language ([research 07](../../research/07-code-inside-the-database.md)).

## Core idea

- **ETS.** A table owned by the process that created it. "When the process terminates, the table is automatically destroyed" unless an heir is named. Writes take "exclusive access" to the table by default. Single operations are atomic; there are no transactions ([ets](https://www.erlang.org/doc/apps/stdlib/ets.html)).
- **Mnesia.** A transaction is an Erlang function (a "Fun") run under locks. "Since Mnesia detects deadlocks, a transaction can be restarted any number of times and therefore the Fun shall not have any side effects" ([mnesia](https://www.erlang.org/doc/apps/mnesia/mnesia.html)). A *deadlock* is two transactions each waiting for a lock the other holds.

## Strengths and what pays for each

- **Native terms and replication.** Paid for by: transaction code that must be safe to restart, which the language does not enforce ([research 07](../../research/07-code-inside-the-database.md)).

## Weaknesses

- After a network partition heals, Mnesia emits `inconsistent_database`. The default handler only logs an error, so recovery is the application's job ([Mnesia chapter 7](https://www.erlang.org/doc/apps/mnesia/mnesia_chap7.html)).
- Disk-only tables have a 2 GB limit. Research 07's only source for this is secondary, and it lists it as not confirmed ([Medium](https://medium.com/@matheuscamarques/a-comparative-technical-analysis-of-riak-and-mnesia-for-distributed-erlang-systems-c59529df59bb)).

## Overlapping work

Mnesia uses locks and detects deadlocks; one transaction in a deadlock is restarted ([mnesia](https://www.erlang.org/doc/apps/mnesia/mnesia.html)). ETS gives each write exclusive access to the table by default ([ets](https://www.erlang.org/doc/apps/stdlib/ets.html)).

## What an agent struggles with

A retried Fun that sends a message sends it twice, and nothing stops an agent from writing one ([research 07](../../research/07-code-inside-the-database.md)).

## Worth borrowing

The lesson is the contrast with Convex: both retry a transaction function, but Mnesia relies on the programmer to keep it free of side effects while Convex enforces it with a sandbox ([research 07](../../research/07-code-inside-the-database.md)). See [deterministic functions as transactions](../ideas/deterministic-functions-inside-transactions.md).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- ets: https://www.erlang.org/doc/apps/stdlib/ets.html
- mnesia: https://www.erlang.org/doc/apps/mnesia/mnesia.html
- Mnesia chapter 7: https://www.erlang.org/doc/apps/mnesia/mnesia_chap7.html
- Riak and Mnesia comparison (secondary): https://medium.com/@matheuscamarques/a-comparative-technical-analysis-of-riak-and-mnesia-for-distributed-erlang-systems-c59529df59bb
