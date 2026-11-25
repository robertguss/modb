#!/usr/bin/env python3
"""Milestone 6: Real-World Multi-Agent Simulation against AgentWorkbench (`mo serve --workers 8`).

Measures and verifies:
  Phase 1A — Coarse-query (`list_project_tasks`) uncoordinated 6-agent World swarm -> measures real needless send-backs!
  Phase 1B — Fine-query (`get_task` + `get_project`) + Claims coordinated 6-agent World swarm -> compares send-back rate!
  Phase 2  — Rogue delegated sub-agent incident -> cascading parent revocation (403) + offline selective-undo Replay
             (`exclude_grant`) unblocking refused SRE tasks (`NowAccepted`) + proposal review & atomic acceptance.
  Phase 3  — Retroactive billing-overhead bug-fix Replay (10% -> 0%) + SHA-256 Portable Export + hard OS SIGKILL survival.
"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
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
            return resp.status, (json.loads(raw) if raw else None), (time.perf_counter() - t0) * 1000.0
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return e.code, parsed, (time.perf_counter() - t0) * 1000.0


def start_server(mo_bin: str, wb_mo: str, root_dir: str, port: int, workers: int = 8) -> subprocess.Popen:
    env = os.environ.copy()
    env["WB_ADMIN_TOKEN"] = "sim-admin"
    env["WB_PLANNER_TOKEN"] = "sim-planner"
    env["WB_WORKER_TOKEN"] = "sim-worker"
    log_fh = open(os.path.join(root_dir, f"wb-{port}.log"), "w", encoding="utf-8")
    proc = subprocess.Popen(
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
            wb_mo,
        ],
        stdout=log_fh,
        stderr=log_fh,
        text=True,
        env=env,
    )
    log_fh.close()
    return proc


def wait_ready(base: str, proc: subprocess.Popen):
    deadline = time.monotonic() + 15.0
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"AgentWorkbench exited early ({proc.returncode})")
        try:
            st, data, _ = http_json(base, "GET", "/health")
            if st == 200:
                return data
        except Exception:
            time.sleep(0.05)
    raise RuntimeError("timed out waiting for AgentWorkbench /health")


def pct(samples: list[float], p: float) -> float:
    if not samples:
        return 0.0
    s = sorted(samples)
    return s[min(len(s) - 1, int(len(s) * p))]


def run_swarm_experiment(base: str, mode: str, project_id: str, task_ids: list[int], grant_prefix: str, admin_hdr: dict):
    """Runs 6 concurrent worker agents + 2 dashboard readers on disjoint tasks in one project.

    mode == 'coarse': each agent calls `list_project_tasks(project_id)` before completing its own task.
      Because other agents complete DIFFERENT tasks in the same project, `list_project_tasks` changes ->
      agent gets sent back with StaleRead, retries the IDENTICAL task completion -> triggers `needless_send_backs`!
    mode == 'fine': each agent acquires a Claim on `task:<id>`, reads ONLY `get_task(id)` (independent of
      sibling tasks!), completes its task, lands cleanly, and releases the Claim -> ZERO needless send-backs!
    """
    assert (
        http_json(
            base,
            "POST",
            "/grants",
            {
                "id": f"{grant_prefix}-root",
                "principal": f"agent:{mode}-lead",
                "allowed_actions": ["complete_task"],
                "max_calls": 200,
                "ttl_seconds": 3600,
            },
            admin_hdr,
        )[0]
        == 200
    )
    for w in range(6):
        assert (
            http_json(
                base,
                "POST",
                f"/grants/{grant_prefix}-root/delegate",
                {
                    "id": f"{grant_prefix}-w{w}",
                    "principal": f"agent:{mode}-w{w}",
                    "allowed_actions": ["complete_task"],
                    "max_calls": 30,
                    "ttl_seconds": 1800,
                },
                {"Authorization": "Bearer sim-planner", "X-Reason": "delegate-worker"},
            )[0]
            == 200
        )

    st_m0, m_before, _ = http_json(base, "GET", "/worlds/metrics")
    assert st_m0 == 200

    # Partition tasks disjointly across 6 worker agents (3 tasks each = 18 tasks)
    buckets = [task_ids[w::6] for w in range(6)]
    lock = threading.Lock()
    stop_readers = threading.Event()
    land_lats: list[float] = []
    read_lats: list[float] = []
    stats = {"landed": 0, "retries": 0, "errors": []}
    t0 = time.perf_counter()

    def worker(w_idx: int):
        gid = f"{grant_prefix}-w{w_idx}"
        who = f"agent:{mode}-w{w_idx}"
        hdr = {"Authorization": "Bearer sim-worker", "X-Agent-Id": who, "X-Reason": f"{mode}-work"}
        for tid in buckets[w_idx]:
            if mode == "fine":
                st_cl, b_cl, _ = http_json(
                    base,
                    "POST",
                    "/claims",
                    {"resource": f"task:{tid}", "grant_id": gid, "world_id": None, "ttl_seconds": 120},
                    hdr,
                )
                if st_cl != 200:
                    with lock:
                        stats["errors"].append(f"claim {tid}: {st_cl} {b_cl}")
                    return

            for attempt in range(30):
                wid = f"w-{mode}-{tid}-a{attempt}"
                st_o, b_o, _ = http_json(
                    base, "POST", "/worlds", {"id": wid, "grant_id": gid, "ttl_seconds": 300}, hdr
                )
                if st_o != 200:
                    with lock:
                        stats["errors"].append(f"open {wid}: {st_o} {b_o}")
                    return

                if mode == "coarse":
                    st_q, b_q, _ = http_json(
                        base,
                        "POST",
                        f"/worlds/{wid}/query",
                        {"query": "list_project_tasks", "args": project_id},
                        hdr,
                    )
                else:
                    st_q, b_q, _ = http_json(
                        base,
                        "POST",
                        f"/worlds/{wid}/query",
                        {"query": "get_task", "args": tid},
                        hdr,
                    )
                if st_q != 200:
                    with lock:
                        stats["errors"].append(f"query {wid}: {st_q} {b_q}")
                    return

                sha = hashlib.sha256(f"{mode}:{tid}:{who}".encode()).hexdigest()[:16]
                st_c, b_c, _ = http_json(
                    base,
                    "POST",
                    f"/worlds/{wid}/call",
                    {
                        "action": "complete_task",
                        "args": {
                            "task_id": tid,
                            "assignee": who,
                            "artifact_id": f"art-{tid}",
                            "artifact_summary": f"Completed task #{tid} ({mode})",
                            "artifact_sha256": sha,
                        },
                    },
                    hdr,
                )
                if st_c != 200:
                    with lock:
                        stats["errors"].append(f"call {wid}: {st_c} {b_c}")
                    return

                st_l, b_l, dt_l = http_json(base, "POST", f"/worlds/{wid}/land", None, hdr)
                if st_l == 200:
                    with lock:
                        stats["landed"] += 1
                        land_lats.append(dt_l)
                    break
                elif st_l == 409:
                    with lock:
                        stats["retries"] += 1
                    continue
                else:
                    with lock:
                        stats["errors"].append(f"land {wid}: {st_l} {b_l}")
                    return

            if mode == "fine":
                http_json(base, "DELETE", f"/claims/task:{tid}", None, hdr)

    def reader(r_idx: int):
        step = 0
        while not stop_readers.is_set():
            path = f"/projects/{project_id}" if (r_idx + step) % 2 == 0 else f"/projects/{project_id}/tasks"
            step += 1
            st_r, _, dt_r = http_json(base, "GET", path)
            with lock:
                if st_r == 200:
                    read_lats.append(dt_r)
                else:
                    stats["errors"].append(f"read {path}: {st_r}")

    with ThreadPoolExecutor(max_workers=8) as pool:
        rfuts = [pool.submit(reader, r) for r in range(2)]
        wfuts = [pool.submit(worker, w) for w in range(6)]
        for f in wfuts:
            f.result()
        stop_readers.set()
        for f in rfuts:
            f.result()

    elapsed = time.perf_counter() - t0
    st_m1, m_after, _ = http_json(base, "GET", "/worlds/metrics")
    assert st_m1 == 200
    assert not stats["errors"], f"{mode} errors: {stats['errors'][:5]}"
    assert stats["landed"] == len(task_ids), (mode, stats)

    return {
        "mode": mode,
        "elapsed_s": elapsed,
        "landed": stats["landed"],
        "stale_retries": m_after["stale_read_rejections"] - m_before["stale_read_rejections"],
        "needless_send_backs": m_after["needless_send_backs"] - m_before["needless_send_backs"],
        "reads": len(read_lats),
        "land_p50_ms": pct(land_lats, 0.5),
        "land_p95_ms": pct(land_lats, 0.95),
        "read_p50_ms": pct(read_lats, 0.5),
    }


def main() -> int:
    mo_bin = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/code/mo/target/release/mo")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    wb_mo = os.path.join(repo_root, "examples", "agent-workbench.mo")

    admin_hdr = {"Authorization": "Bearer sim-admin", "X-Reason": "admin-op"}
    planner_hdr = {"Authorization": "Bearer sim-planner", "X-Reason": "plan-sprint"}

    with tempfile.TemporaryDirectory(prefix="modb-workbench-sim-") as tmp:
        port1 = pick_free_port()
        base1 = f"http://127.0.0.1:{port1}"
        proc1 = start_server(mo_bin, wb_mo, tmp, port1, workers=8)
        try:
            wait_ready(base1, proc1)
            assert http_json(base1, "POST", "/admin/init", None, admin_hdr)[0] == 200

            # Seed two swarm projects (each $1000 = 100,000c) with 18 tasks ($10 each -> $11 billed)
            for pid, title in [("swarm-coarse", "Swarm Coarse Benchmark"), ("swarm-fine", "Swarm Fine Benchmark")]:
                assert (
                    http_json(
                        base1,
                        "POST",
                        "/projects",
                        {"id": pid, "name": title, "budget_cents": 100000},
                        admin_hdr,
                    )[0]
                    == 200
                )
            coarse_ids = list(range(101, 119))
            fine_ids = list(range(201, 219))
            for tid in coarse_ids:
                assert (
                    http_json(
                        base1,
                        "POST",
                        "/tasks",
                        {"id": tid, "project_id": "swarm-coarse", "title": f"Coarse task #{tid}", "base_cost_cents": 1000},
                        planner_hdr,
                    )[0]
                    == 200
                )
            for tid in fine_ids:
                assert (
                    http_json(
                        base1,
                        "POST",
                        "/tasks",
                        {"id": tid, "project_id": "swarm-fine", "title": f"Fine task #{tid}", "base_cost_cents": 1000},
                        planner_hdr,
                    )[0]
                    == 200
                )

            # PHASE 1A vs 1B: Measure needless send-backs on coarse vs fine World queries!
            coarse_res = run_swarm_experiment(base1, "coarse", "swarm-coarse", coarse_ids, "g-coarse", admin_hdr)
            fine_res = run_swarm_experiment(base1, "fine", "swarm-fine", fine_ids, "g-fine", admin_hdr)
            assert coarse_res["needless_send_backs"] > 0, coarse_res
            assert fine_res["needless_send_backs"] == 0 and fine_res["stale_retries"] == 0, fine_res

            # PHASE 2: Rogue delegated sub-agent incident on `infra` ($500 budget)
            assert (
                http_json(
                    base1,
                    "POST",
                    "/grants",
                    {
                        "id": "g-team-b",
                        "principal": "agent:team-b-lead",
                        "allowed_actions": ["create_task", "complete_task"],
                        "max_calls": 20,
                        "ttl_seconds": 3600,
                    },
                    admin_hdr,
                )[0]
                == 200
            )
            assert (
                http_json(
                    base1,
                    "POST",
                    "/grants/g-team-b/delegate",
                    {
                        "id": "g-rogue-sub",
                        "principal": "agent:rogue-bot",
                        "allowed_actions": ["complete_task"],
                        "max_calls": 10,
                        "ttl_seconds": 1800,
                    },
                    planner_hdr,
                )[0]
                == 200
            )

            # Create 2 rogue bloat tasks (20,000c each -> 44,000c billed) and 2 critical SRE tasks (10,000c each)
            for tid, title, cost in [
                (301, "Rogue crypto-miner job 1", 20000),
                (302, "Rogue crypto-miner job 2", 20000),
                (303, "SRE database failover drill", 10000),
                (304, "SRE TLS cert rotation", 10000),
            ]:
                assert (
                    http_json(
                        base1,
                        "POST",
                        "/tasks",
                        {"id": tid, "project_id": "infra", "title": title, "base_cost_cents": cost},
                        planner_hdr,
                    )[0]
                    == 200
                )

            rogue_hdr = {"Authorization": "Bearer sim-worker", "X-Agent-Id": "agent:rogue-bot", "X-Reason": "run-job"}
            # Rogue lands task #301 & #302 -> burns 44,000c of 50,000c infra budget!
            for tid in (301, 302):
                wid = f"w-rogue-{tid}"
                assert http_json(base1, "POST", "/worlds", {"id": wid, "grant_id": "g-rogue-sub", "ttl_seconds": 300}, rogue_hdr)[0] == 200
                assert (
                    http_json(
                        base1,
                        "POST",
                        f"/worlds/{wid}/call",
                        {
                            "action": "complete_task",
                            "args": {
                                "task_id": tid,
                                "assignee": "agent:rogue-bot",
                                "artifact_id": f"art-rogue-{tid}",
                                "artifact_summary": "rogue output",
                                "artifact_sha256": "deadbeef",
                            },
                        },
                        rogue_hdr,
                    )[0]
                    == 200
                )
                assert http_json(base1, "POST", f"/worlds/{wid}/land", None, rogue_hdr)[0] == 200

            # Legitimate SRE tries to complete tasks #303 & #304 (needs 11,000c each, only 6,000c left) -> BOTH 409!
            sre_hdr = {"Authorization": "Bearer sim-worker", "X-Agent-Id": "agent:sre", "X-Reason": "critical-sre"}
            for tid in (303, 304):
                st_sre, _, _ = http_json(
                    base1,
                    "POST",
                    f"/tasks/{tid}/complete",
                    {
                        "task_id": tid,
                        "assignee": "agent:sre",
                        "artifact_id": f"art-sre-{tid}",
                        "artifact_summary": f"SRE completed #{tid}",
                        "artifact_sha256": "cafebabe",
                    },
                    sre_hdr,
                )
                assert st_sre == 409, (tid, st_sre)

            # Mid-flight containment: rogue opens another World -> Admin revokes parent `g-team-b` -> 403 cascade!
            assert http_json(base1, "POST", "/worlds", {"id": "w-rogue-stop", "grant_id": "g-rogue-sub", "ttl_seconds": 300}, rogue_hdr)[0] == 200
            assert http_json(base1, "POST", "/grants/g-team-b/revoke", None, admin_hdr)[0] == 200
            st_rev, _, _ = http_json(base1, "POST", "/worlds/w-rogue-stop/land", None, rogue_hdr)
            assert st_rev == 403, st_rev

            # Selective-Undo Replay: excise parent grant `g-team-b` (auto-expands to `g-rogue-sub`)!
            st_sim1, prop1, sim1_ms = http_json(
                base1,
                "POST",
                "/admin/replay/simulate",
                {
                    "proposal_id": "undo-rogue-team",
                    "description": "Excise compromised grant subtree g-team-b",
                    "exclude_principal": None,
                    "exclude_grant": "g-team-b",
                    "exclude_world": None,
                    "exclude_seqs": None,
                    "stop_before_seq": None,
                    "overhead_pct_override": None,
                },
                admin_hdr,
            )
            assert st_sim1 == 200, (st_sim1, prop1)
            assert prop1["summary"]["excluded"] == 2 and prop1["summary"]["now_accepted"] == 2, prop1["summary"]

            st_acc1, _, acc1_ms = http_json(
                base1, "POST", "/admin/replay/proposals/undo-rogue-team/accept", None, admin_hdr
            )
            assert st_acc1 == 200
            st_ip, infra_post, _ = http_json(base1, "GET", "/projects/infra")
            assert st_ip == 200 and infra_post["spent_cents"] == 22000 and infra_post["remaining_cents"] == 28000, infra_post

            # PHASE 3: Bug-Fix Replay (remove 10% overhead billing bug -> 0%) + Portable Export + SIGKILL!
            st_sim2, prop2, sim2_ms = http_json(
                base1,
                "POST",
                "/admin/replay/simulate",
                {
                    "proposal_id": "fix-overhead-bug",
                    "description": "Retroactively fix 10% overhead billing bug to 0%",
                    "exclude_principal": None,
                    "exclude_grant": "g-team-b",
                    "exclude_world": None,
                    "exclude_seqs": None,
                    "stop_before_seq": None,
                    "overhead_pct_override": 0,
                },
                admin_hdr,
            )
            assert st_sim2 == 200 and prop2["summary"]["reply_changed"] == 36 and prop2["summary"]["now_accepted"] == 2, prop2["summary"]
            st_acc2, _, acc2_ms = http_json(
                base1, "POST", "/admin/replay/proposals/fix-overhead-bug/accept", None, admin_hdr
            )
            assert st_acc2 == 200

            st_exp, exp_snap, exp_ms = http_json(base1, "GET", "/admin/export")
            if st_exp != 200:
                log_path = os.path.join(tmp, f"wb-{port1}.log")
                tail = open(log_path, encoding="utf-8").read()[-1500:] if os.path.exists(log_path) else ""
                raise AssertionError(f"GET /admin/export failed: {st_exp} {str(exp_snap)[:300]}\n--- server log ---\n{tail}")
            assert exp_snap["format_version"] == 1 and len(exp_snap["sha256"]) == 64, (
                st_exp,
                str(exp_snap)[:400],
            )

            # Hard OS SIGKILL right after replay adoption!
            proc1.send_signal(signal.SIGKILL)
            proc1.wait()
        finally:
            if proc1.poll() is None:
                proc1.send_signal(signal.SIGKILL)
                proc1.wait()

        # Restart 8-worker server and verify full durability + repaired state + SHA-256 audit chain!
        port2 = pick_free_port()
        base2 = f"http://127.0.0.1:{port2}"
        proc2 = start_server(mo_bin, wb_mo, tmp, port2, workers=8)
        try:
            wait_ready(base2, proc2)
            st_v, ver, ver_ms = http_json(base2, "GET", "/admin/verify")
            assert st_v == 200 and ver["ok"] is True, (st_v, ver)

            # All 3 projects must reflect 0% overhead after bug-fix replay & SIGKILL!
            for pid, exp_spent in [("swarm-coarse", 18000), ("swarm-fine", 18000), ("infra", 20000)]:
                st_p, proj, _ = http_json(base2, "GET", f"/projects/{pid}")
                assert st_p == 200 and proj["spent_cents"] == exp_spent, (pid, proj)

            # Tasks #301/#302 back to Open (rogue excised), #303/#304 Done (SRE unblocked), rogue artifacts gone!
            for tid, exp_st in [(301, "open"), (302, "open"), (303, "done"), (304, "done")]:
                st_t, task, _ = http_json(base2, "GET", f"/tasks/{tid}")
                assert st_t == 200 and task["status"] == exp_st, (tid, task)
            assert http_json(base2, "GET", "/tasks/301/artifacts")[1] == []
            assert len(http_json(base2, "GET", "/tasks/303/artifacts")[1]) == 1

            print("=== Milestone 6: Real-World Multi-Agent Workbench Report (mo serve --workers 8) ===")
            print(
                f"Phase 1A (Coarse `list_project_tasks`, 6W+2R, 18 tasks): "
                f"{coarse_res['elapsed_s']:.2f}s | stale_retries={coarse_res['stale_retries']} | "
                f"needless_send_backs={coarse_res['needless_send_backs']} | "
                f"land p50={coarse_res['land_p50_ms']:.1f}ms p95={coarse_res['land_p95_ms']:.1f}ms | "
                f"reads={coarse_res['reads']} (p50={coarse_res['read_p50_ms']:.1f}ms)"
            )
            print(
                f"Phase 1B (Fine `get_task` + Claims, 6W+2R, 18 tasks):     "
                f"{fine_res['elapsed_s']:.2f}s | stale_retries={fine_res['stale_retries']} | "
                f"needless_send_backs={fine_res['needless_send_backs']} | "
                f"land p50={fine_res['land_p50_ms']:.1f}ms p95={fine_res['land_p95_ms']:.1f}ms | "
                f"reads={fine_res['reads']} (p50={fine_res['read_p50_ms']:.1f}ms)"
            )
            print(
                f"Phase 2  (Rogue subtree excision replay over {prop1['summary']['total_calls']} calls): "
                f"sim={sim1_ms:.1f}ms accept={acc1_ms:.1f}ms | "
                f"excluded={prop1['summary']['excluded']} now_accepted={prop1['summary']['now_accepted']} "
                f"(cascading revoke -> 403)"
            )
            print(
                f"Phase 3  (Overhead 10%->0% bug-fix replay over {prop2['summary']['total_calls']} calls): "
                f"sim={sim2_ms:.1f}ms accept={acc2_ms:.1f}ms | "
                f"reply_changed={prop2['summary']['reply_changed']} now_accepted={prop2['summary']['now_accepted']} | "
                f"export={exp_ms:.1f}ms ({exp_snap['bucket_count']} buckets, {exp_snap['entry_count']} entries)"
            )
            print(
                f"Post-SIGKILL verify: ok=True ({ver_ms:.1f}ms) | txid={ver['txid']} | "
                f"pages={ver['page_count']} | audit_entries={ver['audit_entries']} | "
                f"hash={ver['last_audit_hash'][:16]}..."
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
