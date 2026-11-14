#!/usr/bin/env python3
"""Run each model for every case and setting and compare with its predictions file."""
import itertools
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
BUILD = HERE.parent / "build" / "models"
JAR = pathlib.Path(os.environ.get("TLA2TOOLS_JAR", HERE.parent / "build" / "tla2tools.jar"))

REPLAY_CAUGHT_BY = {"seat": "FPR", "meeting": "FPR", "skew": "FPR",
                    "discount": "R", "lostupdate": "R", "intent": None}
REPLAY_HAS_RULE = {"seat", "meeting", "skew"}
REPLAY_INVARIANTS = ["Serial", "RuleHolds", "NoNeedlessSendBack", "NotAllDone", "NothingLanded"]

WORLDS_RULE_CASES = ("transfer", "budget")
WORLDS_CASES = WORLDS_RULE_CASES + ("audit", "stuck", "ownread", "apart")
WORLDS_LANDINGS = [("call", "off"), ("call", "inplace"),
                   ("world", "off"), ("world", "main"), ("world", "inplace")]
WORLDS_INVARIANTS = ["RuleHolds", "Serial", "ApprovedOnly", "NotAllDone"]
WORLDS_TRIES = os.environ.get("WORLDS_TRIES", "3")


def violated(spec, name, constants, invariants):
    found = set()
    for invariant in invariants:
        run_name = f"{spec}-{name}-{invariant}"
        cfg = BUILD / f"{run_name}.cfg"
        cfg.write_text(f"SPECIFICATION Spec\nCONSTANTS {constants}\n"
                       f"INVARIANT {invariant}\nCHECK_DEADLOCK FALSE\n")
        run = subprocess.run(
            ["java", "-XX:+UseParallelGC", "-Xmx512m", "-cp", str(JAR), "tlc2.TLC",
             "-noGenerateSpecTE", "-workers", "1", "-metadir", str(BUILD / "states" / run_name),
             "-config", str(cfg), f"{spec}.tla"],
            cwd=HERE, capture_output=True, text=True, check=False)
        (BUILD / f"{run_name}.log").write_text(run.stdout + run.stderr)
        if f"Invariant {invariant} is violated" in run.stdout:
            found.add(invariant)
        elif "No error has been found" not in run.stdout:
            raise SystemExit(f"TLC gave no verdict for {run_name}; see {BUILD / (run_name + '.log')}")
    return found


def verdict(want, got):
    return "as predicted" if want == got else f"NOT AS PREDICTED, expected {sorted(want)}"


def replay_predicted(case, on):
    broken = {"NotAllDone", "NothingLanded"}
    caught_by = REPLAY_CAUGHT_BY[case]
    if caught_by is not None and not set(on) & set(caught_by):
        broken.add("Serial")
        if case in REPLAY_HAS_RULE:
            broken.add("RuleHolds")
    if case == "intent" and "R" in on:
        broken.add("NoNeedlessSendBack")
    return broken


def replay():
    wrong = held = failed = 0
    for case in REPLAY_CAUGHT_BY:
        for bits in itertools.product([False, True], repeat=3):
            on = "".join(m for m, bit in zip("FPR", bits) if bit)
            flags = " ".join(f"Use{m} = {'TRUE' if m in on else 'FALSE'}" for m in "FPR")
            want = replay_predicted(case, on)
            got = violated("Replay", f"{case}-{on or 'none'}",
                           f'Case = "{case}" {flags} MaxTries = 2', REPLAY_INVARIANTS)
            bad = sorted(got & {"Serial", "RuleHolds"})
            held, failed, wrong = held + (not bad), failed + bool(bad), wrong + (want != got)
            needless = "  needless send-back" if "NoNeedlessSendBack" in got else ""
            print(f"{case:10} {on or '-':3} {'fails ' + '+'.join(bad) if bad else 'holds':24}"
                  f"{needless:22} {verdict(want, got)}")
    print(f"Replay: {held} settings hold, {failed} fail; {wrong} of 48 not as predicted")
    return wrong


def worlds_predicted(case, unit, check, reads):
    if case in WORLDS_RULE_CASES:
        if check == "each":
            return set()
        broken = {"NotAllDone"}
        if unit == "call":
            broken.add("RuleHolds")
        if case == "budget":
            broken.add("ApprovedOnly")
        return broken
    if case == "apart":
        return {"NotAllDone"}
    if case == "stuck":
        return {"Serial"} if unit == "call" else set()
    if case == "audit":
        return {"NotAllDone", "Serial"} if unit == "call" else {"NotAllDone"}
    if unit == "world" and reads == "main":
        return set()
    if unit == "world" and reads == "inplace":
        return {"NotAllDone"}
    return {"NotAllDone", "Serial"}


def worlds():
    wrong = held = failed = 0
    for case in WORLDS_CASES:
        for check in ("each", "end") if case in WORLDS_RULE_CASES else ("each",):
            for unit, reads in WORLDS_LANDINGS:
                want = worlds_predicted(case, unit, check, reads)
                got = violated("Worlds", f"{case}-{unit}-{check}-{reads}",
                               f'Case = "{case}" Unit = "{unit}" Check = "{check}" '
                               f'UseR = "{reads}" MaxTries = {WORLDS_TRIES}', WORLDS_INVARIANTS)
                bad = sorted(got - {"NotAllDone"})
                held, failed, wrong = held + (not bad), failed + bool(bad), wrong + (want != got)
                finish = "both finish" if "NotAllDone" in got else "one never finishes"
                print(f"{case:9} {unit:5} {check:4} {reads:7} "
                      f"{'fails ' + '+'.join(bad) if bad else 'holds':29} {finish:19} {verdict(want, got)}")
    print(f"Worlds: {held} settings hold, {failed} fail; {wrong} of 40 not as predicted")
    return wrong


MODELS = {"replay": replay, "worlds": worlds}


def main():
    if not JAR.is_file():
        print(f"no TLC jar at {JAR}; set TLA2TOOLS_JAR. A skip is not a pass.")
        return 77
    (BUILD / "states").mkdir(parents=True, exist_ok=True)
    return 1 if sum(MODELS[name]() for name in sys.argv[1:] or MODELS) else 0


if __name__ == "__main__":
    sys.exit(main())
