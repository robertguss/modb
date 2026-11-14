#!/usr/bin/env python3
"""Does a read wait behind a write? Run after ceiling.py, on the state it left."""
import json
import statistics
import threading

from measure import Service


def main():
    service = Service(first=False)
    alone = [service.call("get", key=1)[0] for _ in range(30)]
    done = threading.Event()
    writes = []

    def write():
        while not done.is_set():
            writes.append(service.call("put", key=0, value="changed")[0])

    writer = threading.Thread(target=write)
    writer.start()
    beside = [service.call("get", key=1)[0] for _ in range(30)]
    done.set()
    writer.join()
    service.stop()
    print(json.dumps({"get_alone_ms": round(statistics.median(alone), 1),
                      "get_beside_writes_ms": round(statistics.median(beside), 1),
                      "get_beside_writes_max_ms": round(max(beside), 1),
                      "write_ms": round(statistics.median(writes), 1), "writes": len(writes)}))


main()
