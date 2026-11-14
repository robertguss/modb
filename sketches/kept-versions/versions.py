#!/usr/bin/env python3
"""Measure the saved size and the write time of three ways to keep old versions in a Mo service."""
import json
import os
import pathlib
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "service-timing"))
import measure

OUT = HERE.parents[1] / "build" / "kept-versions"
SOURCES = {"by-number": HERE / "by-number.mo", "by-reference": HERE / "by-reference.mo",
           "whole-maps": HERE / "whole-maps.mo", "plain-map": HERE.parent / "service-timing" / "main.mo"}
STEPS = {"by-number": 400, "by-reference": 400, "whole-maps": 20000, "plain-map": 20000}
ROW = "0123456789012345678901234567890123456789012345678901234567890123"
ROWS = [int(n) for n in sys.argv[2].split(",")]
KEPT = [int(n) for n in sys.argv[3].split(",")]


def memory(service):
    value = service.call("mo-memory")[2]["value"]
    return {"saved_bytes": int(value["encoded_state_bytes"]), "heap_bytes": int(value["heap_used"])}


def run(variant, rows):
    measure.SOURCE, measure.OUT, measure.DATA = SOURCES[variant], OUT, OUT / "data"
    shutil.rmtree(measure.DATA, ignore_errors=True)
    measure.DATA.mkdir(parents=True)
    service = measure.Service(first=True)
    grown, _, stopped = measure.grow(service, 0, rows, STEPS[variant])
    result = {"variant": variant, "rows": grown, "points": [{"puts": 0, **memory(service)}]}
    if stopped:
        result["stopped_growing"] = stopped
    puts, times = 0, []
    for target in KEPT:
        while puts < target and "refused" not in result and not stopped:
            ms, ok, content = service.call("put", key=(puts * 37) % rows, value=f"changed {puts}")
            if ok:
                puts += 1
                times.append(ms)
            else:
                result["refused"] = {"after_puts": puts, "reply": content}
        if times:
            result["points"].append({"puts": puts, **memory(service), "put_ms": measure.spread(times)})
        times = []
    service.stop()
    if variant != "plain-map" and puts:
        service = measure.Service(first=False)
        result["after_restart"] = {
            "oldest_version_has_the_first_row": service.call("old", version=0, key=0)[2].get("value") == ROW,
            "newest_version_has_the_change": service.call("get", key=0)[2].get("value") == "changed 0",
            **memory(service)}
        service.stop()
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for rows in ROWS:
        for variant in SOURCES:
            results.append(run(variant, rows))
            print(json.dumps(results[-1])[:1500], flush=True)
    (OUT / "versions.json").write_text(json.dumps({"load": os.getloadavg(), "runs": results}, indent=1))


if __name__ == "__main__":
    main()
