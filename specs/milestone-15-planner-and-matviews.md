# Milestone 15 — Index-Accelerated `ReadProgram` Planner & Incremental CoW Materialized Views (`v0.7.0`)

## Goals

1. **Zero-Change-Semantics Index Acceleration for `Modb.Views` (`ReadProgram`):**
   - Register optional `ViewIndex` lookup handlers (`supports_eq`, `supports_range`) per `(view_name, field_name)` in `ViewCatalog`.
   - Add deterministic `plan_read_program` & `explain_read_program` planning over flattened top-level `And` conjuncts:
     `PlanIndexEq` > `PlanIndexInList` > `PlanIndexRange` > `PlanFullScan`.
   - `execute_read_program` loads only candidate rows identified by the chosen `QueryPlan`, enforces all work bounds (`max_rows_scanned`, `max_ops`, `max_result_rows`), strips hidden fields via `project_row`, and always evaluates the full `where_clause` predicate over every candidate so planner errors or stale bounds can never weaken security or change query results.

2. **Incremental CoW Materialized Views (`Modb.MatView`):**
   - Persist durable grouped summary tables in `_modb_matview_meta` and `_modb_matview_rows` supporting `MatCount`, `MatSum(field)`, `MatMin(field)`, and `MatMax(field)` over `Decimal`-exact arithmetic.
   - Track committed progress with a persistent root pin (`mv:<name>`) so `refresh_matview` inspects only O(diff) changed entries via `Modb.diff_roots` since the prior pin root.
   - Handle `MatMin` / `MatMax` edge cases safely: when an updated or deleted source row matches the group's stored extremum (and was not replaced by a tighter extremum), automatically fall back to single-group recomputation over just the affected group (`find_group_source_rows`), avoiding a full table rebuild while preserving exact parity with `rebuild_matview`.
   - Crash recovery: if `_modb_matview_meta.last_txid != pin.txid` or the pin is missing, `refresh_matview` cleanly falls back to `rebuild_matview` and re-aligns `mv:<name>`.
   - Support $k$-anonymous cohort suppression on `query_matview(..., min_group_size: Some(k))`.
