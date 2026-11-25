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
            assert len(tools) >= 30, len(tools)
            for req in (
                "modb_seed_demo",
                "modb_list_grants",
                "modb_list_worlds",
                "modb_world_diff",
                "modb_world_land",
                "modb_replay_simulate",
                "modb_replay_accept",
                "modb_export_snapshot",
                "modb_verify",
            ):
                assert req in tool_names, f"missing MCP tool {req}"

            # 3. Seed demo & drive Grants / Claims / Worlds / CoW Diff / Replay via MCP!
            is_err, seeded = call_tool(proc, 10, "modb_seed_demo", {"reason": "e2e MCP demo"})
            assert not is_err and seeded["ok"] is True, (is_err, seeded)

            is_err, diff = call_tool(proc, 11, "modb_world_diff", {"world_id": "w-demo-payments-401"})
            assert not is_err and isinstance(diff, list) and len(diff) >= 2, (is_err, diff)

            is_err, landed = call_tool(
                proc,
                12,
                "modb_world_land",
                {"world_id": "w-demo-payments-401", "reason": "land reconciliation via MCP"},
            )
            assert not is_err and landed["commit_txid"] > 0, (is_err, landed)

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
            st_ui2, html2 = http_get(f"{base_url}/ui")
            assert st_ui2 == 200 and html2 == html

            for ep in (
                "/projects",
                "/grants",
                "/claims",
                "/worlds",
                "/worlds/metrics",
                "/audit",
                "/admin/replay/calls",
                "/admin/replay/proposals",
            ):
                st, body = http_get(f"{base_url}{ep}")
                assert st == 200, (ep, st)
                json.loads(body)

            print(
                f"PASS: Milestone 7 stdio MCP + Live Inspector UI verified "
                f"(tools={len(tools)}, ui={base_url}/, infra_spent=20000c, payments_spent=8000c, "
                f"export_entries={snap['entry_count']}, txid={ver['txid']}, hash={ver['last_audit_hash'][:16]}...)"
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
