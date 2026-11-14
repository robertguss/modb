#!/usr/bin/env python3
"""The `mo` a trial session runs: the frozen binary, with every check and test recorded, and in arm A the stand-in rule."""
import json
import os
import pathlib
import shutil
import subprocess
import sys

import rule

session = pathlib.Path(sys.argv[1]).resolve()
arguments = sys.argv[2:]
binary = str(session.parents[1] / "mo")
if not arguments or arguments[0] not in ("check", "test"):
    os.execv(binary, [binary, *arguments])

answer = pathlib.Path("answer.mo")
status, output = 0, ""
if answer.exists() and json.loads((session / "session.json").read_text())["arm"] == "a":
    clean = subprocess.run([binary, "check", "answer.mo"], capture_output=True, text=True)
    found = rule.errors(answer.read_text()) if clean.returncode == 0 else []
    if found:
        status, output = 1, rule.report(found)
if not output:
    done = subprocess.run([binary, *arguments], capture_output=True, text=True)
    status, output = done.returncode, done.stdout + done.stderr

log = session / "log"
entry = log / f"{len(list(log.iterdir())) + 1:03}"
entry.mkdir()
(entry / "run.json").write_text(json.dumps({"arguments": arguments, "status": status}))
(entry / "output").write_text(output)
if answer.exists():
    shutil.copy(answer, entry / "answer.mo")
sys.stdout.write(output)
sys.exit(status)
