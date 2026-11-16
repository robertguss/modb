"""Experiment 16: the size of each file and what crosses from the policy to the collection."""
import pathlib
import re

HERE = pathlib.Path(__file__).parent
SHARED = {"ops", "fetch", "keep", "free"}


def code(text):
    kept, inside = [], False
    for line in text.splitlines():
        if line.startswith("test "):
            inside = True
        if not inside and line.strip() and not line.strip().startswith("#"):
            kept.append(line)
        if inside and line == "end":
            inside = False
    return kept


def functions(text):
    found, lines = {}, code(text)
    for i, line in enumerate(lines):
        m = re.match(r"fn (\w+\??)\(", line)
        if m:
            end = next(j for j in range(i, len(lines)) if lines[j] == "end")
            found[m.group(1)] = lines[i + 1:end]
    return found


def main():
    texts = {p.name: p.read_text() for p in sorted(HERE.glob("*.mo"))}
    for name, text in texts.items():
        print(f"{name}: {len(code(text))} lines of code")
    policy, nodes = texts["policy.mo"], texts["nodes.mo"]
    funs = functions(policy)
    print("policy calls from nodes.mo:", sorted(set(re.findall(r"Nodes\.([a-z]\w*\??)", policy))))
    print("policy calls through Ops:", sorted(set(re.findall(r"ops\.(\w+)\(", policy))))
    print("nodes.mo calls through Ops:", sorted(set(re.findall(r"ops\.(\w+)\(", nodes))))
    print("policy functions:", len(funs))
    print("  that open a node:", sorted(n for n, b in funs.items() if re.search(r"\b(Branch|Leaf)\(", "\n".join(b))))
    print("  that only pass their arguments on:", sorted(n for n, b in funs.items() if len(b) == 1 and b[0].strip().startswith("Nodes.")))
    print("  that take the store:", sum("store: S" in line for line in code(policy) if line.startswith("fn ")), "of", len(funs))
    b = functions(texts["backend-b.mo"])
    only = {n: len(body) + 2 for n, body in b.items() if n not in SHARED and n != "sound_after"}
    print("backend B only:", only, "total", sum(only.values()))
    print("backend B shared with A:", {n: len(b[n]) + 2 for n in sorted(SHARED)})
    a = functions(texts["backend-a.mo"])
    print("backend A shared with B:", {n: len(a[n]) + 2 for n in sorted(SHARED)})


if __name__ == "__main__":
    main()
