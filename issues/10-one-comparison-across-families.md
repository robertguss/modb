# One comparison across all families

Type: research
Status: resolved
Blocked by: [Compile the research into the wiki](19-compile-the-research-into-the-wiki.md)

## Question

Reading the wiki, what is the one comparison Robert can decide from?

Write `wiki/comparisons/families.md`: one table of the families against the same columns (what it is for, biggest strength, what pays for it, biggest weakness, how it handles overlapping work, what an agent struggles with). Then list the ideas worth borrowing with the cost of each, and the pairs of ideas that cannot be combined and why.

## Answer

[wiki/comparisons/families.md](../wiki/comparisons/families.md).

- Ranked by how many of the nine gaps each helps close (inference), the top ideas are reads and writes known up front, labels that follow data, deterministic functions as transactions, writes that carry their assumptions, and one writer at a time.
- The ideas that serve the gaps best all forbid the interactive, side-effecting transaction an agent would naturally hold open.
- Merges that never refuse a write (self-merging types, last writer wins) cannot keep rules that need a refusal, such as uniqueness or "never below zero".
- Keeping all history, and an audit the agent cannot erase, conflict with deleting a person's data.
- The wiki cannot say whether agents really hold transactions open, how much any security defence reduces harm, or how often agents meet each gap.
