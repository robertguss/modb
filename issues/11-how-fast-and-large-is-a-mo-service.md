# How fast and how large is a Mo service today?

Type: task
Status: resolved

## Question

AFK. Measure on the current build in `~/code/mo`:

- the time a service takes to handle one message, apart from the MCP rate limit;
- how that time grows with the size of the state (each snapshot encodes the whole state);
- the largest state a service holds before a limit stops it.

The answer records the numbers and how they were taken.

The decision that waits on it: "fast enough that an agent never waits" needs a number, and `research/09-agents-and-databases-today.md` reports that agents send high volumes of exploratory reads.

## Answer

Measured on 2026-11-14. The counts of bytes and rows repeated exactly in two runs. The times did not: another session was building on the same machine (load average 5 to 21 on 8 processors), so every time below is too high by an unknown amount. A quiet run is three commands ([sketches/README.md](../sketches/README.md)).

**How.** Mo at commit `ef37424`, `mo 0.2.0`, built with gcc 13.3.0 at `-O2` with assertions on, the way Mo's own benchmark builds it (`bench/performance/README.md` in `~/code/mo`). Only `-O0` builds existed before. The service ([main.mo](../sketches/service-timing/main.mo)) holds a `Map(Int, Text)`: numbered rows of 64 bytes of text. A Python client calls it over loopback through `mo serve`, one connection for each call, and times each call from its own side. A time therefore includes HTTP, the MCP layer, the handler and the write to SQLite. Calls were 60 ms apart to stay under the limit of 20 calls a second with a burst of 40 (`src/base/limits.h`; read, not measured). The machine is a virtual one with 8 processors (AMD EPYC 9554P), 32 GiB of memory and ext4 on a virtual disk.

**One message.** The median, then the 90th percentile and the largest in brackets, over 40 reads and 210 writes at each size. First run, load average about 5.

| Rows | Read, ms | Write, ms | Process memory | Store file |
| --- | --- | --- | --- | --- |
| 1 | 8.4 [16.2, 24.6] | 17.3 [23.0, 34.5] | 44 MiB | 0.08 MiB |
| 1,001 | 10.8 [14.5, 18.0] | 18.9 [25.2, 53.9] | 45 MiB | 0.2 MiB |
| 10,000 | 7.9 [13.3, 15.5] | 25.6 [33.8, 46.5] | 54 MiB | 0.85 MiB |
| 50,000 | 9.8 [14.4, 20.9] | 53.9 [81.9, 160.2] | 83 MiB | 4.4 MiB |
| 100,000 | 10.7 [16.7, 18.9] | 93.0 [140.8, 471.4] | 123 MiB | 10.9 MiB |

- A read takes about 8 to 11 ms whatever the size of the state.
- A write takes about 17 ms, plus 0.76 ms for every 1,000 rows. That is about 10 ms for every MiB of saved state.
- Under heavier load the write at 100,000 rows measured 85 ms (load 8) and 167 ms (load 20) in two later runs.

**Why a write grows with the state.** Read in the code, not measured apart. Each log record carries "the FNV-1a checksum of the saved state the message produced" (`src/base/log-record.h`), so every write encodes the whole new state. Mo's Phase 4 notes found the same: "Each update at a large state takes about 0.15 s, most of it the saved copy the runtime makes of every new state" (`learnability/phase4/preflight/README.md`).

**Snapshots.** One is taken every 100 messages (`MO_LIMIT_SERVICE_SNAPSHOT_MESSAGES`; the service reported `snapshot_sequence` 200 at `recovery_sequence` 215). At 100,000 rows the two writes that carried a snapshot took 122 and 118 ms, against a median of 85 ms for the rest. In the repeat they took 183 and 129 ms against 167.

**A read waits behind a write.** At 125,000 rows a read alone took 7 ms. With writes running back to back it took 160 ms, the same as the write. In the repeat: 10 ms alone, 189 ms beside writes.

**The largest state.** The same in both runs.

- At 100,000 rows the service reported 7,588,082 bytes of encoded state, 19.2 MB of heap in use and a peak of 51.3 MB. The limit for one call is 58,718,816 bytes: 64 MiB less the stack.
- At 125,000 rows it reported 9,488,082 bytes encoded (9.05 MiB) and a peak of 58,455,547 bytes. A write still worked. Adding 5,000 rows was refused three times with `memory_limit`: "the call ran out of memory; service state is unchanged".
- For small rows, then, the ceiling is the memory one call may use, reached at about 9 MiB of saved state. The 16 MiB limit on saved state is not what stops it. Each added row cost 76 bytes saved, 128 bytes of heap at rest and 287 bytes of heap at the peak of a write.
- In the first run a larger step took the state to 130,000 rows. After that every write was refused, including one that set a row to the value it already had. After 16 refusals the supervisor restarted the service. A service can be grown into a state it cannot write to.
- At 125,000 rows the process used 146 to 154 MiB and the store file was 14.6 MiB.

**Restart.** Empty: 0.5 s, and 0.9 s in the repeat. At 125,000 rows with 25 messages after the last snapshot: 9.1 s, and 4.3 s in the repeat. Not broken down.

**What it means for the decision.**

- "Fast enough that an agent never waits" holds for a state of a few thousand rows, where a write takes about 20 to 25 ms. At 100,000 rows a write takes about a tenth of a second, and every read behind it waits that long.
- One Mo service on Mo's saved state holds about 100,000 small rows, or about 9 MiB. [What real data of yours goes in first?](12-what-real-data-goes-in-first.md) decides whether that is enough for a first slice.
- The cost that grows is the whole state being encoded on every write. A store in which a change rewrites a path and not the whole, such as the tree of write-once nodes in `design-ideas.md`, removes it.
- A world of several calls that lands as one message pays this cost once, not once for each call. This is an inference from the numbers and was not measured.
- A database on this must cap its own size well below the ceiling, as the task queue does.

**Not measured.** A quiet machine. States of other shapes, such as large values or nested records. The time inside the handler apart from the rest. The rate limit itself. What a larger message costs.
