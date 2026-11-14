# Which other specification languages fit?

Type: research
Status: resolved

## Question

Beyond TLA+ and Veil: Quint, P, Alloy, FizzBee, PlusCal, Apalache, Stateright, Ivy and any other found. For each, what it checks, how mature it is, how well agents write it, and how it fits four needs: a protocol whose steps interleave, the order of writes to disk with a crash at any step, rules about shapes of data (is one grant narrower than another), and tying a model to an implementation. Try the lightest ones hands-on with the same small protocol.

## Answer

Add Alloy 6 beside TLA+ for one job: rules about shapes of data, such as a grant never being wider than the grant it was made from. A 31-line Alloy model found a realistic narrowing error in one second. Keep TLA+ for the merge protocol and for disk writes. Quint uses the same logic and checkers as TLA+, so it would be a second notation for the same job. Every ready-made link from a model to running code belongs to another language; for Mo the fit is checking a recorded call log with TLC. Findings: [research/28-which-other-specification-languages-fit.md](../research/28-which-other-specification-languages-fit.md).
