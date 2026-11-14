Research run on 2026-11-14 by a subagent using Exa, for the ticket [What earlier work stands behind write-once trees and views kept current?](../issues/31-earlier-work-on-write-once-trees-and-views-kept-current.md).

# Earlier work on write-once trees, code stored by hash and views kept current (researched 2026-11-14)

The subject is the "Storage underneath" section of [design-ideas.md](../design-ideas.md), with ideas 5 ("A world per agent") and 8 ("Unplanned questions"). It proposes three things:

- **A.** The database as a tree of write-once nodes, each named by the hash of its contents, beside a log of calls.
- **B.** Code stored by the hash of its checked form, so a log entry names exactly the function that ran.
- **C.** An index as a view the database keeps current.

The wiki pages listed in the ticket were read first. What they already say is not repeated here; where they are thin or wrong, the section near the end says so.

Two terms used throughout:

- *Copy-on-write* (also called *shadowing*): a change never overwrites a stored block; it writes a changed copy elsewhere and then repoints the parent, which is therefore copied too, up to the root.
- *Garbage*: blocks that no kept version points to any more. Every design below must find and free them.

## A. A tree of write-once nodes named by hash, beside a log

### LMDB: a copy-on-write B-tree with one writer and no log

**What it is.** An embedded key-value library from the OpenLDAP project. "Data pages use a copy-on-write strategy so no active data pages are ever overwritten", which "eliminates the need of any special recovery procedures after a system crash". Writes are serialized: "only one write transaction may be active at a time" (http://www.lmdb.tech/doc/).

**How a change and a crash work.** "Every branch node from the leaf to the root must be copied/modified for any leaf update" and "any node not on the path from the leaf to the root is unaltered" (http://www.lmdb.tech/SymasDocs/20151008-CMU-LMDB.pdf). The file has two fixed root pages, "used in double-buffer fashion"; a reader takes the one with the greater transaction ID. A commit writes the new pages first and then overwrites the older root page (https://www.openldap.org/pub/hyc/mdm-paper.pdf). This is exactly the crash story in the design: new nodes first, then switch the root.

**How old versions are cleared.** LMDB keeps a second B-tree of freed page IDs per transaction. A writer reuses a freed page only when it is older than every active reader's snapshot; readers record their snapshot in a lock-free table (https://www.openldap.org/pub/hyc/mdm-paper.pdf). It "nominally maintains only two versions of the DB"; "rolling back to a historical version is not interesting for OpenLDAP" (CMU slides above). LMDB grew out of an append-only B-tree and was "changed from append-only to page-reclaiming" (same slides).

**What it cost.** "If a read transaction is open on a particular version of the DB, that version and every version after it are excluded from page reclaiming", so "the DB file size may grow rapidly, devolving into Append-Only behavior until the transactions are closed" (http://www.lmdb.tech/media/20141120-BuildStuff-Lightning.pdf). No numbers for bytes written against bytes changed were found.

**Largest size reported.** A third-party Java binding says it is "used for heavy production workloads (eg > 500 TB of HFT data)" (https://github.com/lmdbjava/lmdbjava/blob/master/README.md; a claim by that project about its users, not confirmed). An RDF database vendor reports its "biggest production repository reached 3.25 billion RDF statements" on LMDB (https://www.rondb.com/post/building-a-trillion-triple-rdf-database-with-dydra-and-rondb-rdf-score; vendor claim).

**What became of it.** Still maintained; the documentation and source above are current (inference from the live repository).

**For the design.** Supports the crash story and the single writer. Warns that every root kept alive (a snapshot, a world, a long read) pins all garbage made after it. LMDB solved this by keeping only two versions, which is the opposite of what the design wants.

### CouchDB's append-only B-tree

**What it is.** CouchDB updates its database files "via append operations, never mutating existing data". The cost: "it tends to use a lot of disk space relative to a more traditional update-in-place DBMS", so garbage is removed by *compaction*, which copies "the most recent revision of every document" to a new file (https://blog.couchdb.org/2016/08/10/feature-compaction/).

**What it cost.** Compaction "requires roughly twice the disk storage". Since 2.1.1 a daemon ("smoosh") compacts automatically, using the ratio or the difference of file size to live data size (https://docs.couchdb.com/en/latest/maintenance/compaction.html). An interrupted compaction may leave "the last header buried several GB from the end of the file", which must be searched for on resume (blog above).

**What became of it.** Still CouchDB's storage. LMDB's author names CouchDB as the design LMDB improved on by reusing pages instead of compacting (https://www.openldap.org/pub/hyc/mdm-paper.pdf).

**For the design.** An append-only tree that keeps everything needs a copying collector and twice the disk while it runs. The design must budget for that, or reclaim pages in place like LMDB.

### Rodeh's copy-on-write B-trees with clones, and Btrfs

**What it is.** A 2008 paper on B-trees that "respects shadowing, achieves good concurrency, and implements cloning (writeable snapshots)" (https://dl.acm.org/doi/pdf/10.1145/1326542.1326544). Btrfs is built on it (https://dl.acm.org/doi/pdf/10.1145/2501620.2501623).

**The problem it solved.** Earlier file systems tracked which snapshot uses a block with bitmaps. In WAFL, "with a map of 32-bits per data block we get 32 clones", 256 clones need "32 bytes ... per data-block", and cloning or deleting a clone needs "a pass on the entire free-space" (https://usenix.org/legacy/events/lsf07/tech/rodeh.pdf).

**What it found.** Keep a *reference count* per block instead, and update it lazily. A clone copies only the root and increments its children's counts. Before a page is changed: "If ref-count == 1: page can be modified in place"; otherwise it is copied, the old count is decremented and its children's counts incremented (slides above). Btrfs's recipe is "standard B+-tree construction" with "a top-down update procedure", no leaf chaining and "lazy reference-counting for space management" (Btrfs paper above).

**For the design.** This is the best-studied answer to "a world per agent" at file-system scale: thousands of writable copies share blocks, and a block is freed when its count reaches zero. It shows a cheaper alternative to reachability scans, but reference counts must themselves be written on every shared-path change. It also shows a design choice the project faces: Rodeh's trees are not named by hash, so two clones with the same contents do not have the same root.

### WAFL: what a copy-on-write file system learned over decades

**What it is.** NetApp's WAFL "never overwrites a persistent block in place". Client operations are logged to non-volatile memory and acknowledged; WAFL "collects and flushes the results of thousands of op[erations]" in each *consistency point*, "a self-consistent, point-in-time image" (https://www.usenix.org/system/files/fast19-kesavan.pdf).

**What it found.** "Copy-on-write increases the demand on the file system to find free blocks quickly; failure to do so may impede allocations for incoming writes" (https://www.usenix.org/system/files/conference/fast17/fast17-kesavan.pdf). "As a file system ages, the free space in that file system gets fragmented as random blocks are freed while others stay allocated or trapped in snapshots" (same paper). Even a file written in order is scattered by later random overwrites (fast19 paper above). Deleting a file does not free it at once; it is moved to a hidden namespace and "gradually shrinks" over several consistency points (fast17 paper).

**What became of it.** Still in production after "more than a de[cade]" of evolution of its free-space code (fast17 abstract); a further paper on defragmentation followed in 2019 and 2020 (https://dl.acm.org/doi/10.1145/3366173).

**For the design.** Two lessons. First, the log-then-batch pattern: the log makes each operation durable, and the tree is written once per batch, not once per operation. The design already says only the log must reach disk before a reply. Second, freeing space in a copy-on-write store is a permanent engineering problem, not a one-off feature. No numbers on WAFL fragmentation were extracted (see "What I could not confirm").

### ZFS deduplication: naming blocks by hash costs memory

**What it is.** ZFS can store identical blocks once by looking up each block's checksum in a *dedup table* (DDT). This is the closest file-system analogue of a store where nodes are named by their hash.

**What it cost.** OpenZFS: "Unless you have a specific reason, do not enable dedup. It is the most resource-intensive feature in ZFS", and in the worst case "a pool that cannot be imported because the DDT does not fit in memory". "Plan for at least 1.25 GiB of RAM per 1 TiB of stored data", and "if it is not comfortably above 2x, dedup is not worth it" (https://openzfs.github.io/openzfs-docs/Basic%20Concepts/Data%20Storage/Deduplication.html). Oracle gives "approximately 320 bytes" per in-memory entry, and warns that removing a large deduplicated file system "will severely decrease system performance" without that memory (https://docs.oracle.com/en/operating-systems/solaris/oracle-solaris/11.4/manage-zfs/dedup-property.html). OpenZFS adds that "clones and `zfs send`-based workflows already share blocks without dedup".

**For the design.** A warning about one form of the idea. Looking up "is there already a node with this hash?" across the whole store needs an index from hash to location, and that index is large. Structural sharing along a path (which ZFS clones and Dolt get for free) does not need the lookup; only deduplicating identical content written independently does. Inference: the design gets most of its sharing from paths, so it need not deduplicate globally.

### Noms and Dolt: prolly trees

**What it is.** A *prolly tree* is a B-tree whose node boundaries are chosen by hashing the content, and whose nodes are named by the hash of their bytes. Noms invented it; Dolt forked Noms. Noms's repository says: "Noms is not being maintained ... you probably want Dolt (https://github.com/dolthub/dolt) which is a fork of this project", and it was archived on 28 August 2021 (https://github.com/attic-labs/noms).

**The problem it solved.** Ordinary B-trees are not *history independent*: "the order of the writes internally changes the structure of the tree. Thus, storage cannot be easily shared between two versions of the same tree." In a prolly tree, "No matter which order you insert, update, or delete values, the Prolly tree is the same", so a diff walks only subtrees whose hashes differ and "scales with the size of the differences, not the size of the tree" (https://www.dolthub.com/docs/architecture/storage-engine/prolly-tree/).

**Design details that matter.** Chunks "are set to be on average 4 kilobytes". A plain rolling hash gives many tiny chunks and a few huge ones, which slows binary search inside a chunk, so Dolt also weighs the current chunk size when deciding a boundary. Dolt hashes only keys when choosing boundaries, so a change to a value "is guaranteed not to shift the chunk boundary" (same page; https://www.dolthub.com/blog/2022-06-27-prolly-chunker/).

**What a change costs.** "Dolt only writes the handful of chunks that actually changed, plus the path up the tree to the root" (https://www.dolthub.com/blog/2026-06-18-dolt-disk-space/; vendor). Dolt's own rule of thumb for history storage: multiply 4KB by the number of write transactions, by the average number of indexes updated per transaction, by the tree depth, roughly `log(table size)/2` (https://www.dolthub.com/blog/2023-12-06-sizing-your-dolt-instance/; vendor). So one row changed in a table with two indexes writes on the order of tens of kilobytes. "If you structure your import as many single point inserts, Dolt generates as much as 10X disk space as garbage" (same post).

**What a read costs.** On Dolt's own sysbench page, version 2.7.3 point selects take 0.26 ms against MySQL's 0.19 ms (multiple 1.37), random point and range selects 1.54 and 1.62, while scans are faster than MySQL; the mean over reads is 0.82 (https://www.dolthub.com/docs/sql-reference/benchmarks/latency/; vendor claim). Dolt took about five years to reach mean parity (https://www.dolthub.com/blog/2025-12-04-dolt-is-as-fast-as-mysql/; vendor).

**How old versions are cleared.** Garbage is anything "written to the chunk store but never becomes reachable from a commit". Since Dolt 1.75 garbage collection runs in the background. Collection is generational and "never revisits the old generation by default"; dropping real history means squashing commits and running `dolt gc --full`, which "is destructive". In Dolt's example, 22 commits squashed to 2 cut the store from 3.1M to 156K (https://www.dolthub.com/blog/2026-06-18-dolt-disk-space/; vendor).

**Largest size reported.** "Dolt has databases in production that are about 1TB, including history" (https://www.dolthub.com/blog/2024-07-03-why-no-dolt/; vendor). Pushing a 1TB database first crashed Dolt's remote server, because the in-memory indexes of its table files "take up about 1% of the size of a Dolt database" (https://www.dolthub.com/blog/2022-02-28-dolt-storage-layer-memory-optimizations/; vendor). For a 650GB Wikipedia import, "Dolt generates about 500GB of garbage a week", and DoltHub advises "approximately 10% of the disk size of your database available in RAM" (https://www.dolthub.com/blog/2024-10-21-dolt-at-scale/; vendor).

**For the design.** The strongest support: a working, 1TB-scale database built on exactly the proposed shape, with near-parity reads. It also carries the clearest warnings: per-transaction path writes produce garbage at a rate comparable to the data itself, and the hash-to-location index costs memory in proportion to the data.

### Merkle search trees, and their use in the AT Protocol

**What it is.** A 2019 paper introducing the *Merkle search tree* (MST), "a new kind of Merkle tree ... that implements a balanced search tree while maintaining key ordering", for syncing large sets between peers without vector clocks. It reports "a 66% reduction of bandwidth cost over a vector-clock approach, as well as a 34% improvement in consistency level" in some scenarios (https://inria.hal.science/hal-02303490/document). Like a prolly tree, its shape is a function of its contents.

**What became of it.** The AT Protocol (Bluesky) stores every account's records in an MST: "This content-addressed deterministic data structure stores data in key-sorted order", and the tree "should be fully reproducible" from its contents (https://atproto.com/specs/repository).

**What it found about history.** In August 2023 the protocol removed history from repositories. Two reasons: "Record deletions are difficult to process. If a user deletes a record, that commit needs to be erased from their repository to match their intent", and "Maintaining repo history can cause anywhere from a 5-10x increase in repo size". Rebases, "discrete moments when the history of a repository is deleted/mutated", were tried and found "tricky and sensitive ... expensive to conduct and complex to communicate across the network" (https://atproto.com/blog/repo-sync-update). The current spec says deletion leaves no "tombstone", and the `prev` link to the previous commit "is virtually always `null`" (https://atproto.com/specs/repository).

**For the design.** The sharpest warning in this survey. A production system with millions of hash-named trees gave up keeping old versions, for the two reasons the design lists as open: erasure and growth.

### Irmin, and its garbage collector in Tezos

**What it is.** "An OCaml library for building mergeable, branchable distributed data stores", with "Bidirectional compatibility with the Git on-disk format" and "custom merge functions" (https://irmin.org/). Its design splits an immutable block store from a small mutable "tag store", "the only mutable part of the whole system"; changing a value in a persistent tree means "creating a chain of new blocks" (https://mirage.io/blog/introducing-irmin). The API offers "custom 3-way merge operators for various user-defined contents" (https://mirage.github.io/irmin/irmin/Irmin/index.html).

**Largest use and what it cost.** Irmin's `irmin-pack` backend holds the Tezos blockchain's state for every block. Originally it "was not possible to 'delete' the information from dead, unreachable objects". A node without pruning grew to "~140 GB"; with the garbage collector added in Octez v15 "the size of the context storage on disk ... oscillates between ~ 30GB and ~60 GB — the spikes are caused by the duplication needed" during collection (https://research-development.nomadic-labs.com/pruning-the-context-and-other-seasonal-activities.html). Keeping 6 cycles needs "~35GB", and in v15 "each subsequent pruning run needs an additional 40GB" while it runs (https://tarides.com/blog/2022-11-10-towards-minimal-disk-usage-for-tezos-bakers/). The collector copies live objects reachable from a chosen commit into a new file (same post). Later, archive nodes were split into an `upper` volume of recent history and `lower` volumes of old data, because random reads "into an enormous data file" made them slower (https://tarides.com/blog/2023-05-05-optimising-archive-node-storage-for-tezos/).

**For the design.** Supports the design: Irmin is the closest earlier work to "a store for typed values of the language, shaped like Git, with merges written in the language". Warns: the garbage collector came years after the store, and it needed spare disk equal to the live set while it ran.

### Git's object store used as a database

**What it is.** Git names every object by its hash. Objects are first written as separate "loose" files; Git later packs them into a packfile that stores "just the deltas from one version of the file to the next", when there are "too many loose objects", on `git gc`, or on push. In the book's example, 15K of loose objects packed to 7K (https://git-scm.com/book/en/v2/Git-Internals-Packfiles).

**What it cost in use as a database.** CocoaPods kept its package index as a Git repository on GitHub, fetched by every user. A GitHub infrastructure engineer explained the rate limiting: "approximately 1.1 Million clones/fetches"; shallow fetches costing "100+ seconds" of server CPU each; and a `Specs` directory with "16k+ subdirectories" that made "some Git operations ... unexpectedly expensive". Together these made it "one of the top five most resource-costly repositories that we host on all of GitHub.com" (https://github.com/CocoaPods/CocoaPods/issues/4989). CocoaPods changed its clone and fetch behaviour (https://blog.cocoapods.org/Master-Spec-Repo-Rate-Limiting-Post-Mortem/).

**For the design.** Two lessons. Git does not keep one file per node: it batches nodes into packs and stores deltas, which is the same batching WAFL and Datomic do. And a very wide node (one directory with 16,000 entries) is slow to change and to diff; the design's tree must split wide collections into bounded nodes, as prolly trees do.

### Datomic's segments

**What it is.** The wiki covers Datomic's model; this is its storage. "These segments range up to about 50kb each. The database is a set of trees of these segments." Every datom is stored "at least 3 times": in the log and in two sorted indexes, more for reference and unique attributes (https://docs.datomic.com/operation/capacity.html). Storage only needs "key-value interface and CAS for updating index root records"; "Segments are immutable"; index trees are "no more than three level deep" with a "1,000+ branching factor" (https://tonsky.me/blog/unofficial-guide-to-datomic-internals/, an outside reading of the internals, not official).

**How a change is made.** Not by rewriting a path per transaction. New datoms go to the log and an in-memory index. "When in-memory index gets too big (`memory-index-threshold`, e.g. 32 Mb), transactor starts current index re-built", merging it into new segments (tonsky, above). This is batching again.

**How old versions are cleared.** "During normal operation, no-longer-referenced (garbage) storage segments accumulate, and you should periodically invoke gc-storage". Garbage is not deleted at once because "not all consumers will immediately adopt the latest tree", and the cut-off "should be at least a month old" (https://docs.datomic.com/operation/capacity.html). One user who did not run it saw the storage footprint grow "to over 900 G" over several months at "perhaps 1 million transactions per day"; a backup and restore brought it to "approximately 40G" (https://forum.datomic.com/t/does-gcstorage-collect-all-of-the-garbage/1189).

**For the design.** Supports "tree of unchanging pieces plus a log", and shows the form that worked at scale: the log takes each write, and the tree is rebuilt in large merges. Warns, with the starkest number found, about garbage left uncollected: 900G for 40G of live data.

### Persistent maps in memory: HAMTs and CHAMP

**What it is.** A *hash array mapped trie* (HAMT) is a tree keyed by the bits of each key's hash, with nodes of up to 32 children; Clojure and Scala use HAMTs as their immutable maps (https://michael.steindorfer.name/publications/oopsla15.pdf). CHAMP is a 2015 successor.

**What it found.** CHAMP "maintains the lookup, insertion, and deletion runtime performance of a HAMT, while reducing memory footprints and significantly improving iteration and equality checks". Against Clojure's maps it improves "a median 72 % for Lookup, 24 % for Insert, and 32 % for Delete", and speedups on a program analysis range "between 9.9 x and 28.1 x" (same paper). It keeps the trie "compact and canonical upon deletion", which makes equality checks fast (same paper). Scala 2.13's immutable `HashMap` uses it (https://team-pj-lab.github.io/CISS/en/algorithms/champ/, a secondary source).

**For the design.** Shows the in-memory half. A canonical HAMT has one shape per set of contents, so it is history independent and could be hashed like a prolly tree (inference). But its order is the order of hashes, so it cannot answer range questions ("all students with surnames from A to C"). For Mo, a CHAMP-style `Map` would fix "a changed copy is a whole copy" in memory (inference). On disk, a key-ordered tree (prolly or MST) is the better fit.

### BranchBench: what sharing storage between copies costs reads

**What it is.** A 2026 benchmark of database branching under agent workloads, run on Postgres transactions, Postgres 18 file copies, Dolt, Neon, TigerData and Xata (https://daplab.cs.columbia.edu/general/2026/05/26/branchable-databases-arent-ready-for-agentic-workloads.html; https://bauplanlabs.github.io/SAO-workshop/papers/37.pdf).

**What it found.** No system finished all workloads within two hours. Neon read fast but branch creation was "up to 25× slower", switching "up to 1500× slower", and it hit a 20-active-branch limit. "Dolt had the opposite profile. Branch creation and checkout were cheap metadata operations over versioned roots", but "larger reads and joins dominated runtime". In a 1000-step tree-search workload "Neon finished 33/1000 steps", and "Dolt finished 170 steps before hitting a 2-hr time out" (blog above).

**What followed.** Dolt then reported a "653.17x speed up" on one slow query, "within 5% of Postgres", and on another still being "around 18x slower than Postgres", attributing the rest to reading from disk and the lack of parallel joins and scans (https://www.dolthub.com/blog/2026-06-25-branch-bench-performance-update/; vendor).

**For the design.** Supports "a version is a root": that part was cheap. The read cost the benchmark exposed in Dolt is, by Dolt's account, mostly query execution, not structural sharing (vendor; the paper's own breakdown was not read). Inference: the design should expect tree reads to be a small constant factor slower than a page store, and should measure, not assume, how depth of sharing affects reads.

### Neon, for contrast: a log of page changes, not a tree

**What it is.** Neon's storage server slices incoming Postgres write-ahead-log records "per relation and page" into immutable "layer files": *image layers* hold a snapshot of a key range at one log position, *delta layers* hold the changes over a range of log positions. Small files are merged into larger ones and old files are removed by garbage collection (https://github.com/neondatabase/neon/blob/main/docs/pageserver-storage.md). A branch is a starting log position on a parent, which is also how point-in-time recovery works (same document).

**For the design.** A proven alternative shape for "cheap copies and old states": a merged log of changes plus periodic images, rather than a hash tree. It gives no cheap diff between two branches by hash, which is what "many agents" needs from the design.

### Erasing one person's data from a store named by hash

What the sources show, beyond what the wiki already records about Datomic, XTDB, QLDB and crypto-shredding:

- **Rewriting history changes every later name.** GitHub: "Rewriting history will change the hashes of the commits that introduced the sensitive data and all commits that came after." Signatures "would no longer be valid", diffs of old pull requests break, and any clone made earlier can bring the data back with an ordinary pull and push (https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository). It also notes that the hashes that stop tampering make expunging "a very involved process of coordination".
- **One production system gave up history to make deletion possible.** The AT Protocol, above.
- **Garbage collection is how erased nodes actually leave the disk.** Dolt, Irmin and Datomic all free a node only when no kept root reaches it (sources above). Inference: in the design, erasing a person means writing new roots that do not reach their nodes, re-pointing or dropping every kept root that does (old states and agents' worlds), and then collecting. The "root before and after" carried by each log entry then no longer matches what is on disk for the erased span, unless the log records the erasure itself and the old hashes are kept with their bytes gone, as QLDB's redaction did (wiki: [deleting personal data from history](../wiki/ideas/deleting-personal-data-from-history.md)).

## B. Code stored by the hash of its checked form

### Unison

**What it is.** "Each Unison definition is identified by a hash of its syntax tree." Arguments are replaced by positions and "all dependencies ... are replaced by their hashes", so a hash "uniquely identifies its exact implementation and pins down all its dependencies". Names "are just separately stored metadata". Hashes are 512-bit SHA3 (https://www.unison-lang.org/docs/the-big-idea/).

**What it made possible.** Parsing and type checking happen once and are cached "in a cache which is never invalidated"; deterministic tests need not rerun "if none of its dependencies have changed"; dependency conflicts "are just not a thing", because two versions of a library are simply two sets of hashes; and code can be shipped between machines by sending missing hashes on demand (same page). The author's list adds "typed durable storage" and "a codebase that is always runnable - never broken" (https://www.unison-lang.org/blog/heres-whats-been-happening-with-unison/).

**How a changed dependency is handled.** Because a hash includes its dependencies' hashes, changing a function gives every function that uses it, directly or not, a new hash. `update` "attempts to update all the existing dependents accordingly. If the process can't be completed automatically, the dependents will be added back to the scratch file for your review"; "All impacted terms, including indirect dependents, will be opened", on a temporary branch merged back when they type check (https://www.unison-lang.org/docs/usage-topics/workflow-how-tos/update-code/).

**What it cost.** "Unison code lives in a database—your 'codebase'—rather than in text files", edited through a separate codebase manager (https://www.unison-lang.org/unison-1-0/). In 2023 the team wrote that the earlier update workflow "hasn't been as good as it needs to be": names were easily replaced "with mysterious hashes", conflicts were invisible "unless you run `todo`", and "The suggested order of edits sometimes leads you in a circle" (https://www.unison-lang.org/blog/new-update-process/). No measured cost in time or space was found.

**What became of it.** Unison 1.0 was released in November 2025 (https://www.unison-lang.org/unison-1-0/).

**For the design.** Strong support. It shows the idea works for a whole language for over a decade, and that the hard part is not storage but the workflow when a dependency changes. The design keeps text source and stores only the checked form by hash, which avoids Unison's biggest cost (code no longer in text files) while keeping the benefit that matters here: a log entry names exactly what ran (inference).

### Dhall: hashing the meaning, not the text

Dhall's imports can be "frozen" with a SHA-256 hash. It is "not a hash of the text of the import", because a file's text does not fix its meaning when it imports other files. Instead it hashes the expression's *normal form*, so "any change to an expression (even via transitive dependencies) will be detected", while "behavior-preserving changes" such as refactoring or comments keep the hash. This is possible because "Every Dhall expression has a canonical normal form because the Dhall configuration language is not Turing-complete" (https://docs.dhall-lang.org/discussions/Safety-guarantees.html). The hash doubles as the key of a local cache (https://github.com/dhall-lang/dhall-lang/blob/master/standard/binary.md).

**For the design.** Shows the choice in "hash of its checked form". Hashing after name resolution and type checking (Unison's choice) makes renaming free; hashing a fully normalised form (Dhall's) makes more rewrites free but needs a language where normal forms exist. Mo is general-purpose, so Unison's level is the realistic one (inference).

### Nix: addressing by inputs, and content-addressed outputs

Nix names each build output by a hash of its build recipe and inputs ("input-addressed"). A change anywhere below means new names everywhere above, and rebuilds. RFC 62 proposes deriving the name from the output instead, so that when a rebuilt dependency gives byte-identical output, nothing above it rebuilds (https://github.com/NixOS/rfcs/blob/master/rfcs/0062-content-addressed-paths.md). This is called *early cutoff*. It is still "an upcoming feature" and opt-in per derivation (https://wiki.nixos.org/wiki/Ca-derivations).

The *Build Systems à la Carte* paper classifies build systems by how they decide to rebuild. Bazel uses *constructive traces*, a cache from hashes of inputs to results that can be shared between users; Nix uses deep constructive traces, which record only the final inputs (https://blogs.ncl.ac.uk/andreymokhov/build-systems-a-la-carte/). A summary of the paper states that deep constructive traces "cannot support early cutoff" and "may generate frankenbuilds if the tasks are not deterministic" (https://thewagner.net/blog/2019/06/19/build-systems-a-la-carte/; secondary).

**For the design.** A log entry that names a function by a hash that includes its dependencies is input-addressing. It gives exact replay. It also means a harmless change to a helper makes every function above it "new", which matters if views or approvals are keyed by hash: a view would be rebuilt, or a function re-approved, when nothing it computes changed (inference). Early cutoff, by comparing results, is the known remedy.

### Ethereum: code fixed by its address, and the proxy workaround

Ethereum contracts are "immutable by design" (https://ethereum.org/developers/docs/smart-contracts/upgrading/). To upgrade, projects put a "proxy" in front that forwards calls to a replaceable logic contract, running its code against the proxy's storage. That brings "storage collisions between different versions of the logic contract", which the pattern does not prevent: "It is up to the user to have new versions of a logic contract extend previous versions" (https://docs.openzeppelin.com/upgrades-plugins/proxies).

**For the design.** A warning about the opposite extreme. When the stored code can never change, people add an indirection by name, and the bugs move to the boundary between old data and new code. Mo already has typed live upgrades, so the design should keep hashes for what ran and names for what runs next (inference).

### Feldera: why a view needs to know its code changed

Feldera assumes every user-defined function is deterministic and "cannot verify" it. It also "assumes that the semantics of a user-defined function does not change between pipeline restarts. Modifying the definition of a UDF before restarting a pipeline may lead to incorrect results", and advises renaming a function whose meaning changes "to recognize that past results produced using the UDF need to be recomputed" (https://docs.feldera.com/sql/udf/).

**For the design.** Direct support for idea B as the foundation of idea C. A view kept current must know exactly which code produced its stored result; naming functions by hash gives that for free, where Feldera relies on the user renaming (inference).

## C. An index as a view the database keeps current

*Incremental view maintenance* (IVM) means updating a stored query result from the changes to its inputs, instead of computing it again.

### Classical incremental view maintenance

**What it is.** The 1993 paper "Maintaining views incrementally" gives two algorithms for views in SQL or Datalog "and may use UNION, negation, aggregation (e.g. SUM, MIN), linear recursion, and general recursion". The *counting* algorithm stores, for each result row, the number of ways it was derived, "at little or no cost above the cost of deriving the tuple"; a deletion removes a row only when its count reaches zero. *DRed* (delete and rederive), for recursive views, "first delet[es] a superset of the tuples that need to be deleted, and then rederiv[es] some of them" (https://dl.acm.org/doi/10.1145/170035.170066; https://www.kirusa.com/inderpal/papers/sigmod93PubViewMaint930322.pdf). A 1995 survey sorts the problem by the class of view, the resources used (for example whether the base data may be read), and the kinds of change (https://vldb.org/dblp/db/journals/debu/GuptaM95.html; only the abstract was read).

**What it cost in products.** Oracle's "fast refresh" shows what a commercial system restricts. It needs a change log on every input table, and the view "must not contain references to non-repeating expressions like `SYSDATE` and `ROWNUM`", nor analytic functions, nor `NOT EXISTS` subqueries, among others. Aggregate views may use only a listed set of aggregates and "You must specify `COUNT(*)`" (https://docs.oracle.com/en/database/oracle/oracle-database/26/dwhsg/basic-materialized-views.html). A view not eligible fails when refreshed (https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/CREATE-MATERIALIZED-VIEW.html).

**For the design.** The restrictions recur in every system: the function must be deterministic, and some operations need hidden bookkeeping (counts) to be maintainable.

### DBSP and Feldera

**What it is.** A 2023 paper giving "a general, heuristic-free solution" to IVM: a small language over streams of changes, and an algorithm "incrementalizing all DBSP programs", including "nested non-monotonic recursion" (https://www.vldb.org/pvldb/vol16/p1601-budiu.pdf; https://arxiv.org/abs/2203.16684). Feldera is the company and engine built on it, MIT-licensed (https://www.feldera.com/blog/announcing-feldera-the-company).

**What it found.** Any program can be made incremental mechanically, but that alone gains nothing: "the resulting query is no more efficient than a query that computes on the entire dataset". The gain comes from algebra. For *linear* operators (filter, projection, map, union, sum), the incremental version is the operator itself, so "the incremental version of such queries can be computed in time proportional to the size of the changes". Joins are *bilinear* and still do work proportional to the changes, at the cost of keeping indexed state. A chain rule composes the rest (arXiv version above). The theory needs changes to form an *abelian group*: every change has an inverse (an insert undoes a delete).

**What it costs.** Feldera's documentation: "simple projections and filters, do not require keeping any state. Others, such as joins and aggregates, may require storing the state of their input relations". Linear aggregates "such as `SUM`, `COUNT`, `AVG`, `STDDEV`, do not require storing the input relation", and "`MIN` and `MAX` aggregates over append-only collections only store one value per group". State is never freed by default: "Feldera does not automatically garbage collect materialized tables and views", and old state is discarded only when the user declares how late data may arrive (`LATENESS`) (https://docs.feldera.com/tutorials/time-series/).

**What became of it.** DDlog, its predecessor at VMware, is archived ("This project is no longer under development") (https://github.com/vmware-archive/differential-datalog/issues/1179). Feldera is active.

**For the design.** The clearest answer to "which form of view can the database keep current by itself": anything built from maps, filters, unions, joins and group-forming aggregates over changes that can be undone. Cheapness depends on linearity; joins and non-invertible aggregates (min, max) cost memory.

### Differential dataflow and Materialize

**What it is.** *Differential computation* (2013) keeps state "according to a partially ordered set of versions rather than a totally ordered sequence", so iterative computations such as graph algorithms can be updated as their inputs change (https://www.cidrdb.org/cidr2013/Papers/CIDR13_Paper111.pdf). Materialize is built on it (wiki).

**What it allows and costs.** Its `group` operator takes a key, all values for that key, and "a reduction function from a key and list of values to a list of output values"; when a key's input changes, it re-forms the input, re-runs the function, and emits the difference from the old output (https://www.vldb.org/pvldb/vol13/p1793-mcsherry.pdf). So arbitrary user code is allowed inside one group, at the price of re-running it over the whole group. The 2020 *shared arrangements* paper lets queries share indexes. With ten concurrent graph queries, memory without sharing "varies substantially (between 60 and 120 GB)", while with sharing it stays "below 40 GB", "a substantial reduction (2–3×)"; installing a new query became faster "often by several orders of magnitude" (same paper). Materialize warns that rebuilding a view's state (*hydration*) "can take more memory than maintaining that state afterwards", and a replica that runs out of memory while hydrating "restarts and tries again" (https://materialize.com/docs/clusters/sizing/).

**For the design.** Supports allowing general code at one level: per record (map) and per group (reduce), with the database owning the joins and the grouping. Warns that indexes for joins dominate memory, and should be shared between views.

### Noria

**What it is.** A 2018 research database that compiles an application's parameterised queries into a dataflow that "pre-computes results for reads and incrementally applies writes". Its idea is *partial state*: results may be evicted and rebuilt on demand, avoiding "state explosion" (https://www.usenix.org/conference/osdi18/presentation/gjengset).

**What it found and cost.** "Our prototype scales to 5× higher load than a hand-optimized MySQL baseline" on a real web application's queries (same page). On a Lobsters workload scaled up tenfold, it met its latency target "if the memory limit exceeds the 2.6 GB working set (38% of 7 GB total state; 3× base tables)", which the authors call "a reasonable space overhead (around 3× base table size)" (https://www.usenix.org/system/files/osdi18-gjengset.pdf).

**What became of it.** ReadySet, a caching layer in front of MySQL and Postgres, "builds on the Noria project"; Noria itself "is a research database that is not intended for production use" (https://github.com/readysettech/readyset/blob/main/history.md). ReadySet is under the BSL 1.1 licence (https://github.com/readysettech/readyset/).

**For the design.** Supports "find things fast needs no second mechanism", and shows partial state as the way to keep memory bounded: keep hot results, rebuild cold ones. The 3× figure is the best single number found for the memory cost of keeping views current.

### Self-adjusting and incremental computation for general programs

These systems accept ordinary programs, not queries, which is the case the design is asking about.

- **Adapton (2014).** The artifact page's example table compares Adapton with recomputing from scratch on lists of 100,000 elements. For `map`, the first run was 7.46 times slower, the heap grew from 22.8 MB to 96.9 MB (166 MB during updates), and each update was only 3.21 times faster than recomputing. For a tree-shaped `fold` computing a minimum, the first run was 14.3 times slower and updates 1,400 times faster. For `exptree`, the first-run overhead was 131 times (http://www.cs.umd.edu/projects/PL/adapton/). A later thesis reports memoising every call of a 100,000-item merge sort needed "around 1600 MB", cut to "120 MB" by memoising more selectively (https://kyleheadley.github.io/PHDWebsite/SpaceandTimeOptimizationsInAdapton.pdf).
- **Jane Street's Incremental (OCaml, in production).** "firing a single node takes on the order of 30ns, which is far more than, say, summing numbers together" (https://blog.janestreet.com/introducing-incremental/). The tutorial: "One incremental node being a record of 27 fields, meaning that the record alone is 216 bytes", firing takes "between 50ns-150ns", and "a very fine-grained incrementalization can end up slower than a coarse grained one". A node fires only if an input changed by its *cutoff* test and some observer needs it (https://github.com/janestreet/incremental/blob/9b1f4da26fb223da43dc874fc797d39c13f14752/doc/tutorial/part7-optimization.mdx).
- **Salsa (Rust, used by rust-analyzer).** Functions marked as tracked record what they read; on a new revision a function re-runs only if an input changed. *Backdating*: if a re-run gives the same result, dependents are told nothing changed. *Durability*: inputs marked rarely-changing let whole regions skip checking (https://salsa-rs.github.io/salsa/reference/algorithm.html; https://salsa-rs.github.io/salsa/reference/durability.html).

**For the design.** Warns that general-purpose incremental computation is expensive per step: several times the memory, a slower first run, and for simple per-element work a gain of only a few times. It pays off only at coarse boundaries, which the programmer chooses. Salsa's model (memoise whole functions, track reads, stop when the result is equal) is the same as Convex's subscriptions in the wiki, and is the realistic fallback for views that do not fit the query shape (inference).

### The incremental lambda calculus

**What it is.** A 2014 paper that turns a program into its *derivative*, a program that "maps changes in the program's input directly to changes in the program's output, without reexecuting the original program". The transformation is "fully static and automatic", supports first-class functions, and is proved correct in Agda (https://dl.acm.org/doi/10.1145/2594291.2594304).

**What it must restrict.** The transformation only glues changes together; "plugins must provide derivatives of the primitives they define", and "differentiation for λ-calculus only implement binding of changes, leaving 'real work' to derivatives of primitives". A derivative is efficient only if it is *self-maintainable*, using "no base parameters, only their changes", and some primitives are self-maintainable "only in certain contexts" or need "additional restrictions" (https://inc-lc.github.io/resources/pldi14-ilc-author-final.pdf). On a MapReduce-style word count the result "reacts to input changes in essentially constant time" (same paper).

**What became of it.** A research line; no production system built on it was found.

**For the design.** The theory behind the design's question. A whole-program compiler can mechanically derive "how does this view change when the data changes", but only cheap if the view is built from primitives with known, self-maintainable derivatives: collection operations over bags with group-valued changes. General code compiles but gains nothing.

### CouchDB's map and reduce views

**What it is.** A view is a map function, which takes a document and emits key-value pairs, optionally followed by a reduce function. CouchDB stores the emitted rows in a sorted B-tree (https://docs.couchdb.org/en/stable/ddocs/views/intro.html).

**What it restricts.** "The restriction on map functions is that they must be referentially transparent", which "allows CouchDB views to be updated incrementally, only reindexing the documents that have changed". A reduce function must also be "commutative and associative for the array value input", so that `f(Key, Values) == f(Key, [ f(Key, Values) ] )`. This lets CouchDB "store off intermediated reductions directly into inner nodes of btree indexes", so updates and retrievals "have logarithmic cost". A reduce must make its input smaller, and CouchDB warns about reduces that do not (https://web.archive.org/web/20120104205055/wiki.apache.org/couchdb/Introduction_to_CouchDB_views). Views are brought up to date "when they are accessed", not when a document is saved (same page).

**For the design.** The best precedent for views written in the application's own language. Inference: its trick of storing each subtree's partial reduction in the tree's inner nodes fits a hash-named tree especially well. A node's stored reduction is part of its contents, so every version and every agent's world that shares the node shares its reduction for free, and a reduction over a whole world costs only the path that changed.

### What the literature says can be kept current automatically

Putting the sources together, ordered from cheap to expensive:

| Form of view | Kept current automatically? | Cost per change | Memory | Sources |
| --- | --- | --- | --- | --- |
| Per-record map or filter, deterministic | Yes | Proportional to the change | Only the result | DBSP (linear); CouchDB map; Feldera ("do not require keeping any state") |
| Grouped reduce with an associative, commutative operation that has an inverse (sum, count, average) | Yes | Proportional to the change, or logarithmic when partial results sit in tree nodes | Result per group | DBSP; ILC (group-valued changes); CouchDB rereduce; Feldera linear aggregates |
| Grouped reduce without an inverse (min, max), or an arbitrary function of a group | Yes, by re-running the function over the changed group | Proportional to the group's size | The group's input must be kept | Feldera MIN/MAX; differential dataflow `group`; counting algorithm |
| Joins between collections | Yes | Proportional to the change | Indexes of both inputs; about 3× base tables in Noria; 2–3× saved by sharing indexes | DBSP (bilinear); Noria; shared arrangements |
| Recursion | Yes, with DRed or differential dataflow | Can over-delete then rederive | Per-iteration state | DRed; differential dataflow |
| Arbitrary code over the whole database | Mechanically yes, usefully no | No better than recomputing, unless split at coarse memoised boundaries | Several times the plain program | DBSP ("no more efficient"); Adapton; Incremental; Salsa |

Every system requires determinism and none can check it for user code (Feldera: "cannot verify"; CouchDB and Prevayler rely on discipline). Inference: Mo's checked determinism, which services already have, removes the most common failure of all these systems.

## One table

| Work | Year | What it showed | What it cost | What it means for the design |
| --- | --- | --- | --- | --- |
| LMDB | 2011 (from memory) | Copy-on-write B-tree, two roots, no recovery log, one writer | Long readers pin pages; file devolves to append-only | Supports the crash story; warns that kept roots pin garbage |
| CouchDB storage | 2005 (wiki: unconfirmed) | Append-only B-tree survives crashes simply | Compaction needs about twice the disk | Budget for a copying collector |
| Rodeh, Btrfs | 2008, 2013 | Many writable clones via lazy reference counts | Count updates on shared paths | Alternative to reachability scans for worlds |
| WAFL | 1994 onward (from memory) | Log each op, write the tree per batch of thousands | Free-space fragmentation for decades | Copy the log-then-batch pattern |
| ZFS dedup | 2009 (from memory) | Global hash lookup works | 1.25 GiB RAM per TiB; "do not enable" | Get sharing from paths, not global dedup |
| Noms, Dolt prolly trees | 2016, 2019 onward (from memory) | History-independent hash tree; diff by hash; 1TB in production | ~4KB × indexes × depth per transaction; 500GB garbage a week at 650GB | Closest precedent; copy the tree, fix the write rate |
| Merkle search trees, AT Protocol | 2019, 2023 | Ordered hash tree at large scale | History 5–10× size; deletion forced dropping history | Strongest warning on erasure |
| Irmin in Tezos | 2014, 2022 | Git-shaped store for typed values with merges | 140GB unpruned vs 30–60GB; 40GB spare to collect | Supports a typed, mergeable store; GC must be designed in |
| Git as a database | 2016 case | Hash-named objects, packed later | Wide nodes and many fetches made a top-five costly repo | Batch nodes; bound node width |
| Datomic segments | 2012 | Immutable segments, rebuilt in large merges | 900G for 40G live without GC | Batch tree writes; schedule GC |
| CHAMP | 2015 | Canonical persistent map, fast equality | No key order | Fix Mo's in-memory `Map`; not the disk tree |
| BranchBench | 2026 | Version-as-root branching is cheap | Dolt reads and joins were slow, mostly query execution (vendor) | Measure read cost of sharing |
| Unison | 2013 onward (from memory), 1.0 in 2025 | Code by hash of syntax tree; no builds; exact identity | Code lives in a database; dependents get new hashes; update workflow was hard | Adopt for checked forms; keep text source |
| Dhall | 2017 (from memory) | Hash of normal form survives refactors | Needs a language with normal forms | Hash at the checked level, not normal form |
| Nix CA | RFC 62, 2020 (from memory) | Early cutoff by output hash | Still experimental | Add early cutoff so helper changes don't rebuild views |
| Ethereum proxies | 2018 onward (from memory) | Immutable code forces indirection | Storage collisions between versions | Keep hashes for what ran, names for what runs next |
| Counting, DRed | 1993 | SQL and Datalog views incl. recursion | Hidden counts; over-delete then rederive | Bookkeeping per derived row |
| Oracle fast refresh | 1990s onward (from memory) | Product IVM | Long restriction list; `COUNT(*)` required | Determinism and fixed aggregates recur |
| DBSP, Feldera | 2023 | Every program incrementalizable; linear ops cheap | Joins and aggregates keep input state; no automatic GC | The theory for which views are cheap |
| Differential dataflow | 2013, 2020 | Arbitrary per-group functions; shared indexes | 60–120GB vs <40GB shared; hydration peaks | Allow code per record and per group |
| Noria, ReadySet | 2018 | 5× MySQL load; partial state | ~3× base tables | Partial state keeps memory bounded |
| Adapton, Incremental, Salsa | 2014, 2015, 2018 (from memory) | General programs made incremental | First run 7–131× slower; ~4–7× heap; 216 bytes, 50–150ns per node | Only coarse boundaries pay off |
| Incremental lambda calculus | 2014 | Static, proved derivatives of higher-order programs | Needs self-maintainable primitive derivatives | Mo's compiler could derive views built from known primitives |
| CouchDB views | 2008 (from memory) | Map and associative reduce in the app's language; reductions in tree nodes | Views updated lazily on read | The view contract to copy |

## The three strongest warnings

1. **Old versions and garbage become the main operating cost, and every kept root makes it worse.** Datomic: over 900G on disk for about 40G of live data when collection was not run. Dolt: about 500GB of garbage a week on a 650GB database, and up to 10× garbage from single-row inserts. Tezos: about 140GB unpruned against 30–60GB pruned, with 40GB spare needed while collecting. CouchDB: twice the disk to compact. LMDB: one long reader turns it into an append-only store. The design wants old states kept for re-asking and a world per agent; each is a root that stops collection below it. Collection cannot be added later; Irmin and Dolt both added it years in.

2. **Hash-named history and erasure pull against each other, and one large system chose erasure.** The AT Protocol dropped history from its hash-named repositories because deletions were "difficult to process" and history cost "5-10x" in size. GitHub's rewrite changes every later hash, breaks signatures and relies on every clone cooperating. In the design, erasing a person also breaks the "root before and after" that each log entry carries, for every entry after the data arrived, unless erasure is designed into the log and the tree from the start.

3. **A view written as arbitrary code cannot be kept current cheaply by the database.** DBSP shows any program can be made incremental and that doing so mechanically is "no more efficient" than recomputing. General incremental computation costs several times the memory and a slower first run (Adapton: 7–131× on the first run, a few times faster on updates for simple maps), and Jane Street warns that fine-grained incrementality "can end up slower". Only views built from maps, associative reduces and joins are cheap, and joins still cost about 3× the base tables in memory (Noria).

A fourth, nearly as strong: **writing a path of nodes per call is costly unless writes are batched.** Dolt's rule (about 4KB × indexes × depth per transaction) is the measured form of the design's own note "each change rewrites and hashes a path of nodes". WAFL, Datomic, Git and Neon all batch.

## What to copy

1. **Dolt's chunk store and prolly tree, written WAFL's and Datomic's way.** Copy the tree: content-defined node boundaries chosen from keys only, nodes of about 4KB, named by hash, so the same contents always give the same root and two worlds diff in proportion to their difference. Change how it is written: the log of calls is the durable record of each call (as Mo already does), and the tree is flushed once per batch, as WAFL flushes thousands of operations per consistency point and Datomic merges a memory index into new segments. Copy LMDB's reader table, so the collector knows which roots are in use, and design collection by reachability from kept roots before the first slice. Inference: batching cuts both the path writes and the garbage, since intermediate roots inside a batch are never written.

2. **CouchDB's view contract, with DBSP's theory behind it.** A view the database keeps current by itself is a deterministic map from one record to keys and values, optionally followed by a reduce that is associative and commutative, with partial reductions stored in the tree's inner nodes. Joins between views are a database operation over indexed views, not user code. Anything else is an ordinary function, re-run when what it read changes (Salsa, Convex), not maintained. Inference: in a hash-named tree, reductions stored in nodes are shared by every version and world that shares the node.

Unison's hashing of the checked form is the third thing to copy, for code; the design already proposes it.

## Where the wiki is wrong or thin

- **[couchdb.md](../wiki/systems/couchdb.md)** says nothing about its storage or its views, although design-ideas.md cites CouchDB for "views are functions in the application's language". Missing: the append-only B-tree, compaction needing about twice the disk, automatic compaction since 2.1.1, views updated on read, map functions that must be referentially transparent, reduces that must be commutative and associative with partial results in B-tree inner nodes.
- **[dolt.md](../wiki/systems/dolt.md)** is thin on storage costs: the 4KB chunk size, the per-transaction history estimate, 10× garbage for point inserts, automatic GC since 1.75, `gc --full` to drop history, 1TB production databases, 500GB of garbage a week at 650GB, and roughly 10% of disk needed in RAM. Its statement that cheap branches are "paid for by shared storage that slows reads on deep branch chains" may be wrong in its cause: the BranchBench authors' blog says Dolt's time went to "larger reads and joins", and Dolt attributes the gap to query execution (a 653× fix on one query; still about 18× slower than Postgres on another). The paper's own breakdown was not read here, so this is a doubt to check, not a correction. Dolt's sysbench page (point selects about 1.4× MySQL, mean reads 0.82×) is also missing.
- **[datomic.md](../wiki/systems/datomic.md)** lacks how storage works: segments up to about 50KB, each datom stored at least three times, writes batched in a memory index and merged into new segments, `gc-storage` needed with a cut-off of at least a month, and the 900G-for-40G report.
- **[materialize.md](../wiki/systems/materialize.md)** and **[continuously-updated-query-results.md](../wiki/ideas/continuously-updated-query-results.md)** say views "must be written in a language the engine can differentiate". That is thin: DBSP shows every program in its language can be incrementalized, and differential dataflow's `group` runs arbitrary reduction functions; the real limit is which parts are cheap. Missing: shared arrangements (2–3× memory saved), hydration needing more memory than steady state, classical IVM (counting, DRed, Oracle's restrictions), DBSP and Feldera, Noria and its 3× figure, and general incremental computation (Adapton, Incremental, Salsa).
- **[derived-copies-fed-from-one-log.md](../wiki/ideas/derived-copies-fed-from-one-log.md)** lacks CouchDB views, DBSP and Noria as forms of derived copy.
- **[neon.md](../wiki/systems/neon.md)** does not describe its storage (immutable image and delta layer files from the write-ahead log, merged and garbage-collected). That shape is the main alternative to a hash tree for cheap branches.
- **[copy-on-write-branches.md](../wiki/ideas/copy-on-write-branches.md)** lists only databases. Missing: LMDB, Rodeh's reference-counted clones and Btrfs, WAFL and ZFS, Irmin, and history independence as the property that makes diff by hash work. It repeats the Dolt read-cost attribution above.
- **[multi-version-snapshots.md](../wiki/ideas/multi-version-snapshots.md)**: its table of where old versions live and how they are cleared lacks LMDB (freed pages reused once no reader holds an older snapshot) and Datomic (`gc-storage`).
- **[deleting-personal-data-from-history.md](../wiki/ideas/deleting-personal-data-from-history.md)** lacks the content-addressed cases: the AT Protocol dropping history for deletion and size, and GitHub's account of what rewriting history breaks.
- **[immutable-pieces-with-background-merge.md](../wiki/ideas/immutable-pieces-with-background-merge.md)** could add Datomic's segments and Neon's layer files, both of which work this way.
- **Pages missing entirely:** LMDB, Irmin, Git as a store, Unison, DBSP/Feldera, Noria, differential dataflow (only through Materialize), and an idea page for trees whose shape depends only on their contents (prolly trees, Merkle search trees).

## What this means for the project

These are inferences from the sources above.

- **The central idea holds, in a specific form.** A history-independent, hash-named, key-ordered tree is proven at 1TB (Dolt) and at blockchain scale (Irmin, AT Protocol). A plain copy-on-write B-tree (LMDB, Btrfs) gives crash safety and snapshots but not "same contents, same root", which "two worlds can be compared quickly" needs.
- **"The tree can be rebuilt from the log" is the most valuable line in the section.** It allows flushing the tree per batch rather than per call. Without it, Dolt's per-transaction cost applies to every call.
- **Retention is a decision, not a detail.** Before the first slice, decide which roots are kept (every call? every hour? every agent's world until merged?), how long, and who may drop them. Collection follows from that.
- **Erasure needs its own design now.** The options found are: keep personal data outside the hashed tree under per-person keys (crypto-shredding, already in the wiki); keep a node's hash while erasing its bytes, as QLDB did; or give up old states, as the AT Protocol did. The design's "marked hole" is the second option; it keeps the "root before and after" check working only if the log records erasures.
- **Code by hash is low-risk and should come first.** Phase 6 digests already exist. The costs Unison paid came from moving code out of text files and from the update workflow, which the design does not need. Add early cutoff so a harmless change to a helper does not count as a new version of every function above it.
- **Answer to "which form of view the database can keep current by itself":** a deterministic per-record map plus an associative, commutative reduce, with partial results stored in the tree's nodes, and joins done by the database over indexed views. Everything else is a plain function re-run when its reads change. Mo can check determinism; it cannot check associativity, so reduces should come from a small library (sum, count, min, max, set union) or be tested by simulation.
- **For idea 8 (unplanned questions):** "the database proposes an index" becomes "the database proposes a view of the CouchDB shape", which it can then keep current itself.
- **For idea 5 (a world per agent):** worlds are cheap to make (Dolt branched cheaply in BranchBench) but each pins garbage and, if it has views, its own changed paths of view nodes. Reductions stored in shared nodes keep that cost proportional to what the agent changed.

## What I could not confirm

- The BranchBench paper's own explanation of why reads slow as branches deepen; only the authors' blog and Dolt's posts were read.
- Measured bytes written against bytes changed for LMDB, CouchDB, Btrfs or ZFS. Only Dolt gives a rule of thumb.
- Numbers on fragmentation in WAFL, ZFS or Btrfs; the WAFL papers describe it but no figures were extracted.
- The largest CouchDB or Irmin deployment beyond the Tezos figures. The LMDB "500 TB" figure is a binding project's statement about its users.
- Any measured cost of Unison's approach (codebase size, hashing time).
- The content of the 1995 Gupta and Mumick survey beyond its abstract, and Acar's original self-adjusting computation measurements.
- That Adapton requires the programmer to mark where results are memoised (from memory, not confirmed); Salsa and Incremental do require it per their docs.
- Years marked "from memory" in the table (LMDB, WAFL, ZFS dedup, Noms and Dolt, Unison's start, Nix RFC 62, Ethereum proxies, Oracle fast refresh, Dhall, Salsa, CouchDB views).
- Whether Merkle search trees and prolly trees differ measurably in write cost; no comparison was found.
- How many nodes an Irmin commit writes, or Datomic's write amplification per transaction.
