# How fast and how large is a Mo service today?

Type: task
Status: claimed

## Question

AFK. Measure on the current build in `~/code/mo`:

- the time a service takes to handle one message, apart from the MCP rate limit;
- how that time grows with the size of the state (each snapshot encodes the whole state);
- the largest state a service holds before a limit stops it.

The answer records the numbers and how they were taken.

The decision that waits on it: "fast enough that an agent never waits" needs a number, and `research/09-agents-and-databases-today.md` reports that agents send high volumes of exploratory reads.
