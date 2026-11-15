#!/usr/bin/env python3
"""Experiment 8. Plans the plain-Mo reads of experiment 4 from their Mo Core, keeps their answers through random
writes, and compares every answer with real Mo running the same functions on the same rows."""
import collections
import json
import pathlib
import random
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
TRIAL = HERE.parent / "enforcement-trial"
sys.path.insert(0, str(TRIAL))

import core
import plan
from tasks import PILOT, TASKS, swept

OUT = HERE.parents[1] / "build" / "planner"
MO = HERE.parents[1] / "build" / "enforcement-trial" / "mo"
PLANTED = [{"name": name, "sweep": ["customer in 0..42"], "call": f"{name}(Shop.large, customer)"}
           for name in ("largest", "doubled", "gifts")]
BY_NAME = {task["name"]: task for task in [*TASKS, PILOT, *PLANTED]}
CITIES = ["Lisbon", "Porto", "Faro", "Braga", "Evora"]
WORDS = ["gift", "call", "wrap", "fragile", "rush", "plain"]
NAMES = ["pen", "ink", "pad", "cap", "nib", "tape", "clip", "glue", "card", "file", "lamp", "desk"]
SHARE = [1, 1, 4, 6]


def modules():
    """Each module of reads: its Mo text, who wrote it, and the reads it holds."""
    found = {}
    for path in sorted((TRIAL / "results" / "answers").glob("*-a-*.mo")):
        number, _, model, task = path.stem.split("-", 3)
        name = "S" + number.replace("p", "9")
        found[name] = (path.read_text().replace("module Answer", f"module {name}", 1), model, [task])
    found["Reference"] = ((TRIAL / "reference-a.mo").read_text(), "reference", [task["name"] for task in [*TASKS, PILOT]])
    found["Planted"] = ((HERE / "controls" / "planted.mo").read_text(), "planted", [task["name"] for task in PLANTED])
    return found


def printer(mods):
    """A Mo program that prints every read's answer over its task's sweep, one line for each call."""
    lines = []
    for module, (_, _, names) in mods.items():
        for name in names:
            task = BY_NAME[name]
            args = ",".join("#{%s}" % header.split(" in ")[0] for header in task["sweep"])
            call = task["call"].replace("Shop.large", "shop")
            lines.append(swept(task, f'console.print("{module}|{name}|{args}|#{{{module}.{call}}}")'))
    uses = "".join(f"use {module}\n" for module in mods)
    return (f"module Main\n{uses}use Shop\n\nfn main(console: Console) : Int\n  shop = Shop.checkpoint()\n"
            f"{''.join(lines)}  0\nend\n")


def in_mo(value, names=None):
    if isinstance(value, tuple) and names:
        return f"{value[0][1:-1]}({', '.join(f'{name}: {in_mo(field)}' for name, field in zip(names, value[1]))})"
    if isinstance(value, tuple):
        return value[0][1:-1]
    return json.dumps(value) if isinstance(value, str) else str(value)


def shop_text(store, fields):
    """The trial's shop module with one more function, `checkpoint`, that gives these rows."""
    head = (TRIAL / "shop-a.head.mo").read_text().replace("sample, large", "sample, large, checkpoint")
    parts, lists = [], []
    for table, kind in zip(store, ("Customer", "Product", "Order", "Line")):
        rows = [in_mo(row, fields[row[0]]) for row in table.rows.values()]
        calls = []
        for at in range(0, len(rows), 400):
            calls.append(f"part_{kind.lower()}_{at}()")
            listed = ",\n".join(rows[at:at + 400])
            parts.append(f"fn part_{kind.lower()}_{at}() : List({kind})\n  [{listed}]\nend\n")
        lists.append(calls[0] + "".join(f".concat({call})" for call in calls[1:]) if calls else "[]")
    joined = ",\n".join(lists)
    return (head + (TRIAL / "rows.mo").read_text() + "\n" + "\n".join(parts)
            + f"\nfn checkpoint() : Shop\n  shop_of(\n{joined}\n  )\nend\n")


def shown(value):
    """A value as Mo prints it inside a text."""
    if isinstance(value, list):
        return "[" + ", ".join(shown(item) for item in value) + "]"
    if isinstance(value, tuple):
        return f"Some({shown(value[1][0])})" if value[0] == core.SOME else "None"
    return json.dumps(value) if isinstance(value, str) else str(value)


def fresh(rng, table, key, orders):
    if table == 0:
        return '"Customer"', (key, f"c{rng.randrange(60)}", rng.choice(CITIES))
    if table == 1:
        return '"Product"', (key, rng.choice(NAMES), rng.randrange(1, 30))
    if table == 2:
        return '"Order"', (key, rng.randrange(1, 44), (rng.choice(['"Open"', '"Paid"', '"Shipped"']), ()),
                           rng.randrange(0, 121), rng.randrange(1, 400), " ".join(rng.sample(WORDS, rng.randrange(3))))
    return '"Line"', (key, rng.randrange(1, orders + 20), rng.randrange(1, 29), rng.randrange(1, 10))


class Planner:
    def __init__(self, folder, mods):
        self.folder = folder
        (folder / "main.mo").write_text(printer(mods))
        for name, (text, _, _) in mods.items():
            (folder / f"{name.lower()}.mo").write_text(text)
        (folder / "shop.mo").write_text(shop_text([core.Table()] * 4, {}))
        datas, self.funs = core.program(MO, folder)
        tables = [kind[-1][1] for _, kind in datas['"Shop.Shop"'][2][0][2]]
        self.tables = [name[1:-1] for name, _ in datas['"Shop.Shop"'][2][0][2]]
        self.fields = {datas[table][2][0][1]: [name[1:-1] for name, _ in datas[table][2][0][2]] for table in tables}
        self.columns = [self.fields[datas[table][2][0][1]] for table in tables]
        self.reads, self.sites = {}, {}
        for module, (_, model, names) in mods.items():
            for name in names:
                decl = self.funs[f'"{module}.{name}"']
                found = plan.planned(decl)
                kept = plan.keepable(decl, found)
                for site in found["sites"]:
                    if site["equal"] or site["range"]:
                        self.sites[id(site["node"])] = site
                self.reads[module, name] = {"decl": decl, "found": found, "kept": kept, "model": model,
                                            "class": plan.class_of(found, kept), "how": self.how(found, kept)}

    def how(self, found, kept):
        parts = []
        for site in found["sites"]:
            columns, table = self.columns[site["table"]], self.tables[site["table"]]
            if site["equal"]:
                parts.append(f"{table} by {'+'.join(columns[field] for field, _ in site['equal'])}")
            elif site["range"]:
                parts.append(f"{table} ranged on {columns[site['range'][0]]}")
            else:
                parts.append(f"{table} read whole at a test" + (", says walk" if site["table"] in found["said"] else ""))
        parts += [f"{self.tables[table]} by key" for table in sorted(found["keyed"])]
        parts += [f"{self.tables[table]} read whole" + (", says walk" if table in found["said"] else "")
                  for table in sorted(found["walked"])]
        return ("kept for each " + "+".join(self.columns[found["sites"][0]["table"]][field] for field in kept) + "; "
                if kept else "kept as one number; " if kept is not None else "") + "; ".join(parts)


class Run:
    """One store, the answers kept for it, and the tally of how its reads compared with Mo."""

    def __init__(self, planner, orders, seed, recheck=True, order=1, skip_updates=False):
        self.planner, self.orders, self.rng = planner, orders, random.Random(seed)
        self.machine = core.Machine(planner.funs, planner.sites, recheck, order)
        self.store = [core.Table() for _ in range(4)]
        self.shop = ('"Shop"', tuple(self.store))
        self.held, self.adjusted = {}, []
        self.tally = collections.defaultdict(lambda: collections.Counter())
        for key, read in planner.reads.items():
            if read["kept"] is not None:
                self.held[key] = collections.Counter()
                self.store[read["found"]["sites"][0]["table"]].kept.append(self.upkeep(key, read, skip_updates))
        self.next = [1, 1, 1, 1]
        for table, count in enumerate([40, 25, orders, orders * 3]):
            for _ in range(count):
                self.write(table, 0.0)

    def upkeep(self, key, read, skip_updates):
        table, fields, name = read["found"]["sites"][0]["table"], read["kept"], read["decl"][1]

        def adjust(old, new):
            if skip_updates and old and new:
                return 0
            for row, sign in ((old, -1), (new, 1)):
                if row:
                    alone = [core.Table() for _ in range(4)]
                    alone[table] = core.Table([row])
                    args = tuple(row[1][field] for field in fields)
                    self.held[key][args] += sign * self.machine.call(name, [('"Shop"', tuple(alone)), *args])
            return (old is not None) + (new is not None)

        return adjust

    def write(self, table=None, chance=None):
        table = self.rng.choices(range(4), SHARE)[0] if table is None else table
        chance = self.rng.random() if chance is None else chance
        held = self.store[table]
        if chance < 0.3 or not held.rows:
            self.next[table] += 1
            return held.put(fresh(self.rng, table, self.next[table] - 1, self.orders))
        key = self.rng.choice(list(held.rows))
        return held.put(fresh(self.rng, table, key, self.orders)) if chance < 0.8 else held.delete(key)

    def writes(self, count):
        self.adjusted += [self.write() for _ in range(count)]

    def answer(self, key, args):
        if key in self.held:
            return self.held[key][tuple(args)], 1
        self.machine.touched = 0
        return self.machine.call(self.planner.reads[key]["decl"][1], [self.shop, *args]), self.machine.touched

    def compare(self):
        """Runs every read in real Mo on the rows as they stand, and counts the answers that match."""
        (self.planner.folder / "shop.mo").write_text(shop_text(self.store, self.planner.fields))
        printed = subprocess.run([MO, "run", "main.mo"], cwd=self.planner.folder, capture_output=True, text=True)
        assert printed.returncode == 0, printed.stdout[-2000:] + printed.stderr[-2000:]
        for line in printed.stdout.splitlines():
            module, name, args, said = line.split("|", 3)
            kinds = [kind for _, kind in self.planner.reads[module, name]["decl"][2][1:]]
            args = [int(arg) if kind == ["int"] else arg for arg, kind in zip(args.split(",") if args else [], kinds)]
            tally = self.tally[module, name]
            tally["asked"] += 1
            try:
                got, touched = self.answer((module, name), args)
                tally["same"] += shown(got) == said
                tally["touched"] += touched
            except (NotImplementedError, StopIteration, KeyError, TypeError, IndexError, ValueError) as fault:
                tally["broke"] += 1
                self.tally[module, name]["fault: " + repr(fault)[:80]] += 1
        return self

    def differing(self):
        return sorted(key for key, tally in self.tally.items() if tally["same"] != tally["asked"])


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    folder = OUT / "program"
    folder.mkdir(exist_ok=True)
    planner = Planner(folder, modules())
    small = Run(planner, 300, seed=8).compare()
    for _ in range(6):
        small.writes(100)
        small.compare()
    large = Run(planner, 1200, seed=9).compare()
    large.writes(200)
    large.compare()
    reversed_order = Run(planner, 300, seed=8, order=-1)
    reversed_order.writes(100)
    reversed_order.compare()
    no_upkeep = Run(planner, 300, seed=8, skip_updates=True)
    no_upkeep.writes(100)
    no_upkeep.compare()
    no_test = Run(planner, 300, seed=8, recheck=False)
    no_test.writes(100)
    no_test.compare()

    lines = [f"{'read':28} {'by':9} {'class':14} {'same as Mo, 300':>16} {'1200':>10} {'rows read per ask':>18}  how"]
    for key, read in planner.reads.items():
        a, b = small.tally[key], large.tally[key]
        lines.append(f"{key[0] + '.' + key[1]:28} {read['model']:9} {read['class']:14} "
                     f"{a['same']:>7}/{a['asked']:<8} {b['same']:>4}/{b['asked']:<5} "
                     f"{a['touched'] / a['asked']:>8.1f} {b['touched'] / b['asked']:>8.1f}  {read['how']}"
                     + "".join(f"  [{note} x{count}]" for note, count in a.items() if note.startswith("fault")))
    agents = [key for key, read in planner.reads.items() if read["model"] in ("claude", "gpt")]
    right = [key for key in agents if key not in small.differing() + large.differing()
             and planner.reads[key]["class"] != "not understood"]
    lines += ["", f"agent-written reads planned from Mo Core with every answer the same as Mo's: {len(right)} of {len(agents)}"]
    for label, keys in (("agent-written", agents), ("all", list(planner.reads))):
        lines.append(f"classes, {label}: " + ", ".join(f"{name} {count}" for name, count in sorted(
            collections.Counter(planner.reads[key]["class"] for key in keys).items())))
    lines.append(f"reads whose answers differed from Mo's: at 300 orders {small.differing()}, at 1200 {large.differing()}")
    for label, run in (("300", small), ("1200", large)):
        lines.append(f"upkeep of one write at {label} orders: mean {sum(run.adjusted) / len(run.adjusted):.1f} "
                     f"adjustments, most {max(run.adjusted)}, over {len(run.adjusted)} writes")
    lines.append(f"reads that differ when an index gives rows in the opposite order: {reversed_order.differing()}")
    lines.append(f"control, updates skip the upkeep of kept answers: differing {no_upkeep.differing()}")
    lines.append(f"control, the test is dropped after the index: {len(no_test.differing())} reads differ")
    report = "\n".join(lines) + "\n"
    (OUT / "report.txt").write_text(report)
    print(report)

    kept = {key for key, read in planner.reads.items() if read["class"] == "kept"}
    assert kept and set(no_upkeep.differing()) == kept, "skipped upkeep must spoil every kept answer and nothing else"
    assert no_test.differing() == [("Planted", "gifts")], "a dropped test must be caught where the index does not cover it"
    assert all(read["class"] == "walked" for key, read in planner.reads.items() if key[1] == "mentions")
    assert all(planner.reads["Planted", name]["class"] == "looked up" for name in ("largest", "doubled", "gifts"))
    assert ("Planted", "doubled") in reversed_order.differing(), "the planted read that leans on order must show"


if __name__ == "__main__":
    main()
