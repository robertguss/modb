#!/usr/bin/env python3
"""Count the instructions of indexed reads and of walks at two store sizes, through mo query."""
import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("asked_again", HERE.parent / "kept-versions" / "asked-again.py")
asked = importlib.util.module_from_spec(spec)
spec.loader.exec_module(asked)
measure = asked.measure

OUT = HERE.parents[1] / "build" / "instruction-counts"
SOURCE = HERE / "main.mo"
SMALL, LARGE = (int(n) for n in sys.argv[2].split(","))
READS = ["index_one_row", "index_ten_rows", "index_growing_answer", "walk_loop", "walk_filter",
         "walk_values", "walk_keys", "walk_contains", "walk_reverse", "walk_unique"]
GROWS = 1.2
IN_STEP = 0.875


def exported(service, rows):
    export = OUT / f"state-{rows}.moex"
    subprocess.run([measure.MO, "fetch", f"http://127.0.0.1:{service.port}/mcp", "--export", "state",
                    "--out", str(export), "--token-env", "PERF_TOKEN"],
                   env={**os.environ, "PERF_TOKEN": measure.TOKEN}, check=True, capture_output=True)
    return export


def main():
    asked.SOURCE = measure.SOURCE = SOURCE
    measure.OUT, measure.DATA = OUT, OUT / "data"
    shutil.rmtree(OUT, ignore_errors=True)
    measure.DATA.mkdir(parents=True)
    service = measure.Service(first=True)
    costs, rows = {}, 0
    try:
        for target in (SMALL, LARGE):
            rows, _, stopped = measure.grow(service, rows, target, 250)
            assert not stopped, stopped
            export = exported(service, rows)
            costs[target] = {read: asked.cost(read, export) for read in READS}
            answers = {costs[target][read]["answer"] for read in ("index_ten_rows", "walk_loop", "walk_filter")}
            assert len(answers) == 1, answers
    finally:
        service.stop()
    table = {}
    print(f"{'read':22} {SMALL:>9} {LARGE:>9}  times  the count says  it is")
    for read in READS:
        small, large = (costs[size][read]["instructions"] for size in (SMALL, LARGE))
        times = large / small
        said = "walk" if times > GROWS else "indexed"
        truth = read.split("_")[0].replace("index", "indexed")
        table[read] = {"small": small, "large": large, "times": round(times, 2), "said": said, "truth": truth}
        print(f"{read:22} {small:9} {large:9} {times:6.2f}  {said:14}  {truth}{'' if said == truth else '   <- wrong'}")
    assert table["walk_loop"]["times"] >= IN_STEP * LARGE / SMALL, table["walk_loop"]
    wrong = [read for read, row in table.items() if row["said"] != row["truth"]]
    print(f"\nthe store grew {LARGE / SMALL:.0f} times; the count is wrong about {len(wrong)} of {len(READS)}: {wrong}")
    (OUT / "results.json").write_text(json.dumps({"load": os.getloadavg(), "costs": costs, "table": table}, indent=1))


if __name__ == "__main__":
    main()
