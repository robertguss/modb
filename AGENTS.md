# AGENTS.md

MoDB is an embedded, crash-safe database built in pure Mo (`~/code/mo`, now a pure-Rust compiler
and runtime as of `robertguss/mo#433`), alongside the research, formal models, and design
decisions toward a database for many AI agents. Milestone 1 (Layer 1 CoW B+Tree storage engine +
Layer 2 typed tables and atomic secondary indexes), Milestone 2 (Layer 3 accountable
hash-chained audit ledger, commit-time invariants, atomic schema migrations, advisory `flock` +
`ReadFiles` least-privilege locking, and a live 8-worker `ShopApi` HTTP `api` server),
Milestone 3 (Layer 1 persistent root pins & O(diff) structural CoW diff + Layer 4 multi-agent
attenuated `Grants`, `Claims`, and speculative `Worlds` with TLA+ parity), Milestone 4
(layout-independent SHA-256 portable `Export`/import + upgrade-aware `Replay` with selective undo,
bug-fix overrides, and proposal-first adoption), Milestone 5 (zero-copy slotted page encoding,
right-edge splitting, raw binary-search reads/scans, lock-free optimistic CoW reads, and O(touched)
incremental invariants), Milestone 6 (real-world 8-worker multi-agent `AgentWorkbench` +
empirical coarse-vs-fine needless send-back, replay recovery, and `SIGKILL` simulation), and
Milestone 7 (live zero-CDN `WorkbenchUi` browser Inspector, native Streamable HTTP `POST /mcp`
server with 43 tools, and zero-dependency Python stdio MCP bridge `tools/modb_mcp_server.py`),
Milestone 8 (Grant-scoped hierarchical `Views` & k-anonymous `Releases`, zero-approval
sandboxed ad-hoc `ReadPrograms` with static field gating & read provenance log, stateless agent
self-onboarding `OnboardingManifest`, and O(1) CoW-diff incremental World read re-validation),
and Milestone 9 (first-class online `Export.backup_db`, atomic `Export.compact_db` /
`Export.compact_db_with_hook`, replay-safe `Replay.compact_with_baseline` preserving
`_modb_replay_baseline`, and production Worlds + Views integration in `motet`), and
Milestone 10 (`v0.2.0`: key-level & range-level `O(diff)` World read skipping, bounded-TTL
starvation fairness `PriorityTickets`, Nested Child Worlds with hierarchical attribution &
excision, schema-less ledger verification, and the standalone `modb` CLI in `src/modb/cli.mo`),
and Milestone 11 (`v0.3.0`: `Modb.Fts` transactional pure-Mo BM25+ full-text search index in
`src/modb/fts.mo` & `tests/test-fts.mo`, `Modb.Vec` quantized CoW vector & Hybrid RRF search in
`src/modb/vec.mo` & `tests/test-vec-hybrid.mo`, Workbench `/search` + `modb fts`/`modb vec` CLI),
and Milestone 12 (`Modb.Policy` `Public`/`Internal`/`Confidential`/`Secret` sensitivity lattice &
non-widening clearance enforcement across Views, Releases, FTS/Vec search & governed Export;
`Modb.Proposals` human-reviewed agent proposals with machine-checked `CapabilityDiff` & live
view/invariant materialization; `Modb.Feeds` CoW-pinned `txid`-cursor reactive change feeds;
`AgentWorkbench` 54 MCP tools + Governance & Feeds Inspector tab + `modb policy/proposals/feeds` CLI)
live in `src/`, `tools/`, verified in `tests/` and `bench/` and demonstrated in `examples/shop.mo`,
`examples/shop-api.mo`, `examples/agent-workbench.mo`, and `examples/workbench-ui.mo`.
`specs/` holds active build specs, `design.md` holds the broader long-term design, and `map.md` is
the earlier wayfinder map that Robert stopped on 2026-11-14.

## Layout

| Path | What it holds | Who edits it |
| --- | --- | --- |
| `mo.toml`, `src/` | Pure-Mo MoDB `v0.3.0` package: Layer 1 CoW B+Tree + pins/diff/import (`modb.mo`, `codec.mo`, `pager.mo`, `tree.mo`, `errors.mo`), Layer 2 typed tables, secondary indexes, transactional BM25+ FTS & quantized Vector/Hybrid RRF search (`table.mo`, `fts.mo`, `vec.mo`), Layer 3 accountable ledger, invariants, migrations & portable export/compaction (`ledger.mo`, `export.mo`), Layer 4 multi-agent coordination, views/read programs, sensitivity policy, human-reviewed agent proposals, reactive change feeds, child worlds, fairness & upgrade-aware replay (`grants.mo`, `claims.mo`, `replay.mo`, `world.mo`, `views.mo`, `policy.mo`, `proposals.mo`, `feeds.mo`), and standalone schema-less `modb` CLI (`cli.mo`) | Active build sessions |
| `tests/` | Differential tests, deterministic crash-simulation tests, typed-table tests, BM25 FTS & Vector/Hybrid tests (`test-fts.mo`, `test-vec-hybrid.mo`), Layer 3 ledger/migration/crash tests, Layer 1 pin/diff tests, Layer 4 `Replay.tla`/`Worlds.tla` parity tests, Experiment 18 multi-version replay & portable export tests, Milestone 8 views/releases/incremental read-validation tests, Milestone 9 backup/compaction tests (`test-compact-backup.mo`), Milestone 10 key/range O(diff), fairness, nested child-world & CLI tests (`test-m10-worlds-cli.mo`), Milestone 12 sensitivity policy, agent proposals & reactive change feed tests (`test-governance-feeds.mo`) (`mo test`), live 8-worker `mo serve` `SIGKILL` test (`test_shop_api_live.py`), and live stdio MCP + HTTP Inspector UI end-to-end test (`test_workbench_mcp_and_ui.py`) | Active build sessions |
| `examples/` | End-to-end MoDB example programs (`shop.mo` CLI demo, `shop-api.mo` e-commerce HTTP `api` server, `agent-workbench.mo` multi-agent project/task/budget/views/governance/feeds/search/replay/MCP HTTP `api` server, and `workbench-ui.mo` self-contained live browser Inspector UI) | Active build sessions |
| `tools/` | Zero-dependency Python 3 stdio MCP server bridge (`modb_mcp_server.py`) connecting MCP clients (Claude Desktop, Cursor, T3 Code) to live `AgentWorkbench` (`mo serve --workers 8`) | Active build sessions |
| `bench/` | Scale, freelist, and SQLite head-to-head benchmarks (`bench-modb.mo`), 1,000-doc FTS/Vector/Hybrid search benchmark (`bench-search.mo`), real OS `SIGKILL` crash loop (`kill_loop.py`), 8-worker HTTP concurrency benchmark (`bench_shop_api.py`), and 8-worker real-world multi-agent simulation (`real_world_agent_sim.py`) | Active build sessions |
| `specs/` | Active implementation specs (`milestone-1-storage-engine.md` through `milestone-12-governance-proposals-and-feeds.md`) and completed Mo PR / Rust-rewrite contracts | Active build sessions |
| `BENCHMARKS.md`, `FRICTION.md` | Verified gate/benchmark records and running Mo language/runtime friction log | Active build sessions |
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

## Verification commands

Using the pure-Rust `mo` release binary (`~/code/mo/target/release/mo` or `mo` on `PATH`):

```sh
mo test src/modb.mo
mo test src/modb/table.mo
mo test src/modb/fts.mo
mo test src/modb/vec.mo
mo test src/modb/ledger.mo
mo test src/modb/export.mo
mo test src/modb/grants.mo
mo test src/modb/claims.mo
mo test src/modb/replay.mo
mo test src/modb/world.mo
mo test src/modb/views.mo
mo test src/modb/policy.mo
mo test src/modb/proposals.mo
mo test src/modb/feeds.mo
mo test src/modb/cli.mo
mo test tests/test-modb.mo
mo test tests/test-table.mo
mo test tests/test-fts.mo
mo test tests/test-vec-hybrid.mo
mo test tests/test-ledger.mo
mo test tests/test-pins-diff.mo
mo test tests/test-worlds.mo
mo test tests/test-replay-export.mo
mo test tests/test-views-incremental.mo
mo test tests/test-compact-backup.mo
mo test tests/test-m10-worlds-cli.mo
mo test tests/test-governance-feeds.mo
mo test examples/shop.mo
mo test examples/shop-api.mo
mo test examples/agent-workbench.mo
python3 tests/test_shop_api_live.py "$(command -v mo || echo ~/code/mo/target/release/mo)"
python3 tests/test_workbench_mcp_and_ui.py "$(command -v mo || echo ~/code/mo/target/release/mo)"
python3 bench/real_world_agent_sim.py "$(command -v mo || echo ~/code/mo/target/release/mo)"
python3 bench/bench_shop_api.py "$(command -v mo || echo ~/code/mo/target/release/mo)"
python3 bench/kill_loop.py "$(command -v mo || echo ~/code/mo/target/release/mo)" 100
TMP=$(mktemp -d) && mo run --root "$TMP" bench/bench-search.mo 1000 && rm -rf "$TMP"
TMP=$(mktemp -d) && mo run --root "$TMP" bench/bench-modb.mo 100000 && rm -rf "$TMP"
```

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
