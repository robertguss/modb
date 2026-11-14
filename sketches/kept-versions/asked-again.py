#!/usr/bin/env python3
"""Measure what asking a world's questions again costs, in a running service and through mo query."""
import json
import os
import pathlib
import shutil
import statistics
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "service-timing"))
import measure

OUT = HERE.parents[1] / "build" / "asked-again"
SOURCE = HERE / "asked-again.mo"
SIZES = [int(n) for n in sys.argv[2].split(",")]
LADDER = sorted({*range(100, 2001, 100), *range(2500, 12001, 500), *SIZES})
QUESTIONS = [("branch_total", 3), ("below", 105), ("bands", 100)]
FUNCTIONS = ["branch_total_3", "below_105", "bands_100", "prepared", "landed", "plain_built", "plain_summed"]
QUERY_LIMIT = 2**30
PAUSE = 16


def call(service, name, **arguments):
    """Five failures within a minute restart a service and three restarts stop it, so wait after each."""
    ms, ok, content = service.call(name, **arguments)
    if content.get("error", {}).get("kind") == "runtime":
        time.sleep(PAUSE)
    return ms, ok, content


def refused(content):
    error = content.get("error", {})
    return error.get("code") or error.get("value")


def world(service, questions, pair):
    """Opens a world, asks the questions, moves 1 from one account to the next and lands it."""
    number = int(call(service, "begin")[2]["value"])
    for name, argument in questions:
        ms, ok, content = call(service, "ask", world=number, question=name, argument=argument)
        if not ok:
            return {"fits": False, "stopped_at": f"ask {name}", "why": refused(content)}
    moved = call(service, "move", world=number, **{"from": 2 * pair, "to": 2 * pair + 1, "amount": 1})
    assert moved[1], moved
    ms, ok, content = call(service, "land", world=number)
    return {"fits": True, "land_ms": round(ms, 1)} if ok else \
        {"fits": False, "stopped_at": "land", "why": refused(content)}


def ask_alone(service, name, argument):
    number = int(call(service, "begin")[2]["value"])
    ms, ok, content = call(service, "ask", world=number, question=name, argument=argument)
    return {"fits": True, "ms": round(ms, 1)} if ok else {"fits": False, "why": refused(content)}


def in_service(service, rows, pair, gave_up):
    """Tries each thing at this size. A thing that did not fit at a smaller size is tried again only at SIZES."""
    things = {f"ask {name}": lambda name=name, argument=argument: ask_alone(service, name, argument)
              for name, argument in QUESTIONS}
    things["land one question"] = lambda: world(service, QUESTIONS[:1], pair)
    things["land three questions"] = lambda: world(service, QUESTIONS, pair + 1)
    point = {"rows": rows}
    for thing, attempt in things.items():
        if thing in gave_up and rows not in SIZES:
            continue
        point[thing] = attempt()
        if not point[thing]["fits"]:
            gave_up.add(thing)
    return point


def query(function, export, limit):
    began = time.perf_counter()
    done = subprocess.run([measure.MO, "query", str(SOURCE), function, "--export", str(export),
                           "--max-work", str(limit)], capture_output=True, text=True)
    return done.returncode, (time.perf_counter() - began) * 1000, done.stdout.strip()


def cost(function, export):
    """The fewest instructions at which the function finishes, and its time under the usual limit."""
    runs = [query(function, export, QUERY_LIMIT) for _ in range(5)]
    assert all(code == 0 for code, _, _ in runs), runs
    low, high = 0, QUERY_LIMIT
    while high - low > 1:
        middle = (low + high) // 2
        code = query(function, export, middle)[0]
        assert code in (0, 70), code
        low, high = (low, middle) if code == 0 else (middle, high)
    return {"instructions": high, "ms": round(statistics.median(ms for _, ms, _ in runs), 1),
            "answer": runs[0][2][:120]}


def through_query(service, rows):
    export = OUT / f"state-{rows}.moex"
    export.unlink(missing_ok=True)
    began = time.perf_counter()
    subprocess.run([measure.MO, "fetch", f"http://127.0.0.1:{service.port}/mcp", "--export", "state",
                    "--out", str(export), "--token-env", "PERF_TOKEN"],
                   env={**os.environ, "PERF_TOKEN": measure.TOKEN}, check=True, capture_output=True)
    fetch_ms = round((time.perf_counter() - began) * 1000)
    costs = {function: cost(function, export) for function in FUNCTIONS}
    assert costs["prepared"]["answer"] == "true" and costs["landed"]["answer"] == "true", costs
    return {"rows": rows, "export_bytes": export.stat().st_size, "fetch_ms": fetch_ms, "functions": costs}


def main():
    measure.SOURCE, measure.OUT, measure.DATA = SOURCE, OUT, OUT / "data"
    shutil.rmtree(OUT, ignore_errors=True)
    measure.DATA.mkdir(parents=True)
    service = measure.Service(first=True)
    results = {"load": os.getloadavg(), "service": [], "query": []}
    rows = pair = 0
    gave_up = set()
    try:
        for target in LADDER:
            rows, _, stopped = measure.grow(service, rows, target, 250)
            assert not stopped, stopped
            results["service"].append(in_service(service, rows, pair, gave_up))
            print(json.dumps(results["service"][-1]), flush=True)
            pair += 2
            if rows in SIZES:
                results["query"].append(through_query(service, rows))
                print(json.dumps(results["query"][-1]), flush=True)
    finally:
        service.stop()
        (OUT / "results.json").write_text(json.dumps(results, indent=1))


if __name__ == "__main__":
    main()
