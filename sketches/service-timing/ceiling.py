#!/usr/bin/env python3
"""Find the largest state that still takes a write, time snapshots apart, and time a restart."""
import json
import pathlib
import shutil
import statistics
import time

import measure
from measure import DATA, OUT, Service


def main():
    shutil.rmtree(DATA, ignore_errors=True)
    DATA.mkdir(parents=True)
    service = Service(first=True)
    out = {"load_before": measure.os.getloadavg()}
    sequence = rows = 0
    while rows < 100000:
        ms, ok, content = service.call("grow", step=20000)
        assert ok, content
        rows, sequence = int(content["value"]), sequence + 1
    plain, snapshots = [], []
    for i in range(210):
        ms, ok, content = service.call("put", key=i, value="changed")
        assert ok, content
        sequence += 1
        (snapshots if sequence % 100 == 0 else plain).append(round(ms, 1))
    out["at_100000"] = {"put_median_ms": statistics.median(plain), "snapshot_put_ms": snapshots}
    for tool in ("mo-memory", "mo-overview"):
        ms, ok, content = service.call(tool)
        out[tool] = {"ms": round(ms, 1), "reply": json.dumps(content)[:900]}
    failures = []
    works = rows
    while len(failures) < 3:
        ms, ok, content = service.call("grow", step=5000)
        if ok:
            rows = int(content["value"])
            ms, ok, content = service.call("put", key=0, value="changed")
        if ok:
            works = rows
            out["at_ceiling"] = {"rows": rows, "put_ms": round(ms, 1),
                                 "memory_mib": round(service.memory_mib(), 1),
                                 "store_mib": round((DATA / "service.sqlite").stat().st_size / 2**20, 2)}
            continue
        failures.append({"rows": rows, "works_at": works, "reply": content})
        time.sleep(15)
    out["failures"] = failures
    ms, ok, content = service.call("mo-memory")
    out["mo-memory-at-end"] = json.dumps(content)[:900]
    service.stop()
    service = Service(first=False)
    out["restart_ms"] = round(service.start_ms, 1)
    out["first_get_after_restart_ms"] = round(service.call("get", key=0)[0], 1)
    service.stop()
    out["load_after"] = measure.os.getloadavg()
    (OUT / "ceiling.json").write_text(json.dumps(out, indent=1))
    print(json.dumps(out, indent=1))


main()
