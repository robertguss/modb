# Is Veil a good home for the protocol models?

Type: research
Status: resolved

## Question

Veil (https://veil.dev/) is a framework inside Lean 4 for specifying, model checking and proving protocols. Mo already uses Lean 4 for its model of Mo Core and TLA+ with TLC for three protocol models. Try Veil hands-on: install it, run an example, write and check a small two-agent "read, decide, write, check the reads again at landing" protocol, and compare the experience with TLA+. Report what it needs (Lean version against Mo's pinned one, solvers, build time), what it can do that TLC cannot, how mature it is, and whether to use it now, later or never.

## Answer

Later, not now. Veil built first time and checked the small protocol correctly; it found the lost update with the same trace as TLC, and in about fifteen minutes it gave a proof that no update is lost for any number of agents, which TLC cannot give. It needs Lean 4.35 where Mo pins 4.34, brings eleven packages and a solver, is young and mostly the work of one lab, and one of its search modes failed on the model. Keep TLA+ and TLC; look again when a claim must hold for any number of agents. Findings: [research/26-is-veil-a-good-home-for-the-protocol-models.md](../research/26-is-veil-a-good-home-for-the-protocol-models.md).
