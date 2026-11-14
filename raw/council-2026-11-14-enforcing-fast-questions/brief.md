You are one of three independent reviewers from different providers. Work alone and read-only: do not edit, create or delete any file, do not commit, and do not start other agents. Reply with your review as plain text, at most 900 words.

THE PROJECT. A database for the Mo programming language, to be written in Mo or built into it. Mo is a pre-release language and runtime whose programs run as long-lived services, and most Mo code is written by AI agents. The project is at the planning stage and holds no database code. The base case is an ordinary Mo application that keeps data; many AI agents sharing that data is a layer on top.

THE IDEA UNDER REVIEW. The draft design has no query language. The idea is that plain Mo is the query language: the compiler recognises certain shapes of ordinary collection code (for example a filter whose test compares one field of the row with a value that does not depend on the row) and gives them a fast route through an index that the store keeps current. Code outside the recognised shapes reads every row. The owner has agreed to try this with no new query syntax.

THE QUESTION. How should the fast route be enforced, so that code is written in the shapes the compiler expects and a slow read never arrives unnoticed? And which small experiments would settle the choice with data instead of opinion?

OPTIONS ON THE TABLE, in no order. They can be combined, and you may add one we missed.
A. Strict. On a stored table, a filter the compiler cannot give a fast route is a compile error, unless the code says so in a word such as `walk`.
B. Warn. The same detection, as a warning only.
C. Demand. Nothing by default. A marker such as `fast` on a function makes the compiler refuse the function if it cannot give it a fast route. Mo already plans "demanding that a function update its input in place" for a later phase.
D. Measure. No static rule. `mo test` runs each read function on a generated store at two sizes and compares the exact count of VM instructions, which is the same on every run. A count that grows with the size of the store fails.
E. A closed form. Instead of recognising shapes in plain Mo, the table type offers a small fixed set of methods that take a field and a value, not a function, so every use is fast by construction.
F. The review door. Each read function gets a ranked cost class, and an upgrade that makes one slower is held for a person.

WHAT TO READ. The planning repository is at /home/exedev/Projects/modb, at commit 883df2c. Read design.md (sections 3, 5 and 8), the first idea and rows 4 and 5 of the rejection table in docs/ideation/2026-11-14-mo-database-ideation.html, the part of design-ideas.md headed "8. Unplanned questions", and sketches/README.md. Do not read anything under raw/ except this brief.
Mo is at /home/exedev/code/mo. Read it as you need: docs/reference/README.md is the language reference, lib/list.mo and lib/map.mo are the collection functions, learnability/ holds measurements of agents writing Mo, and src/ is the C implementation. Another session is editing that checkout, so cite function and file names, not line numbers, and never write to it.

WHAT IS ALREADY DECIDED. Nothing presupposes SQL or the relational model. The ordinary Mo application is the base case. A read program that an agent sends at run time only reads. Agents may propose and a person approves.

CONSTRAINTS ON AN EXPERIMENT. No database code exists and no change to Mo may be assumed. An experiment is therefore small: a Mo program under sketches/ that runs on Mo as it stands, a script in any language that stands in for a compiler pass (for example a recogniser over Mo source), a measurement of agents writing read functions, or a model. Each has its prediction written before it runs and a control that must fail. The owner is in no hurry and is not aiming at production, so "usable sooner" is not a reason to prefer anything.

WHAT TO DELIVER.
1. Your choice: which option or combination, for the program's own code, and separately for a read program an agent sends at run time. Say why.
2. The strongest argument against your choice.
3. At most five experiments, in the order you would run them. For each give: what is built or measured; the one result it must show, stated so that it could come out either way; your predicted result with a percentage; and anything it needs that Mo does not have today (name the function, limit or rule in Mo that stands in the way).
4. Which experiment you would run first and why, and which result would change your choice in 1.
5. What is missing: an option we did not list, or the flaw most likely to sink "plain Mo is the query language".
6. Your confidence in your choice in 1 as a percentage.
