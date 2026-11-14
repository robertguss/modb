#!/usr/bin/env python3
"""Time one insert and one lookup on a Map and on the tree by number, outside a service.

A Map is so much faster that its jobs run ten times as many rows, to rise above the time to start `mo`.
"""
import json
import os
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
MO = sys.argv[1]
SIZES = [int(n) for n in sys.argv[2].split(",")]
RUNS = 5
MAP_TIMES = 10


def seconds(job, count):
    best = None
    count = count * MAP_TIMES if job.startswith("map") else count
    for _ in range(RUNS):
        began = time.perf_counter()
        out = subprocess.run([MO, "run", str(HERE / "ops.mo"), job, str(count)],
                             capture_output=True, text=True, check=True).stdout
        took = time.perf_counter() - began
        best = took if best is None else min(best, took)
    return best, out.split()[-1]


def main():
    results = []
    for count in SIZES:
        took = {job: seconds(job, count) for job in
                ("none", "map-put", "map-get", "tree-put", "tree-get", "tree-keep")}
        def each(job, base):
            done = count * MAP_TIMES if job.startswith("map") else count
            return round((took[job][0] - took[base][0]) / done * 1e6, 2)

        row = {"rows": count,
               "map_insert_us": each("map-put", "none"), "map_lookup_us": each("map-get", "map-put"),
               "tree_insert_us": each("tree-put", "none"), "tree_lookup_us": each("tree-get", "tree-put"),
               "tree_insert_keeping_us": each("tree-keep", "tree-put"),
               "nodes": int(took["tree-put"][1]), "nodes_after_keeping_every_insert": int(took["tree-keep"][1])}
        row["insert_times_map"] = round(row["tree_insert_us"] / row["map_insert_us"], 1)
        row["lookup_times_map"] = round(row["tree_lookup_us"] / row["map_lookup_us"], 1)
        results.append(row)
        print(json.dumps(row), flush=True)
    out = HERE.parents[1] / "build" / "kept-versions"
    out.mkdir(parents=True, exist_ok=True)
    (out / "ops.json").write_text(json.dumps({"load": os.getloadavg(), "sizes": results}, indent=1))


if __name__ == "__main__":
    main()
