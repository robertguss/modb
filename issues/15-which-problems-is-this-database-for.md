# Which problems of agents sharing data is this database for?

Type: grilling
Status: closed
Blocked by: [Agents and databases today](09-agents-and-databases-today.md), [One comparison across all families](10-one-comparison-across-families.md), [Keeping sensitive data from agents and model providers](20-keeping-sensitive-data-from-agents.md), [Security of a database that agents use](21-security-of-a-database-agents-use.md)

## Question

Of the coordination problems (overlapping work, conflicting writes, who changed what and why, try on a copy, guarded writes, discovery), the two Robert raised on 2026-11-13 (keeping sensitive data from agents and model providers, with HIPAA and FERPA in mind; and security against the attacks agents make possible), and any others the research surfaced, which one to three is this database for?

This ticket must weigh the evidence against the coordination-first decision in `research/09-agents-and-databases-today.md`: agents send high volumes of exploratory queries; every recorded incident came from broad credentials and injected instructions, not from concurrency; branching has been added on top of existing databases without a new engine; and the usage figures show many small private databases more than many agents sharing one.

## Comments

**2026-11-14.** Ten candidate centres were put to Robert: A every write answers for itself; B data that protects itself; C many worlds; D undo anything; E the database is the program; F a database that explains itself; G built for the query flood; H memory for agents; I a database per agent; J a shared workspace for agents' work. Robert chose A as the centre, and asked which of the others to pull in.

**2026-11-14, later.** Proposed split: A with F (the database explains itself) and stated assumptions inside it for the first version; D (undo) and B (data that protects itself) second; C and I kept open; G and H out. Robert moved B into the first version because he wants to be able to use the database with FERPA data, and asked what protects that data and what protects the database from an outside attacker. A research ticket on the security baseline for student records was added.

**2026-11-14, outside review.** Robert asked for an outside opinion on the whole direction from a model of another provider (GPT-6 Astra). Its verdict: keep the ambition and reverse the order. Choose one piece of Robert's own work first, build the accountable write for it as a Mo service on Mo's existing storage, use it, and only then decide whether a new storage engine is justified. Its other points, each checked:

- The plan chose mechanisms before choosing the work they improve: [What real data of yours goes in first?](12-what-real-data-goes-in-first.md) is still open.
- Mo's one earlier service, the task queue, lost its week-long run because "Robert starts every agent thread himself, so no thread leases from the queue" (`~/code/mo/docs/ROADMAP.md`). A service chosen without a real use repeats that.
- The reason an agent gives for a write is a declared reason. The database can check grants and conditions; it cannot check that the reason is true.
- An accountable write covers changes. It does not cover reads, exports, backups or what is sent to a model provider.
- Earlier work the survey missed: Hippocratic databases (2002) and Hyperledger Fabric's endorsement policies; see [What earlier work binds a write or a read to a purpose and an approval?](25-earlier-work-on-purpose-and-approval.md).
- Two limits in Mo today: one service credential reaches the operator views of all state (`docs/agent-guide.md`), and a snapshot deletes the recovery log (`src/host/store.c`), so that log is not a permanent history.
- The risk nobody named: approved rules give false assurance. Keeping the rules right, and the person's attention to review them, may be the scarce thing, not write throughput.

**2026-11-14, second outside review.** A model from a third provider (Gemini 4 Carbon) reviewed the direction after reading the first review. Its verdict: do not build a storage engine at all; keep the accountable write as a layer of rules above SQLite; build something Robert works in every day. Its points, each checked unless marked:

- A database is not used directly; an application on top of one is. An engine pushes Mo towards disk internals, while Mo still cannot make an outbound HTTPS call, write raw bytes, tell one caller from another, or let a service hold a file or a socket (`~/code/mo/docs/design/services.md`: state, inputs and results hold no capabilities; one `token` per service).
- A Mo service already is one writer over a memory image logged to SQLite, so a database written in Mo either duplicates that or bends it.
- The accountable write is not new: regulated industries have long required who, under what authority and why on each change to a record (FDA 21 CFR Part 11 and the rules around it; not checked here), and purpose-based access control dates from 2005. It also says Datomic can check facts on the transaction at commit, where the wiki says "optional, unchecked". All three go to [What earlier work binds a write or a read to a purpose and an approval?](25-earlier-work-on-purpose-and-approval.md).
- Who, grant, conditions and resulting state can be checked. Why cannot: a hijacked model invents a plausible reason. A centre about writes also leaves out reads, where leaks happen.
- "Data that protects itself" is an unsolved problem no shipping database solves (`research/20`), so it does not belong in a first version; nor do student records.
- Mo's service limits bound the first slice: 16 MiB of saved state, 16 KiB per request, 32 KiB per reply, 20 requests a second, about a million steps per handler (`src/base/limits.h`). This repo's wiki, research and tickets total 913 KiB, so the state limit is not near; nine files exceed the request limit and one the reply limit.
- Its first job: this project's own tickets and wiki, served by a small Mo service with a token per agent, conditions on each change and a list of who did what, used by two agents for a week.
- The risk it names: research and tickets, which agents produce without effort, standing in for the friction of living in rough Mo software. It counts 126 wiki pages and no Mo code.
- Two errors in it: no Rust prototype exists, only a ticket; and the wiki would not reach the 16 MiB limit.

Both outside reviews and the agent working with Robert now agree on the first step: a Mo service he uses, with accountable writes, on SQLite. They differ on the engine afterwards: this review says never, the first says only if a guarantee needs it.

**2026-11-14, Robert's decision.** After reading the three views, Robert said: "I still want the database." The database stays the destination. The advice to drop the storage engine is not taken.

**2026-11-14, zoom out.** Robert asked to step back: no SQL presumed, a database "written in Mo itself", not built around FERPA or his own work. Two pictures were put to him. In the first, the database is a server that programs talk to, and Mo is only what it is built in. In the second, the database is the Mo program: data lives in Mo types, every read and write is a Mo function the compiler has checked, there is no query language, and an agent with a new question writes a small Mo program. The second is centre E from the list above ("the database is the program"), with the accountable write inside it. Its known cost is in [Models that lost to relational or stayed niche](../wiki/families/models-that-lost-or-stayed-niche.md): object databases tied data to one language and lost.

**2026-11-14, exploring both pictures.** Robert had the first picture in mind, found the second intriguing, and asked to stay here and explore before choosing. Observations and ideas put to him:

- A Mo service is already a small version of the second picture: one typed state, tools that are functions from the old state to a new state and a reply, time passed in as an argument, every call logged (`~/code/mo/services/task-queue/main.mo`). What it lacks to be a database: state larger than memory, finding things without walking everything, questions nobody wrote a tool for, more than one caller, and data shared between programs.
- The pictures meet if the first picture's request language is Mo: an agent sends a small Mo program, and the database checks it and runs it beside the data.
- Ideas: the request is a program; promises as the schema; upgrades as migrations; the log as the permanent truth; a world per agent; simulation built in; shared stores reached through capabilities; and three answers to unplanned questions (scan, indexes the database proposes, a declarative form inside Mo).

The two pictures and the ideas are written out in [design-ideas.md](../design-ideas.md).

**2026-11-14, closed unanswered.** Robert stopped the map before this ticket was answered. What Robert decided along the way is in section 7 of [design.md](../design.md). See [the map](../map.md).
