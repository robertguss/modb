"""Experiment 15: which Mo services hold state that grows, and which want history."""
import pathlib
import random
import re
import sys

MO = pathlib.Path.home() / "code" / "mo"
FOLDERS = ["examples", "services", "learnability"]
CORES = ["account", "rate-limit", "job-queue", "kv", "todo"]
HERE = pathlib.Path(__file__).parent
COLLECTION = re.compile(r"\b(List|Map|Set)\(")
ADDS = re.compile(r"\.(append|push|add|insert|set|concat)\(|\+\+|\+ \[")
HISTORY = re.compile(r"history|log|audit|undo|event|ledger|journal|revision|version", re.I)


def blocks(text, word):
    found = {}
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = re.match(rf"(?:pub )?{word} ([A-Z]\w*)", line)
        if m:
            end = next((j for j in range(i + 1, len(lines)) if lines[j] == "end"), len(lines))
            found[m.group(1)] = "\n".join(lines[i + 1:end])
    return found


def functions(text):
    found = {}
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r"(?:pub )?fn (\w+[?!]?)\(", line)
        if m:
            end = next((j for j in range(i, len(lines)) if lines[j] == "end"), len(lines))
            found[m.group(1)] = "\n".join(lines[i:end])
    return found


def expand(kind, types, seen=()):
    out = kind
    for name, body in types.items():
        if name not in seen and re.search(rf"\b{name}\b", kind):
            out += "\n" + expand(body, types, seen + (name,))
    return out


def service(text):
    m = re.search(r"^service\n(.*?)^end", text, re.M | re.S)
    if not m:
        return None
    block = m.group(1)
    state = re.search(r"^\s*state (.+?) =", block, re.M)
    tools = re.search(r"^\s*tools (.+?)(?=^\s*(?:every|token|promise)\b)", block, re.M | re.S)
    timers = re.findall(r"^\s*every .+ (\w+)\s*$", block, re.M)
    names = [n.strip() for n in tools.group(1).replace("\n", " ").split(",")] if tools else []
    return state.group(1).strip() if state else "", [n for n in names if n] + timers


def central(text):
    firsts = re.findall(r"^(?:pub )?fn \w+[?!]?\(\w+: ([A-Z]\w*)", text, re.M)
    return max(set(firsts), key=firsts.count) if firsts else ""


def label(text, kind, handlers):
    types = {**blocks(text, "struct"), **blocks(text, "enum")}
    full = expand(kind, types)
    holds = bool(COLLECTION.search(full))
    funs = functions(text)
    grows = holds and any(ADDS.search(funs.get(h, "")) for h in handlers)
    fields = " ".join(re.findall(r"^\s*(\w+):", full, re.M))
    wants = grows and bool(HISTORY.search(" ".join(handlers) + " " + fields))
    return {"holds": holds, "grows": grows, "history": wants, "key": (re.sub(r"\s+", " ", full), tuple(sorted(handlers)))}


def label_service(path):
    text = path.read_text()
    found = service(text)
    return None if found is None else label(text, found[0], found[1])


def check_controls():
    want = {"plain": (False, False, False), "lookup": (True, False, False), "ledger": (True, True, True)}
    for name, expected in want.items():
        got = label_service(HERE / "controls" / f"{name}.mo")
        assert (got["holds"], got["grows"], got["history"]) == expected, (name, got)
    print("controls: all three came out as planted")


def share(n, d):
    return f"{n} of {d} ({100 * n / d:.0f}%)" if d else "0 of 0"


def main():
    check_controls()
    if "--controls" in sys.argv:
        return
    files = sorted(p for f in FOLDERS for p in (MO / f).rglob("*.mo") if re.search(r"^service\b", p.read_text(), re.M))
    rows = [(p.relative_to(MO), label_service(p)) for p in files]
    total = len(rows)
    holds = sum(r["holds"] for _, r in rows)
    grows = [(p, r) for p, r in rows if r["grows"]]
    history = sum(r["history"] for _, r in grows)
    print(f"services: {total}")
    print(f"hold a collection: {share(holds, total)}")
    print(f"hold a collection that grows: {share(len(grows), total)}")
    print(f"of those that grow, want history: {share(history, len(grows))}")
    distinct = {}
    for _, r in rows:
        distinct.setdefault(r["key"], r)
    print(f"distinct services: {len(distinct)}; grow: {share(sum(r['grows'] for r in distinct.values()), len(distinct))}; "
          f"want history: {sum(r['history'] for r in distinct.values())}")
    print("example state cores:")
    for name in CORES:
        text = (MO / "examples" / f"{name}.mo").read_text()
        kind = central(text)
        r = label(text, kind, list(functions(text)))
        print(f"  {name}: state {kind}; holds {r['holds']}; grows {r['grows']}; history {r['history']}")
    print("each service:")
    for p, r in rows:
        print(f"  {p}: holds {r['holds']}; grows {r['grows']}; history {r['history']}")
    pick = random.Random(15)
    yes = [str(p) for p, r in rows if r["grows"]]
    no = [str(p) for p, r in rows if not r["grows"]]
    print("to read by hand, grows:", pick.sample(yes, min(10, len(yes))))
    print("to read by hand, does not grow:", pick.sample(no, min(5, len(no))))


if __name__ == "__main__":
    main()
