# AGENTS.md

MoDB is the research and the decisions toward a database for many AI agents, to be built in Mo
(`~/code/mo`). It holds no database code yet. `design.md` is the design as it stands. `map.md` is
the map that led to it, which Robert stopped on 2026-11-14.

## Layout

| Path | What it holds | Who edits it |
| --- | --- | --- |
| `map.md`, `issues/` | The wayfinder map and its tickets, stopped on 2026-11-14 and kept as a record | Nobody |
| `research/` | One findings file for each research ticket | Written once, then never edited |
| `raw/` | Primary sources saved word for word (papers, pages); created when first needed | Never edited |
| `wiki/` | The compiled knowledge base | Agents only |
| `GLOSSARY.md` | The project's vocabulary | The `domain-modeling` skill |
| `models/` | TLA+ models of the design's protocols, each with predictions written before the model and settings that must fail | The session working a prototype ticket |
| `sketches/` | Small Mo programs that check a claim about what Mo can do today, each with a control that must fail, and scripts that measure it; not database code | The session making the claim |
| `design.md` | The data store and the database designed from what they need, and what Mo must gain; a draft until Robert accepts it | The session working on the design with Robert |
| `design-ideas.md` | Our own candidate ideas for the database while they are explored; each says what Mo has, what it needs, earlier work and what is open | The session exploring them with Robert |
| `docs/ideation/` | Ranked idea sets from `ce-ideate` runs, one dated file each, with what was cut and why; candidates, not decisions | The `ce-ideate` skill |
| `experiments.md` | Every open decision with its options and the small experiments that would settle it; each experiment has predictions written before it runs and a control that must fail | The session running the experiment |

`research/` and `raw/` are sources. `wiki/` is what gets read. A correction to a source goes in the
wiki, never in the source.

## The map

Local markdown tracker for the `wayfinder` skill. Robert stopped the map on 2026-11-14 before its
destination. Take no ticket from it. `Status: closed` marks a ticket closed unanswered that day.
The rules below are how it was worked.

- A ticket is `issues/NN-slug.md` with `Type:` (`research`, `prototype`, `grilling`, `task`),
  `Status:` (`open`, `claimed`, `resolved`) and an optional `Blocked by:` line.
- Claim a ticket by setting `Status: claimed` before any work.
- Resolve it by appending `## Answer`, setting `Status: resolved`, and adding one line to
  `map.md` under Decisions so far.
- The frontier is every open ticket whose blockers are all resolved; lowest number first.

## The wiki

The pattern is the LLM Wiki: sources are compiled once into interlinked pages and kept current,
so a question is answered from the wiki and not by re-reading sources.

| Folder | One page per | Sections, in order |
| --- | --- | --- |
| `wiki/systems/` | Database or system (`postgresql.md`) | What it is for; Core idea; Strengths and what pays for each; Weaknesses; Overlapping work; What an agent struggles with; Worth borrowing; Disagreements; Sources |
| `wiki/ideas/` | Design idea (`multi-version-snapshots.md`) | What it is; The problem it solves; What it costs; Systems that use it; Cannot be combined with; Disagreements; Sources |
| `wiki/families/` | Family of databases | What they are for; Members; Shared tradeoffs; Sources |
| `wiki/comparisons/` | Comparison across systems or families | A table first, then what it shows |
| `wiki/questions/` | Answer worth keeping | The question; The answer; Pages it rests on |

`wiki/overview.md` is the current synthesis. `wiki/index.md` lists every page with a link and one
line, grouped by folder. `wiki/log.md` is append-only, one entry per operation:
`## [YYYY-MM-DD] ingest | <title>` (or `query`, `lint`).

Rules for every page:

- Every claim cites a URL, or a file in `raw/` or `research/`.
- A vendor's claim about itself is marked "vendor claim". Reasoning with no source is marked "inference".
- Every strength is written with the constraint that pays for it.
- When sources disagree, say so under Disagreements; never pick one silently.
- Links are relative markdown links. File names are lower-case words joined by hyphens.
- Omit a section that has nothing in it.
- Plain language and short sentences. Explain a specialist term the first time a page uses it.

## Workflows

**Ingest**, one source at a time:

1. Read the source in full.
2. Create or update the page of every system and idea it covers.
3. Update the family pages and `wiki/overview.md` where the synthesis changed.
4. Update `wiki/index.md`.
5. Append the entry to `wiki/log.md`, naming the pages touched.

**Query:** read `wiki/index.md` first, then the pages it points to. Answer with links to pages.
File an answer worth keeping in `wiki/questions/`, then update the index and the log.

**Lint:** look for contradictions between pages, claims a newer source replaced, pages nothing
links to, ideas mentioned without a page, missing links, and claims with no source. Fix what the
sources settle, list the rest, and append the entry to the log.

## Rules

- Web research uses Exa. Queries carry no person's name, project name or personal detail.
- Ask Robert one question at a time, with a recommendation, the reason and a confidence percentage.
- Commit after each logical unit, staging only the files you changed.
