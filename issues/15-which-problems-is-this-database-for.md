# Which problems of agents sharing data is this database for?

Type: grilling
Status: claimed
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
