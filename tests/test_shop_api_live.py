#!/usr/bin/env python3
"""Live HTTP + SIGKILL durability integration test for examples/shop-api.mo under `mo serve`."""
from decimal import Decimal
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def http_json(base: str, method: str, path: str, body=None, headers=None):
    hdrs = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{base}{path}", data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        return e.code, json.loads(raw) if raw else None


def wait_ready(base: str, proc: subprocess.Popen, timeout: float = 15.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            raise RuntimeError(f"mo serve exited early ({proc.returncode}):\nstdout: {out}\nstderr: {err}")
        try:
            st, data = http_json(base, "GET", "/health")
            if st == 200:
                return data
        except Exception:
            time.sleep(0.1)
    raise RuntimeError("timed out waiting for mo serve /health")


def start_server(mo_bin: str, shop_api_mo: str, root_dir: str, port: int) -> subprocess.Popen:
    env = os.environ.copy()
    env["SHOP_ADMIN_TOKEN"] = "live-admin"
    env["SHOP_CLERK_TOKEN"] = "live-clerk"
    env["SHOP_AGENT_TOKEN"] = "live-agent"
    return subprocess.Popen(
        [mo_bin, "serve", "--workers", "1", "--bind", "127.0.0.1", "--port", str(port), "--data", root_dir, shop_api_mo],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def main() -> int:
    mo_bin = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/code/mo/target/release/mo")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shop_api_mo = os.path.join(repo_root, "examples", "shop-api.mo")

    with tempfile.TemporaryDirectory(prefix="modb-shop-api-") as tmp:
        port1 = pick_free_port()
        base1 = f"http://127.0.0.1:{port1}"
        proc1 = start_server(mo_bin, shop_api_mo, tmp, port1)
        try:
            health = wait_ready(base1, proc1)
            assert health == {"status": "ok", "txid": 2, "schema_version": 2, "audit_count": 2}, health

            # Create customer
            st, cust = http_json(
                base1,
                "POST",
                "/customers",
                {"id": 1, "email": "ada@live.org", "name": "Ada", "tier": "member"},
                {"Authorization": "Bearer live-clerk", "X-Reason": "live-signup"},
            )
            assert st == 200 and cust["email"] == "ada@live.org", (st, cust)

            # Reject invariant violation (negative stock -> 422)
            st, inv = http_json(
                base1,
                "POST",
                "/products",
                {"sku": "bad", "title": "Bad", "category": "beans", "price": "10.00", "stock": -1},
                {"Authorization": "Bearer live-admin", "X-Reason": "bad-write"},
            )
            assert st == 422, (st, inv)

            # Agent places order (3 * 16.00 * 0.90 = 43.20)
            st, order = http_json(
                base1,
                "POST",
                "/orders",
                {"id": 501, "buyer_id": 1, "sku": "house-blend", "quantity": 3},
                {"Authorization": "Bearer live-agent", "X-Reason": "agent-live-order"},
            )
            assert st == 200 and Decimal(order["total"]) == Decimal("43.20"), (st, order)

            # Live OpenAPI 3.1 endpoint works out of the box
            st, spec = http_json(base1, "GET", "/openapi.json")
            assert st == 200 and "/orders" in spec.get("paths", {}), (st, spec)

            # Verify before SIGKILL
            st, ver1 = http_json(base1, "GET", "/admin/verify")
            assert st == 200 and ver1["ok"] is True and ver1["audit_entries"] == 4, (st, ver1)
        finally:
            # Hard SIGKILL mid-life to test crash durability
            proc1.send_signal(signal.SIGKILL)
            proc1.wait()

        # Restart fresh server on the same data directory and verify full durability + hash chain
        port2 = pick_free_port()
        base2 = f"http://127.0.0.1:{port2}"
        proc2 = start_server(mo_bin, shop_api_mo, tmp, port2)
        try:
            health2 = wait_ready(base2, proc2)
            assert health2["schema_version"] == 2 and health2["audit_count"] == 4, health2

            st, orders = http_json(base2, "GET", "/customers/1/orders")
            assert st == 200 and len(orders) == 1 and orders[0]["id"] == 501, (st, orders)

            st, audit = http_json(base2, "GET", "/audit?principal=agent:order-bot")
            assert st == 200 and len(audit) == 1 and audit[0]["reason"] == "agent-live-order", (st, audit)

            st, ver2 = http_json(base2, "GET", "/admin/verify")
            assert st == 200 and ver2["ok"] is True and ver2["audit_entries"] == 4, (st, ver2)
            assert ver2["last_audit_hash"] == ver1["last_audit_hash"], (ver1, ver2)

            print(
                f"PASS: live mo serve HTTP + SIGKILL recovery verified "
                f"(txid={ver2['txid']}, audit_entries={ver2['audit_entries']}, "
                f"hash={ver2['last_audit_hash'][:16]}...)"
            )
            return 0
        finally:
            proc2.terminate()
            try:
                proc2.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc2.kill()
                proc2.wait()


if __name__ == "__main__":
    raise SystemExit(main())
