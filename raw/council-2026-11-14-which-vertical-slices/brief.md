You are one of three independent reviewers from different providers. Work alone and read-only: do not edit, create or delete any file, do not commit, and do not start other agents. Reply with your review as plain text, at most 900 words.

THE PROJECT. A database for many AI agents working on the same data, written in Mo, a pre-release language and runtime whose programs can run as long-lived services. The project is at the planning stage. Its owner has decided to explore it by VERTICAL SLICES: small experiments that each carry one job the whole way down (something an agent does, the rule that guards it, and the way its data is kept), instead of building the part agents touch first and the storage second, or the other way round.

THE QUESTION. Which vertical slices should be run, and in what order? What must each one show before the next? When are there enough of them to write the decision the planning map exists for?

WHAT TO READ. Read the planning repository ONLY from this snapshot folder, which is the repository at commit 28b9da6:
modb
Do not read any other copy of that repository, on disk or online: later notes there contain a proposal we do not want to steer you with. Start at map.md. Then read design-ideas.md (especially "The ideas", "Storage underneath", "Many agents working together", "Which half first" and "Deep dives for later"), issues/11-how-fast-and-large-is-a-mo-service.md, issues/35-what-lands-together-when-a-world-holds-more-than-one-call.md, issues/36-which-half-comes-first.md, issues/37-can-a-mo-library-keep-old-versions-cheaply-today.md, sketches/README.md and the code in sketches/kept-versions/.
Mo itself is at mo. Read it as you need (docs/reference/README.md is the language reference, docs/agent-guide.md says what the toolchain does today, src/ is the C implementation). Another session is editing that checkout, so cite function and file names, not line numbers, and never write to it.

WHAT IS ALREADY DECIDED. A request program only reads. Agents may propose and a person approves. The accountable write stays the centre: data changes only through approved write functions. A world, an agent's own version of the data, lands whole or not at all, with the rule checked after every call in it. At landing every question the agent asked counts, by its answer. Exploring by vertical slices is decided; do not argue for one half first.

CONSTRAINTS ON A SLICE. The planning map's destination is a decision, so no database code and no change to Mo is part of it. A slice is therefore a small experiment: a Mo program under sketches/, a model, or a measurement, with its predictions written before it runs and a control that must fail. A slice that would need a change to Mo can be measured or modelled, not built. The owner is in no hurry and is not aiming at production; "usable sooner" is not a reason to prefer anything. The purpose is learning and his own use, and others should be able to use the result. Nothing may presuppose SQL or the relational model.

WHAT TO DELIVER.
1. Your slate: at most five slices, in the order you would run them. For each give: what an agent does in it; the rule or check that guards it; how the data is kept; the one result it must show, stated so that it could come out either way; and whether it needs anything Mo does not have today (name the function, limit or rule in Mo that stands in the way).
2. Which slice you would run first, and why that one before the others.
3. A stop rule: how the owner knows there are enough slices to write the decision.
4. What you deliberately left out, and why.
5. The largest risk of exploring by slices, and how to guard against it.
6. Your confidence in your choice of first slice as a percentage, and what finding would change your mind.

RULES. Every factual claim about Mo or about the planning repository must name the file and function or section it rests on; say plainly where you did not verify something. Do not rely on memory of other databases for claims about this project. You need no web research; if you do any, keep queries generic and never include a person's name, a project or repository name, or the name of the language. Do not write exploit code or attack instructions.