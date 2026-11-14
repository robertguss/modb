# What is Bend2, and what would proved laws mean for promises?

Type: research
Status: resolved

## Question

Bend2 (https://bend2.dev/notes/what-is-bend2/) is a language in which a program states laws and proves them in the same language. Try it hands-on, report what it is, how mature it is and what its limits are. Mo checks its promises with generated inputs. Say what proving a promise would add, what it would cost, and which other languages keep proved properties beside the code.

## Answer

Bend2 is not a tool for checking this design: it proves laws about functions and does not model steps that interleave, crashes or disks. It launched on 2026-09-17, installs and works, and its proofs came to three to six times the size of the code. Tests and proofs caught different errors: Mo's generated tests found a counterexample the researcher had missed, and passed a wrong function that the proof refused. Worth borrowing for Mo's promises: a law a person writes and freezes, with a proof an agent writes. Findings: [research/27-what-is-bend2-and-what-would-proved-laws-mean-for-promises.md](../research/27-what-is-bend2-and-what-would-proved-laws-mean-for-promises.md).
