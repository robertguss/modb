## Comprehensive Milestone 17 verification suite:
## - Exhaustive order-preserving Decimal (10^-18..+/-10^20, scale normalization, negative rejection),
##   Bool, and null-escaped arbitrary-arity Tuple codecs
## - Table.MultiIndex diff-only B+Tree writes (`Modb.begin_write_tracked`), `count_by` / `count_by_multi`,
##   and keyset cursor pagination (`scan_page`, `range_page`, `range_page_multi`)
## - Modb.Dynindex Kanban group counts, Calendar date ranges, Decimal bounds, type-tag isolation,
##   reverse `DynRef` backlinks, 200-op deterministic differential fuzzing vs oracle, and crash atomicity
## - 500-row Modb.Views `PlanCompositeEq`, `PlanCompositeRange`, nested `And` residual filters,
##   `PlanIndexOrdered + Limit` early stop, and cursor pagination parity against unindexed full scans
module TestM17IndexesPlanner
use Json
use Modb
use Modb.Dynindex{DynEntry, DynVal}
use Modb.Errors{ModbError}
use Modb.Table
use Modb.Views

fn to_dec(s: Text) : Decimal
  s.to_decimal or stop "valid decimal"
end

fn jtext(jv: Json) : Text
  case jv
    Json.String(sv): sv
    Json.Null | Json.Boolean(_) | Json.Number(_) | Json.Array(_) | Json.Object(_): ""
  end
end

struct TagItem
  title: Text
  dept: Text
  amount: Decimal
  note: Text
  tags: List(Text)
end

struct WorkRow
  id: Int
  project: Text
  status: Text
  priority: Int
  amount: Decimal
  secret: Text
end

test "M17 Test 1: Decimal, Bool, and arbitrary-arity Tuple order preservation and negative controls"
  # 1. Bool order & malformed rejections
  assert Table.encode_bool_key(false) < Table.encode_bool_key(true)
  assert Table.decode_bool_key(Table.encode_bool_key(false)) == Ok(false)
  assert Table.decode_bool_key(Table.encode_bool_key(true)) == Ok(true)
  bad_b2 = (2).to_byte or stop "b2"
  assert Table.decode_bool_key(Bytes.from_list([bad_b2])) is Error(Table.DecodeKey(reason: _))
  assert Table.decode_bool_key(Bytes.empty) is Error(Table.DecodeKey(reason: _))

  # 2. Extreme signed Decimal ladder covering 10^-18 up to 128-bit boundaries
  ordered_strs = [
    "-170141183460469231731.687303715884105727",
    "-1000000000000.000001",
    "-100.5",
    "-10.25",
    "-1.000000000000000001",
    "-0.01",
    "-0.000001",
    "-0.000000000000000001",
    "0",
    "0.000000000000000001",
    "0.000001",
    "0.001",
    "0.1",
    "1",
    "9.9",
    "10.0",
    "99.999999999999999999",
    "100.0",
    "1000000000000.000001",
    "170141183460469231731.687303715884105727"
  ]
  for i in 0..ordered_strs.size
    cur = to_dec(ordered_strs.get(i) or "0")
    enc = Table.encode_decimal_key(cur)
    assert enc.size == 21
    assert Table.decode_decimal_key(enc) == Ok(cur)
    if i + 1 < ordered_strs.size
      nxt = to_dec(ordered_strs.get(i + 1) or "0")
      assert cur < nxt
      assert enc < Table.encode_decimal_key(nxt)
    end
  end

  # Scale normalization & negative zero collapse
  assert Table.encode_decimal_key(to_dec("10.5")) == Table.encode_decimal_key(to_dec("10.5000"))
  assert Table.encode_decimal_key(to_dec("-0.0")) == Table.encode_decimal_key(to_dec("0.00"))

  # Malformed Decimal byte rejections
  assert Table.decode_decimal_key(Bytes.zeroed(20)) is Error(Table.DecodeKey(reason: _))
  b129 = (129).to_byte or stop "129"
  b0 = (0).to_byte or stop "0"
  b99 = (99).to_byte or stop "99"
  b127 = (127).to_byte or stop "127"
  var bad_sign = [b129]
  var neg_zero = [b127]
  for _j in 0..20
    bad_sign = bad_sign.append(b0)
    neg_zero = neg_zero.append(b99)
  end
  assert Table.decode_decimal_key(Bytes.from_list(bad_sign)) is Error(Table.DecodeKey(reason: _))
  assert Table.decode_decimal_key(Bytes.from_list(neg_zero)) is Error(Table.DecodeKey(reason: _))

  # 3. Arbitrary 4-tuple with embedded 0x00 and 0xFF bytes + prefix upper bounds
  bff = (255).to_byte or stop "255"
  b_a = (65).to_byte or stop "A"
  p0 = Bytes.from_list([b0, bff, b_a, b0])
  p1 = Table.encode_int_key(-999)
  p2 = Table.encode_decimal_key(to_dec("-42.125"))
  p3 = Table.encode_text_key("row-7")
  tup = Table.encode_tuple_key([p0, p1, p2, p3])
  assert Table.decode_tuple_key(tup) == Ok([p0, p1, p2, p3])

  (plo, phi) = Table.encode_tuple_prefix_bounds([p0, p1])
  assert tup >= plo and tup < phi
  after_tup = Table.encode_tuple_key([p0, Table.encode_int_key(-998), p2, p3])
  assert not (after_tup < phi)
end

test "M17 Test 2: Table.MultiIndex diff-only B+Tree writes, count_by, and keyset pagination"
  files = Files.in_memory({})
  assert Modb.open(files, "m17-multi.modb") is Ok(s0)

  by_tags = Table.text_multi_index[Int, TagItem]("titems_tags", fn(r) r.tags end)
  by_dept_amt = Table.composite_index[Text, Decimal, Int, TagItem](
    "titems_dept_amt",
    Table.text_codec(),
    Table.decimal_codec(),
    fn(r) (r.dept, r.amount) end
  )
  tbl = Table.int_key[TagItem]("titems").with_multi_index(by_tags).with_index(by_dept_amt)

  assert Table.write_tx(
    s0,
    fn(tx)
      t1 = try Table.put(
        tx,
        tbl,
        1,
        TagItem(
          title: "Alpha",
          dept: "ops",
          amount: to_dec("25.50"),
          note: "initial",
          tags: ["urgent", "sec", "db", "sync", "m17"]
        )
      )
      t2 = try Table.put(
        t1,
        tbl,
        2,
        TagItem(
          title: "Beta",
          dept: "ops",
          amount: to_dec("10.00"),
          note: "n2",
          tags: ["db", "planner"]
        )
      )
      t3 = try Table.put(
        t2,
        tbl,
        3,
        TagItem(
          title: "Gamma",
          dept: "ops",
          amount: to_dec("40.00"),
          note: "n3",
          tags: ["db", "ui"]
        )
      )
      t4 = try Table.put(
        t3,
        tbl,
        4,
        TagItem(
          title: "Delta",
          dept: "eng",
          amount: to_dec("5.25"),
          note: "n4",
          tags: ["sync", "rust"]
        )
      )
      Table.put(
        t4,
        tbl,
        5,
        TagItem(
          title: "Epsilon",
          dept: "eng",
          amount: to_dec("15.75"),
          note: "n5",
          tags: ["db", "m17"]
        )
      )
    end
  ) is
    Ok(s1)

  # Unindexed field update performs ZERO index bucket writes/deletes!
  tx_noop = Modb.begin_write_tracked(s1)
  assert Table.put(
    tx_noop,
    tbl,
    1,
    TagItem(
      title: "Alpha",
      dept: "ops",
      amount: to_dec("25.50"),
      note: "updated-note-only",
      tags: ["urgent", "sec", "db", "sync", "m17"]
    )
  ) is
    Ok(tx_noop_done)
  assert Modb.tx_touched_puts(tx_noop_done, "titems_tags").empty?
  assert Modb.tx_touched_deletes(tx_noop_done, "titems_tags").empty?
  assert Modb.tx_touched_puts(tx_noop_done, "titems_dept_amt").empty?
  assert Modb.tx_touched_deletes(tx_noop_done, "titems_dept_amt").empty?
  assert Modb.commit(tx_noop_done) is Ok(s2)

  # Swap 1 of 5 tags ("sec" -> "v09"): strictly 1 put + 1 delete in `titems_tags`
  tx_swap = Modb.begin_write_tracked(s2)
  assert Table.put(
    tx_swap,
    tbl,
    1,
    TagItem(
      title: "Alpha",
      dept: "ops",
      amount: to_dec("25.50"),
      note: "updated-note-only",
      tags: ["urgent", "v09", "db", "sync", "m17"]
    )
  ) is
    Ok(tx_swap_done)
  assert Modb.tx_touched_puts(tx_swap_done, "titems_tags").size == 1
  assert Modb.tx_touched_deletes(tx_swap_done, "titems_tags").size == 1
  assert Modb.commit(tx_swap_done) is Ok(s3)

  assert Table.count_by_multi(s3, by_tags, "db") == Ok(4)
  assert Table.count_by_multi(s3, by_tags, "sec") == Ok(0)
  assert Table.count_by_multi(s3, by_tags, "v09") == Ok(1)
  assert Table.count_by(s3, by_dept_amt, ("ops", to_dec("25.50"))) == Ok(1)

  # Full `scan_page` traversal (page_size = 2) equals `Table.all`
  var seen_pk = []
  var cur_pk = None
  for _step in 0..10
    assert Table.scan_page(s3, tbl, None, None, 2, cur_pk) is Ok(pg)
    for (k, _v) in pg.items
      seen_pk = seen_pk.append(k)
    end
    cur_pk = pg.next_cursor
    break if not pg.has_more
  end
  assert seen_pk == [1, 2, 3, 4, 5]

  # `range_page_multi` over ["db", "db\u{10ffff}") returns items 1, 2, 3, 5 cleanly in 2-item pages
  var db_ids = []
  var cur_tag = None
  for _step in 0..10
    assert Table.range_page_multi(s3, tbl, by_tags, Some("db"), Some("dc"), 2, cur_tag) is Ok(pg)
    for (k, _v) in pg.items
      db_ids = db_ids.append(k)
    end
    cur_tag = pg.next_cursor
    break if not pg.has_more
  end
  assert db_ids == [1, 2, 3, 5]

  # Bad cursor rejected
  assert Table.scan_page(s3, tbl, None, None, 2, Some("!!!bad")) is
    Error(Table.DecodeKey(reason: _))
  assert Modb.verify(s3) is Ok(_)
end

fn oracle_record(oracle: Map(Text, List(DynEntry)), row_id: Text, entries: List(DynEntry)) : Map(
  Text,
  List(DynEntry)
)
  if entries.empty?
    oracle.remove(row_id)
  else
    oracle.set(row_id, entries)
  end
end

fn oracle_lookup_status(oracle: Map(Text, List(DynEntry)), want_status: Text) : List(Text)
  var ids = []
  for (rid, entries) in oracle
    if entries.any?(fn(e) e.prop_id == "status" and e.value == DynText(want_status) end)
      var pos = 0
      while pos < ids.size and (ids.get(pos) or "") < rid
        pos += 1
      end
      ids = ids.take(pos).append(rid).concat(ids.drop(pos))
    end
  end
  ids
end

test "M17 Test 3: Modb.Dynindex Kanban/Calendar/Backlinks, 200-op differential fuzzing & crash atomicity"
  files = Files.in_memory({})
  assert Modb.open(files, "m17-dyn.modb") is Ok(s0)
  idx = Dynindex.default_dyn_index("vlm_cells")

  # Seed db1 + db2 with mixed schemas, dates, negative/positive Decimals, and DynRef backlinks
  tx0 = Modb.begin_write(s0)
  r1 = [
    DynEntry(prop_id: "status", value: DynText("backlog")),
    DynEntry(prop_id: "due", value: DynDate("2026-11-24")),
    DynEntry(prop_id: "cost", value: DynDecimal(to_dec("-12.50"))),
    DynEntry(prop_id: "parent", value: DynRef("proj:core"))
  ]
  r2 = [
    DynEntry(prop_id: "status", value: DynText("doing")),
    DynEntry(prop_id: "due", value: DynDate("2026-11-27")),
    DynEntry(prop_id: "cost", value: DynDecimal(to_dec("99.95"))),
    DynEntry(prop_id: "parent", value: DynRef("proj:core"))
  ]
  r3_db2 = [
    DynEntry(prop_id: "status", value: DynText("doing")),
    DynEntry(prop_id: "parent", value: DynRef("proj:core"))
  ]
  assert Dynindex.tx_update_row(tx0, idx, "db1", "r1", [], r1) is Ok(tx1)
  assert Dynindex.tx_update_row(tx1, idx, "db1", "r2", [], r2) is Ok(tx2)
  assert Dynindex.tx_update_row(tx2, idx, "db2", "r3", [], r3_db2) is Ok(tx3)
  assert Modb.commit(tx3) is Ok(s1)

  # Check Decimal negative < positive range and date window isolation
  assert Dynindex.range_scan(
    s1,
    idx,
    "db1",
    "cost",
    Some(DynDecimal(to_dec("-20.0"))),
    Some(DynDecimal(to_dec("0.0"))),
    true,
    false,
    0
  ) ==
    Ok(["r1"])
  assert Dynindex.range_scan(
    s1,
    idx,
    "db1",
    "due",
    Some(DynDate("2026-11-26")),
    Some(DynDate("2026-11-30")),
    true,
    true,
    0
  ) ==
    Ok(["r2"])
  assert Dynindex.lookup_backlinks(s1, idx, "proj:core", None, None) ==
    Ok([("db1", "parent", "r1"), ("db1", "parent", "r2"), ("db2", "parent", "r3")])
  assert Dynindex.range_scan(
    s1,
    idx,
    "db1",
    "cost",
    Some(DynInt(1)),
    Some(DynDecimal(to_dec("2.0"))),
    true,
    true,
    0
  ) is
    Error(Table.Storage(InvalidArgument(reason: _)))

  # Delete db2 namespace: leaves db1 forward + reverse entries intact
  tx_del_ns = Modb.begin_write(s1)
  assert Dynindex.tx_delete_namespace(tx_del_ns, idx, "db2") is Ok(tx_del_ns2)
  assert Modb.commit(tx_del_ns2) is Ok(s2)
  assert Dynindex.lookup_backlinks(s2, idx, "proj:core", None, None) ==
    Ok([("db1", "parent", "r1"), ("db1", "parent", "r2")])

  # Crash atomicity: simulate torn commit mid-Dynindex update (phase 1 & phase 2) -> never torn!
  rng = Random.seeded(91)
  tx_crash = Modb.begin_write(s2)
  assert Dynindex.tx_delete_row(tx_crash, idx, "db1", "r1", r1) is Ok(tx_crash2)
  assert Modb.commit_and_crash(tx_crash2, 1, rng) is Ok(c1)
  assert Modb.open_disk(c1) is Ok(s_rec1)
  assert Dynindex.count_exact(s_rec1, idx, "db1", "status", DynText("backlog")) == Ok(1)
  assert Dynindex.lookup_backlinks(s_rec1, idx, "proj:core", Some("db1"), None) ==
    Ok([("db1", "parent", "r1"), ("db1", "parent", "r2")])
  assert Modb.verify(s_rec1) is Ok(_)
  assert Modb.commit_and_crash(tx_crash2, 2, rng) is Ok(c2)
  assert Modb.open_disk(c2) is Ok(s_rec2)
  assert Modb.verify(s_rec2) is Ok(_)
  s_rec = s2

  # 200-op deterministic differential fuzzing on fresh namespace `fuzz`
  var store = s_rec
  var oracle = {}
  statuses = ["backlog", "doing", "review", "done"]
  targets = ["t:0", "t:1", "t:2", "t:3"]
  for step in 0..200
    rid_idx = (step * 7 + 3) % 18
    rid = if rid_idx < 10: "r0#{rid_idx}" else: "r#{rid_idx}"
    old_e = oracle.get(rid) or []
    do_del? = (step % 5 == 4) and (not old_e.empty?)
    new_e = if do_del?
      []
    else
      st = statuses.get((step * 3 + rid_idx) % 4) or "backlog"
      tgt = targets.get((step + rid_idx) % 4) or "t:0"
      [
        DynEntry(prop_id: "status", value: DynText(st)),
        DynEntry(prop_id: "score", value: DynInt((step * 17) - 500)),
        DynEntry(prop_id: "parent", value: DynRef(tgt))
      ]
    end
    wtx = Modb.begin_write(store)
    assert Dynindex.tx_update_row(wtx, idx, "fuzz", rid, old_e, new_e) is Ok(wtx2)
    assert Modb.commit(wtx2) is Ok(next_store)
    store = next_store
    oracle = oracle_record(oracle, rid, new_e)

    if step % 25 == 24
      for want_st in statuses
        assert Dynindex.lookup(store, idx, "fuzz", "status", DynText(want_st), 0) ==
          Ok(oracle_lookup_status(oracle, want_st))
      end
      assert Modb.verify(store) is Ok(_)
    end
  end
  assert Dynindex.count_groups(store, idx, "fuzz", "status") is Ok(grp_cnts)
  var sum_cnts = 0
  for gc in grp_cnts
    sum_cnts += gc.count
  end
  assert sum_cnts == oracle.size
end

test "M17 Test 4: 500-row Views composite pushdown, PlanIndexOrdered early-stop & cursor pagination parity"
  files = Files.in_memory({})
  assert Modb.open(files, "m17-views500.modb") is Ok(s0)
  by_proj_prio = Table.composite_index[Text, Int, Int, WorkRow](
    "work_proj_prio",
    Table.text_codec(),
    Table.int_codec(),
    fn(r) (r.project, r.priority) end
  )
  by_proj_st = Table.composite_index[Text, Text, Int, WorkRow](
    "work_proj_st",
    Table.text_codec(),
    Table.text_codec(),
    fn(r) (r.project, r.status) end
  )
  tbl = Table.int_key[WorkRow]("work_rows").with_index(by_proj_prio).with_index(by_proj_st)

  tx0 = Modb.begin_write(s0)
  var tx = tx0
  for i in 1..501
    proj = "p#{i % 10}"
    st = if i % 3 == 0: "done" else if i % 3 == 1: "open" else: "doing"
    row = WorkRow(
      id: i,
      project: proj,
      status: st,
      priority: i % 15,
      amount: to_dec("#{i % 50}.25"),
      secret: "sec-#{i}"
    )
    assert Table.put(tx, tbl, i, row) is Ok(ntx)
    tx = ntx
  end
  assert Modb.commit(tx) is Ok(s1)

  to_map = fn(pair)
    w = pair.1
    {
      "id": Json.int(w.id),
      "project": Json.String(w.project),
      "status": Json.String(w.status),
      "priority": Json.int(w.priority),
      "amount": w.amount.to_json
    }
  end
  vdef = Views.ViewDef(
    name: "work_public",
    description: "500-row public workload view",
    source_buckets: ["work_rows"],
    fields: [
      Views.ViewField(name: "id", field_type: "int", description: "id"),
      Views.ViewField(name: "project", field_type: "text", description: "project"),
      Views.ViewField(name: "status", field_type: "text", description: "status"),
      Views.ViewField(name: "priority", field_type: "int", description: "priority"),
      Views.ViewField(name: "amount", field_type: "decimal", description: "amount")
    ],
    narrows: None,
    load: fn(s)
      all_r = try Table.all(s, tbl).map_error(fn(e) e.to_text end)
      Ok(all_r.map(to_map))
    end
  )
  cat_full = Views.with_view(Views.catalog(), vdef)
  cat_fast = Views.with_view_ordered_index(
    Views.with_view_composite_range_index(
      Views.with_view_composite_eq_index(
        cat_full,
        "work_public",
        "proj_status",
        ["project", "status"],
        fn(s, vals)
          p = jtext(vals.get(0) or Json.Null)
          st = jtext(vals.get(1) or Json.Null)
          rows = try Table.lookup(s, tbl, by_proj_st, (p, st)).map_error(fn(e) e.to_text end)
          Ok(rows.map(to_map))
        end
      ),
      "work_public",
      "proj_priority",
      ["project", "priority"],
      fn(s, vals)
        p = jtext(vals.get(0) or Json.Null)
        pr = Json.Object({"v": vals.get(1) or Json.Null}).int_at("v") or 0
        rows = try Table.lookup(s, tbl, by_proj_prio, (p, pr)).map_error(fn(e) e.to_text end)
        Ok(rows.map(to_map))
      end,
      fn(s, eq_vals, lo_opt, hi_opt, lo_inc, hi_inc)
        p = jtext(eq_vals.get(0) or Json.Null)
        lo_i = case lo_opt
          Some(jv):
            iv = Json.Object({"v": jv}).int_at("v") or 0
            if lo_inc: iv else: iv + 1
          None: Table.int64_min
        end
        hi_i = case hi_opt
          Some(jv):
            iv = Json.Object({"v": jv}).int_at("v") or 0
            if hi_inc: iv + 1 else: iv
          None: Table.int64_max
        end
        rows = try Table.range_by(s, tbl, by_proj_prio, Some((p, lo_i)), Some((p, hi_i)), 0)
          .map_error(fn(e) e.to_text end)
        Ok(rows.map(to_map))
      end
    ),
    "work_public",
    "id",
    fn(s, lo_opt, hi_opt, lo_inc, hi_inc, lim)
      lo_i = lo_opt.map(fn(jv)
        iv = Json.Object({"v": jv}).int_at("v") or Table.int64_min
        if lo_inc: iv else: iv + 1
      end)
      hi_i = hi_opt.map(fn(jv)
        iv = Json.Object({"v": jv}).int_at("v") or Table.int64_max
        if hi_inc: iv + 1 else: iv
      end)
      rows = try Table.scan(s, tbl, lo_i, hi_i, lim).map_error(fn(e) e.to_text end)
      Ok(rows.map(to_map))
    end
  )

  t0 = Time.parse("2026-11-26T12:00:00Z") or stop "t0"

  # 1. Composite Eq + Decimal residual filter
  p1 = Views.ReadProgram(
    view: "work_public",
    where_clause: Some(
      Views.And(
        preds: [
          Views.Gt(field: "amount", value: to_dec("20.00").to_json),
          Views.Eq(field: "project", value: Json.String("p3")),
          Views.Eq(field: "status", value: Json.String("done"))
        ]
      )
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: Some(Views.SortSpec(field: "id", desc: false)),
    limit: None
  )
  assert Views.explain_read_program(cat_fast, p1) is Ok(ex1) and
    ex1.text_at("strategy") == Some("composite_eq") and
    ex1.bool_at("residual_filter") == Some(true)
  assert Views.execute_read_program(s1, cat_full, p1, None, true, Views.default_limits(), t0) is
    Ok(r1_full)
  assert Views.execute_read_program(s1, cat_fast, p1, None, true, Views.default_limits(), t0) is
    Ok(r1_fast)
  assert r1_fast.answer_hash == r1_full.answer_hash and r1_fast.rows_scanned < 25

  # 2. Composite Range (`project` Eq + `priority` range) + residual `status != "done"`
  p2 = Views.ReadProgram(
    view: "work_public",
    where_clause: Some(
      Views.And(
        preds: [
          Views.Eq(field: "project", value: Json.String("p4")),
          Views.Gte(field: "priority", value: Json.int(7)),
          Views.Lte(field: "priority", value: Json.int(8)),
          Views.Neq(field: "status", value: Json.String("done"))
        ]
      )
    ),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: Some(Views.SortSpec(field: "id", desc: false)),
    limit: None
  )
  assert Views.explain_read_program(cat_fast, p2) is Ok(ex2) and
    ex2.text_at("strategy") == Some("composite_range")
  assert Views.execute_read_program(s1, cat_full, p2, None, true, Views.default_limits(), t0) is
    Ok(r2_full)
  assert Views.execute_read_program(s1, cat_fast, p2, None, true, Views.default_limits(), t0) is
    Ok(r2_fast)
  assert r2_fast.answer_hash == r2_full.answer_hash and r2_fast.rows_scanned < 25

  # 3. Ordered index early stop: OrderBy(id, asc) Limit(7) scans 7 rows instead of 500!
  p3 = Views.ReadProgram(
    view: "work_public",
    where_clause: None,
    select: Some(["id", "project", "priority"]),
    group_by: None,
    aggregates: None,
    order_by: Some(Views.SortSpec(field: "id", desc: false)),
    limit: Some(7)
  )
  assert Views.explain_read_program(cat_fast, p3) is Ok(ex3) and
    ex3.text_at("strategy") == Some("index_ordered") and
    ex3.bool_at("order_pushdown") == Some(true)
  big_limits = Views.ReadLimits(max_rows_scanned: 10000, max_ops: 250000, max_result_rows: 500)
  assert Views.execute_read_program(s1, cat_full, p3, None, true, Views.default_limits(), t0) is
    Error(Views.WorkBudgetExceeded(metric: "ops", limit: 100000))
  assert Views.execute_read_program(s1, cat_full, p3, None, true, big_limits, t0) is Ok(r3_full)
  assert Views.execute_read_program(s1, cat_fast, p3, None, true, Views.default_limits(), t0) is
    Ok(r3_fast)
  assert r3_fast.rows == r3_full.rows and r3_fast.rows_scanned == 7

  # 4. Sorted with ties (`priority` asc, page_size=13) AND unsorted offset pagination match unpaged output!
  p4 = Views.ReadProgram(
    view: "work_public",
    where_clause: Some(Views.Eq(field: "project", value: Json.String("p5"))),
    select: Some(["id", "priority", "status"]),
    group_by: None,
    aggregates: None,
    order_by: Some(Views.SortSpec(field: "priority", desc: false)),
    limit: None
  )
  assert Views.execute_read_program(s1, cat_full, p4, None, true, Views.default_limits(), t0) is
    Ok(r4_unpaged)
  var p4_all = []
  var cur4 = None
  for _pg in 0..20
    assert Views.execute_read_program_paged(
      s1,
      cat_fast,
      p4,
      cur4,
      13,
      None,
      true,
      Views.default_limits(),
      t0
    ) is
      Ok(pg)
    for row in pg.result.rows
      p4_all = p4_all.append(row)
    end
    cur4 = pg.next_cursor
    break if not pg.has_more
  end
  assert p4_all == r4_unpaged.rows and p4_all.size == 50

  # Mismatched cursor direction rejected cleanly
  assert Views.execute_read_program_paged(
    s1,
    cat_fast,
    p4,
    Some(""),
    10,
    None,
    true,
    Views.default_limits(),
    t0
  ) is
    Error(Views.InvalidProgram(reason: _))
end
