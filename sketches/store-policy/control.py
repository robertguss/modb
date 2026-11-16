"""Experiment 16's controls: a sweep that ignores the holders, and backend B in a service."""
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent.parent
MO = ROOT / "build" / "enforcement-trial" / "mo"
COPY = ROOT / "build" / "store-policy-control"
ASKS = "  live = reach(ops, store, head.holders.values.append(head.root))\n"
IGNORES = "  live = reach(ops, store, [head.root])\n"


def run(*args):
    done = subprocess.run([str(MO), *args], capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def main():
    shutil.rmtree(COPY, ignore_errors=True)
    shutil.copytree(HERE, COPY)
    policy = COPY / "policy.mo"
    text = policy.read_text()
    assert text.count(ASKS) == 1
    policy.write_text(text.replace(ASKS, IGNORES))
    status, out = run("test", str(COPY / "backend-b.mo"))
    print("a sweep that ignores the holders:")
    print("\n".join("  " + line for line in out.splitlines() if line.startswith(("passed", "failed", "stopped")) or " passed, " in line))
    freed = status != 0 and "failed BackendA.service.promise.1" in out and "failed BackendB.test.2" in out
    status, out = run("check", str(HERE / "control-b-service.mo"))
    print("backend B in a service:")
    print("  " + out.splitlines()[0])
    refused = status != 0 and "E0104" in out
    print("controls failed as they must:", freed and refused)
    sys.exit(0 if freed and refused else 1)


if __name__ == "__main__":
    main()
