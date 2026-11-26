## Milestone 10 Verification Suite:
## - Test 1: Key-level O(diff) World read skipping on the SAME bucket + StaleRead negative control.
## - Test 2: Half-open range [start_key, end_key) O(diff) World read skipping + range overlap control.
## - Test 3: Fairness PriorityTickets & starvation prevention (defer competing bucket writes,
##           allow disjoint bucket writes, clear on rescue, and bounded-TTL expiry anti-deadlock).
## - Test 4: Nested Child Worlds (multi-level Grandchild -> Child -> Parent -> Main, child-relative
##           world_diff, disjoint & conflicting sibling merges, cascading drop/revocation, and
##           Grant/World-level Replay excision).
## - Test 5: Standalone `Modb.Cli` end-to-end verification across inspect, verify --fast, worlds,
##           dump, audit, backup, export/restore, compact, and pin/file diffs.
module TestM10WorldsCli
use Json
use Modb
use Modb.Cli
use Modb.Grants{GrantSpec}
use Modb.Ledger{Schema, WriteMeta}
use Modb.Replay{ReplayCatalog}
use Modb.Table
use Modb.World

struct TaskRow
  title: Text
  status: Text
end

struct ItemRow
  val: Text
end

struct NoteRow
  body: Text
end

struct SetTaskArgs
  id: Int
  title: Text
  status: Text
end

struct KvArgs
  k: Text
  v: Text
end

fn tasks_table() : Table(Int, TaskRow)
  Table.int_key[TaskRow]("tasks")
end

fn items_table() : Table(Text, ItemRow)
  Table.text_key[ItemRow]("items")
end

fn notes_table() : Table(Text, NoteRow)
  Table.text_key[NoteRow]("notes")
end

fn app_schema() : Schema
  ttbl = tasks_table()
  Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "seed tasks 1, 2, 20", fn(tx)
      t1 = try Table.put(tx, ttbl, 1, TaskRow(title: "seed-1", status: "open"))
      t2 = try Table.put(t1, ttbl, 2, TaskRow(title: "seed-2", status: "open"))
      Table.put(t2, ttbl, 20, TaskRow(title: "seed-20", status: "open"))
    end)
  ).with_invariant(
    Ledger.row_invariant(
      "non_empty_task_title",
      ttbl,
      fn(id, r) if r.title.trim.empty?: Some("task ##{id} empty title") else: None end
    )
  )
end

fn app_world_catalog() : World.Catalog
  ttbl = tasks_table()
  itbl = items_table()
  ntbl = notes_table()
  World.catalog().with_key_scoped_query(
    "get_task",
    "tasks",
    fn(args)
      id = try args.int_at("id").or_fail("missing task id")
      Ok(Table.encode_int_key(id))
    end,
    fn(tx, args)
      id = try args.int_at("id").or_fail("missing task id")
      case Table.tx_get(tx, ttbl, id)
        Ok(Some(r)): Ok(r.to_json)
        Ok(None): Ok(Json.Null)
        Error(e): Error(e.to_text)
      end
    end
  ).with_range_scoped_query(
    "scan_team",
    "items",
    fn(args)
      pfx = try args.text_at("prefix").or_fail("missing prefix")
      Ok((Some(Table.encode_text_key(pfx)), Some(Table.encode_text_key("#{pfx}~"))))
    end,
    fn(tx, args)
      pfx = try args.text_at("prefix").or_fail("missing prefix")
      rows = try Table.tx_scan(
        tx,
        itbl,
        Some(pfx),
        Some("#{pfx}~"),
        0
      ).map_error(fn(e) e.to_text end)
      Ok(rows.map(fn(p) p.1.val end).to_json)
    end
  ).with_scoped_query(
    "get_note",
    ["notes"],
    fn(tx, args)
      k = try args.text_at("k").or_fail("missing note key")
      case Table.tx_get(tx, ntbl, k)
        Ok(Some(n)): Ok(Json.String(n.body))
        Ok(None): Ok(Json.Null)
        Error(e): Error(e.to_text)
      end
    end
  ).with_action(
    "set_task",
    fn(tx, args)
      a = try Json.decode[SetTaskArgs](Json.encode(args)).map_error(fn(e) e.to_text end)
      row = TaskRow(title: a.title, status: a.status)
      t1 = try Table.put(tx, ttbl, a.id, row).map_error(fn(e) e.to_text end)
      Ok((t1, row.to_json))
    end
  ).with_action(
    "set_item",
    fn(tx, args)
      a = try Json.decode[KvArgs](Json.encode(args)).map_error(fn(e) e.to_text end)
      row = ItemRow(val: a.v)
      t1 = try Table.put(tx, itbl, a.k, row).map_error(fn(e) e.to_text end)
      Ok((t1, row.to_json))
    end
  ).with_action(
    "set_note",
    fn(tx, args)
      a = try Json.decode[KvArgs](Json.encode(args)).map_error(fn(e) e.to_text end)
      row = NoteRow(body: a.v)
      t1 = try Table.put(tx, ntbl, a.k, row).map_error(fn(e) e.to_text end)
      Ok((t1, row.to_json))
    end
  )
end

fn app_replay_catalog() : ReplayCatalog
  ttbl = tasks_table()
  itbl = items_table()
  ntbl = notes_table()
  Replay.catalog().with_action(
    "set_task",
    fn(tx, args)
      a = try Json.decode[SetTaskArgs](Json.encode(args)).map_error(fn(e) e.to_text end)
      row = TaskRow(title: a.title, status: a.status)
      t1 = try Table.put(tx, ttbl, a.id, row).map_error(fn(e) e.to_text end)
      Ok((t1, row.to_json))
    end
  ).with_action(
    "set_item",
    fn(tx, args)
      a = try Json.decode[KvArgs](Json.encode(args)).map_error(fn(e) e.to_text end)
      row = ItemRow(val: a.v)
      t1 = try Table.put(tx, itbl, a.k, row).map_error(fn(e) e.to_text end)
      Ok((t1, row.to_json))
    end
  ).with_action(
    "set_note",
    fn(tx, args)
      a = try Json.decode[KvArgs](Json.encode(args)).map_error(fn(e) e.to_text end)
      row = NoteRow(body: a.v)
      t1 = try Table.put(tx, ntbl, a.k, row).map_error(fn(e) e.to_text end)
      Ok((t1, row.to_json))
    end
  )
end

test "1. Key-level O(diff) read skipping on same bucket + StaleRead negative control"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T02:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T03:00:00Z") or stop "t1"
  sc = app_schema()
  cat = app_world_catalog()
  ttbl = tasks_table()

  assert Ledger.open(files, "m10-key.modb", sc, t0) is Ok(db0)
  gm = WriteMeta(principal: "admin", action: "grant", reason: "init", at: t0)
  assert Grants.issue_root(
    db0,
    gm,
    GrantSpec(
      id: "g-all",
      principal: "agent:a",
      allowed_actions: ["set_task", "set_item", "set_note"],
      max_calls: 50,
      expires_at: t1
    )
  ) is
    Ok((db1, _))

  ## World A reads task #1 and updates task #1
  assert World.open_world(db1, "w-disjoint-key", "g-all", t0, t1) is Ok((db2, _))
  assert World.world_query(
    db2,
    cat,
    "w-disjoint-key",
    "get_task",
    Json.Object({"id": Json.int(1)}),
    t0
  ) is
    Ok((db3, _))
  assert World.world_call(
    db3,
    cat,
    "w-disjoint-key",
    "set_task",
    SetTaskArgs(id: 1, title: "updated-1", status: "done").to_json,
    "finish 1",
    t0
  ) is
    Ok((db4, _))

  ## Concurrent main-line write modifies task #2 in the SAME `tasks` bucket!
  wm = WriteMeta(principal: "admin", action: "ext_write", reason: "sibling row", at: t0)
  assert Ledger.write(db4, wm, "update task 2", Json.Null, fn(tx)
    Table.put(tx, ttbl, 2, TaskRow(title: "concurrent-2", status: "done"))
  end) is
    Ok(db5)

  assert World.land_world(db5, cat, "w-disjoint-key", "land disjoint key", t0) is Ok((db6, lr))
  assert lr.reads_verified == 1 and lr.reads_skipped == 1
  assert World.telemetry(Ledger.store(db6)) is Ok(telem)
  assert telem.key_level_reads_skipped == 1 and telem.bucket_level_reads_skipped == 0

  ## Negative control: Concurrent main-line write modifies the SAME key #1 -> StaleRead!
  assert World.open_world(db6, "w-conflict-key", "g-all", t0, t1) is Ok((db7, _))
  assert World.world_query(
    db7,
    cat,
    "w-conflict-key",
    "get_task",
    Json.Object({"id": Json.int(1)}),
    t0
  ) is
    Ok((db8, _))
  assert World.world_call(
    db8,
    cat,
    "w-conflict-key",
    "set_task",
    SetTaskArgs(id: 1, title: "stale-attempt", status: "done").to_json,
    "attempt",
    t0
  ) is
    Ok((db9, _))
  assert Ledger.write(db9, wm, "clobber task 1", Json.Null, fn(tx)
    Table.put(tx, ttbl, 1, TaskRow(title: "winner-1", status: "closed"))
  end) is
    Ok(db10)
  assert World.land_world(db10, cat, "w-conflict-key", "land conflict", t0) is
    Error((db11, World.StaleRead(query: "get_task", args: _, expected: _, actual: _)))
  assert Table.get(Ledger.store(db11), ttbl, 1) ==
    Ok(Some(TaskRow(title: "winner-1", status: "closed")))
end

test "2. Half-open range O(diff) skipping on same bucket + in-range overlap control"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T02:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T03:00:00Z") or stop "t1"
  sc = app_schema()
  cat = app_world_catalog()
  itbl = items_table()

  assert Ledger.open(files, "m10-range.modb", sc, t0) is Ok(db0)
  gm = WriteMeta(principal: "admin", action: "grant", reason: "init", at: t0)
  assert Grants.issue_root(
    db0,
    gm,
    GrantSpec(
      id: "g-rng",
      principal: "agent:r",
      allowed_actions: ["set_item"],
      max_calls: 20,
      expires_at: t1
    )
  ) is
    Ok((db1, _))
  assert Ledger.write(
    db1,
    WriteMeta(principal: "admin", action: "seed", reason: "seed items", at: t0),
    "seed teamA",
    Json.Null,
    fn(tx) Table.put(tx, itbl, "teamA/1", ItemRow(val: "a1")) end
  ) is
    Ok(db2)

  ## World scans [teamA/, teamA/~); concurrent write modifies `teamB/1` outside range!
  assert World.open_world(db2, "w-rng-ok", "g-rng", t0, t1) is Ok((db3, _))
  assert World.world_query(
    db3,
    cat,
    "w-rng-ok",
    "scan_team",
    Json.Object({"prefix": Json.String("teamA/")}),
    t0
  ) is
    Ok((db4, _))
  assert World.world_call(
    db4,
    cat,
    "w-rng-ok",
    "set_item",
    KvArgs(k: "teamA/2", v: "a2").to_json,
    "add a2",
    t0
  ) is
    Ok((db5, _))
  assert Ledger.write(
    db5,
    WriteMeta(principal: "admin", action: "ext", reason: "teamB edit", at: t0),
    "write teamB",
    Json.Null,
    fn(tx) Table.put(tx, itbl, "teamB/1", ItemRow(val: "b1")) end
  ) is
    Ok(db6)

  assert World.land_world(db6, cat, "w-rng-ok", "land disjoint range", t0) is Ok((db7, lr))
  assert lr.reads_skipped == 1
  assert World.telemetry(Ledger.store(db7)) is Ok(t) and t.key_level_reads_skipped == 1

  ## Negative control: Concurrent write inside [teamA/, teamA/~) -> re-executed -> StaleRead!
  assert World.open_world(db7, "w-rng-hit", "g-rng", t0, t1) is Ok((db8, _))
  assert World.world_query(
    db8,
    cat,
    "w-rng-hit",
    "scan_team",
    Json.Object({"prefix": Json.String("teamA/")}),
    t0
  ) is
    Ok((db9, _))
  assert World.world_call(
    db9,
    cat,
    "w-rng-hit",
    "set_item",
    KvArgs(k: "teamA/3", v: "a3").to_json,
    "add a3",
    t0
  ) is
    Ok((db10, _))
  assert Ledger.write(
    db10,
    WriteMeta(principal: "admin", action: "ext", reason: "teamA concurrent", at: t0),
    "write teamA/9",
    Json.Null,
    fn(tx) Table.put(tx, itbl, "teamA/9", ItemRow(val: "a9")) end
  ) is
    Ok(db11)
  assert World.land_world(db11, cat, "w-rng-hit", "land overlapping range", t0) is
    Error((_, World.StaleRead(query: "scan_team", args: _, expected: _, actual: _)))
end

test "3. Starvation fairness tickets defer overlapping competitors, unblock disjoint buckets, and expire safely"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T02:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T04:00:00Z") or stop "t1"
  sc = app_schema()
  cat = app_world_catalog()
  ttbl = tasks_table()

  assert Ledger.open(files, "m10-fair.modb", sc, t0) is Ok(db0)
  gm = WriteMeta(principal: "admin", action: "grant", reason: "init", at: t0)
  assert Grants.issue_root(
    db0,
    gm,
    GrantSpec(
      id: "g-slow",
      principal: "agent:slow",
      allowed_actions: ["set_task"],
      max_calls: 20,
      expires_at: t1
    )
  ) is
    Ok((db1, _))
  assert Grants.issue_root(
    db1,
    gm,
    GrantSpec(
      id: "g-fast",
      principal: "agent:fast",
      allowed_actions: ["set_task", "set_note"],
      max_calls: 20,
      expires_at: t1
    )
  ) is
    Ok((db2, _))

  ## Trigger 2 consecutive StaleRead rejections for agent:slow
  var db = db2
  for round in 0..2
    wid = "w-slow-#{round}"
    assert World.open_world(db, wid, "g-slow", t0, t1) is Ok((d1, _))
    assert World.world_query(d1, cat, wid, "get_task", Json.Object({"id": Json.int(1)}), t0) is
      Ok((d2, _))
    assert World.world_call(
      d2,
      cat,
      wid,
      "set_task",
      SetTaskArgs(id: 1, title: "slow-#{round}", status: "wip").to_json,
      "slow",
      t0
    ) is
      Ok((d3, _))
    assert Ledger.write(
      d3,
      WriteMeta(principal: "admin", action: "race", reason: "fast overwrite", at: t0),
      "clobber #{round}",
      Json.Null,
      fn(tx) Table.put(tx, ttbl, 1, TaskRow(title: "race-#{round}", status: "done")) end
    ) is
      Ok(d4)
    assert World.land_world(d4, cat, wid, "try", t0) is
      Error((d5, World.StaleRead(query: "get_task", args: _, expected: _, actual: _)))
    db = d5
  end
  assert World.starvation_count(Ledger.store(db), "agent:slow") == Ok(2)

  ## agent:slow claims a bounded 10s priority ticket on ["tasks"]
  assert World.open_world(db, "w-slow-2", "g-slow", t0, t1) is Ok((db3, _))
  assert World.world_query(db3, cat, "w-slow-2", "get_task", Json.Object({"id": Json.int(1)}), t0) is
    Ok((db4, _))
  assert World.world_call(
    db4,
    cat,
    "w-slow-2",
    "set_task",
    SetTaskArgs(id: 1, title: "rescued-slow", status: "done").to_json,
    "slow rescue",
    t0
  ) is
    Ok((db5, _))
  ## Negative control: threshold 5 > starvation 2 -> rejected
  assert World.claim_priority(db5, "w-slow-2", ["tasks"], 5, 10, t0) is
    Error(World.ActionRejected(action: "claim_priority", detail: _))
  assert World.claim_priority(db5, "w-slow-2", ["tasks"], 2, 10, t0) is Ok((db6, ticket))
  assert ticket.world_id == "w-slow-2"

  ## Fast competitor modifying `tasks` is deferred (stays Open & pinned); `notes` competitor lands!
  assert World.open_world(db6, "w-fast-tasks", "g-fast", t0, t1) is Ok((db7, _))
  assert World.world_call(
    db7,
    cat,
    "w-fast-tasks",
    "set_task",
    SetTaskArgs(id: 1, title: "racer", status: "done").to_json,
    "fast task",
    t0
  ) is
    Ok((db8, _))
  assert World.land_world_fair(db8, cat, "w-fast-tasks", "fair try", t0) is
    Ok((db9, World.DeferredByFairness(ticket: _, retry_after: _)))
  assert World.get_world(Ledger.store(db9), "w-fast-tasks") is Ok(Some(wft)) and
    wft.status is World.Open

  assert World.open_world(db9, "w-fast-notes", "g-fast", t0, t1) is Ok((db10, _))
  assert World.world_call(
    db10,
    cat,
    "w-fast-notes",
    "set_note",
    KvArgs(k: "n1", v: "disjoint ok").to_json,
    "fast note",
    t0
  ) is
    Ok((db11, _))
  assert World.land_world_fair(db11, cat, "w-fast-notes", "fair note", t0) is
    Ok((db12, World.LandedOk(result: _)))

  ## Starved world lands cleanly -> ticket cleared, starvation reset, deferred competitor lands next
  assert World.land_world_fair(db12, cat, "w-slow-2", "slow rescue land", t0) is
    Ok((db13, World.LandedOk(result: _)))
  assert World.starvation_count(Ledger.store(db13), "agent:slow") == Ok(0)
  assert World.list_priority_tickets(Ledger.store(db13), t0) == Ok([])
  assert World.telemetry(Ledger.store(db13)) is Ok(tl) and
    tl.fairness_tickets_issued == 1 and
    tl.fairness_deferrals == 1 and
    tl.starved_worlds_rescued == 1

  assert World.land_world_fair(db13, cat, "w-fast-tasks", "retry after ticket cleared", t0) is
    Ok((db14, World.LandedOk(result: _)))

  ## Anti-deadlock TTL expiry test: force starvation again, claim 5s ticket, verify expiry at t0+10s
  assert World.open_world(db14, "w-slow-exp0", "g-slow", t0, t1) is Ok((db15, _))
  assert World.world_query(
    db15,
    cat,
    "w-slow-exp0",
    "get_task",
    Json.Object({"id": Json.int(1)}),
    t0
  ) is
    Ok((db16, _))
  assert Ledger.write(
    db16,
    WriteMeta(principal: "admin", action: "race", reason: "bump", at: t0),
    "bump",
    Json.Null,
    fn(tx) Table.put(tx, ttbl, 1, TaskRow(title: "bump", status: "open")) end
  ) is
    Ok(db17)
  assert World.land_world(db17, cat, "w-slow-exp0", "stale", t0) is Error((db18, _))
  assert World.open_world(db18, "w-slow-ttl", "g-slow", t0, t1) is Ok((db19, _))
  assert World.claim_priority(db19, "w-slow-ttl", ["tasks"], 1, 5, t0) is Ok((db20, _))
  assert World.open_world(db20, "w-after-exp", "g-fast", t0, t1) is Ok((db21, _))
  assert World.world_call(
    db21,
    cat,
    "w-after-exp",
    "set_task",
    SetTaskArgs(id: 2, title: "after-ttl", status: "done").to_json,
    "after ttl",
    t0
  ) is
    Ok((db22, _))
  assert World.land_world_fair(db22, cat, "w-after-exp", "post expiry", t0 + 10.seconds) is
    Ok((_db23, World.LandedOk(result: _)))
end

test "4. Nested Child Worlds: multi-level delegation, diff isolation, sibling O(diff), revocation & Replay"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T02:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T03:00:00Z") or stop "t1"
  t_longer = Time.parse("2026-11-26T05:00:00Z") or stop "t_longer"
  sc = app_schema()
  cat = app_world_catalog()
  rcat = app_replay_catalog()

  assert Ledger.open(files, "m10-child.modb", sc, t0) is Ok(db0)
  gm = WriteMeta(principal: "admin", action: "grant", reason: "init", at: t0)
  assert Grants.issue_root(
    db0,
    gm,
    GrantSpec(
      id: "g-lead",
      principal: "agent:lead",
      allowed_actions: ["set_task", "set_item", "set_note"],
      max_calls: 20,
      expires_at: t1
    )
  ) is
    Ok((db1, _))
  assert Grants.delegate(
    db1,
    gm,
    "g-lead",
    GrantSpec(
      id: "g-h1",
      principal: "agent:h1",
      allowed_actions: ["set_task", "set_item"],
      max_calls: 8,
      expires_at: t1
    )
  ) is
    Ok((db2, _))
  assert Grants.delegate(
    db2,
    gm,
    "g-h1",
    GrantSpec(
      id: "g-gc1",
      principal: "agent:gc1",
      allowed_actions: ["set_item"],
      max_calls: 4,
      expires_at: t1
    )
  ) is
    Ok((db3, _))
  assert Grants.delegate(
    db3,
    gm,
    "g-lead",
    GrantSpec(
      id: "g-h2",
      principal: "agent:h2",
      allowed_actions: ["set_note", "set_task"],
      max_calls: 6,
      expires_at: t1
    )
  ) is
    Ok((db4, _))
  assert Grants.issue_root(
    db4,
    gm,
    GrantSpec(
      id: "g-outsider",
      principal: "agent:outsider",
      allowed_actions: ["set_task"],
      max_calls: 5,
      expires_at: t_longer
    )
  ) is
    Ok((db5, _))

  ## Open Parent P and stage uncommitted step #1
  assert World.open_world(db5, "P", "g-lead", t0, t1) is Ok((db6, _))
  assert World.world_call(
    db6,
    cat,
    "P",
    "set_task",
    SetTaskArgs(id: 1, title: "lead-task", status: "open").to_json,
    "lead step",
    t0
  ) is
    Ok((db7, _))

  ## Non-widening negative controls on open_child_world
  assert World.open_child_world(db7, "P", "bad-grant", "g-outsider", t0, t1) is
    Error(World.GrantFailure(Grants.WideningDenied(field: "parent_grant", detail: _)))
  assert World.open_child_world(db7, "P", "bad-ttl", "g-h1", t0, t_longer) is
    Error(World.GrantFailure(Grants.WideningDenied(field: "expires_at", detail: _)))

  ## Fork Helper 1 (C1) and Sibling 2 (C2) & Sibling 3 (C3) at P's fork point
  assert World.open_child_world(db7, "P", "C1", "g-h1", t0, t1) is Ok((db8, _))
  assert World.open_child_world(db8, "P", "C2", "g-h2", t0, t1) is Ok((db9, _))
  assert World.open_child_world(db9, "P", "C3", "g-h2", t0, t1) is Ok((db10, _))

  ## Guard: Parent cannot land directly while child open; child cannot skip parent via land_world
  assert World.land_world(db10, cat, "P", "early parent land", t0) is
    Error((_, World.WorldNotOpen(id: "P", status: "has_open_children")))
  assert World.land_world(db10, cat, "C1", "skip parent", t0) is
    Error((_, World.WorldNotOpen(id: "C1", status: _)))

  ## C1 sees P's uncommitted write, stages task #10, and isolates ONLY C1 in world_diff!
  assert World.world_query(db10, cat, "C1", "get_task", Json.Object({"id": Json.int(1)}), t0) is
    Ok((db11, ans_p)) and
    Json.encode(ans_p).contains?("lead-task")
  assert World.world_call(
    db11,
    cat,
    "C1",
    "set_task",
    SetTaskArgs(id: 10, title: "c1-task", status: "done").to_json,
    "c1 task",
    t0
  ) is
    Ok((db12, _))
  assert World.world_diff(db12, cat, "C1") ==
    Ok([World.BucketDiffSummary(bucket: "tasks", added: 1, removed: 0, modified: 0)])

  ## Fork Grandchild G1 from C1, stage item, land G1 -> C1, then C1 -> P
  assert World.open_child_world(db12, "C1", "G1", "g-gc1", t0, t1) is Ok((db13, _))
  assert World.world_call(
    db13,
    cat,
    "G1",
    "set_item",
    KvArgs(k: "teamA/gc", v: "from-g1").to_json,
    "gc item",
    t0
  ) is
    Ok((db14, _))
  assert World.land_child_world(db14, cat, "G1", "merge G1->C1", t0) is Ok((db15, gc_res))
  assert gc_res.calls_merged == 1
  assert World.land_child_world(db15, cat, "C1", "merge C1->P", t0) is Ok((db16, c1_res))
  assert c1_res.calls_merged == 2

  ## Disjoint sibling C2 reads key #20 (C1 modified #10 in same bucket) -> lands with O(diff) skip!
  assert World.world_query(db16, cat, "C2", "get_task", Json.Object({"id": Json.int(20)}), t0) is
    Ok((db17, _))
  assert World.world_call(
    db17,
    cat,
    "C2",
    "set_note",
    KvArgs(k: "note-h2", v: "from-h2").to_json,
    "h2 note",
    t0
  ) is
    Ok((db18, _))
  assert World.land_child_world(db18, cat, "C2", "merge C2->P", t0) is Ok((db19, c2_res))
  assert c2_res.reads_skipped == 1

  ## Conflicting sibling C3 read key #10 BEFORE C1 landed key #10 -> StaleRead rejected, P untouched!
  ## Note C3 forked before C1 landed, so its get_task(10) returned null while P now has "c1-task".
  assert World.world_call(
    db19,
    cat,
    "C3",
    "set_note",
    KvArgs(k: "note-h2-bad", v: "should-fail").to_json,
    "h2 bad",
    t0
  ) is
    Ok((db20, _))
  assert World.world_query(db20, cat, "C3", "get_task", Json.Object({"id": Json.int(10)}), t0) is
    Ok((db21, _))
  ## Wait: C3 forked at watermark 1 so build_speculative_tx sees watermark 1 (null), then C1 already merged!
  assert World.land_child_world(db21, cat, "C3", "merge C3->P", t0) is
    Error((db22, World.StaleRead(query: "get_task", args: _, expected: _, actual: _)))

  ## Landing Parent P atomically commits Lead + C1 + G1 + C2, updates child commit_txid & budgets
  assert World.land_world(db22, cat, "P", "land P to main", t0) is Ok((db23, p_res))
  assert p_res.calls_replayed == 4
  assert Table.get(Ledger.store(db23), tasks_table(), 1) ==
    Ok(Some(TaskRow(title: "lead-task", status: "open")))
  assert Table.get(Ledger.store(db23), tasks_table(), 10) ==
    Ok(Some(TaskRow(title: "c1-task", status: "done")))
  assert Table.get(Ledger.store(db23), items_table(), "teamA/gc") ==
    Ok(Some(ItemRow(val: "from-g1")))
  assert Table.get(Ledger.store(db23), notes_table(), "note-h2") ==
    Ok(Some(NoteRow(body: "from-h2")))
  assert World.get_world(Ledger.store(db23), "G1") is Ok(Some(g1_done)) and
    g1_done.status == World.Landed(commit_txid: p_res.commit_txid)
  assert World.get_world(Ledger.store(db23), "C1") is Ok(Some(c1_done)) and
    c1_done.status == World.Landed(commit_txid: p_res.commit_txid)
  assert Grants.get(Ledger.store(db23), "g-lead") is Ok(Some(gl_after)) and gl_after.used_calls == 4
  assert Grants.get(Ledger.store(db23), "g-gc1") is Ok(Some(gg_after)) and gg_after.used_calls == 1

  ## Replay selective-undo by helper grant (ExcludeGrant("g-h2")) removes ONLY C2's note!
  assert Replay.simulate_replay(
    db23,
    rcat,
    Replay.ExcludeGrant(grant_id: "g-h2"),
    "excise-h2",
    "Remove helper 2 child writes",
    "admin",
    t0
  ) is
    Ok((db_sim, prop))
  assert prop.summary.excluded == 1
  acc_meta = WriteMeta(principal: "admin", action: "accept_replay", reason: "clean h2", at: t0)
  assert Replay.accept_proposal(db_sim, "excise-h2", acc_meta) is Ok((db24, _))
  assert Table.get(Ledger.store(db24), notes_table(), "note-h2") == Ok(None)
  assert Table.get(Ledger.store(db24), tasks_table(), 10) ==
    Ok(Some(TaskRow(title: "c1-task", status: "done")))

  ## Cascading drop unpins all child pins + post-merge helper grant revocation blocks Parent land
  assert World.open_world(db24, "P-drop", "g-lead", t0, t1) is Ok((db25, _))
  assert World.open_child_world(db25, "P-drop", "C-drop", "g-h1", t0, t1) is Ok((db26, _))
  assert World.drop_world(db26, "P-drop") is Ok(db27)
  assert World.get_world(Ledger.store(db27), "C-drop") is Ok(Some(cdw)) and
    cdw.status is World.Dropped

  assert World.open_world(db27, "P-rev", "g-lead", t0, t1) is Ok((db28, _))
  assert World.open_child_world(db28, "P-rev", "C-rev", "g-h1", t0, t1) is Ok((db29, _))
  assert World.world_call(
    db29,
    cat,
    "C-rev",
    "set_task",
    SetTaskArgs(id: 30, title: "rev-task", status: "open").to_json,
    "c-rev call",
    t0
  ) is
    Ok((db30, _))
  assert World.land_child_world(db30, cat, "C-rev", "merge before revoke", t0) is Ok((db31, _))
  assert Grants.revoke(db31, gm, "g-h1") is Ok((db32, _))
  assert World.land_world(db32, cat, "P-rev", "should fail due to revoked child grant", t0) is
    Error((db33, World.GrantFailure(Grants.Revoked(id: "g-h1", revoked_ancestor: "g-h1"))))
  assert Modb.list_pins(Ledger.store(db33)) == Ok([])
end

test "5. Standalone Modb.Cli works across M10 Nested Child Worlds & compaction"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T02:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T03:00:00Z") or stop "t1"
  clock = Clock.fixed(t0)
  sc = app_schema()
  cat = app_world_catalog()

  assert Ledger.open(files, "prod.modb", sc, t0) is Ok(db0)
  gm = WriteMeta(principal: "admin", action: "grant", reason: "init", at: t0)
  assert Grants.issue_root(
    db0,
    gm,
    GrantSpec(
      id: "g-cli",
      principal: "agent:lead",
      allowed_actions: ["set_task"],
      max_calls: 10,
      expires_at: t1
    )
  ) is
    Ok((db1, _))
  assert World.open_world(db1, "w-parent", "g-cli", t0, t1) is Ok((db2, _))
  assert World.open_child_world(db2, "w-parent", "w-child", "g-cli", t0, t1) is Ok((db3, _))
  assert World.world_call(
    db3,
    cat,
    "w-child",
    "set_task",
    SetTaskArgs(id: 7, title: "cli-task", status: "done").to_json,
    "task 7",
    t0
  ) is
    Ok((db4, _))
  assert World.land_child_world(db4, cat, "w-child", "merge child", t0) is Ok((db5, _))
  assert World.land_world(db5, cat, "w-parent", "land parent", t0) is Ok((db6, _))
  assert Ledger.record_verify_checkpoint(db6, t0) is Ok((_db7, _))

  c_w = Console.fake()
  assert Cli.run_cli(["worlds", "prod.modb"], c_w, files, clock) == 0
  assert c_w.printed.join("\n").contains?("[child of w-parent")
  assert c_w.printed.join("\n").contains?("child_landed=1")

  c_i = Console.fake()
  assert Cli.run_cli(["inspect", "prod.modb"], c_i, files, clock) == 0
  assert c_i.printed.join("\n").contains?("bucket tasks: 4 entries")

  assert Cli.run_cli(["verify", "prod.modb"], Console.fake(), files, clock) == 0
  assert Cli.run_cli(["verify", "prod.modb", "--fast", "25"], Console.fake(), files, clock) ==
    0
  assert Cli.run_cli(["backup", "prod.modb", "prod-bak.modb"], Console.fake(), files, clock) ==
    0
  assert Cli.run_cli(["compact", "prod.modb"], Console.fake(), files, clock) == 0
  assert Cli.run_cli(["diff", "prod.modb", "prod-bak.modb"], Console.fake(), files, clock) ==
    0
  assert Ledger.open(files, "prod.modb", sc, t0) is Ok(reopened)
  assert Table.get(Ledger.store(reopened), tasks_table(), 7) ==
    Ok(Some(TaskRow(title: "cli-task", status: "done")))
end
