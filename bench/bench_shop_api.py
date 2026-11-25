#!/usr/bin/env python3
"""Multi-worker HTTP concurrency & latency benchmark for examples/shop-api.mo under `mo serve --workers 8`."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
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


def http_json(base: str, method: str, path: str, body=None, headers=None, timeout: float = 30.0):
    hdrs = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{base}{path}", data=data, headers=hdrs, method=method)
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            dt_ms = (time.perf_counter() - t0) * 1000.0
            return resp.status, json.loads(raw) if raw else None, dt_ms
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        dt_ms = (time.perf_counter() - t0) * 1000.0
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return e.code, parsed, dt_ms


def pct(samples: list[float], p: float) -> float:
    if not samples:
        return 0.0
    s = sorted(samples)
    idx = min(len(s) - 1, int(len(s) * p))
    return s[idx]


def main() -> int:
    mo_bin = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/code/mo/target/release/mo")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shop_api_mo = os.path.join(repo_root, "examples", "shop-api.mo")

    admin_hdr = {"Authorization": "Bearer b-admin", "X-Reason": "bench"}
    clerk_hdr = {"Authorization": "Bearer b-clerk", "X-Reason": "bench"}
    agent_hdr = {"Authorization": "Bearer b-agent", "X-Reason": "bench"}

    with tempfile.TemporaryDirectory(prefix="modb-http-bench-") as tmp:
        port = pick_free_port()
        base = f"http://127.0.0.1:{port}"
        env = os.environ.copy()
        env["SHOP_ADMIN_TOKEN"] = "b-admin"
        env["SHOP_CLERK_TOKEN"] = "b-clerk"
        env["SHOP_AGENT_TOKEN"] = "b-agent"
        log_file = open(os.path.join(tmp, "serve.log"), "w", encoding="utf-8")
        proc = subprocess.Popen(
            [
                mo_bin,
                "serve",
                "--workers",
                "8",
                "--bind",
                "127.0.0.1",
                "--port",
                str(port),
                "--data",
                tmp,
                shop_api_mo,
            ],
            stdout=log_file,
            stderr=log_file,
            text=True,
            env=env,
        )
        try:
            for _ in range(100):
                try:
                    st, _, _ = http_json(base, "GET", "/health")
                    if st == 200:
                        break
                except Exception:
                    time.sleep(0.05)

            assert http_json(base, "POST", "/admin/init", None, admin_hdr)[0] == 200
            assert (
                http_json(
                    base,
                    "POST",
                    "/customers",
                    {"id": 1, "email": "ada@bench.dev", "name": "Ada", "tier": "member"},
                    clerk_hdr,
                )[0]
                == 200
            )
            for i in range(10):
                assert (
                    http_json(
                        base,
                        "POST",
                        "/products",
                        {
                            "sku": f"sku-{i}",
                            "title": f"Roast #{i}",
                            "category": "beans",
                            "price": "15.00",
                            "stock": 500,
                        },
                        admin_hdr,
                    )[0]
                    == 200
                )

            # 1. Pure 8-thread read burst (400 requests across 8 workers)
            read_lats: list[float] = []
            read_errs = 0
            lock = threading.Lock()
            t_r0 = time.perf_counter()

            def read_worker(wid: int):
                nonlocal read_errs
                local_lats = []
                local_errs = 0
                for j in range(50):
                    sku = f"sku-{(wid + j) % 10}"
                    st, _, dt = http_json(base, "GET", f"/products/{sku}")
                    if st == 200:
                        local_lats.append(dt)
                    else:
                        local_errs += 1
                with lock:
                    read_lats.extend(local_lats)
                    read_errs += local_errs

            with ThreadPoolExecutor(max_workers=8) as pool:
                for f in [pool.submit(read_worker, w) for w in range(8)]:
                    f.result()
            t_read = time.perf_counter() - t_r0

            # 2. Mixed 80/20 concurrent workload: 6 readers + 2 writers (100 synced orders)
            mix_r_lats: list[float] = []
            mix_w_lats: list[float] = []
            mix_errs = 0
            stop_r = threading.Event()
            t_m0 = time.perf_counter()

            def mix_writer(wid: int):
                nonlocal mix_errs
                local_lats = []
                local_errs = 0
                for j in range(50):
                    oid = 1000 + wid * 100 + j
                    st, _, dt = http_json(
                        base,
                        "POST",
                        "/orders",
                        {"id": oid, "buyer_id": 1, "sku": f"sku-{j % 10}", "quantity": 1},
                        agent_hdr,
                    )
                    if st == 200:
                        local_lats.append(dt)
                    else:
                        local_errs += 1
                with lock:
                    mix_w_lats.extend(local_lats)
                    mix_errs += local_errs

            def mix_reader(wid: int):
                nonlocal mix_errs
                local_lats = []
                local_errs = 0
                step = 0
                while not stop_r.is_set():
                    path = f"/products/sku-{(wid + step) % 10}" if step % 2 == 0 else "/products?category=beans"
                    step += 1
                    st, _, dt = http_json(base, "GET", path)
                    if st == 200:
                        local_lats.append(dt)
                    else:
                        local_errs += 1
                with lock:
                    mix_r_lats.extend(local_lats)
                    mix_errs += local_errs

            with ThreadPoolExecutor(max_workers=8) as pool:
                rfuts = [pool.submit(mix_reader, r) for r in range(6)]
                wfuts = [pool.submit(mix_writer, w) for w in range(2)]
                for f in wfuts:
                    f.result()
                stop_r.set()
                for f in rfuts:
                    f.result()
            t_mix = time.perf_counter() - t_m0

            # 3. Offline replay simulation latency over 111 recorded calls
            st_sim, sim_body, sim_ms = http_json(
                base,
                "POST",
                "/admin/replay/simulate",
                {
                    "proposal_id": "bench-replay",
                    "description": "benchmark replay over 100+ calls",
                    "exclude_principal": None,
                    "exclude_grant": None,
                    "exclude_world": None,
                    "exclude_seqs": None,
                    "stop_before_seq": None,
                    "member_discount_override": "0.15",
                },
                admin_hdr,
            )
            assert st_sim == 200, (st_sim, sim_body)
            st_ver, ver_body, ver_ms = http_json(base, "GET", "/admin/verify")
            assert st_ver == 200 and ver_body["ok"] is True

            assert read_errs == 0 and mix_errs == 0, (read_errs, mix_errs)
            print("=== ShopApi 8-Worker HTTP Concurrency Benchmark ===")
            print(
                f"Pure 8-thread reads (400 reqs): {len(read_lats)/t_read:.1f} req/s | "
                f"p50={pct(read_lats, 0.5):.1f}ms p95={pct(read_lats, 0.95):.1f}ms"
            )
            print(
                f"Mixed 6R+2W ({len(mix_r_lats)} reads + {len(mix_w_lats)} synced orders in {t_mix:.2f}s): "
                f"total={(len(mix_r_lats)+len(mix_w_lats))/t_mix:.1f} req/s | "
                f"read p50={pct(mix_r_lats, 0.5):.1f}ms p95={pct(mix_r_lats, 0.95):.1f}ms | "
                f"write p50={pct(mix_w_lats, 0.5):.1f}ms p95={pct(mix_w_lats, 0.95):.1f}ms"
            )
            print(
                f"Replay simulate ({sim_body['summary']['total_calls']} calls, 15% override): {sim_ms:.1f}ms | "
                f"Full /admin/verify ({ver_body['audit_entries']} audit entries, {ver_body['page_count']} pages): {ver_ms:.1f}ms"
            )
            return 0
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            log_file.close()


if __name__ == "__main__":
    raise SystemExit(main())
