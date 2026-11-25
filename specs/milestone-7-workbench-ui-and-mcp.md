# Milestone 7 Spec: Interactive MoDB Workbench Inspector UI & MCP Agent Server

**Status:** Active implementation spec (2026-11-25)  
**Goal:** Make MoDB's full 4-layer multi-agent stack (`AgentWorkbench`) directly drivable by real AI
agents via the Model Context Protocol (MCP) and observable/operable by humans in a zero-build live
web inspector served straight from `mo serve --workers 8`.

## Components

1. **Inspector Listing & Interactive Demo Endpoints (`examples/agent-workbench.mo`):**
   - `GET /grants` (`Grants.list_all`) and `GET /worlds` (`World.list_worlds`) over `ReadFiles` so
     all Grants, delegation trees, Claims, Worlds, Replay calls/proposals, and Audit entries are
     inspectable without write privileges.
   - `POST /admin/demo`: idempotent one-click interactive demo seeder creating a realistic
     multi-agent scenario (two projects, open & completed tasks, root + delegated rogue grant,
     rogue budget drain, refused SRE tasks recorded as `OrigRefused`, and an open speculative
     World with staged changes ready for CoW diff inspection and Replay recovery).
2. **Self-Contained Live Web Inspector (`examples/workbench-ui.mo`, served at `GET /` and `GET /ui`):**
   - Pure-Mo embedded HTML/CSS/JS dashboard (`Api.html_response`) with zero external CDN or npm
     build dependencies so `mo serve --workers 8 --data DIR examples/agent-workbench.mo` serves both
     the API and live UI on a single port (`8092`).
   - Five live tabs: **Projects & Tasks** (budget bars, task completion, artifacts), **Grants &
     Claims** (delegation hierarchy, issue/delegate/cascading revoke, live leases), **Speculative
     Worlds** (open/query/call/O(diff) viewer/land/abort + needless send-back telemetry), **Replay
     Studio** (call log, `exclude_grant`/`exclude_principal`/`overhead_pct_override` simulator,
     proposal review showing `NowAccepted`/`ReplyChanged`/`Excluded` + atomic accept/discard), and
     **Audit Ledger** (hash chain + one-click `/admin/verify` & SHA-256 `/admin/export` download).
3. **Dual-Transport MCP Agent Server:**
   - **Native Streamable HTTP MCP (`POST /mcp` in `examples/agent-workbench.mo`):** Pure-Mo
     JSON-RPC 2.0 MCP endpoint (`protocolVersion: "2025-03-26"`) implementing `initialize`,
     `notifications/initialized`, `ping`, `tools/list` (22 structured tools with JSON Schemas), and
     `tools/call` reusing `AgentWorkbench`'s exact auth, RBAC, mandatory `reason`, Grants, Claims,
     Worlds, and Replay capture paths.
   - **Stdio MCP Bridge (`tools/modb_mcp_server.py`):** Zero-dependency Python 3 stdio JSON-RPC
     server for MCP hosts (Claude Code, Codex, Cursor, AGY) that either connects to an existing
     `--url` or auto-spawns and supervises `mo serve --workers 8 --data DIR` (strictly keeping
     `stdout` pure JSON-RPC and routing all logs + the live Inspector URL to `stderr`).
4. **Verification:**
   - Zero-socket `ApiTest.send` tests inside `examples/agent-workbench.mo` (`AgentWorkbench.test.2`)
     covering `GET /`, `GET /grants`, `GET /worlds`, `POST /admin/demo`, and full MCP JSON-RPC tool
     execution.
   - Live end-to-end stdio MCP + HTTP UI integration test (`tests/test_workbench_mcp_and_ui.py`)
     driving `tools/modb_mcp_server.py` over real pipes against `mo serve --workers 8`.
