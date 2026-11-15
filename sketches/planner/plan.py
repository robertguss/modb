"""Works out, from a read function's Mo Core, which table reads it holds and how each one can be served."""
from core import SITE

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
    fields, tied, before, found = {}, {row}, [], []

    def side(atom):
        if is_var(atom, fields):
            return "field", fields[atom[1]]
        return None if mentions(atom, tied) else ("other", atom)

    def compared(node):
        if node[0] != "prim" or node[1][0] not in ("eq", "cmp"):
            return
        op = "eq" if node[1][0] == "eq" else node[1][-1][0]
        left, right = (side(atom) for atom in node[2])
        if left and right and {left[0], right[0]} == {"field", "other"}:
            found.append((left[1], op, right[1]) if left[0] == "field" else (right[1], FLIP.get(op, op), left[1]))

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
    return {"before": before, "equal": equal, "range": ranges[0] if ranges else None}


def planned(decl):
    """Every table read in a function: the sites an index can serve, the tables walked and those read by key."""
    found = {"sites": [], "walked": set(), "said": set(), "keyed": set(), "lost": False}

    def use(fact):
        if fact == ("shop",):
            found["lost"] = True
        elif fact and fact[0] in ("rows", "table"):
            found["walked"].add(fact[1])

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
            facts = facts[1:]
        if head == "call" and "Shop.walk(" in node[1] and facts[0] and facts[0][0] == "table":
            found["said"].add(facts[0][1])
            return facts[0]
        if head == "call" and SITE.search(node[1]) and [fact and fact[0] for fact in facts] == ["rows", "test"]:
            found["sites"].append({"node": node, "table": facts[0][1], "how": SITE.search(node[1]).group(1),
                                   **test_of(facts[1][1])})
            return "picked", node
        for fact in facts:
            use(fact)
        return None

    use(scan(decl[4], {decl[2][0][0]: ("shop",)}))
    return found


def class_of(found, kept):
    if found["lost"]:
        return "not understood"
    if kept is not None:
        return "kept"
    if found["walked"] | {site["table"] for site in found["sites"] if not site["equal"] and not site["range"]}:
        return "walked"
    return "looked up" if found["sites"] else "by key"


def adds_only(node, total, done, same=frozenset()):
    """No use of the running total but adding to it and passing it on, and no way out of the loop early."""
    names = same | {total}
    if isinstance(node, str) or not node:
        return True
    if node[0] == "var":
        return node[1] not in names
    if node[0] == "stop" or node[0] == "jump" and node[1] == done:
        return False
    if node[0] == "jump":
        return all(is_var(arg, names) or adds_only(arg, total, done, same) for arg in node[2])
    if node[0] == "let_":
        name, expr, rest = node[1:4]
        if is_var(expr, names):
            return adds_only(rest, total, done, same | {name})
        if name == total:
            return (expr[0] == "prim" and expr[1] == ["int", ["add"]]
                    and [is_var(arg, names) for arg in expr[2]].count(True) == 1
                    and adds_only(rest, total, done, same))
    return all(adds_only(child, total, done, same) for child in (node[1:] if isinstance(node[0], str) else node))


def summed(tail, resolve, picked):
    """Whether this is a loop over the picked rows that only ever adds to one number that starts at nought."""
    try:
        join, done, ((total, _),), after, (_, loop, ((rest, _), (again, _)), body, start) = tail
        case, (_, _, (source,)), ((_, _, ended), (_, _, step)) = body
    except (ValueError, TypeError):
        return False
    return (join == "join" and case == "case_" and again == total and after == ["var", total]
            and resolve(["var", total]) == ["lit", ["int", "0"]] and source == ["var", rest]
            and ended == ["jump", done, [["var", total]]] and start[:2] == ["jump", loop]
            and body[1][1][-1] == ["uncons"] and resolve(start[2][0]) is picked and start[2][1] == ["var", total] and adds_only(step, total, done))


def keepable(decl, found):
    """For an answer that is a count or a sum over one table, the field each parameter is set equal to."""
    if found["lost"] or found["walked"] or found["keyed"] or len(found["sites"]) != 1:
        return None
    site, params = found["sites"][0], [param[0] for param in decl[2][1:]]
    aliases, bound = dict(site["before"]), {}
    for field, other in site["equal"]:
        while other[0] == "var" and other[1] in aliases and aliases[other[1]] != other:
            other = aliases[other[1]]
        if is_var(other, params):
            bound[other[1]] = field
        elif other[0] not in ("lit", "con"):
            return None
    defs, tail = {}, decl[4]
    while tail[0] == "let_":
        defs[tail[1]], tail = tail[2], tail[3]

    def resolve(expr):
        while expr[0] == "var" and expr[1] in defs and defs[expr[1]] != expr:
            expr = defs[expr[1]]
        return expr

    counted = site["how"] == "count" and resolve(tail) is site["node"]
    added = site["how"] == "filter" and summed(tail, resolve, site["node"])
    return [bound[name] for name in params] if set(bound) == set(params) and (counted or added) else None
