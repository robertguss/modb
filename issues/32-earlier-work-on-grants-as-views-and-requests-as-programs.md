# What earlier work stands behind grants as views and requests as programs?

Type: research
Status: resolved

## Question

design-ideas.md proposes that a request is a program in the host language with no query language, that a grant is a view function, and that a narrower grant needs no approval. Find the strongest earlier work on each: languages with built-in persistence, queries written in the host language, views used as access control, narrowed capabilities, and proofs that a program sees only what its view allows. Say what killed the attempts that died.

## Answer

"The request is a program" is an old idea in a new combination. Earlier attempts lost because their data was closed to other tools, unplanned questions were slow, they ran out of money or programmers, and running foreign code safely was hard; none lost because a program is a worse request than a query. A grant as a view function is sound at its core, and SpacetimeDB ships read permissions as view functions. It leaks through errors, timing and evaluation order inside the view, through allowed totals that combine into facts about one person, and through termination and work limits. PINQ's proof for every caller's program was later broken through timing and shared state, so the theorem should say that equal views give the same reply, the same error and the same amount of work. Findings: [research/32-earlier-work-on-grants-as-views-and-requests-as-programs.md](../research/32-earlier-work-on-grants-as-views-and-requests-as-programs.md).
