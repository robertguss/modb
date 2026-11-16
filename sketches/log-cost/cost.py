#!/usr/bin/env python3
"""Measure the bytes a logged call takes in a Mo store and the time to run it again."""
import json
import os
import pathlib
import shutil
import sqlite3
import statistics
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "service-timing"))
MO = sys.argv[1]
SIZES = [int(n) for n in sys.argv[2].split(",")]
STARTS = int(sys.argv[3]) if len(sys.argv) > 3 else 15
sys.argv[1:] = [MO]
import measure as base

OUT = HERE.parents[1] / "build" / "log-cost"
base.SOURCE = HERE / "main.mo"
base.OUT = OUT
ROW = "0123456789012345678901234567890123456789012345678901234567890123"
TAIL = 99


def folder(name):
    return OUT / name


def serve(name, first=False):
    base.DATA = folder(name)
    return base.Service(first=first)


def kill(service):
    service.proc.kill()
    service.proc.wait(timeout=60)


def must(reply):
    assert reply[1], reply
    return reply


def store(name):
    copy = OUT / "reading"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(folder(name), copy)
    db = sqlite3.connect(copy / "service.sqlite")
    log = db.execute("SELECT seq, length(record) FROM log ORDER BY seq").fetchall()
    snapshot = db.execute("SELECT length(record) FROM snapshot").fetchone()[0]
    db.close()
    return log, snapshot


def processor_ms(pid):
    total = 0
    for task in pathlib.Path(f"/proc/{pid}/task").iterdir():
        total += int((task / "schedstat").read_text().split()[0])
    return total / 1e6


def prepare(size):
    empty, full, scratch = f"{size}-tail0", f"{size}-tail{TAIL}", f"{size}-bytes"
    for name in (empty, full, scratch):
        shutil.rmtree(folder(name), ignore_errors=True)
    folder(empty).mkdir(parents=True)
    service = serve(empty, first=True)
    rows, _, stopped = base.grow(service, 0, size, 20000)
    assert not stopped, stopped
    calls = sum(1 for _ in range(0, size, 20000)) if not base.REFUSALS else None
    assert calls, base.REFUSALS
    for i in range(100 - calls):
        must(service.call("put", key=i % size, value=ROW))
    kill(service)
    log, snapshot = store(empty)
    assert log == [], log
    shutil.copytree(folder(empty), folder(full))
    shutil.copytree(folder(empty), folder(scratch))
    service = serve(full)
    for i in range(TAIL):
        must(service.call("put", key=i % size, value=ROW[::-1]))
    kill(service)
    log, _ = store(full)
    assert len(log) == TAIL, len(log)
    return snapshot, sorted({length for _, length in log})


def measure_bytes(size):
    name = f"{size}-bytes"
    service = serve(name)
    values = {"7": "changed", "64": ROW[::-1], "1000": "x" * 1000}
    for value in values.values():
        must(service.call("put", key=0, value=value))
    after_puts_reads = [service.call("get", key=0)[1] for _ in range(5)]
    refusals = [service.call("refuse", key=0)[1] for _ in range(5)]
    kill(service)
    log, _ = store(name)
    return {"rows_after_3_puts_5_gets_5_refusals": len(log),
            "row_bytes": dict(zip(values, [length for _, length in log])),
            "gets_answered": sum(after_puts_reads), "refusals_answered_ok": sum(refusals)}


def starts(name, count):
    before = store(name)[0]
    clock, ready, processor = [], [], []
    for _ in range(count):
        began = time.perf_counter()
        service = serve(name)
        must(service.call("get", key=0))
        clock.append((time.perf_counter() - began) * 1000)
        ready.append(service.start_ms)
        processor.append(processor_ms(service.proc.pid))
        kill(service)
    assert store(name)[0] == before, name
    return {"log_rows": len(before), "processor_ms": base.spread(processor),
            "ready_ms": base.spread(ready), "clock_ms": base.spread(clock),
            "processor_all": [round(ms, 2) for ms in processor]}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = {"mo": MO, "starts": STARTS, "sizes": []}
    for size in SIZES:
        snapshot, tail_rows = prepare(size)
        entry = {"rows": size, "snapshot_bytes": snapshot, "tail_row_bytes": tail_rows,
                 "bytes": measure_bytes(size)}
        if STARTS:
            none, full = starts(f"{size}-tail0", STARTS), starts(f"{size}-tail{TAIL}", STARTS)
            gap = full["processor_ms"]["median"] - none["processor_ms"]["median"]
            entry.update({"tail0": none, f"tail{TAIL}": full,
                          "replay_ms_per_call": round(gap / TAIL, 4)})
        results["sizes"].append(entry)
        print(json.dumps({k: v for k, v in entry.items()}, default=str)[:900], flush=True)
    results["load"] = os.getloadavg()
    (HERE / "results" / "cost-19.json").write_text(json.dumps(results, indent=1))


if __name__ == "__main__":
    main()
