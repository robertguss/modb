#!/usr/bin/env python3
"""Second pass: the judgments that differed from the predictions, each split into smaller ones."""
import json

from evaluate import HERE, REVIEWERS, TERMS, ask, label, noul

STATEMENTS = {
    "proposes_explicit_ids": (
        "Does `review` propose that versions share data through explicit identifiers for nodes?",
        "The review proposes nodes that refer to each other by identifier so that versions can share them.",
        "The review proposes no such identifiers."),
    "collection_written_in_language": (
        "Does `review` propose writing the versioned collection in the language itself?",
        "The review says the versioned collection is written as a program or library in the language.",
        "The review says the collection is built into the runtime or host, or does not say where it is written."),
    "saved_format_must_keep_sharing": (
        "Does `review` propose changing how state is saved so that the saved form keeps sharing?",
        "The review proposes a change to the saving of state so that shared data stays shared.",
        "The review proposes no change to how state is saved."),
    "rewrite_avoidable": (
        "Does `review` say that a later rewrite of the write functions can be avoided?",
        "The review describes a way to keep the write functions from needing a rewrite.",
        "The review does not say the rewrite can be avoided."),
    "rewrite_cheap": (
        "Does `review` say that a later rewrite of the write functions would be cheap?",
        "The review says rewriting the write functions would cost little.",
        "The review does not say the rewrite would cost little."),
}
PREDICTED = {"proposes_explicit_ids": "NNY", "collection_written_in_language": "UUY",
             "saved_format_must_keep_sharing": "NYN", "rewrite_avoidable": "YUN", "rewrite_cheap": "UYN"}

record, table = {}, {}
for who in REVIEWERS:
    payload, reply = ask({"terms": TERMS, "review": (HERE / f"review-{who}.txt").read_text()},
                         {name: noul(*parts) for name, parts in STATEMENTS.items()})
    record[f"followup-{who}"] = {"request": payload, "reply": reply}
    for name in STATEMENTS:
        table.setdefault(name, {})[who] = reply["answers"][name]["noul"]
for name, row in table.items():
    got = "".join(label(row[who]) for who in REVIEWERS)
    wrong = [who for who, want, have in zip(REVIEWERS, PREDICTED[name], got) if want != "U" and have != want]
    print(f"  {name:32} " + " ".join(f"{row[who]:.2f}" for who in REVIEWERS) + f"  {got}  predicted {PREDICTED[name]}"
          + ("  <- differs: " + ",".join(wrong) if wrong else ""))
(HERE / "results-followup.json").write_text(json.dumps(record, indent=1))
print("input tokens", sum(entry["reply"]["usage"]["input_tokens"] for entry in record.values()))
