#!/usr/bin/env python3
"""Sets up the sessions of the enforcement trial, checks its own materials, and grades what the sessions wrote."""
import itertools
import json
import math
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

import rule
from tasks import PILOT, TASKS, example_test, hidden_test, printer, task_text

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parents[1] / "build" / "enforcement-trial"
MO = OUT / "mo"
SESSIONS = OUT / "sessions"
ARMS = "ag"
MODELS = ("claude", "gpt")
PILOTS = {"p1": ("a", "claude"), "p2": ("g", "gpt")}
TABLES = "customers|products|orders|lines"
WALK = re.compile(rf"walk\(\s*\w+\.({TABLES})\b|\.({TABLES})\.walk\b")
BY_NAME = {task["name"]: task for task in [*TASKS, PILOT]}
WRONG = {"orders_of": "shop.orders.walk.filter(fn(order) order.customer != customer end).map(fn(order) order.id end).sort",
         "large_orders": "shop.orders.total_at_least(least + 1).map(fn(order) order.id end).sort",
         "latest": "shop.orders.of_customer(customer).sort_by_desc(fn(order) order.placed end).take(n)"
                   ".map(fn(order) order.id end)"}


def shop(arm):
    return (HERE / f"shop-{arm}.head.mo").read_text() + (HERE / "rows.mo").read_text()


def one_function(task, body, uses="use Shop{Shop}"):
    return f"module Answer\nexpose {task['name']}\n{uses}\n\n{task['signature']}\n  {body}\nend\n"


def folder_for(arm, files):
    folder = pathlib.Path(tempfile.mkdtemp())
    for name, text in {"shop.mo": shop(arm), "reference.mo": (HERE / f"reference-{arm}.mo").read_text(),
                       **files}.items():
        (folder / name).write_text(text)
    return folder


def judged(arm, task, answer):
    """Whether this answer checks, is refused by the arm's own rule, passes the hidden test, and what it walks."""
    folder = folder_for(arm, {"answer.mo": answer, "hidden.mo": hidden_test(task)})
    check = subprocess.run([MO, "check", "answer.mo"], cwd=folder, capture_output=True, text=True)
    checks = check.returncode == 0
    codes = set(re.findall(r"error (E\d+)", check.stdout + check.stderr))
    refused = bool(rule.errors(answer)) if arm == "a" and checks else codes == {"E0064"}
    right = checks and subprocess.run([MO, "test", "hidden.mo"], cwd=folder, capture_output=True).returncode == 0
    shutil.rmtree(folder)
    code = "\n".join(line for line in answer.splitlines() if not line.startswith(("use ", "expose ", "#")))
    walked = {a or b for a, b in WALK.findall(code)}
    if len(re.findall(r"\bwalk\b", code)) > len(WALK.findall(code)):
        walked.add("?")
    needless = bool(walked - set(task["walks"]))
    return {"checks": checks, "refused": refused, "right": right, "walked": sorted(walked), "needless": needless,
            "good": checks and not refused and right and not needless}


def selfcheck():
    """The references must pass in both arms and agree; planted wrong and slow answers must be caught."""
    printed = {}
    for arm in ARMS:
        assert not (arm == "a" and rule.errors((HERE / f"reference-{arm}.mo").read_text()))
        for task in BY_NAME.values():
            names = ", ".join(re.findall(r"(\w+): ", task["signature"]))
            passed = judged(arm, task, one_function(task, f"Reference.{task['name']}({names})",
                                                    "use Reference\nuse Shop{Shop}"))
            assert passed["good"], (arm, task["name"], passed)
        folder = folder_for(arm, {"main.mo": printer(TASKS)})
        printed[arm] = subprocess.run([MO, "run", "main.mo"], cwd=folder, capture_output=True, text=True, check=True).stdout
        shutil.rmtree(folder)
    assert printed["a"] == printed["g"] and len(printed["a"].splitlines()) > 700, len(printed["a"].splitlines())
    for name, body in WRONG.items():
        caught = judged("g", BY_NAME[name], one_function(BY_NAME[name], body))
        assert caught["checks"] and not caught["right"] and not caught["good"], (name, caught)
    assert judged("g", BY_NAME["orders_of"], one_function(BY_NAME["orders_of"], WRONG["orders_of"]))["needless"]
    inside = judged("g", BY_NAME["open_count"], one_function(BY_NAME["open_count"], "shop.orders.rows.size"))
    assert inside["refused"] and not inside["good"], inside
    slow = (HERE / "controls" / "slow-a.mo").read_text()
    folder = folder_for("a", {"answer.mo": slow})
    assert subprocess.run([MO, "check", "answer.mo"], cwd=folder, capture_output=True).returncode == 0
    shutil.rmtree(folder)
    assert len({error["line"] for error in rule.errors(slow)}) == 11, rule.errors(slow)
    print(f"selfcheck: {2 * len(BY_NAME)} reference answers pass and the two arms print the same "
          f"{len(printed['a'].splitlines())} answers; {len(WRONG)} wrong answers fail the hidden tests; "
          f"11 slow reads are refused in arm A; a read inside a table is refused in arm G")


def setup():
    """One folder for each session: 10 tasks, 2 arms, 2 models, and two pilots on a task of their own."""
    cells = {f"{number:02}": (arm, model, task) for number, (task, arm, model)
             in enumerate(itertools.product(TASKS, ARMS, MODELS), 1)}
    cells.update({name: (arm, model, PILOT) for name, (arm, model) in PILOTS.items()})
    for name, (arm, model, task) in cells.items():
        session = SESSIONS / name
        work = session / "work"
        work.mkdir(parents=True)
        (session / "log").mkdir()
        (session / "session.json").write_text(json.dumps({"arm": arm, "model": model, "task": task["name"]}))
        for file, text in {"shop.mo": shop(arm), "STORE.md": (HERE / f"STORE-{arm}.md").read_text(),
                           "TASK.md": task_text(task), "example.mo": example_test(task)}.items():
            (work / file).write_text(text)
        (work / "mo").write_text(f'#!/bin/sh\nexec python3 {HERE / "mo.py"} "$(dirname "$0")/.." "$@"\n')
        (work / "mo").chmod(0o755)
        (session / "prompt.txt").write_text((HERE / "PROMPT.md").read_text().replace("WORK", str(work)))
        print(name, arm, model, task["name"])


def versions(session):
    """The distinct answers the session checked or tested, in order, and then the one it left behind."""
    texts = [entry.read_text() for entry in sorted((session / "log").glob("*/answer.mo"))]
    left = session / "work" / "answer.mo"
    texts += [left.read_text()] if left.exists() else []
    return [text for at, text in enumerate(texts) if at == 0 or text != texts[at - 1]]


def wilson(hits, n):
    if not n:
        return "0/0"
    z = 1.96
    centre, spread = hits / n + z * z / (2 * n), z * math.sqrt(hits * (n - hits) / n ** 3 + z * z / (4 * n * n))
    low, high = ((centre + sign * spread) / (1 + z * z / n) for sign in (-1, 1))
    return f"{hits}/{n} = {100 * hits / n:.0f}% ({100 * low:.0f} to {100 * high:.0f})"


def grade():
    rows = []
    for session in sorted(SESSIONS.iterdir()):
        meta = json.loads((session / "session.json").read_text())
        verdicts = [judged(meta["arm"], BY_NAME[meta["task"]], text) for text in versions(session)]
        valid = [verdict for verdict in verdicts if verdict["checks"] or verdict["refused"]]
        outputs = [entry.read_text() for entry in (session / "log").glob("*/output")]
        rows.append({"session": session.name, **meta, "runs": len(outputs), "versions": len(verdicts),
                     "ended good": bool(verdicts) and verdicts[-1]["good"],
                     "good within two repairs": any(verdict["good"] for verdict in valid[:3]),
                     "first valid version was accepted": bool(valid) and not valid[0]["refused"],
                     "met the rule's error": any("E9001" in output or "E0064" in output for output in outputs),
                     "walked at the end": verdicts[-1]["walked"] if verdicts else [],
                     "needless walk at the end": bool(verdicts) and verdicts[-1]["needless"],
                     "verdicts": verdicts})
    (OUT / "results.json").write_text(json.dumps(rows, indent=1))
    scored = [row for row in rows if not row["session"].startswith("p")]
    for arm, model in [(arm, None) for arm in ARMS] + list(itertools.product(ARMS, MODELS)):
        cell = [row for row in scored if row["arm"] == arm and model in (None, row["model"])]
        indexed = [row for row in cell if not BY_NAME[row["task"]]["walks"]]
        print(f"\narm {arm.upper()}{', ' + model if model else ''}: {len(cell)} sessions")
        for measure in ("good within two repairs", "ended good", "first valid version was accepted",
                        "met the rule's error"):
            print(f"  {measure}: {wilson(sum(row[measure] for row in cell), len(cell))}")
        print(f"  needless walk at the end, of the tasks an index answers: "
              f"{wilson(sum(row['needless walk at the end'] for row in indexed), len(indexed))}")
    print(f"\n{'task':15} " + " ".join(f"{arm.upper()}-{model:6}" for arm, model in itertools.product(ARMS, MODELS)))
    for task in TASKS:
        marks = []
        for arm, model in itertools.product(ARMS, MODELS):
            row = next((row for row in scored if (row["arm"], row["model"], row["task"]) == (arm, model, task["name"])), None)
            marks.append("-" if not row else ("good" if row["good within two repairs"] else
                                              "late" if row["ended good"] else "FAIL") + f"/{row['versions']}")
        print(f"{task['name']:15} " + " ".join(f"{mark:8}" for mark in marks))


if __name__ == "__main__":
    {"selfcheck": selfcheck, "setup": setup, "grade": grade}[sys.argv[1]]()
