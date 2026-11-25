#!/usr/bin/env python3
"""Live 8-worker concurrent HTTP + SIGKILL durability stress test for examples/shop-api.mo under `mo serve --workers 8`."""
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def http_json(base: str, method: str, path: str, body=None, headers=None, timeout: float = 15.0):
    hdrs = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{base}{path}", data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return e.code, parsed


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


def start_server(mo_bin: str, shop_api_mo: str, root_dir: str, port: int, workers: int = 8) -> subprocess.Popen:
    env = os.environ.copy()
    env["SHOP_ADMIN_TOKEN"] = "live-admin"
    env["SHOP_CLERK_TOKEN"] = "live-clerk"
    env["SHOP_AGENT_TOKEN"] = "live-agent"
    return subprocess.Popen(
        [
            mo_bin,
            "serve",
            "--workers",
            str(workers),
            "--bind",
            "127.0.0.1",
            "--port",
            str(port),
            "--data",
            root_dir,
            shop_api_mo,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def main() -> int:
    mo_bin = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/code/mo/target/release/mo")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shop_api_mo = os.path.join(repo_root, "examples", "shop-api.mo")

    admin_hdr = {"Authorization": "Bearer live-admin", "X-Reason": "admin-setup"}
    clerk_hdr = {"Authorization": "Bearer live-clerk", "X-Reason": "live-signup"}
    agent_hdr = {"Authorization": "Bearer live-agent", "X-Reason": "agent-concurrent-order"}

    with tempfile.TemporaryDirectory(prefix="modb-shop-api-") as tmp:
        port1 = pick_free_port()
        base1 = f"http://127.0.0.1:{port1}"
        proc1 = start_server(mo_bin, shop_api_mo, tmp, port1, workers=8)
        wave2_acked_orders: set[int] = set()
        wave2_lock = threading.Lock()
        pre_wave2_audit_entries = 0

        try:
            # 1. Read-only GET /health before init reports uninitialized without mutating disk
            health0 = wait_ready(base1, proc1)
            assert health0 == {"status": "uninitialized", "txid": 0, "schema_version": 0, "audit_count": 0}, health0

            # 2. Admin bootstrap runs atomic v0 -> v1 -> v2 schema migration under exclusive lock
            st, init_res = http_json(base1, "POST", "/admin/init", None, admin_hdr)
            assert st == 200 and init_res == {
                "status": "ok",
                "txid": 2,
                "schema_version": 2,
                "audit_count": 2,
            }, (st, init_res)

            # 3. Create customer + reject invariant violation (422) + seed stress-test product (stock=40)
            st, cust = http_json(
                base1,
                "POST",
                "/customers",
                {"id": 1, "email": "ada@live.org", "name": "Ada", "tier": "member"},
                clerk_hdr,
            )
            assert st == 200 and cust["email"] == "ada@live.org", (st, cust)

            st, inv = http_json(
                base1,
                "POST",
                "/products",
                {"sku": "bad", "title": "Bad", "category": "beans", "price": "10.00", "stock": -1},
                admin_hdr,
            )
            assert st == 422, (st, inv)

            st, prod = http_json(
                base1,
                "POST",
                "/products",
                {
                    "sku": "stress-beans",
                    "title": "Concurrency Roast (250g)",
                    "category": "beans",
                    "price": "10.00",
                    "stock": 40,
                },
                admin_hdr,
            )
            assert st == 200 and prod["stock"] == 40, (st, prod)

            # Live OpenAPI 3.1 endpoint
            st, spec = http_json(base1, "GET", "/openapi.json")
            assert st == 200 and "/orders" in spec.get("paths", {}) and "/admin/init" in spec.get("paths", {}), (
                st,
                spec,
            )

            st, ver_pre = http_json(base1, "GET", "/admin/verify")
            assert st == 200 and ver_pre["ok"] is True and ver_pre["audit_entries"] == 4, (st, ver_pre)

            # 4. WAVE 1: 8-thread concurrent HTTP stress test against `mo serve --workers 8`
            #    4 writer threads submit 60 total 1-unit orders against stock=40 (expect exactly 40x 200 + 20x 409)
            #    4 reader threads continuously hammer GET /products, /customers/1/orders, /audit, /admin/verify
            stop_readers = threading.Event()
            writer_statuses: list[int] = []
            writer_order_ids: list[int] = []
            reader_counts = {"ok": 0, "errors": 0}
            reader_errors: list[str] = []
            stats_lock = threading.Lock()

            def run_writer(worker_idx: int):
                for j in range(15):
                    oid = 1000 + worker_idx * 100 + j
                    st_w, body_w = http_json(
                        base1,
                        "POST",
                        "/orders",
                        {"id": oid, "buyer_id": 1, "sku": "stress-beans", "quantity": 1},
                        {
                            "Authorization": "Bearer live-agent",
                            "X-Reason": f"wave1-w{worker_idx}-{j}",
                        },
                    )
                    with stats_lock:
                        writer_statuses.append(st_w)
                        if st_w == 200:
                            assert Decimal(body_w["total"]) == Decimal("9.00"), body_w
                            writer_order_ids.append(oid)
                        elif st_w != 409:
                            reader_errors.append(f"unexpected writer status {st_w}: {body_w}")

            def run_reader(reader_idx: int):
                routes = [
                    "/products/stress-beans",
                    "/products?category=beans",
                    "/customers/1/orders",
                    "/audit?limit=15",
                    "/admin/verify",
                ]
                step = 0
                while not stop_readers.is_set():
                    path = routes[(reader_idx + step) % len(routes)]
                    step += 1
                    st_r, body_r = http_json(base1, "GET", path)
                    with stats_lock:
                        if st_r == 200:
                            reader_counts["ok"] += 1
                            if path == "/admin/verify" and not body_r.get("ok"):
                                reader_errors.append(f"/admin/verify returned not ok: {body_r}")
                        else:
                            reader_counts["errors"] += 1
                            reader_errors.append(f"GET {path} -> {st_r}: {body_r}")

            with ThreadPoolExecutor(max_workers=8) as pool:
                reader_futs = [pool.submit(run_reader, r) for r in range(4)]
                writer_futs = [pool.submit(run_writer, w) for w in range(4)]
                for f in writer_futs:
                    f.result()
                stop_readers.set()
                for f in reader_futs:
                    f.result()

            assert not reader_errors, f"concurrent errors: {reader_errors[:5]}"
            assert reader_counts["errors"] == 0 and reader_counts["ok"] > 0, reader_counts
            ok_writes = sum(1 for s in writer_statuses if s == 200)
            conflict_writes = sum(1 for s in writer_statuses if s == 409)
            assert ok_writes == 40 and conflict_writes == 20 and len(writer_order_ids) == 40, (
                ok_writes,
                conflict_writes,
                writer_statuses,
            )

            # Verify exact stock conservation (40 -> 0), exact order count, and intact hash chain
            st, prod_after = http_json(base1, "GET", "/products/stress-beans")
            assert st == 200 and prod_after["stock"] == 0, (st, prod_after)

            st, orders_after = http_json(base1, "GET", "/customers/1/orders")
            assert st == 200 and len(orders_after) == 40, (st, len(orders_after))
            assert {o["id"] for o in orders_after} == set(writer_order_ids)

            st, ver_wave1 = http_json(base1, "GET", "/admin/verify")
            assert st == 200 and ver_wave1["ok"] is True and ver_wave1["audit_entries"] == 44, (
                st,
                ver_wave1,
            )

            # 5. WAVE 2: Restock to 50, launch 8 concurrent threads, and fire hard SIGKILL mid-flight!
            st, restock = http_json(
                base1,
                "POST",
                "/products",
                {
                    "sku": "stress-beans",
                    "title": "Concurrency Roast (250g)",
                    "category": "beans",
                    "price": "10.00",
                    "stock": 50,
                },
                admin_hdr,
            )
            assert st == 200 and restock["stock"] == 50, (st, restock)
            pre_wave2_audit_entries = 45

            kill_ready = threading.Event()
            stop_wave2 = threading.Event()

            def wave2_writer(worker_idx: int):
                for j in range(10):
                    if stop_wave2.is_set():
                        return
                    oid = 2000 + worker_idx * 100 + j
                    try:
                        st_w, _body_w = http_json(
                            base1,
                            "POST",
                            "/orders",
                            {"id": oid, "buyer_id": 1, "sku": "stress-beans", "quantity": 1},
                            {
                                "Authorization": "Bearer live-agent",
                                "X-Reason": f"wave2-w{worker_idx}-{j}",
                            },
                            timeout=5.0,
                        )
                        if st_w == 200:
                            with wave2_lock:
                                wave2_acked_orders.add(oid)
                                if len(wave2_acked_orders) >= 8:
                                    kill_ready.set()
                    except Exception:
                        # Expected once SIGKILL tears down the server socket mid-request
                        return

            def wave2_reader():
                while not stop_wave2.is_set():
                    try:
                        http_json(base1, "GET", "/products/stress-beans", timeout=5.0)
                    except Exception:
                        return

            pool2 = ThreadPoolExecutor(max_workers=8)
            futs2 = [pool2.submit(wave2_writer, w) for w in range(4)] + [
                pool2.submit(wave2_reader) for _ in range(4)
            ]
            # Wait until several concurrent writes have been acknowledged, then hard-SIGKILL mid-wave
            kill_ready.wait(timeout=10.0)
            proc1.send_signal(signal.SIGKILL)
            proc1.wait()
            stop_wave2.set()
            pool2.shutdown(wait=True)
        finally:
            if proc1.poll() is None:
                proc1.send_signal(signal.SIGKILL)
                proc1.wait()

        # 6. Restart fresh 8-worker server on the same data directory and verify crash durability
        port2 = pick_free_port()
        base2 = f"http://127.0.0.1:{port2}"
        proc2 = start_server(mo_bin, shop_api_mo, tmp, port2, workers=8)
        try:
            health2 = wait_ready(base2, proc2)
            assert health2["status"] == "ok" and health2["schema_version"] == 2, health2

            st, ver2 = http_json(base2, "GET", "/admin/verify")
            assert st == 200 and ver2["ok"] is True and ver2["invariants_checked"] == 3, (st, ver2)

            st, all_orders = http_json(base2, "GET", "/customers/1/orders")
            assert st == 200, (st, all_orders)
            persisted_ids = {o["id"] for o in all_orders}

            # Every Wave 1 order (40) AND every acknowledged Wave 2 order MUST survive SIGKILL
            missing_acked = wave2_acked_orders - persisted_ids
            assert not missing_acked, f"lost acknowledged orders across SIGKILL: {missing_acked}"

            wave2_persisted = [o for o in all_orders if o["id"] >= 2000]
            assert len(wave2_persisted) >= len(wave2_acked_orders), (
                len(wave2_persisted),
                len(wave2_acked_orders),
            )

            # Exact stock conservation after SIGKILL: remaining stock + wave2 persisted orders == 50
            st, prod_rec = http_json(base2, "GET", "/products/stress-beans")
            assert st == 200, (st, prod_rec)
            assert prod_rec["stock"] + len(wave2_persisted) == 50, (
                prod_rec["stock"],
                len(wave2_persisted),
            )

            # Exact audit-log parity after SIGKILL
            expected_audit = pre_wave2_audit_entries + len(wave2_persisted)
            assert ver2["audit_entries"] == expected_audit, (ver2["audit_entries"], expected_audit)

            print(
                f"PASS: live 8-worker concurrent HTTP + SIGKILL recovery verified "
                f"(wave1=40ok/20conflict/{reader_counts['ok']}reads, "
                f"wave2_acked={len(wave2_acked_orders)}/persisted={len(wave2_persisted)}, "
                f"txid={ver2['txid']}, audit_entries={ver2['audit_entries']}, "
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
