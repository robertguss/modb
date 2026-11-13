# A database for many agents

The vocabulary of the effort to decide what database to build in Mo, kept so that each session uses the same words.

## Language

**Overlapping work**:
Work by two or more agents on the same data whose spans in time intersect, whether or not any two operations execute at the same instant.
_Avoid_: Concurrency, concurrent

**Parallel execution**:
Two or more operations executing at the same instant on different cores.
_Avoid_: Concurrency, concurrent

**Coordination**:
Keeping overlapping work correct and accountable: conflicts, history, undo and guarded writes.
_Avoid_: Concurrency control

**Guarded write**:
A write the database rejects or holds because it would break a rule a person approved.
_Avoid_: Validation, constraint

**Driver project**:
An ambitious program built in Mo whose needs decide what Mo gains next.
_Avoid_: Real software, demo

**Real use**:
Robert relying on a program with his own data, for its own sake.
_Avoid_: Real software, dogfooding

**First slice**:
The smallest version of the database that is in real use.
_Avoid_: MVP, prototype
