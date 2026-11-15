#!/usr/bin/env python3
"""Experiments 8 and 9. Plans the plain-Mo reads of experiment 4 from their Mo Core, keeps their answers through
random writes, and compares every answer with real Mo running the same functions on the same rows."""
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
CITY = ['city in ["Lisbon", "Porto", "Faro", "Braga", "Evora", "Rome"]']
PLANTED = [{"name": name, "sweep": sweep, "call": f"{name}(Shop.large{', ' + arg if arg else ''})"}
           for name, sweep, arg in [
               ("largest", ["customer in 0..42"], "customer"), ("doubled", ["customer in 0..42"], "customer"),
               ("gifts", ["customer in 0..42"], "customer"), ("spend_by_city", CITY, "city"),
               ("product_buyers", ["product in 0..28"], "product"), ("revenue", ["product in 0..28"], "product"),
               ("unlined", [], ""), ("busiest", [], "")]]
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
        self.reads, self.sites, self.cuts, self.skipped = {}, {}, {}, set()
        for module, (_, model, names) in mods.items():
            for name in names:
                decl = self.funs[f'"{module}.{name}"']
                found = plan.planned(decl)
                cut = plan.cut_of(decl, found)
                for site in found["sites"]:
                    if site["equal"] or site["range"]:
                        self.sites[id(site["node"])] = site
                if cut:
                    cut["read"] = module, name
                    self.cuts.update({id(node): cut for node in (cut["node"], cut.get("start"), cut.get("ended")) if node})
                    self.skipped |= {id(site["node"]) for site in [cut["driven"][1]] if site and site["node"] is not cut["node"]}
                    self.skipped |= {id(stage) for stage in cut["stages"]}
                self.reads[module, name] = {"decl": decl, "found": found, "cut": cut, "model": model,
                                            "class": plan.class_of(found, cut), "how": self.how(found, cut)}

    def how(self, found, cut):
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
        if not cut:
            return "; ".join(parts)
        each = "+".join(self.columns[cut["table"]][field] for field in cut["fields"])
        rows = (f"pair of rows of {self.tables[cut['table']]} and {self.tables[cut['inner']]}"
                if cut.get("inner") is not None else f"row of {self.tables[cut['table']]}")
        return (f"a {'number' if cut['kind'] == 'sum' else 'list'} kept {'for each ' + each if each else 'as one'}, "
                f"a part for each {rows}; a part reads: " + "; ".join(parts))


class Run:
    """One store, the answers kept for it in parts, and the tally of how its reads compared with Mo."""

    def __init__(self, planner, orders, seed, recheck=True, order=1, skip_updates=False, skip_others=False,
                 skip_flips=False):
        self.planner, self.orders, self.rng = planner, orders, random.Random(seed)
        self.machine = core.Machine(planner.funs, planner.sites, recheck, order)
        self.machine.cuts, self.machine.skipped, self.machine.whole = planner.cuts, planner.skipped, self.whole
        self.store = [core.Table() for _ in range(4)]
        self.shop = ('"Shop"', tuple(self.store))
        self.kept = {key: read["cut"] for key, read in planner.reads.items() if read["cut"]}
        self.parts = {key: {} for key in self.kept}
        self.sums = {key: collections.Counter() for key in self.kept}
        self.lists = {key: collections.defaultdict(dict) for key in self.kept}
        self.readers, self.indexed = collections.defaultdict(set), collections.defaultdict(set)
        self.skip_updates, self.skip_others, self.skip_flips, self.upkeep = skip_updates, skip_others, skip_flips, []
        self.owned = {key: collections.defaultdict(set) for key in self.kept}
        self.tally = collections.defaultdict(lambda: collections.Counter())
        for at, table in enumerate(self.store):
            table.kept.append(lambda old, new, at=at: self.after(at, old, new))
        self.next = [1, 1, 1, 1]
        for table, count in enumerate([40, 25, orders, orders * 3]):
            for _ in range(count):
                self.write(table, 0.0)

    def reached(self, read, alone, row):
        """Runs a read up to its cut over these tables. Gives the value reached and what was read on the way."""
        cut, decl = self.kept[read], self.planner.reads[read]["decl"]
        args = [None] * (len(decl[2]) - 1)
        for place, field in zip(cut["places"], cut["fields"]):
            args[place] = row[1][field]
        self.machine.mode, self.machine.log = "part", set()
        try:
            self.machine.call(decl[1], [('"Shop"', tuple(alone)), *args])
            raise AssertionError(f"a part of {read} ran past its cut")
        except core.Captured as reached:
            return reached.args[0], self.machine.log
        finally:
            self.machine.mode, self.machine.log = None, None

    def drop(self, read, part):
        if part in self.parts[read]:
            where, value, entries = self.parts[read].pop(part)
            for entry in entries:
                self.readers[entry].discard((read, part))
            if self.kept[read]["kind"] == "sum":
                self.sums[read][where] -= value
            else:
                self.lists[read][where].pop(part, None)

    def hold(self, read, part, row, value, entries):
        where = tuple(row[1][field] for field in self.kept[read]["fields"])
        self.parts[read][part] = where, value, entries
        for entry in entries:
            self.readers[entry].add((read, part))
            if entry[1] not in ("key", "all"):
                self.indexed[entry[0]].add(entry[2] if entry[1] == "some" else entry[1])
        if self.kept[read]["kind"] == "sum":
            self.sums[read][where] += value
        elif value:
            self.lists[read][where][part] = value

    def flat(self, read, key, row):
        """Works out again the part of a kept answer that belongs to one row, or drops it when the row is gone."""
        self.drop(read, key)
        if row is not None:
            alone = list(self.store)
            alone[self.kept[read]["table"]] = core.Table([row])
            value, log = self.reached(read, alone, row)
            self.hold(read, key, row, value, {entry for entry in log if entry[0] in self.store})

    def paired(self, read, key, row):
        """For a loop inside a loop: notes which inner rows belong to this outer row, and makes a part for each."""
        cut = self.kept[read]
        for part in self.owned[read].pop(key, ()):
            self.drop(read, part)
        self.drop(read, ("of", key))
        if row is None:
            return
        alone = list(self.store)
        alone[cut["table"]], alone[cut["inner"]] = core.Table([row]), core.Table()
        value, log = self.reached(read, alone, row)
        assert not value, f"{read} gives {value} for a row with no inner rows"
        mine = {(self.store[cut["inner"]], *entry[1:]) for entry in log if entry[0] is alone[cut["inner"]]}
        self.hold(read, ("of", key), row, value, mine | {entry for entry in log if entry[0] in self.store})
        for fields, values in (entry[1:] for entry in mine):
            for inner in list(self.store[cut["inner"]].by_equal(fields, values)):
                self.pair(read, key, inner)

    def pair(self, read, key, inner):
        cut, part = self.kept[read], (key, inner)
        self.drop(read, part)
        self.owned[read][key].discard(part)
        row, other = self.store[cut["table"]].rows.get(key), self.store[cut["inner"]].rows.get(inner)
        mine = [entry for entry in self.parts[read].get(("of", key), ((), 0, ()))[2] if entry[0] is self.store[cut["inner"]]]
        if row is None or other is None or not any(inner in entry[0].by_equal(*entry[1:]) for entry in mine):
            return
        alone = list(self.store)
        alone[cut["table"]], alone[cut["inner"]] = core.Table([row]), core.Table([other])
        value, log = self.reached(read, alone, row)
        self.hold(read, part, row, value, {entry for entry in log if entry[0] in self.store})
        self.owned[read][key].add(part)

    def after(self, at, old, new):
        """What one write to a table does to the kept answers. Gives how many parts were worked out again."""
        if self.skip_updates and old and new:
            return 0
        key, table, done = (old or new)[1][0], self.store[at], 0
        for read, cut in self.kept.items():
            if cut["table"] == at:
                (self.paired if cut.get("inner") is not None else self.flat)(read, key, new)
                done += 1
        if self.skip_others:
            return done
        touched = {(table, "all"), (table, "key", key)}
        for fields in self.indexed[table]:
            before, now = (row and tuple(row[1][field] for field in fields) for row in (old, new))
            touched |= {(table, fields, values) for values in (before, now) if values is not None}
            if before != now and not self.skip_flips:
                if before is not None and not table.by_equal(fields, before):
                    touched.add((table, "some", fields, before))
                if now is not None and len(table.by_equal(fields, now)) == 1:
                    touched.add((table, "some", fields, now))
        for read, part in sorted({reader for entry in touched for reader in self.readers.get(entry, ())}, key=repr):
            cut = self.kept[read]
            if not isinstance(part, tuple):
                self.flat(read, part, self.store[cut["table"]].rows[part])
            elif part[0] != "of":
                self.pair(read, *part)
            elif cut["inner"] == at:
                self.pair(read, part[1], key)
            else:
                self.paired(read, part[1], self.store[cut["table"]].rows[part[1]])
            done += 1
        return done

    def whole(self, cut, env):
        """The kept parts of an answer put together, for the parameters the read is being asked with."""
        read, where = cut["read"], tuple(env[name] for name in cut["names"])
        if cut["kind"] == "sum":
            self.machine.touched += 1
            return self.sums[read][where]
        parts, turn = self.lists[read].get(where, {}), self.machine.order
        first = self.store[cut["table"]].arrived
        second = self.store[cut["inner"]].arrived if cut.get("inner") is not None else {}
        joined = [item for part in sorted(parts, key=lambda part: (turn * first[part[0]], turn * second[part[1]])
                                          if isinstance(part, tuple) else (turn * first[part], 0)) for item in parts[part]]
        self.machine.touched += max(len(joined), 1)
        return joined

    def write(self, table=None, chance=None):
        table = self.rng.choices(range(4), SHARE)[0] if table is None else table
        chance = self.rng.random() if chance is None else chance
        held, before = self.store[table], self.machine.touched
        if chance < 0.3 or not held.rows:
            self.next[table] += 1
            adjusted = held.put(fresh(self.rng, table, self.next[table] - 1, self.orders))
        else:
            key = self.rng.choice(list(held.rows))
            adjusted = held.put(fresh(self.rng, table, key, self.orders)) if chance < 0.8 else held.delete(key)
        return table, adjusted, self.machine.touched - before

    def writes(self, count):
        self.upkeep += [self.write() for _ in range(count)]

    def answer(self, key, args):
        self.machine.touched, self.machine.mode = 0, "whole" if key in self.kept else None
        try:
            return self.machine.call(self.planner.reads[key]["decl"][1], [self.shop, *args]), self.machine.touched
        finally:
            self.machine.mode = None

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
            except (NotImplementedError, StopIteration, KeyError, TypeError, IndexError, ValueError, AttributeError) as fault:
                tally["fault: " + repr(fault)[:80]] += 1
        return self

    def differing(self):
        return sorted(key for key, tally in self.tally.items() if tally["same"] != tally["asked"])

    def cost(self, names):
        lines = []
        for at, name in enumerate(names):
            mine = [(adjusted, rows) for table, adjusted, rows in self.upkeep if table == at]
            lines.append(f"  a write to {name:10} {len(mine):4} writes; parts and index entries adjusted: mean "
                         f"{sum(a for a, _ in mine) / len(mine):6.1f}, most {max(a for a, _ in mine):4}; "
                         f"rows read for upkeep: mean {sum(r for _, r in mine) / len(mine):7.1f}, most {max(r for _, r in mine):5}")
        rows = [rows for _, _, rows in self.upkeep]
        return lines + [f"  any write: rows read for upkeep, mean {sum(rows) / len(rows):.1f}"]


def control(planner, **flags):
    run = Run(planner, 300, seed=8, **flags)
    run.writes(100)
    return run.compare()


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
    large.writes(600)
    large.compare()
    reversed_order, no_upkeep = control(planner, order=-1), control(planner, skip_updates=True)
    no_others, no_test = control(planner, skip_others=True), control(planner, recheck=False)
    no_flips = control(planner, skip_flips=True)

    lines = [f"{'read':28} {'by':9} {'class':10} {'same as Mo, 300':>16} {'1200':>10} {'rows read per ask':>18}  how"]
    for key, read in planner.reads.items():
        a, b = small.tally[key], large.tally[key]
        lines.append(f"{key[0] + '.' + key[1]:28} {read['model']:9} {read['class']:10} "
                     f"{a['same']:>7}/{a['asked']:<8} {b['same']:>4}/{b['asked']:<5} "
                     f"{a['touched'] / a['asked']:>8.1f} {b['touched'] / b['asked']:>8.1f}  {read['how']}"
                     + "".join(f"  [{note} x{count}]" for note, count in a.items() if note.startswith("fault")))
    agents = [key for key, read in planner.reads.items() if read["model"] in ("claude", "gpt")]
    right = [key for key in agents if key not in small.differing() + large.differing()
             and planner.reads[key]["class"] != "not understood"]
    asked = sum(tally["asked"] for run in (small, large) for tally in run.tally.values())
    lines += ["", f"answers compared with Mo's: {asked}",
              f"agent-written reads planned from Mo Core with every answer the same as Mo's: {len(right)} of {len(agents)}"]
    for label, keys in (("agent-written", agents), ("all", list(planner.reads))):
        lines.append(f"classes, {label}: " + ", ".join(f"{name} {count}" for name, count in sorted(
            collections.Counter(planner.reads[key]["class"] for key in keys).items())))
    lines.append(f"reads whose answers differed from Mo's: at 300 orders {small.differing()}, at 1200 {large.differing()}")
    for label, run in (("300", small), ("1200", large)):
        lines += [f"upkeep at {label} orders, over {len(run.upkeep)} writes:"] + run.cost(planner.tables)
    lines.append(f"reads that differ when rows come back in the opposite order: {reversed_order.differing()}")
    lines.append(f"control, updates skip all upkeep: differing {no_upkeep.differing()}")
    lines.append(f"control, a write to another table skips the parts that read it: differing {no_others.differing()}")
    lines.append(f"control, the test is dropped after the index: differing {no_test.differing()}")
    lines.append(f"control, no notice when an index entry empties or fills: differing {no_flips.differing()}")
    report = "\n".join(lines) + "\n"
    (OUT / "report.txt").write_text(report)
    print(report)

    kept = set(small.kept)
    spans = {key for key in kept if ({site["table"] for site in planner.reads[key]["found"]["sites"]}
                                     | planner.reads[key]["found"]["keyed"]) - {planner.reads[key]["cut"]["table"]}}
    assert not small.differing() and not large.differing(), "every answer must be Mo's"
    assert no_upkeep.differing() and set(no_upkeep.differing()) <= kept, "skipped upkeep must spoil kept answers only"
    assert no_others.differing() and set(no_others.differing()) <= spans, "it must spoil only answers that span tables"
    assert no_test.differing() == [("Planted", "gifts")], "a dropped test must be caught where the index does not cover it"
    asks = {key for key in kept if any(site["how"] == "any?" and site["exact"]
                                       for site in planner.reads[key]["found"]["sites"])}
    assert no_flips.differing() and set(no_flips.differing()) <= asks, "it must spoil only reads that ask if any row matches"
    assert all(read["class"] == "walked" for key, read in planner.reads.items() if key[1] == "mentions")
    assert all(planner.reads["Planted", name]["cut"] is None for name in ("largest", "doubled", "busiest"))
    assert ("Planted", "doubled") in reversed_order.differing(), "the planted read that leans on order must show"


if __name__ == "__main__":
    main()
