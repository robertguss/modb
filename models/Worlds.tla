------------------------------- MODULE Worlds -------------------------------
\* A world that holds more than one call: what lands together, and when the rule is checked.
\* Predictions were written first, in worlds-predictions.md.
EXTENDS Integers, Sequences, TLC

CONSTANTS Case,      \* which of the six cases to run
          Unit,      \* "call": each call lands by itself. "world": the whole world lands or none of it
          Check,     \* "each": the rule is checked after every call. "end": after the world's last call
          UseR,      \* the recorded reads: "off", "main" or "inplace"
          MaxTries   \* how often an agent may fork

VARIABLES main,      \* the main line: three numbers, x, y and z
          w          \* each agent's world

vars == <<main, w>>

Agents == {"A", "B"}

Set(k, v) == [op |-> "set", k |-> k, v |-> v]
Add(k, v) == [op |-> "add", k |-> k, v |-> v]
Close == [op |-> "close", k |-> "y", v |-> 0]

\* transfer, audit and stuck: x and y are two accounts.  budget: x is spent, y is the budget.
Start ==
    CASE Case \in {"transfer", "audit", "stuck"} -> ([x |-> 2, y |-> 0, z |-> 0])
      [] Case = "budget" -> ([x |-> 1, y |-> 2, z |-> 0])
      [] OTHER -> ([x |-> 0, y |-> 0, z |-> 0])

Steps(a) ==
    IF a = "A" THEN 2 ELSE IF Case \in {"transfer", "budget"} THEN 0 ELSE 1

\* What step k of agent a reads before it decides.
Reads(a, k) ==
    CASE Case = "audit" /\ a = "B" -> ({"x", "y"})
      [] Case = "ownread" /\ a = "A" /\ k = 2 -> ({"x"})
      [] OTHER -> ({})

Answers(s, a, k) == [key \in Reads(a, k) |-> s[key]]

\* The call step k of agent a makes. The same answers give the same call.
Decide(a, k, ans) ==
    CASE Case = "budget" ->
            (IF k = 1 THEN Add("x", 2) ELSE Close)
      [] Case \in {"transfer", "audit"} /\ a = "A" ->
            (IF k = 1 THEN Add("x", -1) ELSE Add("y", 1))
      [] Case = "audit" /\ a = "B" ->
            (Set("z", ans["x"] + ans["y"]))
      [] Case = "stuck" ->
            (IF a = "B" THEN Add("y", 1) ELSE IF k = 1 THEN Add("x", -2) ELSE Add("y", 2))
      [] Case = "ownread" ->
            (IF a = "B" THEN Set("x", 5) ELSE IF k = 1 THEN Add("x", 1) ELSE Set("y", ans["x"]))
      [] OTHER ->
            (IF a = "A" /\ k = 2 THEN Add("y", 1) ELSE Add("x", 1))

Apply(s, c) ==
    CASE c.op = "set" -> ([s EXCEPT ![c.k] = c.v])
      [] c.op = "add" -> ([s EXCEPT ![c.k] = @ + c.v])
      [] OTHER -> ([s EXCEPT !.y = s.x])

\* The write function's own check: no number goes below nothing, and in stuck y holds 2 at most.
FOk(s, c) ==
    /\ c.op = "add" => s[c.k] + c.v >= 0
    /\ (Case = "stuck" /\ c.op = "add" /\ c.k = "y") => s.y + c.v <= 2

Rule(s) ==
    CASE Case = "transfer" -> (s.x + s.y = 2)
      [] Case = "budget" -> (s.x <= s.y)
      [] OTHER -> (TRUE)

\* What the person who approved "spend" and "close" relies on: the budget is never raised.
Approved(s) == Case = "budget" => s.y <= 2

\* The steps agent a records from step k on, working in its own copy s.
RECURSIVE Plan(_, _, _)
Plan(a, k, s) ==
    IF k > Steps(a) THEN << >>
    ELSE LET ans == Answers(s, a, k)
             c == Decide(a, k, ans)
         IN  <<[ans |-> ans, call |-> c]>> \o Plan(a, k + 1, Apply(s, c))

\* Replay recorded steps on s, the first of them being step k. Gives the state reached and
\* whether every check passed. "inplace" runs each step's read again where the replay has got to.
RECURSIVE Replay(_, _, _, _, _)
Replay(a, k, plan, s, ok) ==
    IF plan = << >> THEN [s |-> s, ok |-> ok]
    ELSE LET step == Head(plan)
             t == Apply(s, step.call)
         IN  Replay(a, k + 1, Tail(plan), t,
                    /\ ok
                    /\ UseR = "inplace" => Answers(s, a, k) = step.ans
                    /\ FOk(s, step.call)
                    /\ Check = "each" => Rule(t))

Init ==
    /\ main = Start
    /\ w = [a \in Agents |-> [st |-> "idle", plan |-> << >>, next |-> 1, tries |-> 0]]

\* Fork a world and run the steps that have not landed yet.
Fork(a) ==
    /\ w[a].st = "idle"
    /\ w[a].tries < MaxTries
    /\ w' = [w EXCEPT ![a].st = "open", ![a].plan = Plan(a, w[a].next, main), ![a].tries = @ + 1]
    /\ UNCHANGED main

\* The world is the unit: every call lands, or none does.
LandWorld(a) ==
    /\ Unit = "world"
    /\ w[a].st = "open"
    /\ LET plan == w[a].plan
           r == Replay(a, 1, plan, main, TRUE)
           seen == UseR = "main" => \A i \in 1..Len(plan) : Answers(main, a, i) = plan[i].ans
       IN  IF seen /\ r.ok /\ Rule(r.s)
           THEN /\ main' = r.s
                /\ w' = [w EXCEPT ![a].st = "done"]
           ELSE /\ w' = [w EXCEPT ![a].st = "idle"]
                /\ UNCHANGED main

\* The call is the unit: the next call lands by itself. Calls that landed earlier stay landed.
LandCall(a) ==
    /\ Unit = "call"
    /\ w[a].st = "open"
    /\ IF w[a].plan = << >>
       THEN /\ w' = [w EXCEPT ![a].st = "done"]
            /\ UNCHANGED main
       ELSE LET step == Head(w[a].plan)
                t == Apply(main, step.call)
                last == Len(w[a].plan) = 1
            IN  IF /\ UseR = "off" \/ Answers(main, a, w[a].next) = step.ans
                   /\ FOk(main, step.call)
                   /\ (Check = "each" \/ last) => Rule(t)
                THEN /\ main' = t
                     /\ w' = [w EXCEPT ![a].plan = Tail(@), ![a].next = @ + 1,
                                       ![a].st = IF last THEN "done" ELSE "open"]
                ELSE /\ w' = [w EXCEPT ![a].st = "idle"]
                     /\ UNCHANGED main

Next == \E a \in Agents : Fork(a) \/ LandWorld(a) \/ LandCall(a)

Spec == Init /\ [][Next]_vars

\* Agent a's whole world landing on s with nothing in between: the state reached, or s if refused.
Whole(a, s) ==
    LET r == Replay(a, 1, Plan(a, 1, s), s, TRUE)
    IN  IF r.ok /\ Rule(r.s) THEN r.s ELSE s

Outcomes == {Start, Whole("A", Start), Whole("B", Start),
             Whole("B", Whole("A", Start)), Whole("A", Whole("B", Start))}

Quiet == \A a \in Agents : w[a].st = "done" \/ (w[a].st = "idle" /\ w[a].tries = MaxTries)

RuleHolds == Rule(main)
Serial == Quiet => main \in Outcomes
ApprovedOnly == Approved(main)

\* Meant to be violated: a violation shows that both agents can finish.
NotAllDone == \E a \in Agents : w[a].st # "done"
=============================================================================
