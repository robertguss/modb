#!/usr/bin/env python3
"""End-to-end live 8-worker HTTP pull-replica sync integration test for MoDB v0.9.0.

Tests `modb sync <replica.modb> pull` against a live `mo serve --workers 8 examples/agent-workbench.mo`:
  1. Plain pull: auto-bootstraps missing replica via POST /sync/peers/:id/snapshot + pulls
     sequential delta 1 + acks -> commits new project on primary -> pulls delta 2 -> verifies
     exact data parity via `modb verify` & `modb dump`.
  2. Encrypted keyring-rotated pull across server restart:
     - Snapshot + delta 1 sealed with key k1 (MODB_BACKUP_KEY_ID=k1).
     - Restart primary server with rotated key k2 (MODB_BACKUP_KEY_ID=k2) and write new data.
     - Pull delta 2 using `--decrypt --keyring-env MODB_BACKUP_KEYRING --aad live-m17`.
     - Negative control: wrong AAD fails closed without advancing server `acked_seq` or corrupting replica.
"""
from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


K1_HEX = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
K2_HEX = "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
ADMIN_TOK = "tok-live-pull-admin"


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def http_json(base: str, method: str, path: str, body=None, token: str | None = None, reason: str | None = None):
    hdrs = {}
    if token:
        hdrs["Authorization"] = f"Bearer {token}"
    if reason:
        hdrs["X-Reason"] = reason
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{base}{path}", data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15.0) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return e.code, parsed


def wait_ready(base: str, proc: subprocess.Popen[str], timeout: float = 20.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            raise RuntimeError(f"mo serve exited early ({proc.returncode}):\nstdout:\n{out}\nstderr:\n{err}")
        try:
            st, _ = http_json(base, "GET", "/health")
            if st == 200:
                return
        except Exception:
            time.sleep(0.1)
    raise RuntimeError(f"Timed out waiting for {base}/health")


def start_workbench(
    mo_bin: str, repo_root: str, data_dir: str, port: int, key_id: str, key_hex: str
) -> subprocess.Popen[str]:
    env = os.environ.copy()
    env.update(
        {
            "WB_ADMIN_TOKEN": ADMIN_TOK,
            "WB_PLANNER_TOKEN": "tok-plan",
            "WB_WORKER_TOKEN": "tok-work",
            "MODB_BACKUP_KEY_ID": key_id,
            "MODB_BACKUP_KEY_HEX": key_hex,
        }
    )
    return subprocess.Popen(
        [
            mo_bin,
            "serve",
            "--workers",
            "8",
            "--port",
            str(port),
            "--data",
            data_dir,
            os.path.join(repo_root, "examples", "agent-workbench.mo"),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def run_modb_cli(modb_bin: str, cwd: str, args: list[str], extra_env: dict[str, str] | None = None) -> tuple[int, str, str]:
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    proc = subprocess.run([modb_bin] + args, cwd=cwd, env=env, capture_output=True, text=True, timeout=30)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def stop_proc(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def main() -> int:
    mo_bin = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/bin/mo")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    modb_bin = shutil.which("modb") or os.path.expanduser("~/.local/bin/modb")

    with tempfile.TemporaryDirectory(prefix="modb-pull-live-") as tmp:
        primary_dir = os.path.join(tmp, "primary")
        replica_dir = os.path.join(tmp, "replica")
        os.makedirs(primary_dir, exist_ok=True)
        os.makedirs(replica_dir, exist_ok=True)

        port = pick_free_port()
        base = f"http://127.0.0.1:{port}"
        srv = start_workbench(mo_bin, repo_root, primary_dir, port, "k1", K1_HEX)

        try:
            wait_ready(base, srv)

            # Initialize DB and register plain + encrypted sync peers
            st, _ = http_json(base, "POST", "/admin/init", token=ADMIN_TOK, reason="init primary")
            assert st == 200, st
            st, _ = http_json(
                base,
                "POST",
                "/sync/peers",
                {"peer_id": "live-plain", "include_internal": False, "from_empty": False},
                token=ADMIN_TOK,
            )
            assert st == 200, st
            st, _ = http_json(
                base,
                "POST",
                "/sync/peers",
                {"peer_id": "live-enc", "include_internal": False, "from_empty": False},
                token=ADMIN_TOK,
            )
            assert st == 200, st

            # Write project p-live-1 after peer registration
            st, _ = http_json(
                base,
                "POST",
                "/projects",
                {"id": "p-live-1", "name": "Live Pull One", "budget_cents": 42000},
                token=ADMIN_TOK,
                reason="seed p-live-1",
            )
            assert st == 200, st

            cli_env = {
                "PULL_TOK": ADMIN_TOK,
                "MODB_BACKUP_KEYRING": f"k1={K1_HEX},k2={K2_HEX}",
            }

            # 1. Plain pull #1 (bootstrap + delta 1 + ack)
            rc, out, err = run_modb_cli(
                modb_bin,
                replica_dir,
                [
                    "sync",
                    "rep-plain.modb",
                    "pull",
                    "--url",
                    f"{base}/sync/peers",
                    "--peer",
                    "live-plain",
                    "--token-env",
                    "PULL_TOK",
                    "--once",
                    "--json",
                ],
                cli_env,
            )
            assert rc == 0, f"plain pull 1 failed: {err}\n{out}"
            rep1 = json.loads(out)
            assert rep1["bootstrapped?"] is True and rep1["acked?"] is True and rep1["delta_seq"] == 1, rep1

            # 2. Encrypted pull #1 (snapshot + delta 1 sealed under k1)
            rc, out, err = run_modb_cli(
                modb_bin,
                replica_dir,
                [
                    "sync",
                    "rep-enc.modb",
                    "pull",
                    "--url",
                    f"{base}/sync/peers",
                    "--peer",
                    "live-enc",
                    "--token-env",
                    "PULL_TOK",
                    "--decrypt",
                    "--keyring-env",
                    "MODB_BACKUP_KEYRING",
                    "--aad",
                    "live-m17",
                    "--once",
                    "--json",
                ],
                cli_env,
            )
            assert rc == 0, f"enc pull 1 failed: {err}\n{out}"
            erep1 = json.loads(out)
            assert erep1["bootstrapped?"] is True and erep1["acked?"] is True and erep1["delta_seq"] == 1, erep1

            # Restart primary server with ROTATED encryption key k2 and add project p-live-2
            stop_proc(srv)
            port2 = pick_free_port()
            base2 = f"http://127.0.0.1:{port2}"
            srv = start_workbench(mo_bin, repo_root, primary_dir, port2, "k2", K2_HEX)
            wait_ready(base2, srv)

            st, _ = http_json(
                base2,
                "POST",
                "/projects",
                {"id": "p-live-2", "name": "Live Pull Two", "budget_cents": 84000},
                token=ADMIN_TOK,
                reason="seed p-live-2 after k2 rotation",
            )
            assert st == 200, st

            # 3. Plain pull #2 (incremental delta 2)
            rc, out, err = run_modb_cli(
                modb_bin,
                replica_dir,
                [
                    "sync",
                    "rep-plain.modb",
                    "pull",
                    "--url",
                    f"{base2}/sync/peers",
                    "--peer",
                    "live-plain",
                    "--token-env",
                    "PULL_TOK",
                    "--once",
                    "--json",
                ],
                cli_env,
            )
            assert rc == 0, f"plain pull 2 failed: {err}\n{out}"
            rep2 = json.loads(out)
            assert rep2["bootstrapped?"] is False and rep2["delta_seq"] == 2 and rep2["acked?"] is True, rep2

            # 4. Encrypted pull #2 with k2-sealed delta opened automatically via k1+k2 keyring!
            rc, out, err = run_modb_cli(
                modb_bin,
                replica_dir,
                [
                    "sync",
                    "rep-enc.modb",
                    "pull",
                    "--url",
                    f"{base2}/sync/peers",
                    "--peer",
                    "live-enc",
                    "--token-env",
                    "PULL_TOK",
                    "--decrypt",
                    "--keyring-env",
                    "MODB_BACKUP_KEYRING",
                    "--aad",
                    "live-m17",
                    "--once",
                    "--json",
                ],
                cli_env,
            )
            assert rc == 0, f"enc pull 2 failed: {err}\n{out}"
            erep2 = json.loads(out)
            assert erep2["bootstrapped?"] is False and erep2["delta_seq"] == 2 and erep2["acked?"] is True, erep2

            # 5. Verify both replicas with `modb verify` & `modb dump projects`
            for db_name in ("rep-plain.modb", "rep-enc.modb"):
                rc, vout, verr = run_modb_cli(modb_bin, replica_dir, ["verify", db_name, "--json"])
                assert rc == 0, f"verify {db_name} failed: {verr}"
                assert json.loads(vout)["ok?"] is True, vout
                rc, dout, derr = run_modb_cli(modb_bin, replica_dir, ["dump", db_name, "projects", "--json"])
                assert rc == 0, f"dump {db_name} failed: {derr}"
                assert "p-live-1" in dout and "p-live-2" in dout, (db_name, dout)

            # 6. Negative control: wrong k2 key in keyring MUST fail closed and NEVER advance acked_seq
            st, _ = http_json(
                base2,
                "POST",
                "/projects",
                {"id": "p-live-3", "name": "Live Pull Three", "budget_cents": 10000},
                token=ADMIN_TOK,
                reason="seed p-live-3",
            )
            assert st == 200, st
            bad_env = dict(cli_env)
            bad_env["WRONG_KEYRING"] = f"k1={K1_HEX},k2={'11' * 32}"
            rc_bad, _out_bad, err_bad = run_modb_cli(
                modb_bin,
                replica_dir,
                [
                    "sync",
                    "rep-enc.modb",
                    "pull",
                    "--url",
                    f"{base2}/sync/peers",
                    "--peer",
                    "live-enc",
                    "--token-env",
                    "PULL_TOK",
                    "--decrypt",
                    "--keyring-env",
                    "WRONG_KEYRING",
                    "--aad",
                    "live-m17",
                    "--once",
                ],
                bad_env,
            )
            assert rc_bad != 0 and "decryption failed" in err_bad.lower(), (rc_bad, err_bad)

            st, peers = http_json(base2, "GET", "/sync/peers", token=ADMIN_TOK)
            assert st == 200
            enc_peer = [p for p in peers if p["peer_id"] == "live-enc"][0]
            assert enc_peer["acked_seq"] == 2, enc_peer
            rc, dout_after, _ = run_modb_cli(modb_bin, replica_dir, ["dump", "rep-enc.modb", "projects", "--json"])
            assert rc == 0 and "p-live-3" not in dout_after, dout_after

            print("test_sync_pull_live PASSED (plain + rotated-keyring AEAD pull + fail-closed AAD check)")
            return 0
        finally:
            stop_proc(srv)


if __name__ == "__main__":
    raise SystemExit(main())
