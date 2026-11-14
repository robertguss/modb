# The data store and the database, designed from what they need

Claude's draft of 2026-11-14, written at Robert's request after his steer that the work had become "too focused on what can Mo do today and not what Mo needs to be able to do". It designs the parts as if Mo already had what they need. Section 8 lists what that is. It was re-ordered the same day at Robert's decision: the ordinary application is the base case, and agents are a layer on top.

Nothing here is decided unless it says "decided by Robert". The ideas come from [design-ideas.md](design-ideas.md), which keeps their history and the earlier work behind each. The measurements are evidence for the list of what Mo must gain. They do not shape the design.

## 1. What it is for

**The base: any Mo program that keeps data.** A web application, a service or a tool written in Mo keeps typed data that outlasts the program and may be larger than memory. The program changes that data through its own functions, asks questions of it, and relies on rules that stay true.

**The layer on top: callers that are not part of the program.** These are AI agents above all, many at once, and also a person with a question nobody planned and a report. Each needs to ask questions nobody planned for, to try changes without harming anyone else's work, and to leave a record a person can trust of who changed what and why.

**Decided by Robert on 2026-11-14.** He said the first draft was "a bit too fixated on agents doing everything" and asked how an ordinary web application in Mo would store and query its data and where its business logic goes. He then answered "Yes" to making the ordinary Mo application the base case, with agents as a layer on top.

**What is new.** Claude's proposal, not accepted:

- The base: durable data that is part of the Mo program. The types are the schema, the program's functions are the only way the data changes, and every change is recorded.
- The layer: many agents share that same data. Each asks questions as programs checked before they run, and each works in its own version of the data, which lands whole or not at all.

Earlier systems did much of the base ([Code inside the database, and databases inside a language](issues/07-code-inside-the-database.md)). What would be new is the two together.

It has no separate query language. Questions, rules, permissions and changes are all written in Mo.

## 2. The whole in one picture

```
a page handler, a job             agents, a person's unplanned question, a report
part of the program               not part of the program
        |                                   |
        |                         THE LAYER FOR OUTSIDE CALLERS
        |                         grants, read programs, worlds, landing, proposals
        |                                   |
THE DATABASE     tables, indexes, write functions run whole, promises, the log of calls
        |        asks the store for: a version, a row, a change, the differences between two versions
THE DATA STORE   a tree of nodes written once, roots, the log on disk, views kept current, freeing
        |        asks Mo for: bytes at a place in a file, forced to disk, and a hash
MO               the language, the runtime, capabilities
```

The data store keeps data and versions of it. It knows nothing of who calls. The database is what a program meets. The layer is what an outside caller meets: it decides who may ask what, what may change, and what lands.

## 3. The base case: an ordinary application

A web application written in Mo that keeps users, items and orders. No agent is involved. The `store` block, `Table` and the `index` lines below are proposed and do not exist in Mo. The rest is Mo as it is.

```mo
struct User
  email: Text
  name: Text
end

struct Order
  buyer: Int
  item: Int
  count: Int
end

store Shop
  users: Table(Int, User)
  stock: Table(Int, Int)
  orders: Table(Int, Order)
  index users_by_email: users by email
  index orders_by_buyer: orders by buyer

  promise "stock never goes below zero"
    after.stock.all(fn(_item, left) left >= 0 end)
  end
end

fn place_order(shop: Shop, _now: Time, buyer: Int, item: Int, count: Int) : Result(Shop, OrderError)
  left = shop.stock.get(item) or 0
  return Error(SoldOut(item)) if left < count
  var next = shop
  next.stock = shop.stock.set(item, left - count)
  next.orders = shop.orders.add(Order(buyer: buyer, item: item, count: count))
  Ok(next)
end

fn orders_of(shop: Shop, email: Text) : List(Order)
  case shop.users_by_email.get(email)
    Some(buyer): shop.orders_by_buyer.all(buyer)
    None: []
  end
end
```

**The schema is the types.** There are no tables to declare elsewhere, no query strings and no layer that maps rows to objects. The compiler checks every use of the data.

**The business logic is ordinary functions.** `place_order` is the application's own code. The page handler calls it. The database runs it whole or not at all, checks the promises, records the call with the signed-in user, and saves only the nodes that changed. A tool of a Mo service already has this shape today. What changes is that the state no longer has to fit in memory or be saved whole.

**A query is a function that only reads.** It gets data three ways:

- by key, as `shop.stock.get(item)`;
- through an index the program declared, as `shop.users_by_email.get(email)`. The store keeps an index current on every write;
- by walking a collection, as any Mo code may. This is the slow way.

**How it is stored.** Each `Table` is a tree of nodes written once, on disk. A row is a leaf. An index is a second tree. Only the nodes a request touches are read into memory.

**Where it runs.** In the application's own process. The store is a part of Mo that a program uses, not a server it connects to.

**Changing the schema** is an upgrade of the program, with a function from the old types to the new ones.

**What this case gets without asking.** Every change is in the log with who made it. Any past state can be read. The whole application, store included, runs under `mo test` with a fake disk and a fake clock.

**Where this case is weak.**

- **A question nobody declared an index for walks everything.** Nothing chooses a fast route, as a query planner does. A form of "the orders where..." that the compiler can match to an index is an idea with no design. This is the largest gap for an ordinary application.
- **Only Mo programs can read the data.** A reporting tool or a spreadsheet cannot. Object databases lost to relational ones on this.
- **Reads hop from node to node,** which is slower than a table laid out for reading.
- **For this case alone, SQLite is hard to beat.** What this offers over it is checked types from page to disk, logic and data that change together, and history, undo and simulation with no extra work.

## 4. The data store

### What it must do

1. **Hold more than fits in memory.**
2. **Make a write cost what it changes,** not what the store holds.
3. **Make a version cheap.** A version is the data as it stood at one moment. Every read needs one to run on, every outside caller's world is one, and every past question that is run again needs the one it was asked on.
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
| A root | The name of one node at the top. A version is a root, and so are a snapshot, an old state and a world | 3 |
| The order of writes | New nodes first, then the log entry forced to disk, then the root is switched. Nothing is ever overwritten | 4 |
| Shared nodes | Two versions share every node that neither changed, and a shared node has the same name in both. Walking only where the names differ finds the differences | 5 |
| Views kept current | A view is a function from the data to other data. An index and a saved answer are views. The store updates each one from the rows a write changed | 6 |
| The log of calls | One file that only grows. Each entry names the function called, its arguments, its caller, and the root before and after | 7 |
| Code stored by hash | Each write function is kept under the hash of its checked form, and a log entry names the function by that hash. An old call can then always be run again with the code that ran at the time | 7 |
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

## 5. The database: what every program gets

### What it must do

1. **Hold the program's data in the program's own types,** with no second schema.
2. **Change data only through the program's write functions,** each run whole or not at all, and record each call with who made it. This is the accountable write. For an outside caller the record also says under which grant, for which task and why.
3. **Keep the rules the program declares true after every change.**
4. **Answer the program's questions without reading everything.**
5. **Change shape when the program changes.**
6. **Keep a history that can be checked, searched and repaired.**

### The design

**Three kinds of code, all part of the program.**

| Kind | What it says |
| --- | --- |
| Types and promises | What the data is, which indexes are kept, and what must stay true |
| Write functions | How the data may change. A write function takes the data and returns the changed data or an error |
| Queries | Functions that only read |

**One write, start to finish.**

1. A page handler calls a write function with its arguments.
2. The function runs on the current version and returns a new version or an error. An error changes nothing.
3. The promises are checked on the new version.
4. The call is added to the log, and the log is forced to disk.
5. The root is switched to the new version, and the reply is sent.

**One query, start to finish.** It takes the current root and reads from it. The root never changes, so the query does not wait for a write and never sees half of one.

**The log is the truth.** Audit is reading the log. Taking one caller's work out is replaying the log without its calls; the later calls that are then refused are the ones that depended on it.

**A change of shape is an upgrade of the program,** with a function from the old types to the new ones. Mo already upgrades a running service this way.

### Not designed yet

- **A question in a form the compiler can match to an index.** Without it a question nobody declared an index for walks everything.
- **Reading by programs that are not written in Mo.**
- **Whether one store can be shared by more than one program.**

## 6. The layer for outside callers: agents

An outside caller is not part of the compiled program. It arrives while the program runs, with questions and intentions nobody planned for. A page handler makes one call to one function, which lands at once. An agent thinks for a long time between calls, and many of them work at once.

### What it adds

1. **Answer any question** without a query language and without a function written for it beforehand.
2. **Show each caller only what its grant allows.**
3. **Let many agents work at once** with no locks, however long each one thinks.
4. **Let agents extend the program,** with a person deciding whenever more becomes possible.
5. **Keep sensitive data from leaving** except in forms a person approved.
6. **Teach an agent that remembers nothing** what it may do.

### The design

**Three more kinds of Mo code.** The first two are approved by a person. The third is free.

| Kind | What it says | Who writes it |
| --- | --- | --- |
| View functions | What a caller may read: a function from the full data to a narrower type | A person approves a wider one; a narrower one is free |
| Release functions | What may leave, such as a count or an average over at least ten | A person approves |
| Read programs | Any question. A read program cannot change anything | Any agent, with no approval |

An agent changes data only by calling the program's write functions, and only those its grant names.

**One question, start to finish.**

1. The agent writes a small Mo function. Its parameters are the only data it can touch.
2. The database compiles it against the type its grant's view gives. A program that mentions a field the view leaves out does not compile.
3. It runs on a version, under a limit on its work.
4. The program, its caller, the version and the answer are recorded.

**One world, start to finish.** A world is an agent's own version of the data.

1. The agent opens a world. This costs one root.
2. It asks questions and calls write functions. It sees its own changes. Nobody else does.
3. It lands the world. The database replays the world's calls, in order, on the main line as it now stands.
4. Each replayed call checks its own conditions again. The promises are checked after every call.
5. Every question the agent asked is asked again. A different answer means the agent decided on something that is no longer true.
6. The world lands whole, or it goes back to the agent with the reason and nothing changes.

**Asking again costs what changed.** The store lists the rows that differ between the version a question was asked on and the main line. A question whose answer those rows cannot have changed needs no second reading. A world opened on the version that is still the main line has nothing to ask again. The same holds for a promise.

**Helpers get less, never more.** An agent hands a helper a grant made from its own: a view on top of its view, fewer functions, a limit on calls and an end time. The helper works in a world opened from the agent's world.

**Proposals.** An agent may propose a new view, write function, release function, type or promise as Mo code. The machine checks it first. A person then reviews what would become possible, not the code.

### Not designed yet

- **Need 5.** Sensitivity that travels in the types is an idea with no design, and Mo has nothing for it.
- **Need 6.** What an agent with no memory is shown first.
- **Fairness.** An agent that thinks for a long time keeps losing to agents that work fast.
- **Which reads count.** An agent reads much that it does not rely on. Counting needless send-backs is how the finer rule would be chosen.

## 7. What Robert has decided

- The database stays the destination, and nothing in it presupposes SQL or the relational model.
- The ordinary Mo application is the base case, and agents are a layer on top (2026-11-14).
- The accountable write stays the centre.
- A read program only reads.
- Agents may propose, and a person approves.
- A world lands whole or not at all, and the rules are checked after every call in it.
- At landing every question the agent asked counts, by its answer.
- For the first version one operation runs at a time. This design asks to narrow that to one write at a time; he has not accepted the change.

## 8. What Mo must gain

Each line is an ability other programs would also use, which is Robert's test for anything Mo gains. "Mo today" is what was read in Mo's source or measured on 2026-11-14. "For" says whether the base needs the line or only the layer for outside callers does.

| # | Mo must be able to | For | The design uses it for | Who else would use it | Mo today |
| --- | --- | --- | --- | --- | --- |
| 1 | Write bytes at a place in a file, read from a place, force them to disk, and rename a file | Base | The store's own file and log | Any program that keeps data: logs, caches, downloads | A file is read whole. Text can be written whole or added at the end. Bytes cannot be written, and there is no reading or writing at a place, no forcing to disk and no renaming |
| 2 | Hash bytes | Base | Naming nodes and code | Checksums, finding duplicates, signatures | No such function |
| 3 | Let a service keep data outside its one saved state | Base | The store, held by the program that uses it | Any service whose data grows, such as Mo's task queue | The whole state is re-saved on every write: 17 ms plus 0.66 ms for every 1,000 small rows, and writes stop at about 125,000 rows. A service's state and handlers may hold no capability |
| 4 | Keep a large collection whose copies share what did not change | Base | The tree | Undo, snapshots, any program that keeps old states | A `Map` is one block and a changed copy is a whole copy. Written as a library, an insert took 33 times a `Map` insert |
| 5 | Give a call the work it needs, set by the service, and refuse a call without counting it against the service | Layer | Read programs and landings of any size | Any service with one slow tool | A fixed 1,048,576 instructions, about 26 ms. Fifteen refused calls, five to a minute, stop the service |
| 6 | Run reads while a write runs | Base | Queries, read programs and worlds, which hold a root that never changes | Any service with slow reads | One operation at a time. A read waited 91 ms behind writes |
| 7 | Accept a caller's program while running, check it, and run it holding only what the caller holds | Layer | Read programs and proposals | Plug-ins, rules a user writes, any service that is extended while it runs | New code arrives only by upgrading the whole service. `mo query` runs a caller's function on a copy that takes 28 seconds to fetch at 50,000 rows |
| 8 | Tell callers apart, and hand a caller a grant that can be narrowed | Layer | Grants, helpers, the accountable write | Any service with more than one user | One token for a whole service |
| 9 | Keep a log the program owns, with reads in it | Both | History, audit and replay in the base; asking again in the layer | Any service that must show what happened | A read is not logged, and a snapshot deletes the log |
| 10 | Check a promise when a write lands, not only in a test | Base | Rules written once | Any service with a rule that must always hold | A promise is checked by `mo test` only, so a rule is written twice |
| 11 | Simulate a disk that tears, loses and corrupts writes, and many callers at once | Base | Checking the store and the landing rule | Any program that writes files | Simulation has neither |
| 12 | Take and give more than a few kilobytes in one request | Layer | Read programs and their answers | Any service that moves documents | A request is at most 16 KiB and a reply 32 KiB |
| 13 | Carry a label on sensitive data in its type | Layer | Need 5 of the layer | Any program that handles secrets | Nothing |
| 14 | Say what is wanted from a collection in a form the compiler can match to an index | Base | Queries in an ordinary application, and questions nobody planned | Any program that searches its own data | Nothing. Not designed |

Three smaller matters belong to Mo whatever is built on it. A map held in a record is copied every time it changes. Every call spends about 10 ms in the layer that reads the request. The child process that compiles arriving code runs with the server's own access.

**The order Claude would take them in.** Lines 1 to 4 are the data store, and nothing else can be built without them. Lines 6, 9, 10, 11 and 14 finish the base. Lines 5, 7, 8, 12 and 13 are the layer for outside callers.

## 9. What this draft leaves open

- **Whether Robert accepts it.** He has decided the order of its parts and the points in section 7. He has not accepted the rest.
- **Library or runtime.** The store can be a library written in Mo, where every step that touches the disk is visible and can be simulated, or part of the runtime, where any value can live on disk. Line 3 above is where that is chosen. Claude leans to the library.
- **Names by hash or by number.** Hashes let anyone check history and compare versions. Numbers are cheaper and do not fight erasing.
- **Which real data goes in first.** [What real data of yours goes in first?](issues/12-what-real-data-goes-in-first.md) was closed unanswered.
- **Where this sits beside Phases 6 to 8** of Mo. [Does Phase 6 finish before database work starts?](issues/13-does-phase-6-finish-first.md) was closed unanswered.
- **Whether building starts.** [The map](map.md) that led here said no database code and no change to Mo was part of it. Robert stopped that map on 2026-11-14. Whether the next effort builds any line of the table is his decision.
