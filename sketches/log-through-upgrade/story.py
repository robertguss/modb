#!/usr/bin/env python3
"""Send a story of calls to real services across two upgrades, then run the record again in Mo."""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "service-timing"))
MO = str(pathlib.Path(sys.argv[1]).resolve())
sys.argv[1:] = [MO]
import measure as base

OUT = HERE.parents[1] / "build" / "log-through-upgrade"
TOKEN = base.TOKEN
NAMES = ["x", "y", "z"]
STORY = [
    (1, "a", "add", {"name": "x", "n": 10}),
    (1, "b", "add", {"name": "y", "n": 5}),
    (1, "c", "add", {"name": "z", "n": 2}),
    (1, "b", "move", {"giver": "y", "taker": "x", "n": 3}),
    (1, "a", "move", {"giver": "x", "taker": "z", "n": 12}),
    (1, "c", "move", {"giver": "z", "taker": "y", "n": 20}),
    (1, "a", "add", {"name": "x", "n": 4}),
    (1, "b", "add", {"name": "z", "n": 1}),
    (1, "c", "add", {"name": "y", "n": 1}),
    (1, "a", "move", {"giver": "y", "taker": "x", "n": 3}),
    (2, "a", "add", {"name": "x", "n": 2}),
    (2, "b", "move", {"giver": "x", "taker": "z", "n": 4}),
    (2, "c", "move", {"giver": "z", "taker": "y", "n": 1}),
    (2, "a", "move", {"giver": "y", "taker": "z", "n": 5}),
    (2, "c", "move", {"giver": "z", "taker": "x", "n": 3}),
    (2, "b", "add", {"name": "y", "n": 2}),
    (2, "a", "move", {"giver": "x", "taker": "y", "n": 9}),
    (2, "c", "add", {"name": "z", "n": 7}),
    (2, "b", "move", {"giver": "y", "taker": "x", "n": 30}),
    (2, "a", "add", {"name": "x", "n": 1}),
    (3, "a", "move", {"giver": "y", "taker": "x", "n": 6}),
    (3, "b", "move", {"giver": "z", "taker": "x", "n": 2}),
    (3, "c", "add", {"name": "y", "n": 3}),
    (3, "a", "move", {"giver": "x", "taker": "z", "n": 9}),
    (3, "c", "move", {"giver": "x", "taker": "y", "n": 1}),
    (3, "b", "add", {"name": "x", "n": 5}),
    (3, "a", "move", {"giver": "z", "taker": "y", "n": 5}),
    (3, "c", "move", {"giver": "y", "taker": "z", "n": 8}),
    (3, "b", "move", {"giver": "x", "taker": "y", "n": 5}),
    (3, "a", "add", {"name": "z", "n": 1}),
]
CALLS = [(index + 1, *call) for index, call in enumerate(STORY)]


class Service(base.Service):
    def __init__(self, data, source, extra):
        command = [MO, "serve", str(source), "--port", "0", "--data", str(data)] + extra
        self.errors = OUT / "serve.err"
        self.proc = subprocess.Popen(command, env={**os.environ, "BOOK_TOKEN": TOKEN},
                                     stdout=subprocess.PIPE, stderr=open(self.errors, "a"),
                                     text=True)
        said, found = [], None
        while not found:
            line = self.proc.stdout.readline()
            if not line:
                self.proc.wait(timeout=60)
                raise RuntimeError("".join(said) + self.errors.read_text()[-2000:])
            said.append(line)
            found = re.search(r":(\d+)/mcp", line)
        self.port = int(found.group(1))
        self.next_id = 0
        self.post({"jsonrpc": "2.0", "id": 0, "method": "initialize",
                   "params": {"protocolVersion": "2025-11-25", "capabilities": {},
                              "clientInfo": {"name": "story", "version": "1"}}})
        self.post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def raw(self, tool, arguments):
        self.next_id += 1
        _ms, status, data = self.post(
            {"jsonrpc": "2.0", "id": self.next_id, "method": "tools/call",
             "params": {"name": tool, "arguments": {k: str(v) for k, v in arguments.items()}}})
        reply = json.loads(data) if data else {}
        result = reply.get("result", {})
        ok = status == 200 and "result" in reply and not result.get("isError")
        return ok, result.get("structuredContent", reply)


def reply_text(ok, content):
    if ok:
        return str(content["value"])
    return "error " + str(content.get("error", {}).get("value", json.dumps(content, sort_keys=True)))


def real(name, calls, versions):
    data = OUT / name
    shutil.rmtree(data, ignore_errors=True)
    data.mkdir(parents=True)
    replies, steps = {}, []
    for place, version in enumerate(versions):
        extra = [] if place == 0 else ["--upgrade"]
        if place and version == 3:
            extra += ["--migrate", "Book.from_v2"]
        command = " ".join(["mo serve", f"v{version}/main.mo", "--data DIR"] + extra)
        try:
            service = Service(data, HERE / f"v{version}" / "main.mo", extra)
        except RuntimeError as refused:
            held = re.findall(r"restart with --review ([0-9a-f]{64})", str(refused))
            if not held:
                raise
            steps.append(command + "  (refused with E1435: the upgrade waits for review)")
            command += " --review ID"
            service = Service(data, HERE / f"v{version}" / "main.mo", extra + ["--review", held[-1]])
        steps.append(command)
        for index, at, _caller, tool, arguments in calls:
            if at == version or (place == 0 and at < version):
                ok, content = service.raw(tool, arguments)
                replies[index] = reply_text(ok, content)
        if version == 3:
            state = {name: int(service.raw("tally", {"name": name})[1]["value"]) for name in NAMES}
            state["moves"] = int(service.raw("moves", {})[1]["value"])
        service.stop()
    return {"steps": steps, "replies": replies, "state": state}


def module_named(source, name, old_use=None):
    text = source.read_text().replace("module Book\n", f"module {name}\n", 1)
    if old_use:
        text = text.replace("use UpgradeOld\n", f"use {old_use}\n").replace("UpgradeOld.", f"{old_use}.")
    return text


def calls_module():
    lines = ["## The record of calls, written out by story.py.", "module Calls",
             "expose Call(..), Tool(..), story", "", "enum Tool", "  Add(name: Text, n: Int)",
             "  Move(giver: Text, taker: Text, n: Int)", "end", "", "struct Call", "  index: Int",
             "  version: Int", "  caller: Text", "  tool: Tool", "end", "", "story = ["]
    for index, version, caller, tool, a in CALLS:
        made = (f'Add(name: "{a["name"]}", n: {a["n"]})' if tool == "add" else
                f'Move(giver: "{a["giver"]}", taker: "{a["taker"]}", n: {a["n"]})')
        lines.append(f'  Call(index: {index}, version: {version}, caller: "{caller}", tool: {made}),')
    return "\n".join(lines + ["]", ""])


def check(folder, file):
    done = subprocess.run([MO, "check", file], cwd=folder, capture_output=True, text=True)
    return {"exit": done.returncode, "says": (done.stdout + done.stderr).strip()[:600]}


def same_name():
    tried = {}
    folder = OUT / "same-name-a"
    shutil.rmtree(folder, ignore_errors=True)
    for version in (1, 2):
        (folder / f"v{version}").mkdir(parents=True)
        shutil.copy(HERE / f"v{version}" / "book.mo", folder / f"v{version}" / "book.mo")
    (folder / "main.mo").write_text("module Main\nuse Book\n\nfn main(console: Console)\n"
                                    "  console.print(\"#{Book.empty.tallies.size}\")\nend\n")
    tried["two files that each say `module Book`, in folders v1 and v2"] = check(folder, "main.mo")
    folder = OUT / "same-name-b"
    shutil.rmtree(folder, ignore_errors=True)
    for version in (1, 2):
        (folder / f"v{version}").mkdir(parents=True)
        (folder / f"v{version}" / "book.mo").write_text(
            module_named(HERE / f"v{version}" / "book.mo", f"V{version}.Book"))
    (folder / "main.mo").write_text("module Main\nuse V1.Book\nuse V2.Book\n\nfn main(console: Console)\n"
                                    "  console.print(\"#{Book.empty.tallies.size}\")\nend\n")
    tried["`module V1.Book` and `module V2.Book`, both used by one module"] = check(folder, "main.mo")
    return tried


def rebuild_folder():
    folder = OUT / "rebuild"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    (folder / "book1.mo").write_text(module_named(HERE / "v1" / "book.mo", "Book1"))
    (folder / "book2.mo").write_text(module_named(HERE / "v2" / "book.mo", "Book2"))
    (folder / "book3.mo").write_text(module_named(HERE / "v3" / "book.mo", "Book3", "Book2"))
    (folder / "calls.mo").write_text(calls_module())
    shutil.copy(HERE / "rebuild.mo", folder / "rebuild.mo")
    return folder


def rebuilt(folder, job):
    done = subprocess.run([MO, "run", "rebuild.mo", job], cwd=folder, capture_output=True, text=True)
    assert done.returncode == 0, done.stdout + done.stderr
    replies, state = {}, {}
    for line in done.stdout.splitlines():
        kind, rest = line.split(" ", 1)
        if kind == "reply":
            index, text = rest.split(" ", 1)
            replies[int(index)] = text
        elif kind == "tally":
            name, count = rest.split(" ")
            state[name] = int(count)
        else:
            state["moves"] = int(rest)
    return {"replies": replies, "state": state}


def no_upgrade_function(folder):
    control = OUT / "control-no-upgrade"
    shutil.rmtree(control, ignore_errors=True)
    shutil.copytree(folder, control)
    text = (control / "rebuild.mo").read_text()
    assert text.count("Book3.from_v2(two)") == 2
    (control / "rebuild.mo").write_text(text.replace("Book3.from_v2(two)", "two"))
    return check(control, "rebuild.mo")


def changed(before, after):
    return sorted(index for index in after if before[index] != after[index])


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    without_b = [call for call in CALLS if call[2] != "b"]
    services = {"upgraded twice": real("real-full", CALLS, [1, 2, 3]),
                "never sent b's calls": real("real-without-b", without_b, [1, 2, 3]),
                "began on version 2": real("real-began-on-2", CALLS, [2, 3])}
    folder = rebuild_folder()
    runs = {job: rebuilt(folder, job) for job in ("faithful", "without-b", "fixed", "newest")}
    full = services["upgraded twice"]
    results = {
        "same_name": same_name(),
        "services": services,
        "rebuilds": runs,
        "faithful_same_state": runs["faithful"]["state"] == full["state"],
        "faithful_same_replies": runs["faithful"]["replies"] == full["replies"],
        "without_b_same_replies": runs["without-b"]["replies"] == services["never sent b's calls"]["replies"],
        "fixed_same_replies": runs["fixed"]["replies"] == services["began on version 2"]["replies"],
        "without_b_same_state": runs["without-b"]["state"] == services["never sent b's calls"]["state"],
        "fixed_same_state": runs["fixed"]["state"] == services["began on version 2"]["state"],
        "control_newest_differs": runs["newest"]["state"] != full["state"],
        "control_without_b_differs": runs["without-b"]["state"] != runs["faithful"]["state"],
        "control_no_upgrade_function": no_upgrade_function(folder),
        "calls_changed_without_b": changed(runs["faithful"]["replies"], runs["without-b"]["replies"]),
        "calls_changed_by_fix": changed(runs["faithful"]["replies"], runs["fixed"]["replies"]),
        "story": [{"index": i, "version": v, "caller": c, "tool": t, "arguments": a}
                  for i, v, c, t, a in CALLS],
    }
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "story-18.json").write_text(json.dumps(results, indent=1))
    for key, value in results.items():
        if key not in ("services", "rebuilds", "story"):
            print(key, json.dumps(value)[:500])
    for name, run in list(services.items()) + list(runs.items()):
        print(name, run["state"])


if __name__ == "__main__":
    main()
