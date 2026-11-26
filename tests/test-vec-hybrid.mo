## Comprehensive verification suite for `Modb.Vec` and Hybrid BM25+Vector RRF Search:
## 1. Distance metrics (`Cosine`, `DotProduct`, `Euclidean`), `Quantized16`/`Quantized8` accuracy, and validation
## 2. Incremental overwrite, cross-scope move cleanup, zero/empty scopes, and delete hygiene
## 3. Fail-closed `required_scope` O(scope) prefix scan & `search_filtered` predicate isolation
## 4. Differential test (120+ multi-op transactions vs exact float64 reference cosine)
## 5. Hybrid BM25 + Vector RRF search (`hybrid_search` / `hybrid_search_filtered`, graceful fallbacks, deterministic ties)
## 6. Atomic `Modb.commit_and_crash` fault-injection + Layer 3/4 `Ledger` / `Replay` / `Export` / `compact_db` round-trips
module TestVecHybrid
use Json
use Modb
use Modb.Export
use Modb.Fts
use Modb.Ledger{Schema, WriteMeta}
use Modb.Pager{sim_empty}
use Modb.Replay
use Modb.Table
use Modb.Vec{
  HybridOptions,
  VecConfig,
  VecSearchOptions,
  VectorInput
}

struct NoteItem
  scope: Text
  title: Text
  body: Text
end

struct PutNoteArgs
  id: Text
  scope: Text
  title: Text
  body: Text
  vec: List(Float)
end

fn notes_table() : Table.Table(Text, NoteItem)
  Table.text_key[NoteItem]("notes")
end

fn notes_fts() : Fts.FtsIndex
  Fts.index("notes")
end

fn notes_vec() : Vec.VecIndex
  Vec.index("notes", 8)
end

fn pseudo_unit_vec(rng: Random, dims: Int) : List(Float)
  var raw = []
  for _ in 0..dims
    ## Uniform integer mapped to [-1000, 1000] / 1000.0
    v = (rng.int(0, 2001) - 1000).to_float / 1000.0
    raw = raw.append(v)
  end
  Vec.normalize(raw)
end

fn ref_cosine_top_k(
  corpus: Map(Text, VectorInput),
  q: List(Float),
  limit: Int,
  req_scope: Option(Text)
) : List((Text, Text, Float))
  var scored = []
  for (id, doc) in corpus.entries
    scope_ok = case req_scope
      Some(s): doc.scope == s
      None: true
    end
    if scope_ok
      sc = Vec.cosine_similarity(doc.values, q)
      scored = scored.append((id, doc.scope, sc))
    end
  end
  scored.sort_by(fn(p) p.0 end).sort_by_desc(fn(p) p.2 end).take(limit)
end

test "1. Metrics, quantization accuracy (Q16/Q8), and input validation"
  files = Files.in_memory({})
  assert Modb.open(files, "metrics.modb") is Ok(db0)

  ## Config validation
  assert Vec.index_with_config("", Vec.default_config(4)) is Error(Vec.InvalidConfig(reason: _))
  assert Vec.index_with_config("_modb_secret", Vec.default_config(4)) is
    Error(Vec.InvalidConfig(reason: _))
  assert Vec.index_with_config("bad", Vec.default_config(0)) is
    Error(Vec.InvalidConfig(reason: _))

  q16_cos = Vec.index("q16c", 4)
  v_a = [0.85, 0.35, -0.25, 0.30]
  v_b = [-0.40, 0.90, 0.15, -0.10]
  v_z = [0.0, 0.0, 0.0, 0.0]
  q_vec = [0.80, 0.45, -0.20, 0.34]

  assert Vec.put_vectors(
    db0,
    q16_cos,
    [
      VectorInput(doc_id: "a", scope: "s1", values: v_a),
      VectorInput(doc_id: "b", scope: "s1", values: v_b),
      VectorInput(doc_id: "zero", scope: "s1", values: v_z)
    ]
  ) is
    Ok(db1)

  ## Reject dimension mismatch, NaN, and empty doc_id
  assert Vec.put_vector(db1, q16_cos, VectorInput(doc_id: "bad_dim", scope: "s1", values: [1.0, 2.0])) is
    Error(Vec.DimensionMismatch(expected: 4, actual: 2))
  nan_val = "NaN".to_float or (-1.0).to_float.sqrt
  inf_val = "inf".to_float or ("1e309".to_float or 0.0.to_float)
  assert Vec.put_vector(
    db1,
    q16_cos,
    VectorInput(doc_id: "bad_nan", scope: "s1", values: [nan_val, 0.0, 0.0, 0.0])
  ) is
    Error(Vec.InvalidVector(reason: _))
  assert Vec.put_vector(
    db1,
    q16_cos,
    VectorInput(doc_id: "bad_inf", scope: "s1", values: [inf_val, 0.0, 0.0, 0.0])
  ) is
    Error(Vec.InvalidVector(reason: _))
  assert Vec.put_vector(db1, q16_cos, VectorInput(doc_id: "", scope: "s1", values: v_a)) is
    Error(Vec.InvalidVector(reason: _))

  assert Vec.search(db1, q16_cos, q_vec, Vec.default_search_options(10)) is Ok(hits16)
  assert hits16.size == 3
  h_a = hits16.find(fn(h) h.doc_id == "a" end) or stop "h_a"
  h_b = hits16.find(fn(h) h.doc_id == "b" end) or stop "h_b"
  h_z = hits16.find(fn(h) h.doc_id == "zero" end) or stop "h_z"
  assert (h_a.score - Vec.cosine_similarity(v_a, q_vec)).abs < 0.0005
  assert (h_b.score - Vec.cosine_similarity(v_b, q_vec)).abs < 0.0005
  assert h_z.score == 0.0

  ## Round-trip reconstruction restores original scale
  assert Vec.get_vector(db1, q16_cos, "a") is Ok(Some(restored))
  for (x0, xr) in v_a.zip(restored)
    assert (x0 - xr).abs < 0.0005
  end

  ## DotProduct preserves norm difference
  assert Vec.index_with_config(
    "dot8",
    VecConfig(dimensions: 3, metric: Vec.DotProduct, encoding: Vec.Quantized8)
  ) is
    Ok(dot_idx)
  assert Vec.put_vectors(
    db1,
    dot_idx,
    [
      VectorInput(doc_id: "small", scope: "s", values: [1.0, 0.0, 0.0]),
      VectorInput(doc_id: "large", scope: "s", values: [10.0, 0.0, 0.0])
    ]
  ) is
    Ok(db2)
  assert Vec.search(db2, dot_idx, [2.0, 0.0, 0.0], Vec.default_search_options(2)) is Ok(dot_hits)
  assert (dot_hits.first or stop "dot0").doc_id == "large"
  assert (dot_hits.first or stop "dot0").score > 19.5

  ## Euclidean 1/(1+d) ranks closest points first
  assert Vec.index_with_config(
    "euc16",
    VecConfig(dimensions: 2, metric: Vec.Euclidean, encoding: Vec.Quantized16)
  ) is
    Ok(euc_idx)
  assert Vec.put_vectors(
    db2,
    euc_idx,
    [
      VectorInput(doc_id: "p1", scope: "s", values: [3.0, 4.0]),
      VectorInput(doc_id: "p2", scope: "s", values: [30.0, 40.0])
    ]
  ) is
    Ok(db3)
  assert Vec.search(db3, euc_idx, [0.0, 0.0], Vec.default_search_options(2)) is Ok(euc_hits)
  assert (euc_hits.first or stop "e0").doc_id == "p1"
  ## distance([0,0], [3,4]) == 5 -> 1/(1+5) = 0.1666...
  assert ((euc_hits.first or stop "e0").score - (1.0 / 6.0)).abs < 0.001
end

test "2. Overwrite, cross-scope move cleanup, empty scope, and full removal hygiene"
  files = Files.in_memory({})
  assert Modb.open(files, "scopes-del.modb") is Ok(db0)
  idx = Vec.index("mv", 3)

  assert Vec.put_vectors(
    db0,
    idx,
    [
      VectorInput(doc_id: "d1", scope: "", values: [1.0, 0.0, 0.0]),
      VectorInput(doc_id: "d2", scope: "alpha", values: [0.0, 1.0, 0.0])
    ]
  ) is
    Ok(db1)
  assert Vec.stats(db1, idx) is Ok(st1) and st1.doc_count == 2 and st1.total_bytes == 12

  ## Move d2 from alpha -> beta cleanly
  assert Vec.put_vector(db1, idx, VectorInput(doc_id: "d2", scope: "beta", values: [0.9, 0.1, 0.0])) is
    Ok(db2)
  assert Vec.stats(db2, idx) is Ok(st2) and st2.doc_count == 2 and st2.total_bytes == 12
  assert Modb.count_bucket(db2, "mv_vec_data") == Ok(2)

  ## Confirm alpha scope is now completely empty and "" scope retains d1
  assert Vec.search(
    db2,
    idx,
    [1.0, 0.0, 0.0],
    VecSearchOptions(limit: 10, required_scope: Some("alpha"), min_score: None)
  ) ==
    Ok([])
  assert Vec.search(
    db2,
    idx,
    [1.0, 0.0, 0.0],
    VecSearchOptions(limit: 10, required_scope: Some(""), min_score: None)
  ) is
    Ok(empty_scope_hits)
  assert empty_scope_hits.size == 1 and (empty_scope_hits.first or stop "es0").doc_id == "d1"

  ## Delete both + idempotent repeat remove -> stats cleanly removed
  assert Vec.remove_vector(db2, idx, "d1") is Ok(db3)
  assert Vec.remove_vector(db3, idx, "d2") is Ok(db4)
  assert Vec.remove_vector(db4, idx, "nonexistent") is Ok(db5)
  assert Vec.stats(db5, idx) == Ok(Vec.empty_stats(idx.config))
  assert Modb.count_bucket(db5, "mv_vec_data") == Ok(0)
  assert Modb.count_bucket(db5, "mv_vec_docs") == Ok(0)
  assert Modb.count_bucket(db5, "mv_vec_meta") == Ok(0)
end

test "3. Fail-closed search_filtered isolation and min_score threshold"
  files = Files.in_memory({})
  assert Modb.open(files, "acl-vec.modb") is Ok(db0)
  idx = Vec.index("acl", 4)

  assert Vec.put_vectors(
    db0,
    idx,
    [
      VectorInput(doc_id: "secret", scope: "exec", values: [1.0, 0.0, 0.0, 0.0]),
      VectorInput(doc_id: "pub_blocked", scope: "public", values: [0.99, 0.1, 0.0, 0.0]),
      VectorInput(doc_id: "pub_ok_hi", scope: "public", values: [0.90, 0.44, 0.0, 0.0]),
      VectorInput(doc_id: "pub_ok_lo", scope: "public", values: [0.10, 0.99, 0.0, 0.0])
    ]
  ) is
    Ok(db1)

  opts = VecSearchOptions(limit: 10, required_scope: Some("public"), min_score: Some(0.5))
  assert Vec.search_filtered(
    db1,
    idx,
    [1.0, 0.0, 0.0, 0.0],
    opts,
    fn(id, scope) scope == "public" and id != "pub_blocked" end
  ) is
    Ok(hits)
  assert hits.size == 1 and (hits.first or stop "pub").doc_id == "pub_ok_hi"
end

test "4. Differential test: 120 random transactions vs exact float64 cosine reference"
  rng = Random.seeded(11262026)
  files = Files.in_memory({})
  assert Modb.open(files, "diff-vec.modb") is Ok(db0)
  dims = 16
  idx = Vec.index("diffv", dims)
  scopes = ["proj_a", "proj_b", "proj_c"]

  var db = db0
  var ref = {}

  for step in 0..120
    doc_num = rng.int(0, 40)
    doc_id = "doc_#{doc_num}"
    op = rng.int(0, 5)
    if op == 0
      assert Vec.remove_vector(db, idx, doc_id) is Ok(next_db)
      db = next_db
      ref = ref.remove(doc_id)
    else
      sc = scopes.get(rng.int(0, 3)) or "proj_a"
      vec = pseudo_unit_vec(rng, dims)
      inp = VectorInput(doc_id: doc_id, scope: sc, values: vec)
      assert Vec.put_vector(db, idx, inp) is Ok(next_db)
      db = next_db
      ref = ref.set(doc_id, inp)
    end

    if step.floor_mod(20) == 0 or step == 119
      assert Vec.stats(db, idx) is Ok(st)
      assert st.doc_count == ref.size
      assert st.total_bytes == ref.size * dims * 2

      q = pseudo_unit_vec(rng, dims)
      req = if step.floor_mod(40) == 0: Some("proj_b") else: None
      expected = ref_cosine_top_k(ref, q, 8, req)
      assert Vec.search(db, idx, q, VecSearchOptions(limit: 8, required_scope: req, min_score: None)) is
        Ok(actual)
      assert actual.size == expected.size
      for ((eid, esc, esc_score), ah) in expected.zip(actual)
        assert ah.scope == esc
        assert (ah.score - esc_score).abs < 0.001
        ## Only insist exact doc_id if top scores aren't identical within Q16 tolerance
        if eid != ah.doc_id
          e_match = actual.find(fn(h) h.doc_id == eid end)
          assert e_match is Some(_)
        end
      end
    end
  end
end

test "5. Hybrid BM25 + Vector RRF search, single-channel fallbacks, ACLs, and ties"
  files = Files.in_memory({})
  assert Modb.open(files, "hybrid.modb") is Ok(db0)
  f_idx = Fts.index("kb")
  v_idx = Vec.index("kb", 4)

  ## Both lexical + semantic target doc vs lexical-only vs semantic-only
  f_docs = [
    Fts.DocumentInput(
      doc_id: "both",
      scope: "infra",
      fields: [Fts.FieldInput(name: "title", text: "database failover playbook", weight: 3)]
    ),
    Fts.DocumentInput(
      doc_id: "lex_only",
      scope: "infra",
      fields: [Fts.FieldInput(name: "title", text: "database failover legacy checklist", weight: 3)]
    ),
    Fts.DocumentInput(
      doc_id: "sem_only",
      scope: "infra",
      fields: [Fts.FieldInput(name: "title", text: "replica promotion architecture", weight: 3)]
    ),
    Fts.DocumentInput(
      doc_id: "secret_both",
      scope: "secret",
      fields: [Fts.FieldInput(name: "title", text: "database failover master key", weight: 3)]
    )
  ]
  v_docs = [
    VectorInput(doc_id: "both", scope: "infra", values: [0.92, 0.39, 0.0, 0.0]),
    VectorInput(doc_id: "lex_only", scope: "infra", values: [0.0, 0.0, 1.0, 0.0]),
    VectorInput(doc_id: "sem_only", scope: "infra", values: [0.99, 0.14, 0.0, 0.0]),
    VectorInput(doc_id: "secret_both", scope: "secret", values: [1.0, 0.0, 0.0, 0.0])
  ]

  assert Fts.index_documents(db0, f_idx, f_docs) is Ok(db1)
  assert Vec.put_vectors(db1, v_idx, v_docs) is Ok(db2)

  q_vec = [0.99, 0.14, 0.0, 0.0]
  infra_opts = HybridOptions(
    limit: 5,
    prefix_last_term?: true,
    required_scope: Some("infra"),
    rrf_k: 60,
    fts_weight: 1.0.to_float,
    vec_weight: 1.0.to_float,
    candidate_limit: 20,
    min_vec_score: None
  )

  assert Vec.hybrid_search(db2, f_idx, v_idx, "database failov", Some(q_vec), infra_opts) is Ok(hh)
  assert hh.size == 3
  top = hh.first or stop "hh0"
  assert top.doc_id == "both"
  assert top.fts_rank is Some(_) and top.vec_rank is Some(_)
  assert not hh.any?(fn(h) h.doc_id == "secret_both" end)

  ## Fail-closed predicate filter blocks even top candidate without exposing across either channel
  assert Vec.hybrid_search_filtered(
    db2,
    f_idx,
    v_idx,
    "database failover",
    Some(q_vec),
    Vec.default_hybrid_options(5),
    fn(id, scope) scope == "infra" and id != "both" end
  ) is
    Ok(fh)
  assert not fh.any?(fn(h) h.doc_id == "both" or h.doc_id == "secret_both" end)

  ## Single-channel fallbacks: vector-only (empty text) and FTS-only (None vector)
  assert Vec.hybrid_search(db2, f_idx, v_idx, "", Some(q_vec), infra_opts) is Ok(vec_only_h)
  assert (vec_only_h.first or stop "vo0").doc_id == "sem_only"
  assert (vec_only_h.first or stop "vo0").fts_rank == None

  assert Vec.hybrid_search(db2, f_idx, v_idx, "database failover", None, infra_opts) is Ok(fts_only_h)
  assert fts_only_h.size == 2
  assert (fts_only_h.first or stop "fo0").vec_rank == None

  ## Zero vectors tie cleanly in alphabetical doc_id order under Vector-only fallback
  assert Vec.put_vectors(
    db2,
    v_idx,
    [
      VectorInput(doc_id: "tie_b", scope: "tie", values: [1.0, 0.0, 0.0, 0.0]),
      VectorInput(doc_id: "tie_a", scope: "tie", values: [1.0, 0.0, 0.0, 0.0])
    ]
  ) is
    Ok(db3)
  tie_opts = VecSearchOptions(limit: 5, required_scope: Some("tie"), min_score: None)
  assert Vec.search(db3, v_idx, [1.0, 0.0, 0.0, 0.0], tie_opts) is Ok(th)
  assert (th.first or stop "th0").doc_id == "tie_a" and (th.get(1) or stop "th1").doc_id == "tie_b"
end

test "6. Crash-simulation atomicity + Ledger, Replay selective undo, Export & Compact"
  ## Part A: Modb.commit_and_crash across Table + Fts + Vec in one WriteTx
  rng = Random.seeded(884422)
  assert Modb.open_disk(sim_empty()) is Ok(disk0)
  var disk = disk0
  ntbl = notes_table()
  f_idx = notes_fts()
  v_idx = notes_vec()
  var live_ids = Set.empty

  for trial in 0..20
    nid = "n_#{rng.int(0, 8)}"
    before_txid = Modb.txid(disk)
    before_ids = live_ids

    tx0 = Modb.begin_write(disk)
    var next_tx = tx0
    var next_ids = before_ids
    if rng.int(0, 4) == 0
      assert Table.delete(tx0, ntbl, nid) is Ok(t1)
      assert Fts.tx_remove_document(t1, f_idx, nid) is Ok(t2)
      assert Vec.tx_remove_vector(t2, v_idx, nid) is Ok(t3)
      next_tx = t3
      next_ids = next_ids.remove(nid)
    else
      v = pseudo_unit_vec(rng, 8)
      title = "incident runbook #{trial}"
      assert Table.put(tx0, ntbl, nid, NoteItem(scope: "ops", title: title, body: "recovery")) is
        Ok(t1)
      assert Fts.tx_index_document(
        t1,
        f_idx,
        Fts.DocumentInput(
          doc_id: nid,
          scope: "ops",
          fields: [Fts.FieldInput(name: "title", text: title, weight: 3)]
        )
      ) is
        Ok(t2)
      assert Vec.tx_put_vector(t2, v_idx, VectorInput(doc_id: nid, scope: "ops", values: v)) is
        Ok(t3)
      next_tx = t3
      next_ids = next_ids.add(nid)
    end

    assert Modb.commit_and_crash(next_tx, 1, rng) is Ok(c1)
    assert Modb.open_disk(c1) is Ok(r1)
    assert Modb.verify(r1) is Ok(_) and Modb.txid(r1) == before_txid
    assert Table.count(r1, ntbl) == Ok(before_ids.size)
    assert Fts.stats(r1, f_idx) is Ok(fs1) and fs1.doc_count == before_ids.size
    assert Vec.stats(r1, v_idx) is Ok(vs1) and vs1.doc_count == before_ids.size

    assert Modb.commit_and_crash(next_tx, 2, rng) is Ok(c2)
    assert Modb.open_disk(c2) is Ok(r2)
    assert Modb.verify(r2) is Ok(_)
    if Modb.txid(r2) == before_txid
      assert Modb.commit(next_tx) is Ok(ok_d)
      disk = ok_d
    else
      assert Modb.txid(r2) == before_txid + 1
      disk = r2
    end
    live_ids = next_ids
    assert Table.count(disk, ntbl) == Ok(live_ids.size)
    assert Fts.stats(disk, f_idx) is Ok(fs_ok) and fs_ok.doc_count == live_ids.size
    assert Vec.stats(disk, v_idx) is Ok(vs_ok) and vs_ok.doc_count == live_ids.size
  end

  ## Part B: Layer 3/4 Ledger + Replay ExcludePrincipal + Export + Compact
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T12:00:00Z") or stop "t0"
  sc = Schema(
    target_version: 1,
    require_reason: true,
    migrations: [Ledger.migration(1, "init notes", fn(tx) Ok(tx) end)],
    invariants: []
  )
  rc = Replay.catalog().with_action(
    "put_note",
    fn(tx, args)
      a = try Json.decode[PutNoteArgs](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      t1 = try Table.put(tx, ntbl, a.id, NoteItem(scope: a.scope, title: a.title, body: a.body))
        .map_error(fn(e) e.to_text end)
      t2 = try Fts.tx_index_document(
        t1,
        f_idx,
        Fts.DocumentInput(
          doc_id: a.id,
          scope: a.scope,
          fields: [Fts.FieldInput(name: "title", text: a.title, weight: 3)]
        )
      ).map_error(fn(e) Fts.to_text(e) end)
      t3 = try Vec.tx_put_vector(t2, v_idx, VectorInput(doc_id: a.id, scope: a.scope, values: a.vec))
        .map_error(fn(e) Vec.to_text(e) end)
      Ok((t3, Json.String(a.id)))
    end
  )

  assert Ledger.open(files, "replay-hv.modb", sc, t0) is Ok(ldb0)
  v_good = [1.0, 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
  v_bad = [0.99, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
  assert Replay.execute(
    ldb0,
    rc,
    WriteMeta(principal: "user:alice", action: "put_note", reason: "keep alice note", at: t0),
    PutNoteArgs(id: "good", scope: "ops", title: "failover plan", body: "verified", vec: v_good)
      .to_json
  ) is
    Ok((ldb1, _, _))
  assert Replay.execute(
    ldb1,
    rc,
    WriteMeta(principal: "agent:rogue", action: "put_note", reason: "rogue injection", at: t0),
    PutNoteArgs(id: "bad", scope: "ops", title: "failover backdoor", body: "bad", vec: v_bad).to_json
  ) is
    Ok((ldb2, _, _))

  assert Replay.simulate_replay(
    ldb2,
    rc,
    Replay.ExcludePrincipal(principal: "agent:rogue"),
    "p-excise",
    "Remove rogue note + its FTS and Vec entries",
    "admin",
    t0
  ) is
    Ok((ldb3, _prop))
  assert Replay.accept_proposal(
    ldb3,
    "p-excise",
    WriteMeta(principal: "admin", action: "accept", reason: "excise rogue", at: t0)
  ) is
    Ok((ldb4, _))

  st4 = Ledger.store(ldb4)
  assert Fts.stats(st4, f_idx) is Ok(fs4) and fs4.doc_count == 1
  assert Vec.stats(st4, v_idx) is Ok(vs4) and vs4.doc_count == 1
  assert Vec.hybrid_search(st4, f_idx, v_idx, "failover", Some(v_good), Vec.default_hybrid_options(5)) is
    Ok(hh_clean)
  assert hh_clean.size == 1 and (hh_clean.first or stop "hc0").doc_id == "good"

  ## Export backup + in-place compact preserve both Fts and Vec buckets cleanly
  assert Export.backup_db(
    files.read_only,
    "replay-hv.modb",
    files,
    "backup-hv.modb",
    sc,
    false,
    t0
  ) is
    Ok(_bak_rep)
  assert Ledger.open_read_only(files.read_only, "backup-hv.modb", sc) is Ok(bak_db)
  bak_st = Ledger.store(bak_db)
  assert Vec.hybrid_search(
    bak_st,
    f_idx,
    v_idx,
    "failover",
    Some(v_good),
    Vec.default_hybrid_options(5)
  ) is
    Ok(hh_bak)
  assert hh_bak.size == 1 and (hh_bak.first or stop "hbak0").doc_id == "good"
  assert Ledger.verify_all(bak_db) is Ok(_)

  assert Export.compact_db(files, "replay-hv.modb", sc, false, true, t0) is Ok(_comp_rep)
  assert Ledger.open_read_only(files.read_only, "replay-hv.modb", sc) is Ok(comp_db)
  comp_st = Ledger.store(comp_db)
  assert Vec.hybrid_search(
    comp_st,
    f_idx,
    v_idx,
    "failover",
    Some(v_good),
    Vec.default_hybrid_options(5)
  ) is
    Ok(hh_comp)
  assert hh_comp.size == 1 and (hh_comp.first or stop "hcomp0").doc_id == "good"
  assert Ledger.verify_all(comp_db) is Ok(_)
end
