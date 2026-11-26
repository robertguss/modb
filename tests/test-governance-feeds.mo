## Milestone 12 Integration, Negative-Control & Invariant Test Suite:
## Sensitivity/Taint Labels, Human-Reviewed Agent Proposals, and Reactive `txid`-Cursor Change Feeds.
module TestGovernanceFeeds
use Json
use Modb
use Modb.Export
use Modb.Feeds
use Modb.Fts
use Modb.Grants
use Modb.Ledger
use Modb.Policy
use Modb.Proposals
use Modb.Table
use Modb.Vec
use Modb.Views

struct BudgetRec
  id: Int
  dept: Text
  status: Text
  owner: Text
  secret_cap_cents: Int
end

test "M12.1: Sensitivity lattice, cascading parent clearance attenuation, views, releases, FTS/Vec & governed Export"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T16:30:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T20:00:00Z") or stop "t1"
  sc = Ledger.schema(0).with_require_reason(false)
  pub_tbl = Table.int_key[BudgetRec]("budgets")
  sec_tbl = Table.text_key[Text]("secrets")
  f_idx = Fts.index("gov_docs")
  v_idx = Vec.index("gov_docs", 4)

  ## Lattice ordering and case-insensitive parsing
  assert Policy.sensitivity_from_text("CoNfIdEnTiAl") is Some(Policy.Confidential)
  assert Policy.sensitivity_from_text("nope") is None
  assert Policy.rank(Policy.Public) < Policy.rank(Policy.Internal)
  assert Policy.rank(Policy.Internal) < Policy.rank(Policy.Confidential)
  assert Policy.rank(Policy.Confidential) < Policy.rank(Policy.Secret)

  assert Ledger.open(files, "gov.modb", sc, t0) is Ok(db0)
  m = Ledger.WriteMeta(principal: "admin:root", action: "seed", reason: "init", at: t0)
  assert Ledger.write(db0, m, "seed budgets, secrets & search docs", Json.Null, fn(tx)
    t_a = try Table.put(
      tx,
      pub_tbl,
      1,
      BudgetRec(id: 1, dept: "core", status: "active", owner: "alice", secret_cap_cents: 1000)
    )
    t_b = try Table.put(
      t_a,
      pub_tbl,
      2,
      BudgetRec(id: 2, dept: "core", status: "active", owner: "bob", secret_cap_cents: 2000)
    )
    t_c = try Table.put(
      t_b,
      pub_tbl,
      3,
      BudgetRec(id: 3, dept: "ml", status: "paused", owner: "carol", secret_cap_cents: 3000)
    )
    t_d = try Table.put(t_c, sec_tbl, "root_api_key", "sk_live_do_not_export")
    t_e = try Fts.tx_index_document(
      t_d,
      f_idx,
      Fts.DocumentInput(
        doc_id: "doc-pub",
        scope: "open",
        fields: [Fts.FieldInput(name: "body", text: "incident playbook escalation", weight: 2)]
      )
    ).map_error(fn(e) Table.DecodeKey(reason: Fts.to_text(e)) end)
    t_f = try Fts.tx_index_document(
      t_e,
      f_idx,
      Fts.DocumentInput(
        doc_id: "doc-sec",
        scope: "vault",
        fields: [Fts.FieldInput(name: "body", text: "incident escalation private key", weight: 2)]
      )
    ).map_error(fn(e) Table.DecodeKey(reason: Fts.to_text(e)) end)
    t_g = try Vec.tx_put_vector(
      t_f,
      v_idx,
      Vec.VectorInput(doc_id: "doc-pub", scope: "open", values: [1.0, 0.0, 0.0, 0.0])
    ).map_error(fn(e) Table.DecodeKey(reason: Vec.to_text(e)) end)
    Vec.tx_put_vector(
      t_g,
      v_idx,
      Vec.VectorInput(doc_id: "doc-sec", scope: "vault", values: [1.0, 0.0, 0.0, 0.0])
    ).map_error(fn(e) Table.DecodeKey(reason: Vec.to_text(e)) end)
  end) is
    Ok(db1)

  vcat = Views.catalog().with_view(
    Views.ViewDef(
      name: "budgets_full",
      description: "Full department budgets",
      source_buckets: ["budgets"],
      fields: [
        Views.ViewField(name: "id", field_type: "int", description: "id"),
        Views.ViewField(name: "dept", field_type: "text", description: "dept"),
        Views.ViewField(name: "status", field_type: "text", description: "status"),
        Views.ViewField(name: "owner", field_type: "text", description: "owner"),
        Views.ViewField(name: "secret_cap_cents", field_type: "int", description: "cap")
      ],
      narrows: None,
      load: fn(store)
        rows = try Table.all(store, pub_tbl).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            r = p.1
            {
              "id": Json.int(r.id),
              "dept": Json.String(r.dept),
              "status": Json.String(r.status),
              "owner": Json.String(r.owner),
              "secret_cap_cents": Json.int(r.secret_cap_cents)
            }
          end)
        )
      end
    )
  ).with_view(
    Views.ViewDef(
      name: "secret_vault_only",
      description: "Pure secret view",
      source_buckets: ["secrets"],
      fields: [
        Views.ViewField(name: "token", field_type: "text", description: "token")
      ],
      narrows: None,
      load: fn(_store) Ok([{"token": Json.String("hidden")}]) end
    )
  ).with_release(
    Views.ReleaseDef(
      name: "dept_budget_stats",
      description: "Department budget summary (k=3)",
      source_buckets: ["budgets"],
      min_group_size: 3,
      args_description: "{\"status\": optional}",
      run: fn(store, args)
        st_opt = args.text_at("status")
        rows = try Table.all(store, pub_tbl).map_error(fn(e) e.to_text end)
        var cnt = 0
        var sum = 0
        for (_k, r) in rows
          ok? = case st_opt
            Some(s): r.status == s
            None: true
          end
          if ok?
            cnt += 1
            sum += r.secret_cap_cents
          end
        end
        Ok((cnt, Json.Object({"count": Json.int(cnt), "total_cents": Json.int(sum)})))
      end
    )
  ).with_release(
    Views.ReleaseDef(
      name: "singleton_leak",
      description: "Unsafe k=1 release",
      source_buckets: ["budgets"],
      min_group_size: 1,
      args_description: "{}",
      run: fn(_store, _args) Ok((1, Json.Object({"leaked": Json.int(1000)}))) end
    )
  )

  pol = Policy.policy().with_default_clearance(Policy.Public).with_bucket_sensitivity(
    "budgets",
    Policy.Internal
  ).with_bucket_sensitivity("secrets", Policy.Secret).with_view_field_sensitivity(
    "budgets_full",
    "owner",
    Policy.Internal
  ).with_view_field_sensitivity("budgets_full", "secret_cap_cents", Policy.Confidential)
    .with_view_field_sensitivity("secret_vault_only", "token", Policy.Secret)
    .with_scope_sensitivity("open", Policy.Public).with_scope_sensitivity(
      "vault",
      Policy.Secret
    ).with_release_policy(
      "dept_budget_stats",
      Policy.ReleasePolicy(
        input_sensitivity: Policy.Confidential,
        output_sensitivity: Policy.Public,
        min_group_size: 3
      )
    ).with_release_policy(
      "singleton_leak",
      Policy.ReleasePolicy(
        input_sensitivity: Policy.Confidential,
        output_sensitivity: Policy.Public,
        min_group_size: 2
      )
    )

  ## Issue 3-level grant chain: g-org -> g-team -> g-leaf
  assert Grants.issue_root_scoped(
    db1,
    m,
    Grants.GrantSpec(
      id: "g-org",
      principal: "agent:org",
      allowed_actions: ["noop"],
      max_calls: 30,
      expires_at: t1
    ),
    Some(["budgets_full", "secret_vault_only"]),
    Some(["dept_budget_stats", "singleton_leak"])
  ) is
    Ok((db2, _))
  assert Grants.delegate_scoped(
    db2,
    m,
    "g-org",
    Grants.GrantSpec(
      id: "g-team",
      principal: "agent:team",
      allowed_actions: ["noop"],
      max_calls: 20,
      expires_at: t1
    ),
    Some(["budgets_full", "secret_vault_only"]),
    Some(["dept_budget_stats", "singleton_leak"]),
    Views.view_narrows_map(vcat)
  ) is
    Ok((db3, _))
  assert Grants.delegate_scoped(
    db3,
    m,
    "g-team",
    Grants.GrantSpec(
      id: "g-leaf",
      principal: "agent:leaf",
      allowed_actions: ["noop"],
      max_calls: 10,
      expires_at: t1
    ),
    Some(["budgets_full", "secret_vault_only"]),
    Some(["dept_budget_stats", "singleton_leak"]),
    Views.view_narrows_map(vcat)
  ) is
    Ok((db4, _))

  ## Set g-org=Confidential, g-team=Internal; trying to give g-leaf Confidential must fail!
  assert Policy.set_clearance(db4, pol, m, "g-org", Policy.Confidential, t0) is Ok((db5, _))
  assert Policy.set_clearance(db5, pol, m, "g-team", Policy.Internal, t0) is Ok((db6, _))
  assert Policy.set_clearance(db6, pol, m, "g-leaf", Policy.Confidential, t0) is
    Error(
      Policy.ClearanceWideningDenied(
        grant_id: "g-leaf",
        parent_id: "g-team",
        requested: Policy.Confidential,
        parent_clearance: Policy.Internal
      )
    )
  assert Policy.effective_clearance(Ledger.store(db6), pol, Some("g-leaf"), false) is
    Ok(Policy.Internal)

  ## Wildcard ReadProgram auto-redacts `secret_cap_cents`; all-secret view fails closed
  w_prog = Views.ReadProgram(
    view: "budgets_full",
    where_clause: None,
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert Policy.execute_read_program_governed_recorded(
    db6,
    vcat,
    pol,
    w_prog,
    "agent:leaf",
    Some("g-leaf"),
    false,
    Views.default_limits(),
    t0
  ) is
    Ok((db7, gres, _log))
  assert gres.redacted_fields == ["secret_cap_cents"]
  assert gres.result.result_count == 3
  assert not Json.encode(Json.Array(gres.result.rows)).contains?("secret_cap_cents")

  all_sec_p = Views.ReadProgram(
    view: "secret_vault_only",
    where_clause: None,
    select: None,
    group_by: None,
    aggregates: None,
    order_by: None,
    limit: None
  )
  assert Policy.execute_read_program_governed(
    Ledger.store(db7),
    vcat,
    pol,
    all_sec_p,
    Some("g-leaf"),
    false,
    Views.default_limits(),
    t0
  ) is
    Error(
      Policy.ClearanceDenied(
        subject: "view:secret_vault_only",
        required: Policy.Secret,
        actual: Policy.Internal
      )
    )

  ## Even COUNT(*) with no field names on an all-restricted view must fail closed!
  count_sec_p = Views.ReadProgram(
    view: "secret_vault_only",
    where_clause: None,
    select: None,
    group_by: None,
    aggregates: Some([Views.AggSpec(alias: "n", op: Views.Count)]),
    order_by: None,
    limit: None
  )
  assert Policy.execute_read_program_governed(
    Ledger.store(db7),
    vcat,
    pol,
    count_sec_p,
    Some("g-leaf"),
    false,
    Views.default_limits(),
    t0
  ) is
    Error(
      Policy.ClearanceDenied(
        subject: "view:secret_vault_only",
        required: Policy.Secret,
        actual: Policy.Internal
      )
    )

  ## Filter, sort & aggregate oracle attacks on `secret_cap_cents` are rejected BEFORE scanning
  for bad_prog in [
    Views.ReadProgram(
      view: "budgets_full",
      where_clause: Some(Views.Gt(field: "secret_cap_cents", value: Json.int(1500))),
      select: Some(["id"]),
      group_by: None,
      aggregates: None,
      order_by: None,
      limit: None
    ),
    Views.ReadProgram(
      view: "budgets_full",
      where_clause: None,
      select: Some(["id"]),
      group_by: None,
      aggregates: None,
      order_by: Some(Views.SortSpec(field: "secret_cap_cents", desc: true)),
      limit: None
    ),
    Views.ReadProgram(
      view: "budgets_full",
      where_clause: None,
      select: None,
      group_by: Some("dept"),
      aggregates: Some([Views.AggSpec(alias: "s", op: Views.Sum(field: "secret_cap_cents"))]),
      order_by: None,
      limit: None
    )
  ]
    assert Policy.execute_read_program_governed(
      Ledger.store(db7),
      vcat,
      pol,
      bad_prog,
      Some("g-leaf"),
      false,
      Views.default_limits(),
      t0
    ) is
      Error(
        Policy.ClearanceDenied(
          subject: "view:budgets_full.secret_cap_cents",
          required: Policy.Confidential,
          actual: Policy.Internal
        )
      )
  end

  ## Cascading parent downgrade: setting g-org -> Public immediately strips g-leaf from reading Internal `owner`!
  assert Policy.set_clearance(db7, pol, m, "g-org", Policy.Public, t0) is Ok((db8, _))
  assert Policy.effective_clearance(Ledger.store(db8), pol, Some("g-leaf"), false) is
    Ok(Policy.Public)
  assert Policy.execute_read_program_governed(
    Ledger.store(db8),
    vcat,
    pol,
    Views.ReadProgram(
      view: "budgets_full",
      where_clause: None,
      select: Some(["id", "owner"]),
      group_by: None,
      aggregates: None,
      order_by: None,
      limit: None
    ),
    Some("g-leaf"),
    false,
    Views.default_limits(),
    t0
  ) is
    Error(
      Policy.ClearanceDenied(
        subject: "view:budgets_full.owner",
        required: Policy.Internal,
        actual: Policy.Public
      )
    )

  ## k-Anonymous declassification Release: Public caller gets cohort=3 aggregate,
  ## cohort=2 (< 3) is blocked, and unsafe k=1 declassification is blocked statically!
  assert Policy.execute_release_governed(
    Ledger.store(db8),
    vcat,
    pol,
    "dept_budget_stats",
    Json.Object({}),
    Some("g-leaf"),
    false,
    t0
  ) is
    Ok(rel_ok)
  assert rel_ok.cohort_size == 3
  assert Policy.execute_release_governed(
    Ledger.store(db8),
    vcat,
    pol,
    "dept_budget_stats",
    Json.Object({"status": Json.String("active")}),
    Some("g-leaf"),
    false,
    t0
  ) is
    Error(
      Policy.ViewsFailure(
        Views.ReleaseThresholdBlocked(
          release: "dept_budget_stats",
          min_group_size: 3,
          actual_count: 2
        )
      )
    )
  assert Policy.execute_release_governed(
    Ledger.store(db8),
    vcat,
    pol,
    "singleton_leak",
    Json.Object({}),
    Some("g-leaf"),
    false,
    t0
  ) is
    Error(
      Policy.DeclassificationDenied(
        release: "singleton_leak",
        input_sensitivity: Policy.Confidential,
        output_sensitivity: Policy.Public,
        min_group_size: 2
      )
    )

  ## FTS, Vec & Hybrid governed search: g-leaf (Public) sees ONLY `doc-pub`, Admin sees both!
  assert Policy.search_fts_governed(
    Ledger.store(db8),
    pol,
    f_idx,
    "escalation",
    Fts.default_search_options(10),
    Some("g-leaf"),
    false
  ) is
    Ok(fts_pub)
  assert fts_pub.size == 1 and (fts_pub.first or stop "fh").doc_id == "doc-pub"
  assert Policy.search_vec_governed(
    Ledger.store(db8),
    pol,
    v_idx,
    [1.0, 0.0, 0.0, 0.0],
    Vec.default_search_options(10),
    Some("g-leaf"),
    false
  ) is
    Ok(vec_pub)
  assert vec_pub.size == 1 and (vec_pub.first or stop "vh").doc_id == "doc-pub"
  assert Policy.hybrid_search_governed(
    Ledger.store(db8),
    pol,
    f_idx,
    v_idx,
    "escalation",
    Some([1.0, 0.0, 0.0, 0.0]),
    Vec.default_hybrid_options(10),
    Some("g-leaf"),
    false
  ) is
    Ok(hyb_pub)
  assert hyb_pub.size == 1
  assert Policy.hybrid_search_governed(
    Ledger.store(db8),
    pol,
    f_idx,
    v_idx,
    "escalation",
    Some([1.0, 0.0, 0.0, 0.0]),
    Vec.default_hybrid_options(10),
    None,
    true
  ) is
    Ok(hyb_adm)
  assert hyb_adm.size == 2

  ## Governed Export: StrictFailClosed blocks g-leaf; RedactRestricted omits Internal/Secret buckets,
  ## passes SHA-256 verification, and imports cleanly without `secrets`!
  assert Policy.export_governed(
    Ledger.store(db8),
    pol,
    Policy.StrictFailClosed,
    false,
    Some("g-leaf"),
    false,
    t0
  ) is
    Error(Policy.ExportBlocked(bucket: "budgets", required: Policy.Internal, actual: Policy.Public))
  assert Policy.set_clearance(db8, pol, m, "g-org", Policy.Internal, t0) is Ok((db9, _))
  assert Policy.export_governed(
    Ledger.store(db9),
    pol,
    Policy.RedactRestricted,
    false,
    Some("g-leaf"),
    false,
    t0
  ) is
    Ok(exp_res)
  assert exp_res.redacted_buckets == ["secrets"]
  assert Export.verify_snapshot(exp_res.snapshot) is Ok(_)
  assert Export.import_db(files, "gov-redacted.modb", sc, exp_res.snapshot, t0) is Ok(redacted_db)
  assert Table.get(Ledger.store(redacted_db), sec_tbl, "root_api_key") is Ok(None)
  assert Ledger.verify_all(redacted_db) is Ok(_)
end

test "M12.2: Human-reviewed agent proposals, capability diffs, rejections/withdrawals & live materialization"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T16:40:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T20:00:00Z") or stop "t1"
  sc0 = Ledger.schema(0).with_require_reason(false)
  pub_tbl = Table.int_key[BudgetRec]("budgets")
  assert Ledger.open(files, "gov-prop.modb", sc0, t0) is Ok(db0)
  m = Ledger.WriteMeta(principal: "admin:lead", action: "seed", reason: "init", at: t0)
  assert Ledger.write(db0, m, "seed 3 budgets", Json.Null, fn(tx)
    t_a = try Table.put(
      tx,
      pub_tbl,
      1,
      BudgetRec(id: 1, dept: "core", status: "active", owner: "alice", secret_cap_cents: 1000)
    )
    t_b = try Table.put(
      t_a,
      pub_tbl,
      2,
      BudgetRec(id: 2, dept: "infra", status: "active", owner: "bob", secret_cap_cents: 2000)
    )
    Table.put(
      t_b,
      pub_tbl,
      3,
      BudgetRec(id: 3, dept: "ml", status: "paused", owner: "carol", secret_cap_cents: 3000)
    )
  end) is
    Ok(db1)

  assert Grants.issue_root_scoped(
    db1,
    m,
    Grants.GrantSpec(
      id: "g-agent",
      principal: "agent:analyst",
      allowed_actions: ["noop"],
      max_calls: 25,
      expires_at: t1
    ),
    Some(["budgets_full", "budgets_ops"]),
    Some(["dept_summary"])
  ) is
    Ok((db2, _))

  base_cat = Views.catalog().with_view(
    Views.ViewDef(
      name: "budgets_full",
      description: "Full budgets",
      source_buckets: ["budgets"],
      fields: [
        Views.ViewField(name: "id", field_type: "int", description: "id"),
        Views.ViewField(name: "dept", field_type: "text", description: "dept"),
        Views.ViewField(name: "status", field_type: "text", description: "status"),
        Views.ViewField(name: "secret_cap_cents", field_type: "int", description: "cap")
      ],
      narrows: None,
      load: fn(store)
        rows = try Table.all(store, pub_tbl).map_error(fn(e) e.to_text end)
        Ok(
          rows.map(fn(p)
            r = p.1
            {
              "id": Json.int(r.id),
              "dept": Json.String(r.dept),
              "status": Json.String(r.status),
              "secret_cap_cents": Json.int(r.secret_cap_cents)
            }
          end)
        )
      end
    )
  ).with_release(
    Views.ReleaseDef(
      name: "dept_summary",
      description: "k=3 summary",
      source_buckets: ["budgets"],
      min_group_size: 3,
      args_description: "{}",
      run: fn(store, _args)
        rows = try Table.all(store, pub_tbl).map_error(fn(e) e.to_text end)
        Ok((rows.size, Json.Object({"count": Json.int(rows.size)})))
      end
    )
  )
  base_pol = Policy.policy().with_view_field_sensitivity(
    "budgets_full",
    "secret_cap_cents",
    Policy.Confidential
  )

  ## Negative static controls: unknown field on ProposeView & internal bucket invariant rejected on submit
  assert Proposals.submit_proposal(
    db2,
    base_cat,
    base_pol,
    "bad-field",
    Proposals.ProposeView(
      spec: Proposals.DynamicViewSpec(
        name: "bad_v",
        description: "bad",
        base_view: "budgets_full",
        fields: ["id", "nonexistent"],
        field_sensitivities: {}
      )
    ),
    "agent:analyst",
    Some("g-agent"),
    "test",
    t0
  ) is
    Error(Proposals.InvalidProposal(reason: _))
  assert Proposals.submit_proposal(
    db2,
    base_cat,
    base_pol,
    "bad-internal",
    Proposals.ProposeInvariant(
      spec: Proposals.DynamicInvariantSpec(
        name: "bad_inv",
        description: "bad",
        bucket: "_modb_audit",
        rule: Proposals.FieldNonEmpty(field: "action")
      )
    ),
    "agent:analyst",
    Some("g-agent"),
    "test",
    t0
  ) is
    Error(Proposals.InvalidProposal(reason: _))

  ## 1. Submit & approve dynamic narrowed View (`budgets_ops`), Clearance upgrade, and Release policy
  assert Proposals.submit_proposal(
    db2,
    base_cat,
    base_pol,
    "prop-view-ops",
    Proposals.ProposeView(
      spec: Proposals.DynamicViewSpec(
        name: "budgets_ops",
        description: "Operational budget view",
        base_view: "budgets_full",
        fields: ["id", "dept", "status", "secret_cap_cents"],
        field_sensitivities: {}
      )
    ),
    "agent:analyst",
    Some("g-agent"),
    "create ops view",
    t0
  ) is
    Ok((db3, pv))
  assert pv.diff.narrows_only and pv.diff.risk_level == "low"
  assert Proposals.approve_proposal(
    db3,
    base_cat,
    base_pol,
    "prop-view-ops",
    "admin:lead",
    true,
    "approve ops view",
    t0
  ) is
    Ok((db4, _))

  assert Proposals.submit_proposal(
    db4,
    base_cat,
    base_pol,
    "prop-clr-up",
    Proposals.ProposeClearance(
      grant_id: "g-agent",
      target_clearance: Policy.Confidential,
      justification: "needs cap audit"
    ),
    "agent:analyst",
    Some("g-agent"),
    "request confidential clearance",
    t0
  ) is
    Ok((db5, pc))
  assert pc.diff.widens_access and pc.diff.risk_level == "high"
  assert Proposals.approve_proposal(
    db5,
    base_cat,
    base_pol,
    "prop-clr-up",
    "admin:lead",
    true,
    "grant confidential for audit",
    t0
  ) is
    Ok((db6, _))

  assert Proposals.submit_proposal(
    db6,
    base_cat,
    base_pol,
    "prop-rel-pol",
    Proposals.ProposeReleasePolicy(
      spec: Proposals.DynamicReleaseSpec(
        release_name: "dept_summary",
        description: "Declassify Confidential -> Public with k>=3",
        input_sensitivity: Policy.Confidential,
        output_sensitivity: Policy.Public,
        min_group_size: 3
      )
    ),
    "agent:analyst",
    Some("g-agent"),
    "register k-anon declassification",
    t0
  ) is
    Ok((db7, prp))
  assert prp.diff.declassifies and prp.diff.risk_level == "medium"
  assert Proposals.approve_proposal(
    db7,
    base_cat,
    base_pol,
    "prop-rel-pol",
    "admin:lead",
    true,
    "approve release policy",
    t0
  ) is
    Ok((db8, _))

  ## Live materialized catalog + policy executes dynamic view immediately with Confidential clearance!
  assert Proposals.materialize_catalog(Ledger.store(db8), base_cat) is Ok(live_cat)
  assert Proposals.materialize_policy(Ledger.store(db8), base_pol) is Ok(live_pol)
  assert live_pol.release_policies.has?("dept_summary")
  assert Policy.execute_read_program_governed(
    Ledger.store(db8),
    live_cat,
    live_pol,
    Views.ReadProgram(
      view: "budgets_ops",
      where_clause: Some(Views.Eq(field: "status", value: Json.String("active"))),
      select: Some(["id", "secret_cap_cents"]),
      group_by: None,
      aggregates: None,
      order_by: Some(Views.SortSpec(field: "id", desc: false)),
      limit: None
    ),
    Some("g-agent"),
    false,
    Views.default_limits(),
    t0
  ) is
    Ok(dyn_res)
  assert dyn_res.result.result_count == 2 and dyn_res.max_sensitivity_read is Policy.Confidential

  ## 2. Reject and withdraw lifecycle + AllowedValues invariant materialization
  assert Proposals.submit_proposal(
    db8,
    live_cat,
    live_pol,
    "prop-inv-status",
    Proposals.ProposeInvariant(
      spec: Proposals.DynamicInvariantSpec(
        name: "valid_status",
        description: "status must be active or paused",
        bucket: "budgets",
        rule: Proposals.AllowedValues(field: "status", values: ["active", "paused"])
      )
    ),
    "agent:analyst",
    Some("g-agent"),
    "enforce status enum",
    t0
  ) is
    Ok((db9, pinv))
  assert pinv.diff.existing_violations == 0
  assert Proposals.approve_proposal(
    db9,
    live_cat,
    live_pol,
    "prop-inv-status",
    "admin:lead",
    true,
    "approve status enum",
    t0
  ) is
    Ok((db10, _))

  assert Proposals.submit_proposal(
    db10,
    live_cat,
    live_pol,
    "prop-reject-me",
    Proposals.ProposeClearance(
      grant_id: "g-agent",
      target_clearance: Policy.Secret,
      justification: "give me secret"
    ),
    "agent:analyst",
    Some("g-agent"),
    "ask secret",
    t0
  ) is
    Ok((db11, _))
  assert Proposals.reject_proposal(db11, "prop-reject-me", "admin:lead", true, "denied", t0) is
    Ok((db12, rej_p))
  assert rej_p.status is Proposals.Rejected

  assert Proposals.submit_proposal(
    db12,
    live_cat,
    live_pol,
    "prop-withdraw-me",
    Proposals.ProposeClearance(
      grant_id: "g-agent",
      target_clearance: Policy.Public,
      justification: "drop clearance"
    ),
    "agent:analyst",
    Some("g-agent"),
    "withdraw test",
    t0
  ) is
    Ok((db13, _))
  assert Proposals.withdraw_proposal(
    db13,
    "prop-withdraw-me",
    "agent:other",
    false,
    "unauthorized",
    t0
  ) is
    Error(Proposals.ApprovalDenied(reason: _))
  assert Proposals.withdraw_proposal(
    db13,
    "prop-withdraw-me",
    "agent:analyst",
    false,
    "nevermind",
    t0
  ) is
    Ok((db14, wd_p))
  assert wd_p.status is Proposals.Withdrawn

  assert Proposals.list_proposals(Ledger.store(db14), Some(Proposals.Approved)) is Ok(app_list)
  assert app_list.size == 4
  assert Ledger.verify_all(db14) is Ok(_)

  ## Re-open DB with materialized dynamic invariants -> invalid status rejected at commit time!
  assert Proposals.apply_dynamic_invariants(Ledger.store(db14), sc0) is Ok(sc_live)
  assert Ledger.open(files, "gov-prop.modb", sc_live, t0) is Ok(db15)
  assert Ledger.write(db15, m, "bad status", Json.Null, fn(tx)
    Table.put(
      tx,
      pub_tbl,
      4,
      BudgetRec(id: 4, dept: "ops", status: "bogus", owner: "dan", secret_cap_cents: 100)
    )
  end) is
    Error(Ledger.InvariantViolation(name: "valid_status", detail: _))
  assert Ledger.write(db15, m, "good status", Json.Null, fn(tx)
    Table.put(
      tx,
      pub_tbl,
      4,
      BudgetRec(id: 4, dept: "ops", status: "active", owner: "dan", secret_cap_cents: 100)
    )
  end) is
    Ok(db16)
  assert Ledger.verify_all(db16) is Ok(_)
end

test "M12.3: Reactive txid-cursor feeds: O(diff) subtree skip, pagination, grant revocation, freelist reclaim & compact resync"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T16:50:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T20:00:00Z") or stop "t1"
  sc = Ledger.schema(0).with_require_reason(false)
  items_t = Table.int_key[BudgetRec]("items")
  other_t = Table.text_key[Text]("other")
  sec_t = Table.text_key[Text]("vault")
  pol = Policy.policy().with_bucket_sensitivity("items", Policy.Internal).with_bucket_sensitivity(
    "other",
    Policy.Public
  ).with_bucket_sensitivity("vault", Policy.Secret)

  assert Ledger.open(files, "feeds-full.modb", sc, t0) is Ok(db0)
  m = Ledger.WriteMeta(principal: "admin:lead", action: "seed", reason: "init", at: t0)

  ## Bulk load 220 rows across multi-page B+Tree leaves so `subtrees_skipped > 0` on small diffs
  assert Ledger.write(db0, m, "bulk seed 220 items", Json.Null, fn(tx)
    var t = tx
    for i in 1..221
      t = try Table.put(
        t,
        items_t,
        i,
        BudgetRec(id: i, dept: "core", status: "active", owner: "u#{i}", secret_cap_cents: i * 10)
      )
    end
    Ok(t)
  end) is
    Ok(db1)

  assert Grants.issue_root(
    db1,
    m,
    Grants.GrantSpec(
      id: "g-feed",
      principal: "agent:daemon",
      allowed_actions: ["noop"],
      max_calls: 20,
      expires_at: t1
    )
  ) is
    Ok((db2, _))
  assert Policy.set_clearance(db2, pol, m, "g-feed", Policy.Internal, t0) is Ok((db3, _))

  ## 1. Tail feed watching ONLY ["items", "vault"] -> idle reads 0 pages; unrelated `other` write skips data pages
  assert Feeds.subscribe(
    db3,
    Feeds.FeedSpec(
      id: "tail-items",
      principal: "agent:daemon",
      grant_id: Some("g-feed"),
      buckets: ["items", "vault"],
      include_internal: false,
      from_beginning: false
    ),
    "watch items",
    t0
  ) is
    Ok((db4, _))

  assert Ledger.write(db4, m, "write unwatched", Json.Null, fn(tx)
    Table.put(tx, other_t, "k1", "v1")
  end) is
    Ok(db5)
  assert Feeds.poll_feed(Ledger.store(db5), pol, "tail-items", false, 100, t0) is Ok(unwatched_b)
  assert unwatched_b.events.empty? and unwatched_b.pages_read == 0

  ## Mutate 2 items out of 220 + insert Secret `vault` entry
  assert Ledger.write(db5, m, "update item 10, delete 200, add secret", Json.Null, fn(tx)
    t_a = try Table.put(
      tx,
      items_t,
      10,
      BudgetRec(id: 10, dept: "core", status: "paused", owner: "u10", secret_cap_cents: 999)
    )
    t_b = try Table.delete(t_a, items_t, 200)
    Table.put(t_b, sec_t, "k-sec", "top-secret-value")
  end) is
    Ok(db6)

  assert Feeds.poll_feed(Ledger.store(db6), pol, "tail-items", false, 1, t0) is Ok(capped_b)
  assert capped_b.events.size == 1 and capped_b.truncated and capped_b.filtered_buckets == ["vault"]

  ## Truncated consume_feed must NOT advance cursor!
  assert Feeds.consume_feed(db6, pol, "tail-items", false, 1, t0) is Ok((db6_same, b_trunc, _))
  assert b_trunc.truncated and Modb.txid(Ledger.store(db6_same)) == Modb.txid(Ledger.store(db6))

  ## Full poll proves O(diff) B+Tree subtree skipping (`subtrees_skipped > 0`) and receives both events
  assert Feeds.consume_feed(db6_same, pol, "tail-items", false, 0, t0) is Ok((db7, full_b, sub7))
  assert not full_b.truncated and full_b.events.size == 2 and full_b.subtrees_skipped > 0
  assert full_b.filtered_buckets == ["vault"] and sub7.events_delivered == 2

  ## 2. Repeated overwrites while pin exists -> deferred pages accumulate, then graduate on consume + unsubscribe!
  var cur_db = db7
  for round in 1..4
    assert Ledger.write(cur_db, m, "overwrite round #{round}", Json.Null, fn(tx)
      var t = tx
      for k in 1..40
        t = try Table.put(
          t,
          items_t,
          k,
          BudgetRec(
            id: k,
            dept: "r#{round}",
            status: "active",
            owner: "u#{k}",
            secret_cap_cents: k + round
          )
        )
      end
      Ok(t)
    end) is
      Ok(next_d)
    cur_db = next_d
  end
  assert Modb.verify(Ledger.store(cur_db)) is Ok(_)
  assert Feeds.consume_feed(cur_db, pol, "tail-items", false, 0, t0) is Ok((db8, b_rounds, _))
  assert not b_rounds.events.empty?
  assert Modb.verify(Ledger.store(db8)) is Ok(_)

  ## 3. Bootstrap subscription (`from_beginning: true`) receives full initial snapshot cleanly
  assert Feeds.subscribe(
    db8,
    Feeds.FeedSpec(
      id: "boot-other",
      principal: "agent:daemon",
      grant_id: Some("g-feed"),
      buckets: ["other"],
      include_internal: false,
      from_beginning: true
    ),
    "bootstrap other",
    t0
  ) is
    Ok((db9, boot_sub))
  assert not boot_sub.bootstrapped
  assert Feeds.consume_feed(db9, pol, "boot-other", false, 0, t0) is Ok((db10, b_boot, sub_boot2))
  assert b_boot.events.size == 1 and sub_boot2.bootstrapped and sub_boot2.events_delivered == 1

  ## 4. Grant revocation fails closed on subsequent poll_feed
  assert Grants.revoke(db10, m, "g-feed") is Ok((db11, _))
  assert Feeds.poll_feed(Ledger.store(db11), pol, "tail-items", false, 0, t0) is
    Error(Feeds.GrantFailure(Grants.Revoked(id: "g-feed", revoked_ancestor: "g-feed")))

  ## Unsubscribe & re-verify clean freelist + audit chain
  assert Feeds.unsubscribe(db11, "tail-items", m) is Ok(db12)
  assert Modb.get_pin(Ledger.store(db12), Feeds.feed_pin_id("tail-items")) is Ok(None)
  assert Ledger.verify_all(db12) is Ok(_)

  ## 5. Compaction recovery: compact_db drops `_modb_pins` -> active feed returns PinMissing -> resync_feed recovers!
  assert Feeds.subscribe(
    db12,
    Feeds.FeedSpec(
      id: "admin-items",
      principal: "admin:lead",
      grant_id: None,
      buckets: ["items"],
      include_internal: false,
      from_beginning: false
    ),
    "admin tail feed",
    t0
  ) is
    Ok((_db13, _))
  assert Export.compact_db(files, "feeds-full.modb", sc, true, false, t0) is Ok(_)
  assert Ledger.open(files, "feeds-full.modb", sc, t0) is Ok(db_cmp)
  assert Feeds.poll_feed(Ledger.store(db_cmp), pol, "admin-items", true, 0, t0) is
    Error(Feeds.PinMissing(feed_id: "admin-items", pin_id: "feed:admin-items"))
  assert Feeds.resync_feed(db_cmp, "admin-items", false, t0) is Ok((db_resync, _))
  assert Feeds.poll_feed(Ledger.store(db_resync), pol, "admin-items", true, 0, t0) is Ok(b_after)
  assert b_after.events.empty?
  assert Ledger.verify_all(db_resync) is Ok(_)
end
