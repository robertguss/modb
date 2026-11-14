#!/usr/bin/env python3
"""Count the code that picks rows from a collection, and how much of it is in a shape a compiler could turn into an index lookup."""
import collections
import hashlib
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parents[1] / "build" / "shape-census"
CALL = re.compile(r"\.(filter|find|count|any\?)\(")
FOR = re.compile(r"\s*for (.+?) in (.+)$")
NAME = re.compile(r"[A-Za-z_]\w*")
NAMED = re.compile(r"([A-Za-z_][\w.]*[?!]?)\)")
LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)\'')
TEXT = re.compile(r"\.(chars|lines|words|enumerate)$|\.split\([^)]*\)$")
POSTFIX = re.compile(r"(?:return|continue|break)\b.*?\bif (.+)$")
OPERATORS = ("==", "<=", ">=", "<", ">")
FOUND = ("equal", "range")


def indent(line):
    return len(line) - len(line.lstrip())


def block(lines, at):
    """The lines under lines[at]: every following line indented deeper than it."""
    inner = []
    for line in lines[at + 1:]:
        if line.strip() and indent(line) <= indent(lines[at]):
            break
        inner.append(line)
    return inner


def fields(texts):
    """The field names of every struct declared in these files."""
    names = set()
    for text in texts:
        lines = text.splitlines()
        for at, line in enumerate(lines):
            if re.match(r"\s*struct \w", line):
                names.update(m.group(1) for inner in block(lines, at) if (m := re.match(r"\s+(\w+): ", inner)))
    return names


def split(text, word):
    """Splits on `word` where it stands outside every bracket."""
    parts, depth, start = [], 0, 0
    for m in re.finditer(rf"[(\[{{]|[)\]}}]|\b{word}\b", text):
        if m.group() in "([{":
            depth += 1
        elif m.group() in ")]}":
            depth -= 1
        elif depth == 0:
            parts.append(text[start:m.start()])
            start = m.end()
    return parts + [text[start:]]


def mentions(text, rows):
    return any(re.search(rf"\b{re.escape(row)}\b", text) for row in rows)


def row_path(side, rows, known):
    parts = side.strip().split(".")
    return parts[0] in rows and all(part in known or part.isdigit() for part in parts[1:])


def indexable(part, rows, known):
    """A stored field, or the row itself, compared with a value that does not depend on the row."""
    part = part.strip()
    while part.startswith("(") and part.endswith(")"):
        part = part[1:-1].strip()
    if "!=" in part or part.startswith("not "):
        return None
    for operator in OPERATORS:
        if operator in part:
            left, right = part.split(operator, 1)
            if any(row_path(row, rows, known) and not mentions(other, rows)
                   for row, other in ((left, right), (right, left))):
                return "equal" if operator == "==" else "range"
            return None
    return "equal" if "." in part and row_path(part, rows, known) else None


def shape(test, rows, known):
    test = LITERAL.sub('""', test)
    if len(split(test, "or")) > 1:
        return "miss: or"
    kinds = [indexable(part, rows, known) for part in split(test, "and")]
    for kind in FOUND:
        if kind in kinds:
            return kind
    return "miss: negation" if re.search(r"!=|\bnot\b", test) else "miss: a call or a computed value on the row"


def call_sites(lines, known):
    for at, line in enumerate(lines):
        if line.strip().startswith("#"):
            continue
        for m in CALL.finditer(line):
            rest = line[m.end():]
            if rest.startswith("fn("):
                rows = NAME.findall(rest[3:rest.index(")")])
                after = rest[rest.index(")") + 1:]
                if re.search(r"\bend\b", after):
                    body = [re.split(r"\bend\b", after)[0]]
                else:
                    body = [inner for inner in block(lines, at) if inner.strip()]
                result = shape(body[0], rows, known) if len(body) == 1 else "miss: a test of several lines"
            elif (named := NAMED.match(rest)) and (m.group(1) != "find" or named.group(1).endswith("?")):
                result = "miss: a named function"
            else:
                continue
            yield {"line": at + 1, "kind": "call", "over": line[:m.start()].strip(), "text": line.strip(),
                   "shape": result}


def own(body):
    """The loop's lines, without the lines of any loop inside it."""
    skip = 0
    for at, line in enumerate(body):
        if skip:
            skip -= 1
        else:
            yield line
            if FOR.match(line):
                skip = len(block(body, at))


def loop_sites(lines, known, tally):
    for at, line in enumerate(lines):
        header = FOR.match(line)
        if not header or line.strip().startswith("#"):
            continue
        rows = [name for name in NAME.findall(header.group(1)) if name != "_"]
        over = header.group(2).strip()
        if ".." in over or over.startswith("["):
            tally["loops over a range or a written-out list"] += 1
            continue
        body = block(lines, at)
        tests = []
        for inner in own(body):
            text = inner.strip()
            if text.startswith(("if ", "else if ")):
                tests.append(text.split("if ", 1)[1].split(": ")[0])
            elif m := POSTFIX.match(text):
                tests.append(m.group(1))
        tests = [test for test in tests if mentions(test, rows)]
        if not tests:
            tally["loops with no test on the row"] += 1
            continue
        top = [inner.strip() for inner in body if inner.strip() and indent(inner) == indent(line) + 2]
        one_if = len(top) == 2 and top[0].startswith("if ") and ": " not in top[0] and top[1] == "end"
        result = shape(tests[0], rows, known) if one_if else "miss: the loop does more than one if"
        yield {"line": at + 1, "kind": "loop", "over": over, "text": f"{line.strip()} | {' | '.join(tests)}",
               "shape": result, "some test": any(shape(test, rows, known) in FOUND for test in tests)}


def census(root):
    """Every site in the Mo files under root, once for each distinct file."""
    by_folder = collections.defaultdict(list)
    for path in sorted(root.rglob("*.mo")):
        by_folder[path.parent].append(path)
    seen, sites, tally = set(), [], collections.Counter()
    for folder, paths in by_folder.items():
        texts = {path: path.read_text() for path in paths}
        known = fields(texts.values())
        for path, text in texts.items():
            tally["files"] += 1
            digest = hashlib.sha256(text.encode()).hexdigest()
            if digest in seen:
                continue
            seen.add(digest)
            tally["distinct files"] += 1
            lines = text.splitlines()
            for site in [*call_sites(lines, known), *loop_sites(lines, known, tally)]:
                sites.append({"file": str(path.relative_to(root)), **site})
    return sites, tally


def distinct(sites):
    return list({(site["kind"], site["text"]): site for site in sites}.values())


def share(sites):
    """How many sites, how many are library calls in a shape, and how many more are loops in a shape."""
    calls = sum(site["kind"] == "call" and site["shape"] in FOUND for site in sites)
    loops = sum(site["kind"] == "loop" and site["shape"] in FOUND for site in sites)
    return {"sites": len(sites), "library calls only": calls, "with loops of one if": calls + loops,
            "by equality alone": sum(site["shape"] == "equal" for site in sites),
            "with any loop that has a test in a shape": calls + sum(site.get("some test", False) for site in sites)}


def percent(part, whole):
    return f"{part}/{whole} = {100 * part / whole:.0f}%" if whole else "0/0"


def report(name, sites, tally):
    records = [site for site in sites if not TEXT.search(site["over"])]
    result = {"tally": dict(tally), "kinds": dict(collections.Counter(site["kind"] for site in sites)),
              "distinct sites": share(distinct(sites)), "every site": share(sites),
              "distinct sites, not over text": share(distinct(records)),
              "shapes of distinct sites": dict(collections.Counter(site["shape"] for site in distinct(sites)))}
    print(f"\n{name}: {tally['files']} files, {tally['distinct files']} distinct")
    for key in ("loops over a range or a written-out list", "loops with no test on the row"):
        print(f"  not counted, {key}: {tally[key]}")
    for key in ("distinct sites", "every site", "distinct sites, not over text"):
        row = result[key]
        print(f"  {key}: library calls only {percent(row['library calls only'], row['sites'])}; "
              f"with loops of one if {percent(row['with loops of one if'], row['sites'])}; "
              f"by equality alone {percent(row['by equality alone'], row['sites'])}; "
              f"with any loop that has a test in a shape "
              f"{percent(row['with any loop that has a test in a shape'], row['sites'])}")
    for kind, count in sorted(result["shapes of distinct sites"].items(), key=lambda item: -item[1]):
        print(f"    {count:4} {kind}")
    return result


def controls():
    """The planted misses must be found and all missed; the planted hits must all be recognised."""
    misses, _ = census(HERE / "controls" / "misses")
    hits, _ = census(HERE / "controls" / "hits")
    assert len(misses) == 10 and not any(site["shape"] in FOUND for site in misses), misses
    assert len(hits) == 8 and all(site["shape"] in FOUND for site in hits), hits
    assert share(hits)["library calls only"] == 5, hits
    print(f"controls: {len(misses)} planted misses, 0 recognised; {len(hits)} planted hits, {len(hits)} recognised")


def main():
    controls()
    OUT.mkdir(parents=True, exist_ok=True)
    results = {}
    for root in map(pathlib.Path, sys.argv[1:]):
        sites, tally = census(root)
        results[root.name] = report(root.name, sites, tally)
        (OUT / f"sites-{root.name}.json").write_text(json.dumps(sites, indent=1))
    (OUT / "results.json").write_text(json.dumps(results, indent=1))


if __name__ == "__main__":
    main()
