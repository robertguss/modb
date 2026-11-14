# What lands together when a world holds more than one call?

Type: prototype
Status: claimed

## Question

A TLA+ model of an agent's world that holds two calls, such as a transfer written as "take" then "put". It compares the ways such a world could land: each call by itself or the whole world at once, with the rule checked after every call or once at the end. Predictions are written before the model, in `models/worlds-predictions.md`. Settings that are predicted to fail must fail. The model shows what goes wrong under each way. It does not make the choice.
