# Recording why a write happened (gap)

The idea is a database that stores the reason for each write, and who asked for it, as part of the write. No system found does this; this page records how close they come.

## What it is

Each write would carry, as checked data, its reason, the requester, and the approver: for example "agent A, acting for Robert, under rule R" ([05](../../research/05-databases-that-keep-history.md)). [09](../../research/09-agents-and-databases-today.md) frames it as tying a write to the agent's task, its inputs, and the rule that allowed it.

## The problem it solves

History stores record what changed and when. Without the why (the intent, the triggering request, or the agent's reasoning), provenance is left to logs outside the database (inference, [00](../../research/00-landscape-overview.md)). An agent choosing between two sides of a merge needs both sides' intent, which a branch does not record ([06](../../research/06-divergent-copies-and-merging.md)).

Research 21 adds a security reason: an append-only audit tied to agent and task makes theft and unexplained changes traceable, but only if the audited actor cannot edit it ([21](../../research/21-security-of-a-database-agents-use.md)). See [history and audit the agent cannot erase](history-and-audit-the-agent-cannot-erase.md).

## What it costs

The researcher's inference: designing a schema for intent and making every writer supply it ([05](../../research/05-databases-that-keep-history.md)).

## Systems that use it

None makes *why* a required part of a write ([05](../../research/05-databases-that-keep-history.md)). The nearest:

- **[Datomic](../systems/datomic.md)** comes closest. A transaction is an entity, and you "can add additional attributes ... such as the purpose of the transaction, the application that executed it, the provenance of the data ..., or the user who caused it" (https://docs.datomic.com/transactions/transaction-data-reference.html). It is optional and unchecked; teams invent attributes like "admin user working on behalf of another user" (https://cjohansen.no/annotating-datomic-transactions/).
- **[XTDB](../systems/xtdb.md)**: free-form transaction `METADATA` for "upstream request IDs, correlation IDs, or other data lineage information" (https://docs.xtdb.com/reference/main/sql/txs.html).
- **[KurrentDB](../systems/kurrentdb.md)**: `$correlationId` and `$causationId` link an event to the request and message that caused it (https://docs.kurrent.io/server/v26.0/features/streams). That gives "because of what", not a reason or an approver.
- **[Oracle](../systems/oracle.md)**: Flashback Transaction Query shows `LOGON_USER` per change (https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/FLASHBACK_TRANSACTION_QUERY.html), usually a shared application account ([05](../../research/05-databases-that-keep-history.md)).
- **[Amazon QLDB](../systems/amazon-qldb.md)**: `id`, `version`, `txTime`, `txId`; no user, no reason (https://docs.aws.amazon.com/qldb/latest/developerguide/working.metadata.by-clause.html). Snowflake and SQL:2011 tables likewise record time and transaction only ([05](../../research/05-databases-that-keep-history.md)).
- **[Dolt](../systems/dolt.md)**: a commit log with author and message ([09](../../research/09-agents-and-databases-today.md)). The message is free text (inference, [09](../../research/09-agents-and-databases-today.md)).

None records a chain of authority, none rejects a write without a reason, and none treats reasons as typed, queryable data. The slot exists (the transaction record); nothing fills it, checks it or gives it meaning ([05](../../research/05-databases-that-keep-history.md)).

## Disagreements

- **Do history stores record who made a change?** [00](../../research/00-landscape-overview.md) says bitemporal stores record when a fact changed and who wrote it, but not why. [05](../../research/05-databases-that-keep-history.md) says QLDB, Snowflake and SQL:2011 tables record only time and transaction (no user), Oracle records only a usually shared logon user, and Datomic and XTDB can hold a purpose or requester only in optional, unchecked transaction metadata.

## Sources

- [research/00-landscape-overview.md](../../research/00-landscape-overview.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- [research/06-divergent-copies-and-merging.md](../../research/06-divergent-copies-and-merging.md)
- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- https://docs.datomic.com/transactions/transaction-data-reference.html
- https://cjohansen.no/annotating-datomic-transactions/
- https://docs.xtdb.com/reference/main/sql/txs.html
- https://docs.kurrent.io/server/v26.0/features/streams
- https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/FLASHBACK_TRANSACTION_QUERY.html
- https://docs.aws.amazon.com/qldb/latest/developerguide/working.metadata.by-clause.html
