"""Works out, from a read function's Mo Core, which table reads it holds and how each one can be served."""
import collections
import re

from core import SITE

CHAIN = re.compile(r"::List\.(filter|map|flat_map)\(")

FLIP = {"lt": "gt", "gt": "lt", "le": "ge", "ge": "le"}
ARGS = {"prim": lambda node: node[2], "con": lambda node: node[3], "tuple": lambda node: node[1],
        "proj": lambda node: [node[1]], "if_": lambda node: node[1:4], "jump": lambda node: node[2],
        "app": lambda node: [node[1], *node[2]]}


def is_var(node, names):
    return node[0] == "var" and node[1] in names


def mentions(node, names):
    if isinstance(node, str) or not node:
        return False
    return is_var(node, names) or any(mentions(child, names) for child in node)


def field_of(expr, names):
    """The place of the field when `expr` takes one field out of a record held in one of `names`."""
    if expr[0] == "case_" and is_var(expr[1], names) and len(expr[2]) == 1 and expr[2][0][2][0] == "var":
        return expr[2][0][1].index(expr[2][0][2][1])
    return None


def harmless(expr):
    """A value that cannot stop the program when worked out early: a name, a constant, or a field of a record."""
    if expr[0] == "case_":
        return expr[1][0] == "var" and field_of(expr, {expr[1][1]}) is not None
    return expr[0] in ("var", "lit") or expr[0] == "con" and not expr[3]


def without(env, params):
    names = {param if isinstance(param, str) else param[0] for param in params}
    return {name: fact for name, fact in env.items() if name not in names}


def test_of(test):
    """The fields a test sets equal to, or ranges against, a value that does not depend on the row."""
    row = test[1][0][0]
    fields, tied, before, found, loose = {}, {row}, [], [], []

    def side(atom):
        if is_var(atom, fields):
            return "field", fields[atom[1]]
        return None if mentions(atom, tied) else ("other", atom)

    def compared(node):
        if node[0] == "prim" and node[1][0] in ("eq", "cmp"):
            op = "eq" if node[1][0] == "eq" else node[1][-1][0]
            left, right = (side(atom) for atom in node[2])
            if left and right and {left[0], right[0]} == {"field", "other"}:
                found.append((left[1], op, right[1]) if left[0] == "field" else (right[1], FLIP.get(op, op), left[1]))
                if op == "eq":
                    return
        loose.append(node)

    def tail(node):
        while node[0] == "let_":
            name, expr = node[1], node[2]
            if field_of(expr, {row}) is not None:
                fields[name] = field_of(expr, {row})
                tied.add(name)
            elif mentions(expr, tied) or not harmless(expr):
                tied.add(name)
            else:
                before.append((name, expr))
            node = node[3]
        if node[0] == "if_" and node[3] == ["lit", ["bool", "false"]]:
            compared(node[1])
            tail(node[2])
        else:
            compared(node)

    tail(test[2])
    equal = sorted({field: other for field, op, other in reversed(found) if op == "eq"}.items())
    ranges = [cond for cond in found if cond[1] != "eq"]
    return {"before": before, "equal": equal, "range": ranges[0] if ranges else None,
            "exact": bool(equal) and not loose}


def planned(decl):
    """Every table read in a function: the sites an index can serve, the tables walked and those read by key."""
    found = {"sites": [], "walked": set(), "said": set(), "keyed": set(), "lost": False,
             "count": collections.Counter()}

    def use(fact):
        if fact == ("shop",):
            found["lost"] = True
        elif fact and fact[0] in ("rows", "table"):
            found["walked"].add(fact[1])
            found["count"][fact[1]] += 1

    def scan(node, env):
        head = node[0]
        if head == "let_":
            return scan(node[3], {**env, node[1]: scan(node[2], env)})
        if head == "var":
            return env.get(node[1])
        if head == "lam":
            scan(node[2], without(env, node[1]))
            return "test", node
        if head == "case_":
            if env.get(node[1][1] if node[1][0] == "var" else None) == ("shop",) and field_of(node, {node[1][1]}) is not None:
                return "table", field_of(node, {node[1][1]})
            use(scan(node[1], env))
            for _, binds, body in node[2]:
                use(scan(body, without(env, binds)))
            return None
        if head == "join":
            use(scan(node[3], without(env, node[2])))
            return scan(node[4], env)
        facts = [scan(arg, env) for arg in ARGS.get(head, lambda node: [])(node)] if head != "call" else \
            [scan(arg, env) for arg in node[2]]
        if head == "prim" and node[1][0] == "map" and facts[0] and facts[0][0] == "table":
            if node[1][-1][0] == "values":
                return "rows", facts[0][1]
            found["walked" if node[1][-1][0] == "keys" else "keyed"].add(facts[0][1])
            found["count"][facts[0][1]] += 1
            facts = facts[1:]
        if head == "call" and "Shop.walk(" in node[1] and facts[0] and facts[0][0] == "table":
            found["said"].add(facts[0][1])
            return facts[0]
        if head == "call" and SITE.search(node[1]) and [fact and fact[0] for fact in facts] == ["rows", "test"]:
            found["sites"].append({"node": node, "table": facts[0][1], "how": SITE.search(node[1]).group(1),
                                   "test": facts[1][1], **test_of(facts[1][1])})
            found["count"][facts[0][1]] += 1
            return "picked", node
        for fact in facts:
            use(fact)
        return None

    use(scan(decl[4], {decl[2][0][0]: ("shop",)}))
    return found


def walks(found):
    return found["walked"] | {site["table"] for site in found["sites"] if not site["equal"] and not site["range"]}


def class_of(found, cut):
    if found["lost"]:
        return "not understood"
    if cut:
        return "kept"
    if walks(found):
        return "walked"
    return "looked up" if found["sites"] else "by key"


def refused(found, cut):
    """A read that walks a table its code does not pass through `walk`."""
    return class_of(found, cut) == "walked" and bool(walks(found) - found["said"])


def fans(cut, pairs=True):
    """Each table a write to which must redo one part for every row that names the row it changed: the written
    table, the table whose rows name it, and the fields they name it by, empty where the plan does not show them.
    A part names a row when it looks it up by key itself, or, with `pairs`, when it is a pair whose outer row it is."""
    outer, inner = cut["table"], cut.get("inner")
    found = [(outer, inner, cut["named"])] if pairs and inner is not None else []
    if not (cut["late"] and cut["free"]):
        part = outer if inner is None else inner
        found += [(table, part if row is None else (outer, inner)[row], field) for table, row, field in cut["lookups"]]
    return found


def nodes(node):
    if isinstance(node, str) or not node:
        return
    if isinstance(node[0], str):
        yield node
    for child in node:
        yield from nodes(child)


def bodies(decl, funs):
    """The body of a function and of each function it calls, once each."""
    seen, todo = set(), [decl]
    while todo:
        decl = todo.pop()
        if decl[1] not in seen:
            seen.add(decl[1])
            yield decl[4]
            todo += [funs[node[1]] for node in nodes(decl[4]) if node[0] == "call" and node[1] in funs]


def fields_read(decl, funs, ctors):
    """For each table, the places of the fields the function takes out of that table's rows."""
    found = collections.defaultdict(set)
    for body in bodies(decl, funs):
        for node in nodes(body):
            if node[0] == "case_":
                for ctor, names, branch in node[2]:
                    if ctor in ctors:
                        found[ctors[ctor]] |= {at for at, name in enumerate(names) if mentions(branch, {name})}
    return found


def changes(decl, funs, ctors, types, widths):
    """What a write function can change: for each table it sets, the places of the fields its new rows do not copy
    from a row of the same type, every field where no row is built; and the tables it removes rows from."""
    written, removes, built, binds, aliases = set(), set(), [], {}, {}
    for body in bodies(decl, funs):
        for node in nodes(body):
            if node[0] == "case_":
                for ctor, names, _ in node[2]:
                    if ctor in ctors:
                        binds.update({name: (ctor, at) for at, name in enumerate(names)})
            if node[0] == "let_" and node[2][0] == "case_" and len(node[2][2]) == 1 and node[2][2][0][2][0] == "var":
                aliases[node[1]] = node[2][2][0][2][1]
            if node[0] == "prim" and node[1][0] == "map" and node[1][2][-1] in types:
                what = node[1][-1][0]
                if what in ("set", "update"):
                    written.add(types[node[1][2][-1]])
                elif what == "remove":
                    removes.add(types[node[1][2][-1]])
            if node[0] == "con" and node[1][-1] in types and node[2] in ctors:
                built.append(node)
    sets = {table: set() for table in written}
    for con in built:
        table = types[con[1][-1]]
        if table in sets:
            copied = {at for at, arg in enumerate(con[3])
                      if arg[0] == "var" and binds.get(aliases.get(arg[1], arg[1])) == (con[2], at)}
            sets[table] |= set(range(len(con[3]))) - copied
    for table in written:
        if not any(types[con[1][-1]] == table for con in built):
            sets[table] = set(range(widths[table]))
    return {"sets": sets, "removes": removes}


def grows_only(node, total, done, kind, same=frozenset()):
    """No use of the running value but adding or appending to it and passing it on, and no early way out."""
    names = same | {total}
    if isinstance(node, str) or not node:
        return True
    if node[0] == "var":
        return node[1] not in names
    if node[0] == "stop" or node[0] == "jump" and node[1] == done:
        return False
    if node[0] == "jump":
        return all(is_var(arg, names) or grows_only(arg, total, done, kind, same) for arg in node[2])
    if node[0] == "let_":
        name, expr, rest = node[1:4]
        if is_var(expr, names):
            return grows_only(rest, total, done, kind, same | {name})
        if name == total and kind == "sum":
            return (expr[0] == "prim" and expr[1] == ["int", ["add"]]
                    and [is_var(arg, names) for arg in expr[2]].count(True) == 1
                    and grows_only(rest, total, done, kind, same))
        if name == total:
            return (expr[0] == "prim" and expr[1][0] == "list" and expr[1][-1] in (["append"], ["concat"])
                    and is_var(expr[2][0], names) and not mentions(expr[2][1], names)
                    and grows_only(rest, total, done, kind, same))
    return all(grows_only(child, total, done, kind, same) for child in (node[1:] if isinstance(node[0], str) else node))


def occurrences(node, name):
    if isinstance(node, str) or not node:
        return 0
    return 1 if node == ["var", name] else sum(occurrences(child, name) for child in node)


def looks_up(node):
    """Whether this work reads a table by key."""
    if isinstance(node, str) or not node:
        return False
    return node[0] == "prim" and node[1][0] == "map" and node[1][-1] == ["get"] or any(looks_up(child) for child in node)


def keyed_by(work, pairs, shop):
    """Each lookup by key in this work: the table, and which row of `pairs` and which of its fields give the key,
    None and () where the key is not a field of one of those rows."""
    rows, fields, tables, found = {}, {}, {}, []

    def scan(node):
        if isinstance(node, str) or not node:
            return
        if node[0] == "let_":
            name, expr = node[1], node[2]
            if expr[0] == "proj" and is_var(expr[1], pairs) and expr[2] == "0":
                rows[name] = pairs.index(expr[1][1])
            elif is_var(expr, rows):
                rows[name] = rows[expr[1]]
            elif field_of(expr, {shop}) is not None:
                tables[name] = field_of(expr, {shop})
            elif field_of(expr, rows) is not None:
                fields[name] = rows[expr[1][1]], (field_of(expr, rows),)
        if node[0] == "prim" and node[1][0] == "map" and node[1][-1] == ["get"] and is_var(node[2][0], tables):
            key = node[2][1][1] if node[2][1][0] == "var" else None
            found.append((tables[node[2][0][1]], *fields.get(key, (None, ()))))
        for child in node:
            scan(child)

    scan(work)
    return found


def needed(work, pairs, tests):
    """The fields this work reads of each row it goes over, outside the tests that chose the rows. None for a row
    used whole. `pairs` names what each loop holds its row and the rest of its list in."""
    rows, read = {}, [set() for _ in pairs]

    def scan(node):
        if isinstance(node, str) or not node or id(node) in tests:
            return
        if node[0] == "let_" and node[2][0] == "proj" and is_var(node[2][1], pairs) and node[2][2] == "0":
            rows[node[1]] = pairs.index(node[2][1][1])
        elif node[0] == "let_" and is_var(node[2], rows):
            rows[node[1]] = rows[node[2][1]]
        elif node[0] == "case_" and is_var(node[1], rows) and field_of(node, rows) is not None:
            if read[rows[node[1][1]]] is not None:
                read[rows[node[1][1]]].add(field_of(node, rows))
        elif is_var(node, rows):
            read[rows[node[1]]] = None
        elif node[0] == "proj" and is_var(node[1], pairs) and node[2] == "0":
            read[pairs.index(node[1][1])] = None
        else:
            for child in node:
                scan(child)
            return
        if node[0] == "let_":
            scan(node[3])

    scan(work)
    return [fields if fields is None else tuple(sorted(fields)) for fields in read]


def any_order(post, total):
    """Whether what follows the cut gives the same answer for the kept list in any order: it is sorted before any
    other use, with or without `unique` first."""
    if post[0] == "let_" and post[2][0] == "prim" and post[2][1][-1] == ["unique"] and post[2][2] == [["var", total]]:
        post, total = post[3], post[1]
    return post[0] == "call" and "::List.sort(" in post[1] and post[2] == [["var", total]]


def loop_in(tail):
    """The pieces of a `for` loop that carries one running value, as Mo Core writes it, or None."""
    try:
        join, done, ((total, _),), after, (inner, loop, ((rest, _), (again, _)), body, start) = tail
        case, (_, op, (walked,)), ((_, _, ended), (_, (pair,), step)) = body
        if (join == inner == "join" and case == "case_" and again == total and op[-1] == ["uncons"]
                and walked == ["var", rest] and ended == ["jump", done, [["var", total]]]
                and start[:2] == ["jump", loop] and start[2][1] == ["var", total]):
            return {"done": done, "total": total, "post": after, "loop": loop, "start": start, "ended": ended,
                    "step": step, "pair": pair}
    except (ValueError, TypeError, IndexError):
        pass
    return None


def cut_of(decl, found):
    """Where a read splits into work done for each row of one table, which can be kept, and work on the whole.

    When a part's work holds a lookup by key the cut is `late`. Where order cannot matter the cut is also `free`: the
    part waits at the lookup, the rest runs when the read is asked, and waiting parts that agree on the fields in
    `needs` share one kept entry. Where order counts, the part does its lookups and the whole answer is kept."""
    if found["lost"]:
        return None
    shop, params = decl[2][0][0], [param[0] for param in decl[2][1:]]
    lets, tail = [], decl[4]
    while tail[0] == "let_":
        lets.append(tail)
        tail = tail[3]
    defs = {let[1]: let[2] for let in lets}
    sites = {id(site["node"]): site for site in found["sites"]}

    def resolve(expr, defs=defs):
        while expr[0] == "var" and expr[1] in defs and defs[expr[1]] != expr:
            expr = defs[expr[1]]
        return expr

    def source(expr, defs=defs):
        node = resolve(expr, defs)
        if id(node) in sites:
            return sites[id(node)]["table"], sites[id(node)]
        if node[0] == "prim" and node[1][0] == "map" and node[1][-1] == ["values"]:
            inner = resolve(node[2][0], defs)
            while inner[0] == "call" and "Shop.walk(" in inner[1]:
                inner = resolve(inner[2][0], defs)
            if field_of(inner, {shop}) is not None:
                return field_of(inner, {shop}), None
        return None

    def loop_inside(outer, table):
        """The inner table, site and loop when the loop's body is itself a loop, nothing is looked up before it, and
        the value changes only in there."""
        before, inside = [], outer["step"]
        while inside[0] == "let_":
            before.append(inside)
            inside = inside[3]
        inner, total = loop_in(inside), outer["total"]
        onward = ["jump", outer["loop"], [["proj", ["var", outer["pair"]], "1"], ["var", total]]]
        if not inner or inner["total"] != total or inner["post"] != onward:
            return None
        if any(let[1] == total or mentions(let[2], {total}) or looks_up(let[2]) for let in before):
            return None
        picked = source(inner["start"][2][0], {**defs, **{let[1]: let[2] for let in before}})
        if picked and picked[1] and picked[1]["equal"] and picked[0] != table and found["count"][picked[0]] == 1:
            return picked[0], picked[1], inner
        return None

    stale = {let[1] for let in lets if source(let[2])}
    cut, inside, outer = None, None, loop_in(tail)
    if outer:
        first = resolve(["var", outer["total"]])
        kind = ("sum" if first == ["lit", ["int", "0"]] else
                "list" if first[0] == "prim" and first[1][0] == "list" and first[1][-1] == ["lit", "0"] else None)
        driven = source(outer["start"][2][0])
        if kind and driven and grows_only(outer["step"], outer["total"], outer["done"], kind):
            inside = loop_inside(outer, driven[0])
            cut = {"kind": kind, "driven": driven, "start": outer["start"], "ended": outer["ended"],
                   "done": outer["done"], "post": outer["post"], "node": None, "stages": [],
                   "inner": inside and inside[0]}
    if not cut:
        driven, bag, stages, last = None, set(), [], None
        for name, expr, post in [(let[1], let[2], let[3]) for let in lets] + [(None, tail, None)]:
            if id(expr) in sites and (driven is None or is_var(expr[2][0], bag) and not stages):
                driven, bag, stages = source(expr), {name}, [expr]
                last = ("sum", expr, post) if sites[id(expr)]["how"] == "count" and name is None else None
            elif driven is None and source(expr) and expr[0] != "var":
                driven, bag = source(expr), {name}
            elif driven and is_var(expr, bag):
                bag.add(name)
            elif driven and expr[0] == "call" and CHAIN.search(expr[1]) and is_var(expr[2][0], bag):
                stale |= bag
                bag, last = {name}, ("list", expr, post)
                stages.append(expr)
            elif mentions(expr, bag):
                break
        if last:
            cut = {"kind": last[0], "driven": driven, "node": last[1], "post": last[2],
                   "stages": [stage for stage in stages if stage is not last[1]]}
    if not cut or found["count"][cut["driven"][0]] != 1:
        return None
    if any(mentions(let[2], stale) for let in lets if let[1] not in stale and let[2] is not cut["node"]):
        return None
    if cut["post"] and mentions(cut["post"], stale):
        return None
    site, bound = cut["driven"][1], {}
    aliases = dict(site["before"]) if site else {}
    for field, other in (site["equal"] if site else []):
        while other[0] == "var" and other[1] in aliases and aliases[other[1]] != other:
            other = aliases[other[1]]
        if is_var(other, params):
            bound[other[1]] = field
        elif other[0] not in ("lit", "con"):
            return None
    early = {name for name in params
             if occurrences(decl[4], name) > (occurrences(cut["post"], name) if cut["post"] else 0)}
    if not early <= set(bound):
        return None
    looped = cut["node"] is None
    late = any(looks_up(work) for work in ([outer["step"]] if looped else [*cut["stages"], cut["node"]]))
    free = looped and (cut["kind"] == "sum" or any_order(cut["post"], outer["total"]))
    pairs = [outer["pair"]] + ([inside[2]["pair"]] if inside else []) if looped else []
    needs = late and looped and needed(outer["step"], pairs,
                                       {id(chose["test"]) for chose in (site, inside and inside[1]) if chose})
    lookups = keyed_by(outer["step"] if looped else [*cut["stages"], cut["node"]], pairs, shop)
    named = tuple(field for field, _ in inside[1]["equal"]) if inside else ()
    return {**cut, "late": late, "free": free, "needs": needs, "lookups": lookups, "named": named,
            "table": cut["driven"][0], "names": sorted(bound),
            "fields": [bound[name] for name in sorted(bound)], "places": [params.index(name) for name in sorted(bound)]}
