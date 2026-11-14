

2026-11-14, reopened by Robert: with no hurry, and with the database's own storage engine now certain, he asked whether the Rust rewrite is back on the table. What that changes:

- The engine is written in Mo, so its own logic is memory safe on any runtime. What it adds to the runtime is the support under it: writing bytes, reading and writing at an offset, forcing data to disk, and a fake disk that injects faults for testing. Today Mo has only whole-file `read_text`, `read_bytes`, `write_text` and `append_text` (`~/code/mo/src/base/hostops.def`). That support is offset arithmetic over raw buffers, the kind of C where memory bugs live.
- Once the engine replaces SQLite, a Rust runtime leaves no C in the server's process. With SQLite kept, a Rust runtime still left 271,131 lines of C there.
- "Usable sooner" no longer counts against a port.

What it does not change: the port is about 38,600 lines of runtime C plus the serving parts of `src/tools`, with their unit tests, fuzz targets and CBMC proofs to rebuild; its speed and memory are unmeasured; and the middle of Phase 6 is the wrong moment.
