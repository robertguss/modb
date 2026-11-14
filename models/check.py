#!/usr/bin/env python3
"""Run Replay.tla for every case and setting and compare with replay-predictions.md."""
import itertools
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
BUILD = HERE.parent / "build" / "replay"
JAR = pathlib.Path(os.environ.get("TLA2TOOLS_JAR", HERE.parent / "build" / "tla2tools.jar"))
CAUGHT_BY = {"seat": "FPR", "meeting": "FPR", "skew": "FPR",
             "discount": "R", "lostupdate": "R", "intent": None}
HAS_RULE = {"seat", "meeting", "skew"}
INVARIANTS = ["Serial", "RuleHolds", "NoNeedlessSendBack", "NotAllDone", "NothingLanded"]


def predicted(case, on):
    violated = {"NotAllDone", "NothingLanded"}
    caught_by = CAUGHT_BY[case]
    if caught_by is not None and not set(on) & set(caught_by):
        violated.add("Serial")
        if case in HAS_RULE:
            violated.add("RuleHolds")
    if case == "intent" and "R" in on:
        violated.add("NoNeedlessSendBack")
    return violated


def observed(case, on):
    flags = " ".join(f"Use{m} = {'TRUE' if m in on else 'FALSE'}" for m in "FPR")
    violated = set()
    for invariant in INVARIANTS:
        name = f"{case}-{on or 'none'}-{invariant}"
        cfg = BUILD / f"{name}.cfg"
        cfg.write_text(f'SPECIFICATION Spec\nCONSTANTS Case = "{case}" {flags} MaxTries = 2\n'
                       f"INVARIANT {invariant}\nCHECK_DEADLOCK FALSE\n")
        run = subprocess.run(
            ["java", "-XX:+UseParallelGC", "-Xmx512m", "-cp", str(JAR), "tlc2.TLC",
             "-workers", "1", "-metadir", str(BUILD / "states" / name), "-config", str(cfg),
             "Replay.tla"], cwd=HERE, capture_output=True, text=True, check=False)
        (BUILD / f"{name}.log").write_text(run.stdout + run.stderr)
        if f"Invariant {invariant} is violated" in run.stdout:
            violated.add(invariant)
        elif "No error has been found" not in run.stdout:
            raise SystemExit(f"TLC gave no verdict for {name}; see {BUILD / (name + '.log')}")
    return violated


def main():
    if not JAR.is_file():
        print(f"no TLC jar at {JAR}; set TLA2TOOLS_JAR. A skip is not a pass.")
        return 77
    BUILD.mkdir(parents=True, exist_ok=True)
    wrong = held = failed = 0
    for case in CAUGHT_BY:
        for bits in itertools.product([False, True], repeat=3):
            on = "".join(m for m, bit in zip("FPR", bits) if bit)
            want, got = predicted(case, on), observed(case, on)
            bad = sorted(got & {"Serial", "RuleHolds"})
            held, failed = held + (not bad), failed + bool(bad)
            needless = "  needless send-back" if "NoNeedlessSendBack" in got else ""
            verdict = "as predicted" if want == got else f"NOT AS PREDICTED, expected {sorted(want)}"
            wrong += want != got
            print(f"{case:10} {on or '-':3} {'fails ' + '+'.join(bad) if bad else 'holds':24}"
                  f"{needless:22} {verdict}")
    print(f"{held} runs hold, {failed} fail; {wrong} of 48 not as predicted")
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
