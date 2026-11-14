#!/usr/bin/env python3
"""Time one message of a Mo service at several state sizes, and find the largest state."""
import http.client
import json
import os
import pathlib
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
MO = sys.argv[1]
SOURCE = HERE / "main.mo"
OUT = HERE.parents[1] / "build" / "service-timing"
DATA = OUT / "data"
TOKEN = "perf-token-1234567890"
GAP = 0.06
REFUSALS = []
HEADERS = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json",
           "MCP-Protocol-Version": "2025-11-25"}


class Service:
    def __init__(self, first):
        command = [MO, "serve"] + ([str(SOURCE)] if first else []) + \
                  ["--port", "0", "--data", str(DATA)]
        began = time.perf_counter()
        self.proc = subprocess.Popen(command, env={**os.environ, "PERF_TOKEN": TOKEN},
                                     stdout=subprocess.PIPE, stderr=open(OUT / "serve.err", "a"),
                                     text=True)
        line = self.proc.stdout.readline()
        self.start_ms = (time.perf_counter() - began) * 1000
        self.port = int(re.search(r":(\d+)/mcp", line).group(1))
        self.next_id = 0
        self.post({"jsonrpc": "2.0", "id": 0, "method": "initialize",
                   "params": {"protocolVersion": "2025-11-25", "capabilities": {},
                              "clientInfo": {"name": "measure", "version": "1"}}})
        self.post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def post(self, body):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=300)
        began = time.perf_counter()
        conn.request("POST", "/mcp", json.dumps(body), HEADERS)
        response = conn.getresponse()
        data = response.read()
        ms = (time.perf_counter() - began) * 1000
        conn.close()
        time.sleep(GAP)
        return ms, response.status, data

    def call(self, name, **arguments):
        self.next_id += 1
        ms, status, data = self.post(
            {"jsonrpc": "2.0", "id": self.next_id, "method": "tools/call",
             "params": {"name": name, "arguments": {k: str(v) for k, v in arguments.items()}}})
        reply = json.loads(data) if data else {}
        result = reply.get("result", {})
        ok = status == 200 and "result" in reply and not result.get("isError")
        return ms, ok, result.get("structuredContent", reply)

    def memory_mib(self):
        status = pathlib.Path(f"/proc/{self.proc.pid}/status").read_text()
        return int(re.search(r"VmRSS:\s+(\d+)", status).group(1)) / 1024

    def stop(self):
        self.proc.send_signal(signal.SIGTERM)
        self.proc.wait(timeout=60)


def spread(times):
    ordered = sorted(times)
    return {"min": round(ordered[0], 3), "median": round(statistics.median(ordered), 3),
            "p90": round(ordered[int(len(ordered) * 0.9)], 3), "max": round(ordered[-1], 3)}


def grow(service, rows, target, step):
    while rows < target:
        want = min(step, target - rows)
        ms, ok, content = service.call("grow", step=want)
        if not ok:
            REFUSALS.append({"rows": rows, "step": want, "ms": round(ms, 1), "reply": content})
            print(json.dumps(REFUSALS[-1])[:300], flush=True)
            if want == 1:
                return rows, step, content
            step = max(1, want // 2)
            time.sleep(15)
            continue
        rows = int(content["value"])
    return rows, step, None


def measure(service, rows):
    gets = [service.call("get", key=i % max(rows, 1))[0] for i in range(40)]
    puts = []
    for i in range(210):
        ms, ok, content = service.call("put", key=i % max(rows, 1), value="changed")
        assert ok, content
        puts.append(ms)
    slowest = sorted(range(len(puts)), key=lambda i: -puts[i])[:3]
    return {"rows": int(content["value"]), "get_ms": spread(gets), "put_ms": spread(puts),
            "slowest_puts": [(i, round(puts[i], 2)) for i in slowest],
            "memory_mib": round(service.memory_mib(), 1),
            "store_mib": round((DATA / "service.sqlite").stat().st_size / 2**20, 2)}


def main():
    shutil.rmtree(DATA, ignore_errors=True)
    DATA.mkdir(parents=True)
    service = Service(first=True)
    results = {"sizes": [], "start_ms_empty": round(service.start_ms, 1)}
    rows, step, stopped = 0, 20000, None
    for target in (int(n) for n in sys.argv[2].split(",")):
        rows, step, stopped = grow(service, rows, target, step)
        if stopped:
            break
        results["sizes"].append(measure(service, rows))
        print(json.dumps(results["sizes"][-1]), flush=True)
    results["largest"] = {"rows": rows, "refusals": REFUSALS, "load": os.getloadavg()}
    service.stop()
    service = Service(first=False)
    results["start_ms_largest"] = round(service.start_ms, 1)
    results["get_after_restart"] = service.call("get", key=0)[1:]
    service.stop()
    (OUT / "results.json").write_text(json.dumps(results, indent=1))
    print(json.dumps({k: v for k, v in results.items() if k != "sizes"}))


if __name__ == "__main__":
    main()
