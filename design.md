# The data store and the database, designed from what they need

Claude's draft of 2026-11-14, written at Robert's request after his steer that the work had become "too focused on what can Mo do today and not what Mo needs to be able to do". It designs the two halves as if Mo already had what they need. The last part lists what that is.

Nothing here is decided unless it says "decided by Robert". The ideas come from [design-ideas.md](design-ideas.md), which keeps their history and the earlier work behind each. The measurements are evidence for the list of what Mo must gain. They do not shape the design.

## 1. What it is for

Many AI agents work on the same data at once. Each needs to ask questions nobody planned for, to try changes without harming anyone else's work, and to leave a record a person can trust of who changed what and why.

**What is new, in one sentence.** Claude's proposal: a store that many agents share, in which every question is a program checked before it runs, every change is a call to a function a person approved, and each agent works in its own version of the data, which lands whole or not at all.

It has no query language. Questions, rules, permissions and changes are all written in Mo.

## 2. The whole in one picture

```
agents      send: read programs, calls to approved functions, proposals
   |
DATABASE    worlds, grants, rules, landing, the log of calls
   |        asks the store for: a version, a row, a change, the differences between two versions
DATA STORE  a tree of nodes written once, roots, the log on disk, views kept current, freeing
   |        asks Mo for: bytes at a place in a file, forced to disk, and a hash
MO          the language, the runtime, capabilities
```

The data store keeps data and versions of it. It knows nothing of agents. The database is what agents meet: it decides who may ask what, what may change, and what lands.

## 3. The data store

### What it must do

1. **Hold more than fits in memory.**
2. **Make a write cost what it changes,** not what the store holds.
3. **Make a version cheap.** A version is the data as it stood at one moment. Every read program needs one to run on, every agent's world is one, and every past question that is run again needs the one it was asked on.
4. **Survive a crash at any moment** with nothing half-written.
5. **Find the differences between two versions** at a cost in proportion to the differences.
6. **Find things without reading everything.**
7. **Keep the log of calls for good.**
8. **Forget on purpose:** free a version nobody holds, and erase one person's data from every version.
9. **Let readers run while the writer writes.**

### The design

**Store the data the way Mo already holds a value.** A Mo value never changes once made. On disk that is a tree of nodes, each written once. A change writes new nodes along one path from the root to the row and shares every other node with the version before. Each node is named by the hash of its contents.

| Part | What it is | Which need it meets |
| --- | --- | --- |
| The tree of write-once nodes | Rows at the leaves, branches above them, every node named by its hash | 1, 2 |
| A root | The name of one node at the top. A version is a root, and so are a snapshot, an old state and an agent's world | 3 |
| The order of writes | New nodes first, then the log entry forced to disk, then the root is switched. Nothing is ever overwritten | 4 |
| Shared nodes | Two versions share every node that neither changed, and a shared node has the same name in both. Walking only where the names differ finds the differences | 5 |
| Views kept current | A view is a function from the data to other data. An index and a saved answer are views. The store updates each one from the rows a write changed | 6 |
| The log of calls | One file that only grows. Each entry names the function called, its arguments, its caller, and the root before and after | 7 |
| Code stored by hash | Each approved function is kept under the hash of its checked form, and a log entry names the function by that hash. An old call can then always be run again with the code that ran at the time | 7 |
| Holders | A version is kept while the main line, an open world or the history policy holds its root. A node no kept version reaches is freed | 8 |
| Readers on roots | A reader holds a root, which never changes, so it does not wait for the writer | 9 |

The tree can be rebuilt from the log, because the same call always gives the same result. Only the log has to reach the disk before a reply is sent.

**What it offers the database.** Seven operations, in plain words: read a row of a version; change a row, giving a new version; keep a version; list the rows of a version; list the differences between two versions; add an entry to the log; say which versions are still held.

### What each strength costs

- **Cheap versions cost a path on every change.** A change rewrites every node between the root and the row.
- **Sharing costs reads.** A read hops from node to node. The survey found no system with shared storage and fast reads.
- **Never overwriting costs space.** Old versions pile up, and freeing them is work the store must do in the background.
- **Names by hash fight erasing.** Erasing a row from an old version changes the hashes above it. The store can leave a marked hole where a node was. This is not designed yet.
- **Only some views can be kept current.** A sum, a count and a filter can. An arbitrary program cannot.

### What the sketches already showed

A tree of this shape, written in Mo as it stands, kept a version for 778 bytes at any size measured, where a whole copy cost megabytes ([ticket](issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md)). Its nodes were named by number, because Mo has no hash. The shape works. Its speed there says nothing about the design: it ran as bytecode inside a service that re-saves its whole state on every write.

## 4. The database

### What it must do

1. **Answer any question** without a query language and without a function written for it beforehand.
2. **Change data only in ways a person approved,** and record each change with who made it, under which grant, for which task and why. This is the accountable write.
3. **Show each caller only what its grant allows.**
4. **Keep the rules a person approved true after every change.**
5. **Let many agents work at once** with no locks, however long each one thinks.
6. **Let agents extend it,** with a person deciding whenever more becomes possible.
7. **Keep a history that can be checked, searched and repaired.**
8. **Keep sensitive data from leaving** except in forms a person approved.
9. **Teach an agent that remembers nothing** what it may do.

### The design

**Five kinds of Mo code.** Four are approved by a person. The fifth is free.

| Kind | What it says | Who writes it |
| --- | --- | --- |
| Types and promises | What the data is and what must stay true | A person approves |
| View functions | What a caller may read: a function from the full data to a narrower type | A person approves a wider one; a narrower one is free |
| Write functions | How the data may change. Each call is an accountable write | A person approves |
| Release functions | What may leave, such as a count or an average over at least ten | A person approves |
| Read programs | Any question. A read program cannot change anything | Any agent, with no approval |

**One question, start to finish.**

1. The agent writes a small Mo function. Its parameters are the only data it can touch.
2. The database compiles it against the type its grant's view gives. A program that mentions a field the view leaves out does not compile.
3. It runs on a version, under a limit on its work.
4. The program, its caller, the version and the answer are recorded.

**One world, start to finish.** A world is an agent's own version of the data.

1. The agent opens a world. This costs one root.
2. It asks questions and calls write functions. It sees its own changes. Nobody else does.
3. It lands the world. The database replays the world's calls, in order, on the main line as it now stands.
4. Each replayed call checks its own conditions again. The rules are checked after every call.
5. Every question the agent asked is asked again. A different answer means the agent decided on something that is no longer true.
6. The world lands whole, or it goes back to the agent with the reason and nothing changes.

**Asking again costs what changed.** The store lists the rows that differ between the version a question was asked on and the main line. A question whose answer those rows cannot have changed needs no second reading. A world opened on the version that is still the main line has nothing to ask again. The same holds for a rule.

**Helpers get less, never more.** An agent hands a helper a grant made from its own: a view on top of its view, fewer functions, a limit on calls and an end time. The helper works in a world opened from the agent's world.

**Proposals.** An agent may propose a new view, write function, release function, type or promise as Mo code. The machine checks it first. A person then reviews what would become possible, not the code.

**The log is the truth.** Audit is reading the log. Taking one agent's work out is replaying the log without its calls; the later calls that are then refused are the ones that depended on it.

### What Robert has decided

- The database stays the destination, and nothing in it presupposes SQL or the relational model.
- A read program only reads.
- Agents may propose, and a person approves.
- A world lands whole or not at all, and the rules are checked after every call in it.
- At landing every question the agent asked counts, by its answer.
- For the first version one operation runs at a time. This design asks to narrow that to one write at a time; he has not accepted the change.

### Not designed yet

- **Need 8.** Sensitivity that travels in the types is an idea with no design, and Mo has nothing for it.
- **Need 9.** What an agent with no memory is shown first.
- **Fairness.** An agent that thinks for a long time keeps losing to agents that work fast.
- **Which reads count.** An agent reads much that it does not rely on. Counting needless send-backs is how the finer rule would be chosen.

## 5. What Mo must gain

Each line is an ability other programs would also use, which is Robert's test for anything Mo gains. "Mo today" is what was read in Mo's source or measured on 2026-11-14.

| # | Mo must be able to | The design uses it for | Who else would use it | Mo today |
| --- | --- | --- | --- | --- |
| 1 | Write bytes at a place in a file, read from a place, force them to disk, and rename a file | The store's own file and log | Any program that keeps data: logs, caches, downloads | A file is read whole. Text can be written whole or added at the end. Bytes cannot be written, and there is no reading or writing at a place, no forcing to disk and no renaming |
| 2 | Hash bytes | Naming nodes and code | Checksums, finding duplicates, signatures | No such function |
| 3 | Let a service keep data outside its one saved state | The store, held by the service that is the database | Any service whose data grows, such as Mo's task queue | The whole state is re-saved on every write: 17 ms plus 0.66 ms for every 1,000 small rows, and writes stop at about 125,000 rows. A service's state and handlers may hold no capability |
| 4 | Keep a large collection whose copies share what did not change | The tree | Undo, snapshots, any program that keeps old states | A `Map` is one block and a changed copy is a whole copy. Written as a library, an insert took 33 times a `Map` insert |
| 5 | Give a call the work it needs, set by the service, and refuse a call without counting it against the service | Read programs and landings of any size | Any service with one slow tool | A fixed 1,048,576 instructions, about 26 ms. Fifteen refused calls, five to a minute, stop the service |
| 6 | Run reads while a write runs | Read programs and worlds, which hold a root that never changes | Any service with slow reads | One operation at a time. A read waited 91 ms behind writes |
| 7 | Accept a caller's program while running, check it, and run it holding only what the caller holds | Read programs and proposals | Plug-ins, rules a user writes, any service that is extended while it runs | New code arrives only by upgrading the whole service. `mo query` runs a caller's function on a copy that takes 28 seconds to fetch at 50,000 rows |
| 8 | Tell callers apart, and hand a caller a grant that can be narrowed | Grants, helpers, the accountable write | Any service with more than one user | One token for a whole service |
| 9 | Keep a log the program owns, with reads in it | History, audit, replay, asking again | Any service that must show what happened | A read is not logged, and a snapshot deletes the log |
| 10 | Check a promise when a write lands, not only in a test | Rules written once | Any service with a rule that must always hold | A promise is checked by `mo test` only, so a rule is written twice |
| 11 | Simulate a disk that tears, loses and corrupts writes, and many callers at once | Checking the store and the landing rule | Any program that writes files | Simulation has neither |
| 12 | Take and give more than a few kilobytes in one request | Read programs and their answers | Any service that moves documents | A request is at most 16 KiB and a reply 32 KiB |
| 13 | Carry a label on sensitive data in its type | Need 8 of the database | Any program that handles secrets | Nothing |

Three smaller matters belong to Mo whatever is built on it. A map held in a record is copied every time it changes. Every call spends about 10 ms in the layer that reads the request. The child process that compiles arriving code runs with the server's own access.

**The order Claude would take them in.** Lines 1 to 4 are the data store, and nothing else can be built without them. Lines 5 to 9 are the database above it. Lines 10 to 13 can follow.

## 6. What this draft leaves open

- **Library or runtime.** The store can be a library written in Mo, where every step that touches the disk is visible and can be simulated, or part of the runtime, where any value can live on disk. Line 3 above is where that is chosen. Claude leans to the library.
- **Names by hash or by number.** Hashes let anyone check history and compare versions. Numbers are cheaper and do not fight erasing.
- **Which real data goes in first.** [What real data of yours goes in first?](issues/12-what-real-data-goes-in-first.md) is still open.
- **Where this sits beside Phases 6 to 8** of Mo: [Does Phase 6 finish before database work starts?](issues/13-does-phase-6-finish-first.md).
- **The map's rule.** [The map](map.md) says no database code and no change to Mo is part of it. Building any line of the table means lifting that rule or starting a new effort. That is Robert's decision.
