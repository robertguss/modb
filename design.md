# The data store and the database, designed from what they need

Claude's draft of 2026-11-14, written at Robert's request after his steer that the work had become "too focused on what can Mo do today and not what Mo needs to be able to do". It designs the parts as if Mo already had what they need. Section 8 lists what that is. It was re-ordered the same day at Robert's decision: the ordinary application is the base case, and agents are a layer on top.

On 2026-11-15 the rule for reads and writes was added to section 5, from experiments 8 to 12 in [experiments.md](experiments.md). Sections 3, 7, 8 and 9 were brought into line with it.

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

A web application written in Mo that keeps users, items and orders. No agent is involved. The `store` block and `Table` below are proposed and do not exist in Mo. The rest is Mo as it is.

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

fn users_with(shop: Shop, email: Text) : List(User)
  shop.users.filter(fn(user) user.email == email end)
end

fn orders_of(shop: Shop, buyer: Int) : List(Order)
  shop.orders.filter(fn(order) order.buyer == buyer end)
end

fn orders_placed(shop: Shop, buyer: Int) : Int
  shop.orders.count(fn(order) order.buyer == buyer end)
end
```

**The schema is the types.** There are no tables to declare elsewhere, no query strings and no layer that maps rows to objects. The compiler checks every use of the data.

**The business logic is ordinary functions.** `place_order` is the application's own code. The page handler calls it. The database runs it whole or not at all, checks the promises, records the call with the signed-in user, and saves only the nodes that changed. A tool of a Mo service already has this shape today. What changes is that the state no longer has to fit in memory or be saved whole.

**A query is a function that only reads, written as ordinary Mo over the tables.** Nobody declares an index. The compiler works out from the queries what to keep ready, sorts each query into one of four classes, and reports which:

- *by key*, as `shop.stock.get(item)`: one row;
- *looked up*, as `users_with` and `orders_of`: through an index the compiler made for it. Its work grows with its answer;
- *kept*, as `orders_placed`: the answer is stored, and `place_order` adds one to it. Asking costs one row;
- *walked*: it reads a whole table. This is an error unless the code says `walk`.

Section 5 has the rule and what it was tested on.

**How it is stored.** Each `Table` is a tree of nodes written once, on disk. A row is a leaf. An index is a second tree. Only the nodes a request touches are read into memory.

**Where it runs.** In the application's own process. The store is a part of Mo that a program uses, not a server it connects to.

**Changing the schema** is an upgrade of the program, with a function from the old types to the new ones.

**What this case gets without asking.** Every change is in the log with who made it. Any past state can be read. The whole application, store included, runs under `mo test` with a fake disk and a fake clock.

**Where this case is weak.**

- **Nothing in Mo plans a query today.** The rule in section 5 was tested by a script that stands beside the compiler, on 41 queries over one shop of four tables. Building it into Mo is line 14 of section 8.
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
- **Only some views can be kept current.** A sum, a count and a filter can. An arbitrary program cannot. Section 5 says which queries the experiments could keep.

### What the sketches already showed

A tree of this shape, written in Mo as it stands, kept a version for 778 bytes at any size measured, where a whole copy cost megabytes ([ticket](issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md)). Its nodes were named by number, because Mo has no hash. The shape works. Its speed there says nothing about the design: it ran as bytecode inside a service that re-saves its whole state on every write.

## 5. The database: what every program gets

### What it must do

1. **Hold the program's data in the program's own types,** with no second schema.
2. **Change data only through the program's write functions,** each run whole or not at all, and record each call with who made it. This is the accountable write. For an outside caller the record also says under which grant, for which task and why.
3. **Keep the rules the program declares true after every change.**
4. **Answer the program's questions without reading everything,** and let no write pay for the size of the store without the code saying so.
5. **Change shape when the program changes.**
6. **Keep a history that can be checked, searched and repaired.**

### The design

**Three kinds of code, all part of the program.**

| Kind | What it says |
| --- | --- |
| Types and promises | What the data is and what must stay true |
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

### The rule for reads and writes

Claude's draft of 2026-11-15, for Robert to accept. A read here is one call of a query. The experiments are numbers 8 to 13 in [experiments.md](experiments.md), which holds every figure below with its predictions and controls.

**Decided by Robert.**

- Tables are part of the language, and a read is ordinary Mo that the compiler plans (2026-11-14, as the direction to design and test).
- A slow read is first made fast by keeping its answer. It is refused only when that cannot be done (2026-11-15).
- A write is held to the same rule as a read (2026-11-15).

**The rule.** Not accepted.

1. **The compiler sorts every read into one of four classes.**

   | Class | What the compiler keeps ready | What one ask costs |
   | --- | --- | --- |
   | By key | Nothing | One row |
   | Looked up | An index on the fields the read tests | The rows of its answer |
   | Kept | The answer, in parts | One row for a number, the length of the list for a list, and more where point 3 applies |
   | Walked | Nothing | The whole table |

   A list of rows picked on one field is the same thing kept or looked up. The script calls it kept, and it gained nothing over the index.

2. **It keeps an answer where it can.** It can when the answer splits into parts, one for each row the read goes over, or one for each pair of rows where a loop sits inside a loop, and each part is worked out from its own rows alone. Each part records what it read. A write redoes only the parts that read what it changed.
3. **Where a part looks a row up by key in another table, the compiler groups before the lookup if it can show that order does not count.** Each part runs as far as the lookup and waits. Parts that would go on the same way are held as one entry with a count. An ask does the lookup once for each entry. Order does not count when the answer is a number, or a list the code sorts before any other use.
4. **Otherwise it keeps the whole answer.** The ask stays cheap. A write to the looked-up table must then redo one part for every row that refers to the row it changed.
5. **It reports every plan.** For a read: its class and what it reads. For a write: what it must keep up, in terms of rows, as "one part for every line that names this product". The compiler can say that much. It cannot say how many lines that is.
6. **Two things are errors unless the code says so.** A read that walks a whole table. A write that must redo one part for each row that refers to the row it changed.

**What it rests on.** A script read the compiler's own Mo Core for 41 reads over a shop of four tables: 21 written by agents, 11 by Claude as references and 9 planted to press on the rule. It planned each one, kept the answers up to date through 1,200 random writes, and compared 23,877 answers with real Mo running the same code. None differed. Every control failed where it should.

- **Classes, by rule alone.** Of the 21 agent-written reads: 2 by key, 12 kept, 5 looked up and 2 walked. Both walks test `contains` on a word the caller gives.
- **What each way costs,** in rows read at 1,200 orders:

| | One ask of `bought`, a join of three tables | One write to a product, over every kept read that looks a product up |
| --- | --- | --- |
| Looked up, no answer kept | 189.0 | Not measured. Nothing kept reads a product |
| The whole answer kept, experiment 10 | 67.5 | 675.4 |
| Grouped before the lookup, experiment 12 | 51.5 | 0.0 |

- **Grouping gains nothing where the key does not repeat or order counts.** The buyers of a product cost 350.1 rows an ask grouped and 369.8 with nothing kept. A list in table order cannot be grouped at all.

**What it does not rest on.**

- A write test that sees growth. Experiment 13 ran the whole rule once. The read error refused exactly the one planted walk that does not say `walk`. The write error, worked out from the plan alone, flagged every write that grew, to customers and to products. It also flagged writes to orders, which stay flat at about 21 rows, because `bought` holds a part for each pair of an order and one of its lines, and an order has about three lines. The plan shows "one part for every row that names this row" and not how many rows that is. Point 4 was run only on pairs of rows.
- A compiler pass. The planner is a Python script beside the compiler, and it handles only the forms these reads use. It groups only reads written as a loop.
- More than one store. It has about 40 customers and 25 products at both sizes, so "grows with the store" was only seen as more lines for each product and more orders for each customer.
- Time or memory. Rows were counted. Nothing was timed, and what the kept answers cost to hold was not measured.
- Agents told nothing. The agents had one page of rules, so every test sits in a library call. A test written as an `if` inside a loop over a whole table comes out walked.
- A table with no order. The rows kept the order they arrived in, as a Mo `Map` does.

**Open inside the rule.**

- **Where the code says so for a write.** The growth comes from a kept read, and the error would land on a write function that somebody else may have written. Claude leans to putting the word on the read, at 65%: the read chooses between a cheap ask with a growing write and the reverse.
- **What order a table gives its rows.** Two of the 21 agent-written reads leaned on arrival order without sorting. A table with no order of its own would make such a read an error or a visible choice.
- **The same task written two ways lands in two classes.** One agent's `bought` looks in its own list before it adds to it, so it was looked up at 189.0 rows. The other's was kept at 51.5. The report must say why a read was not kept.
- **Which lookup to wait at,** where a part does more than one. The script waits at the first, and the buyers read needs the second.
- **Totalling before a lookup.** Revenue of a product cost 17.4 rows an ask grouped, and would cost about 2 if quantities were added up before the price is looked up.
- **More shapes where order does not count:** a count, a set, a test for membership.
- **`.map(...).sum` is kept as a list.** Mo Core writes `sum` out as a loop, and the script does not see through it.
- **A read that arrives while the program runs,** from an agent. Whether it is planned against what is already kept, or may ask for more.
- **Building an index or a kept answer** when an upgrade brings a read that needs one. Experiment 7 would test it and has not run.

### Not designed yet

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
- Tables are part of the language, and a read is ordinary Mo that the compiler plans (2026-11-14, as the direction to design and test).
- A slow read is first made fast by keeping its answer, and refused only when that cannot be done (2026-11-15).
- A write is held to the same rule as a read (2026-11-15). The rule as written in section 5 is Claude's, and he has not accepted it.
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
| 14 | Hold a table as a kind of value, plan every read of one when the program is compiled, and keep indexes and answers current as writes land | Base | The rule for reads and writes in section 5, and questions nobody planned | Any program that searches its own data | Nothing in Mo. A `Map` keeps insertion order. A script beside the compiler planned 21 of 21 agent-written reads from Mo Core (experiments 8 to 12) |
| 15 | Carry what a function costs as a checked part of it, and count rows read as it runs | Base | The two errors of the rule in section 5 | Any program with a budget for a request | `--max-work` counts instructions, and a built-in that goes over a whole collection counts as 26 or 27 (experiment 5) |

Three smaller matters belong to Mo whatever is built on it. A map held in a record is copied every time it changes. Every call spends about 10 ms in the layer that reads the request. The child process that compiles arriving code runs with the server's own access.

**The order Claude would take them in.** Lines 1 to 4 are the data store, and nothing else can be built without them. Lines 6, 9, 10, 11, 14 and 15 finish the base. Lines 5, 7, 8, 12 and 13 are the layer for outside callers.

## 9. What this draft leaves open

- **Whether Robert accepts it.** He has decided the order of its parts and the points in section 7. He has not accepted the rest. The newest part waiting on him is the rule for reads and writes in section 5.
- **Library or runtime.** The store can be a library written in Mo, where every step that touches the disk is visible and can be simulated, or part of the runtime, where any value can live on disk. Line 3 above is where that is chosen. Claude leans to the library.
- **Names by hash or by number.** Hashes let anyone check history and compare versions. Numbers are cheaper and do not fight erasing.
- **Which real data goes in first.** [What real data of yours goes in first?](issues/12-what-real-data-goes-in-first.md) was closed unanswered.
- **Where this sits beside Phases 6 to 8** of Mo. [Does Phase 6 finish before database work starts?](issues/13-does-phase-6-finish-first.md) was closed unanswered.
- **Whether building starts.** [The map](map.md) that led here said no database code and no change to Mo was part of it. Robert stopped that map on 2026-11-14. Whether the next effort builds any line of the table is his decision.
