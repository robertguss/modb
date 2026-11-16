------------------------------- MODULE Sweep -------------------------------
EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS Order, Sweep, Names, Keep, MaxWrites, MaxCrashes

VARIABLES next, kids, leaves, made, disk, root, snap, log, held, ever,
          w, writes, s, broken, freed, crashes

vars == <<next, kids, leaves, made, disk, root, snap, log, held, ever,
          w, writes, s, broken, freed, crashes>>

All == 1..(2 * MaxWrites)
Idle == [pc |-> "idle", new |-> 0, leaf |-> 0]
Resting == [pc |-> "idle", marks |-> {}, seen |-> {}]

Kids(r) == IF r = 0 THEN {} ELSE kids[r]
Reach(r) == IF r = 0 THEN {} ELSE {r} \cup kids[r]
ReachAll(rs) == UNION {Reach(r) : r \in rs}
Roots == {root} \cup held \cup (IF Keep = "snap" THEN {snap} ELSE {})
InFlight == IF w.pc = "idle" THEN {} ELSE {w.new, w.leaf}

Init ==
    /\ next = 1 /\ kids = [n \in All |-> {}] /\ leaves = {} /\ made = {}
    /\ disk = {} /\ root = 0 /\ snap = 0 /\ log = <<>> /\ held = {} /\ ever = {}
    /\ w = Idle /\ writes = 0 /\ s = Resting
    /\ broken = FALSE /\ freed = FALSE /\ crashes = 0

WriteNodes ==
    /\ w.pc = "idle" /\ writes < MaxWrites
    /\ \E leaf \in (IF Names = "hash" THEN leaves ELSE {}) \cup {next} :
       \E gone \in SUBSET Kids(root) :
          /\ Cardinality(gone) <= 1
          /\ LET after == IF leaf = next THEN next + 1 ELSE next
                 content == (Kids(root) \ gone) \cup {leaf}
                 same == {r \in made : kids[r] = content}
                 new == IF Names = "hash" /\ same # {} THEN CHOOSE r \in same : TRUE ELSE after
             IN /\ next' = IF new = after THEN after + 1 ELSE after
                /\ kids' = [kids EXCEPT ![new] = content]
                /\ leaves' = leaves \cup {leaf}
                /\ made' = made \cup {new}
                /\ disk' = disk \cup {leaf, new}
                /\ w' = [pc |-> "nodes", new |-> new, leaf |-> leaf]
                /\ s' = IF s.pc = "marked" /\ Sweep = "pin"
                        THEN [s EXCEPT !.marks = @ \cup {leaf, new}] ELSE s
    /\ writes' = writes + 1
    /\ UNCHANGED <<root, snap, log, held, ever, broken, freed, crashes>>

LogIt == /\ log' = Append(log, [root |-> w.new, leaf |-> w.leaf])
         /\ ever' = ever \cup {w.new}
         /\ root' = root

SwitchIt == root' = w.new /\ UNCHANGED <<log, ever>>

First ==
    /\ w.pc = "nodes"
    /\ IF Order = "log" THEN LogIt ELSE SwitchIt
    /\ w' = [w EXCEPT !.pc = "mid"]
    /\ UNCHANGED <<next, kids, leaves, made, disk, snap, held, writes, s, broken, freed, crashes>>

Second ==
    /\ w.pc = "mid"
    /\ IF Order = "log" THEN SwitchIt ELSE LogIt
    /\ w' = Idle
    /\ UNCHANGED <<next, kids, leaves, made, disk, snap, held, writes, s, broken, freed, crashes>>

Hold ==
    /\ root # 0 /\ root \notin held
    /\ held' = held \cup {root}
    /\ UNCHANGED <<next, kids, leaves, made, disk, root, snap, log, ever, w, writes, s, broken, freed, crashes>>

Drop ==
    /\ \E r \in held : held' = held \ {r}
    /\ UNCHANGED <<next, kids, leaves, made, disk, root, snap, log, ever, w, writes, s, broken, freed, crashes>>

Snap ==
    /\ w.pc = "idle" /\ (snap # root \/ log # <<>>)
    /\ snap' = root /\ log' = <<>>
    /\ UNCHANGED <<next, kids, leaves, made, disk, root, held, ever, w, writes, s, broken, freed, crashes>>

SweepWhole ==
    /\ Sweep = "excl" /\ w.pc = "idle"
    /\ disk' = disk \cap ReachAll(Roots)
    /\ disk' # disk
    /\ freed' = TRUE
    /\ UNCHANGED <<next, kids, leaves, made, root, snap, log, held, ever, w, writes, s, broken, crashes>>

Mark ==
    /\ Sweep # "excl" /\ s.pc = "idle"
    /\ s' = [pc |-> "marked", seen |-> disk,
             marks |-> ReachAll(Roots) \cup (IF Sweep = "ignore" THEN {} ELSE InFlight)]
    /\ UNCHANGED <<next, kids, leaves, made, disk, root, snap, log, held, ever, w, writes, broken, freed, crashes>>

Free ==
    /\ s.pc = "marked"
    /\ LET victims == ((IF Sweep = "born" THEN s.seen ELSE disk) \ s.marks) \cap disk
       IN /\ disk' = disk \ victims
          /\ freed' = (freed \/ victims # {})
    /\ s' = Resting
    /\ UNCHANGED <<next, kids, leaves, made, root, snap, log, held, ever, w, writes, broken, crashes>>

RECURSIVE Replay(_, _, _)
Replay(d, base, i) ==
    IF i > Len(log) THEN [disk |-> d, ok |-> TRUE]
    ELSE LET rest == Replay(d \cup {log[i].root, log[i].leaf}, log[i].root, i + 1)
         IN [disk |-> rest.disk, ok |-> rest.ok /\ (base = 0 \/ base \in d)]

Crash ==
    /\ crashes < MaxCrashes
    /\ LET again == Replay(disk, snap, 1)
       IN /\ disk' = again.disk
          /\ broken' = (broken \/ ~again.ok)
    /\ root' = IF log = <<>> THEN snap ELSE log[Len(log)].root
    /\ w' = Idle /\ s' = Resting /\ crashes' = crashes + 1
    /\ UNCHANGED <<next, kids, leaves, made, snap, log, held, ever, writes, freed>>

Next == WriteNodes \/ First \/ Second \/ Hold \/ Drop \/ Snap \/ SweepWhole \/ Mark \/ Free \/ Crash

Spec == Init /\ [][Next]_vars

Safe == ReachAll({root} \cup held) \subseteq disk
Logged == w.pc = "idle" => held \subseteq ever
Recovers == ~broken
NothingFreed == ~freed
=============================================================================
