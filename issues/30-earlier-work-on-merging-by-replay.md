# What earlier work stands behind merging by replay, checking reads again, and taking work back out?

Type: research
Status: resolved

## Question

design-ideas.md proposes that an agent's world is a list of calls replayed on the main line, that the reads the agent made are run again at landing, and that one agent's work can be removed by replaying the log without it. Find the strongest earlier work on each, what it found, what it cost and what became of it. Confirm or correct the claims the file marks as from Claude's own knowledge (Macaroons, Retro).

## Answer

The replay rule is not new; it is known parts in a combination nobody was found shipping. Replaying named calls is Bayou, Concurrent Revisions and Calvin; running reads again at commit is optimistic concurrency control from 1981. The least precedented part is capturing an agent's reads automatically. Three warnings: sending work back whenever an answer changed blocks far too much (a 2026 preprint measured 92 to 95% of harmless races blocked, and none by checks of declared rules); landing first come, first served starves slow agents; and taking one agent's work out is not a plain replay, since the systems that do it re-run only what was affected and still pay heavily. Findings: [research/30-earlier-work-on-merging-by-replay.md](../research/30-earlier-work-on-merging-by-replay.md).
