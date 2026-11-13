# Security of a database that agents use

Type: research
Status: resolved

## Question

What does it take to build a database that stays secure when its users are AI agents, and what do current systems do and fail to do?

Cover the attacks seen from 2024 to 2026 (instructions injected through stored data, over-broad credentials, agents deleting or leaking data, poisoned tools and MCP servers, stolen tokens), and the defences: least privilege and short-lived credentials, capability-based security, treating data an agent reads as untrusted and tracking where it came from, information-flow control, approval and delay on destructive operations, undo, audit, and encryption at rest and in use.

Go deepest on:

- which defences can live inside the database and which only outside it;
- what the "lethal trifecta" (private data, untrusted content, a way to send data out) means for a database's design;
- how a database's own implementation gets attacked (memory-safety bugs, injection through the query language, the wire protocol, dependencies) and what the safest engines do about it;
- what is proven or measured, against what is only advice.

Context: Mo gives a program no ambient authority; every effect on the outside world goes through a capability value passed to it. Say what that model does and does not cover here. `research/09-agents-and-databases-today.md` has the recorded incidents as a starting point.

## Answer

Findings: [research/21-security-of-a-database-agents-use.md](../research/21-security-of-a-database-agents-use.md)

- A shared database holds all three legs of the lethal trifecta itself: private rows, untrusted rows written by others, and writes that others read. Removing an agent's web access does not close the way out.
- Measured results favour limiting over detecting: tuned attacks lifted agent hijacking from 11% to 81% (NIST), and adaptive attacks beat 12 published defences, most above 90%. Only plan-and-data splits (CaMeL, Fides) carry proofs, and they live in the harness.
- Defences only the database can enforce: narrowed short-lived grants per agent task, row labels for writer, trust and readers (IFDB measured about 1% cost), approval bound to a computed change, history and audit the agent cannot delete, and a statement authoriser.
- Engine attacks in 2025 were memory-safety bugs in protocol and scripting code (MongoBleed before login, RediShell) plus quoting and read-only bypasses. Memory-safe code and no parsing before login address the first kind.
- Mo's capabilities confine the database program's own effects, which covers poisoned dependencies and parser bugs phoning home. They do not cover which agent may read which row, exfiltration through ordinary writes, prompt injection, or bugs in the C VM.
