# Does the replay rule catch what merges get wrong?

Type: prototype
Status: resolved

## Question

A TLA+ model of the replay rule from design-ideas.md ("Many agents working together"). Predictions are written before the model, in `models/replay-predictions.md`. The model runs six cases with each of the three mechanisms (the write function's own check, the promises, the recorded reads) switched on and off, and shows which mechanism catches which case. Settings that are predicted to fail must fail.

## Answer

Yes, for the six cases modelled. All 48 settings came out as predicted in `models/replay-predictions.md`, which was committed before the model. The recorded reads alone caught all five mistakes; the function's own check and the promises caught the three that break a declared rule. A call that says what it means needed no mechanism, and the recorded reads sent it back for nothing. The model is tiny and leaves out worlds with more than one call. Results and limits are in `models/README.md`.
