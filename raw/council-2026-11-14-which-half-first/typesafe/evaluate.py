#!/usr/bin/env python3
"""Typed judgments about the three council reviews from TypeSafe's Jev. The verdicts are made here, in code."""
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
MO = pathlib.Path.home() / "code" / "mo"
REVIEWERS = ("sol", "opus", "gemini")
YES, NO, SETTLED = 0.7, 0.3, 0.8

TERMS = {
    "upper half": "The part of the database that agents and people touch: write functions, read programs, grants, "
                  "an agent's own copy of the data (a world) and how it lands.",
    "storage half": "How the data is kept: more data than fits in memory, saving only what changed, keeping "
                    "versions without copying, and storage on disk.",
    "today's services": "The language's existing services. Each keeps its whole state in memory and saves the "
                        "whole state on every write.",
    "the document": "The planning document the review was asked to read, which sets out both orders.",
}

STATEMENTS = {
    "upper_first_on_today": (
        "Does `review` recommend building the upper half first, on today's services?",
        "The order the review recommends begins with the upper half built on today's services.",
        "The order the review recommends begins with something other than the upper half on today's services."),
    "whole_storage_first": (
        "Does `review` recommend completing the storage half before any of the upper half is built?",
        "The review recommends that the whole storage half is built first.",
        "The review recommends that only a part of the storage work, or none of it, comes before the upper half."),
    "versioned_collection_first": (
        "Does `review` recommend building a collection that keeps versions without copying before the upper half?",
        "The order the review recommends has such a collection built before the upper half.",
        "The order the review recommends does not put such a collection before the upper half."),
    "disk_last": (
        "Does `review` recommend leaving storage on disk until after the upper half is built?",
        "The review's order builds the upper half first and storage on disk after it.",
        "The review's order builds storage on disk before the upper half or in the same slice as it."),
    "experiment_before_committing": (
        "Does `review` name an experiment to run before the order is committed to?",
        "The review names at least one sketch, measurement or model to do before committing.",
        "The review asks for nothing to be tried before committing."),
    "runtime_change_needed": (
        "Does `review` say that keeping versions cheaply needs a change to how the runtime saves state?",
        "The review says cheap versions cannot be had without changing how the runtime saves state.",
        "The review does not say that a change to how the runtime saves state is needed."),
    "no_runtime_change_needed": (
        "Does `review` describe a way to keep versions cheaply that needs no change to the runtime?",
        "The review describes a design that keeps versions cheaply on the runtime as it is.",
        "The review describes no such design."),
    "sharing_lost_on_save": (
        "Does `review` say that saving a service's state turns data shared between versions into full copies?",
        "The review says that sharing is lost when state is saved.",
        "The review does not make this point."),
    "reads_not_logged": (
        "Does `review` say that today's services do not log read calls?",
        "The review says that read calls are left out of the log.",
        "The review does not make this point."),
    "data_beyond_memory_open": (
        "Does `review` name, as an open problem, how functions reach data that is not in memory?",
        "The review says it is not settled how functions reach data that is not in memory.",
        "The review does not raise this problem."),
    "capability_rule_matters": (
        "Does `review` say that the rule against capabilities in a service's state bears on how storage is built?",
        "The review ties the rule against capabilities in service state to the design of storage.",
        "The review does not mention that rule."),
    "call_limits_untouched": (
        "Does `review` say that the limits on each call are a problem that neither order fixes?",
        "The review says the limits on calls remain whichever half is built first.",
        "The review does not make this point."),
    "cannot_run_new_read_program": (
        "Does `review` say that today's services cannot run a new read program without upgrading the whole service?",
        "The review says new code enters a running service only through an upgrade of the whole service.",
        "The review does not make this point."),
    "doubts_agents_write_programs": (
        "Does `review` raise doubt about whether agents will write correct read programs?",
        "The review says it is uncertain that agents can write correct read programs.",
        "The review raises no such doubt."),
    "rework_overstated": (
        "Does `review` say that rewriting the write functions later would cost less than the document suggests?",
        "The review says the cost of rewriting write functions is smaller than the document makes it.",
        "The review does not say the document overstates that cost."),
    "storage_needs_known": (
        "Does `review` say that what storage must provide is already known from decisions already made?",
        "The review says the needs storage must meet are already fixed.",
        "The review does not say that the needs are already fixed."),
    "storage_needs_unsettled": (
        "Does `review` say that the design of storage depends on upper-half rules that are not yet settled?",
        "The review says storage cannot be designed well until some upper-half rules are settled.",
        "The review does not make this point."),
    "advises_no_database": (
        "Does `review` advise against building the database?",
        "The review tells the owner not to build the database.",
        "The review accepts that the database will be built."),
    "argues_from_speed": (
        "Does `review` give being usable sooner as a reason for the order it recommends?",
        "One of the review's reasons for its order is that something would be usable sooner.",
        "None of the review's reasons for its order is that something would be usable sooner."),
    "gives_case_against_itself": (
        "Does `review` give an argument against its own recommendation?",
        "The review states a case against the order it recommends.",
        "The review gives only arguments in favour of its order."),
    "reports_factual_error": (
        "Does `review` report a factual error in the documents it read?",
        "The review names at least one statement in the documents that it found to be wrong.",
        "The review names no statement in the documents as wrong."),
}

PREDICTED = {
    "upper_first_on_today": "NNN", "whole_storage_first": "NNN", "versioned_collection_first": "UYY",
    "disk_last": "NNY", "experiment_before_committing": "YYY", "runtime_change_needed": "UYN",
    "no_runtime_change_needed": "NNU", "sharing_lost_on_save": "NYY", "reads_not_logged": "YNN",
    "data_beyond_memory_open": "YNY", "capability_rule_matters": "YNU", "call_limits_untouched": "NYU",
    "cannot_run_new_read_program": "NNY", "doubts_agents_write_programs": "NYU", "rework_overstated": "YYN",
    "storage_needs_known": "UYN", "storage_needs_unsettled": "UNY", "advises_no_database": "NNN",
    "argues_from_speed": "NNN", "gives_case_against_itself": "YYY", "reports_factual_error": "YUY",
}

FIRST_STEP = {
    "sketch_of_the_boundary": "A small runnable sketch of the boundary between the two halves, before either half.",
    "versioned_collection_in_memory": "A collection that keeps versions without copying, held in memory, with no "
                                      "change to how state is saved.",
    "versioned_collection_and_saving": "A collection that keeps versions without copying, together with a change "
                                       "to how state is saved so that sharing survives.",
    "upper_half_on_todays_services": "The upper half, on today's services as they are.",
    "whole_storage_half": "The whole storage half, on disk.",
}
PREDICTED_FIRST_STEP = {"sol": "sketch_of_the_boundary", "opus": "versioned_collection_and_saving",
                        "gemini": "versioned_collection_in_memory"}

RELATION = {
    "supports": "The evidence shows that the claim is true.",
    "contradicts": "The evidence shows that the claim is false.",
    "says_nothing": "The evidence does not show whether the claim is true or false.",
}

CLAIMS = [
    ("sol_1", "Each replacement state is encoded and then decoded.", [("src/vm/service.c", 259, 266)], "supports"),
    ("sol_2", "A checksum is computed over the whole encoded state when an update is persisted.",
     [("src/vm/service.c", 455, 468)], "supports"),
    ("sol_3", "A read-only tool never produces a replacement state.", [("src/vm/service.c", 238, 243)], "supports"),
    ("sol_4", "Only a call that updated the state is persisted.", [("src/vm/service.c", 1114, 1118)], "supports"),
    ("sol_5", "A service's state, handler inputs and handler results may not contain capabilities.",
     [("docs/reference/README.md", 1106, 1108)], "supports"),
    ("opus_1", "When a value is saved, data shared inside it is written out in full and not as links.",
     [("docs/design/saved-state.md", 199, 200)], "supports"),
    ("opus_2", "Every new state of a service with a store goes through encode and decode before it is accepted.",
     [("docs/design/saved-state.md", 209, 212)], "supports"),
    ("opus_3", "Parameters marked as owned are duplicated before the handler is called.",
     [("src/vm/service.c", 292, 297)], "supports"),
    ("opus_4", "A table whose reference count is not 1 is copied when it is changed.",
     [("src/heap/table.c", 253, 272)], "supports"),
    ("opus_5", "Taking a snapshot deletes the log.", [("src/host/store.c", 470, 476)], "supports"),
    ("opus_6", "The limit on saved nodes is defined as 1 << 20.", [("src/base/limits.h", 364, 364)], "supports"),
    ("gemini_1", "After every fifth failure the supervisor records a restart, and at the third restart it stops "
                 "the service.", [("src/base/limits.h", 336, 338), ("src/vm/service.c", 1065, 1077)], "supports"),
    ("gemini_2", "The size of the process record is subtracted from the heap size.",
     [("src/vm/process.c", 117, 122)], "supports"),
    ("gemini_3", "The token is checked by a call to the listener.", [("src/tools/protocol-request.c", 132, 135)],
     "supports"),
    ("gemini_4", "The function `plan` calls `headers` on the request.", [("src/tools/protocol-request.c", 172, 175)],
     "supports"),
    ("gemini_5", "This line defines the limit on saved nodes.", [("src/base/limits.h", 221, 221)], "contradicts"),
    ("gemini_6", "The state is encoded and decoded on every write even when the service has no store.",
     [("src/vm/service.c", 268, 276), ("src/vm/service.c", 302, 305)], "contradicts"),
    ("gemini_7", "This code makes a copy of a whole table.", [("src/heap/table.c", 172, 188)], "supports"),
]


def ask(state, questions):
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
    return payload, reply


def noul(text, yes, no):
    return {"type": "noul", "instructions": text, "criteria": {"true": yes, "false": no}}


def label(p):
    return "Y" if p >= YES else "N" if p <= NO else "?"


def positions(record):
    table, first = {}, {}
    for who in REVIEWERS:
        questions = {name: noul(*parts) for name, parts in STATEMENTS.items()}
        questions["first_step"] = {"type": "choice", "instructions": "What does `review` recommend building first?",
                                   "criteria": FIRST_STEP}
        state = {"terms": TERMS, "review": (HERE / f"review-{who}.txt").read_text()}
        payload, reply = ask(state, questions)
        record[f"positions-{who}"] = {"request": payload, "reply": reply}
        for name in STATEMENTS:
            table.setdefault(name, {})[who] = reply["answers"][name]["noul"]
        first[who] = reply["answers"]["first_step"]
    print("POSITIONS  (probability each review says so: sol, opus, gemini)")
    surprises = []
    for name, row in table.items():
        got = "".join(label(row[who]) for who in REVIEWERS)
        kind = {"YYY": "all three", "NNN": "none"}.get(got, "unsettled" if "?" in got else "split")
        wrong = [who for who, want, have in zip(REVIEWERS, PREDICTED[name], got) if want != "U" and have != want]
        if wrong:
            surprises.append((name, wrong))
        print(f"  {name:30} " + " ".join(f"{row[who]:.2f}" for who in REVIEWERS)
              + f"  {got}  {kind:9} predicted {PREDICTED[name]}" + ("  <- differs: " + ",".join(wrong) if wrong else ""))
    print("FIRST STEP")
    for who in REVIEWERS:
        answer = first[who]
        ranked = sorted(answer["probabilities"].items(), key=lambda item: -item[1])[:2]
        print(f"  {who:7} " + ", ".join(f"{name} {p:.2f}" for name, p in ranked)
              + f"   predicted {PREDICTED_FIRST_STEP[who]}"
              + ("" if answer["choice"] == PREDICTED_FIRST_STEP[who] else "  <- differs"))
    return surprises


def excerpt(path, first, last):
    lines = (MO / path).read_text().splitlines()[first - 1:last]
    return {"file": path, "lines": f"{first}-{last}", "text": "\n".join(lines)}


def citations(record):
    print("CITATIONS  (verdict with options in two orders, then the smaller of the two top probabilities)")
    for name, claim, spans, predicted in CLAIMS:
        state = {"claim": claim, "evidence": [excerpt(*span) for span in spans]}
        question = "How does `evidence` relate to `claim`?"
        payload, reply = ask(state, {
            "forward": {"type": "choice", "instructions": question, "criteria": RELATION},
            "reversed": {"type": "choice", "instructions": question, "criteria": dict(reversed(RELATION.items()))}})
        record[f"citation-{name}"] = {"request": payload, "reply": reply}
        forward, backward = reply["answers"]["forward"], reply["answers"]["reversed"]
        agree = forward["choice"] == backward["choice"]
        least = min(forward["probabilities"][forward["choice"]], backward["probabilities"][backward["choice"]])
        verdict = forward["choice"] if agree and least >= SETTLED else "needs a person"
        print(f"  {name:9} {forward['choice']:12} {backward['choice']:12} {least:.2f}  -> {verdict:14}"
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
