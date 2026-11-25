# Mo PR Contract: Advisory File Locks, `ReadFiles.open`, and Milestone 2A DX Fixes

**Target repo:** `~/code/mo` (implement in a clean worktree/branch off `origin/main` after the post-cutover hardening PR merges).  
**Rust discipline:** `rustc 1.97+`, edition `2024`, `#![forbid(unsafe_code)]`, hardened `[workspace.lints]`, zero new external dependencies (`rustix` with `"fs"` is already in `crates/mo-host/Cargo.toml`).  
**Source:** Real concurrency and ergonomics findings recorded in [FRICTION.md](../FRICTION.md) (#13, #15, #16) while building MoDB Milestone 2A (`Modb.Ledger` + `examples/shop-api.mo`). Every addition is 100% general-purpose—nothing database-specific.

---

## 1. Advisory File Locks on `Files.File` (`FRICTION.md` #16)

Any Mo program that coordinates concurrent readers and writers over a shared file across multiple `mo serve --workers N` threads or multiple OS processes (embedded stores, lockfiles, caches, append-only logs) needs advisory shared/exclusive locking on open `Files.File` handles.

### 1.1 Host Operations (`crates/mo-def/defs/hostops.def`)

Follow the exact existing `Files.File` registration convention (`crates/mo-def/defs/hostops.def:109-114`, resolved via UFCS on `Files.File` in `crates/mo-check/src/infer/calls.rs:590`):

```c
HOSTOP(FILES_LOCK_SHARED,    "Files", "lock_shared",    "fn(Files.File) : Result(Unit, FileError)", "b", "", false)
HOSTOP(FILES_LOCK_EXCLUSIVE, "Files", "lock_exclusive", "fn(Files.File) : Result(Unit, FileError)", "b", "", false)
HOSTOP(FILES_UNLOCK,         "Files", "unlock",         "fn(Files.File) : Result(Unit, FileError)", "b", "", false)
```

### 1.2 Real OS Semantics (`crates/mo-host/src/real_files.rs`)

- **Use BSD `flock` via safe `rustix::fs::flock` (`#![forbid(unsafe_code)]`):**
  - `FilesLockShared` → `rustix::fs::flock(&file.fd, FlockOperation::LockShared)` (blocking, retrying on `Errno::INTR`).
  - `FilesLockExclusive` → first check `if file.read_only` → return `FileError.NotAllowed(path)` (see §2); otherwise `rustix::fs::flock(&file.fd, FlockOperation::LockExclusive)` (blocking, retrying on `Errno::INTR`).
  - `FilesUnlock` → `rustix::fs::flock(&file.fd, FlockOperation::Unlock)` (retrying on `Errno::INTR`; unlocking an unlocked handle succeeds with `Ok(Unit)`).
- **Why `flock` (and NOT POSIX `fcntl` `F_SETLKW`):**
  - POSIX `fcntl` record locks are per-process and are silently dropped whenever *any* descriptor to the same inode is closed inside the same process—which breaks multi-threaded `mo serve --workers 8`.
  - BSD `flock` binds to the **open file description** (`OwnedFd` returned by `openat`), so separate worker threads inside one `mo serve` process *and* separate OS processes (`mo run` CLI + live `mo serve`) all synchronize cleanly on both Linux and macOS.
- **Automatic release on drop:** Dropping `RealOpenFile` closes its `OwnedFd`, which automatically releases any held `flock`—guaranteeing a stopped/failed request handler can never leak a stuck lock.

### 1.3 In-Memory Fake Parity (`crates/mo-host/src/fake_files.rs`)

- Assign each `FakeOpenFileCap` a monotonic `handle_id: u64` and track per-canonical-path lock state on the shared `FakeFs`:
  - `shared_holders: BTreeSet<u64>`
  - `exclusive_holder: Option<u64>`
- **Single-threaded deadlock-free semantics in `mo test`:**
  - `lock_shared`: succeeds (`Ok(Unit)`) if `exclusive_holder` is `None` (adds `handle_id` to `shared_holders`) or `Some(handle_id)` (downgrades to shared). If held exclusively by a *different* `handle_id`, returns `Error(FileError.Failed(path, "file is locked exclusively"))` instead of deadlocking the single-threaded VM.
  - `lock_exclusive`: rejects `read_only == true` with `FileError.NotAllowed(path)`. Succeeds (`Ok(Unit)`) if no *other* `handle_id` holds a shared or exclusive lock (idempotent if already held exclusively by `handle_id`; upgrades if `handle_id` is the sole shared holder). Otherwise returns `Error(FileError.Failed(path, "file is locked"))`.
  - `unlock`: removes `handle_id` from `shared_holders` and clears `exclusive_holder` if equal to `Some(handle_id)`; always returns `Ok(Unit)`.
- **Auto-unlock on `Drop`:** `Drop` for `FakeOpenFileCap` releases any shared/exclusive lock held by `handle_id` (mirroring real OS `OwnedFd` close semantics).

---

## 2. Read-Only Random-Access File Handles: `ReadFiles.open` (`FRICTION.md` #16)

Today `ReadFiles` supports whole-file `read_bytes`/`read_text`, while random-access `open` exists only on writable `Files`. Adding `ReadFiles.open` lets read-only HTTP routes, query tools, and inspect utilities perform bounded `read_at` + `lock_shared` without requesting write authority—keeping read-only authority statically visible in function signatures and `mo diff`.

### 2.1 Host Operation (`crates/mo-def/defs/hostops.def`)

```c
HOSTOP(READFILES_OPEN, "ReadFiles", "open", "fn(ReadFiles, Text) : Result(Files.File, FileError)", "bb", "too many files open at once", false)
```

*(Design note: Returning `Files.File` with an immutable host-enforced `read_only: true` flag avoids adding a new bytecode `Capability` enum tag and lets libraries like `Modb.Pager` share one `Files.File` code path for both read-only and read-write handles while still guaranteeing kernel + host write refusal.)*

### 2.2 Confinement & Read-Only Attenuation Invariants

- **Real (`crates/mo-host/src/real_files.rs`):**
  - Resolves path strictly inside the `ReadFiles` root descriptor using `PathMode::Read` (`O_RDONLY | O_NOFOLLOW | O_CLOEXEC`; **never** passes `O_CREAT`).
  - Missing files return `FileError.NotFound`; `..`/symlink escapes return `FileError.NotAllowed`; enforces `MO_LIMIT_OPEN_FILES`.
  - Stores `read_only: bool` on `RealOpenFile` (`false` for `Files.open`, `true` for `ReadFiles.open`).
  - Defense in depth: on a `read_only == true` handle, `write_at`, `truncate`, `sync`, and `lock_exclusive` return `Error(FileError.NotAllowed(path))` **before** issuing any syscall, while `read_at`, `size`, `lock_shared`, and `unlock` work normally.
- **Fake (`crates/mo-host/src/fake_files.rs`):**
  - `ReadfilesOpen` resolves strictly within `folder.prefix`, returns `FileError.NotFound` if the entry does not exist (never creates), rejects directories (`"is a folder"`), enforces `MO_LIMIT_OPEN_FILES`, and sets `read_only: true` on `FakeOpenFileCap`.
  - Same `read_only == true` refusal (`FileError.NotAllowed`) on `write_at`, `truncate`, `sync`, and `lock_exclusive`.

---

## 3. Milestone 2A DX Fixes (`FRICTION.md` #13 & #15)

### 3.1 Clean Parser Recovery & Diagnostic Hint on `actor` Keyword Misuse (`FRICTION.md` #13)

`actor` is a reserved keyword alongside `service` and `api` (`crates/mo-syntax/src/lexer.rs:84`, `grammar/mo.y:70`). That is consistent—keep `actor` reserved so `grammar/mo.y` stays zero-conflict. However, when a user accidentally names a struct field or function parameter `actor: Text`:

- Currently `crates/mo-syntax/src/parser.rs` reports `E0017: expected snake_case name, found actor`, then mis-synchronizes on `TokenKind::Actor` as a top-level `actor` block and floods 20+ bogus `E0007: an actor clause starts with state, calls, every or promise` errors across the rest of the function.
- **Fix in `crates/mo-syntax/src/parser.rs`:**
  1. When expecting a `snake_case` field or parameter name and encountering a reserved keyword (`actor`, `service`, `api`, etc.), emit a clear single diagnostic naming it as a reserved keyword (preserving existing error codes `E0013` / `E0017` and all existing `tests/errors/` snapshots).
  2. Consume the bogus keyword token (and optional `: Type`) inside parameter/struct-field recovery instead of falling out of the parameter list into top-level `DeclHeaderKind::Actor` parsing, preventing the 20-line error cascade.

### 3.2 Subcommand `--help` / `-h` and `mo serve --root` Hint (`FRICTION.md` #15)

Currently `mo serve --help` prints `unknown flag: "--help"`, and passing `--root` or `--state-dir` to `mo serve` prints `flag is not accepted by this command: "--root"` without telling the user that `mo serve` uses `--data DIR`.

- **Fix in `crates/mo-cli/src/cli.rs` & `crates/mo-cli/src/execute.rs`:**
  1. Support `--help` / `-h` on top-level `mo` and every subcommand (`mo <cmd> --help`), printing concise usage + accepted flags derived from `FLAGS` and exiting `0` (verify against `tests/cli/` so no existing error snapshot changes).
  2. When `--root` or `--state-dir` is passed to `mo serve`, include a one-line hint pointing to `--data DIR`.

---

## 4. Exact Touchpoints in Pure-Rust `~/code/mo`

| Area | Files |
| --- | --- |
| Contract table | `crates/mo-def/defs/hostops.def` (+4 `HOSTOP`s; `mo-def/build.rs` regenerates `HostOpId` automatically) |
| Core IR & verifier | `crates/mo-core/src/{lib,check,codec}.rs` (`CoreIoNullaryOp`: `FileLockShared`, `FileLockExclusive`, `FileUnlock`, `ReadFileOpen`) |
| Lowering & codegen | `crates/mo-lower/src/applications.rs`, `crates/mo-codegen/src/operations.rs` |
| Host runtime (`#![forbid(unsafe_code)]`) | `crates/mo-host/src/{lib,real_files,fake_files}.rs` |
| Lean formal model & oracle | `formal/MoCore/{Syntax,Prim,Builtins,Text/Prim}.lean`, `formal/TEXT.md` (mirroring `fileOpen`/`fileSync`) |
| Parser recovery & CLI | `crates/mo-syntax/src/parser.rs`, `crates/mo-cli/src/{cli,execute}.rs` |
| Docs & hostop checks | `docs/design/library.md` (checked by `ci/library_map.sh`), `docs/reference/README.md`, `ci/check_host.py` |

---

## 5. Verification Gates

### 5.1 `~/code/mo` PR Gates
1. `CI=1 bash ci/check.sh` across all groups (`rust`, `drivers`, `bench`, `lean`, `static`, `models`) — **0 skips, 0 warnings**.
2. New Rust unit tests in `crates/mo-host/`:
   - Multi-threaded real `flock` test (8 OS threads contending on `lock_exclusive` + concurrent `lock_shared` readers verifying mutual exclusion and shared concurrency).
   - Automatic lock release on `RealOpenFile` and `FakeOpenFileCap` drop.
   - `ReadFiles.open` real & fake tests: missing file → `NotFound`, escape/symlink → `NotAllowed`, `read_at`/`size`/`lock_shared`/`unlock` succeed, `write_at`/`truncate`/`sync`/`lock_exclusive` return `NotAllowed`, handle limit enforced.
3. New Mo tests in `tests/` covering `File.lock_*`, `ReadFiles.open`, non-cascading `actor` parameter diagnostic, and `mo serve --help` / `--root` hint.
4. Keep `#![forbid(unsafe_code)]`, 0 new external crates, and 0 OpenSSL/system-`libsqlite3` linkage.

### 5.2 Follow-Up MoDB Phase 2B Adoption Gate (In `modb`)
Once this PR merges into `robertguss/mo` `main`:
1. Add lock-aware helpers (`Modb.open_read_only`, `Modb.Ledger.read_locked`, `Modb.Ledger.write_locked`) in `src/modb.mo` and `src/modb/ledger.mo`.
2. Switch `examples/shop-api.mo`'s read routes (`GET /*`) to `ReadFiles` + `lock_shared` and write routes (`POST /*`) to `Files` + `lock_exclusive` (re-opening fresh committed meta-pages under the lock before writing).
3. Upgrade `tests/test_shop_api_live.py` to boot **`mo serve --workers 8`** and run an **8-thread concurrent HTTP stress test** (simultaneous `POST /orders` + `GET /products` + `GET /audit` + `GET /admin/verify` + mid-load `SIGKILL` recovery), verifying zero `500`s, exact stock conservation, and unbroken SHA-256 audit hash chain.
