#!/usr/bin/env python3
"""Typed judgments about the three council reviews of how to enforce fast questions, from TypeSafe's Jev.

Jev says what each review contains. The counts and the comparison with the predictions are made here, in code.
"""
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
FILES = {"sol": "gpt-sol.md", "opus": "claude-opus.md", "gemini": "gemini-carbon.md"}
YES, NO = 0.7, 0.3
MOST_REQUESTS = 12

TERMS = {
    "Mo": "A pre-release programming language and runtime. Most Mo code is written by AI agents.",
    "read function": "A function in the program that only reads stored data.",
    "read program": "A small program an AI agent sends while the service runs, to read stored data.",
    "fast route": "Answering a read through an index the store keeps, without reading every row.",
    "walk": "Reading every row of a stored table.",
    "recognised shape": "A way of writing a filter that the compiler can turn into a fast route.",
}

OPTIONS = {
    "A_strict": "A filter with no fast route is a compile error unless the code says in a word that it walks.",
    "B_warn": "A filter with no fast route gets a warning only.",
    "C_demand": "Nothing by default. A marker on a function makes the compiler refuse it if it has no fast route.",
    "D_measure": "No static rule. A test runs each read function at two store sizes and compares instruction counts.",
    "E_closed_form": "The table offers a fixed set of methods that take a field and a value, not a function.",
    "F_review_door": "Each read function gets a ranked cost class, and an upgrade that makes one slower is held.",
}

STATEMENTS = {
    "own_code_strict": (
        "For the program's own code, does `review` choose that a filter with no fast route is a compile error?",
        "The review's choice for the program's own code makes a filter with no fast route fail to compile, "
        "with or without a word that allows a walk.",
        "The review's choice for the program's own code lets a filter with no fast route compile without an error."),
    "own_code_closed_form": (
        "For the program's own code, does the choice in `review` include a fixed set of table methods that take a "
        "field and a value?",
        "The review chooses fixed table methods that take a field and a value as part of its answer for the "
        "program's own code.",
        "The review's choice for the program's own code keeps filters written as ordinary functions."),
    "choice_includes_measuring": (
        "Does the choice in `review` include a test that runs a read function at more than one store size and "
        "compares instruction counts?",
        "The review's chosen combination includes comparing instruction counts at different store sizes.",
        "The review's chosen combination has no test that compares instruction counts at different store sizes."),
    "choice_includes_review_door": (
        "Does the choice in `review` include holding an upgrade that makes a read function slower?",
        "The review's chosen combination holds or flags an upgrade that makes a read function slower.",
        "The review's chosen combination does nothing at upgrade time about a read function becoming slower."),
    "agent_rule_differs": (
        "Does `review` give a read program an agent sends at run time a different rule from the program's own code?",
        "The review chooses one rule for the program's own code and another for a read program sent at run time.",
        "The review applies the same rule to the program's own code and to a read program sent at run time."),
    "agent_run_time_limit": (
        "For a read program an agent sends at run time, does `review` choose a limit on rows read or work done "
        "while it runs?",
        "The review limits how many rows a read program sent at run time may read, or how much work it may do.",
        "The review sets no run-time limit on rows or work for a read program sent at run time."),
    "says_agents_miss_shapes": (
        "Does `review` say that agents will often write a read in a form the compiler does not recognise?",
        "The review says code written by agents will often fall outside the recognised shapes.",
        "The review does not say that agents' code will often fall outside the recognised shapes."),
    "says_two_table_reads_are_a_gap": (
        "Does `review` say that a read which combines two tables is a gap in the idea?",
        "The review names reads that look up or combine a second table as something the idea does not cover well.",
        "The review does not name reads across two tables as a gap."),
    "says_indexes_cost_writes": (
        "Does `review` say that keeping indexes current makes writes slower or uses more space?",
        "The review says an index kept current costs time on writes or costs space.",
        "The review does not mention a cost of indexes on writes or space."),
    "says_large_answer_is_slow": (
        "Does `review` say that a read served by an index can still be slow because its answer is large?",
        "The review says a read with a fast route can still be slow when it returns many rows.",
        "The review does not say that a large answer makes an indexed read slow."),
    "says_mo_lacks_ordered_collection": (
        "Does `review` say that Mo has no sorted or ordered collection today?",
        "The review says Mo today lacks a sorted map, an ordered index or a tree collection.",
        "The review does not say that Mo lacks a sorted or ordered collection."),
    "says_new_syntax_will_be_needed": (
        "Does `review` say that a new syntax for queries will be needed in the end?",
        "The review says the project will need new query syntax or a query language eventually.",
        "The review does not say that new query syntax will be needed."),
    "experiment_agents_write_reads": (
        "Does `review` propose an experiment in which AI agents write read functions and the result is counted?",
        "One of the review's experiments has agents write read functions and counts how many fit the recognised "
        "shapes.",
        "No experiment in the review has agents write read functions."),
    "experiment_recogniser_script": (
        "Does `review` propose building a recogniser of the fast shapes as a script over Mo source?",
        "One of the review's experiments builds a script that reads Mo source and says which filters have a fast "
        "route.",
        "No experiment in the review builds a recogniser over Mo source."),
    "experiment_growth_at_two_sizes": (
        "Does `review` propose an experiment that runs a read at more than one store size and compares instruction "
        "counts?",
        "One of the review's experiments compares instruction counts of the same read at different store sizes.",
        "No experiment in the review compares instruction counts at different store sizes."),
    "experiment_agent_repairs_after_error": (
        "Does `review` propose an experiment that measures whether an agent fixes its code after being told a filter "
        "has no fast route?",
        "One of the review's experiments gives an agent an error or warning about a walk and measures whether it "
        "rewrites the code into a recognised shape.",
        "No experiment in the review measures an agent's repair after such a message."),
    "experiment_existing_code": (
        "Does `review` propose measuring Mo code that already exists for how its filters are written?",
        "One of the review's experiments counts filter shapes in existing Mo code, such as Mo's library, its "
        "services or its recorded agent sessions.",
        "No experiment in the review measures existing Mo code."),
    "experiment_index_upkeep_cost": (
        "Does `review` propose an experiment that measures what keeping an index current costs on writes?",
        "One of the review's experiments measures the cost a kept index adds to each write.",
        "No experiment in the review measures the cost of keeping an index current."),
}

# Written before any review arrived. How many of the three reviews are predicted to say yes.
PREDICTED_COUNT = {
    "own_code_strict": 2, "own_code_closed_form": 1, "choice_includes_measuring": 3,
    "choice_includes_review_door": 1, "agent_rule_differs": 3, "agent_run_time_limit": 2,
    "says_agents_miss_shapes": 3, "says_two_table_reads_are_a_gap": 2, "says_indexes_cost_writes": 2,
    "says_large_answer_is_slow": 1, "says_mo_lacks_ordered_collection": 2, "says_new_syntax_will_be_needed": 1,
    "experiment_agents_write_reads": 3, "experiment_recogniser_script": 3, "experiment_growth_at_two_sizes": 3,
    "experiment_agent_repairs_after_error": 2, "experiment_existing_code": 2, "experiment_index_upkeep_cost": 1,
}

# Claude's own position before the reviews, told to the owner on 2026-11-14: strict for the program's own code,
# with the growth test behind it; a walk allowance set by the grant for a read program sent at run time.
CLAUDES_POSITION = {"own_code_strict": True, "own_code_closed_form": False, "choice_includes_measuring": True,
                    "choice_includes_review_door": True, "agent_rule_differs": True, "agent_run_time_limit": True}

FIRST_EXPERIMENT = {
    "agents_write_read_functions": "Agents write read functions and the shapes they use are counted.",
    "recogniser_over_mo_source": "A script that recognises the fast shapes is built and run over Mo source.",
    "instruction_counts_at_two_sizes": "The same read is run at different store sizes and its instruction counts "
                                       "are compared.",
    "agent_repair_after_error": "An agent is told its filter has no fast route and its repair is measured.",
    "index_upkeep_on_writes": "The cost a kept index adds to each write is measured.",
}
PREDICTED_FIRST = {"sol": "agents_write_read_functions", "opus": "agents_write_read_functions",
                   "gemini": "recogniser_over_mo_source"}


def ask(state, questions, record, name):
    assert len(record) < MOST_REQUESTS, "the budget of requests is spent"
    payload = {"model": "jev-latest", "state": state, "questions": questions}
    text = json.dumps(payload)
    assert not re.search(r"exedev|Robert|robertguss", text)
    request = urllib.request.Request("https://api.typesafe.ai/v1/systemone", text.encode(), {
        "Authorization": "Bearer " + os.environ["TYPESAFE_API_KEY"], "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            reply = json.loads(response.read())
    except urllib.error.HTTPError as error:
        sys.exit(f"TypeSafe refused the request: {error.code} {error.read().decode()[:400]}")
    record[name] = {"request": payload, "reply": reply}
    return reply


def anonymous(text):
    return re.sub(r"/home/\w+/", "", re.sub(r"\bRobert\b", "the owner", text))


def noul(text, yes, no):
    return {"type": "noul", "instructions": text, "criteria": {"true": yes, "false": no}}


def label(p):
    return "Y" if p >= YES else "N" if p <= NO else "?"


def main():
    record, table, first = {}, {}, {}
    for who, file in FILES.items():
        review = anonymous((HERE.parent / file).read_text())
        questions = {name: noul(*parts) for name, parts in STATEMENTS.items()}
        questions["first_experiment"] = {
            "type": "choice", "instructions": "Which experiment does `review` say it would run first?",
            "criteria": FIRST_EXPERIMENT}
        questions["first_experiment_is_listed"] = noul(
            "Is the experiment `review` would run first one of these: agents writing read functions, a recogniser "
            "script over Mo source, instruction counts at different store sizes, an agent's repair after an error, "
            "or the cost of keeping an index on writes?",
            "The review's first experiment is one of those five.",
            "The review's first experiment is something else, or the review names no first experiment.")
        reply = ask({"terms": TERMS, "options": OPTIONS, "review": review}, questions, record, who)
        for name in STATEMENTS:
            table.setdefault(name, {})[who] = reply["answers"][name]["noul"]
        first[who] = (reply["answers"]["first_experiment"], reply["answers"]["first_experiment_is_listed"]["noul"])

    print("WHAT EACH REVIEW SAYS  (Y at 0.70 or more, N at 0.30 or less, ? between)")
    print(f"  {'statement':38} sol        opus       gemini     yes  predicted  Claude")
    for name, row in table.items():
        cells = "  ".join(f"{label(row[who])} {row[who]:.2f}   " for who in FILES)
        count = sum(row[who] >= YES for who in FILES)
        unsettled = any(NO < row[who] < YES for who in FILES)
        mine = {True: "yes", False: "no", None: ""}[CLAUDES_POSITION.get(name)]
        flag = "" if count == PREDICTED_COUNT[name] and not unsettled else "  <- differs" if not unsettled else "  <- unsettled"
        print(f"  {name:38} {cells}{count}    {PREDICTED_COUNT[name]}          {mine:4}{flag}")
    print()
    print("FIRST EXPERIMENT  (choice, its probability, and whether any listed option fits)")
    for who, (answer, listed) in first.items():
        fits = "" if listed >= YES else "  (no listed option fits: read the review)"
        differs = "" if answer["choice"] == PREDICTED_FIRST[who] else "  <- differs"
        print(f"  {who:7} {answer['choice']:34} {answer['probabilities'][answer['choice']]:.2f}  "
              f"listed {listed:.2f}  predicted {PREDICTED_FIRST[who]}{differs}{fits}")
    (HERE / "results.json").write_text(json.dumps(record, indent=1))
    usage = [r["reply"].get("usage", {}) for r in record.values()]
    print()
    print(f"{len(record)} requests. usage: {json.dumps(usage)}")


if __name__ == "__main__":
    main()
