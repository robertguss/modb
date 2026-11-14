---- MODULE Replay_TTrace_1794631803 ----
EXTENDS Sequences, TLCExt, Replay, Toolbox, Naturals, TLC

_expression ==
    LET Replay_TEExpression == INSTANCE Replay_TEExpression
    IN Replay_TEExpression!expression
----

_trace ==
    LET Replay_TETrace == INSTANCE Replay_TETrace
    IN Replay_TETrace!trace
----

_inv ==
    ~(
        TLCGet("level") = Len(_TETrace)
        /\
        w = ([A |-> [ans |-> [x |-> 2], st |-> "done", call |-> [op |-> "set", k |-> "x", v |-> 4], tries |-> 1], B |-> [ans |-> [x |-> 2], st |-> "done", call |-> [op |-> "set", k |-> "x", v |-> 3], tries |-> 1]])
        /\
        serialOk = (FALSE)
        /\
        main = ([x |-> 3, y |-> 0])
        /\
        needless = (FALSE)
    )
----

_init ==
    /\ needless = _TETrace[1].needless
    /\ serialOk = _TETrace[1].serialOk
    /\ w = _TETrace[1].w
    /\ main = _TETrace[1].main
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ needless  = _TETrace[i].needless
        /\ needless' = _TETrace[j].needless
        /\ serialOk  = _TETrace[i].serialOk
        /\ serialOk' = _TETrace[j].serialOk
        /\ w  = _TETrace[i].w
        /\ w' = _TETrace[j].w
        /\ main  = _TETrace[i].main
        /\ main' = _TETrace[j].main

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("Replay_TTrace_1794631803.json", _TETrace)

=============================================================================

 Note that you can extract this module `Replay_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `Replay_TEExpression.tla` file takes precedence 
  over the module `Replay_TEExpression` below).

---- MODULE Replay_TEExpression ----
EXTENDS Sequences, TLCExt, Replay, Toolbox, Naturals, TLC

expression == 
    [
        \* To hide variables of the `Replay` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        needless |-> needless
        ,serialOk |-> serialOk
        ,w |-> w
        ,main |-> main
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_needlessUnchanged |-> needless = needless'
        
        \* Format the `needless` variable as Json value.
        \* ,_needlessJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(needless)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_needlessModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].needless # _TETrace[s-1].needless
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE Replay_TETrace ----
\*EXTENDS IOUtils, Replay, TLC
\*
\*trace == IODeserialize("Replay_TTrace_1794631803.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE Replay_TETrace ----
EXTENDS Replay, TLC

trace == 
    <<
    ([w |-> [A |-> [ans |-> <<>>, st |-> "idle", call |-> [op |-> "none", k |-> "x", v |-> 0], tries |-> 0], B |-> [ans |-> <<>>, st |-> "idle", call |-> [op |-> "none", k |-> "x", v |-> 0], tries |-> 0]],serialOk |-> TRUE,main |-> [x |-> 2, y |-> 0],needless |-> FALSE]),
    ([w |-> [A |-> [ans |-> [x |-> 2], st |-> "open", call |-> [op |-> "set", k |-> "x", v |-> 4], tries |-> 1], B |-> [ans |-> <<>>, st |-> "idle", call |-> [op |-> "none", k |-> "x", v |-> 0], tries |-> 0]],serialOk |-> TRUE,main |-> [x |-> 2, y |-> 0],needless |-> FALSE]),
    ([w |-> [A |-> [ans |-> [x |-> 2], st |-> "open", call |-> [op |-> "set", k |-> "x", v |-> 4], tries |-> 1], B |-> [ans |-> [x |-> 2], st |-> "open", call |-> [op |-> "set", k |-> "x", v |-> 3], tries |-> 1]],serialOk |-> TRUE,main |-> [x |-> 2, y |-> 0],needless |-> FALSE]),
    ([w |-> [A |-> [ans |-> [x |-> 2], st |-> "done", call |-> [op |-> "set", k |-> "x", v |-> 4], tries |-> 1], B |-> [ans |-> [x |-> 2], st |-> "open", call |-> [op |-> "set", k |-> "x", v |-> 3], tries |-> 1]],serialOk |-> TRUE,main |-> [x |-> 4, y |-> 0],needless |-> FALSE]),
    ([w |-> [A |-> [ans |-> [x |-> 2], st |-> "done", call |-> [op |-> "set", k |-> "x", v |-> 4], tries |-> 1], B |-> [ans |-> [x |-> 2], st |-> "done", call |-> [op |-> "set", k |-> "x", v |-> 3], tries |-> 1]],serialOk |-> FALSE,main |-> [x |-> 3, y |-> 0],needless |-> FALSE])
    >>
----


=============================================================================

---- CONFIG Replay_TTrace_1794631803 ----
CONSTANTS
    Case = "lostupdate"
    UseF = TRUE
    UseP = TRUE
    UseR = FALSE
    MaxTries = 2

INVARIANT
    _inv

CHECK_DEADLOCK
    \* CHECK_DEADLOCK off because of PROPERTY or INVARIANT above.
    FALSE

INIT
    _init

NEXT
    _next

CONSTANT
    _TETrace <- _trace

ALIAS
    _expression
=============================================================================
\* Generated on Sat Nov 14 04:50:03 UTC 2026