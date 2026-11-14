# Can a Mo library keep old versions cheaply today?

Type: prototype
Status: resolved

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

## Answer

Resolved on 2026-11-14. The sketch is [sketches/kept-versions/](../sketches/kept-versions/), and how to run it is in [sketches/README.md](../sketches/README.md). It ran on `mo` 0.2.0 built from Mo's commit `ef37424`, optimised as Mo's own benchmark builds it.

**In short.** Keeping an old version is cheap in space today, with no change to Mo: 778 bytes for each kept version, at any size measured, and the old versions are still there after a restart. A write is no cheaper for it. Every write to a service still costs in proportion to all of the state, and the tree makes that a little worse. So the reviewers were each half right. Gemini Carbon's nodes named by number work in Mo as it stands. Claude Opus was right that sharing by reference does not survive a save. That review said a saved form that keeps sharing was needed; the sketch keeps versions cheaply without one.

### Against the predictions

| # | Predicted | Found |
| --- | --- | --- |
| 1 | By reference and whole maps grow by a full copy for each kept version | As predicted. See the first table below |
| 2 | By number, a kept version adds less than 2 KiB at any size | As predicted: 778 bytes at 1,000, 10,000 and 50,000 rows |
| 3 | Outside a service a lookup takes 5 to 15 times a `Map` lookup, an insert 10 to 50 times | As predicted, after a rewrite: a lookup 12.7 to 14.5 times, an insert 33 times |
| 4 | In a service a write to the tree is the same to 3 times slower than a write to a plain `Map` | As predicted: 1.1 to 1.5 times slower |
| 5 | At 10,000 rows and 100 kept versions, by reference and whole maps are refused for passing the limit on saved state, and by number is not | The refusals came, far sooner and for another reason: the call ran out of memory, after 19 and after 13 kept versions |
| 6 | The workload needs no change to Mo | As predicted: six tests pass, and the control fails |

### What a kept version costs

Each service was grown to a number of rows of 64 bytes, and `put` was then called until 100 versions were kept or a call was refused. Saved size is what `mo-memory` reports for the encoded state.

| Rows | Way | Saved, no version kept | Added to the saved size by each kept version | Added in memory by each | Kept before a refusal |
| --- | --- | --- | --- | --- | --- |
| 1,000 | by number | 94,683 bytes | 778 bytes | 1,690 bytes | 100, none refused |
| 1,000 | by reference | 77,477 | 74,511 | 147,679 | 100, none refused |
| 1,000 | whole maps | 76,140 | 73,267 | 175,535 | 100, none refused |
| 10,000 | by number | 939,483 | 778 | 1,690 | 100, none refused |
| 10,000 | by reference | 768,677 | 767,900 | 1,493,868 | 19 |
| 10,000 | whole maps | 760,140 | 759,619 | 2,082,527 | 13 |
| 50,000 | by number | 4,694,051 | 778 | 1,690 | 100, none refused |
| 50,000 | by reference | 3,840,589 | 3,840,250 | 7,467,426 | 3 |
| 50,000 | whole maps | 3,800,140 | 3,799,922 | 9,611,278 | 2 |

- By number, a kept version costs the six nodes between the root and the changed row.
- The other two cost one whole copy of the rows, on disk and in memory, because Mo writes shared data out in full and reads that copy back after every write.
- Every refusal was `memory_limit`, "the call ran out of memory; service state is unchanged". Memory ran out before the limit on saved state was reached.
- After a restart each service still gave the first value of row 0 from its oldest version and the changed value from its newest.
- With no version kept, the tree by number is 24% larger when saved than a plain `Map` of the same rows, and 11% larger in memory at 50,000 rows.

### What a write costs in a service

Median time of one `put`, measured from the client, over the 90 calls between 10 and 100 kept versions. The plain map is the service from [How fast and how large is a Mo service today?](11-how-fast-and-large-is-a-mo-service.md), which keeps no version.

| Rows | Tree by number, keeping a version | Plain `Map`, keeping none | Ratio |
| --- | --- | --- | --- |
| 1,000 | 20.3 ms | 18.7 ms | 1.1 |
| 10,000 | 35.6 ms | 28.6 ms | 1.2 |
| 50,000 | 66.4 ms | 43.9 ms | 1.5 |

That is about 0.94 ms for each 1,000 rows by number against 0.51 ms for the plain map. The cause is the service, not the collection: it copies the map of nodes when the function first changes it, then encodes, decodes and checksums the whole state. The tree only adds more to encode.

### What an insert and a lookup cost outside a service

The fastest of five runs of `mo run`, at 20,000 and 60,000 rows.

| Operation | `Map` | Tree by number | Ratio |
| --- | --- | --- | --- |
| Insert | 0.74 to 0.82 µs | 24.7 to 27.1 µs | 33 |
| Lookup | 0.83 to 0.87 µs | 11.1 to 12.0 µs | 12.7 to 14.5 |
| Insert that keeps the version before | none | 31.3 to 33.4 µs | |

The tree is not tuned. It has five levels of 16 slots whatever its size.

### Three things the sketch ran into

**Mo copies a map that sits in a record every time the map changes.** The first tree was a record holding the map of nodes and three numbers. It took 49.7 seconds to insert 20,000 rows, 2.5 ms each. `in-place.mo` isolates it, adding rows to a map six ways. A way that copies the map takes four times as long for twice the rows:

| Way of changing the map | 20,000 rows | 40,000 rows |
| --- | --- | --- |
| Assign the field of a record that stays in one function | 5.4 s | 22.6 s |
| Assign the field of a record passed to a function | 5.6 s | 23.9 s |
| Take the map out of the record first | 5.9 s | 23.0 s |
| Take the record apart and build it again | 5.6 s | 22.6 s |
| Pass the map alone | 0.13 s | 0.11 s |
| Return the map in a tuple that is taken apart at once | 0.08 s | 0.14 s |

The first row is the form section 6.2 of Mo's reference gives for changing a field, `cart.items = cart.items.append(item)`, here with a map. For the three rows that pass the record to a function, Mo's bytecode (`mo check --emit=bytecode`) marks the record parameter `borrowed`; for the last two rows it marks the map parameter `owned`. A borrowed record is still held by the caller, so its map has two holders and is copied. The tree was rewritten as a bare map with its three numbers kept in the map under number 0. That is what made an insert cost 25 µs. It is an awkward shape for a library. Sections 6.2 and 13.3 of the reference promise a change in place when a value has one holder, and neither says that a map in a record has two.

**A call's instruction limit is reached by a few hundred tree inserts.** 1,000 inserts into the tree in one call were refused with `work_limit`. 400 fit. A plain `Map` takes 20,000 in one call.

**A view cannot be a value in a service's state.** A service's state may hold no function. In `worlds.mo` a view is a named function, `low?`, passed to `ask` and `act`. A grant kept as data would have to name its function.

### The workload

`worlds.mo` keeps balances in the tree by number. The rule is that their total never changes.

- A world starts as one number, the root of the main line. Its first call added at most 12 nodes to the tree and left the main line as it was.
- Two worlds that touch different rows both land. The main line as it was before them can still be read.
- When two worlds asked about the same row and one has landed, the other is sent back with `Moved`, and nothing changes. The second world's call would have succeeded if it had run; it is sent back because the answer it relied on is no longer true.
- A world whose second call breaks the rule lands nothing.
- A view keeps a world from asking about, or changing, a row outside it.

The control: with the check of the questions removed from `land`, the second overlapping world lands, and `mo test` reports `11 passed, 1 failed`.

### What this means for the order

- Worlds, history and kept versions do not wait for the storage half. They can be built on a collection by number in Mo today, up to the sizes a service holds.
- What the storage half must fix is not versions. It is that every write costs in proportion to all of the state, in time and in memory.
- Three smaller things belong to Mo and not to the database: a map in a record is copied on every change, a call's instruction limit is reached by a few hundred tree inserts, and a service's state cannot hold a function.

### Not shown

- Freeing the nodes of a version nobody keeps. Mo does not do it, and the sketch has no function for it. A long-lived tree grows until that exists.
- Removing a row.
- The worlds running as a service. They ran as functions under `mo test`.
- The largest tree by number a service will hold.
- A quiet machine throughout. The load was 2.1 falling to 1.5 while the services were measured, 1.0 to 1.4 for the inserts and lookups, and 0.6 to 1.0 for `in-place.mo`.
- The rule in the workload sums every row after every call, which costs in proportion to the rows. A real rule over many rows needs a total that is kept up to date.
