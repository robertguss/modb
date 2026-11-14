Research run on 2026-11-14 by a subagent using Exa, for the ticket [What earlier work stands behind merging by replay, checking reads again, and taking work back out?](../issues/30-earlier-work-on-merging-by-replay.md).

# Earlier work on merging by replay, checking reads again, and taking work back out (researched 2026-11-14)

The design under test is in [design-ideas.md](../design-ideas.md), section "Many agents working together", and idea "4. The log is the truth". It has three parts:

- **A. Merging by replay.** An agent's world is a list of calls to approved write functions. Landing replays those calls, in order, on the main line as it now is. Each function checks its own conditions again, and the promises (declared rules) are checked on the result.
- **B. Running the agent's reads again.** The database ran every read program the agent asked, so it holds each question and its answer. At landing it runs them again. A different answer sends the work back.
- **C. Taking one actor's work back out.** Replay the log from before the actor's first call, without its calls. Later calls that are now refused, or whose recorded answers now differ, are the ones that depended on it.

The wiki pages listed in the ticket already cover [Bayou](../wiki/systems/bayou.md), [Zero](../wiki/systems/zero.md), Calvin's reconnaissance queries, Convex, Dolt, I-confluence and the Berkeley "multi-world isolation" paper. This file does not repeat them. It adds what they lack.

Terms used throughout:

- A *transaction* is a group of reads and writes that the database treats as one step.
- *Serializable* means the result is the same as if the transactions had run one after another in some order.
- *Optimistic concurrency control* (OCC) lets transactions run without locks, then checks at the end ("validation") whether what they read was changed by someone else. If so, the transaction is thrown away and run again (an *abort* and *restart*).
- A *false abort* is an abort that was not needed: the transaction would have been correct anyway.
- A *read set* is the list of things a transaction read; a *write set* is the list it wrote.

## A. Merging by replaying named calls

### Optimistic concurrency control (Kung and Robinson, 1981)

**What it is.** H. T. Kung and John T. Robinson, "On Optimistic Methods for Concurrency Control", ACM Transactions on Database Systems, June 1981 ([ACM](https://dl.acm.org/doi/10.1145/319566.319567); [PDF](https://eecs.harvard.edu/~htk/publication/1981-tods-kung-robinson.pdf)). The methods rely "mainly on transaction backup as a control mechanism, “hoping” that conflicts between transactions will not occur" (same PDF).

**How it works.** A transaction has a read phase, a validation phase and a write phase. "During the read phase, all writes take place on local copies of the nodes to be modified." At validation, the system checks that the changes "will not cause a loss of integrity", and only then are the local copies made global ([PDF](https://eecs.harvard.edu/~htk/publication/1981-tods-kung-robinson.pdf)). This is the design's world (local copies), landing (validation) and main line (global copy), forty-five years earlier.

**What it found.** The authors expected the methods to "be superior to locking methods for systems where transaction conflict is highly unlikely", for example "query dominant systems" ([PDF](https://eecs.harvard.edu/~htk/publication/1981-tods-kung-robinson.pdf)). They named the weak point themselves: "in an optimistic approach, the major difficulty is starvation, which can be solved by using locking" (same PDF). *Starvation* means one transaction keeps losing and never finishes.

**What it cost and what became of it.** See the next entry for the cost under contention. The idea became standard: the wiki's [optimistic concurrency](../wiki/ideas/optimistic-concurrency.md) page lists a dozen shipping systems that use it.

**What it means for the design.** Supports it, and it answers one of the design's open questions. "Fairness between fast and slow agents" is Kung and Robinson's starvation problem, and their answer is to fall back to a lock (here: a claim held as data) after repeated failure (inference).

### When optimistic methods lose: Agrawal, Carey and Livny (1987)

**What it is.** "Concurrency Control Performance Modeling: Alternatives and Implications", ACM TODS 1987 ([PDF](https://pages.cs.wisc.edu/~yxy/cs839-s20/papers/cc_modeling_1987.pdf); [summary](https://blog.acolyer.org/2016/01/07/concurrency-control-performance/)). It compared blocking (locks), immediate restart, and optimistic validation in one simulation model, to explain why earlier studies contradicted each other.

**What it found.** With plentiful resources, optimistic methods kept gaining throughput as more transactions ran at once. With limited resources, blocking won. The conclusion: "a blocking algorithm like dynamic two-phase locking is a better choice than a restart-oriented concurrency control algorithm like the immediate-restart or optimistic algorithms for systems with medium to high levels of resource utilization" ([summary quoting the paper](https://blog.acolyer.org/2016/01/07/concurrency-control-performance/)).

It also exposed a modelling trick, the "fake restart assumption, in which a restarted transaction is assumed to be replaced by a new transaction that is independent of the restarted one" (same page). Under plentiful resources this assumption "produces significantly higher throughputs" for the restart-based methods, "making them look artificially better" (the summary's words).

**What it means for the design.** A warning. A world that is sent back is a real restart, never a fake one: the same agent must redo the same thinking, and thinking is the scarce resource. Any estimate of how often replay fails must count the full cost of re-thinking (inference).

### Serializable snapshot isolation (Cahill, Röhm and Fekete, 2008; PostgreSQL, 2012)

**What it is.** *Snapshot isolation* gives each transaction a frozen copy of the data to read. It is not serializable on its own: two transactions can each read something the other then changes ("write skew", the design's "skew" case). Cahill, Röhm and Fekete (SIGMOD 2008) made it serializable by tracking read-write dependencies and aborting a transaction when a "dangerous structure" of two such edges appears ([PDF](https://people.eecs.berkeley.edu/~kubitron/courses/cs262a-F13/handouts/papers/p729-cahill.pdf)). Ports and Grittner built it into PostgreSQL 9.1 (VLDB 2012) ([PDF](http://vldb.org/pvldb/vol5/p1850_danrkports_vldb2012.pdf)).

**What it found.** The check is deliberately approximate: "we accept a small chance of unnecessary aborts, in order to keep the detection overhead low" ([Cahill PDF](https://people.eecs.berkeley.edu/~kubitron/courses/cs262a-F13/handouts/papers/p729-cahill.pdf)). In PostgreSQL, on the DBT-2++ benchmark held in memory, "SSI causes a 5% slowdown relative to snapshot isolation because of increased CPU usage"; on the 150-warehouse configuration "the serialization failure rate was under 0.25%" ([Ports and Grittner](http://vldb.org/pvldb/vol5/p1850_danrkports_vldb2012.pdf)).

**What it cost.** False aborts, accepted on purpose; memory to remember committed transactions' reads, which PostgreSQL compresses "at the cost of an increased false positive rate" (same paper).

**What it means for the design.** Supports R and frames its trade. A cheap, coarse check that sometimes sends work back needlessly is the industry norm. The difference is the price of one false abort: milliseconds for a database transaction, a whole round of model calls for an agent (inference).

### Deterministic databases: order first, run after (H-Store, Calvin, Aria, Fauna)

**What they are.** These engines accept only whole transactions written as stored procedures, put them in one agreed order, and then run them.

- **H-Store** (Stonebraker et al., VLDB 2007): "H-Store has only one DBMS capability, namely to execute a predefined transaction". Each partition is single-threaded. They measured "H-Store to be a factor of 82 faster on TPC-C" than a popular commercial database ([PDF](https://vldb.org/conf/2007/papers/industrial/p1150-stonebraker.pdf)).
- **Calvin** (Thomson et al., SIGMOD 2012) fixes "a deterministic ordering guarantee" before any locks are taken, and replicates "transaction inputs rather than effects" ([ACM](https://dl.acm.org/doi/10.1145/2213836.2213838)). The paper contrasts itself with Microsoft's Hyder: Hyder's ordered log holds "the after-effects of transactions, whereas the analogous log in Calvin contains unexecuted transaction requests" ([Calvin PDF](https://www.cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf)). That is exactly the design's choice of a log of calls rather than of changed cells.
- **Aria** (Lu et al., PVLDB 2020) drops Calvin's need to know read and write sets in advance. It "first executes a batch of transactions against the same database snapshot", then "deterministically ... chooses those that should commit"; "Aborted transactions will be scheduled for re-execution at the beginning of the next batch" ([PDF](http://www.vldb.org/pvldb/vol13/p2047-lu.pdf)). Its *deterministic reordering* commits transactions in an order that reduces aborts, reaching "higher transaction throughput by up to a factor of three with deterministic reordering on a YCSB workload with skewed access" (same PDF).
- **Fauna**, the commercial descendant: "Fauna’s distributed architecture is based on the Calvin transaction protocol" (vendor claim, [Fauna DTE post](https://fauna.com/blog/inside-faunas-distributed-transaction-engine-dte)). A coordinator "optimistically executes it without committing writes"; later "The set of optimistic read locks collected previously are checked, and if any concurrent modification is detected, this commit attempt will fail and the coordinator will retry the transaction" (same post, vendor claim).

**What became of them.** H-Store became VoltDB (from memory, not confirmed). Fauna announced on 2025-03-19 that "The Fauna service will be ending on May 30, 2025", because "it is not possible to raise the capital needed" ([Fauna](https://fauna.com/blog/the-future-of-fauna)). That was a business failure, not a technical one; the post commits to open-sourcing the core (same page).

**What it means for the design.** Strong support. Aria is the closest database analogue to many worlds forked from one root: all transactions in a batch run on the same snapshot and are then landed in one order, with losers re-run. Fauna's run-on-snapshot, record-the-reads, check-the-reads-at-commit is the design's R for ordinary queries. Aria also shows a better way: the landing order need not be arrival order.

### Concurrent Revisions and the Global Sequence Protocol (Microsoft Research, 2010 to 2015)

**What they are.** In *Concurrent Revisions* (Burckhardt, Baldassin and Leijen, OOPSLA 2010), "each forked task gets a conceptual copy of all the shared state, and state changes are integrated only when tasks are joined, at which time write-write conflicts are deterministically resolved" ([semantics paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/semantics-revisions-2010.pdf); [ACM](https://dl.acm.org/doi/10.1145/1932682.1869515)). The follow-up "Eventually Consistent Transactions" (ESOP 2012) states the merge rule: "When a revision joins another revision, it replays all the updates performed in the joined revision at the join point" ([PDF](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/ecr-esop2012.pdf)). A revision can join into any revision it can reach, not only the main one (same PDF), which is the design's "two worlds reconcile the same way".

The *Global Sequence Protocol* (Burckhardt, Leijen, Protzenko and Fähndrich, ECOOP 2015) gives a client a known prefix of one global sequence of updates plus its own pending updates; its current state is the known prefix with the pending updates applied on top ([PDF](https://drops.dagstuhl.de/storage/00lipics/lipics-vol037-ecoop2015/LIPIcs.ECOOP.2015.568/LIPIcs.ECOOP.2015.568.pdf)). It was implemented in TouchDevelop as "cloud types" (same PDF). It describes Bayou as similar but says there "Conflicts are not resolved simply by ordering updates, but require explicit merge functions provided by the user" (same PDF).

**What they found and cost.** The revisions papers say outright: "there are no read-write or write-read conflicts between revisions" ([semantics paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/semantics-revisions-2010.pdf)). A later analysis puts it as "Rather than issuing rollbacks in the event of conflict (as in TM), in CR the conflict is resolved at run time using deterministic merge functions" ([Overbeek, 2019](https://arxiv.org/pdf/1912.09741)). So these systems never send work back. They buy that by ignoring what a revision read.

**What became of them.** Research systems; TouchDevelop's cloud types were their public deployment ([GSP PDF](https://drops.dagstuhl.de/storage/00lipics/lipics-vol037-ecoop2015/LIPIcs.ECOOP.2015.568/LIPIcs.ECOOP.2015.568.pdf)). Whether TouchDevelop still runs: not checked.

**What it means for the design.** This is the formal model of "replay the updates at the join point", with the same fork, join and many-worlds shape. It is also the clearest evidence that replay alone does not catch stale reasoning: these systems chose not to look at reads, so the discount and lost-update cases would pass. The design's R is what they left out.

### TARDiS (Crooks et al., SIGMOD 2016)

**What it is.** A key-value store that makes conflicting branches a first-class object: "branch-on-conflict". Each thread sees sequential storage on its branch, and the application merges branches "atomically, when and how applications want" ([PDF](https://dl.acm.org/doi/pdf/10.1145/2882903.2882951)).

**What it found.** It "reduces coding complexity" and "judicious branch-on-conflict can improve their local throughput at each site by two to eight times" (same PDF).

**What it means for the design.** A different road. TARDiS merges states with the application's code and keeps the fork point for context; it does not replay calls. It is useful as the contrast case: keeping both branches visible instead of refusing one.

### IceCube (Kermarrec, Rowstron, Shapiro and Druschel, PODC 2001)

**What it is.** Log-based reconciliation of copies that diverged. Each copy's log is a sequence of *actions*. IceCube "captures the static and dynamic reconciliation constraints between all pairs of actions, proposes schedules that satisfy the static constraints, and validates them against the dynamic constraints" ([ACM](https://doi.org/10.1145/383962.384020)). Constraints include *parcels*, an "all-or-nothing grouping", and *alternatives*, a set from which one action is chosen ([2002 technical report](https://asc.di.fct.unl.pt/~nmp/pubs/tr-msr-2002.pdf)).

**What it found.** Replaying in a fixed order drops work that a better order keeps: "With syntactic ordering, approximately 12% Requests are dropped, contrasted to close to none for semantic-directed search" ([report](https://asc.di.fct.unl.pt/~nmp/pubs/tr-msr-2002.pdf)). The report names Bayou's order as a case of such syntactic ordering (same report).

**What it cost.** Search over orderings: "O(n 2 ) in IceCube and O(n) for concatenation" (same report). And design discipline: "Use static constraints as much as possible, and avoid dynamic constraints; the former direct the search while the latter cause schedule execution to roll back" (same report).

**What it means for the design.** Supports the shape and shows a better way. IceCube's dynamic constraints are the design's function checks and promises; its parcels answer the open question in [replay-predictions.md](../models/replay-predictions.md) about a world with several calls (land them whole). Its 12% figure is a warning against landing worlds strictly first-come.

### IMS Fast Path and the escrow method (1970s; O'Neil, 1986)

**What it is.** Patrick O'Neil's "The Escrow Transactional Method" (ACM TODS 1986) describes IBM IMS Fast Path, whose theory dates from "1974 and 1975" ([PDF](https://www.cs.umb.edu/~poneil/EscrowTM.pdf); [ACM](https://dl.acm.org/doi/10.1145/7239.7265)). A program issues `VERIFY QOH ≥ CONST` and then `MODIFY QOH := QOH - CONST`. "Fast Path validates the VERIFY requests at the time the logic is executed and again during commit processing. The MODIFY requests, however, are not actually executed until commit time, after all VERIFY requests have once again been validated" ([PDF](https://www.cs.umb.edu/~poneil/EscrowTM.pdf)). Escrow extends this so many transactions can take from one quantity at once while a bound holds.

**What it means for the design.** Strong support from production practice. "A write function re-checks its own condition at landing, and the write itself is an intent such as 'subtract 3', not a new value" is how Fast Path handled hot inventory counters fifty years ago. It is also the reason the design's "intent" case needs no mechanism.

### Operation-based merging in replicated and local-first systems

Bayou and Zero are on the wiki. This search added nothing that changes them, beyond GSP above, which is their formal model. One newer system, Zeta-Lite (2026), branches an in-browser SQL database for agent memory but merges with ordinary snapshot-isolation write-write checks, not by replay ([arXiv 2609.01818](https://arxiv.org/html/2609.01818)).

### Transaction repair and healing: re-run only the affected part

**What they are.** Instead of throwing away a transaction that fails validation, re-run only the operations that depended on the stale read.

- **Transaction healing** (Wu et al., SIGMOD 2016). The motivating observation: "the majority of transactions failing OCC’s validation phase is due to the inconsistency of a very small portion of its read set" ([PDF](https://yingjunwu.github.io/papers/sigmod2016.pdf)). It "captures the dependencies across operations within a transaction prior to its execution" (same PDF). On TPC-C with 48 cores it scaled "near linearly towards 46 cores, achieving respectively 2.3 and 6.2 times higher throughput" than its locking and Silo-style baselines ([search excerpt of the paper](https://www.comp.nus.edu.sg/~chancy/sigmod16-occ-healing.pdf)).
- **Transaction repair** (Dashti, Basil John, Shaikhha and Koch, SIGMOD 2017). "restarting from scratch creates a negative feedback loop in the system, because the system incurs additional overhead that may create even more conflicts." It summarises each transaction program as a dependency graph and "partially re-executes the conflicting transactions" ([ACM](https://dl.acm.org/doi/10.1145/3035918.3035919); [arXiv](https://arxiv.org/abs/1603.00542)). I did not find its speed-up numbers.

**What they cost.** Both need the transaction's program in advance, so its internal dependencies can be extracted (same sources).

**What it means for the design.** Supports a better way at the level of calls, not of thinking. A replayed call whose function is known code could be healed. The agent's decision cannot: it was made by a model the database cannot analyse (inference). The 2026 agent-workflow system REVISE does the agent-level version for structured workflows (section B).

### 2024 to 2026: agents working on copies

Beyond the Berkeley paper and the 2026 first-commit-wins OS paper, both on the wiki ([branches that reconcile](../wiki/ideas/branches-that-reconcile-with-each-other.md)):

- **"Tracking State Footprints: How Agents Can Transact"** (Mraz, Şerban, Psarakis, Kulahcioglu Ozkan and Katsifodimos; arXiv 2026-10, marked for PVLDB 2027). It argues that "current orchestrators do not track the state that agents read and write" and that agents, "unlike database transactions, ... do not read from a fixed schema or an isolated snapshot, and cannot be replayed deterministically upon failure. They can, however, resolve conflicts semantically instead of aborting" ([arXiv 2610.03140](https://arxiv.org/html/2610.03140v1)). A vision paper, no measurements.
- **Atomix** (arXiv 2026) says orchestrators that treat a tool's return as final "can leave partial effects, losing-branch residue, stale writes, or irreversible sends" ([arXiv 2602.14849](https://arxiv.org/html/2602.14849v2)).
- **Cordon** (arXiv 2026-06) wraps an agent task in a "semantic transaction": reversible changes run "in shadow state", and outward actions wait "in an effect outbox" until the whole flow is validated ([arXiv 2606.17573](https://arxiv.org/abs/2606.17573)).
- **"Agentic Transaction: Towards ACID-Compliant Agent Systems"** (arXiv 2026) defines atomicity over "model invocations, tool calls, document mutations, and external actions" ([arXiv 2608.13900](https://arxiv.org/html/2608.13900v1)).

**What it means for the design.** Several groups reached the same problem in 2026, from the orchestrator side rather than the database side. None found here replays named calls on a main line with automatically recorded reads. Cordon's outbox matches the design's rule that release functions run only on the main line.

## B. Running the agent's reads again at landing

### Re-running scans at commit (Hekaton, PVLDB vol. 5)

**What it is.** The optimistic mode of Microsoft's in-memory engine, described by Larson et al. Validation checks each version read, and "To check for phantoms, T walks its ScanSet and repeats each scan looking for versions that came into existence during T’s lifetime and are visible as of the end of the transaction" ([PDF](https://vldb.org/pvldb/vol5/p298_per-akelarson_vldb2012.pdf)). A *phantom* is a row that a query would now return but did not when it ran.

**What it means for the design.** Direct support. Re-running the read at commit to see whether its answer changed is how a shipping engine catches phantoms.

### Predicates instead of rows (1981 to 2015)

- **Precision locks** (Jordan, Banerjee and Batman, 1981) record each read as a predicate and check every later update against it, so that they block "only if a real conflict occurs" ([ACM](https://doi.org/10.1145/582318.582340)). Course notes give the catch for general predicate locks: "Determining if predicates are compatible is NP-hard" ([Stanford notes](https://www.scs.stanford.edu/nyu/02fa/notes/l8.pdf)).
- **Predicate optimistic concurrency control** (VLDB 1983) keeps "the selector defining the selection predicate" in the read set and validates against it ([PDF](https://vldb.org/conf/1983/P081.PDF)). Authors not checked.
- **HyPer** (Neumann, Mühlbauer and Kemper, SIGMOD 2015) validates by checking that "the (extensional) writes of recently committed transactions do not intersect with the (intensional) read predicate space of a committing transaction", and concludes "there is little need to prefer SI over full serializability any longer" ([ACM](https://dl.acm.org/doi/10.1145/2723372.2749436)).

**What it means for the design.** Supports R and shows its cost choice. Comparing two predicates in general is intractable; HyPer avoids it by testing concrete written rows against the read predicate. The design avoids it differently: it simply runs the read again. That trades CPU at landing for never having to reason about predicates (inference).

### Comparing answers, not data (value-based validation and commutativity)

- **Value-based validation.** NOrec (PPoPP 2010), a software transactional memory, validates by re-reading values, so transactions "detect if they have actually been invalidated by a committing writer, rather than making a conservative assumption" ([PDF](https://cs.rochester.edu/u/scott/papers/2010_ppopp_NOrec.pdf)).
- **Results in the conflict check.** Fekete, Lynch, Merritt and Weihl (JCSS 1990): "The results of operations, in addition to their names and arguments, can be used in checking for conflicts, further increasing concurrency" ([PDF](https://groups.csail.mit.edu/tds/papers/Lynch/jcss90.pdf)). Badrinath and Ramamritham (TODS 1992) went further with "recoverability", letting non-commuting operations proceed under a commit order ([ACM](https://doi.org/10.1145/128765.128771)).

**What it means for the design.** Supports the design's own suggestion, "Comparing answers, not the data under them, helps". Using the returned answer as the unit of conflict is thirty-five years old and proven correct for abstract data types.

### Choosing which reads were relied on: Retro's predicates and Warp's partitions

Retro and Warp (section C) faced B's open problem directly: after a repair, which logged actions must run again?

- Retro "uses predicates to selectively re-execute only actions that were semantically affected". Example from the paper: if a file was changed and later read by process P, "we may be able to avoid re-executing P if the part of the file accessed by P is the same before and after repair" ([Retro PDF](https://www.usenix.org/legacy/events/osdi10/tech/full_papers/Kim.pdf)).
- Warp skips re-running a read query that touched only unchanged *partitions* (groups of rows chosen by column values). "If the database manager cannot determine what partitions a query might read based on the WHERE clause, it conservatively assumes that the query reads all partitions", and the programmer must name the partitioning columns ([Warp paper](https://www.sigops.org/s/conferences/sosp/2011/current/2011-Cascais/08-chandra-online.pdf)).

**What it means for the design.** Retro's rule is the design's rule: re-run only when the part actually read now differs. Warp shows the fallback when that cannot be worked out: assume everything was read, which over-flags.

### The 2026 measurement: stale does not mean unsafe

**What it is.** Zheng, Long, Li and Yao, "Stale Does Not Mean Unsafe: Guard Precision for Tool-Using LLM Agents under Infrastructure State Races", arXiv 2026-08 ([arXiv 2609.29522](https://arxiv.org/abs/2609.29522)). It separates "invalidating races, which break a declared safety predicate, from predicate-preserving and irrelevant races". It compared three commit-time guards: a global epoch, a read-set version, and a "semantic commit predicate" (same page).

**What it found.** "All three guards eliminate unsafe commits, but their availability differs sharply: freshness-based guards needlessly block 92–95% of benign races, forfeiting up to 43% of safe task completions, while the complete predicate guard blocks none." But "deleting a single declared clause converts exactly its fault family into unsafe commits (up to 7.9%)". And "after a freshness-guard block agents re-commit unsafely from refreshed but still-incomplete reads" (same page).

**What it cost.** Small, locally hosted models (4B to 8B parameters), 16 simulated tasks, 3,456 trajectories, one preprint (same page). Treat the numbers as indicative.

**What it means for the design.** The sharpest evidence on B. R as stated is a freshness guard, and freshness guards over-flag heavily. Promises are the precise guard, but only for what was declared. The model's prediction 3 ("NoNeedlessSendBack fails in intent whenever R is on") is the toy version of this finding.

### REVISE (arXiv 2026)

When an agent workflow is revised mid-run, REVISE "intersects its delta with recorded data and control dependencies", "recomputes only the affected region", and "reused results are revalidated before commit". It "reduces model calls by 40.6–56.0%" against a baseline whose name was cut off in what I could read ([arXiv 2609.00643](https://arxiv.org/html/2609.00643v1)). It works on structured workflows (graphs of steps), where dependencies can be recorded; a free-form agent's reasoning has no such graph (inference).

### What the literature offers on "which reads count as relied on"

1. **Let the writer say** (Bayou's dependency check: "a query to be performed at the database and the expected result of that query", [Bayou applications paper](https://faculty.cc.gatech.edu/~keith/pubs/bayou.pdf)). Precise, but agents rarely do it (wiki).
2. **Assume everything read was relied on** (OCC, Fauna, Warp's fallback). Safe, over-flags.
3. **Compare answers, not versions** (NOrec, Fekete et al., Retro's predicates). Removes flags where the data changed but the answer did not. Leaves flags where the answer changed but did not matter.
4. **Judge by the rule, not the read** (the 2026 guard paper; IMS Fast Path's VERIFY; the design's own promises). Precise for what is declared, blind to the rest.
5. **Track dependencies inside the program** (transaction healing, repair, REVISE). Needs analysable code, which an agent's reasoning is not.

Nothing found solves it for an opaque decision-maker. The practical answer the sources point to is a mix: compare answers; treat a changed answer as a reason to ask the write function's own check and the promises first; and send back only when the write function's author has said that read matters (inference).

## C. Taking one actor's work back out

### Retro (Kim, Wang, Zeldovich and Kaashoek, OSDI 2010): the claim checked

**The claim in design-ideas.md**, marked as from memory: "Retro (2010) repaired a system after a break-in by re-running everything except the attacker's actions."

**What the paper says.** Taesoo Kim, Xi Wang, Nickolai Zeldovich and M. Frans Kaashoek (MIT CSAIL), "Intrusion Recovery Using Selective Re-execution", 9th USENIX Symposium on Operating Systems Design and Implementation (OSDI '10), Vancouver, October 2010 ([USENIX](https://www.usenix.org/conference/osdi10/intrusion-recovery-using-selective-re-execution); [PDF](https://www.usenix.org/legacy/events/osdi10/tech/full_papers/Kim.pdf)).

"RETRO repairs a desktop or server after an adversary compromises it, by undoing the adversary’s changes while preserving legitimate user actions, with minimal user involvement." It records an *action history graph*, a detailed dependency graph of the system's run. To repair, it undoes "an unwanted action and its indirect effects by first rolling back its direct effects, and then re-executing legitimate actions that were influenced by that change". It "uses predicates to selectively re-execute only actions that were semantically affected by the adversary’s changes, and uses compensating actions to handle external effects" ([PDF](https://www.usenix.org/legacy/events/osdi10/tech/full_papers/Kim.pdf)).

**Verdict: the year and the gist are right; the mechanism is wrong.** Retro does not re-run everything except the attacker's actions. It rolls back only what the attacker touched and re-runs only the legitimate actions whose inputs changed, and it stops re-running a process once its state converges with the original run ("shepherded re-execution", same PDF). Its whole contribution is avoiding the full replay the design describes.

**What it found.** "Out of ten experiment scenarios, six required no user input to repair, two required user confirmation that a conflicting login session belonged to the attacker, and two required the user to manually redo affected operations." It "avoids false positives and negatives from previous solutions" (same PDF).

**What it cost.** "35–127% in execution time overhead and ... 4–150 GB of log space per day, depending on the workload". A conference-submission site saw "35% slowdown" and "4 GB of logs per day" (same PDF).

**What became of it.** Kim's thesis says Retro's record-and-replay recovery "inspired four new systems: WARP and AIRE for automatic recovery, and POIROT and RAIL for auditing past intrusions", and that Retro itself "is not a good fit for systems that have lots of interaction to users or incur lots of external dependencies" ([thesis](https://taesoo.kim/pubs/2014/kim:thesis.pdf)).

**What it means for the design.** Strong support for C, with a correction. The design's test ("later calls whose recorded answers now differ") is Retro's predicate rule. The design's method ("replay the log from before its first call") is the naive version Retro was built to avoid. Retro also says what the design leaves open: external effects need compensating actions, and some cases need a person.

### Warp (Chandra, Kim, Shah, Narula and Zeldovich, SOSP 2011)

**What it is.** Intrusion recovery for web applications backed by a database. "Warp repairs from an intrusion by rolling back parts of the database to a version before the attack, and replaying subsequent legitimate actions." It allows administrators to "retroactively patch security vulnerabilities---i.e., apply new security patches to past executions". Its "time-travel database allows fine-grained rollback of database rows, and enables repair to proceed concurrently with normal operation" ([ACM](https://dl.acm.org/doi/abs/10.1145/2043556.2043567)). It keeps "every value that ever existed for each row", so a re-run query can read untouched rows as of "precisely the time that query originally ran" ([paper](https://www.sigops.org/s/conferences/sosp/2011/current/2011-Cascais/08-chandra-online.pdf)).

**What it found and cost.** For MediaWiki it needed "no application source code changes to recover from a range of common web application vulnerabilities with minimal user input at a cost of 24--27% in throughput and 2--3.2 GB/day in storage" ([ACM](https://dl.acm.org/doi/abs/10.1145/2043556.2043567)). Non-deterministic calls are matched between runs as an optimisation; when matching fails, Warp re-executes more ("if the application code generates a different HTTP cookie during re-execution, WARP will be forced to re-execute all page visits that used that cookie") ([paper](https://www.sigops.org/s/conferences/sosp/2011/current/2011-Cascais/08-chandra-online.pdf)).

**What it means for the design.** The closest relative of C. It also answers idea 4's "rule for replaying calls whose code has since changed": retroactive patching runs new code over old inputs on purpose. And it shows that repair can run while the system stays live.

### Undo for Operators (Brown and Patterson, USENIX ATC 2003)

**What it is.** "Three R's" undo for an e-mail store: rewind, repair, replay. It logs user interactions "before they enter the system, creating a record of user intent". During undo, state is "physically rewound", the operator repairs, and then lost work "is reintegrated into the repaired system by replaying the logged user interactions while tracking and compensating for any resulting externally-visible inconsistencies" ([USENIX](https://www.usenix.org/conference/2003-usenix-annual-technical-conference/undo-operators-building-undoable-e-mail-store)). Each logged *verb* says whether it commutes with or is independent of another, and reads are logged too: "Synchronous verbs executed read-only are still added to the end of the timeline log, as they can externalize state even if they cannot change it" ([PDF](https://www.usenix.org/legacy/event/usenix03/tech/brown/brown.pdf)).

**What it found and cost.** The abstract reports "only a small performance overhead" and "days or weeks of recovery log on a single disk" (same pages). The figures show median session overheads in the hundreds of milliseconds; I could not read them cleanly enough to quote.

**What it means for the design.** Strong support, and a precedent for logging reads as part of the record because what a reader saw can leave the system.

### Repairing a database after a bad transaction (Ammann, Jajodia and Liu, 2002)

**What it is.** "Recovery From Malicious Transactions", IEEE Transactions on Knowledge and Data Engineering, vol. 14, no. 5, 2002 ([PDF](http://s2.ist.psu.edu/paper/1167.pdf); [IEEE](https://ieeexplore.ieee.org/document/1033782)). "Recovery is complicated by the presence of benign transactions that depend, directly or indirectly, on the malicious transactions." The algorithms "restore only the damaged part of the database", some while the database stays in use (same PDF).

**What later work found.** Finding the dependent transactions means scanning the log forward from the bad one, and "unless damage assessment proceeds at a faster rate than normal processing of transactions, it is possible that the damage assessment process will never terminate" ([Ray et al.](https://www.cs.colostate.edu/~iray/research/papers/bncod04.pdf)).

**What it means for the design.** Support, and a warning the design's "Costs and limits" already half states: removal costs a replay of everything after the call, and on a busy main line that replay must outrun new work.

### Retroactive data structures (Demaine, Iacono and Langerman, 2004; TALG 2007)

They define data structures where one can insert or delete an operation in the past and see the effect now. "We prove that, unlike persistence, efficient retroactivity is not always achievable" ([abstract](https://erikdemaine.org/papers/Retroactive_TALG/)). The general fallback is the *rollback method*: undo the last operations, apply the change, then re-perform them ([paper](https://erikdemaine.org/papers/Retroactive_TALG/paper.pdf)). Cheap retroactivity exists for queues, priority queues, union-find and some search structures, and for "commutative invertible operations" (same pages).

**What it means for the design.** A theoretical floor: in general, removing a past call costs work proportional to what came after. It is cheap only for calls that commute and can be inverted, which is the same line as the design's "intent" case (inference).

### What event-sourced systems do

Martin Fowler's "Retroactive Event" (2005) names three cases: out-of-order, rejected and incorrect events. "A rejected event is an event that you now realize was false and should never have been processed." The system rebuilds to the branch point, reverses the event and marks it rejected; "Events marked as rejected are ignored by all further processing ... They stay in the event log to maintain history" ([Fowler](https://martinfowler.com/eaaDev/RetroactiveEvent.html)). For outside effects: "if processing events should cause interactions with external systems, then this is a Bad Thing", so call them "through gateways that can be configured to ensure that no messages go out unless you are processing an event 'for real'" ([Fowler, Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)).

**What it means for the design.** Support. "Keep the removed call in the log, marked, and skip it on replay" is the established form. The gateway rule is the design's release-function rule.

### Undo for agents (GoEx, 2024)

Berkeley's Gorilla Execution Engine argues for "post-facto validation" of agent actions, made safe by "undoing an action, and damage confinement". It warns that undo "could require maintaining multiple versions of the system state, leading to high costs in terms of memory and computational resources" ([Gorilla blog](https://gorilla.cs.berkeley.edu/blogs/10_gorilla_exec_engine.html)). The year 2024 is from memory, not confirmed.

### Is the claim in C right?

Partly (inference from the sources above):

- **Right:** a later call whose recorded answer now differs depended on the removed work. Retro and Warp use this test.
- **Incomplete:** a call made without reading (a blind "add 3") can depend on the removed work through a promise and still replay cleanly or be refused for a new reason; a call that was refused at the time might now succeed. Retro and Warp re-execute both kinds; the design only flags.
- **Incomplete:** flagging is not repair. A flagged call came from an agent that cannot be "replayed deterministically" ([footprints paper](https://arxiv.org/html/2610.03140v1)), so it goes back to that agent or to a person. Each such call can flag further calls in turn.
- **Costly:** a full replay is the naive form. Every repair system found replays selectively, and still paid 24% to 127% overhead and gigabytes of log per day.

## One table

| Work | Year | What it showed | What it cost | What it means for the design |
| --- | --- | --- | --- | --- |
| IMS Fast Path VERIFY/MODIFY (via O'Neil) | 1970s; 1986 | Conditions re-checked at commit; writes as intents | Special field types | Supports F; "intent" needs no mechanism |
| Kung and Robinson, OCC | 1981 | Local copies, validate, publish | Starvation, "solved by using locking" | Supports A; answers the fairness question |
| Precision locks | 1981 | Reads recorded as predicates | Predicate compatibility is NP-hard in general | Re-running reads sidesteps it |
| Agrawal, Carey, Livny | 1987 | Blocking beats restarts at medium-high load; "fake restart" flatters restarts | n/a (a study) | Warns: agent restarts are real and costly |
| Fekete, Lynch, Merritt, Weihl | 1990 | Operation results can decide conflicts | Per-type reasoning | Supports comparing answers |
| Bayou | 1995 | Dependency check = query + expected result | Hand-written checks and merges | Supports A and B (wiki has detail) |
| IceCube | 2001 | Fixed order drops ~12%; search keeps nearly all | O(n²) search; constraints by hand | Better way: reorder; parcels for multi-call worlds |
| Ammann, Jajodia, Liu | 2002 | Undo bad transactions, keep benign ones | Log scans that must outrun new work | Supports C |
| Undo for Operators | 2003 | Rewind, repair, replay logged intents; compensate | Small overhead; days-weeks of log | Supports C; reads logged too |
| H-Store | 2007 | Stored procedures only; 82x on TPC-C | No ad hoc transactions | Supports "data changes only by approved functions" |
| SSI (Cahill; PostgreSQL) | 2008, 2012 | Serializable with false aborts accepted; 5% slowdown, <0.25% failures | False aborts; memory | Norm for R; cost per abort differs for agents |
| Concurrent Revisions, ESOP 2012, GSP | 2010-2015 | Join "replays all the updates"; worlds join each other | Ignores read-write conflicts | Formal model of A; shows why R is needed |
| Retro | 2010 | Selective re-execution after intrusion | 35–127% time, 4–150 GB/day | Supports C; corrects the design's description |
| Hekaton | 2011-12 | Repeats scans at commit to catch phantoms | CPU at commit | Supports R directly |
| Warp | 2011 | Row-level time travel; retroactive patching | 24–27% throughput, 2–3.2 GB/day | Supports C; answers "code changed since" |
| Calvin | 2012 | Log of unexecuted requests; recon reads validated at execution | Sets known in advance or a restart | Supports A and B |
| HyPer MVCC | 2015 | Precision-locking validation, cheap serializability | Main memory | Supports predicate-level R |
| TARDiS | 2016 | Branch on conflict, merge later; 2–8x throughput | App writes merges | Contrast: keep both, do not refuse |
| Transaction healing / repair | 2016, 2017 | Re-run only affected operations; up to 6.2x | Program known in advance | Better way for calls, not for thinking |
| Aria | 2020 | Batch on one snapshot, deterministic commit, reordering up to 3x | Batching delay | Closest database analogue; reorder |
| Fauna | 2017-2025 | Calvin-based; reads checked at commit (vendor claim) | Service ended 2025-05-30 for funding | Supports B in production |
| Stale Does Not Mean Unsafe | 2026 | Freshness guards block 92–95% of benign races; predicate guard none | Contract must be complete | Warns: R over-flags; promises are precise |
| Footprints; Cordon; Atomix; REVISE | 2026 | Agents need read/write tracking, outboxes, selective recovery | Mostly visions or preprints | Same problem, orchestrator side |

## Is the replay rule new?

**No. It is an existing idea under other names, put together in a combination that has not been found shipped.**

- Replaying named operations on the agreed state at a join is Bayou (1995), Concurrent Revisions and GSP (2010 to 2015), Calvin's log of "unexecuted transaction requests" (2012) and Zero today.
- Each operation re-checking its condition at commit is IMS Fast Path (1970s) and Bayou's dependency check.
- Re-running reads at commit and refusing on a changed result is Kung and Robinson's validation (1981), Hekaton's repeated scans, Calvin's reconnaissance reads and Fauna's read check.
- Declared rules checked over the merged result are IceCube's dynamic constraints and Dolt's constraint check.
- Removing one actor by replaying without it is Retro, Warp, Undo for Operators and Fowler's rejected events.

What is less common is the combination: worlds that last hours, whose read sets are captured automatically as whole read programs with their answers, landed by replay with function checks and promises, with the same log serving audit and removal. The least precedented single piece is applying this to a decision-maker that is an opaque model, which cannot be replayed or healed. Several 2026 preprints are working on that piece from the orchestrator side ([footprints](https://arxiv.org/html/2610.03140v1), [guards](https://arxiv.org/abs/2609.29522), [Cordon](https://arxiv.org/abs/2606.17573)). The design should cite its ancestors rather than present the rule as new (inference).

## The three strongest warnings

1. **Sending work back on any changed answer will over-flag, and each false send-back is a full re-think.** Freshness guards "needlessly block 92–95% of benign races, forfeiting up to 43% of safe task completions" ([2026](https://arxiv.org/abs/2609.29522)); SSI accepts false aborts by design ([Cahill](https://people.eecs.berkeley.edu/~kubitron/courses/cs262a-F13/handouts/papers/p729-cahill.pdf)); restart-based methods lose to blocking at medium to high load, and modelling restarts as fresh work makes them look better than they are ([Agrawal et al.](https://blog.acolyer.org/2016/01/07/concurrency-control-performance/)). The fix the sources point to is to judge by the rule where one is declared, and to compare answers rather than versions. Agents also re-commit unsafely after a refresh that is still incomplete (same 2026 paper).
2. **First-come landing with plain send-back starves slow agents and drops work a better order would keep.** Kung and Robinson name starvation as optimism's "major difficulty" and fix it with a lock ([1981](https://eecs.harvard.edu/~htk/publication/1981-tods-kung-robinson.pdf)); IceCube drops about 12% under fixed order against nearly none with search ([report](https://asc.di.fct.unl.pt/~nmp/pubs/tr-msr-2002.pdf)); Aria gains up to three times by reordering ([Aria](http://www.vldb.org/pvldb/vol13/p2047-lu.pdf)); repair work notes that restarting "creates a negative feedback loop" ([Dashti et al.](https://dl.acm.org/doi/10.1145/3035918.3035919)).
3. **Taking work back out is neither a plain replay nor cheap nor complete.** Every working system replays selectively, using dependencies and predicates, and still paid 24–127% overhead and gigabytes of log per day ([Retro](https://www.usenix.org/legacy/events/osdi10/tech/full_papers/Kim.pdf), [Warp](https://dl.acm.org/doi/abs/10.1145/2043556.2043567)). Outside effects need compensation, and some cases need a person (Retro: four of ten). Damage assessment must outrun new work or never finish ([Ray et al.](https://www.cs.colostate.edu/~iray/research/papers/bncod04.pdf)). In general, "efficient retroactivity is not always achievable" ([Demaine et al.](https://erikdemaine.org/papers/Retroactive_TALG/)).

## Where the wiki is wrong or thin

- **[writes-that-carry-their-assumptions.md](../wiki/ideas/writes-that-carry-their-assumptions.md), [merging-by-meaning.md](../wiki/ideas/merging-by-meaning.md), [bayou.md](../wiki/systems/bayou.md) and research 06** say Bayou's dependency check is "the one mechanism" found that records the assumption. Too narrow: IMS Fast Path's VERIFY, Calvin's reconnaissance reads, Fauna's read check and Hekaton's repeated scans all record a read and check it again at commit. Bayou is the one where the writer states it by hand.
- **[merging-by-meaning.md](../wiki/ideas/merging-by-meaning.md), Disagreements, "Does anything merge by intent?"** Research 00's "nobody does" is wrong. Escrow and Fast Path, commutativity-based concurrency control (Fekete et al. 1990), GSP and Concurrent Revisions all merge by the meaning of operations.
- **[branches-that-reconcile-with-each-other.md](../wiki/ideas/branches-that-reconcile-with-each-other.md)** says "None in full" reconciles branches with each other. Concurrent Revisions and the ESOP 2012 paper let any revision join any revision it can reach, by replaying updates; TARDiS keeps sibling branches as first-class. None of them checks reads, so the page's real gap is reconciliation that also checks reads. Its "rule for siblings" item should add IceCube and Aria reordering.
- **[optimistic-concurrency.md](../wiki/ideas/optimistic-concurrency.md)** has no primary for the idea (Kung and Robinson 1981), no Agrawal et al. 1987, no starvation, and no repair or healing as an alternative to abort. Its "false aborts" line has no numbers; PostgreSQL's are above.
- **[zero.md](../wiki/systems/zero.md)** is thin: no link to GSP, which is the formal model of re-running pending mutators on a known prefix.
- **[read-and-write-sets-known-up-front.md](../wiki/ideas/read-and-write-sets-known-up-front.md)** should add Aria, a deterministic database that does not need the sets in advance, and Fauna as Calvin's production descendant and its 2025 end.
- **[one-writer-at-a-time.md](../wiki/ideas/one-writer-at-a-time.md)** lacks H-Store, the strongest evidence for single-threaded execution of stored procedures (82x).
- **[storing-events-instead-of-state.md](../wiki/ideas/storing-events-instead-of-state.md)** says nothing about undoing an event later events depended on: Fowler's rejected events and the gateway rule belong there, and Retro and Warp need pages.
- **design-ideas.md** describes Retro as re-running everything except the attacker's actions; it re-ran only affected actions (section C). design-ideas.md is not a source, so this belongs on a new Retro wiki page.

## What this means for the project

All inference from the sources above.

- **Keep the replay rule, and name its ancestors.** It is Bayou plus Kung and Robinson plus Retro. Saying so makes the design easier to check against forty years of results.
- **Make R compare answers, and let a changed answer go to the write function's check and the promises first.** Send back only for reads that the function's author marked as relied on, or when no rule covers the case. This is the 2026 guard finding and Bayou's explicit check combined.
- **Add a starvation rule now.** After a set number of send-backs, the agent takes a claim held as data, as Kung and Robinson prescribed.
- **Land a world whole.** IceCube's parcels and GSP's update transactions agree with the replay-predictions doc: promises are checked at the end of a world, not after each call.
- **Do not promise cheap removal.** Plan for selective replay with recorded reads, rejected calls kept in the log and skipped, compensation records for anything released, and flagged calls sent to their agent or a person.
- **Treat Warp's retroactive patching as the precedent** for replaying old calls under changed code.
- **For the TLA model:** add a slow agent that keeps losing (starvation), and a benign race that R sends back (false send-back), so the predictions can fail where the literature says they will.

## What I could not confirm

- Calvin's headline throughput: the PDF text I read did not contain it.
- Transaction repair's speed-up numbers (Dashti et al., 2017).
- Transaction healing's numbers come from a search excerpt of the paper, not a full read.
- Undo for Operators: the exact way it detects and compensates for "externally-visible inconsistencies"; I read only the abstract and parts of the body.
- Bayou's undo and redo of tentative writes still rests on the summary the wiki cites; the applications paper I found confirms only the dependency check and merge procedure.
- That H-Store became VoltDB, and whether Fauna has released its open-source core.
- Authors of the 1983 predicate OCC paper, the 2002 IceCube report and NOrec; the year of GoEx.
- Whether TouchDevelop and its cloud types still run.
- The 2026 agent papers are preprints; their numbers come from small models and simulated tasks.
- Macaroons (the other claim the ticket names) checks out: Birgisson, Politz, Erlingsson, Taly, Vrable and Lentczner, NDSS 2014; caveats "attenuate and contextually confine when, where, by who, and for what purpose a target service should authorize requests" ([NDSS](https://www.ndss-symposium.org/ndss2014/ndss-2014-programme/macaroons-cookies-contextual-caveats-decentralized-authorization-cloud/); [PDF](https://www.ndss-symposium.org/wp-content/uploads/2017/09/04_3_1.pdf)). I did not check whether a holder can add caveats without the issuer beyond this abstract.
