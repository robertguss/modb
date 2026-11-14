"""Stands in for a compiler rule: a stored table is read by key, by a filter in a recognised shape, or through walk."""
import collections
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "shape-census"))
import census

INDEXED = {"customers": ["id", "city"], "products": ["id"],
           "orders": ["id", "customer", "status", "total", "placed"], "lines": ["id", "order", "product"]}
VIEW = r"(?:\.values|\.entries|\.keys)?"
BOUND = re.compile(rf"\s*(\w+) = (\w+\.(?:{'|'.join(INDEXED)}){VIEW})\s*$")
WHY = {
    "use": "every row of `{table}` is read here",
    "loop": "this loop visits every row of `{table}`",
    "miss: or": "a test joined with `or` has no fast route",
    "miss: negation": "a test with `not` or `!=` has no fast route",
    "miss: a named function": "the compiler does not look inside a named function for the test",
    "miss: a call or a computed value on the row":
        "the test does not compare an indexed field of the row with a value that does not depend on the row",
    "miss: a test of several lines": "a test of several lines has no fast route",
    "miss: the loop does more than one if": "a loop over a stored table must hold a single `if` and nothing else",
}


def masked(line):
    return census.LITERAL.sub(lambda m: '"' + " " * (len(m.group()) - 2) + '"', line)


def logical(text):
    """Numbered source lines, with a line that continues an expression joined to the line it continues."""
    lines, depth = [], 0
    for number, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith("#"):
            line = ""
        if lines and (depth > 0 or line.strip().startswith(".")):
            lines[-1] = (lines[-1][0], f"{lines[-1][1]} {line.strip()}" if depth > 0 else lines[-1][1] + line.strip())
        else:
            lines.append((number, line))
            depth = 0
        bare = masked(line)
        depth += sum(bare.count(c) for c in "([{") - sum(bare.count(c) for c in ")]}")
    return lines


def inlined(lines):
    """Puts a table in place of each name bound to it, within the function that binds it."""
    names, out = {}, []
    for number, line in lines:
        if line.startswith("fn "):
            names = {}
        bound = BOUND.match(line)
        if bound:
            names[bound.group(1)] = bound.group(2)
            line = ""
        for name, table in names.items():
            line = re.sub(rf"(?<![\w.]){name}\b(?!\s*(?:[:(]|=[^=]))", table, line)
        out.append((number, line))
    return out


def errors(text):
    lines = inlined(logical(text))
    texts = [line for _, line in lines]
    found = []
    for table, fields in INDEXED.items():
        sites = {(site["line"], site["kind"], site["over"]): site["shape"]
                 for site in [*census.call_sites(texts, set(fields)),
                              *census.loop_sites(texts, set(fields), collections.Counter())]}
        for at, line in enumerate(texts):
            bare = masked(line)
            for m in re.finditer(rf"\b\w+\.{table}\b{VIEW}", bare):
                before, after = bare[:m.start()], bare[m.end():]
                header = census.FOR.match(line)
                if re.match(r"\.(get\(|has\?\(|size\b|empty\?)", after) and m.group().endswith(table):
                    continue
                if re.search(r"\bwalk\(\s*$", before) or after.startswith(".walk"):
                    continue
                if census.CALL.match(bare, m.end()):
                    reason = sites.get((at + 1, "call", line[:m.end()].strip()), "use")
                elif header and header.group(2).strip() == m.group():
                    reason = sites.get((at + 1, "loop", m.group()), "loop")
                else:
                    reason = "use"
                if reason not in census.FOUND:
                    found.append({"line": lines[at][0], "column": m.start() + 1, "width": len(m.group()),
                                  "table": table, "reason": reason, "source": line})
    return sorted(found, key=lambda error: (error["line"], error["column"]))


def report(found, file="answer.mo"):
    out = []
    for error in found:
        table, fields = error["table"], INDEXED[error["table"]]
        listed = ", ".join(f"`{field}`" for field in fields[:-1]) + (" and " if len(fields) > 1 else "") + f"`{fields[-1]}`"
        gutter = " " * len(str(error["line"]))
        out.append(f"""error E9001: a stored table is read with no fast route  {file}:{error["line"]}:{error["column"]}

  {error["line"]} | {error["source"]}
  {gutter} | {" " * (error["column"] - 1)}{"^" * error["width"]} {WHY[error["reason"]].format(table=table)}

A stored table is read by key, by a filter on an indexed field, or through `walk` (STORE.md, "Reading a stored table"). The indexed fields of `{table}` are {listed}.

Fix: filter on an indexed field, comparing it with a value that does not depend on the row
  shop.{table}.values.filter(fn(row) row.{fields[-1]} == value end)
or, when every row really must be read, say so
  walk(shop.{table})
""")
    return "\n".join(out)


if __name__ == "__main__":
    print(report(errors(pathlib.Path(sys.argv[1]).read_text()), sys.argv[1]), end="")
