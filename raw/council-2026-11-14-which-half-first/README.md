# Council review, 2026-11-14: which half first

Sources for [Which half comes first?](../../issues/36-which-half-comes-first.md). Never edited.

- `gpt-sol.md`, `claude-opus.md`, `gemini-carbon.md`: the three reviews as delivered. The only change is that the home folder was cut from file paths, so `mo/src/...` is Mo and a bare path is this repository.
- `typesafe/evaluate.py` and `typesafe/followup.py`: the questions put to TypeSafe's Jev, the predictions written before each run, and the code that turns the answers into verdicts.
- `typesafe/evaluate.out`: what the first run printed.
- `typesafe/results.json` and `typesafe/results-followup.json`: every request as sent and every reply.
- `typesafe/results-followup-rerun.json`: the second pass sent again by mistake. Its answers differ from the first by at most 0.04.

Line numbers in the reviews and in `evaluate.py` are those of Mo at commit `392f3bf9`. Mo's files have moved since, so running the script again reads other lines. `results.json` holds the excerpts that were sent.

`evaluate.py` differs from the script that ran in one line: the path to Mo no longer names a home folder. It needs `TYPESAFE_API_KEY` in the environment.
