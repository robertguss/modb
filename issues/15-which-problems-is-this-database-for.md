# Which problems of agents sharing data is this database for?

Type: grilling
Status: open
Blocked by: [Agents and databases today](09-agents-and-databases-today.md), [One comparison across all families](10-one-comparison-across-families.md), [Keeping sensitive data from agents and model providers](20-keeping-sensitive-data-from-agents.md), [Security of a database that agents use](21-security-of-a-database-agents-use.md)

## Question

Of the coordination problems (overlapping work, conflicting writes, who changed what and why, try on a copy, guarded writes, discovery), the two Robert raised on 2026-11-13 (keeping sensitive data from agents and model providers, with HIPAA and FERPA in mind; and security against the attacks agents make possible), and any others the research surfaced, which one to three is this database for?

This ticket must weigh the evidence against the coordination-first decision in `research/09-agents-and-databases-today.md`: agents send high volumes of exploratory queries; every recorded incident came from broad credentials and injected instructions, not from concurrency; branching has been added on top of existing databases without a new engine; and the usage figures show many small private databases more than many agents sharing one.
