#!/usr/bin/env python3
"""Zero-dependency stdio MCP server bridging AI agents to MoDB's `AgentWorkbench`.

Speaks newline-delimited JSON-RPC 2.0 on stdin/stdout (strictly routing all diagnostics to
stderr) and forwards every MCP request to `AgentWorkbench`'s native `POST /mcp` endpoint.

Usage:
  # Auto-spawn a local 8-worker `AgentWorkbench` + live web inspector against a data folder:
  python3 tools/modb_mcp_server.py --data ./workbench-data

  # Or attach to an already-running `AgentWorkbench` server:
  python3 tools/modb_mcp_server.py --url http://127.0.0.1:8092

  # Print ready-to-paste MCP host configuration:
  python3 tools/modb_mcp_server.py --print-config --data ./workbench-data
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request


def log(msg: str) -> None:
    sys.stderr.write(f"[modb-mcp] {msg}\n")
    sys.stderr.flush()


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def find_mo_binary(explicit: str | None) -> str:
    if explicit:
        return explicit
    on_path = shutil.which("mo")
    if on_path:
        return on_path
    fallback = os.path.expanduser("~/code/mo/target/release/mo")
    if os.path.isfile(fallback) and os.access(fallback, os.X_OK):
        return fallback
    raise RuntimeError("could not locate `mo` binary; pass --mo /path/to/mo")


def wait_for_health(base_url: str, proc: subprocess.Popen[str] | None, timeout_s: float = 15.0) -> None:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if proc is not None and proc.poll() is not None:
            raise RuntimeError(f"AgentWorkbench exited early with status {proc.returncode}")
        try:
            req = urllib.request.Request(f"{base_url}/health", method="GET")
            with urllib.request.urlopen(req, timeout=2.0) as resp:
                if resp.status == 200:
                    return
        except Exception:
            time.sleep(0.05)
    raise RuntimeError(f"timed out waiting for AgentWorkbench at {base_url}/health")


def forward_mcp(
    base_url: str,
    payload: dict,
    token: str,
    agent_id: str | None,
    default_reason: str | None,
    timeout_s: float = 60.0,
) -> tuple[int, dict | None]:
    raw = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
    }
    if agent_id:
        headers["X-Agent-Id"] = agent_id
    if default_reason:
        headers["X-Reason"] = default_reason
    req = urllib.request.Request(f"{base_url}/mcp", data=raw, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read().decode("utf-8").strip()
            if not body:
                return resp.status, None
            return resp.status, json.loads(body)
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", errors="replace").strip()
        try:
            parsed = json.loads(body) if body else None
        except json.JSONDecodeError:
            parsed = {"raw": body}
        return err.code, parsed


def rpc_error(req_id, code: int, message: str) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": code, "message": message},
    }


def write_rpc(msg: dict) -> None:
    sys.stdout.write(json.dumps(msg, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    default_wb = os.path.join(repo_root, "examples", "agent-workbench.mo")

    parser = argparse.ArgumentParser(description="Stdio MCP bridge for MoDB AgentWorkbench")
    parser.add_argument("--url", help="Connect to an already-running AgentWorkbench HTTP URL")
    parser.add_argument(
        "--data",
        default=os.path.join(repo_root, ".modb-workbench-data"),
        help="Data directory for auto-spawned AgentWorkbench (ignored with --url)",
    )
    parser.add_argument("--port", type=int, default=0, help="Port for auto-spawned server (0 = auto)")
    parser.add_argument("--workers", type=int, default=8, help="Worker threads for `mo serve`")
    parser.add_argument("--mo", dest="mo_bin", help="Path to `mo` binary")
    parser.add_argument("--workbench", default=default_wb, help="Path to agent-workbench.mo")
    parser.add_argument(
        "--token",
        default=os.environ.get("WB_TOKEN") or os.environ.get("WB_ADMIN_TOKEN") or "wb-admin",
        help="Bearer token (defaults to WB_TOKEN / WB_ADMIN_TOKEN / wb-admin)",
    )
    parser.add_argument("--agent-id", default=os.environ.get("WB_AGENT_ID"), help="Optional X-Agent-Id")
    parser.add_argument(
        "--default-reason",
        default=os.environ.get("WB_REASON"),
        help="Fallback X-Reason header when a tool call omits `reason`",
    )
    parser.add_argument(
        "--print-config",
        action="store_true",
        help="Print a ready-to-paste MCP server JSON config snippet and exit",
    )
    args = parser.parse_args()

    if args.print_config:
        cfg = {
            "mcpServers": {
                "modb-workbench": {
                    "command": "python3",
                    "args": [
                        os.path.abspath(__file__),
                        "--data",
                        os.path.abspath(args.data),
                    ],
                    "env": {
                        "WB_TOKEN": args.token,
                    },
                }
            }
        }
        print(json.dumps(cfg, indent=2))
        return 0

    proc: subprocess.Popen[str] | None = None
    log_fh = None
    try:
        if args.url:
            base_url = args.url.rstrip("/")
            wait_for_health(base_url, None)
            log(f"connected to existing AgentWorkbench at {base_url} (Inspector UI: {base_url}/)")
        else:
            mo_bin = find_mo_binary(args.mo_bin)
            os.makedirs(args.data, exist_ok=True)
            port = args.port if args.port > 0 else pick_free_port()
            base_url = f"http://127.0.0.1:{port}"
            env = os.environ.copy()
            env.setdefault("WB_ADMIN_TOKEN", "wb-admin")
            env.setdefault("WB_PLANNER_TOKEN", "wb-planner")
            env.setdefault("WB_WORKER_TOKEN", "wb-worker")
            log_path = os.path.join(args.data, f"workbench-serve-{port}.log")
            log_fh = open(log_path, "a", encoding="utf-8")
            proc = subprocess.Popen(
                [
                    mo_bin,
                    "serve",
                    "--workers",
                    str(args.workers),
                    "--bind",
                    "127.0.0.1",
                    "--port",
                    str(port),
                    "--data",
                    args.data,
                    args.workbench,
                ],
                stdout=log_fh,
                stderr=log_fh,
                text=True,
                env=env,
            )
            wait_for_health(base_url, proc)
            log(
                f"spawned AgentWorkbench ({args.workers} workers) on {base_url} "
                f"(Inspector UI: {base_url}/ | server log: {log_path})"
            )

        for raw_line in sys.stdin:
            line = raw_line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError as exc:
                write_rpc(rpc_error(None, -32700, f"parse error: {exc}"))
                continue

            if not isinstance(msg, dict):
                write_rpc(rpc_error(None, -32600, "JSON-RPC message must be an object"))
                continue

            req_id = msg.get("id")
            is_notification = "id" not in msg or msg.get("method", "").startswith("notifications/")

            try:
                status, resp_obj = forward_mcp(
                    base_url, msg, args.token, args.agent_id, args.default_reason
                )
            except Exception as exc:
                if not is_notification:
                    write_rpc(rpc_error(req_id, -32603, f"bridge transport error: {exc}"))
                continue

            if is_notification:
                continue

            if status == 200 and isinstance(resp_obj, dict) and "jsonrpc" in resp_obj:
                write_rpc(resp_obj)
            elif status == 401:
                write_rpc(rpc_error(req_id, -32001, "unauthenticated: check WB_TOKEN / --token"))
            else:
                write_rpc(rpc_error(req_id, -32603, f"upstream HTTP {status}: {resp_obj}"))
        return 0
    finally:
        if proc is not None and proc.poll() is None:
            proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        if log_fh is not None:
            log_fh.close()


if __name__ == "__main__":
    raise SystemExit(main())
