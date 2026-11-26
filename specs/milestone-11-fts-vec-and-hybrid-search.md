# Milestone 11 (`v0.3.0`): Transactional Pure-Mo BM25 Full-Text (`Modb.Fts`), Vector & Hybrid RRF Search (`Modb.Vec`), Workbench/UI/MCP Integration, and `modb` CLI Upgrades

Builds directly on Milestone 10 (`v0.2.0`) while preserving 100% disk and API compatibility for existing `.modb` databases. Milestone 11 splits cleanly into **11A** (`Modb.Fts` BM25+ full-text search, landed in PR #7 and live in Motet at `schema=v2`) and **11B** (`Modb.Vec` quantized CoW vector search + Hybrid RRF fusion, `AgentWorkbench`/Inspector UI/MCP/CLI integration, search scale benchmarks, and `v0.3.0`).

---

## 1. Milestone 11A: Pure-Mo BM25+ Full-Text Search (`src/modb/fts.mo`)

- Four ordinary Layer 1/2 buckets per `FtsIndex(prefix)` (non-`_modb_` prefixed, automatically included in `Export`, `backup_db`, and `compact_db`):
  - `{prefix}_fts_postings`: composite key `(term.bytes, doc_id.bytes)` -> `Posting(tf, weighted_tf, fields)`
  - `{prefix}_fts_docs`: `Table.text_key[IndexedDoc]`
  - `{prefix}_fts_df`: `Table.text_key[Int]`
  - `{prefix}_fts_meta`: `Table.text_key[FtsStats]` at `"stats"`
- Transactional mutators `tx_index_document(tx, idx, doc)` and `tx_remove_document(tx, idx, doc_id)` compose directly inside `Modb.WriteTx`, `Ledger.transact`, `Replay.execute`, and `World` actions.
- Query entry points `search` and fail-closed `search_filtered` support weighted fields, pure-Mo `ln_pos` BM25+ scoring (`k1 = 1.2`, `b = 0.75`), trailing-token prefix expansion (`max_prefix_expansions = 32`), `required_scope`, and deterministic `(score desc, doc_id asc)` ordering.

---

## 2. Milestone 11B: Pure-Mo Vector & Hybrid RRF Search (`src/modb/vec.mo`)

### 2.1 Storage Layout
Three ordinary Layer 1/2 buckets per `VecIndex(prefix, VecConfig(dimensions, metric, encoding))`:
- `{prefix}_vec_meta`: `Table.text_key[VecStats]` at key `"stats"` (`doc_count`, `dimensions`, `metric`, `encoding`, `total_bytes`)
- `{prefix}_vec_docs`: `Table.text_key[VecDocMeta]` keyed by `doc_id` (`doc_id`, `scope`, `dimensions`, `norm`, `scale`, `zero_norm?`)
- `{prefix}_vec_data`: raw `Modb` bucket keyed by `Table.encode_composite_key(scope.bytes, doc_id.bytes)` storing packed big-endian quantized bytes directly on 4 KiB CoW pages (zero JSON float-array parsing overhead at query time).
  - Keying `{prefix}_vec_data` by `(scope, doc_id)` enables $O(\text{scope})$ `Modb.prefix_scan` whenever `opts.required_scope` is set, and `tx_remove_vector` deletes the old composite key cleanly even when a document moves across scopes.

### 2.2 Encodings & Distance Metrics
- **Encodings (`VectorEncoding`):**
  - `Quantized16` (default): `2 * dimensions` bytes per vector; symmetric uniform quantization of normalized (or raw for `DotProduct`/`Euclidean`) components into `[-32767, +32767]` biased into unsigned `u16_be` (`0..65534`), read via `Bytes.u16_be_at` with zero intermediate allocations (`~3e-5` cosine error vs float64).
  - `Quantized8`: `dimensions` bytes per vector; compact `[-127, +127]` symmetric quantization biased into `0..254` for 2× smaller storage when maximum compactness matters.
- **Metrics (`DistanceMetric`):**
  - `Cosine` (default): unit-normalizes non-zero vectors on ingest, computes pure `Int64` integer dot product across quantized lanes and scales once (`acc.to_float * meta.scale * q_scale`), clamping to `[-1.0, 1.0]`. Zero vectors safely score `0.0`.
  - `DotProduct`: preserves vector magnitudes and computes scaled inner product cleanly in `Int64`.
  - `Euclidean`: computes exact quantized L2 distance `d = sqrt(sum((v_i - q_i)^2))` and returns bounded similarity `1.0 / (1.0 + d)` so higher scores always rank first.
- **Zero-dependency lexical/subword sketch (`text_sketch_embedding`):** Deterministic signed FNV-1a hashed word + character 3-gram projection onto the unit sphere for local demos, tests, and zero-external-API fallback. Production apps with model APIs pass native `List(Float)` embeddings directly.

### 2.3 Transactional Writes & Fail-Closed Search
- `tx_put_vector(tx, idx, VectorInput)` and `tx_remove_vector(tx, idx, doc_id)` compose inside any `WriteTx`, `Ledger` transaction, `World` action, or `Replay` call, and reject `NaN`/`Inf` elements, empty `doc_id`s, and `DimensionMismatch`.
- `search` and `search_filtered(store, idx, query_vec, opts, allow_doc)` check `allow_doc(doc_id, scope)` before decoding metadata or scoring any candidate vector.
- `hybrid_search` and `hybrid_search_filtered` run fail-closed `Fts.search_filtered` and `Vec.search_filtered` over top `candidate_limit` items per channel and fuse by `doc_id` using weighted 1-indexed Reciprocal Rank Fusion (`rrf_k = 60` default, configurable `fts_weight` / `vec_weight`), gracefully falling back when either text query or vector is empty/omitted.

---

## 3. Product Integrations (`AgentWorkbench`, UI, MCP & Standalone `modb` CLI)

1. **`examples/agent-workbench.mo` & `examples/workbench-ui.mo`:**
   - Atomically maintain `workbench` `FtsIndex` and 32-d `VecIndex` inside `action_create_task` and `action_complete_task` (tasks + artifacts).
   - Expose `POST /search` (supports `"hybrid"`, `"fts"`, `"vec"` modes, optional `project_id`, `limit`, `prefix_last_term`, `vector`) and `GET /search/stats`.
   - Add `modb_search` and `modb_search_stats` to native Streamable HTTP `/mcp` (43 MCP tools total), verified through `tools/modb_mcp_server.py`.
   - Add interactive **Search (FTS / Hybrid)** tab in `examples/workbench-ui.mo`.
2. **`src/modb/cli.mo` (`modb` CLI):**
   - `modb fts <db.modb> [prefix] [query...] [--scope S] [--prefix] [--limit N] [--json]`
   - `modb vec <db.modb> [prefix] [--json]`

---

## 4. Verification Criteria
- `mo test src/modb/fts.mo` and `mo test src/modb/vec.mo` pass.
- `mo test tests/test-fts.mo` and `mo test tests/test-vec-hybrid.mo` (quantization fidelity, cross-scope moves, `allow_doc` isolation, 120-step differential test vs float64 reference, Hybrid RRF fusion, `Modb.commit_and_crash` fault injection, plus `Ledger`/`Replay`/`Export`/`compact_db` round-trips) pass.
- `mo test src/modb/cli.mo`, `mo test examples/agent-workbench.mo`, `tests/test_workbench_mcp_and_ui.py`, `bench/real_world_agent_sim.py`, and `bench/bench-search.mo` pass, and downstream `motet` `store.mo` tests remain green.
