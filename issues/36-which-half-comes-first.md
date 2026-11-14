# Which half comes first?

Type: grilling
Status: resolved

## Question

HITL. The design has an upper half, which is what agents and people touch, and a storage half, which is how the data is kept. Which is built first: the upper half on Mo's services as they are, the storage half, or another order?

Robert accepted the upper half first on 2026-11-14. He reopened it the same day, after the measurements on [How fast and how large is a Mo service today?](11-how-fast-and-large-is-a-mo-service.md): "It doesn't really matter to me which one comes first. I'm in no rush." The trade-offs of each order are in [design-ideas.md](../design-ideas.md) under "Which half first".

## The council's review, 2026-11-14

Robert asked for a review by models of other providers. Three ran through the `council` skill, each with the same brief, read-only, and without Claude's view. Their reviews are kept word for word in [raw/council-2026-11-14-which-half-first/](../raw/council-2026-11-14-which-half-first/README.md).

| Reviewer | Builds first | Its confidence | What would change its mind |
| --- | --- | --- | --- |
| GPT Sol (`gpt-6.1-sol`) | A small runnable sketch of the boundary between the halves, then one thin slice through both, with storage that writes only what changed | 85% | Storage first, if ordinary write functions cannot keep a bounded cost without paging. Upper half first, if the sketch shows a simple boundary and overlapping worlds fit today's limits. |
| Gemini Carbon (`gemini-4-carbon`) | A versioned collection with explicit identifiers for its nodes, in memory, behind a seam; then the upper half; storage on disk last | 75% | A small paged tree in the C host first, if Mo needs a capability or an error type on every lookup. Storage and indexes earlier, if read programs lose to a fixed form of query. |
| Claude Opus (`claude-opus-5-5`) | The seam from the storage side: a versioned collection and a saved form that keeps sharing; then a thin slice of the upper half | 65% | Upper half first on whole copies with a hard cap on size, if keeping sharing needs deep runtime work. Learnability first, if agents write read programs badly. |

**New facts they found.** Each was checked against Mo at commit `392f3bf9`.

- A saved value writes shared data out in full, and a service loads that copy back after every write (`docs/design/saved-state.md`: "Sharing is expanded, not serialized"; `encoded_copy` in `src/vm/service.c`). A world, a snapshot or an old version kept in a service's state is therefore a full copy at every write, whatever collection the program uses.
- A write copies the whole map before the function changes it. The service gives the function a second reference to the state, and a shared map is copied on its first change (`src/vm/service.c`, `src/heap/table.c`).
- Only calls that change the state are logged. A read is not (`replacement` and `persist` in `src/vm/service.c`).
- A service's state, inputs and results may hold no capability (`docs/reference/README.md`, section 11.5). A storage library that loads nodes through a capability does not fit a service as Mo stands.
- New code enters a running service only through an upgrade of the whole service (`src/tools/protocol-upgrade.c`).
- Saved state is limited to about a million nodes (`MO_LIMIT_SAVED_NODES`). The measurements used rows of one text; rows with several fields may reach this first.

**Corrections to our documents.** All applied on 2026-11-14.

- "Every call is logged" was wrong; see above.
- The growing cost of a write is mostly the saved copy, not the checksum for the log.
- `authenticate` does not spend its time checking the token. It parses the request's headers in Mo, and `plan` converts them again. The token is checked in C.
- The heap limit is 64 MiB less the stack and less 1,440 bytes.
- The supervisor's rule is five failures within 60 seconds for a restart, and a stop at the third restart.
- Two line counts in `design-ideas.md` were out of date.

**Where a reviewer was wrong.**

- Gemini Carbon said the state is encoded and decoded on every write "even without a store". A service with no store takes a plain reference (`saved_copy` in `src/vm/service.c`).
- Gemini Carbon cited `src/base/limits.h:221` for the limit on saved nodes. That line defines another limit. The limit itself is as it said, at line 364.

## How the reviews were evaluated

Robert asked for the reviews to be evaluated with TypeSafe. Its model, Jev, answers a typed question about supplied text with a probability. It was asked for judgments only; the verdicts below were made in code, and Claude's predictions were written before the run. The questions, requests, replies and predictions are in [raw/council-2026-11-14-which-half-first/typesafe/](../raw/council-2026-11-14-which-half-first/typesafe/). It took 24 requests and 28,882 tokens, about a tenth of a cent. Three more requests were sent by mistake when the second pass was run twice. Its answers differed from the first run's by at most 0.04 and changed no verdict, so the same question does not return exactly the same number each time.

**Where each review stands.** The probability that each review says so. At 0.7 and above it counts as yes, at 0.3 and below as no.

| Statement | GPT Sol | Claude Opus | Gemini Carbon |
| --- | --- | --- | --- |
| Recommends the upper half first, on today's services | 0.18 | 0.02 | 0.03 |
| Recommends the whole storage half first | 0.06 | 0.32 | 0.03 |
| Names an experiment to run before committing | 0.99 | 0.99 | 1.00 |
| Recommends a versioned collection before the upper half | 0.19 | 0.98 | 0.94 |
| Leaves storage on disk until after the upper half | 0.10 | 0.03 | 0.96 |
| Says what storage must provide is already known | 0.11 | 0.92 | 0.03 |
| Says storage depends on upper-half rules not yet settled | 0.82 | 0.30 | 0.99 |
| Says saving turns shared data into full copies | 0.29 | 0.97 | 0.93 |
| Says reads are not logged | 0.95 | 0.07 | 0.05 |
| Names how functions reach data not in memory as open | 0.98 | 0.38 | 0.94 |
| Says the limits on each call are fixed by neither order | 0.19 | 0.97 | 0.15 |
| Doubts that agents write correct read programs | 0.11 | 0.98 | 0.22 |
| Advises against building the database | 0.04 | 0.05 | 0.05 |
| Argues from being usable sooner | 0.09 | 0.12 | 0.12 |

- 21 statements were asked of each review, 63 answers in all. Claude predicted yes or no for 54 and marked 9 as unsure. Of the 54, 50 came back as predicted, 2 came back between 0.3 and 0.7, and 2 came back the other way. One of those two is the unsettled point below. The other was a question of Claude's that mixed two things.
- Asked what each review builds first, Jev chose as Claude predicted for all three, at 1.00, 1.00 and 0.88.

**Whether the cited code supports each claim.** 18 claims, each sent with the lines the reviewer cited. A verdict counted as settled when it was the same with the options in either order and at 0.8 or above.

- 15 settled, all as Claude had found by reading. 14 were "supports". One was "contradicts": the claim about a service with no store.
- 3 were left for a person, and Claude checked each by hand. "Only a call that updated the state is persisted" holds: `persist` has one caller, and it runs only when the state changed. The wrong line number is wrong. The claim that the cited lines copy a whole table holds.

**What it could not settle.** Whether Gemini Carbon's design needs a change to Mo's runtime. Jev read that review as saying a change to saving is needed (0.92). Claude reads its explicit identifiers as a design written in Mo that needs none, and narrower questions confirmed the two parts of that reading: explicit identifiers (0.98) and written in the language (0.80). The review does not say which it means. This is the point on which the reviewers differ, and a sketch settles it where reading cannot.

**Settled since by a sketch.** [Can a Mo library keep old versions cheaply today?](37-can-a-mo-library-keep-old-versions-cheaply-today.md) built the design with explicit identifiers in Mo as it stands. It needs no change to Mo's runtime: a kept version costs 778 bytes when saved, at any size measured, and survives a restart. A write still costs in proportion to all of the state.

**Limits of this evaluation.** Jev measured what each review says, and whether an excerpt supports a claim. It did not judge which order is right. One of Claude's questions mixed two things and was split in a second pass: GPT Sol says a later rewrite of the write functions can be avoided (0.87), and Claude Opus says it would be cheap (0.95).

## Answer

Resolved by Robert on 2026-11-14: neither half first. "Yes to vertical slices." The database is explored as vertical slices, small experiments that each carry one job the whole way down, with part of the upper half and part of the storage built together. The order of the halves is no longer a question.

Three things led there.

- The council: none of the three reviewers chose either half outright, and each asked for an experiment first.
- The sketch, [Can a Mo library keep old versions cheaply today?](37-can-a-mo-library-keep-old-versions-cheaply-today.md): worlds, history and kept versions do not wait for the storage half, so the strongest reason to build storage first is gone. What storage must fix is that every write costs in proportion to all of the state.
- Robert's own idea while the sketch was being built: "Instead of developing out the whole front half and then the storage."

Which slices, and in what order, is [Which vertical slices, in what order, and what must each show?](38-which-vertical-slices-in-what-order.md).
