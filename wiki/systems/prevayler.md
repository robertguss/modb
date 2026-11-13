# Prevayler

Prevayler is a Java library that keeps all business objects in memory and makes them durable by logging every change as a command. It is the best-known example of *object prevalence* ([Prevayler FAQ](https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html); [research 07](../../research/07-code-inside-the-database.md)).

## What it is for

Keeping all business objects in RAM to avoid "all that database hassle" ([Prevayler FAQ](https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html)).

## Core idea

Each change is a serializable command, written to a journal (a *command log*) before it is applied. A periodic snapshot plus the journal rebuilds the state ([FAQ](https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html)). `execute()` guarantees "only one Transaction is executed at a time" ([Prevayler API](https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html)).

## Strengths and what pays for each

**No concurrency bugs inside the model, and queries are plain method calls.** Three constraints pay for this ([research 07](../../research/07-code-inside-the-database.md)):

- all data fits in RAM;
- every change is a command;
- commands are deterministic: they use the `executionTime` passed in and never the clock, or replay diverges ([API](https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html)).

## Weaknesses

- Snapshots block writes while they run ([API](https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html)).
- Transactions must be short "because they block the system", and long ones are "an open question". This is said of cl-prevalence, the Common Lisp version of the same design ([cl-prevalence](https://cl-prevalence.common-lisp.dev/)).
- The determinism rule is stated, not enforced; Prevayler relies on discipline ([research 07](../../research/07-code-inside-the-database.md)).
- When code changes, the stored data sits in a journal of serialized commands that new classes must still be able to read (inference, [research 07](../../research/07-code-inside-the-database.md)). Research 07 could not confirm how Prevayler handles class changes in an existing journal.

## Overlapping work

None inside the model: one transaction runs at a time ([API](https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html)).

## Worth borrowing

Research 07 compares Prevayler with Mo, which also replays a log to rebuild state. Mo's upgrade writes a snapshot at the head of the log in one SQLite transaction and deletes the log tail, so "restart never reruns the migration" (`~/code/mo/docs/design/upgrades.md`, lines 18–19 and 118–119). That avoids replaying old commands through new code. Cost: old history survives only in retained snapshots ([research 07](../../research/07-code-inside-the-database.md)).

## Sources

- [research 07: Code inside the database](../../research/07-code-inside-the-database.md)
- Prevalence Skeptical FAQ: https://prevayler.org/old_wiki/PrevalenceSkepticalFAQ.html
- Prevayler API 2.6: https://prevayler.org/apidocs/2.6/org/prevayler/Prevayler.html
- cl-prevalence: https://cl-prevalence.common-lisp.dev/
