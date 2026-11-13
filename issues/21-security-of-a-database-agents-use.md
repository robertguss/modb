# Security of a database that agents use

Type: research
Status: claimed

## Question

What does it take to build a database that stays secure when its users are AI agents, and what do current systems do and fail to do?

Cover the attacks seen from 2024 to 2026 (instructions injected through stored data, over-broad credentials, agents deleting or leaking data, poisoned tools and MCP servers, stolen tokens), and the defences: least privilege and short-lived credentials, capability-based security, treating data an agent reads as untrusted and tracking where it came from, information-flow control, approval and delay on destructive operations, undo, audit, and encryption at rest and in use.

Go deepest on:

- which defences can live inside the database and which only outside it;
- what the "lethal trifecta" (private data, untrusted content, a way to send data out) means for a database's design;
- how a database's own implementation gets attacked (memory-safety bugs, injection through the query language, the wire protocol, dependencies) and what the safest engines do about it;
- what is proven or measured, against what is only advice.

Context: Mo gives a program no ambient authority; every effect on the outside world goes through a capability value passed to it. Say what that model does and does not cover here. `research/09-agents-and-databases-today.md` has the recorded incidents as a starting point.
