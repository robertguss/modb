# MoDB

An embedded, single-file, crash-safe database written in pure [Mo](https://github.com/robertguss/mo) (now running on the pure-Rust `#![forbid(unsafe_code)]` Mo compiler and bytecode VM), engineered from first principles for multi-agent AI applications.

Instead of passing raw SQL strings over external drivers, MoDB stores typed Mo records directly on copy-on-write (CoW) 4 KiB pages protected by full per-page SHA-256 checksums, alternating meta-pages, dual `fsync` commit barriers, atomic secondary indexes, hash-chained audit ledgers, attenuated agent grants, advisory leases, speculative CoW worlds, and proposal-first time-travel replay.

---

## Architecture & Capabilities

MoDB is organized cleanly into four pure-Mo layers inside [`src/`](src/):

| Layer | Modules | What it provides |
| --- | --- | --- |
| **Layer 1: Storage Engine** | [`src/modb.mo`](src/modb.mo), [`tree.mo`](src/modb/tree.mo), [`codec.mo`](src/modb/codec.mo), [`pager.mo`](src/modb/pager.mo), [`errors.mo`](src/modb/errors.mo) | Single-file CoW B+Tree over 4 KiB pages, per-page SHA-256 verification, zero-copy slotted page sealing, right-edge sequential splitting (~98% leaf fill), binary-search lookups & zero-decode entry counting (`count_entries`, `count_bucket`), overflow chains, persistent root pins (`pin_root`), $O(\text{diff})$ structural CoW diffs (`diff_roots`, `diff_user_tx_from_root`), and lock-free optimistic CoW snapshot reads (`with_shared_lock`) with advisory `flock` fallback. |
| **Layer 2: Typed Tables, Indexes & FTS** | [`src/modb/table.mo`](src/modb/table.mo), [`src/modb/fts.mo`](src/modb/fts.mo) | Typed `Table(K, V)` and transactional `Table.transact` / `Table.write_tx` with automatic maintenance of unique and non-unique secondary indexes (`unique_text_index`, `text_index`, `int_index`) inside the same CoW commit, plus `Modb.Fts` transactional pure-Mo BM25+ full-text search (`Fts.index`, `tx_index_document`, `tx_remove_document`, `search`, `search_filtered`) with field weights, trailing-term prefix expansion, and fail-closed scope/predicate filtering. |
| **Layer 3: Ledger, Invariants & Export** | [`src/modb/ledger.mo`](src/modb/ledger.mo), [`src/modb/export.mo`](src/modb/export.mo) | Every write records caller metadata (`principal`, `action`, `reason`, timestamp) into an unbroken SHA-256 hash-chained `_modb_audit` log. Enforces $O(\text{touched})$ incremental commit-time invariants, atomic versioned schema migrations, checkpoint-anchored fast verification (`verify_fast`, `verify_audit_store`, `verify_audit_window_store`), layout-independent canonical SHA-256 `PortableSnapshot` export/import, consistent online `backup_db`, and atomic `compact_db` (`compact_db_with_hook`). |
| **Layer 4: Multi-Agent Coordination** | [`src/modb/grants.mo`](src/modb/grants.mo), [`claims.mo`](src/modb/claims.mo), [`world.mo`](src/modb/world.mo), [`replay.mo`](src/modb/replay.mo), [`views.mo`](src/modb/views.mo) | **Grants:** Attenuated hierarchical capabilities ("helpers get less, never more") with cascading revocation.<br>**Claims:** Ordinary persisted TTL leases in `_modb_claims` so agents see contention through data.<br>**Worlds:** Speculative CoW sandboxes with $O(1)$ bucket-level & $O(\text{diff})$ key/range-level CoW-diff read skipping, bounded-TTL fairness priority tickets (`claim_priority`, `land_world_fair`), and Nested Child Worlds (`open_child_world`, `land_child_world`) with per-step lineage attribution.<br>**Replay:** Upgrade-aware offline simulation (`ExcludePrincipal`, `ExcludeGrant`, `ExcludeSeqs`, `ExcludeWorld`, `StopBeforeSeq`, bug-fix overrides), `compact_with_baseline` + CoW-pinned `ReplayBaseline` $O(\text{diff})$ delta proposals, staleness guards, and explicit atomic acceptance.<br>**Views & Onboarding:** Grant-scoped `Views`, k-anonymous `Releases`, zero-approval sandboxed `ReadProgram`s with static field gating & read provenance logs, and stateless `OnboardingManifest` (`describe_for_caller`). |
| **Standalone CLI** | [`src/modb/cli.mo`](src/modb/cli.mo) | Schema-less `modb` CLI (`inspect`, `verify [--fast]`, `dump`, `audit`, `worlds`, `backup`, `export`, `restore`, `compact`, `diff`) installable via `mo install src/modb/cli.mo --name modb`. |

---

## Quick Start

Add MoDB as a path dependency in your project's `mo.toml`:

```toml
[package]
name = "my-app"
version = "0.1.0"

[dependencies]
modb = { path = "../modb" }
```

Define typed tables and secondary indexes in plain Mo and execute atomic, indexed transactions (modeled on [`examples/shop.mo`](examples/shop.mo)):

```mo
module App
use Modb
use Modb.Table{Table, TableError}

struct Product
  title: Text
  category: Text
  price: Decimal
  stock: Int
end

products_by_category = Table.text_index[Text, Product]("products_by_category", fn(p) p.category end)
products = Table.text_key[Product]("products").with_index(products_by_category)

fn restock(files: Files, db_path: Text, sku: Text, delta: Int) : Result(Product, TableError)
  db = try Modb.open(files, db_path).map_error(fn(e) Table.Storage(e) end)
  (_next_db, updated) = try Table.transact(
    db,
    fn(e) e end,
    fn(tx)
      prod = try (try Table.tx_get(tx, products, sku)).or_fail(
        Table.InvalidKey(reason: "unknown product '#{sku}'")
      )
      var next = prod
      next.stock += delta
      tx1 = try Table.put(tx, products, sku, next)
      Ok((tx1, next))
    end
  )
  Ok(updated)
end
```

For multi-worker HTTP servers built with Mo's `api` block, pass read-only `ReadFiles` handlers to `Modb.with_shared_lock` / `Ledger.read_locked` and writable `Files` handlers to `Modb.with_exclusive_lock` / `Ledger.locked` (see [`examples/shop-api.mo`](examples/shop-api.mo) and [`examples/agent-workbench.mo`](examples/agent-workbench.mo)).

---

## Examples, Live Inspector UI & MCP Server

| Example / Tool | How to run | What it demonstrates |
| --- | --- | --- |
| **CLI Roastery Demo** ([`examples/shop.mo`](examples/shop.mo)) | `TMP=$(mktemp -d) && mo run --root "$TMP" examples/shop.mo && rm -rf "$TMP"` | Typed records, exact `Decimal` arithmetic, unique & non-unique secondary indexes, O(1) snapshots, and persistence. |
| **AgentWorkbench + Live Web Inspector** ([`examples/agent-workbench.mo`](examples/agent-workbench.mo), [`examples/workbench-ui.mo`](examples/workbench-ui.mo)) | `mo serve --workers 8 --data ./workbench-data examples/agent-workbench.mo` | 8-worker HTTP API (`:8092`), interactive browser Inspector UI (`GET /`), native Streamable HTTP MCP endpoint (`POST /mcp` with 41 tools), Grants, Claims, Speculative & Nested Child Worlds, Fairness Tickets, Views, Releases, Replay Studio, and SHA-256 Export. |
| **Stdio MCP Bridge** ([`tools/modb_mcp_server.py`](tools/modb_mcp_server.py)) | `python3 tools/modb_mcp_server.py --data ./workbench-data` | Zero-dependency Python 3 stdio MCP server bridging Claude Desktop, Cursor, or T3 Code to a live `AgentWorkbench` instance (`--url` to attach, `--print-config` for host setup). |
| **8-Worker E-Commerce API** ([`examples/shop-api.mo`](examples/shop-api.mo)) | `mo serve --workers 8 --data ./shop-data examples/shop-api.mo` | Least-privilege `ReadFiles`/`Files` locking, Layer 3 hash-chained ledger, commit invariants, migrations, and selective-undo replay. |

---

## Crash-Safety & Benchmark Highlights

Full methodology, historical comparisons, and reproduction steps live in [`BENCHMARKS.md`](BENCHMARKS.md). Highlights from pure-Rust `mo` on Linux ext4 (4 KiB pages, SHA-256 checksums on every page, 2 `fsync`s per commit):

- **Deterministic Crash Simulation:** **500/500** torn, dropped, and reordered write crashes recovered cleanly with bit-flip detection (`mo test tests/test-modb.mo`).
- **Real OS `SIGKILL` Crash Loops:** **100/100** `kill -9` kills survived cleanly in `8.9 s`–`11.0 s` with `Modb.verify` passing after every kill (`bench/kill_loop.py`), and multi-process OS PID `flock` + `SIGKILL` stress tests pass (`tests/test_multiprocess_flock.py`).
- **100,000-Row Storage Engine (Milestone 5):**
  - Bulk load (`100 × 1,000`-row synced batches): **`5.78–6.82 s`**
  - Full overwrite (`100 × 1,000`-row synced batches): **`8.81–8.85 s`** (`8.2 MiB` / `2,041` pages flat on disk)
  - Warm point `get` (1,000×): **`98–111 ms`** (`~98–111 µs`/lookup)
  - `Modb.verify` (100k cold SHA-256): **`764–783 ms`**
- **8-Worker Concurrent HTTP (`mo serve --workers 8`, post-native-JSON `mo`):**
  - `ShopApi` pure 8-thread reads: **`386.0 req/s`** (`0` errors, `p50 = 20.1 ms`); mixed 6 readers + 2 synced writers: **`333.6 req/s`** (`write p50 = 34.3 ms`, zero writer starvation)
  - `AgentWorkbench` multi-agent coordination (18 tasks): coarse queries hit `49` `StaleRead` retries (`4.59 s`), while fine queries + Claims achieved **`0` retries and `0` needless send-backs in `1.38 s`**
  - Milestone 10 8-worker (`mo serve --workers 8`): fine key-level `get_task` skipped **`15` reads** naturally under 6-worker contention (`2.29 s`, `0` retries), disjoint `scan_tasks_range` skipped `3` concurrent range validations, `PriorityTicket` fairness deferred `3` competitors and rescued the starved World (`62.6 ms`), and `2` concurrent Child Worlds merged & landed cleanly (`BENCHMARKS.md` §11)
  - 82-call offline Replay simulation: **`132.6–183.2 ms`**, atomic acceptance: **`64.3–116.1 ms`**, 922-entry canonical SHA-256 export: **`31.6 ms`**

---

## Running Tests & Benchmarks

Using `mo` (from `PATH` or `~/code/mo/target/release/mo`):

```sh
# Core unit & integration tests
mo test src/modb.mo
mo test src/modb/table.mo
mo test src/modb/fts.mo
mo test src/modb/ledger.mo
mo test src/modb/export.mo
mo test src/modb/grants.mo
mo test src/modb/claims.mo
mo test src/modb/replay.mo
mo test src/modb/world.mo
mo test src/modb/views.mo
mo test src/modb/cli.mo

# Differential, crash-simulation, pin/diff, worlds, replay/export & views tests
mo test tests/test-modb.mo
mo test tests/test-table.mo
mo test tests/test-fts.mo
mo test tests/test-ledger.mo
mo test tests/test-pins-diff.mo
mo test tests/test-worlds.mo
mo test tests/test-replay-export.mo
mo test tests/test-views-incremental.mo
mo test tests/test-compact-backup.mo
mo test tests/test-m10-worlds-cli.mo

# Install standalone `modb` CLI
mo install src/modb/cli.mo --name modb --bin-dir ~/.local/bin

# End-to-end example suites
mo test examples/shop.mo
mo test examples/shop-api.mo
mo test examples/agent-workbench.mo

# Live 8-worker OS SIGKILL, flock, HTTP Inspector & stdio MCP integration tests
python3 tests/test_multiprocess_flock.py "$(command -v mo || echo ~/code/mo/target/release/mo)"
python3 tests/test_shop_api_live.py "$(command -v mo || echo ~/code/mo/target/release/mo)"
python3 tests/test_workbench_mcp_and_ui.py "$(command -v mo || echo ~/code/mo/target/release/mo)"

# Stress benchmarks
python3 bench/kill_loop.py "$(command -v mo || echo ~/code/mo/target/release/mo)" 100
python3 bench/bench_shop_api.py "$(command -v mo || echo ~/code/mo/target/release/mo)"
python3 bench/real_world_agent_sim.py "$(command -v mo || echo ~/code/mo/target/release/mo)"
TMP=$(mktemp -d) && mo run --root "$TMP" bench/bench-modb.mo 100000 && rm -rf "$TMP"
```

---

## Repository Layout & Documentation

| Path | Purpose |
| --- | --- |
| [`mo.toml`](mo.toml), [`src/`](src/) | Pure-Mo MoDB package (`Modb` Layer 1, `Modb.Table` & `Modb.Fts` Layer 2, `Modb.Ledger` & `Modb.Export` Layer 3, `Modb.Grants`/`Claims`/`World`/`Replay`/`Views` Layer 4, `Modb.Cli`) |
| [`examples/`](examples/) | End-to-end apps: [`shop.mo`](examples/shop.mo), [`shop-api.mo`](examples/shop-api.mo), [`agent-workbench.mo`](examples/agent-workbench.mo), [`workbench-ui.mo`](examples/workbench-ui.mo) |
| [`tools/`](tools/) | Stdio MCP server bridge ([`tools/modb_mcp_server.py`](tools/modb_mcp_server.py)) |
| [`tests/`](tests/) | Differential, crash-simulation, layer integration, multi-process `flock`+`SIGKILL`, and live UI/MCP test suites |
| [`bench/`](bench/) | 100k-row storage/SQLite comparison, OS `SIGKILL` crash loop, and 8-worker concurrency & multi-agent benchmarks |
| [`specs/`](specs/) | Milestone 1–10 architecture & implementation specifications |
| [`models/`](models/) | TLA+ formal models (`Replay.tla`, `Worlds.tla`, `Sweep.tla`) and predictions |
| [`design.md`](design.md), [`BENCHMARKS.md`](BENCHMARKS.md), [`FRICTION.md`](FRICTION.md), [`GLOSSARY.md`](GLOSSARY.md) | Long-term design doc, verified benchmark ledger, Mo language/runtime friction log, and terminology |
| [`wiki/`](wiki/), [`research/`](research/) | Compiled database knowledge base and primary research notes |
