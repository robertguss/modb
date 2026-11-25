# Mo PR Contract: Random-Access Binary `Files` and `Bytes` Packing

**Target repo:** `~/code/mo` (implement in a clean worktree/branch off `origin/main`).
**Goal:** Add the minimal, general-purpose binary file I/O and fixed-width byte-packing primitives needed by any Mo program that reads/writes binary formats, caches, archives, logs, or embedded storage engines—with zero database-specific concepts.

---

## 1. New Capability Operations (`src/base/hostops.def`)

All operations reuse the existing `FileError` enum (`NotFound`, `NotAllowed`, `NotText`, `Failed`) and follow the existing handle-capability pattern used by `Sqlite.open -> Sqlite.Database` and `Network.connect -> Connection`.

### 1.1 Whole-File Operations on `Files`

```c
HOSTOP(FILES_WRITE_BYTES, "Files", "write_bytes",
       "fn(Files, Text, Bytes) : Result(Unit, FileError)", "bbb", "", false)
HOSTOP(FILES_RENAME,      "Files", "rename",
       "fn(Files, Text, Text) : Result(Unit, FileError)", "bbb", "", false)
HOSTOP(FILES_OPEN,        "Files", "open",
       "fn(Files, Text) : Result(Files.File, FileError)", "bb",
       "too many files open at once", false)
```

### 1.2 Open File Handle Capability (`Files.File`)

`Files.File` is a non-serializable capability handle (same rules as `Sqlite.Database` and `Connection`: cannot be stored in `service`/`actor` saved state; automatically closes its OS descriptor when its refcount drops to 0).

```c
HOSTOP(FILE_READ_AT,  "Files.File", "read_at",
       "fn(Files.File, Int, Int) : Result(Bytes, FileError)", "bbb",
       "negative file offset; read count outside 0 to the read limit", false)
HOSTOP(FILE_WRITE_AT, "Files.File", "write_at",
       "fn(Files.File, Int, Bytes) : Result(Unit, FileError)", "bbb",
       "negative file offset", false)
HOSTOP(FILE_SIZE,     "Files.File", "size",
       "fn(Files.File) : Result(Int, FileError)", "b", "", false)
HOSTOP(FILE_TRUNCATE, "Files.File", "truncate",
       "fn(Files.File, Int) : Result(Unit, FileError)", "bb",
       "negative file size", false)
HOSTOP(FILE_SYNC,     "Files.File", "sync",
       "fn(Files.File) : Result(Unit, FileError)", "b", "", false)
```

*(Note: verify during implementation whether qualified module name `"Files.File"` follows `"Sqlite.Database"` directly in `src/base/hostops.def` / `src/check/types.c`, or whether a top-level capability name like `File` matches `Connection` more cleanly—either works as long as `files.open(path)` returns a handle whose methods are callable as `file.read_at(...)`, `file.write_at(...)`, `file.size`, `file.truncate(...)`, `file.sync`.)*

### 1.3 Confinement, Limits, and OS Semantics

- **Limits (`src/base/limits.h` and `src/host/host.c`):**
  - `MO_LIMIT_OPEN_FILES 64` (accounted for in `rlim_t wanted` in `src/host/host.c`).
  - `MO_LIMIT_FILE_IO_BYTES (16 * 1024 * 1024)` — cap on a single `read_at` count (matches `MO_LIMIT_API_BODY_BYTES`).
- **Path confinement (same guarantees as existing `Files` ops):**
  - `write_bytes`, `rename`, and `open` resolve paths strictly inside the `Files` root descriptor using existing safe traversal (`openat` / `openat2` `RESOLVE_BENEATH`, `O_NOFOLLOW`, rejecting `..` escapes and symlinks with `NotAllowed`).
  - `rename` resolves *both* `from` and `to` strictly within the same `Files` root, calls `renameat`, and `fsync`s the destination parent directory.
  - `open` opens with `O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC` (mode `0644`); if newly created, `fsync`s the parent directory so the directory entry itself is durable.
  - `ReadFiles` does **not** gain `write_bytes`, `rename`, or writable `open`.
- **Short-I/O loops & EOF:**
  - `read_at`: loops `pread` on `EINTR` / short reads until `count` bytes are read or EOF (`0`). Returns fewer than `count` bytes at EOF, or empty `Bytes` if `offset >= size`. Rejects `offset < 0` or `count < 0` or `count > MO_LIMIT_FILE_IO_BYTES` as a bug.
  - `write_at`: loops `pwrite` on `EINTR` / short writes until all bytes of `data` are written. Extending past current EOF is valid (POSIX behavior). Rejects `offset < 0` as a bug.
  - `size`: wraps `fstat` and returns `st_size` as `Int`.
  - `truncate`: wraps `ftruncate` (retrying on `EINTR`). Rejects `size < 0` as a bug.
  - `sync`: calls `fcntl(fd, F_FULLFSYNC)` on macOS (falling back to `fsync` if unsupported) and `fsync(fd)` on Linux.
- **Close on drop:** `Files.File` closes its fd and decrements `host->open_files` when dropped by the heap; safe against double-close.

### 1.4 Fake Parity (`Files.in_memory`)

- Upgrade `Files.in_memory` backing storage to hold raw byte buffers (`uint8_t *` + `size_t`) instead of UTF-8 text only (initial `Map(Text, Text)` entries populate as their UTF-8 bytes; existing `read_text` still returns `NotText` on invalid UTF-8 bytes).
- `write_bytes` writes raw bytes; `rename` moves the entry atomically inside the in-memory map (returning `NotFound` if `from` is missing, `NotAllowed` on escape).
- `open` returns an in-memory `Files.File` handle pointing to the same shared in-memory store entry (creating an empty entry if absent), so `read_at`, `write_at`, `size`, `truncate` (zero-filling extensions, shrinking truncations), and `sync` (no-op returning `Ok(Unit)`) work identically under `mo test`—including re-opening the same path after dropping a handle.

---

## 2. New `Bytes` Primitives (`src/base/prims.def` & `src/prim/`)

Mo's `Int` is signed 64-bit (`int64_t`), so 16-bit and 32-bit unsigned helpers range-check inputs, while 64-bit uses lossless signed `i64` (which is order-preserving for all non-negative values such as page IDs, txids, lengths, and timestamps).

```c
PRIM(BYTES_EMPTY,       "Bytes", "empty",       "Bytes",                               "",   "")
PRIM(BYTES_ZEROED,      "Bytes", "zeroed",      "fn(Int) : Bytes",                     "b",  "negative count; count exceeds limit")
PRIM(BYTES_FROM_LIST,   "Bytes", "from_list",   "fn(List(Byte)) : Bytes",              "b",  "")
PRIM(BYTES_TO_LIST,     "Bytes", "to_list",     "fn(Bytes) : List(Byte)",              "b",  "")

PRIM(BYTES_FROM_U16_BE, "Bytes", "from_u16_be", "fn(Int) : Bytes",                     "b",  "value outside 0 to 65535")
PRIM(BYTES_FROM_U32_BE, "Bytes", "from_u32_be", "fn(Int) : Bytes",                     "b",  "value outside 0 to 4294967295")
PRIM(BYTES_FROM_I64_BE, "Bytes", "from_i64_be", "fn(Int) : Bytes",                     "b",  "")

PRIM(BYTES_U16_BE_AT,   "Bytes", "u16_be_at",   "fn(Bytes, Int) : Option(Int)",        "bb", "")
PRIM(BYTES_U32_BE_AT,   "Bytes", "u32_be_at",   "fn(Bytes, Int) : Option(Int)",        "bb", "")
PRIM(BYTES_I64_BE_AT,   "Bytes", "i64_be_at",   "fn(Bytes, Int) : Option(Int)",        "bb", "")
```

### 2.1 Exact Edge-Case Semantics

- `Bytes.zeroed(count)`: bug if `count < 0` or `(uint64_t)count > MO_LIMIT_FILE_IO_BYTES` (or heap OOM); returns `count` zero bytes.
- `Bytes.from_u16_be(n)`: bug if `n < 0 || n > 65535`; returns 2-byte big-endian `Bytes`.
- `Bytes.from_u32_be(n)`: bug if `n < 0 || n > 4294967295`; returns 4-byte big-endian `Bytes`.
- `Bytes.from_i64_be(n)`: total (all `int64_t` values valid, including `INT64_MIN`); encodes raw two's-complement 8 bytes big-endian.
- `u16_be_at` / `u32_be_at` / `i64_be_at`: return `None` whenever `offset < 0` or `offset + width > bytes.size` (checked without signed overflow: `offset < 0 || (uint64_t)offset > bytes.size || bytes.size - (size_t)offset < width`). Otherwise return `Some(value)`.
- `Bytes.from_list` / `Bytes.to_list`: exact round-trip; `from_list([]) == Bytes.empty`.

---

## 3. Expected Touchpoints in `~/code/mo`

1. **Tables & limits:** `src/base/hostops.def`, `src/base/prims.def`, `src/base/limits.h`, `src/base/codes.h` (if any new diagnostic).
2. **Type/bytecode/heap:** Capability type registration for `Files.File` in `src/check/`, `src/lower/`, `src/bytecode/`, `src/heap/`, and `src/vm/` (mirroring `Sqlite.Database`).
3. **Implementations:**
   - `src/host/files.c` & `src/host/host.c` (real POSIX/macOS `File` + upgraded `Files.in_memory` + `MO_LIMIT_OPEN_FILES` in `rlim_t`).
   - `src/prim/text.c` (or new `src/prim/bytes.c` wired into `src/prim/prim.c`).
4. **Docs & embedded guide:** `docs/design/library.md` (must pass `make library-map`), `docs/agent-guide.md`, `docs/reference/README.md`.
5. **Tests & fuzzers:**
   - C unit tests in `tests/` covering real + in-memory `File` handles, path-escape rejections, partial/EOF `read_at`, past-EOF `write_at`, `truncate` grow/shrink, `rename` atomicity & confinement, handle-limit exhaustion, fd leak/drop check, and every `Bytes` boundary (`0`, `65535`, `4294967295`, `-1`, `INT64_MIN`, `INT64_MAX`, overflow offsets).
   - Extend `fuzz/fuzz_prim.c` and `fuzz/fuzz_host.c` / `fuzz/fuzz_host_real.c` (per `AGENTS.md`).
   - Verify with `bash ci/check.sh gcc`, `clang`, `sanitize`, `drivers`, and `static`.

## 4. Explicitly Deferred (Not in This PR)

- Bitwise operators on `Int` (`&`, `|`, `^`, `<<`, `>>`) — wait until MoDB profiling shows whether they're needed.
- `Crypto.crc32` — `Crypto.sha256` already exists and is strong enough for Milestone 1 page/meta checksums.
- Mutable `BytesBuilder` — `Bytes.join` already exists; only add a builder if profiling shows page assembly is a bottleneck.
- C-level fault-injecting `Files` fake — Milestone 1 puts deterministic torn-write/dropped-sync simulation in pure Mo above the `BlockStore` seam first.
