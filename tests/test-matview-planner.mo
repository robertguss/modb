## MoDB Milestone 15 (`v0.7.0`) Verification Suite:
## - 200-step randomized differential parity (`refresh_matview` == `rebuild_matview`) across
##   inserts, in-place updates, group moves, deletes, and extremum deletions
## - Synchronous `tx_apply_matview` + `pin_align` refresh parity
## - Crash recovery fallback when `mv:<name>` pin is stale or missing
## - 500-row `Modb.Views` ReadProgram index planner parity & O(k) rows_scanned reduction
module TestMatviewPlanner
use Json
use Modb
use Modb.Matview
use Modb.Table
use Modb.Views

fn lcg_next(seed: Int) : Int
  (seed * 1103515245 + 12345).floor_mod(2147483648)
end

fn dept_of(idx: Int) : Text
  m = idx.floor_mod(4)
  if m == 0
    "eng"
  else if m == 1
    "ops"
  else if m == 2
    "fin"
  else
    "sec"
  end
end

fn step_write(store: Modb.Store, orders: Table.Table(Int, Json), key: Int, op: Int, dept_i: Int, cents: Int) : Modb.Store
  tx = Modb.begin_write(store)
  tx1 = if op == 0
    case Table.delete(tx, orders, key)
      Ok(nt): nt
      Error(_): stop "delete failed"
    end
  else
    row = Json.Object({
      "id": Json.int(key),
      "dept": Json.String(dept_of(dept_i)),
      "cost": Json.decimal(cents.to_decimal / 100.0)
    })
    case Table.put(tx, orders, key, row)
      Ok(nt): nt
      Error(_): stop "put failed"
    end
  end
  case Modb.commit(tx1)
    Ok(s): s
    Error(_): stop "commit failed"
  end
end

test "200-step randomized differential parity between incremental refresh and full rebuild"
  assert Modb.open(Files.in_memory({}), "diff.modb") is Ok(s0_a)
  assert Modb.open(Files.in_memory({}), "ref.modb") is Ok(s0_b)
  orders = Table.int_key[Json]("orders")

  mv_def = Matview.MatViewDef(
    name: "dept_stats",
    description: "Department order rollup",
    source_bucket: "orders",
    group_by: "dept",
    aggregates: [
      Matview.MatAggSpec(alias: "cnt", op: Matview.MatCount),
      Matview.MatAggSpec(alias: "sum_cost", op: Matview.MatSum(field: "cost")),
      Matview.MatAggSpec(alias: "min_cost", op: Matview.MatMin(field: "cost")),
      Matview.MatAggSpec(alias: "max_cost", op: Matview.MatMax(field: "cost"))
    ]
  )
  assert Matview.define_matview(s0_a, mv_def) is Ok((sa_init, _))
  assert Matview.define_matview(s0_b, mv_def) is Ok((sb_init, _))

  var sa = sa_init
  var sb = sb_init
  var seed = 424242
  var step = 1
  while step <= 200
    seed = lcg_next(seed)
    key = seed.floor_mod(25) + 1
    seed = lcg_next(seed)
    op = seed.floor_mod(4)
    seed = lcg_next(seed)
    dept_i = seed.floor_mod(4)
    seed = lcg_next(seed)
    cents = seed.floor_mod(5000) + 10

    sa = step_write(sa, orders, key, op, dept_i, cents)
    sb = step_write(sb, orders, key, op, dept_i, cents)

    # Refresh incrementally every 1..3 steps to test both single-tx and multi-tx batched diffs
    if step.floor_mod(2) == 0 or step == 200
      assert Matview.refresh_matview(sa, "dept_stats") is Ok((sa_refreshed, rep_inc))
      sa = sa_refreshed
      assert rep_inc.strategy == "incremental" or rep_inc.strategy == "noop"
      assert Matview.rebuild_matview(sb, "dept_stats") is Ok((sb_rebuilt, _))
      sb = sb_rebuilt

      assert Matview.query_matview(sa, "dept_stats", None) is Ok(qa)
      assert Matview.query_matview(sb, "dept_stats", None) is Ok(qb)
      assert qa.total_groups == qb.total_groups
      assert qa.rows == qb.rows
    end
    step += 1
  end
  assert Modb.verify(sa) is Ok(vr) and vr.page_count > 0
end

test "tx_apply_matview synchronous updates and crash-recovery stale pin fallback"
  assert Modb.open(Files.in_memory({}), "crash.modb") is Ok(s0)
  orders = Table.int_key[Json]("orders")
  mv_def = Matview.MatViewDef(
    name: "sync_mv",
    description: "In-tx maintained matview",
    source_bucket: "orders",
    group_by: "dept",
    aggregates: [
      Matview.MatAggSpec(alias: "cnt", op: Matview.MatCount),
      Matview.MatAggSpec(alias: "total", op: Matview.MatSum(field: "cost"))
    ]
  )
  assert Matview.define_matview(s0, mv_def) is Ok((s1, _))

  # Synchronous tx_apply_matview updates rows inside the data transaction itself
  tx0 = Modb.begin_write(s1)
  assert Table.put(tx0, orders, 1, Json.Object({"dept": "eng".to_json, "cost": Json.decimal(15.25)})) is
    Ok(tx1)
  assert Table.put(tx1, orders, 2, Json.Object({"dept": "eng".to_json, "cost": Json.decimal(4.75)})) is
    Ok(tx2)
  assert Matview.tx_apply_matview(tx2, "sync_mv") is Ok(tx3)
  assert Modb.commit(tx3) is Ok(s2)

  assert Matview.query_matview(s2, "sync_mv", None) is Ok(q_immediate)
  assert q_immediate.returned_groups == 1
  row0 = q_immediate.rows.first or Json.Object({})
  assert row0.int_at("cnt") == Some(2)
  assert row0.path("total") == Some(Json.decimal(20.0))

  # Next refresh realigns pin without double-counting committed rows!
  assert Matview.refresh_matview(s2, "sync_mv") is Ok((s3, rep_align))
  assert rep_align.strategy == "pin_align"
  assert Matview.query_matview(s3, "sync_mv", None) is Ok(q_after)
  assert q_after.rows == q_immediate.rows

  # Simulated crash / stale pin mismatch: write row 3 then move pin to an old txid behind last_txid
  tx4 = Modb.begin_write(s3)
  assert Table.put(tx4, orders, 3, Json.Object({"dept": "ops".to_json, "cost": Json.decimal(99.0)})) is
    Ok(tx5)
  assert Modb.commit(tx5) is Ok(s4)
  # Remove pin to simulate missing/stale pin state
  assert Modb.unpin_root(s4, "mv:sync_mv") is Ok(s5)
  assert Matview.refresh_matview(s5, "sync_mv") is Ok((s6, rep_recover))
  assert rep_recover.strategy == "rebuild" and rep_recover.group_count == 2
  assert Matview.query_matview(s6, "sync_mv", None) is Ok(q_rec)
  assert q_rec.returned_groups == 2
end

test "500-row ViewCatalog index planner slashes rows_scanned with identical rows and answer_hash"
  assert Modb.open(Files.in_memory({}), "plan500.modb") is Ok(s0)
  t0 = Time.parse("2026-11-26T12:00:00Z") or stop "time"
  dept_idx = Table.text_index[Int, Json]("items_dept_idx", fn(r) r.text_at("dept") or "" end)
  score_idx = Table.int_index[Int, Json]("items_score_idx", fn(r) r.int_at("score") or 0 end)
  tbl = Table.int_key[Json]("items").with_index(dept_idx).with_index(score_idx)

  tx0 = Modb.begin_write(s0)
  var tx = tx0
  var i = 1
  while i <= 500
    d = if i <= 8
      "vip"
    else if i <= 20
      "ml"
    else
      "bulk_#{i.floor_mod(10)}"
    end
    row = Json.Object({
      "id": Json.int(i),
      "dept": Json.String(d),
      "score": Json.int(i * 10),
      "secret_token": Json.String("sec-#{i}")
    })
    assert Table.put(tx, tbl, i, row) is Ok(nx)
    tx = nx
    i += 1
  end
  assert Modb.commit(tx) is Ok(s1)

  proj = fn(r)
    {"id": r.get("id") or Json.Null, "dept": r.get("dept") or Json.Null, "score": r.get("score") or
      Json.Null}
  end
  vdef = Views.ViewDef(
    name: "items_view",
    description: "500-row view",
    source_buckets: ["items"],
    fields: [
      Views.ViewField(name: "id", field_type: "int", description: "id"),
      Views.ViewField(name: "dept", field_type: "text", description: "dept"),
      Views.ViewField(name: "score", field_type: "int", description: "score")
    ],
    narrows: None,
    load: fn(s)
      all_r = try Table.all(s, tbl).map_error(fn(e) e.to_text end)
      Ok(all_r.map(fn(p) proj(p.1) end))
    end
  )
  cat_full = Views.with_view(Views.catalog(), vdef)
  cat_idx = Views.with_view_range_index(
    Views.with_view_eq_index(
      cat_full,
      "items_view",
      "dept",
      fn(s, jv)
        k = case jv
          Json.String(sv): sv
          Json.Null | Json.Boolean(_) | Json.Number(_) | Json.Array(_) | Json.Object(_): jv.to_text
        end
        rows = try Table.lookup(s, tbl, dept_idx, k).map_error(fn(e) e.to_text end)
        Ok(rows.map(fn(p) proj(p.1) end))
      end
    ),
    "items_view",
    "score",
    fn(s, jv)
      k = Json.Object({"v": jv}).int_at("v") or 0
      rows = try Table.lookup(s, tbl, score_idx, k).map_error(fn(e) e.to_text end)
      Ok(rows.map(fn(p) proj(p.1) end))
    end,
    fn(s, lo_opt, hi_opt, lo_inc, hi_inc)
      lo_k = case lo_opt
        Some(jv):
          case Json.Object({"v": jv}).int_at("v")
            Some(iv): Some(if lo_inc: iv else: iv + 1)
            None: None
          end
        None: None
      end
      hi_k = case hi_opt
        Some(jv):
          case Json.Object({"v": jv}).int_at("v")
            Some(iv): Some(if hi_inc: iv + 1 else: iv)
            None: None
          end
        None: None
      end
      rows = try Table.range_by(s, tbl, score_idx, lo_k, hi_k, 0).map_error(fn(e) e.to_text end)
      Ok(rows.map(fn(p) proj(p.1) end))
    end
  )

  # 1. PlanIndexEq: 8 rows scanned vs 500
  p_eq = Views.ReadProgram(
    view: "items_view",
    where_clause: Some(
      Views.And(
        preds: [
          Views.Gt(field: "score", value: Json.int(20)),
          Views.Eq(field: "dept", value: Json.String("vip"))
        ]
      )
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: Some(Views.SortSpec(field: "id", desc: false)),
    limit: None
  )
  assert Views.execute_read_program(s1, cat_full, p_eq, None, true, Views.default_limits(), t0) is
    Ok(res_eq_full)
  assert Views.execute_read_program(s1, cat_idx, p_eq, None, true, Views.default_limits(), t0) is
    Ok(res_eq_fast)
  assert res_eq_full.rows_scanned == 500 and res_eq_fast.rows_scanned == 8
  assert res_eq_fast.rows == res_eq_full.rows and res_eq_fast.answer_hash == res_eq_full.answer_hash

  # 2. PlanIndexInList: 20 rows scanned vs 500
  p_in = Views.ReadProgram(
    view: "items_view",
    where_clause: Some(
      Views.InList(field: "dept", values: [Json.String("vip"), Json.String("ml")])
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: Some(Views.SortSpec(field: "id", desc: false)),
    limit: None
  )
  assert Views.execute_read_program(s1, cat_full, p_in, None, true, Views.default_limits(), t0) is
    Ok(res_in_full)
  assert Views.execute_read_program(s1, cat_idx, p_in, None, true, Views.default_limits(), t0) is
    Ok(res_in_fast)
  assert res_in_full.rows_scanned == 500 and res_in_fast.rows_scanned == 20
  assert res_in_fast.rows == res_in_full.rows and res_in_fast.answer_hash == res_in_full.answer_hash

  # 3. PlanIndexRange: 10 rows scanned vs 500
  p_rng = Views.ReadProgram(
    view: "items_view",
    where_clause: Some(
      Views.And(
        preds: [
          Views.Gte(field: "score", value: Json.int(4910)),
          Views.Lte(field: "score", value: Json.int(5000))
        ]
      )
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: Some(Views.SortSpec(field: "id", desc: false)),
    limit: None
  )
  assert Views.execute_read_program(s1, cat_full, p_rng, None, true, Views.default_limits(), t0) is
    Ok(res_rng_full)
  assert Views.execute_read_program(s1, cat_idx, p_rng, None, true, Views.default_limits(), t0) is
    Ok(res_rng_fast)
  assert res_rng_full.rows_scanned == 500 and res_rng_fast.rows_scanned == 10
  assert res_rng_fast.rows == res_rng_full.rows and
    res_rng_fast.answer_hash == res_rng_full.answer_hash

  # 4. Hidden field gated statically even when indexed catalog is used
  p_bad = Views.ReadProgram(
    view: "items_view",
    where_clause: Some(Views.Eq(field: "secret_token", value: Json.String("sec-1"))),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert Views.execute_read_program(s1, cat_idx, p_bad, None, true, Views.default_limits(), t0) is
    Error(Views.FieldNotInView(view: "items_view", field: "secret_token", allowed: _))
end
