#!/usr/bin/env python3
"""Typed judgments about the three council reviews of the vertical slices, from TypeSafe's Jev.

Jev says what each review contains. The counts and verdicts are made here, in code.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
MO = pathlib.Path.home() / "code" / "mo"
MODB = HERE.parents[2]
COMMITS = {"mo": (MO, "af246d7d"), "modb": (MODB, "28b9da6")}
FILES = {"sol": "gpt-sol.md", "opus": "claude-opus.md", "gemini": "gemini-carbon.md"}
REVIEWERS = ("sol", "opus", "gemini")
YES, NO, SETTLED = 0.7, 0.3, 0.8
MOST_REQUESTS = 60

TERMS = {
    "vertical slice": "A small experiment that carries one job the whole way down: something an agent does, the "
                      "rule that guards it, and the way its data is kept.",
    "slate": "The ordered list of vertical slices that the review proposes.",
    "world": "An agent's own version of the data. It sees its own changes and nobody else's until it lands.",
    "landing": "Applying a world's calls to the shared data, all of them or none.",
    "view": "A function that narrows which data an agent may read or change.",
    "read program": "A small program or function an agent writes to read the data, in place of a fixed query.",
    "Mo": "The language and runtime the database is written in. A Mo service keeps its whole state in memory and "
          "saves the whole state on every write.",
}

STATEMENTS = {
    "slice_worlds_on_service": (
        "Does the slate in `review` include a slice that runs worlds and their landing as a running service?",
        "One of the review's slices runs worlds, with their landing, as a service that agents call.",
        "No slice in the review runs worlds as a service that agents call."),
    "slice_rule_without_reading_all": (
        "Does the slate in `review` include a slice that checks a rule, or answers a narrowed read, over many rows "
        "without reading every row?",
        "One of the review's slices keeps a total or an index up to date so that a check or a read does not go "
        "through every row.",
        "No slice in the review is about avoiding a pass over every row for a rule or a read."),
    "slice_read_program": (
        "Does the slate in `review` include a slice in which an agent writes a read program?",
        "One of the review's slices has an agent write a program or function that reads the data.",
        "No slice in the review has an agent write a program to read the data."),
    "slice_save_only_changes": (
        "Does the slate in `review` include a slice about saving only what a write changed?",
        "One of the review's slices measures, models or builds saving only the changed part of the data on a write.",
        "No slice in the review is about saving only the changed part of the data."),
    "slice_proposal_approval": (
        "Does the slate in `review` include a slice in which an agent proposes a change and a person approves it?",
        "One of the review's slices has an agent propose a new call or a change that a person then approves.",
        "No slice in the review has a person approve something an agent proposed."),
    "slice_data_beyond_memory": (
        "Does the slate in `review` include a slice in which the data does not all sit in memory?",
        "One of the review's slices keeps data that is larger than memory, or loads parts of it when they are needed.",
        "Every slice in the review keeps all of its data in memory."),
    "slice_freeing_versions": (
        "Does the slate in `review` include a slice about dropping old versions of the data?",
        "One of the review's slices drops versions nobody needs and frees what only they held.",
        "No slice in the review drops old versions or frees what they held."),
    "slice_history": (
        "Does the slate in `review` include a slice about reading the history of the data?",
        "One of the review's slices has someone read back who changed something, or why, from a kept history.",
        "No slice in the review is about reading back the history of changes."),
    "slice_agent_learns_tools": (
        "Does the slate in `review` include a slice that tests whether an agent with no prior knowledge of the "
        "database can use it correctly?",
        "One of the review's slices gives the database to an agent that has not seen it and checks what it does.",
        "No slice in the review tests an agent that has not seen the database before."),
    "slice_grant_as_view": (
        "Does the slate in `review` include a slice about what an agent is allowed to read or change?",
        "One of the review's slices tests a grant or a view that narrows what an agent may read or change.",
        "No slice in the review is about limiting what an agent may read or change."),
    "first_needs_mo_change": (
        "Does `review` say that its first slice needs something Mo does not have today?",
        "The review says its first slice cannot be built in Mo as it is.",
        "The review says its first slice can be built in Mo as it is, or names nothing Mo lacks for it."),
    "some_slice_needs_mo_change": (
        "Does `review` say that at least one of its slices cannot be built without a change to Mo?",
        "The review names a slice that Mo as it is cannot carry, so it is measured or modelled and not built.",
        "The review says every one of its slices can be built in Mo as it is."),
    "gives_stop_rule": (
        "Does `review` state how the owner knows that enough slices have been run?",
        "The review gives a rule for stopping the slices and writing the decision.",
        "The review gives no rule for when to stop running slices."),
    "stop_rule_names_questions": (
        "Does `review` tie stopping to named open questions being answered?",
        "The review's rule for stopping lists the questions that must have answers.",
        "The review's rule for stopping does not list questions, or the review has no such rule."),
    "risk_never_decides": (
        "Does `review` name as a risk that the slices never end in a decision?",
        "The review warns that experiments could pile up without a decision being written.",
        "The review does not warn that the slices might never end in a decision."),
    "risk_small_scale_misleads": (
        "Does `review` name as a risk that a result from a small experiment does not hold for the real system?",
        "The review warns that what a small sketch shows may not hold at real size or in the real system.",
        "The review does not warn that small experiments may mislead about the real system."),
    "risk_slices_do_not_join": (
        "Does `review` name as a risk that slices built apart do not fit together?",
        "The review warns that separate slices may each work and still not make one design.",
        "The review does not warn that the slices may fail to fit together."),
    "argues_from_speed": (
        "Does `review` give being usable sooner as a reason for any choice?",
        "The review prefers something because it would be usable or delivered sooner.",
        "The review does not use being usable sooner as a reason."),
    "presupposes_sql": (
        "Does any slice in `review` assume SQL or the relational model?",
        "A slice in the review relies on SQL, or on tables related by keys and joined.",
        "No slice in the review relies on SQL or on the relational model."),
    "argues_for_a_half_first": (
        "Does `review` argue for building one half of the database before the other?",
        "The review argues that the part agents touch, or the storage, should be built first as a whole.",
        "The review keeps to vertical slices and does not argue for one half first."),
    "uses_real_data": (
        "Does `review` ask for a slice to use real data in place of made-up rows?",
        "The review asks that at least one slice runs on real data the owner has.",
        "The review does not ask for real data in any slice."),
    "measures_cost_at_sizes": (
        "Does `review` require a slice to measure a cost at more than one size of data?",
        "The review asks for a time or a size to be measured at two or more sizes of data.",
        "The review does not ask for a cost to be measured at more than one size."),
}

PREDICTED_COUNT = {
    "slice_worlds_on_service": (3, 3), "slice_rule_without_reading_all": (1, 2), "slice_read_program": (2, 3),
    "slice_save_only_changes": (2, 3), "slice_proposal_approval": (0, 1), "slice_data_beyond_memory": (1, 2),
    "slice_freeing_versions": (0, 1), "slice_history": (0, 1), "slice_agent_learns_tools": (1, 2),
    "slice_grant_as_view": (1, 2), "first_needs_mo_change": (0, 0), "some_slice_needs_mo_change": (3, 3),
    "gives_stop_rule": (3, 3), "stop_rule_names_questions": (2, 3), "risk_never_decides": (2, 3),
    "risk_small_scale_misleads": (1, 2), "risk_slices_do_not_join": (1, 2), "argues_from_speed": (0, 0),
    "presupposes_sql": (0, 0), "argues_for_a_half_first": (0, 0), "uses_real_data": (0, 1),
    "measures_cost_at_sizes": (2, 3),
}

CLAUDES_SLICES = {
    "1 a world over the wire": "slice_worlds_on_service",
    "2 a rule and a view over many rows": "slice_rule_without_reading_all",
    "3 a read program": "slice_read_program",
    "4 a write that costs what it changes": "slice_save_only_changes",
    "5 a proposal a person approves": "slice_proposal_approval",
}
NOT_ON_CLAUDES_LIST = ("slice_data_beyond_memory", "slice_freeing_versions", "slice_history",
                       "slice_agent_learns_tools", "slice_grant_as_view")

ADDED_AFTER_TWO_REVIEWS = {
    "first_checks_programs_at_landing": (
        "Is the first slice in `review` about read programs whose answers are checked again at landing?",
        "The review's first slice has an agent's questions answered by programs, and those answers are checked "
        "again when the world lands.",
        "The review's first slice does not check the answers of read programs again at landing."),
    "slice_authority_withdrawn": (
        "Does the slate in `review` include a slice in which a grant is withdrawn, or approved code is replaced, "
        "while a world is open?",
        "One of the review's slices changes what an agent is allowed to do, or the approved code, while that "
        "agent's world is still open.",
        "No slice in the review changes a grant or the approved code while a world is open."),
    "slice_lost_reply_retry": (
        "Does the slate in `review` include a slice in which an agent loses a reply and tries again?",
        "One of the review's slices has an agent retry after a lost reply or a crash and checks that the change "
        "is not made twice.",
        "No slice in the review is about a lost reply, a crash or a retry."),
    "slices_extend_one_sketch": (
        "Does `review` ask that the slices build on one shared sketch or scenario?",
        "The review asks that each slice extends the same code or the same recorded scenario as the others.",
        "The review does not ask for the slices to share one sketch or scenario."),
    "says_mo_runs_callers_function": (
        "Does `review` say that Mo can already run a caller's own function over a service's exported state?",
        "The review says Mo already has a way to run a function the caller wrote over an exported state.",
        "The review does not say that Mo can run a caller's function over an exported state."),
}

FIRST_SLICE = {
    "worlds_on_a_running_service": "Agents' worlds and their landing, run as a service that agents call.",
    "rule_or_read_over_many_rows": "A rule check or a narrowed read over many rows that does not read every row.",
    "read_program": "An agent writes a program or function that reads the data.",
    "saving_only_what_changed": "A write that saves only what it changed, not the whole state.",
    "data_larger_than_memory": "Data that is larger than memory, or is loaded when it is needed.",
    "proposal_and_approval": "An agent proposes a change and a person approves it.",
    "agent_learns_the_tools": "An agent that has not seen the database before tries to use it.",
}
PREDICTED_FIRST_SLICE = {"sol": "worlds_on_a_running_service", "opus": "worlds_on_a_running_service",
                         "gemini": "worlds_on_a_running_service"}

RELATION = {
    "supports": "The evidence shows that the claim is true.",
    "contradicts": "The evidence shows that the claim is false.",
    "says_nothing": "The evidence does not show whether the claim is true or false.",
}

CLAIMS = [
    ("query-command", "Mo has a command that runs a function over an exported state of a service.",
     [("mo", "docs/reference/README.md", 1534, 1541)], "supports"),
    ("no-functions", "A service's state, its handlers' inputs and its handlers' results may hold neither "
     "capabilities nor functions.", [("mo", "docs/reference/README.md", 1104, 1108)], "supports"),
    ("crash-between", "The crashes that the recovery check generates fall between steps and never inside a commit.",
     [("mo", "docs/reference/README.md", 1387, 1391)], "supports"),
    ("retry-unsafe", "The outcome of a commit can be unknown after a failed write, and duplicate requests are not "
     "removed.", [("mo", "docs/design/saved-state.md", 88, 94)], "supports"),
    ("reads-unlogged", "A successful call that only reads writes nothing to the store.",
     [("mo", "docs/design/saved-state.md", 88, 90)], "supports"),
    ("log-deleted", "Taking a snapshot deletes the log records that the snapshot covers.",
     [("mo", "docs/design/saved-state.md", 81, 86)], "supports"),
    ("body-limit", "The body of an MCP request is limited to 16 KiB.",
     [("mo", "src/base/limits.h", 518, 518)], "supports"),
    ("one-token", "A service declares exactly one token.", [("mo", "docs/design/services.md", 132, 133)], "supports"),
    ("nearest-thing", "The design notes call the upgrade path the nearest thing Mo has to accepting a program "
     "while the database runs.", [("modb", "design-ideas.md", 69, 69)], "supports"),
    ("not-a-service", "The worlds in the sketch ran as functions under a test command and not as a running service.",
     [("modb", "issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md", 131, 138)], "supports"),
    ("needs-callers", "The design notes list telling callers apart, and grants made from grants, among what is "
     "needed.", [("modb", "design-ideas.md", 324, 326)], "supports"),
    ("no-file-sync", "Mo's files lack byte writes, seek and sync.", [("modb", "map.md", 50, 50)], "supports"),
    ("finer-rule", "The design notes say the finer rule is chosen once needless send-backs have been counted.",
     [("modb", "design-ideas.md", 554, 554)], "supports"),
    ("rule-twice", "The earlier sketch states its rule twice, once as a promise and once as a function.",
     [("modb", "sketches/land-whole/main.mo", 25, 29), ("modb", "sketches/land-whole/main.mo", 54, 58)],
     "supports"),
    ("ceiling-cause", "The 16 MiB limit on saved state is what stops a service at about 125,000 rows.",
     [("modb", "issues/11-how-fast-and-large-is-a-mo-service.md", 46, 48)], "contradicts"),
    ("test-only", "A promise is checked by the test command and cannot be called when a write lands.",
     [("modb", "sketches/README.md", 17, 17)], "supports"),
    ("auth-and-plan", "Most of the time spent reading a request goes to the functions that authenticate it and "
     "plan it.", [("modb", "issues/11-how-fast-and-large-is-a-mo-service.md", 114, 120)], "supports"),
    ("synced-write", "A synced write to SQLite by itself takes about 3 ms.",
     [("modb", "issues/11-how-fast-and-large-is-a-mo-service.md", 97, 97)], "supports"),
    ("control-1", "A call to a service may run 1,073,741,824 instructions.",
     [("mo", "src/base/limits.h", 333, 333)], "contradicts"),
    ("control-2", "Taking a snapshot deletes the log records that the snapshot covers.",
     [("mo", "docs/design/services.md", 132, 133)], "says_nothing"),
]


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
    return re.sub(r"\bRobert\b", "the owner", text)


def noul(text, yes, no):
    return {"type": "noul", "instructions": text, "criteria": {"true": yes, "false": no}}


def label(p):
    return "Y" if p >= YES else "N" if p <= NO else "?"


def positions(record):
    table, added, first = {}, {}, {}
    for who in REVIEWERS:
        questions = {name: noul(*parts) for name, parts in {**STATEMENTS, **ADDED_AFTER_TWO_REVIEWS}.items()}
        questions["first_slice"] = {"type": "choice", "instructions": "Which slice does `review` run first?",
                                    "criteria": FIRST_SLICE}
        questions["first_slice_is_listed"] = noul(
            "Is the first slice in `review` about worlds on a running service, a rule or read over many rows, a "
            "read program, saving only what changed, data larger than memory, a proposal and its approval, or an "
            "agent that has not seen the database?",
            "The review's first slice is about one of those seven things.",
            "The review's first slice is about something else.")
        reply = ask({"terms": TERMS, "review": anonymous((HERE.parent / FILES[who]).read_text())}, questions, record,
                    f"positions-{who}")
        for name in STATEMENTS:
            table.setdefault(name, {})[who] = reply["answers"][name]["noul"]
        for name in ADDED_AFTER_TWO_REVIEWS:
            added.setdefault(name, {})[who] = reply["answers"][name]["noul"]
        first[who] = (reply["answers"]["first_slice"], reply["answers"]["first_slice_is_listed"]["noul"])
    print("WHAT EACH REVIEW CONTAINS  (probability: sol, opus, gemini; then how many say yes)")
    for name, row in table.items():
        got = "".join(label(row[who]) for who in REVIEWERS)
        low, high = PREDICTED_COUNT[name]
        yes, open_ = got.count("Y"), got.count("?")
        held = low <= yes <= high if not open_ else ("?" if yes <= high and yes + open_ >= low else False)
        print(f"  {name:32} " + " ".join(f"{row[who]:.2f}" for who in REVIEWERS)
              + f"  {got}  yes {yes}" + (f" unsettled {open_}" if open_ else "")
              + f"  predicted {low}-{high}  " + {True: "as predicted", False: "<- differs", "?": "open"}[held])
    print("ADDED AFTER READING TWO REVIEWS, NO PREDICTION  (probability: sol, opus, gemini)")
    for name, row in added.items():
        print(f"  {name:34} " + " ".join(f"{row[who]:.2f}" for who in REVIEWERS) + "  "
              + "".join(label(row[who]) for who in REVIEWERS))
    print("FIRST SLICE  (choice, its probability, and whether any listed option fits)")
    for who in REVIEWERS:
        answer, fits = first[who]
        ranked = sorted(answer["probabilities"].items(), key=lambda item: -item[1])[:2]
        print(f"  {who:7} " + ", ".join(f"{name} {p:.2f}" for name, p in ranked) + f"   an option fits {fits:.2f}"
              + f"   predicted {PREDICTED_FIRST_SLICE[who]}"
              + ("" if answer["choice"] == PREDICTED_FIRST_SLICE[who] else "  <- differs"))
    print("CLAUDE'S FIVE SLICES AGAINST THE THREE SLATES  (2 or 3 yes: shared; 1: contested; 0: Claude's alone)")
    for slice_name, statement in CLAUDES_SLICES.items():
        got = [label(table[statement][who]) for who in REVIEWERS]
        yes = got.count("Y")
        verdict = "unsettled" if "?" in got and yes < 2 else "shared" if yes >= 2 else "contested" if yes else "alone"
        print(f"  {slice_name:38} {''.join(got)}  {verdict}")
    print("SLICES NOT ON CLAUDE'S LIST  (2 or 3 yes: missing from it)")
    for statement in NOT_ON_CLAUDES_LIST:
        got = [label(table[statement][who]) for who in REVIEWERS]
        print(f"  {statement:38} {''.join(got)}  " + ("missing from Claude's list" if got.count("Y") >= 2 else "-"))


def excerpt(root, path, first, last):
    repo, commit = COMMITS[root]
    whole = subprocess.run(["git", "-C", str(repo), "show", f"{commit}:{path}"], check=True, capture_output=True,
                           text=True).stdout
    lines = whole.splitlines()[first - 1:last]
    return {"file": path, "lines": f"{first}-{last}", "text": anonymous("\n".join(lines))}


def citations(record):
    print("CITATIONS  (verdict with options in two orders, then the smaller of the two top probabilities)")
    for name, claim, spans, predicted in CLAIMS:
        question = "How does `evidence` relate to `claim`?"
        reply = ask({"claim": claim, "evidence": [excerpt(*span) for span in spans]}, {
            "forward": {"type": "choice", "instructions": question, "criteria": RELATION},
            "reversed": {"type": "choice", "instructions": question, "criteria": dict(reversed(RELATION.items()))}},
            record, f"citation-{name}")
        forward, backward = reply["answers"]["forward"], reply["answers"]["reversed"]
        agree = forward["choice"] == backward["choice"]
        least = min(forward["probabilities"][forward["choice"]], backward["probabilities"][backward["choice"]])
        verdict = forward["choice"] if agree and least >= SETTLED else "needs a person"
        print(f"  {name:10} {forward['choice']:12} {backward['choice']:12} {least:.2f}  -> {verdict:14}"
              f" predicted {predicted}" + ("" if verdict == predicted else "  <- differs"))


def main():
    record = {}
    positions(record)
    citations(record)
    (HERE / "results.json").write_text(json.dumps(record, indent=1))
    tokens = sum(entry["reply"]["usage"]["input_tokens"] for entry in record.values())
    print(f"requests {len(record)}, input tokens {tokens}, cost about ${tokens * 0.042 / 1e6:.4f}")


if __name__ == "__main__":
    main()
