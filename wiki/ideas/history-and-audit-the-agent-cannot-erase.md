# History and audit the agent cannot erase

Undo and audit protect only if the agent whose actions they record cannot delete or edit them. That means a second authority over the history, and a log tied to the agent and the task.

## What it is

Two defences from research 21's table ([21](../../research/21-security-of-a-database-agents-use.md)):

- **History the agent cannot delete**, so a destructive change can be undone.
- **An append-only audit log tied to agent and task**, so theft and unexplained changes can be traced.

## The problem it solves

- **Lost data and backups.** PocketOS lost its backups with the volume the agent deleted; Replit's agent deleted a production database ([09](../../research/09-agents-and-databases-today.md)). Undo protects only if the agent's credential cannot also delete the history (inference, [21](../../research/21-security-of-a-database-agents-use.md)).
- **Hidden theft.** In the August 2025 Salesloft Drift theft, the attacker deleted its query jobs, but "logs were not impacted", so the theft was traceable (https://cloud.google.com/blog/topics/threat-intelligence/data-theft-salesforce-instances-via-salesloft-drift).

## What it costs

- **Storage, and a second authority** ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Privacy of the log.** An audit log is itself a store of who did what ([21](../../research/21-security-of-a-database-agents-use.md)). See [deleting personal data from history](deleting-personal-data-from-history.md).
- **Unmeasured.** Research 21 found no measurement of how much undo reduces harm from agents.

## Systems that use it

- [Amazon QLDB](../systems/amazon-qldb.md) offered cryptographic verification of its history and reached end of support on 2025-07-31 (https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html).
- [Oracle](../systems/oracle.md) Flashback Time Travel keeps history tables that even a database administrator cannot edit ([05](../../research/05-databases-that-keep-history.md), https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html).
- Railway made its volume-delete endpoint delay deletions after PocketOS ([09](../../research/09-agents-and-databases-today.md)).

Related: [facts that are added, never changed](append-only-facts.md) and [recording why a write happened](recording-why-a-write-happened.md).

## Sources

- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- [research/09-agents-and-databases-today.md](../../research/09-agents-and-databases-today.md)
- [research/05-databases-that-keep-history.md](../../research/05-databases-that-keep-history.md)
- https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/flashback.html
- https://cloud.google.com/blog/topics/threat-intelligence/data-theft-salesforce-instances-via-salesloft-drift
- https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html
