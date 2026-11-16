#!/usr/bin/env python3
"""Processor time of a live put and a live get at one state size, to set beside the replay time."""
import json
import shutil
import sys

sys.argv[1:] = [sys.argv[1], sys.argv[2], "0"]
import cost

SIZE = cost.SIZES[0]


def per_call(service, tool, count, **arguments):
    before = cost.processor_ms(service.proc.pid)
    for i in range(count):
        cost.must(service.call(tool, key=i % SIZE, **arguments))
    return round((cost.processor_ms(service.proc.pid) - before) / count, 3)


def main():
    name = f"{SIZE}-live"
    shutil.rmtree(cost.folder(name), ignore_errors=True)
    shutil.copytree(cost.folder(f"{SIZE}-tail0"), cost.folder(name))
    service = cost.serve(name)
    result = {"rows": SIZE, "get_processor_ms": per_call(service, "get", 50),
              "put_processor_ms": per_call(service, "put", 50, value=cost.ROW)}
    cost.kill(service)
    (cost.HERE / "results" / f"live-19-{SIZE}.json").write_text(json.dumps(result))
    print(result)


if __name__ == "__main__":
    main()
