# Can a Mo library keep old versions cheaply today?

Type: prototype
Status: claimed

## Question

AFK, by Robert's decision on 2026-11-14: "I think you should open a prototype ticket and build that sketch. Before we choose the order." It is the experiment all three reviewers asked for on [Which half comes first?](36-which-half-comes-first.md), and it is meant to settle the point they differ on.

A versioned collection keeps an old version beside a new one, and the two share everything that did not change. Mo writes shared data out in full when it saves a service's state, so sharing does not survive a save. Claude Opus said cheap versions therefore need a change to how Mo saves. Gemini Carbon proposed giving every node a number and having nodes name each other by number. Which holds in Mo as it stands?

The sketch is in `sketches/kept-versions/`. It builds one collection of numbered rows three ways:

- **By number.** A tree whose nodes sit in one map and name their children by number.
- **By reference.** The same tree with each node holding its children directly. This is the control.
- **Whole maps.** A list of Mo's own `Map`, one whole map for each version. This is what a program does today.

It measures the saved size of each as kept versions grow, the cost of one insert and one lookup against `Map` outside a service, and the time of one write in a running service. It then runs one small workload on the tree by number: two worlds that overlap, a narrowed view, and a landing with the rule checked after every call.

## Predictions, written before any code ran

1. By reference and whole maps: the saved size grows by about one full copy for each kept version.
2. By number: each kept version adds less than 2 KiB to the saved size, whatever the number of rows, because a change copies only the nodes between the root and the row.
3. Outside a service, a lookup by number takes 5 to 15 times as long as a `Map` lookup, and an insert takes 10 to 50 times as long as a `Map` insert.
4. In a running service, a write to the tree by number is not faster than a write to a plain `Map` holding the same rows. Predicted: between the same and 3 times slower. The service still copies the map of nodes and encodes and decodes the whole state on every write.
5. At 10,000 rows and 100 kept versions, by reference and whole maps are refused for passing the limit on saved state, and by number is not.
6. The workload can be written in Mo with no change to Mo: a world costs one number to start, a failed landing changes nothing, and the second of two overlapping worlds is sent back.

Known before the sketch, so not predictions: a service's state may not hold a function, so a view is a named function in the program and not a value in the state. Mo does not free the nodes of a version nobody keeps any more; the library has to.
