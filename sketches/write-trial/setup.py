#!/usr/bin/env python3
"""Sets up the sessions of experiment 14, in which agents write the functions that change the shop, and collects them."""
import pathlib
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent
TRIAL = HERE.parent / "enforcement-trial"
OUT = HERE.parents[1] / "build" / "write-trial"
MO = HERE.parents[1] / "build" / "enforcement-trial" / "mo"
SESSIONS = {"w1": "claude", "w2": "gpt", "w3": "claude", "w4": "gpt"}


def setup():
    for name in SESSIONS:
        work = OUT / name / "work"
        work.mkdir(parents=True)
        (work / "shop.mo").write_text((TRIAL / "shop-a.head.mo").read_text() + (TRIAL / "rows.mo").read_text())
        (work / "STORE.md").write_text((TRIAL / "STORE-a.md").read_text())
        (work / "TASK.md").write_text((HERE / "TASK.md").read_text())
        (work / "mo").write_text(f'#!/bin/sh\nexec {MO} "$@"\n')
        (work / "mo").chmod(0o755)
        (OUT / name / "prompt.txt").write_text((HERE / "PROMPT.md").read_text().replace("WORK", str(work)))
        print(name, SESSIONS[name], OUT / name / "prompt.txt")


def collect():
    """Copies what each session left into `results/`, as `writes-<session>-<model>.mo` and `checks-<session>-<model>.mo` beside it."""
    (HERE / "results").mkdir(exist_ok=True)
    for name, model in SESSIONS.items():
        for file in ("writes.mo", "checks.mo"):
            found = OUT / name / "work" / file
            if found.exists():
                shutil.copy(found, HERE / "results" / f"{file[:-3]}-{name}-{model}.mo")


if __name__ == "__main__":
    {"setup": setup, "collect": collect}[sys.argv[1]]()
