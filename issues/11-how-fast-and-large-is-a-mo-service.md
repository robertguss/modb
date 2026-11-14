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

Measured on 2026-11-14. The counts of bytes and rows repeated exactly in two runs. The times did not: another session was building on the same machine (load average 5 to 21 on 8 processors), so the times in this first part were taken under load. The part added at the end has a quiet run, which came out close to these, a yardstick and a breakdown of where the time goes.

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

**Why a write grows with the state.** Read in the code here; measured apart in the part added at the end. Each log record carries "the FNV-1a checksum of the saved state the message produced" (`src/base/log-record.h`), so every write encodes the whole new state. Mo's Phase 4 notes found the same: "Each update at a large state takes about 0.15 s, most of it the saved copy the runtime makes of every new state" (`learnability/phase4/preflight/README.md`).

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

**Not measured.** States of other shapes, such as large values or nested records. The rate limit itself. What a larger message costs.

## Added later on 2026-11-14: a quiet run, a yardstick and a breakdown

Robert asked for these after reading the answer above. The numbers above stay as they were taken.

**A quiet run.** The same three scripts, with the load average falling from 2.9 to 1.1 on 8 processors. The fastest and the median of 40 reads and 210 writes at each size, in ms.

| Rows | Read: fastest, median | Write: fastest, median |
| --- | --- | --- |
| 1 | 4.9, 11.4 | 8.3, 16.6 |
| 1,001 | 5.3, 12.5 | 8.6, 17.2 |
| 10,000 | 5.0, 8.2 | 15.0, 29.3 |
| 50,000 | 4.9, 11.4 | 39.9, 47.7 |
| 100,000 | 5.3, 11.7 | 72.5, 82.2 |

- The medians are close to the first run's. The load did not change the picture.
- By the medians a write takes about 17 ms plus 0.66 ms for every 1,000 rows. By the fastest calls it takes about 8 ms plus 0.64 ms.
- A read takes 5 ms at its fastest and 8 to 12 ms at the median, at every size. Why the median is twice the fastest was not found.
- The ceiling repeated to the byte: 125,000 rows, 9,488,082 bytes encoded, a peak of 58,455,547 bytes, and adding 5,000 rows refused three times. At 100,000 rows the median write took 80 ms and the two writes that carried a snapshot took 121 and 105 ms.
- Restart took 9.0 s at 100,000 rows and 5.3 s at 125,000 rows, against 0.5 s empty. Still not broken down.
- At 125,000 rows a read alone took 9.6 ms. Beside writes running back to back it took 91 ms, the same as the write (93 ms).

**A yardstick: SQLite by itself.** [yardstick.py](../sketches/service-timing/yardstick.py) does the same job without Mo: a table of numbered rows of 64 bytes, in SQLite 3.53.1 inside one Python process. It uses the settings Mo's store uses (`journal_mode=DELETE`, `synchronous=EXTRA`, `locking_mode=EXCLUSIVE`, `cache_size=-256`; `src/host/store.c` in `~/code/mo`). A write changes one row and commits, so it is synced to disk. Load average 2. Times in ms.

| Rows | Read, median | Write: fastest, median | File |
| --- | --- | --- | --- |
| 1 | 0.001 | 1.3, 2.9 | under 0.1 MiB |
| 1,000 | 0.003 | 1.4, 3.1 | 0.1 MiB |
| 10,000 | 0.003 | 1.3, 2.6 | 0.7 MiB |
| 50,000 | 0.003 | 0.9, 2.7 | 3.5 MiB |
| 100,000 | 0.007 | 2.1, 3.9 | 7.1 MiB |
| 1,000,000 | 0.005 | 1.5, 4.2 | 71.2 MiB |
| 10,000,000 | 0.004 | 1.4, 3.1 | 722.6 MiB |

- A synced write takes about 3 ms and a read a few thousandths of a millisecond, from one row to ten million.
- This is a floor, not a like-for-like figure. There is no HTTP request, no token check and no handler around it.
- What it shows: the disk on this machine takes a synced write in about 3 ms, and a store that writes only what changed does not slow down as the data grows.
- A first run of the script timed a write of 0.002 ms at one row. It set the row to the value it already had, and SQLite wrote nothing. The script now writes a different value each time, and the table is from that run.

**Where the time goes.** [breakdown.py](../sketches/service-timing/breakdown.py) reads the server's processor time from `/proc` over 200 calls of each kind. Load average 1.2 to 2.5.

| Call | Time at the client, median | Server's processor time for one call |
| --- | --- | --- |
| Read, 1,000 rows | 12.3 ms | 10.5 ms |
| Read, 100,000 rows | 11.5 ms | 9.6 ms |
| Operator tool `mo-memory`, 100,000 rows | 15.2 ms | 12.6 ms |
| Write, 1,000 rows | 19.5 ms | 12.3 ms |
| Write, 100,000 rows | 85.0 ms | 83.7 ms |

The script then stops the service with `gdb` while calls run, and counts the share of busy samples each function is in. `perf` has no build for this machine's kernel. A share counts a function and everything it calls, so shares overlap. With this few samples a share is good to a few points for writes and to about fifteen points for reads.

*The fixed 10 ms of every call is the layer that reads the HTTP request.*

- Reads ran at the usual pace, 60 ms apart: 1,225 calls, none refused, 300 samples, 43 of them busy.
- 42 of the 43 were inside the VM (`mo_vm_execute`). 88% were under `mo_protocol_read`, which reads the request, and 9% under `mo_protocol_complete`.
- Handling the head of the request (`head_complete`) was in 72%: checking who is calling (`authenticate`) in 47% and deciding what the request is (`plan`) in 26%.
- That layer is Mo bytecode that the VM runs under a work budget. `authenticate` calls `mo_protocol_invoke(s, c, PF_INSPECT, args, &value)` (`src/tools/protocol-request.c`).
- The step that runs the handler (`mo_service_step`) is not among the 45 functions listed, so it was in one sample at most.
- A trace of the system calls of one read agrees: the request arrives, 5.9 ms pass with no system call, and the reply is sent.
- So a read does not touch the disk and does not depend on the size of the state. It costs what reading and checking one HTTP request costs in interpreted Mo.
- An earlier sampling fired reads with no gap. The service refuses calls past 20 a second, so most of those were refusals, and that sampling is not used here.

*The extra 7 ms of a small write is mostly time off the processor.*

- At 1,000 rows a write used 12.3 ms of processor against 10.5 ms for a read, and took 19.5 ms against 12.3 ms.
- One traced write made five `fsync` calls and 15 `pwrite64` calls.
- That the time off the processor is the disk is inferred from these; the calls were not timed apart on a quiet run.
- SQLite by itself, with the same settings, needs about 3 ms for a synced write on this disk.

*The part that grows is processor work on the whole state.* At 100,000 rows a write used 83.7 ms of processor. Writes ran back to back, which stays under the limit: 425 calls, none refused, 140 samples, 136 of them busy.

| Share of busy samples | Where |
| --- | --- |
| 59% | `encoded_copy` (`src/vm/service.c`): the new state is encoded, then decoded back into a fresh copy. The decode alone is 52%: putting every row back into the map (`mo_table_set`, 32%) and checking that every text is valid UTF-8 (`mo_value_text`, 20%). |
| 10% | `mo_protocol_read`: reading the HTTP request, as for a read. |
| 10% | `mo_value_drop`: freeing the old copy. |
| 10% | `copy_table`: copying a map. |
| 9% | `mo_binary_checksum`: the checksum over the whole saved state. |
| 9% | `fsync`: syncing to disk. |

- Mo's Phase 4 notes say why the copy is made: "the runtime passes each new state through a saved copy and refuses one it cannot save" (`learnability/phase4/preflight/README.md` in `~/code/mo`).
- The read samples and the write samples come from two runs of the script. The first run spaced the writes 60 ms apart and caught only 17 busy samples, so the script now runs them back to back.

**What this changes.**

- The first answer stands. A quiet machine gives nearly the same numbers.
- There are three costs, and they belong to different things.
  1. About 10 ms of processor on every call, read or write, for the HTTP layer of `mo serve`. It does not depend on the data. At 10 ms a call that is about 100 calls a second for each processor, and the rate limit of 20 a second comes first.
  2. About 7 ms on every write, mostly waiting for the disk. Any store that syncs each write pays some of this. SQLite by itself pays about 3 ms.
  3. About 0.65 ms for every 1,000 rows on every write, for copying and checksumming the whole state. SQLite's flat line shows that a store which syncs each write need not pay this.
- Only the third is about how the database stores data. The first is a property of Mo's services whatever they hold.
- A request program that does many reads in one request pays the first cost once, not once for each read. This is an inference and was not measured.

**Not measured.** The lookup inside Mo apart from the request around it. More than one client at a time. Why Mo's wait on a write is 7 ms where SQLite's whole write is 3 ms. Restart, broken down. Why the median call takes twice the fastest.
