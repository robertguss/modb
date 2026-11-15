"""Reads the Mo Core that `mo check --emit=core` prints, and runs it over tables that keep their own indexes."""
import bisect
import json
import re
import subprocess

SITE = re.compile(r"::List\.(filter|count|any\?|find)\(")
SOME, NONE = '"Some"', '"None"'


def parsed(text):
    tokens = re.findall(r'"(?:[^"\\]|\\.)*"|[()]|[^\s()]+', text)

    def read(at):
        if tokens[at] != "(":
            return tokens[at], at + 1
        out, at = [], at + 1
        while tokens[at] != ")":
            item, at = read(at)
            out.append(item)
        return out, at + 1

    return read(0)[0]


def program(mo, folder, file="main.mo"):
    """The data types and functions of a Mo program, as its compiler lowers them to Mo Core."""
    core = subprocess.run([mo, "check", file, "--emit=core"], cwd=folder, capture_output=True, text=True, check=True)
    tree = parsed(core.stdout)[2]
    return {decl[1]: decl for decl in tree[1]}, {decl[1]: decl for decl in tree[2]}


class Table:
    """A stored table: rows by id in the order they arrived, and the indexes the reads asked for."""

    def __init__(self, rows=()):
        self.rows, self.arrived, self.equal, self.ranged, self.kept = {}, {}, {}, {}, []
        for row in rows:
            self.put(row)

    def put(self, row):
        """Adds or replaces a row. Gives how many index entries and kept answers were adjusted."""
        key = row[1][0]
        old = self.rows.get(key)
        self.arrived.setdefault(key, len(self.arrived))
        self.rows[key] = row
        return self.adjust(old, row)

    def delete(self, key):
        return self.adjust(self.rows.pop(key), None)

    def adjust(self, old, new):
        adjusted = 0
        for fields, held in self.equal.items():
            before, after = (row and tuple(row[1][at] for at in fields) for row in (old, new))
            if before != after:
                adjusted += (old is not None) + (new is not None)
                if old:
                    held[before].discard(old[1][0])
                if new:
                    held.setdefault(after, set()).add(new[1][0])
        for field, held in self.ranged.items():
            before, after = (row and (row[1][field], row[1][0]) for row in (old, new))
            if before != after:
                adjusted += (old is not None) + (new is not None)
                if old:
                    held.pop(bisect.bisect_left(held, before))
                if new:
                    bisect.insort(held, after)
        for upkeep in self.kept:
            adjusted += upkeep(old, new)
        return adjusted

    def by_equal(self, fields, values):
        if fields not in self.equal:
            held = self.equal[fields] = {}
            for row in self.rows.values():
                held.setdefault(tuple(row[1][at] for at in fields), set()).add(row[1][0])
        return self.equal[fields].get(values, ())

    def by_range(self, field, op, value):
        if field not in self.ranged:
            self.ranged[field] = sorted((row[1][field], row[1][0]) for row in self.rows.values())
        held = self.ranged[field]
        low, high = bisect.bisect_left(held, (value,)), bisect.bisect_right(held, (value, float("inf")))
        chosen = {"ge": held[low:], "gt": held[high:], "lt": held[:low], "le": held[:high]}[op]
        return [key for _, key in chosen]


class Rows:
    """Every row of a table, not yet read. Reading it is a walk unless a planned read takes it first."""

    def __init__(self, table):
        self.table = table


class Captured(Exception):
    """Carries the value a read had reached at its cut, when only that value was wanted."""


class Waiting(Exception):
    """Raised at a lookup by key, when a part is to be run only as far as its first one."""


class Held:
    def __init__(self, params, body, env=None):
        self.params, self.body, self.env = params, body, env


def literal(node):
    kind = node[0]
    if kind == "int":
        return int(node[1])
    if kind == "bool":
        return node[1] == "true"
    if kind == "text":
        return json.loads(node[1])
    return ()


def option(found):
    return (NONE, ()) if found is None else (SOME, (found,))


def unique(items):
    return list(dict.fromkeys(items))


PRIMS = {
    ("int", "add"): lambda a, b: a + b, ("int", "sub"): lambda a, b: a - b, ("int", "mul"): lambda a, b: a * b,
    ("int", "max"): max, ("int", "min"): min, ("int", "div"): lambda a, b: a // b, ("int", "rem"): lambda a, b: a % b, ("eq",): lambda a, b: a == b, ("not",): lambda a: not a,
    ("cmp", "lt"): lambda a, b: a < b, ("cmp", "le"): lambda a, b: a <= b,
    ("cmp", "gt"): lambda a, b: a > b, ("cmp", "ge"): lambda a, b: a >= b,
    ("list", "lit"): lambda *items: list(items), ("list", "append"): lambda items, item: items + [item],
    ("list", "uncons"): lambda items: option((items[0], items[1:]) if items else None),
    ("list", "size"): len, ("list", "isEmpty"): lambda items: not items,
    ("list", "take"): lambda items, n: items[:max(n, 0)], ("list", "drop"): lambda items, n: items[max(n, 0):],
    ("list", "concat"): lambda a, b: a + b, ("list", "unique"): unique,
    ("list", "get"): lambda items, at: option(items[at] if 0 <= at < len(items) else None),
    ("list", "contains"): lambda items, item: item in items,
    ("text", "contains"): lambda text, part: part in text, ("text", "concat"): lambda a, b: a + b,
}


class Machine:
    """Runs Mo Core. `sites` maps a planned call to the index it reads through; `touched` counts rows read.

    `cuts` maps a node to the cut it belongs to. In mode "part" a run stops at its cut and gives the value reached;
    in mode "whole" the cut gives what `whole` holds for it, and the calls in `skipped` are not run at all.
    `log`, when it is a set, collects what was read: a key, an index entry, whether an index entry has any row,
    or all of a table. `again` counts lookups by key of a row already in `got`. While `waits` is set a lookup by key
    stops the run."""

    def __init__(self, funs, sites=None, recheck=True, order=1):
        self.funs, self.sites, self.recheck, self.order, self.touched = funs, sites or {}, recheck, order, 0
        self.cuts, self.skipped, self.mode, self.whole, self.log = {}, set(), None, None, None
        self.got, self.again, self.waits = set(), 0, False

    def noted(self, *entry):
        if self.log is not None:
            self.log.add(entry)

    def call(self, name, args):
        decl = self.funs[name]
        return self.read(self.run(decl[4], dict(zip((param[0] for param in decl[2]), args))))

    def read(self, value):
        if isinstance(value, Rows):
            self.touched += len(value.table.rows)
            self.noted(value.table, "all")
            return list(value.table.rows.values())
        return value

    def narrowed(self, site, rows, test):
        """The rows of the table that the site's index gives for this test, in the order the table holds them."""
        env = test.env
        for name, expr in site["before"]:
            env = {**env, name: self.run(expr, env)}
        if site["equal"]:
            fields = tuple(field for field, _ in site["equal"])
            values = tuple(self.run(other, env) for _, other in site["equal"])
            keys = rows.table.by_equal(fields, values)
            if site["how"] == "any?" and site["exact"]:
                self.noted(rows.table, "some", fields, values)
                keys = sorted(keys)[:1]
            else:
                self.noted(rows.table, fields, values)
        else:
            field, op, other = site["range"]
            keys = rows.table.by_range(field, op, self.run(other, env))
            self.noted(rows.table, "all")
        self.touched += len(keys)
        return [rows.table.rows[key] for key in sorted(keys, key=lambda key: self.order * rows.table.arrived[key])]

    def run(self, node, env):
        while True:
            head = node[0]
            if head == "let_":
                env = {**env, node[1]: self.run(node[2], env)}
                node = node[3]
            elif head == "var":
                return env[node[1]]
            elif head == "lit":
                return literal(node[1])
            elif head == "if_":
                node = node[2] if self.run(node[1], env) else node[3]
            elif head == "case_":
                value = self.read(self.run(node[1], env))
                binds, node = next((binds, body) for ctor, binds, body in node[2] if ctor == value[0])
                env = {**env, **dict(zip(binds, value[1]))}
            elif head == "join":
                held = Held([param[0] for param in node[2]], node[3])
                env = held.env = {**env, node[1]: held}
                node = node[4]
            elif head == "jump" and self.mode and id(node) in self.cuts:
                cut = self.cuts[id(node)]
                if self.mode == "part" and node is cut["ended"]:
                    raise Captured(self.run(node[2][0], env))
                if self.mode == "whole" and node is cut["start"]:
                    held = env[cut["done"]]
                    env, node = {**held.env, held.params[0]: self.whole(cut, env)}, held.body
                else:
                    held = env[node[1]]
                    env = {**held.env, **dict(zip(held.params, (self.read(self.run(arg, env)) for arg in node[2])))}
                    node = held.body
            elif head in ("jump", "app"):
                held = env[node[1]] if head == "jump" else self.run(node[1], env)
                env = {**held.env, **dict(zip(held.params, (self.read(self.run(arg, env)) for arg in node[2])))}
                node = held.body
            elif head == "lam":
                return Held([param[0] for param in node[1]], node[2], env)
            elif head == "call" and self.mode == "whole" and (id(node) in self.cuts or id(node) in self.skipped):
                return self.whole(self.cuts[id(node)], env) if id(node) in self.cuts else None
            elif head == "call":
                args = [self.run(arg, env) for arg in node[2]]
                site = self.sites.get(id(node))
                if site and isinstance(args[0], Rows):
                    args[0] = self.narrowed(site, *args)
                    if not self.recheck:
                        args[1] = Held(args[1].params, ["lit", ["bool", "true"]], {})
                decl = self.funs[node[1]]
                inside = dict(zip((param[0] for param in decl[2]), map(self.read, args)))
                if self.mode == "part" and id(node) in self.cuts:
                    raise Captured(self.read(self.run(decl[4], inside)))
                env, node = inside, decl[4]
            elif head == "prim":
                return self.prim(node[1], [self.read(self.run(arg, env)) for arg in node[2]])
            elif head == "con":
                return (node[2], tuple(self.run(arg, env) for arg in node[3]))
            elif head == "tuple":
                return tuple(self.run(arg, env) for arg in node[1])
            elif head == "proj":
                return self.run(node[1], env)[int(node[2])]
            else:
                raise NotImplementedError(head)

    def prim(self, op, args):
        if op[0] == "map":
            table, what = args[0], op[-1][0]
            if what == "values":
                return Rows(table)
            if what == "get":
                if self.waits:
                    raise Waiting
                self.touched += 1
                self.again += (id(table), args[1]) in self.got
                self.got.add((id(table), args[1]))
                self.noted(table, "key", args[1])
                return option(table.rows.get(args[1]))
            if what == "keys":
                self.touched += len(table.rows)
                self.noted(table, "all")
                return list(table.rows)
        key = (op[0],) if op[0] in ("eq", "not") else (op[0], op[-1][0])
        if key not in PRIMS:
            raise NotImplementedError(str(op))
        return PRIMS[key](*args)
