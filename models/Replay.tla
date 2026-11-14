------------------------------- MODULE Replay -------------------------------
\* The replay rule from design-ideas.md, "Many agents working together".
\* Predictions were written first, in replay-predictions.md.
EXTENDS Integers, TLC

CONSTANTS Case,      \* which of the six cases to run
          UseF,      \* the write function's own check runs at replay
          UseP,      \* the promises are checked on the result
          UseR,      \* the agent's reads are run again at landing
          MaxTries   \* how often an agent may fork

VARIABLES main,      \* the main line: two numbers, x and y
          w,         \* each agent's world
          serialOk,  \* history: every landed call was the call its agent would choose now
          needless   \* history: R sent back a world whose agent would choose the same call

vars == <<main, w, serialOk, needless>>

Agents == {"A", "B"}

None == [op |-> "none", k |-> "x", v |-> 0]
Set(k, v) == [op |-> "set", k |-> k, v |-> v]
Add(k, v) == [op |-> "add", k |-> k, v |-> v]

\* seat: x is seats booked, of one.       meeting: x is the start, y the end.
\* skew: x and y are two people on call.  discount: x is the price, y the discount.
\* lostupdate and intent: x is a balance.
Start ==
    CASE Case = "seat" -> ([x |-> 0, y |-> 0])
      [] Case = "meeting" -> ([x |-> 1, y |-> 4])
      [] Case = "skew" -> ([x |-> 1, y |-> 1])
      [] Case = "discount" -> ([x |-> 4, y |-> 0])
      [] OTHER -> ([x |-> 2, y |-> 0])

\* What each agent reads before it decides.
Reads(a) ==
    CASE Case \in {"meeting", "skew"} -> ({"x", "y"})
      [] Case = "discount" -> (IF a = "A" THEN {"x"} ELSE {})
      [] OTHER -> ({"x"})

Answers(s, a) == [k \in Reads(a) |-> s[k]]

\* The call an agent chooses from its answers. The same answers give the same call.
Decide(a, ans) ==
    CASE Case = "seat" ->
            (IF ans["x"] < 1 THEN Add("x", 1) ELSE None)
      [] Case = "meeting" ->
            (IF a = "A"
             THEN (IF 3 < ans["y"] THEN Set("x", 3) ELSE None)
             ELSE (IF ans["x"] < 2 THEN Set("y", 2) ELSE None))
      [] Case = "skew" ->
            (IF a = "A"
             THEN (IF ans["y"] = 1 THEN Set("x", 0) ELSE None)
             ELSE (IF ans["x"] = 1 THEN Set("y", 0) ELSE None))
      [] Case = "discount" ->
            (IF a = "A" THEN Set("y", ans["x"] \div 2) ELSE Set("x", 2))
      [] Case = "lostupdate" ->
            (Set("x", ans["x"] + (IF a = "A" THEN 2 ELSE 1)))
      [] OTHER ->
            (Add("x", IF a = "A" THEN 2 ELSE 1))

Apply(s, c) ==
    CASE c.op = "set" -> ([s EXCEPT ![c.k] = c.v])
      [] c.op = "add" -> ([s EXCEPT ![c.k] = s[c.k] + c.v])
      [] OTHER -> (s)

\* F: the write function's own check, on the state it is replayed on.
FOk(s, c) ==
    CASE Case = "seat" -> (s["x"] < 1)
      [] Case = "meeting" -> (IF c.k = "x" THEN c.v < s["y"] ELSE s["x"] < c.v)
      [] Case = "skew" -> (IF c.k = "x" THEN s["y"] = 1 ELSE s["x"] = 1)
      [] OTHER -> (TRUE)

\* The case's own rule. P checks it on the result of a call.
Rule(s) ==
    CASE Case = "seat" -> (s["x"] <= 1)
      [] Case = "meeting" -> (s["x"] < s["y"])
      [] Case = "skew" -> (s["x"] + s["y"] >= 1)
      [] OTHER -> (TRUE)

Init ==
    /\ main = Start
    /\ w = [a \in Agents |-> [st |-> "idle", ans |-> << >>, call |-> None, tries |-> 0]]
    /\ serialOk = TRUE
    /\ needless = FALSE

\* Fork a world: read, record the answers, decide one call.
Fork(a) ==
    /\ w[a].st = "idle"
    /\ w[a].tries < MaxTries
    /\ LET ans == Answers(main, a)
       IN  w' = [w EXCEPT ![a] = [st |-> "open", ans |-> ans,
                                  call |-> Decide(a, ans), tries |-> @.tries + 1]]
    /\ UNCHANGED <<main, serialOk, needless>>

\* Land a world: replay its call on the main line as it now is.
\* A world with no call only read, so it finishes and counts as having run when it forked.
Land(a) ==
    /\ w[a].st = "open"
    /\ LET c == w[a].call
           now == Decide(a, Answers(main, a))
           stale == Answers(main, a) # w[a].ans
       IN  IF c.op = "none"
           THEN /\ w' = [w EXCEPT ![a].st = "done"]
                /\ UNCHANGED <<main, serialOk, needless>>
           ELSE IF UseR /\ stale
           THEN /\ w' = [w EXCEPT ![a].st = "idle"]
                /\ needless' = (needless \/ now = c)
                /\ UNCHANGED <<main, serialOk>>
           ELSE IF (UseF /\ ~FOk(main, c)) \/ (UseP /\ ~Rule(Apply(main, c)))
           THEN /\ w' = [w EXCEPT ![a].st = "idle"]
                /\ UNCHANGED <<main, serialOk, needless>>
           ELSE /\ main' = Apply(main, c)
                /\ serialOk' = (serialOk /\ now = c)
                /\ w' = [w EXCEPT ![a].st = "done"]
                /\ UNCHANGED needless

Next == \E a \in Agents : Fork(a) \/ Land(a)

Spec == Init /\ [][Next]_vars

Serial == serialOk
RuleHolds == Rule(main)
NoNeedlessSendBack == ~needless

\* These two are meant to be violated. They show that both agents can finish and that a call can land.
NotAllDone == \E a \in Agents : w[a].st # "done"
NothingLanded == main = Start
=============================================================================
