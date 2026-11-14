# What lands together when a world holds more than one call?

Type: prototype
Status: resolved

## Question

A TLA+ model of an agent's world that holds two calls, such as a transfer written as "take" then "put". It compares the ways such a world could land: each call by itself or the whole world at once, with the rule checked after every call or once at the end. Predictions are written before the model, in `models/worlds-predictions.md`. Settings that are predicted to fail must fail. The model shows what goes wrong under each way. It does not make the choice.

## Answer

All 40 settings came out as predicted in `models/worlds-predictions.md`, which was committed before the model. Each call landing by itself either refuses a two-call change for ever or lands it with a gap that another agent can read and that can stay open for good. The whole world landing with the rule checked at the end lets an agent combine approved calls into a change neither could make. The whole world landing with the rule checked after every call got nothing wrong in the six cases; its price is that a change whose middle breaks a rule must be one approved function. The recorded reads must be run again in place. Robert chose that last way on 2026-11-14: a world lands whole, and the rule is checked after every call. Results and limits are in `models/README.md`.
