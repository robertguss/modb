# How have storage engines and databases been checked?

Type: research
Status: resolved

## Question

What methods, tools and papers exist for checking a storage engine and a database, what each catches and misses, what it cost and what its users reported: small executable models with generated tests, deterministic simulation, crash-consistency testing, checkers of isolation and of histories, design models tied to the implementation by its traces, full proofs of storage systems, and recent work on agents writing models and proofs. The wiki already covers part of this; add what is missing. End with a checking plan for one person and agents building a storage engine and a merge protocol in a new language.

## Answer

The method with the best return is a small model written in the code's own language and checked against the code with generated call sequences; Amazon reports models under 2% of the code and bugs found at each of three layers. Mo's recovery check restarts a service on an in-memory store, so it does not test a disk that loses or tears writes. A database that writes down its own order can check its history by replaying it, which is far cheaper than checking from outside. The plan in the findings file adds a reference model in Mo for each part first, and advises checking real code under simulated crashes in place of a TLA+ model of disk writes. Findings: [research/29-how-have-storage-engines-and-databases-been-checked.md](../research/29-how-have-storage-engines-and-databases-been-checked.md).
