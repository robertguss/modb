#!/usr/bin/env python3
"""Live 8-worker concurrent HTTP + Multi-Agent Worlds/Grants/Claims + SIGKILL stress test for examples/shop-api.mo."""
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
    agent_hdr = {"Authorization": "Bearer live-agent", "X-Reason": "agent-work"}

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

            # Live OpenAPI 3.1 endpoint includes both base routes and Milestone 3 coordination routes
            st, spec = http_json(base1, "GET", "/openapi.json")
            paths = spec.get("paths", {})
            assert st == 200 and "/orders" in paths and "/worlds" in paths and "/grants" in paths and "/claims" in paths, (
                st,
                list(paths.keys()),
            )

            st, ver_pre = http_json(base1, "GET", "/admin/verify")
            assert st == 200 and ver_pre["ok"] is True and ver_pre["audit_entries"] == 4, (st, ver_pre)

            # 4. WAVE 1: 8-thread concurrent HTTP stress test against `mo serve --workers 8`
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
                        return

            def wave2_reader():
                while not stop_wave2.is_set():
                    try:
                        http_json(base1, "GET", "/products/stress-beans", timeout=5.0)
                    except Exception:
                        return

            pool2 = ThreadPoolExecutor(max_workers=8)
            _futs2 = [pool2.submit(wave2_writer, w) for w in range(4)] + [
                pool2.submit(wave2_reader) for _ in range(4)
            ]
            kill_ready.wait(timeout=10.0)
            proc1.send_signal(signal.SIGKILL)
            proc1.wait()
            stop_wave2.set()
            pool2.shutdown(wait=True)
        finally:
            if proc1.poll() is None:
                proc1.send_signal(signal.SIGKILL)
                proc1.wait()

        # 6. Restart fresh 8-worker server, verify Wave 2 recovery, and run WAVE 3 (Multi-Agent Worlds/Grants/Claims + SIGKILL)!
        port2 = pick_free_port()
        base2 = f"http://127.0.0.1:{port2}"
        proc2 = start_server(mo_bin, shop_api_mo, tmp, port2, workers=8)
        world_landed = 0
        world_stale = 0
        try:
            health2 = wait_ready(base2, proc2)
            assert health2["status"] == "ok" and health2["schema_version"] == 2, health2

            st, ver2 = http_json(base2, "GET", "/admin/verify")
            assert st == 200 and ver2["ok"] is True and ver2["invariants_checked"] == 3, (st, ver2)

            st, all_orders = http_json(base2, "GET", "/customers/1/orders")
            assert st == 200, (st, all_orders)
            persisted_ids = {o["id"] for o in all_orders}
            missing_acked = wave2_acked_orders - persisted_ids
            assert not missing_acked, f"lost acknowledged orders across SIGKILL: {missing_acked}"

            wave2_persisted = [o for o in all_orders if 2000 <= o["id"] < 3000]
            assert len(wave2_persisted) >= len(wave2_acked_orders)

            st, prod_rec = http_json(base2, "GET", "/products/stress-beans")
            assert st == 200 and prod_rec["stock"] + len(wave2_persisted) == 50, (
                prod_rec["stock"],
                len(wave2_persisted),
            )
            assert ver2["audit_entries"] == pre_wave2_audit_entries + len(wave2_persisted)

            # WAVE 3: Live 8-worker multi-agent Worlds, attenuated Grants, Claims & pinned-World SIGKILL survival
            st, _g_lead = http_json(
                base2,
                "POST",
                "/grants",
                {
                    "id": "g-lead",
                    "principal": "agent:lead",
                    "allowed_actions": ["place_order", "save_product"],
                    "max_calls": 50,
                    "ttl_seconds": 3600,
                },
                admin_hdr,
            )
            assert st == 200, (st, _g_lead)

            # Narrowed helper grant succeeds; widening attempt returns 403
            st, _g_bad = http_json(
                base2,
                "POST",
                "/grants/g-lead/delegate",
                {
                    "id": "g-wide",
                    "principal": "helper:bad",
                    "allowed_actions": ["place_order", "ship_order"],
                    "max_calls": 5,
                    "ttl_seconds": 1800,
                },
                agent_hdr,
            )
            assert st == 403, (st, _g_bad)

            st, _g_help = http_json(
                base2,
                "POST",
                "/grants/g-lead/delegate",
                {
                    "id": "g-helper",
                    "principal": "helper:sub",
                    "allowed_actions": ["place_order"],
                    "max_calls": 10,
                    "ttl_seconds": 1800,
                },
                agent_hdr,
            )
            assert st == 200, (st, _g_help)

            # Stale-price World rejected (409) when Admin reprices house-blend before landing
            st, _ = http_json(
                base2,
                "POST",
                "/worlds",
                {"id": "w-stale", "grant_id": "g-lead", "ttl_seconds": 600},
                agent_hdr,
            )
            assert st == 200
            st, q_p = http_json(
                base2,
                "POST",
                "/worlds/w-stale/query",
                {"query": "get_product", "args": "house-blend"},
                agent_hdr,
            )
            assert st == 200 and Decimal(q_p["price"]) == Decimal("16.00"), (st, q_p)
            st, _ = http_json(
                base2,
                "POST",
                "/worlds/w-stale/call",
                {
                    "action": "place_order",
                    "args": {"id": 4001, "buyer_id": 1, "sku": "house-blend", "quantity": 1},
                },
                agent_hdr,
            )
            assert st == 200
            st, _ = http_json(
                base2,
                "POST",
                "/products",
                {
                    "sku": "house-blend",
                    "title": "House Espresso Blend (250g)",
                    "category": "beans",
                    "price": "20.00",
                    "stock": 25,
                },
                admin_hdr,
            )
            assert st == 200
            st, stale_body = http_json(base2, "POST", "/worlds/w-stale/land", None, agent_hdr)
            assert st == 409, (st, stale_body)

            # Parent revocation mid-flight blocks helper's open World from landing (403)
            st, _ = http_json(
                base2,
                "POST",
                "/worlds",
                {"id": "w-rev", "grant_id": "g-helper", "ttl_seconds": 600},
                agent_hdr,
            )
            assert st == 200
            st, _ = http_json(
                base2,
                "POST",
                "/worlds/w-rev/call",
                {
                    "action": "place_order",
                    "args": {"id": 4002, "buyer_id": 1, "sku": "house-blend", "quantity": 1},
                },
                agent_hdr,
            )
            assert st == 200
            st, _ = http_json(base2, "POST", "/grants/g-lead/revoke", None, admin_hdr)
            assert st == 200
            st, rev_body = http_json(base2, "POST", "/worlds/w-rev/land", None, agent_hdr)
            assert st == 403, (st, rev_body)

            # Seed world-beans (stock=15), open persistent observer World `w-persist` pinning stock=15,
            # then race 4 agent World threads + 4 reader threads under `--workers 8`!
            st, _ = http_json(
                base2,
                "POST",
                "/grants",
                {
                    "id": "g-race",
                    "principal": "agent:racer",
                    "allowed_actions": ["place_order"],
                    "max_calls": 100,
                    "ttl_seconds": 3600,
                },
                admin_hdr,
            )
            assert st == 200
            st, _ = http_json(
                base2,
                "POST",
                "/products",
                {
                    "sku": "world-beans",
                    "title": "World Blend (250g)",
                    "category": "beans",
                    "price": "12.00",
                    "stock": 15,
                },
                admin_hdr,
            )
            assert st == 200
            st, _ = http_json(
                base2,
                "POST",
                "/worlds",
                {"id": "w-persist", "grant_id": "g-race", "ttl_seconds": 3600},
                agent_hdr,
            )
            assert st == 200

            w3_errors: list[str] = []
            w3_lock = threading.Lock()
            w3_stop_readers = threading.Event()
            w3_counts = {"landed": 0, "stale": 0, "reads": 0}

            def world_racer(idx: int):
                for j in range(5):
                    oid = 5000 + idx * 100 + j
                    for attempt in range(8):
                        wid = f"wr-{idx}-{j}-{attempt}"
                        st_o, b_o = http_json(
                            base2,
                            "POST",
                            "/worlds",
                            {"id": wid, "grant_id": "g-race", "ttl_seconds": 600},
                            agent_hdr,
                            timeout=30.0,
                        )
                        if st_o != 200:
                            with w3_lock:
                                w3_errors.append(f"open {wid}: {st_o} {b_o}")
                            return
                        st_q, b_q = http_json(
                            base2,
                            "POST",
                            f"/worlds/{wid}/query",
                            {"query": "get_product", "args": "world-beans"},
                            agent_hdr,
                            timeout=30.0,
                        )
                        if st_q != 200:
                            with w3_lock:
                                w3_errors.append(f"query {wid}: {st_q} {b_q}")
                            return
                        if b_q["stock"] < 1:
                            http_json(base2, "DELETE", f"/worlds/{wid}", None, agent_hdr, timeout=30.0)
                            return
                        st_c, b_c = http_json(
                            base2,
                            "POST",
                            f"/worlds/{wid}/call",
                            {
                                "action": "place_order",
                                "args": {"id": oid, "buyer_id": 1, "sku": "world-beans", "quantity": 1},
                            },
                            agent_hdr,
                            timeout=30.0,
                        )
                        if st_c != 200:
                            http_json(base2, "DELETE", f"/worlds/{wid}", None, agent_hdr, timeout=30.0)
                            return
                        st_l, b_l = http_json(
                            base2,
                            "POST",
                            f"/worlds/{wid}/land",
                            None,
                            agent_hdr,
                            timeout=30.0,
                        )
                        if st_l == 200:
                            with w3_lock:
                                w3_counts["landed"] += 1
                            break
                        elif st_l == 409:
                            with w3_lock:
                                w3_counts["stale"] += 1
                            continue
                        else:
                            with w3_lock:
                                w3_errors.append(f"land {wid}: {st_l} {b_l}")
                            return

            def world_reader(idx: int):
                routes = [
                    "/worlds/metrics",
                    "/worlds/w-persist/diff",
                    "/claims",
                    "/products/world-beans",
                    "/worlds/metrics",
                    "/products?category=beans",
                    "/claims",
                    "/admin/verify",
                ]
                step = 0
                while not w3_stop_readers.is_set():
                    path = routes[(idx + step) % len(routes)]
                    if path == "/admin/verify" and (idx != 0 or step % 16 != 0):
                        path = "/products/world-beans"
                    step += 1
                    st_r, b_r = http_json(base2, "GET", path, timeout=30.0)
                    with w3_lock:
                        if st_r == 200:
                            w3_counts["reads"] += 1
                        else:
                            w3_errors.append(f"GET {path}: {st_r} {b_r}")
                    time.sleep(0.005)

            with ThreadPoolExecutor(max_workers=8) as pool3:
                rfuts = [pool3.submit(world_reader, r) for r in range(4)]
                wfuts = [pool3.submit(world_racer, w) for w in range(4)]
                for f in wfuts:
                    f.result()
                w3_stop_readers.set()
                for f in rfuts:
                    f.result()

            assert not w3_errors, f"wave3 world errors: {w3_errors[:5]}"
            world_landed = w3_counts["landed"]
            world_stale = w3_counts["stale"]
            assert world_landed > 0 and world_landed <= 15, w3_counts
            st, wb_after = http_json(base2, "GET", "/products/world-beans")
            assert st == 200 and wb_after["stock"] + world_landed == 15, (wb_after, world_landed)

            # Hard SIGKILL while `w-persist` is STILL OPEN pinning world-beans at stock=15!
            proc2.send_signal(signal.SIGKILL)
            proc2.wait()
        finally:
            if proc2.poll() is None:
                proc2.send_signal(signal.SIGKILL)
                proc2.wait()

        # 7. Restart 3rd server and prove open World `w-persist` survived SIGKILL with frozen stock=15!
        port3 = pick_free_port()
        base3 = f"http://127.0.0.1:{port3}"
        proc3 = start_server(mo_bin, shop_api_mo, tmp, port3, workers=8)
        try:
            wait_ready(base3, proc3)
            st, ver3 = http_json(base3, "GET", "/admin/verify")
            assert st == 200 and ver3["ok"] is True, (st, ver3)

            # Open World `w-persist` STILL reads frozen stock=15 even after concurrent orders + SIGKILL!
            st, frozen = http_json(
                base3,
                "POST",
                "/worlds/w-persist/query",
                {"query": "get_product", "args": "world-beans"},
                agent_hdr,
            )
            assert st == 200 and frozen["stock"] == 15, (st, frozen)

            # Drop `w-persist` cleanly -> unpins base root -> final verify passes
            st, dropped = http_json(base3, "DELETE", "/worlds/w-persist", None, agent_hdr)
            assert st == 200 and dropped == {"ok": True}, (st, dropped)

            st, ver_pre4 = http_json(base3, "GET", "/admin/verify")
            assert st == 200 and ver_pre4["ok"] is True, (st, ver_pre4)

            st, met_final = http_json(base3, "GET", "/worlds/metrics")
            assert st == 200 and met_final["total_landed"] == world_landed, (st, met_final)

            # WAVE 4: Live Milestone 4 Replay (selective grant-subtree undo + NowAccepted +
            # bug-fix discount override) + Portable Export + 3rd SIGKILL recovery!
            st, _ = http_json(
                base3,
                "POST",
                "/products",
                {
                    "sku": "replay-beans",
                    "title": "Replay Reserve (250g)",
                    "category": "beans",
                    "price": "20.00",
                    "stock": 5,
                },
                admin_hdr,
            )
            assert st == 200

            st, _ = http_json(
                base3,
                "POST",
                "/grants",
                {
                    "id": "g-bad-root",
                    "principal": "agent:rogue-root",
                    "allowed_actions": ["place_order"],
                    "max_calls": 10,
                    "ttl_seconds": 3600,
                },
                admin_hdr,
            )
            assert st == 200
            st, _ = http_json(
                base3,
                "POST",
                "/grants/g-bad-root/delegate",
                {
                    "id": "g-bad-child",
                    "principal": "helper:rogue-child",
                    "allowed_actions": ["place_order"],
                    "max_calls": 5,
                    "ttl_seconds": 1800,
                },
                agent_hdr,
            )
            assert st == 200

            # Rogue delegated child drains all 5 replay-beans via speculative World
            st, _ = http_json(
                base3,
                "POST",
                "/worlds",
                {"id": "w-rogue-drain", "grant_id": "g-bad-child", "ttl_seconds": 600},
                agent_hdr,
            )
            assert st == 200
            st, _ = http_json(
                base3,
                "POST",
                "/worlds/w-rogue-drain/call",
                {
                    "action": "place_order",
                    "args": {"id": 6001, "buyer_id": 1, "sku": "replay-beans", "quantity": 5},
                },
                agent_hdr,
            )
            assert st == 200
            st, _ = http_json(base3, "POST", "/worlds/w-rogue-drain/land", None, agent_hdr)
            assert st == 200

            # Legitimate order #6002 for 2x replay-beans is REFUSED (409 InsufficientStock)
            st, _ = http_json(
                base3,
                "POST",
                "/orders",
                {"id": 6002, "buyer_id": 1, "sku": "replay-beans", "quantity": 2},
                clerk_hdr,
            )
            assert st == 409

            # Admin simulates removing g-bad-root (excises child g-bad-child) -> NowAccepted!
            st, prop1 = http_json(
                base3,
                "POST",
                "/admin/replay/simulate",
                {
                    "proposal_id": "wave4-undo",
                    "description": "Remove rogue subtree g-bad-root",
                    "exclude_principal": None,
                    "exclude_grant": "g-bad-root",
                    "exclude_world": None,
                    "exclude_seqs": None,
                    "stop_before_seq": None,
                    "member_discount_override": None,
                },
                admin_hdr,
                timeout=30.0,
            )
            assert st == 200, (st, prop1)
            assert prop1["summary"]["excluded"] == 1 and prop1["summary"]["now_accepted"] >= 1, prop1["summary"]

            # Live stock is untouched (0) until Admin explicitly accepts!
            st, rb_pre = http_json(base3, "GET", "/products/replay-beans")
            assert st == 200 and rb_pre["stock"] == 0, rb_pre

            # Admin accepts proposal -> stock restored to 3, order #6002 fulfilled ($36.00), #6001 gone!
            st, acc1 = http_json(
                base3,
                "POST",
                "/admin/replay/proposals/wave4-undo/accept",
                None,
                admin_hdr,
                timeout=30.0,
            )
            assert st == 200, (st, acc1)
            st, rb_after = http_json(base3, "GET", "/products/replay-beans")
            assert st == 200 and rb_after["stock"] == 3, rb_after

            st, cust_ords = http_json(base3, "GET", "/customers/1/orders")
            assert st == 200
            ords_by_id = {o["id"]: o for o in cust_ords}
            assert 6001 not in ords_by_id and 6002 in ords_by_id
            assert Decimal(ords_by_id[6002]["total"]) == Decimal("36.00"), ords_by_id[6002]

            # Bug-fix replay: apply 20% Member discount override while keeping g-bad-root excluded -> $32.00!
            st, prop2 = http_json(
                base3,
                "POST",
                "/admin/replay/simulate",
                {
                    "proposal_id": "wave4-discount-fix",
                    "description": "Retroactive 20% Member discount fix",
                    "exclude_principal": None,
                    "exclude_grant": "g-bad-root",
                    "exclude_world": None,
                    "exclude_seqs": None,
                    "stop_before_seq": None,
                    "member_discount_override": "0.20",
                },
                admin_hdr,
                timeout=30.0,
            )
            assert st == 200 and prop2["summary"]["reply_changed"] > 0, (st, prop2.get("summary"))
            st, acc2 = http_json(
                base3,
                "POST",
                "/admin/replay/proposals/wave4-discount-fix/accept",
                None,
                admin_hdr,
                timeout=30.0,
            )
            assert st == 200, (st, acc2)

            # Portable export check over ReadFiles
            st, exp_snap = http_json(base3, "GET", "/admin/export", timeout=30.0)
            assert st == 200 and exp_snap["format_version"] == 1 and len(exp_snap["sha256"]) == 64
            assert all(b["name"] != "_modb_pins" for b in exp_snap["buckets"])

            # 3rd hard SIGKILL after live replay proposals accepted!
            proc3.send_signal(signal.SIGKILL)
            proc3.wait()
        finally:
            if proc3.poll() is None:
                proc3.send_signal(signal.SIGKILL)
                proc3.wait()

        # 8. Restart 4th server and prove accepted replay state & full hash chain survived 3rd SIGKILL!
        port4 = pick_free_port()
        base4 = f"http://127.0.0.1:{port4}"
        proc4 = start_server(mo_bin, shop_api_mo, tmp, port4, workers=8)
        try:
            wait_ready(base4, proc4)
            st, ver_final = http_json(base4, "GET", "/admin/verify")
            assert st == 200 and ver_final["ok"] is True, (st, ver_final)

            st, rb_rec = http_json(base4, "GET", "/products/replay-beans")
            assert st == 200 and rb_rec["stock"] == 3, rb_rec
            st, cust_ords4 = http_json(base4, "GET", "/customers/1/orders")
            assert st == 200
            ords4_by_id = {o["id"]: o for o in cust_ords4}
            assert 6001 not in ords4_by_id and 6002 in ords4_by_id
            assert Decimal(ords4_by_id[6002]["total"]) == Decimal("32.00"), ords4_by_id[6002]

            print(
                f"PASS: live 8-worker HTTP + Worlds/Grants/Claims + Replay/Export + 3x SIGKILL verified "
                f"(wave1=40ok/20conflict/{reader_counts['ok']}reads, "
                f"wave2_acked={len(wave2_acked_orders)}/persisted={len(wave2_persisted)}, "
                f"wave3_worlds={world_landed}landed/{world_stale}stale_retries, "
                f"wave4_replay=undo_NowAccepted+20pct_fix+export_ok, "
                f"txid={ver_final['txid']}, audit_entries={ver_final['audit_entries']}, "
                f"hash={ver_final['last_audit_hash'][:16]}...)"
            )
            return 0
        finally:
            proc4.terminate()
            try:
                proc4.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc4.kill()
                proc4.wait()


if __name__ == "__main__":
    raise SystemExit(main())
