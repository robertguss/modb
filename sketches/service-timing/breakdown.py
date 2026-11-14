#!/usr/bin/env python3
"""Where one call's time goes: the server's processor time for each call, and which functions hold it."""
import collections
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time

import measure
from measure import DATA, Service, spread

TICKS = os.sysconf("SC_CLK_TCK")
IDLE = re.compile(r"futex|poll|accept|nanosleep|cond_wait")
FRAME = re.compile(r"^#\d+\s+(?:0x[0-9a-f]+ in )?([\w.@]+)", re.M)


def processor_ms(pid):
    fields = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) * 1000 / TICKS


def per_call(service, count, call):
    before = processor_ms(service.proc.pid)
    times = [call(i)[0] for i in range(count)]
    used = processor_ms(service.proc.pid) - before
    return {"client_ms": spread(times), "server_processor_ms_per_call": round(used / count, 2)}


def sample(service, count, call, gap):
    measure.GAP = gap
    stop = threading.Event()
    calls = collections.Counter()

    def fire():
        i = 0
        while not stop.is_set():
            calls["ok" if call(i)[1] else "refused"] += 1
            i += 1

    thread = threading.Thread(target=fire)
    thread.start()
    seen, busy = collections.Counter(), 0
    for _ in range(count):
        time.sleep(0.2)
        stacks = subprocess.run(["gdb", "-p", str(service.proc.pid), "-batch", "-ex", "thread apply all bt 18"],
                                capture_output=True, text=True).stdout
        for block in stacks.split("\nThread ")[1:]:
            frames = FRAME.findall(block)
            if frames and not IDLE.search(" ".join(frames[:3])):
                busy += 1
                seen.update(set(frames))
    stop.set()
    thread.join()
    return {"calls": dict(calls), "samples": count, "busy": busy,
            "share_of_busy": {name: round(n / max(busy, 1), 2) for name, n in seen.most_common(45)}}


def main():
    reads, writes = int(sys.argv[2]), int(sys.argv[3])
    shutil.rmtree(DATA, ignore_errors=True)
    DATA.mkdir(parents=True)
    service = Service(first=True)
    rows = 0
    get = lambda i: service.call("get", key=i % rows)
    put = lambda i: service.call("put", key=i % rows, value=f"changed {i}")
    for target in (1000, 100000):
        while rows < target:
            ms, ok, content = service.call("grow", step=min(20000, target - rows))
            assert ok, content
            rows = int(content["value"])
        print(json.dumps({"rows": rows, "read": per_call(service, 200, get),
                          "operator_tool": per_call(service, 200, lambda i: service.call("mo-memory")),
                          "write": per_call(service, 200, put)}), flush=True)
    print(json.dumps({"rows": rows, "read": sample(service, reads, get, measure.GAP)}), flush=True)
    print(json.dumps({"rows": rows, "write": sample(service, writes, put, 0)}), flush=True)
    service.stop()


if __name__ == "__main__":
    main()
