## Milestone 8 Verification Suite:
## - Test 1: Grant View & Release attenuation, hierarchical narrowing, widening denial, cascading revoke
## - Test 2: Static field gate (`FieldNotInView`), numeric-agg type check, and `ReadLimits` work budgets
## - Test 3: Expressive ad-hoc ReadPrograms (boolean preds, group_by, count/sum/min/max/avg, sort, limit)
## - Test 4: Approved k-anonymous Releases (`ReleaseThresholdBlocked` negative control) & `OnboardingManifest`
## - Test 5: CoW-diff incremental World read re-validation (`reads_skipped`, sound skip + `StaleRead` controls)
module TestViewsIncremental
use Json
use Modb.Grants
use Modb.Ledger
use Modb.Table
use Modb.Views
use Modb.World

struct JobRow
  id: Int
  team: Text
  title: Text
  status: Text
  cost_cents: Int
  owner: Option(Text)
end

struct NoteRow
  body: Text
end

fn jobs_table() : Table.Table(Int, JobRow)
  Table.int_key[JobRow]("jobs")
end

fn notes_table() : Table.Table(Text, NoteRow)
  Table.text_key[NoteRow]("notes")
end

fn demo_view_catalog() : Views.ViewCatalog
  jtbl = jobs_table()
  Views.catalog().with_view(
    Views.ViewDef(
      name: "jobs_full",
      description: "Full jobs including cost and owner",
      source_buckets: ["jobs"],
      fields: [
        Views.ViewField(name: "id", field_type: "int", description: "Job ID"),
        Views.ViewField(name: "team", field_type: "text", description: "Team"),
        Views.ViewField(name: "title", field_type: "text", description: "Title"),
        Views.ViewField(name: "status", field_type: "text", description: "Status"),
        Views.ViewField(name: "cost_cents", field_type: "int", description: "Cost in cents"),
        Views.ViewField(name: "owner", field_type: "text", description: "Assigned agent")
      ],
      narrows: None,
      load: fn(store)
        rows = try Table.all(store, jtbl).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            j = p.1
            owner_j = case j.owner
              Some(o): Json.String(o)
              None: Json.Null
            end
            {
              "id": Json.int(j.id),
              "team": Json.String(j.team),
              "title": Json.String(j.title),
              "status": Json.String(j.status),
              "cost_cents": Json.int(j.cost_cents),
              "owner": owner_j
            }
          end)
        )
      end
    )
  ).with_view(
    Views.ViewDef(
      name: "jobs_public",
      description: "Public jobs hiding cost_cents and owner",
      source_buckets: ["jobs"],
      fields: [
        Views.ViewField(name: "id", field_type: "int", description: "Job ID"),
        Views.ViewField(name: "team", field_type: "text", description: "Team"),
        Views.ViewField(name: "title", field_type: "text", description: "Title"),
        Views.ViewField(name: "status", field_type: "text", description: "Status")
      ],
      narrows: Some("jobs_full"),
      load: fn(store)
        rows = try Table.all(store, jtbl).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            j = p.1
            {
              "id": Json.int(j.id),
              "team": Json.String(j.team),
              "title": Json.String(j.title),
              "status": Json.String(j.status)
            }
          end)
        )
      end
    )
  ).with_release(
    Views.ReleaseDef(
      name: "team_cost_stats",
      description: "Team aggregate cost stats (k-anonymous min_group_size=2)",
      source_buckets: ["jobs"],
      min_group_size: 2,
      args_description: "{\"team\": \"sre\"}",
      run: fn(store, args)
        team_name = try args.text_at("team").or_fail("missing team")
        rows = try Table.all(store, jtbl).map_error(fn(e) e.to_text end)
        var cnt = 0
        var total = 0
        for (_k, j) in rows
          if j.team == team_name
            cnt += 1
            total += j.cost_cents
          end
        end
        avg = if cnt == 0: 0 else: total / cnt
        Ok((
          cnt,
          Json.Object({
            "team": Json.String(team_name),
            "count": Json.int(cnt),
            "total_cost_cents": Json.int(total),
            "avg_cost_cents": Json.int(avg)
          })
        ))
      end
    )
  ).with_action_doc("complete_job", "Mark a job done", "{\"id\": 1}").with_invariant_doc(
    "non_negative_cost",
    "Every job has cost_cents >= 0"
  )
end

fn seed_jobs_db(files: Files, t0: Time) : Ledger.Db
  sc = Ledger.schema(0).with_require_reason(false)
  assert Ledger.open(files, "m8.modb", sc, t0) is Ok(db0)
  jtbl = jobs_table()
  ntbl = notes_table()
  assert Ledger.write(
    db0,
    Ledger.WriteMeta(principal: "admin", action: "seed", reason: "seed jobs", at: t0),
    "seed 5 jobs + 1 note",
    Json.Null,
    fn(tx)
      t1 = try Table.put(
        tx,
        jtbl,
        1,
        JobRow(
          id: 1,
          team: "sre",
          title: "TLS rotation",
          status: "done",
          cost_cents: 1000,
          owner: Some("agent:alice")
        )
      )
      t2 = try Table.put(
        t1,
        jtbl,
        2,
        JobRow(
          id: 2,
          team: "sre",
          title: "DB failover drill",
          status: "open",
          cost_cents: 3000,
          owner: None
        )
      )
      t3 = try Table.put(
        t2,
        jtbl,
        3,
        JobRow(
          id: 3,
          team: "sre",
          title: "Backup restore test",
          status: "done",
          cost_cents: 2000,
          owner: Some("agent:bob")
        )
      )
      t4 = try Table.put(
        t3,
        jtbl,
        4,
        JobRow(
          id: 4,
          team: "ml",
          title: "Fine-tune reranker",
          status: "open",
          cost_cents: 9000,
          owner: Some("agent:ml-1")
        )
      )
      t5 = try Table.put(
        t4,
        jtbl,
        5,
        JobRow(
          id: 5,
          team: "core",
          title: "Compaction sweep",
          status: "done",
          cost_cents: 500,
          owner: None
        )
      )
      Table.put(t5, ntbl, "n1", NoteRow(body: "initial note"))
    end
  ) is
    Ok(db1)
  db1
end

test "M8 Test 1: Grant View & Release attenuation, widening denial, and cascading revocation"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  db1 = seed_jobs_db(files, t0)
  vcat = demo_view_catalog()
  narrows = Views.view_narrows_map(vcat)

  ## Root grant holds `jobs_full` + `team_cost_stats`
  assert Grants.issue_root_scoped(
    db1,
    Ledger.WriteMeta(principal: "admin", action: "issue_grant", reason: "root", at: t0),
    Grants.GrantSpec(
      id: "g-lead",
      principal: "agent:lead",
      allowed_actions: ["complete_job"],
      max_calls: 20,
      expires_at: t1
    ),
    Some(["jobs_full"]),
    Some(["team_cost_stats"])
  ) is
    Ok((db2, _))

  ## Narrowed delegation: `jobs_full` -> `jobs_public` (permitted via narrows hierarchy!)
  assert Grants.delegate_scoped(
    db2,
    Ledger.WriteMeta(principal: "agent:lead", action: "delegate_grant", reason: "narrow", at: t0),
    "g-lead",
    Grants.GrantSpec(
      id: "g-pub",
      principal: "agent:pub",
      allowed_actions: ["complete_job"],
      max_calls: 10,
      expires_at: t1
    ),
    Some(["jobs_public"]),
    None,
    narrows
  ) is
    Ok((db3, _))

  ## Negative control: `g-pub` CANNOT widen back up to `jobs_full`!
  assert Grants.delegate_scoped(
    db3,
    Ledger.WriteMeta(principal: "agent:pub", action: "delegate_grant", reason: "widen", at: t0),
    "g-pub",
    Grants.GrantSpec(
      id: "g-widen-view",
      principal: "agent:evil",
      allowed_actions: ["complete_job"],
      max_calls: 5,
      expires_at: t1
    ),
    Some(["jobs_full"]),
    None,
    narrows
  ) is
    Error(Grants.WideningDenied(field: "allowed_views", detail: _))

  ## Negative control: `g-pub` (no releases) CANNOT widen to add `team_cost_stats`!
  assert Grants.delegate_scoped(
    db3,
    Ledger.WriteMeta(principal: "agent:pub", action: "delegate_grant", reason: "widen rel", at: t0),
    "g-pub",
    Grants.GrantSpec(
      id: "g-widen-rel",
      principal: "agent:evil",
      allowed_actions: ["complete_job"],
      max_calls: 5,
      expires_at: t1
    ),
    Some(["jobs_public"]),
    Some(["team_cost_stats"]),
    narrows
  ) is
    Error(Grants.WideningDenied(field: "allowed_releases", detail: _))

  ## `g-lead` CAN read both `jobs_full` AND narrower `jobs_public`; `g-pub` CANNOT read `jobs_full`
  pub_q = Views.ReadProgram(
    view: "jobs_public",
    where_clause: None,
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  full_q = Views.ReadProgram(
    view: "jobs_full",
    where_clause: None,
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert Views.execute_read_program(
    Ledger.store(db3),
    vcat,
    pub_q,
    Some("g-lead"),
    false,
    Views.default_limits(),
    t0
  ) is
    Ok(_)
  assert Views.execute_read_program(
    Ledger.store(db3),
    vcat,
    full_q,
    Some("g-pub"),
    false,
    Views.default_limits(),
    t0
  ) is
    Error(Views.GrantFailure(Grants.ViewDenied(id: "g-pub", view: "jobs_full")))

  ## Revoking parent `g-lead` immediately blocks `g-pub` read programs (cascading revoke)!
  assert Grants.revoke(
    db3,
    Ledger.WriteMeta(principal: "admin", action: "revoke", reason: "contain", at: t0),
    "g-lead"
  ) is
    Ok((db4, _))
  assert Views.execute_read_program(
    Ledger.store(db4),
    vcat,
    pub_q,
    Some("g-pub"),
    false,
    Views.default_limits(),
    t0
  ) is
    Error(Views.GrantFailure(Grants.Revoked(id: "g-pub", revoked_ancestor: "g-lead")))
end

test "M8 Test 2: Static field gate, type check, and ReadLimits work budget enforcement"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  db1 = seed_jobs_db(files, t0)
  vcat = demo_view_catalog()

  ## Hidden field rejected statically in where, select, group_by, aggregate, and order_by
  for bad in [
    Views.ReadProgram(
      view: "jobs_public",
      where_clause: Some(Views.Gt(field: "cost_cents", value: Json.int(0))),
      select: None,
      group_by: None,
      aggregates: None,
      order_by: None,
      limit: None
    ),
    Views.ReadProgram(
      view: "jobs_public",
      where_clause: None,
      select: Some(["id", "owner"]),
      group_by: None,
      aggregates: None,
      order_by: None,
      limit: None
    ),
    Views.ReadProgram(
      view: "jobs_public",
      where_clause: None,
      select: None,
      group_by: Some("owner"),
      aggregates: Some([Views.AggSpec(alias: "n", op: Views.Count)]),
      order_by: None,
      limit: None
    ),
    Views.ReadProgram(
      view: "jobs_public",
      where_clause: None,
      select: None,
      group_by: None,
      aggregates: Some([Views.AggSpec(alias: "s", op: Views.Sum(field: "cost_cents"))]),
      order_by: None,
      limit: None
    ),
    Views.ReadProgram(
      view: "jobs_public",
      where_clause: None,
      select: None,
      group_by: None,
      aggregates: None,
      order_by: Some(Views.SortSpec(field: "cost_cents", desc: true)),
      limit: None
    )
  ]
    assert Views.execute_read_program(
      Ledger.store(db1),
      vcat,
      bad,
      None,
      true,
      Views.default_limits(),
      t0
    ) is
      Error(Views.FieldNotInView(view: "jobs_public", field: _, allowed: _))
  end

  ## Numeric aggregate on text field fails statically (`InvalidProgram`)
  bad_type = Views.ReadProgram(
    view: "jobs_public",
    where_clause: None,
    select: None,
    group_by: None,
    aggregates: Some([Views.AggSpec(alias: "bad", op: Views.Sum(field: "title"))]),
    order_by: None,
    limit: None
  )
  assert Views.execute_read_program(
    Ledger.store(db1),
    vcat,
    bad_type,
    None,
    true,
    Views.default_limits(),
    t0
  ) is
    Error(Views.InvalidProgram(reason: _))

  ## Work budget enforcement: tight `max_rows_scanned` and `max_ops` both abort cleanly
  scan_all = Views.ReadProgram(
    view: "jobs_public",
    where_clause: Some(Views.Eq(field: "team", value: Json.String("sre"))),
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert Views.execute_read_program(
    Ledger.store(db1),
    vcat,
    scan_all,
    None,
    true,
    Views.ReadLimits(max_rows_scanned: 2, max_ops: 1000, max_result_rows: 100),
    t0
  ) is
    Error(Views.WorkBudgetExceeded(metric: "rows_scanned", limit: 2))
  assert Views.execute_read_program(
    Ledger.store(db1),
    vcat,
    scan_all,
    None,
    true,
    Views.ReadLimits(max_rows_scanned: 100, max_ops: 3, max_result_rows: 100),
    t0
  ) is
    Error(Views.WorkBudgetExceeded(metric: "ops", limit: 3))
end

test "M8 Test 3: Ad-hoc ReadPrograms (preds, group_by, aggs, sort, limit) & provenance log"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  db1 = seed_jobs_db(files, t0)
  vcat = demo_view_catalog()

  ## Complex predicate: team in ["sre", "ml"] AND NOT status == "open" AND owner NotNull
  prog1 = Views.ReadProgram(
    view: "jobs_full",
    where_clause: Some(
      Views.And(
        preds: [
          Views.InList(field: "team", values: [Json.String("sre"), Json.String("ml")]),
          Views.Not(pred: Views.Eq(field: "status", value: Json.String("open"))),
          Views.NotNull(field: "owner")
        ]
      )
    ),
    select: Some(["id", "title", "cost_cents"]),
    group_by: None,
    aggregates: None,
    order_by: Some(Views.SortSpec(field: "cost_cents", desc: true)),
    limit: Some(10)
  )
  assert Views.execute_read_program_recorded(
    db1,
    vcat,
    prog1,
    "admin:lead",
    None,
    true,
    Views.default_limits(),
    t0
  ) is
    Ok((db2, r1, log1))
  assert r1.result_count == 2 and r1.rows_scanned == 5 and log1.seq == 1
  ## Descending by cost_cents: job #3 (2000c) then job #1 (1000c)
  first_row = r1.rows.first or stop "row 0"
  assert first_row.int_at("id") == Some(3)

  ## Grouped aggregates by `team`: count, sum, min, max, avg sorted by total desc
  prog2 = Views.ReadProgram(
    view: "jobs_full",
    where_clause: None,
    select: None,
    group_by: Some("team"),
    aggregates: Some([
      Views.AggSpec(alias: "cnt", op: Views.Count),
      Views.AggSpec(alias: "total", op: Views.Sum(field: "cost_cents")),
      Views.AggSpec(alias: "lo", op: Views.Min(field: "cost_cents")),
      Views.AggSpec(alias: "hi", op: Views.Max(field: "cost_cents")),
      Views.AggSpec(alias: "mean", op: Views.Avg(field: "cost_cents"))
    ]),
    order_by: Some(Views.SortSpec(field: "total", desc: true)),
    limit: Some(2)
  )
  assert Views.execute_read_program_recorded(
    db2,
    vcat,
    prog2,
    "admin:lead",
    None,
    true,
    Views.default_limits(),
    t0
  ) is
    Ok((db3, r2, log2))
  assert r2.result_count == 2 and log2.seq == 2
  top_team = r2.rows.first or stop "top team"
  assert top_team.text_at("team") == Some("ml") and top_team.int_at("total") == Some(9000)
  sre_team = r2.rows.get(1) or stop "second team"
  assert sre_team.text_at("team") == Some("sre") and
    sre_team.int_at("cnt") == Some(3) and
    sre_team.int_at("total") == Some(6000) and
    sre_team.int_at("lo") == Some(1000) and
    sre_team.int_at("hi") == Some(3000) and
    sre_team.int_at("mean") == Some(2000)

  assert Views.list_read_log(Ledger.store(db3), 10) is Ok(entries)
  assert entries.size == 2
end

test "M8 Test 4: Approved k-anonymous Releases & stateless agent OnboardingManifest"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  db1 = seed_jobs_db(files, t0)
  vcat = demo_view_catalog()

  assert Grants.issue_root_scoped(
    db1,
    Ledger.WriteMeta(principal: "admin", action: "issue_grant", reason: "analyst", at: t0),
    Grants.GrantSpec(
      id: "g-analyst",
      principal: "agent:analyst",
      allowed_actions: ["complete_job"],
      max_calls: 5,
      expires_at: t1
    ),
    Some(["jobs_public"]),
    Some(["team_cost_stats"])
  ) is
    Ok((db2, _))

  ## Cohort size 3 ("sre") >= 2 -> allowed!
  assert Views.execute_release_recorded(
    db2,
    vcat,
    "team_cost_stats",
    Json.Object({"team": Json.String("sre")}),
    "agent:analyst",
    Some("g-analyst"),
    false,
    t0
  ) is
    Ok((db3, rel, _))
  assert rel.cohort_size == 3 and rel.data.int_at("avg_cost_cents") == Some(2000)

  ## Negative control: cohort size 1 ("ml") < min_group_size 2 -> ReleaseThresholdBlocked!
  assert Views.execute_release(
    Ledger.store(db3),
    vcat,
    "team_cost_stats",
    Json.Object({"team": Json.String("ml")}),
    Some("g-analyst"),
    false,
    t0
  ) is
    Error(
      Views.ReleaseThresholdBlocked(release: "team_cost_stats", min_group_size: 2, actual_count: 1)
    )

  ## Onboarding manifest for `g-analyst` exposes ONLY `jobs_public` (4 fields, no `cost_cents`)
  assert Views.describe_for_caller(
    db3,
    vcat,
    "agent:analyst",
    "worker",
    false,
    [],
    Some("g-analyst"),
    Views.default_limits(),
    t0
  ) is
    Ok(manifest)
  assert manifest.allowed_views.size == 1
  v0 = manifest.allowed_views.first or stop "v0"
  assert v0.name == "jobs_public" and v0.fields.size == 4
  assert manifest.allowed_releases.size == 1 and manifest.invariants.size == 1
end

test "M8 Test 5: CoW-diff incremental World read re-validation (O(1) skips + StaleRead negative controls)"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  db1 = seed_jobs_db(files, t0)
  vcat = demo_view_catalog()
  jtbl = jobs_table()
  ntbl = notes_table()

  assert Grants.issue_root_scoped(
    db1,
    Ledger.WriteMeta(principal: "admin", action: "issue_grant", reason: "w", at: t0),
    Grants.GrantSpec(
      id: "g-w",
      principal: "agent:w",
      allowed_actions: ["mark_done", "set_note"],
      max_calls: 20,
      expires_at: t1
    ),
    Some(["jobs_public"]),
    None
  ) is
    Ok((db2, _))

  wcat = World.catalog().with_scoped_query(
    "get_job_status",
    ["jobs"],
    fn(tx, args)
      jid = try Json.from_json[Int](args).map_error(fn(e) e.to_text end)
      case Table.tx_get(tx, jtbl, jid)
        Ok(Some(j)): Ok(Json.String(j.status))
        Ok(None): Ok(Json.Null)
        Error(e): Error(e.to_text)
      end
    end
  ).with_scoped_query(
    "get_note",
    ["notes"],
    fn(tx, args)
      nid = try Json.from_json[Text](args).map_error(fn(e) e.to_text end)
      case Table.tx_get(tx, ntbl, nid)
        Ok(Some(n)): Ok(Json.String(n.body))
        Ok(None): Ok(Json.Null)
        Error(e): Error(e.to_text)
      end
    end
  ).with_action(
    "mark_done",
    fn(tx, args)
      jid = try Json.from_json[Int](args).map_error(fn(e) e.to_text end)
      cur = try Table.tx_get(tx, jtbl, jid).map_error(fn(e) e.to_text end)
      j = try cur.or_fail("missing job")
      var updated = j
      updated.status = "done"
      t_next = try Table.put(tx, jtbl, jid, updated).map_error(fn(e) e.to_text end)
      Ok((t_next, Json.String("done")))
    end
  ).with_action(
    "set_note",
    fn(tx, args)
      body = try Json.from_json[Text](args).map_error(fn(e) e.to_text end)
      t_next = try Table.put(tx, ntbl, "n1", NoteRow(body: body)).map_error(fn(e) e.to_text end)
      Ok((t_next, Json.String(body)))
    end
  )

  ## Case A: Zero external data drift (even with an intervening `_modb_read_log` commit!) -> BOTH reads skipped!
  assert World.open_world(db2, "w-zero-drift", "g-w", t0, t1) is Ok((db3, _))
  assert World.world_query(db3, wcat, "w-zero-drift", "get_job_status", Json.int(2), t0) is
    Ok((db4, _))
  assert World.world_call(db4, wcat, "w-zero-drift", "mark_done", Json.int(2), "done #2", t0) is
    Ok((db5, _))
  assert World.world_query(db5, wcat, "w-zero-drift", "get_job_status", Json.int(2), t0) is
    Ok((db6, _))
  ## An external agent logs a read in `_modb_read_log` — bookkeeping-only, must NOT defeat O(1) skip!
  assert Views.execute_read_program_recorded(
    db6,
    vcat,
    Views.ReadProgram(
      view: "jobs_public",
      where_clause: None,
      select: None,
      group_by: None,
      aggregates: None,
      order_by: None,
      limit: Some(1)
    ),
    "agent:w",
    Some("g-w"),
    false,
    Views.default_limits(),
    t0
  ) is
    Ok((db7, _, _))
  assert World.land_world(db7, wcat, "w-zero-drift", "land A", t0) is Ok((db8, lr_a))
  assert lr_a.reads_verified == 2 and lr_a.reads_skipped == 2

  ## Case B: Unrelated bucket ("notes") changes on main line while World read scoped ["jobs"] -> SKIPPED!
  assert World.open_world(db8, "w-disjoint", "g-w", t0, t1) is Ok((db9, _))
  assert World.world_query(db9, wcat, "w-disjoint", "get_job_status", Json.int(4), t0) is
    Ok((db10, _))
  assert World.world_call(db10, wcat, "w-disjoint", "mark_done", Json.int(4), "done #4", t0) is
    Ok((db11, _))
  ## Concurrent main-line write touches ONLY `notes` (not `jobs`)
  assert Ledger.write(
    db11,
    Ledger.WriteMeta(principal: "admin", action: "note", reason: "unrelated", at: t0),
    "update note",
    Json.Null,
    fn(tx) Table.put(tx, ntbl, "n1", NoteRow(body: "changed concurrently")) end
  ) is
    Ok(db12)
  assert World.land_world(db12, wcat, "w-disjoint", "land B", t0) is Ok((db13, lr_b))
  assert lr_b.reads_verified == 1 and lr_b.reads_skipped == 1

  ## Case C (Negative control): Main line modifies `notes` while World read `get_note` (["notes"]) -> StaleRead!
  assert World.open_world(db13, "w-stale", "g-w", t0, t1) is Ok((db14, _))
  assert World.world_query(db14, wcat, "w-stale", "get_note", Json.String("n1"), t0) is
    Ok((db15, _))
  assert World.world_call(db15, wcat, "w-stale", "set_note", Json.String("mine"), "edit", t0) is
    Ok((db16, _))
  assert Ledger.write(
    db16,
    Ledger.WriteMeta(principal: "admin", action: "note", reason: "conflict", at: t0),
    "conflicting note update",
    Json.Null,
    fn(tx) Table.put(tx, ntbl, "n1", NoteRow(body: "raced!")) end
  ) is
    Ok(db17)
  assert World.land_world(db17, wcat, "w-stale", "land C", t0) is
    Error((db18, World.StaleRead(query: "get_note", args: _, expected: _, actual: _)))

  ## Case D (Soundness control): External write to `notes` + World mutates `jobs` BEFORE reading `jobs`
  ## -> conservative soundness check sees `jobs` is dirty in `cur_tx` under non-empty ext drift -> re-executes!
  assert World.open_world(db18, "w-postcall-read", "g-w", t0, t1) is Ok((db19, _))
  assert World.world_call(db19, wcat, "w-postcall-read", "mark_done", Json.int(5), "m5", t0) is
    Ok((db20, _))
  assert World.world_query(db20, wcat, "w-postcall-read", "get_job_status", Json.int(5), t0) is
    Ok((db21, _))
  assert Ledger.write(
    db21,
    Ledger.WriteMeta(principal: "admin", action: "note", reason: "drift", at: t0),
    "external drift on notes",
    Json.Null,
    fn(tx) Table.put(tx, ntbl, "n1", NoteRow(body: "drift2")) end
  ) is
    Ok(db22)
  assert World.land_world(db22, wcat, "w-postcall-read", "land D", t0) is Ok((db23, lr_d))
  assert lr_d.reads_verified == 1 and lr_d.reads_skipped == 0

  ## Cumulative telemetry matches exact counts (4 verified, 3 skipped, 1 stale rejection)
  assert World.metrics(Ledger.store(db23)) is Ok(m)
  assert m.total_landed == 3 and
    m.total_reads_verified == 4 and
    m.total_reads_skipped == 3 and
    m.stale_read_rejections == 1
end
