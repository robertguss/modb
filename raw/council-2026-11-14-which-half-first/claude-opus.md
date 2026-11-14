**1. Recommendation.** Put the seam first, from the storage side: build a collection that keeps versions without copying and a saved state that keeps that sharing, then run a thin slice of the upper half on it. I'm about 65% sure.

**2. Three strongest reasons**

- **Today's service can't hold a version cheaply, even with a tree written in Mo.**
  - Checked in the code and read in a document: `docs/design/saved-state.md:199` says "Sharing is expanded, not serialized". Lines 209–216 say every new state goes through encode and decode before it is accepted.
  - Checked in the code: `src/vm/service.c:259-266` and `:305` do exactly that.
  - My reasoning: a world, a snapshot or an old root kept in the state therefore becomes a full copy on every write, whatever collection the program uses. Building the upper half first would test worlds, snapshots and history with whole copies at a small size. The two models already showed that much at toy size.
  - "Which half first" says versions cost a copy (line 595). It understates the problem: this cannot be fixed in the library layer.
- **The upper half's logic is already largely de-risked, and its needs are now stated.**
  - Read in a document: the replay model matched all 48 predictions and the worlds model all 40 (`models/README.md`). The land-whole sketch passes `mo test` (`sketches/README.md`). Every-question-counts and landing whole were decided on 2026-11-14 (`design-ideas.md`).
  - My reasoning: "built for needs the upper half has only guessed at" (line 611) is out of date. Snapshots for read-only programs, roots per world, a kept log and replay all follow from decisions already made. Line 243 already lists them.
- **The growing cost is Mo's own cost, not the database's.**
  - Read in a document: issue 11 splits a write's cost three ways. The part that grows is about 0.65 ms per 1,000 rows of whole-state encode, decode and checksum.
  - Checked in the code: a write also starts with a whole copy of the map. `service.c:293-294` duplicates parameters marked owned, and `src/heap/table.c:254-272` copies a table whenever its reference count is not 1.
  - My inference: that copy is the 10% `copy_table` share in issue 11, so changing only how state is saved would not flatten the line.
  - My reasoning: fixing both grows Mo for every service, which is the stated purpose. "Usable sooner" was the main argument for the upper half, and it has been ruled out.

**3. Strongest case against.** My reasoning: the biggest unknowns are in the upper half, and storage cannot answer them.

- Do agents write correct read programs?
- How often is a send-back needless?
- Can a person review "what becomes possible"?

A clean versioned store could be built and request-as-program could then fail with agents. Storage-first also changes the runtime early. That reopens memory safety (issue 24) and collides with Phases 6 to 8. Both outside reviews warned against this half (read in a document).

**4. What "Which half first" gets wrong, misses or frames unfairly**

- **Wrong or missing:** saving expands sharing and every write copies the map in memory. Together these mean "upper half first on today's services" cannot really test worlds or history (checked in the code, see above).
- **Missing order: learnability first.**
  - Read in a document: idea 1 says `learnability/` in Mo could measure whether agents write correct small programs.
  - My reasoning: that measurement needs neither half and is the largest risk to idea 1.
- **Missing third track: the call path.**
  - Read in a document: 10 ms of HTTP per call (issue 11).
  - Checked in the code: 20 calls a second with a burst of 40, a 16 KiB body and a 32 KiB reply (`src/base/limits.h:518, 524, 566-567`).
  - My reasoning: for many agents these limits bind before storage does, and neither order touches them.
- **Unfair rework comparison.** My reasoning: rewriting write functions costs little if the new collection keeps a `Map`-like interface. Building storage for the wrong needs costs more. The section weighs the two as equals.
- **Untested ceiling.** Checked in the code: `MO_LIMIT_SAVED_NODES` is 2^20 (`limits.h:364`). My reasoning: rows that are records with several fields could hit that node limit before the memory ceiling. Issue 11 measured only a `Map(Int, Text)`.

**5. What to measure before committing**

- **(a) A persistent ordered map written in Mo today, inside a service.**
  - Measure: steps per insert and lookup at 100k rows, against `Map`.
  - Measure: the saved size with N retained versions. I predict roughly N× (my reasoning).
  - Find out: what it takes to make the saved codec and the handler handoff keep sharing.
  - What would change my mind: if keeping sharing needs deep runtime or memory-safety work that collides with Phases 6 to 8, I'd switch to the upper half first on whole copies with a hard size cap.
- **(b) A small learnability run of agents writing read programs against a typed view.**
  - What would change my mind: correctness well below the query-language baselines (issue 04) would put "learnability first" ahead of both halves.

**6. Claims I checked against Mo's code**

- Confirmed:
  - A snapshot deletes the log: `src/host/store.c:472-476`.
  - Snapshot every 100 messages: `limits.h:365`.
  - About a million steps of work: `limits.h:333`.
  - 64 MiB per call: `limits.h:334`.
  - 16 MiB saved state: `limits.h:344`.
  - Request, reply and rate limits: `limits.h:518`, `:524`, `:566`.
- Nuance, not an error: "a Mo `Map` is one block, so a changed copy is a whole copy" holds only when the map is shared. A map with one owner is updated in place (`table.c:254`). At the service boundary the state is shared, so the claim holds in practice.
- Incomplete: "Only the third cost is about how data is stored" leaves out the in-memory map copy at handler entry (`service.c:293-294`, `table.c:271`).

I didn't run anything, so the `copy_table` attribution and the N× saved-size prediction are inferences. Reference section 11 beyond 11.5's opening lines was not read.
