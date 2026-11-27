# Milestone 17 Spec (`v0.9.0`): Composite/Multi-Value/Dynamic Indexes, Compound Query Planner Pushdown & Keyset Pagination, and Continuous HTTP Pull-Replica Sync

Builds on Milestones 1–16 (`src/`, `examples/`, `tests/`) to directly close real-world secondary-index, dynamic-schema, planner pushdown, pagination, and continuous HTTP replica-sync gaps surfaced by downstream production apps (`motet` and `vellum`), while remaining 100% backwards-compatible with existing `Modb.Table`, `Modb.Views`, and `Modb.Sync` callers.

## 1. Slice 17A — Composite, Multi-Value & Dynamic Schema Indexes (`src/modb/table.mo`, `src/modb/dynindex.mo`)

1. **Order-preserving binary key codecs (`src/modb/table.mo`)**
   - `Bool`: `encode_bool_key` (`0x00` false, `0x01` true), `decode_bool_key`, `bool_codec`, `bool_index`, `unique_bool_index`.
   - `Decimal` (Mo 128-bit fixed-point `i128 * 10^-18`): fixed **21-byte** lexicographic encoding (`0x80` + 20 base-100 pairs for non-negative values over 22 integer + 18 fractional digits; `0x7F` + 20 `99 - pair` complemented pairs for negative values; negative zero normalized to non-negative). Preserves exact signed numeric order across all `Decimal` values.
   - Arbitrary-arity null-escaped tuples: `encode_tuple_key(List(Bytes))`, `encode_tuple_prefix_hi(List(Bytes))`, `encode_tuple_prefix_bounds(List(Bytes))`, `decode_tuple_key(Bytes)`, `pair_codec`, `composite_index`, `unique_composite_index`, plus `next_byte_key(Bytes)`.

2. **Diff-only index maintenance, `MultiIndex`, `count_by` & keyset pagination (`src/modb/table.mo`)**
   - `MultiIndex(K, V, I)` (`multi_index`, `text_multi_index`, `int_multi_index`, `decimal_multi_index`, `with_multi_index`) supporting `fn(V) : List(I)` extraction with deduplicated keys per row.
   - `put_specs` and `delete_specs` compute set differences `(old_keys - new_keys)` and `(new_keys - old_keys)` in `WriteTx` so unchanged keys perform zero `Modb.tx_get`/`tx_put`/`tx_delete` CoW B+Tree writes.
   - `count_by` and `count_by_multi`: fast exact count scanning only the index bucket (zero primary row fetches / JSON decodes).
   - `PageResult(K, V)` and keyset cursor pagination (`scan_page`, `range_page`, `range_page_multi`) using base64url-encoded raw key cursors and `next_byte_key` resume bounds.

3. **First-class runtime dynamic-schema index engine (`src/modb/dynindex.mo`, `Modb.Dynindex`)**
   - Typed tagged `DynVal` (`DynNull`, `DynBool`, `DynInt`, `DynDecimal`, `DynText`, `DynDate`, `DynRef`) with collision-free `(1-byte tag + order-preserving payload)` encoding.
   - Forward entries `[ns, prop_id, enc_val, row_id]` and automatic reverse-relation entries `[target_id, ns, prop_id, row_id]` for `DynRef` links (`default_dyn_index(prefix)` -> `"<prefix>_fwd"` / `"<prefix>_rev"`).
   - Diff-only `tx_update_row`, `tx_delete_row`, and `tx_delete_namespace`.
   - Type-tag-isolated `range_scan`, `snapshot_range_scan`, and `range_page` (enforcing matching `DynVal` type tags across bounds and open-ended scans so numeric/date/text/bool values in mixed schemas never bleed across types).
   - Reverse-relation queries (`lookup_backlinks`, `tx_lookup_backlinks`), exact lookups (`lookup`, `tx_lookup`, `snapshot_lookup`, `lookup_page`), exact counts (`count_exact`), and single-scan grouped counts (`count_groups` for Kanban columns).

## 2. Slice 17B — Compound Query Planner Pushdown, Ordered-Limit Early Stop & Keyset Pagination (`src/modb/views.mo`)

1. **Backwards-compatible composite & ordered View indexes**
   - Preserves existing `ReadProgram`, `ReadResult`, and `ViewIndex` definitions and existing `explain_read_program` keys verbatim.
   - Adds `ViewCompositeIndex` (`with_view_composite_index`, `with_view_composite_eq_index`, `with_view_composite_range_index`) and `ViewOrderedIndex` (`with_view_ordered_index`).

2. **Planner pushdown & early-stop execution**
   - Extends `QueryPlan` with `PlanCompositeEq`, `PlanCompositeRange`, and `PlanIndexOrdered`.
   - `plan_read_program` flattens nested `And` conjuncts and prioritizes:
     1. Longest matching `PlanCompositeEq` (all fields `Eq`),
     2. `PlanCompositeRange` (leading `Eq` fields + tail range bounds),
     3. Single-field `PlanIndexEq`,
     4. Prefix-only `PlanCompositeRange` (leading `Eq` fields, open tail),
     5. Single-field `PlanIndexInList`,
     6. `PlanIndexOrdered` (ascending `OrderBy` with optional bounds & `Limit` pushdown) or `PlanIndexRange`,
     7. `PlanFullScan`.
   - `execute_read_program` enforces strict View projection and evaluates residual predicates (`And`/`Or`/`Not` etc.), verifies ascending monotonicity for `PlanIndexOrdered` + stops scanning immediately once `eff_limit` matches are collected (skipping `sort_rows` when verified sorted).
   - `explain_read_program` adds `"residual_filter"`, `"residual_predicates"`, `"order_pushdown"`, and `"limit_pushdown"` metadata.

3. **Additive keyset cursor pagination (`PagedReadResult`)**
   - `execute_read_program_paged`, `execute_read_program_paged_recorded`, and `execute_read_program_paged_locked` accept `after_cursor: Option(Text)` and `page_size: Int`, validating opaque base64url cursors against `(view, order_by)` and pushing `Gte(sort.field, last_val)` down into range/ordered index scans on sorted single-table reads.

## 3. Slice 17C — Continuous HTTP Pull-Replica Sync (`src/modb/sync.mo`, `src/modb/pull.mo`, `src/modb/cli.mo`, `examples/agent-workbench.mo`)

1. **Replica cursor helpers (`Modb.Sync`)**: `get_replica_cursor`, `get_replica_cursor_locked`, and `seed_replica_cursor_locked` for seamless mid-stream snapshot bootstrapping.
2. **Pull-replication engine (`Modb.Pull`)**:
   - `pull_once` / `pull_loop` consuming HTTP `/<peer>/snapshot`, `/<peer>/export`, and `/<peer>/ack` (compatible with both `AgentWorkbench` `/sync/peers` and `Motet` `/v1/modb/sync/peers`).
   - Supports Bearer auth, `--decrypt` with `--key-file`/`--key-env`/`--keyring-file`/`--keyring-env` + `--aad`/`--key-id`, auto-bootstrap from missing replica path, and fail-closed verification (never `/ack`s before durable local commit).
   - Automatic lost-ack crash recovery: if a prior cycle applied locally and crashed before `/ack`, `pull_once` detects `actual_seq == expected_seq - 1`, verifies matching local cursor, sends the delayed `/ack`, and retries cleanly.
3. **Standalone CLI (`modb sync <replica.modb> pull ...`)** and `AgentWorkbench` `/sync/peers/:id/snapshot` + `?encrypt=true&key_id=...&aad=...`, composite/ordered view indexes, `/views/query/paged`, and MCP `0.9.0`.

## 4. Verification Gates (`v0.9.0`)

- Unit tests: `src/modb/table.mo`, `src/modb/dynindex.mo`, `src/modb/views.mo`, `src/modb/sync.mo`, `src/modb/pull.mo`, `src/modb/cli.mo`.
- Integration/differential suites: `tests/test-table.mo`, `tests/test-views-incremental.mo`, `tests/test-matview-planner.mo`, `tests/test-sync-replication.mo`, `tests/test-m17-indexes-planner.mo`.
- Live 8-worker suites: `examples/agent-workbench.mo`, `tests/test_workbench_mcp_and_ui.py`, `tests/test_sync_pull_live.py`.
- Cross-repo compatibility gate: `motet` (`store.mo`, `main.mo`, `server.mo`) passes cleanly against updated `modb`.
