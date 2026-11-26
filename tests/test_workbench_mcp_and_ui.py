#!/usr/bin/env python3
"""End-to-end integration test for Milestone 7:
  1. Launches `tools/modb_mcp_server.py` over real stdin/stdout JSON-RPC pipes (auto-spawning
     `mo serve --workers 8` against a fresh temporary data directory).
  2. Verifies stdout carries ONLY valid JSON-RPC frames while stderr carries diagnostics + UI URL.
  3. Drives full MCP lifecycle: `initialize` -> `notifications/initialized` -> `ping` ->
     `tools/list` (31 tools) -> `tools/call` across:
       - `modb_seed_demo`
       - `modb_list_projects`, `modb_list_grants`, `modb_list_claims`, `modb_list_worlds`
       - `modb_world_diff`, `modb_world_land` (landing open demo World `w-demo-payments-401`)
       - `modb_revoke_grant` (cascading parent revocation of `g-team-b`)
       - `modb_replay_simulate` (`exclude_grant: "g-team-b"` -> `excluded=2, now_accepted=2`)
       - `modb_replay_accept` (unblocks SRE tasks #303 & #304 on `infra`)
       - `modb_replay_simulate` (`overhead_pct_override: 0` -> `reply_changed >= 1`) + accept
       - `modb_export_snapshot` (verified SHA-256) & `modb_verify` (`ok: true`)
  4. Verifies the live Web Inspector UI (`GET /` and `GET /ui`) and all inspector JSON endpoints
     (`/projects`, `/grants`, `/claims`, `/worlds`, `/worlds/metrics`, `/audit`, `/admin/replay/calls`,
     `/admin/replay/proposals`) against the exact same running server!
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import urllib.request


def read_json_line(proc: subprocess.Popen[str]) -> dict:
    line = proc.stdout.readline()  # type: ignore[union-attr]
    if not line:
        raise RuntimeError(f"MCP server closed stdout unexpectedly (rc={proc.poll()})")
    return json.loads(line)


def send_rpc(proc: subprocess.Popen[str], obj: dict) -> None:
    proc.stdin.write(json.dumps(obj) + "\n")  # type: ignore[union-attr]
    proc.stdin.flush()  # type: ignore[union-attr]


def call_tool(proc: subprocess.Popen[str], req_id: int, name: str, arguments: dict) -> tuple[bool, object]:
    send_rpc(
        proc,
        {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        },
    )
    resp = read_json_line(proc)
    assert resp["jsonrpc"] == "2.0" and resp["id"] == req_id, resp
    assert "result" in resp, resp
    res = resp["result"]
    text = res["content"][0]["text"]
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = text
    return bool(res["isError"]), parsed


def http_get(url: str) -> tuple[int, str]:
    with urllib.request.urlopen(url, timeout=15.0) as resp:
        return resp.status, resp.read().decode("utf-8")


def main() -> int:
    mo_bin = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/bin/mo")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    bridge = os.path.join(repo_root, "tools", "modb_mcp_server.py")

    # Verify --print-config outputs valid JSON cleanly
    cfg_raw = subprocess.check_output(
        [sys.executable, bridge, "--print-config", "--data", "/tmp/demo-wb"], text=True
    )
    cfg = json.loads(cfg_raw)
    assert "modb-workbench" in cfg["mcpServers"], cfg

    stderr_lines: list[str] = []

    with tempfile.TemporaryDirectory(prefix="modb-mcp-e2e-") as tmp:
        proc = subprocess.Popen(
            [
                sys.executable,
                bridge,
                "--mo",
                mo_bin,
                "--data",
                tmp,
                "--workers",
                "8",
                "--token",
                "wb-admin",
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

        def drain_stderr() -> None:
            assert proc.stderr is not None
            for line in proc.stderr:
                stderr_lines.append(line.strip())

        err_thread = threading.Thread(target=drain_stderr, daemon=True)
        err_thread.start()

        try:
            # 1. MCP Handshake
            send_rpc(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
            init_resp = read_json_line(proc)
            assert init_resp["result"]["serverInfo"]["name"] == "modb-agent-workbench", init_resp
            assert init_resp["result"]["serverInfo"]["version"] == "0.8.1", init_resp
            assert init_resp["result"]["protocolVersion"] == "2025-03-26", init_resp

            send_rpc(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

            send_rpc(proc, {"jsonrpc": "2.0", "id": 2, "method": "ping"})
            ping_resp = read_json_line(proc)
            assert ping_resp["id"] == 2 and ping_resp["result"] == {}, ping_resp

            # 2. Discover tools
            send_rpc(proc, {"jsonrpc": "2.0", "id": 3, "method": "tools/list"})
            list_resp = read_json_line(proc)
            tools = list_resp["result"]["tools"]
            tool_names = {t["name"] for t in tools}
            assert len(tools) >= 67, len(tools)
            for req in (
                "modb_seed_demo",
                "modb_search",
                "modb_search_stats",
                "modb_policy_get",
                "modb_clearance_set",
                "modb_proposal_submit",
                "modb_proposals_list",
                "modb_proposal_approve",
                "modb_proposal_reject",
                "modb_feed_subscribe",
                "modb_feeds_list",
                "modb_feed_poll",
                "modb_feed_consume",
                "modb_feed_unsubscribe",
                "modb_taint_sessions",
                "modb_taint_record_untrusted",
                "modb_taint_clear",
                "modb_erasure_receipts",
                "modb_list_grants",
                "modb_list_worlds",
                "modb_world_diff",
                "modb_world_land",
                "modb_world_telemetry",
                "modb_world_open_child",
                "modb_world_list_children",
                "modb_world_land_child",
                "modb_world_claim_priority",
                "modb_world_land_fair",
                "modb_replay_simulate",
                "modb_replay_accept",
                "modb_export_snapshot",
                "modb_verify",
                "modb_describe",
                "modb_read_program",
                "modb_release",
                "modb_read_log",
                "modb_explain_view",
                "modb_matviews_list",
                "modb_matview_refresh",
                "modb_matview_query",
            ):
                assert req in tool_names, f"missing MCP tool {req}"

            # 3. Seed demo & drive Grants / Claims / Worlds / CoW Diff / Views / Releases / Replay via MCP!
            is_err, seeded = call_tool(proc, 10, "modb_seed_demo", {"reason": "e2e MCP demo"})
            assert not is_err and seeded["ok"] is True, (is_err, seeded)

            # Milestone 11B: Transactional BM25 + Vector + Hybrid RRF search over demo tasks
            is_err, s_stats = call_tool(proc, 97, "modb_search_stats", {})
            assert not is_err and s_stats["fts"]["doc_count"] >= 6 and s_stats["vec"]["doc_count"] == s_stats["fts"]["doc_count"], (
                is_err,
                s_stats,
            )
            is_err, s_fts = call_tool(
                proc, 98, "modb_search", {"query": "failov", "mode": "fts", "project_id": "infra"}
            )
            assert not is_err and s_fts["hits"] and s_fts["hits"][0]["doc_id"] == "task:303", (is_err, s_fts)
            is_err, s_hyb = call_tool(
                proc, 99, "modb_search", {"query": "ledger reconciliation", "mode": "hybrid", "limit": 5}
            )
            assert not is_err and s_hyb["hits"] and s_hyb["hits"][0]["doc_id"] == "task:401", (is_err, s_hyb)

            # Milestone 8: Stateless agent onboarding (`modb_describe`), View field hiding, & k-anonymous Release
            is_err, desc_rogue = call_tool(proc, 101, "modb_describe", {"grant_id": "g-rogue-sub"})
            assert not is_err, desc_rogue
            rogue_views = [v["name"] for v in desc_rogue["allowed_views"]]
            assert rogue_views == ["tasks_public"], rogue_views
            rogue_fields = {f["name"] for f in desc_rogue["allowed_views"][0]["fields"]}
            assert "billed_cents" not in rogue_fields and "title" in rogue_fields, rogue_fields

            # Negative control: querying hidden field `billed_cents` on `tasks_public` fails statically
            is_err, bad_read = call_tool(
                proc,
                102,
                "modb_read_program",
                {
                    "grant_id": "g-rogue-sub",
                    "program": {
                        "view": "tasks_public",
                        "where_clause": {"gt": {"field": "billed_cents", "value": 0}},
                    },
                },
            )
            assert is_err and "view_field_blocked" in json.dumps(bad_read), (is_err, bad_read)

            # Valid ad-hoc ReadProgram on `tasks_public` succeeds and records read provenance
            is_err, good_read = call_tool(
                proc,
                103,
                "modb_read_program",
                {
                    "grant_id": "g-rogue-sub",
                    "program": {
                        "view": "tasks_public",
                        "where_clause": {"eq": {"field": "project_id", "value": "infra"}},
                        "order_by": {"field": "id", "desc": False},
                    },
                },
            )
            assert not is_err and good_read["result_count"] == 4, (is_err, good_read)

            # Approved k-anonymous Release: 3 projects >= 2 passes; high min_budget (1 project < 2) blocked!
            is_err, rel_ok = call_tool(
                proc,
                104,
                "modb_release",
                {"grant_id": "g-sre", "release": "project_budget_summary", "args": {}},
            )
            assert not is_err and rel_ok["cohort_size"] == 3, (is_err, rel_ok)
            is_err, rel_blocked = call_tool(
                proc,
                105,
                "modb_release",
                {
                    "grant_id": "g-sre",
                    "release": "project_budget_summary",
                    "args": {"min_budget_cents": 90000},
                },
            )
            assert is_err and "release_blocked" in json.dumps(rel_blocked), (is_err, rel_blocked)

            is_err, rlog = call_tool(proc, 106, "modb_read_log", {"limit": 10})
            assert not is_err and len(rlog) == 2, (is_err, rlog)

            is_err, diff = call_tool(proc, 11, "modb_world_diff", {"world_id": "w-demo-payments-401"})
            assert not is_err and isinstance(diff, list) and len(diff) >= 2, (is_err, diff)

            # Note: even after 2 `_modb_read_log` writes above, zero data buckets changed since w-demo-payments-401
            # opened, so Layer 1 CoW O(diff) skips re-executing `get_task` (`reads_skipped == 1`)!
            is_err, landed = call_tool(
                proc,
                12,
                "modb_world_land",
                {"world_id": "w-demo-payments-401", "reason": "land reconciliation via MCP"},
            )
            assert not is_err and landed["commit_txid"] > 0 and landed["reads_skipped"] == 1, (is_err, landed)

            is_err, rev = call_tool(
                proc, 13, "modb_revoke_grant", {"id": "g-team-b", "reason": "contain rogue parent"}
            )
            assert not is_err and rev["revoked"] is True, (is_err, rev)

            is_err, prop1 = call_tool(
                proc,
                14,
                "modb_replay_simulate",
                {
                    "proposal_id": "mcp-undo-rogue",
                    "description": "Excise rogue grant subtree g-team-b",
                    "exclude_grant": "g-team-b",
                },
            )
            assert not is_err, prop1
            assert prop1["summary"]["excluded"] == 2 and prop1["summary"]["now_accepted"] == 2, prop1["summary"]

            is_err, acc1 = call_tool(
                proc,
                15,
                "modb_replay_accept",
                {"proposal_id": "mcp-undo-rogue", "reason": "adopt rogue excision"},
            )
            assert not is_err and isinstance(acc1["status"], dict) and "accepted" in acc1["status"], (is_err, acc1)

            # Bug-fix replay: 10% -> 0% overhead override
            is_err, prop2 = call_tool(
                proc,
                16,
                "modb_replay_simulate",
                {
                    "proposal_id": "mcp-zero-overhead",
                    "description": "Remove 10% billing overhead",
                    "exclude_grant": "g-team-b",
                    "overhead_pct_override": 0,
                },
            )
            assert not is_err and prop2["summary"]["reply_changed"] >= 1, (is_err, prop2)

            is_err, acc2 = call_tool(
                proc,
                17,
                "modb_replay_accept",
                {"proposal_id": "mcp-zero-overhead", "reason": "apply 0% overhead fix"},
            )
            assert not is_err and isinstance(acc2["status"], dict) and "accepted" in acc2["status"], (is_err, acc2)

            is_err, projects = call_tool(proc, 18, "modb_list_projects", {})
            assert not is_err, projects
            by_id = {p["id"]: p for p in projects}
            assert by_id["infra"]["spent_cents"] == 20000, by_id["infra"]
            assert by_id["payments"]["spent_cents"] == 8000, by_id["payments"]

            is_err, snap = call_tool(proc, 19, "modb_export_snapshot", {})
            assert not is_err and snap["format_version"] == 1 and len(snap["sha256"]) == 64, (is_err, snap)

            is_err, ver = call_tool(proc, 20, "modb_verify", {})
            assert not is_err and ver["ok"] is True, (is_err, ver)

            # Milestone 10: Range O(diff) skipping, Nested Child Worlds & Fairness Landing via MCP!
            is_err, del_child = call_tool(
                proc,
                110,
                "modb_delegate_grant",
                {
                    "parent_id": "g-sre",
                    "id": "g-sre-child",
                    "principal": "agent:sre-child",
                    "allowed_actions": ["complete_task"],
                    "max_calls": 5,
                    "ttl_seconds": 1800,
                    "reason": "delegate M10 child grant",
                },
            )
            assert not is_err and del_child["id"] == "g-sre-child", (is_err, del_child)

            for tid, title in [(403, "M10 task 403"), (404, "M10 task 404")]:
                is_err, created_t = call_tool(
                    proc,
                    110 + (tid - 402),
                    "modb_create_task",
                    {
                        "id": tid,
                        "project_id": "payments",
                        "title": title,
                        "base_cost_cents": 4000,
                        "reason": f"create task {tid} for M10",
                    },
                )
                assert not is_err and created_t["id"] == tid, (is_err, created_t)

            is_err, wp = call_tool(
                proc,
                113,
                "modb_world_open",
                {"id": "w-m10-parent", "grant_id": "g-sre", "ttl_seconds": 600},
            )
            assert not is_err and wp["id"] == "w-m10-parent", (is_err, wp)

            is_err, rng = call_tool(
                proc,
                114,
                "modb_world_query",
                {
                    "world_id": "w-m10-parent",
                    "query": "scan_tasks_range",
                    "args": {"start_id": 403, "end_id": 405, "limit": 20},
                },
            )
            assert not is_err and [r["id"] for r in rng] == [403, 404], (is_err, rng)

            is_err, wc = call_tool(
                proc,
                115,
                "modb_world_open_child",
                {
                    "parent_world_id": "w-m10-parent",
                    "id": "w-m10-child",
                    "grant_id": "g-sre-child",
                    "ttl_seconds": 300,
                },
            )
            assert not is_err and wc["id"] == "w-m10-child", (is_err, wc)

            is_err, kids = call_tool(
                proc, 116, "modb_world_list_children", {"parent_world_id": "w-m10-parent"}
            )
            assert not is_err and [w["id"] for w in kids] == ["w-m10-child"], (is_err, kids)

            is_err, wc_call = call_tool(
                proc,
                117,
                "modb_world_call",
                {
                    "world_id": "w-m10-child",
                    "action": "complete_task",
                    "args": {
                        "task_id": 403,
                        "assignee": "agent:sre-child",
                        "artifact_id": "art-pay-403",
                        "artifact_summary": "Child M10 task output",
                        "artifact_sha256": "m10child0403",
                    },
                    "reason": "child completes 403",
                },
            )
            assert not is_err, (is_err, wc_call)

            is_err, lc = call_tool(
                proc,
                118,
                "modb_world_land_child",
                {"world_id": "w-m10-child", "reason": "merge M10 child 403"},
            )
            assert not is_err and lc["calls_merged"] == 1 and lc["parent_world_id"] == "w-m10-parent", (
                is_err,
                lc,
            )

            # Mutate disjoint task #402 directly on main line (outside [403, 405)) so O(diff) skips range!
            is_err, d402 = call_tool(
                proc,
                119,
                "modb_complete_task",
                {
                    "task_id": 402,
                    "assignee": "agent:sre",
                    "artifact_id": "art-pay-402",
                    "artifact_summary": "Direct disjoint complete 402",
                    "artifact_sha256": "m10direct402",
                    "reason": "disjoint direct complete",
                },
            )
            assert not is_err, (is_err, d402)

            is_err, lf = call_tool(
                proc,
                120,
                "modb_world_land_fair",
                {"world_id": "w-m10-parent", "reason": "land M10 parent fairly"},
            )
            assert not is_err and isinstance(lf, dict) and "landed_ok" in lf, (is_err, lf)
            lf_res = lf["landed_ok"]["result"]
            assert lf_res["calls_replayed"] == 1 and lf_res["reads_skipped"] >= 1, lf_res

            is_err, tel = call_tool(proc, 121, "modb_world_telemetry", {})
            assert not is_err, tel
            tcounts = tel["telemetry"]
            assert tcounts["key_level_reads_skipped"] >= 1 and tcounts["child_worlds_landed"] == 1, tel
            assert any(
                lnk["child_world_id"] == "w-m10-child"
                and (lnk.get("merged_into_parent?") or lnk.get("merged_into_parent"))
                for lnk in tel["links"]
            ), tel

            is_err, ver2 = call_tool(proc, 122, "modb_verify", {})
            assert not is_err and ver2["ok"] is True, (is_err, ver2)

            # Milestone 12: Sensitivity clearances, Governance proposals + CapabilityDiff, and Reactive Feeds via MCP!
            is_err, pol0 = call_tool(proc, 123, "modb_policy_get", {})
            assert not is_err and any(c["grant_id"] == "g-sre" for c in pol0["clearances"]), (is_err, pol0)

            is_err, sub_gp = call_tool(
                proc,
                124,
                "modb_proposal_submit",
                {
                    "id": "mcp-view-triage",
                    "kind": "view",
                    "proposer_grant_id": "g-sre",
                    "description": "Operational triage view via MCP",
                    "view_name": "tasks_triage",
                    "base_view": "tasks_finance",
                    "fields": ["id", "project_id", "title", "status"],
                    "reason": "propose tasks_triage",
                },
            )
            assert not is_err and sub_gp["diff"]["narrows_only"] and sub_gp["diff"]["risk_level"] == "low", (
                is_err,
                sub_gp,
            )

            is_err, app_gp = call_tool(
                proc,
                125,
                "modb_proposal_approve",
                {"proposal_id": "mcp-view-triage", "note": "lgtm via mcp"},
            )
            assert not is_err and app_gp["status"] == "approved", (is_err, app_gp)

            is_err, dyn_q = call_tool(
                proc,
                126,
                "modb_read_program",
                {
                    "program": {
                        "view": "tasks_triage",
                        "where_clause": {"eq": {"field": "project_id", "value": "infra"}},
                        "limit": 10,
                    }
                },
            )
            assert not is_err and dyn_q["result_count"] >= 4, (is_err, dyn_q)

            is_err, sub_f = call_tool(
                proc,
                127,
                "modb_feed_subscribe",
                {
                    "id": "mcp-tasks-feed",
                    "grant_id": "g-sre",
                    "buckets": ["tasks"],
                    "reason": "mcp reactive feed",
                },
            )
            assert not is_err and sub_f["id"] == "mcp-tasks-feed", (is_err, sub_f)

            is_err, t_new = call_tool(
                proc,
                128,
                "modb_create_task",
                {
                    "id": 912,
                    "project_id": "infra",
                    "title": "M12 reactive feed task",
                    "base_cost_cents": 1500,
                    "reason": "trigger mcp feed",
                },
            )
            assert not is_err and t_new["id"] == 912, (is_err, t_new)

            is_err, p_batch = call_tool(
                proc, 129, "modb_feed_poll", {"feed_id": "mcp-tasks-feed", "limit": 20}
            )
            assert not is_err and len(p_batch["events"]) == 1, (is_err, p_batch)

            is_err, c_out = call_tool(
                proc, 130, "modb_feed_consume", {"feed_id": "mcp-tasks-feed", "limit": 20}
            )
            assert not is_err and c_out["subscription"]["events_delivered"] == 1, (is_err, c_out)

            is_err, idle_b = call_tool(
                proc, 131, "modb_feed_poll", {"feed_id": "mcp-tasks-feed", "limit": 20}
            )
            assert not is_err and len(idle_b["events"]) == 0 and idle_b["pages_read"] == 0, (is_err, idle_b)

            is_err, unsub = call_tool(
                proc,
                132,
                "modb_feed_unsubscribe",
                {"feed_id": "mcp-tasks-feed", "reason": "done mcp feed"},
            )
            assert not is_err and unsub["ok"] is True, (is_err, unsub)

            # 3c. Milestone 13 MCP tools: session taint tracking, admin clear, erasure receipts
            is_err, t_mark = call_tool(
                proc,
                134,
                "modb_taint_record_untrusted",
                {
                    "session_id": "mcp-sess-1",
                    "source": "web:ticket-77",
                    "principal": "agent:mcp",
                },
            )
            assert not is_err and t_mark["untrusted_tainted"] is True, (is_err, t_mark)

            is_err, t_list = call_tool(proc, 135, "modb_taint_sessions", {})
            assert not is_err and any(s["id"] == "mcp-sess-1" for s in t_list), (is_err, t_list)

            is_err, t_clr = call_tool(
                proc,
                136,
                "modb_taint_clear",
                {"session_id": "mcp-sess-1", "reason": "mcp e2e clear"},
            )
            assert not is_err and t_clr["untrusted_tainted"] is False, (is_err, t_clr)

            is_err, er_list = call_tool(proc, 137, "modb_erasure_receipts", {})
            assert not is_err and isinstance(er_list, list), (is_err, er_list)

            # Milestone 15: ViewIndex query planner explain + incremental CoW MatViews via MCP
            is_err, exp_res = call_tool(
                proc,
                138,
                "modb_explain_view",
                {
                    "program": {
                        "view": "tasks_public",
                        "where_clause": {"eq": {"field": "project_id", "value": "infra"}},
                    },
                },
            )
            assert not is_err and exp_res["strategy"] == "index_eq" and exp_res["field"] == "project_id", (
                is_err,
                exp_res,
            )

            is_err, mvs = call_tool(proc, 139, "modb_matviews_list", {})
            mv_names = {m["def"]["name"] for m in mvs}
            assert not is_err and {"tasks_by_status", "tasks_by_project"} <= mv_names, (is_err, mvs)

            is_err, mv_ref = call_tool(proc, 140, "modb_matview_refresh", {"name": "tasks_by_status"})
            assert not is_err and mv_ref["name"] == "tasks_by_status", (is_err, mv_ref)

            is_err, mv_q = call_tool(proc, 141, "modb_matview_query", {"name": "tasks_by_project"})
            assert not is_err and mv_q["returned_groups"] >= 2, (is_err, mv_q)

            # Milestone 16: Incremental Sync replication lifecycle via MCP
            is_err, sy_i = call_tool(
                proc, 142, "modb_sync_init_peer", {"peer_id": "mcp-mirror"}
            )
            assert not is_err and sy_i["peer_id"] == "mcp-mirror", (is_err, sy_i)

            is_err, sy_l = call_tool(proc, 143, "modb_sync_peers", {})
            assert not is_err and any(p["peer_id"] == "mcp-mirror" for p in sy_l), (is_err, sy_l)

            is_err, sy_e = call_tool(
                proc, 144, "modb_sync_export", {"peer_id": "mcp-mirror"}
            )
            assert not is_err and sy_e["seq"] == 1 and sy_e["delta_hash"], (is_err, sy_e)

            is_err, sy_a = call_tool(
                proc,
                145,
                "modb_sync_ack",
                {"peer_id": "mcp-mirror", "seq": 1, "delta_hash": sy_e["delta_hash"]},
            )
            assert not is_err and sy_a["acked_seq"] == 1, (is_err, sy_a)

            is_err, sy_rm = call_tool(
                proc, 146, "modb_sync_remove_peer", {"peer_id": "mcp-mirror"}
            )
            assert not is_err and sy_rm["ok"] is True, (is_err, sy_rm)

            is_err, ver3 = call_tool(proc, 133, "modb_verify", {})
            assert not is_err and ver3["ok"] is True, (is_err, ver3)

            # 4. Extract live Inspector UI URL from stderr and verify UI + inspector HTTP routes!
            base_url = None
            for line in stderr_lines:
                m = re.search(r"Inspector UI: (http://127\.0\.0\.1:\d+)/", line)
                if m:
                    base_url = m.group(1)
                    break
            assert base_url is not None, stderr_lines

            st_ui, html = http_get(f"{base_url}/")
            assert st_ui == 200 and "MoDB AgentWorkbench" in html and "Replay Studio" in html
            assert "scan_tasks_range" in html and "Fork Child World" in html
            assert "Search (FTS / Hybrid)" in html and "/search/stats" in html
            assert "Governance &amp; Feeds" in html and "/policy" in html
            assert "Session Taint Monitor" in html and "/taint/sessions" in html and "/erasures" in html
            assert "/events/stream" in html and "feed-stream" in html
            st_ui2, html2 = http_get(f"{base_url}/ui")
            assert st_ui2 == 200 and html2 == html

            for ep in (
                "/projects",
                "/grants",
                "/claims",
                "/worlds",
                "/worlds/metrics",
                "/worlds/telemetry",
                "/reads",
                "/search/stats",
                "/policy",
                "/proposals",
                "/feeds",
                "/matviews",
                "/matviews/tasks_by_status/query",
                "/sync/peers",
                "/taint/sessions",
                "/erasures",
                "/audit",
                "/admin/replay/calls",
                "/admin/replay/proposals",
            ):
                st, body = http_get(f"{base_url}{ep}")
                assert st == 200, (ep, st)
                json.loads(body)

            print(
                f"PASS: Milestone 7+8+10+11+12 stdio MCP + Live Inspector UI verified "
                f"(tools={len(tools)}, ui={base_url}/, reads_skipped={landed['reads_skipped']}, "
                f"key_skips={tcounts['key_level_reads_skipped']}, child_landed={tcounts['child_worlds_landed']}, "
                f"infra_spent=20000c, payments_spent=8000c, "
                f"export_entries={snap['entry_count']}, txid={ver3['txid']}, hash={ver3['last_audit_hash'][:16]}...)"
            )
            return 0
        finally:
            if proc.stdin:
                proc.stdin.close()
            try:
                proc.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            err_thread.join(timeout=2.0)


if __name__ == "__main__":
    raise SystemExit(main())
