#!/usr/bin/env python3
"""Gate 3: Real OS SIGKILL (kill -9) crash-survival loop for MoDB."""
import os
import random
import signal
import subprocess
import sys
import tempfile
import time

def read_max_acked(ledger_path: str) -> int:
    if not os.path.exists(ledger_path):
        return 0
    max_seq = 0
    with open(ledger_path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.isdigit():
                max_seq = max(max_seq, int(s))
    return max_seq

def main() -> int:
    if len(sys.argv) < 2:
        print("usage: kill_loop.py <path-to-mo> [kills=100]", file=sys.stderr)
        return 2
    mo_bin = sys.argv[1]
    kills = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    script_dir = os.path.dirname(os.path.abspath(__file__))
    writer_mo = os.path.join(script_dir, "kill-writer.mo")

    rng = random.Random(20261123)
    with tempfile.TemporaryDirectory(prefix="modb-kill-") as tmp:
        bc_path = os.path.join(tmp, "kill_writer.bc")
        emit = subprocess.run([mo_bin, "emit", writer_mo, "-o", bc_path], capture_output=True, text=True)
        if emit.returncode != 0:
            print(f"emit failed:\n{emit.stdout}\n{emit.stderr}", file=sys.stderr)
            return 1

        db_name = "crash.modb"
        ledger_name = "acked.log"
        ledger_abs = os.path.join(tmp, ledger_name)
        t0 = time.monotonic()
        last_info = ""

        for k in range(1, kills + 1):
            proc = subprocess.Popen(
                [mo_bin, "run", "--root", tmp, bc_path, "write", db_name, ledger_name, "50000"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
            # Wait for the writer to finish startup and enter its live commit loop before killing.
            ready_line = proc.stdout.readline() if proc.stdout else ""
            if not ready_line.startswith("ready "):
                out, err = proc.communicate()
                print(
                    f"kill {k}: writer did not become ready ({proc.returncode}): {ready_line}{out}{err}",
                    file=sys.stderr,
                )
                return 1
            delay = rng.uniform(0.005, 0.045)
            time.sleep(delay)
            if proc.poll() is None:
                proc.send_signal(signal.SIGKILL)
                proc.wait()
            else:
                out, err = proc.communicate()
                if proc.returncode != 0:
                    print(f"kill {k}: writer exited unexpectedly ({proc.returncode}): {err}", file=sys.stderr)
                    return 1

            min_acked = read_max_acked(ledger_abs)
            ver = subprocess.run(
                [mo_bin, "run", "--root", tmp, bc_path, "verify", db_name, str(min_acked)],
                capture_output=True,
                text=True,
            )
            if ver.returncode != 0:
                print(
                    f"VERIFY FAILED after kill {k} (min_acked={min_acked}):\n"
                    f"stdout: {ver.stdout}\nstderr: {ver.stderr}",
                    file=sys.stderr,
                )
                return 1
            last_info = ver.stdout.strip()
            if k % 25 == 0 or k == kills:
                print(f"kill {k}/{kills}: acked={min_acked} | {last_info}", flush=True)

        elapsed = time.monotonic() - t0
        final_acked = read_max_acked(ledger_abs)
        if final_acked < 50:
            print(f"FAIL: too few commits landed during kill loop (acked={final_acked})", file=sys.stderr)
            return 1
        print(f"PASS: {kills} SIGKILL crashes survived in {elapsed:.1f}s (acked={final_acked}, {last_info})")
        return 0

if __name__ == "__main__":
    raise SystemExit(main())
