[Own reasoning] Build a small executable sketch of the boundary between the halves first, then one thin slice through both, including incremental storage; I am **85% confident**.

My three strongest reasons:

1. [Read in a document] [models/README.md](models/README.md) establishes useful distinctions about replay and whole-world landing, but explicitly has no implementation comparison; [sketches/README.md](sketches/README.md) says the existing sketch omits forks, recorded reads and replay against changed state. [Own reasoning] Implementing that complete interaction is the next valuable experiment. Neither a finished upper half nor a finished storage engine is necessary to discover whether it works.

2. [Read in a document] [issue 11](issues/11-how-fast-and-large-is-a-mo-service.md) separates fixed HTTP overhead from whole-state copying and reports a roughly 9 MiB effective ceiling for its measured shape. [Checked in the code] [service.c:259](mo/src/vm/service.c:259) encodes and decodes replacement state, and [service.c:463](mo/src/vm/service.c:463) checksums its entire encoding. [Own reasoning] These justify addressing persistence early, but do not justify designing all storage before exercising its consumers. Adding worlds and retained history to this existing persistence path compounds precisely the measured weakness.

3. [Read in a document] [design-ideas.md](design-ideas.md) proposes both pure functions over typed state and a storage library that loads nodes through a capability; [the reference](mo/docs/reference/README.md:1107) excludes capabilities from service state, inputs and results. [Own reasoning] The important uncertainty is how approved functions and arbitrary read programs access data larger than memory. Explicit fetching, transparent paging and materialised views impose different language and execution contracts. Settle that with executable examples before either half hardens around an incompatible assumption.

[Own reasoning] The strongest case against my recommendation is that the storage requirements already overlap substantially: cheap versions, incremental writes and durable ordered commits. Building a minimal persistent collection first could teach more than inventing an interface around today’s limitations. A boundary sketch can become speculative architecture. I would constrain mine to one concrete workload and discard abstractions that the slice does not need.

[Own reasoning] “Which half first” needs these qualifications:

- Storage first does not require completing indexes, content addressing, background maintenance and concurrent reads together. A persistent collection with version roots is a smaller first step.
- Upper first does not require exposing `Map` throughout approved functions. A small domain module can contain that dependency; rewriting every write function is a risk, not an inevitable cost.
- The boundary includes durable commit, retained code identities, replay context, storage failures and work accounting—not just collection type and copying.
- Needless-send-back counts will not necessarily carry over unchanged: storage latency changes overlap between worlds and therefore conflict frequency. Upper-first measurements remain useful, but workload timing matters.
- An additional intermediate order is a persistent collection **in memory**, then replay and read programs over it, then durable nodes. This separates collection semantics from disk recovery without abandoning either.

[Own reasoning] Before committing, I would sketch one workload with two overlapping worlds, interleaved reads and writes, a narrowed view, and whole-world landing with checks after each call. Specify where nodes are fetched, how failures surface, and what is committed before acknowledgement. Then measure copied bytes, nodes read/written, retained bytes per world, validation work and retries as world count and length grow.

[Own reasoning] I would favour storage first if ordinary approved functions cannot retain a useful, bounded execution contract without paging support. I would favour upper first if the sketch shows a simple replaceable boundary and realistic overlapping worlds remain comfortably within today’s memory and work limits. These are learning criteria, consistent with [map.md](map.md), rather than speed-to-use criteria.

[Checked in the code] One factual correction: [design-ideas.md](design-ideas.md) says “Every call is logged.” Successful reads are excluded: [service.c:242](mo/src/vm/service.c:242) prevents a read-only tool from producing replacement state, and [service.c:1118](mo/src/vm/service.c:1118) persists only updates. [Own reasoning] Recording questions for replay and accountable reads therefore needs an additional durable mechanism, even before snapshots’ log pruning becomes relevant.
