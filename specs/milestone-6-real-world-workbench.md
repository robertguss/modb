# Milestone 6 Spec: Real-World Multi-Agent Workbench & Empirical Simulation

**Status:** Active implementation spec (Option 1, 2026-11-25)  
**Goal:** Exercise the entire pure-Mo MoDB stack (Layer 1 CoW B+Tree + persistent pins + lock-free
optimistic reads, Layer 2 typed tables & secondary indexes, Layer 3 hash-chained audit ledger +
O(touched) invariants + migrations + portable SHA-256 export, Layer 4 attenuated Grants + Claims +
speculative Worlds + upgrade-aware Replay) in a realistic multi-agent engineering workbench under
`mo serve --workers 8`, and collect real empirical measurements (throughput, latency, conflict rate,
coarse-vs-fine needless send-back floor, replay latency, and `SIGKILL` recovery).

## Components

1. **`examples/agent-workbench.mo` (`module AgentWorkbench`):**
   - Pure-Mo multi-agent HTTP `api` server managing `projects` (with `budget_cents`/`spent_cents`),
     `tasks` (with `tasks_by_project` and `tasks_by_status` secondary indexes), and `artifacts`
     (with `artifacts_by_task` index).
   - Enforces three commit-time invariants (`budget_bounds`, `task_valid`, `referential_integrity`),
     strict `ReadFiles`/`Files` capability separation, attenuated `Grants`, `Claims`, speculative
     `Worlds`, automatic replay call capture (including budget-exceeded refusals -> `OrigRefused`),
     offline `Replay` proposals (selective principal/grant/world undo + retroactive overhead
     bug-fix override), and SHA-256 `Export`.
   - Includes a zero-socket `ApiTest.send` end-to-end test suite.
2. **`bench/real_world_agent_sim.py`:**
   - Launches `AgentWorkbench` under `mo serve --workers 8` and executes a 3-phase real-world
     8-agent simulation:
     - **Phase 1 (Swarm & Needless Send-Back Experiment):** Compares coordinated (Claims + fine
       queries) vs uncoordinated coarse-query (`list_project_tasks`) vs fine-query (`get_task` +
       `get_project`) multi-agent Worlds, directly measuring `needless_send_backs` (`design-ideas.md`).
     - **Phase 2 (Rogue Sub-Agent Containment & Selective-Undo Replay):** Compromised delegated
       grant drains project budget causing legitimate SRE work to be refused (`409`); Admin revokes
       parent grant mid-flight (`403` cascade), simulates `exclude_grant` replay (`NowAccepted`
       unblocks SRE tasks), inspects diff/outcomes, and accepts atomically.
     - **Phase 3 (Bug-Fix Overhead Replay + Portable Export + Hard `SIGKILL`):** Retroactively
       fixes a 10% overhead billing bug via replay proposal -> accept, verifies `GET /admin/export`,
       fires hard OS `SIGKILL`, restarts 8 workers, and verifies full state & SHA-256 audit chain.
