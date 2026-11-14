# Does the replay rule catch what merges get wrong?

Type: prototype
Status: claimed

## Question

A TLA+ model of the replay rule from design-ideas.md ("Many agents working together"). Predictions are written before the model, in `models/replay-predictions.md`. The model runs six cases with each of the three mechanisms (the write function's own check, the promises, the recorded reads) switched on and off, and shows which mechanism catches which case. Settings that are predicted to fail must fail.
