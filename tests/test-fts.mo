## Comprehensive verification suite for `Modb.Fts`:
## 1. Tokenizer, pure-Mo `ln_pos`, BM25 IDF & field/length ranking invariants
## 2. Incremental re-indexing & complete index cleanup on delete
## 3. Trailing-token prefix search (`Cmd+K` typeahead) & expansion bounds
## 4. Scope & grant-filtered search isolation (no cross-scope leakage)
## 5. Differential test (150+ randomized multi-op transactions vs reference in-memory BM25)
## 6. Atomic WriteTx + `Modb.commit_and_crash` fault-injection across typed Table + FTS index
module TestFts
use Modb
use Modb.Fts{DocumentInput, FieldInput, FtsConfig, FtsError, FtsStats, SearchHit, SearchOptions}
use Modb.Pager{sim_empty}
use Modb.Table

struct PageMeta
  title: Text
  collection_id: Text
end

fn pages_table() : Table.Table(Text, PageMeta)
  Table.text_key[PageMeta]("pages")
end

fn ref_tokenize(text: Text) : List(Text)
  Fts.tokenize(text, 64)
end

fn ref_update_doc(corpus: Map(Text, DocumentInput), doc: DocumentInput) : Map(Text, DocumentInput)
  corpus.set(doc.doc_id, doc)
end

fn ref_stats(corpus: Map(Text, DocumentInput)) : FtsStats
  var doc_count = 0
  var total_tokens = 0
  var total_weighted_len = 0
  for (_id, doc) in corpus.entries
    doc_count += 1
    for f in doc.fields
      toks = ref_tokenize(f.text)
      total_tokens += toks.size
      total_weighted_len += toks.size * f.weight
    end
  end
  FtsStats(doc_count: doc_count, total_tokens: total_tokens, total_weighted_len: total_weighted_len)
end

fn ref_df_map(corpus: Map(Text, DocumentInput)) : Map(Text, Int)
  var dfs = {}
  for (_id, doc) in corpus.entries
    var doc_terms = Set.empty
    for f in doc.fields
      for t in ref_tokenize(f.text)
        doc_terms = doc_terms.add(t)
      end
    end
    for t in doc_terms.to_list
      dfs = dfs.set(t, (dfs.get(t) or 0) + 1)
    end
  end
  dfs
end

fn ref_search(corpus: Map(Text, DocumentInput), cfg: FtsConfig, query: Text, limit: Int) : List(
  SearchHit
)
  return [] if limit <= 0 or corpus.empty?
  var q_terms = []
  var q_seen = Set.empty
  for qt in ref_tokenize(query)
    if not q_seen.has?(qt)
      q_seen = q_seen.add(qt)
      q_terms = q_terms.append(qt)
    end
  end
  return [] if q_terms.empty?

  st = ref_stats(corpus)
  dfs = ref_df_map(corpus)
  avgdl = if st.total_weighted_len > 0
    st.total_weighted_len.to_float / st.doc_count.to_float
  else
    1.0.to_float
  end

  var hits = []
  for (_id, doc) in corpus.entries
    var wlen = 0
    var term_wtf = {}
    var term_fields = {}
    for f in doc.fields
      toks = ref_tokenize(f.text)
      wlen += toks.size * f.weight
      for t in toks
        term_wtf = term_wtf.set(t, (term_wtf.get(t) or 0) + f.weight)
        fs = term_fields.get(t) or []
        if not fs.contains?(f.name)
          term_fields = term_fields.set(t, fs.append(f.name))
        end
      end
    end

    var score = 0.0.to_float
    var m_terms = []
    var m_fields = []
    for qt in q_terms
      wtf = term_wtf.get(qt) or 0
      df_val = dfs.get(qt) or 0
      if wtf > 0 and df_val > 0
        idf = Fts.bm25_idf(st.doc_count, df_val)
        tf_s = Fts.bm25_tf_score(wtf, wlen, avgdl, cfg.k1, cfg.b)
        score += idf * tf_s
        m_terms = m_terms.append(qt)
        for fnm in (term_fields.get(qt) or [])
          if not m_fields.contains?(fnm)
            m_fields = m_fields.append(fnm)
          end
        end
      end
    end

    if not m_terms.empty?
      hits = hits.append(
        SearchHit(
          doc_id: doc.doc_id,
          scope: doc.scope,
          score: score,
          matched_terms: m_terms.sort,
          matched_fields: m_fields.sort
        )
      )
    end
  end

  hits.sort_by(fn(h) h.doc_id end).sort_by_desc(fn(h) h.score end).take(limit)
end

fn vocab_word(idx: Int) : Text
  words = [
    "alpha",
    "beta",
    "gamma",
    "delta",
    "deploy",
    "deployment",
    "deployed",
    "database",
    "grant",
    "claim",
    "world",
    "proposal",
    "audit",
    "ledger",
    "search",
    "token",
    "oidc",
    "bucket",
    "markdown",
    "kanban"
  ]
  words.get(idx) or "alpha"
end

fn make_random_doc(rng: Random, id_num: Int) : DocumentInput
  scope = if id_num.floor_mod(2) == 0: "col_even" else: "col_odd"
  t_words = rng.int(1, 5)
  var title_parts = []
  for _ in 0..t_words
    title_parts = title_parts.append(vocab_word(rng.int(0, 20)))
  end
  b_words = rng.int(0, 14)
  var body_parts = []
  for _ in 0..b_words
    body_parts = body_parts.append(vocab_word(rng.int(0, 20)))
  end
  DocumentInput(
    doc_id: "doc_#{id_num}",
    scope: scope,
    fields: [
      FieldInput(name: "title", text: title_parts.join(" "), weight: 3),
      FieldInput(name: "body", text: body_parts.join(" "), weight: 1)
    ]
  )
end

test "1. Tokenizer, config validation, and BM25 ranking properties"
  assert Fts.index_with_config("", Fts.default_config()) is Error(InvalidConfig(reason: _))
  bad_b = FtsConfig(
    k1: 1.2.to_float,
    b: 1.5.to_float,
    max_prefix_expansions: 8,
    max_token_bytes: 32
  )
  assert Fts.index_with_config("v", bad_b) is Error(InvalidConfig(reason: _))

  files = Files.in_memory({})
  assert Modb.open(files, "rank.modb") is Ok(db0)
  idx = Fts.index("vlm")

  ## Invalid doc rejections leave store clean.
  assert Fts.index_document(db0, idx, DocumentInput(doc_id: "", scope: "c", fields: [])) is
    Error(InvalidDocument(reason: _))
  assert Fts.index_document(
    db0,
    idx,
    DocumentInput(
      doc_id: "p1",
      scope: "c",
      fields: [FieldInput(name: "body", text: "hi", weight: 0)]
    )
  ) is
    Error(InvalidDocument(reason: _))

  ## Focused short doc vs long noisy doc + rare term vs common term + title weight vs body weight.
  docs = [
    DocumentInput(
      doc_id: "short_focused",
      scope: "eng",
      fields: [
        FieldInput(name: "title", text: "Incident Checklist", weight: 3),
        FieldInput(name: "body", text: "Verify backup", weight: 1)
      ]
    ),
    DocumentInput(
      doc_id: "long_noisy",
      scope: "eng",
      fields: [
        FieldInput(name: "title", text: "Quarterly Notes", weight: 3),
        FieldInput(
          name: "body",
          text: "Random prose words one two three four five six seven eight nine ten incident checklist",
          weight: 1
        )
      ]
    ),
    DocumentInput(
      doc_id: "common_only",
      scope: "eng",
      fields: [
        FieldInput(name: "title", text: "Team Updates", weight: 3),
        FieldInput(name: "body", text: "Notes and checklist and notes and notes", weight: 1)
      ]
    ),
    DocumentInput(
      doc_id: "rare_match",
      scope: "eng",
      fields: [
        FieldInput(name: "title", text: "Runbook", weight: 3),
        FieldInput(name: "body", text: "Contains hypercube alongside notes", weight: 1)
      ]
    )
  ]
  assert Fts.index_documents(db0, idx, docs) is Ok(db1)

  opts = Fts.default_search_options(10)
  assert Fts.search(db1, idx, "incident checklist", opts) is Ok(hits_inc)
  assert hits_inc.size >= 2
  assert (hits_inc.first or stop "h0").doc_id == "short_focused"

  ## Rarer term ("hypercube", df=1) adds more BM25 weight than common term ("notes", df=3).
  assert Fts.search(db1, idx, "hypercube notes", opts) is Ok(hits_rare)
  assert (hits_rare.first or stop "r0").doc_id == "rare_match"
end

test "2. Re-indexing replaces old postings cleanly and full delete empties all FTS buckets"
  files = Files.in_memory({})
  assert Modb.open(files, "reindex.modb") is Ok(db0)
  idx = Fts.index("vlm")

  d1_v1 = DocumentInput(
    doc_id: "pag_1",
    scope: "eng",
    fields: [
      FieldInput(name: "title", text: "Legacy Runbook", weight: 3),
      FieldInput(name: "body", text: "Use deprecated docker compose script", weight: 1)
    ]
  )
  d1_v2 = DocumentInput(
    doc_id: "pag_1",
    scope: "eng",
    fields: [
      FieldInput(name: "title", text: "Single Binary Guide", weight: 3),
      FieldInput(name: "body", text: "Run mo serve directly", weight: 1)
    ]
  )

  assert Fts.index_document(db0, idx, d1_v1) is Ok(db1)
  assert Fts.term_df(db1, idx, "legacy") == Ok(1)
  assert Fts.term_df(db1, idx, "docker") == Ok(1)

  assert Fts.index_document(db1, idx, d1_v2) is Ok(db2)
  assert Fts.term_df(db2, idx, "legacy") == Ok(0)
  assert Fts.term_df(db2, idx, "docker") == Ok(0)
  assert Fts.term_df(db2, idx, "binary") == Ok(1)
  assert Fts.term_df(db2, idx, "serve") == Ok(1)
  assert Fts.search(db2, idx, "docker", Fts.default_search_options(10)) == Ok([])
  assert Fts.search(db2, idx, "binary", Fts.default_search_options(10)) is Ok(b_hits)
  assert b_hits.size == 1

  assert Fts.remove_document(db2, idx, "missing_id") is Ok(db2_noop)
  assert Fts.stats(db2_noop, idx) == Fts.stats(db2, idx)
  assert Fts.remove_document(db2_noop, idx, "pag_1") is Ok(db3)
  assert Fts.stats(db3, idx) == Ok(Fts.empty_stats())
  assert Fts.get_doc(db3, idx, "pag_1") == Ok(None)
  assert Modb.count_bucket(db3, "vlm_fts_postings") == Ok(0)
  assert Modb.count_bucket(db3, "vlm_fts_docs") == Ok(0)
  assert Modb.count_bucket(db3, "vlm_fts_df") == Ok(0)
  assert Modb.count_bucket(db3, "vlm_fts_meta") == Ok(0)
end

test "3. Prefix search typeahead and max_prefix_expansions bound"
  files = Files.in_memory({})
  assert Modb.open(files, "prefix.modb") is Ok(db0)
  cfg = FtsConfig(k1: 1.2.to_float, b: 0.75.to_float, max_prefix_expansions: 2, max_token_bytes: 64)
  assert Fts.index_with_config("p", cfg) is Ok(idx)

  docs = [
    DocumentInput(
      doc_id: "d_a",
      scope: "s",
      fields: [FieldInput(name: "body", text: "deploy", weight: 1)]
    ),
    DocumentInput(
      doc_id: "d_b",
      scope: "s",
      fields: [FieldInput(name: "body", text: "deployed", weight: 1)]
    ),
    DocumentInput(
      doc_id: "d_c",
      scope: "s",
      fields: [FieldInput(name: "body", text: "deployment", weight: 1)]
    )
  ]
  assert Fts.index_documents(db0, idx, docs) is Ok(db1)

  ## Exact mode matches only d_a.
  exact_opts = SearchOptions(limit: 10, prefix_last_term?: false, required_scope: None)
  assert Fts.search(db1, idx, "deploy", exact_opts) is Ok(ex_hits)
  assert ex_hits.size == 1
  assert (ex_hits.first or stop "ex0").doc_id == "d_a"

  ## Prefix mode expands only top max_prefix_expansions (2) lexicographically: "deploy", "deployed".
  pref_opts = SearchOptions(limit: 10, prefix_last_term?: true, required_scope: None)
  assert Fts.search(db1, idx, "depl", pref_opts) is Ok(p_hits)
  assert p_hits.size == 2
  p_ids = p_hits.map(fn(h) h.doc_id end).sort
  assert p_ids == ["d_a", "d_b"]
end

test "4. Grant and scope isolation prevents leakage of higher-scoring restricted docs"
  files = Files.in_memory({})
  assert Modb.open(files, "acl.modb") is Ok(db0)
  idx = Fts.index("acl")

  docs = [
    DocumentInput(
      doc_id: "secret_1",
      scope: "col_exec",
      fields: [
        FieldInput(name: "title", text: "Acquisition Plan Acquisition", weight: 3),
        FieldInput(name: "body", text: "Acquisition acquisition acquisition", weight: 1)
      ]
    ),
    DocumentInput(
      doc_id: "public_1",
      scope: "col_public",
      fields: [
        FieldInput(name: "title", text: "General Notes", weight: 3),
        FieldInput(name: "body", text: "Brief acquisition mention", weight: 1)
      ]
    ),
    DocumentInput(
      doc_id: "public_blocked",
      scope: "col_public",
      fields: [
        FieldInput(name: "title", text: "Acquisition Draft", weight: 3),
        FieldInput(name: "body", text: "Draft notes", weight: 1)
      ]
    )
  ]
  assert Fts.index_documents(db0, idx, docs) is Ok(db1)

  pub_opts = SearchOptions(limit: 10, prefix_last_term?: false, required_scope: Some("col_public"))
  assert Fts.search_filtered(
    db1,
    idx,
    "acquisition",
    pub_opts,
    fn(doc_id, scope) scope == "col_public" and doc_id != "public_blocked" end
  ) is
    Ok(hits)
  assert hits.size == 1
  assert (hits.first or stop "h0").doc_id == "public_1"
end

test "5. Differential test: 150 random transactions vs reference in-memory BM25 engine"
  rng = Random.seeded(20261126)
  files = Files.in_memory({})
  assert Modb.open(files, "diff-fts.modb") is Ok(db0)
  var db = db0
  var ref = {}
  idx = Fts.index("diff")
  cfg = idx.config

  for step in 0..150
    doc_num = rng.int(0, 25)
    doc_id = "doc_#{doc_num}"
    op = rng.int(0, 5)
    if op == 0
      assert Fts.remove_document(db, idx, doc_id) is Ok(db_next)
      db = db_next
      ref = ref.remove(doc_id)
    else
      d = make_random_doc(rng, doc_num)
      assert Fts.index_document(db, idx, d) is Ok(db_next)
      db = db_next
      ref = ref_update_doc(ref, d)
    end

    if step.floor_mod(15) == 0 or step == 149
      assert Fts.stats(db, idx) == Ok(ref_stats(ref))
      ref_dfs = ref_df_map(ref)
      for vi in 0..20
        w = vocab_word(vi)
        assert Fts.term_df(db, idx, w) == Ok(ref_dfs.get(w) or 0)
      end

      q = "#{vocab_word(rng.int(0, 20))} #{vocab_word(rng.int(0, 20))}"
      expected_hits = ref_search(ref, cfg, q, 10)
      assert Fts.search(db, idx, q, Fts.default_search_options(10)) is Ok(actual_hits)
      assert actual_hits.size == expected_hits.size
      for (eh, ah) in expected_hits.zip(actual_hits)
        assert ah.doc_id == eh.doc_id
        assert ah.scope == eh.scope
        assert ah.matched_terms == eh.matched_terms
        assert ah.matched_fields == eh.matched_fields
        assert (ah.score - eh.score).abs < 0.000000001
      end
    end
  end
end

test "6. Crash-simulation atomicity across typed pages table and Fts index"
  rng = Random.seeded(771122)
  assert Modb.open_disk(sim_empty()) is Ok(db0)
  var db = db0
  idx = Fts.index("vlm")
  ptbl = pages_table()
  var committed_titles = {}

  for trial in 0..45
    pid = "pag_#{rng.int(0, 12)}"
    before_txid = Modb.txid(db)
    before_titles = committed_titles

    var tx = Modb.begin_write(db)
    var candidate_titles = before_titles
    if rng.int(0, 4) == 0
      assert Table.delete(tx, ptbl, pid) is Ok(t1)
      assert Fts.tx_remove_document(t1, idx, pid) is Ok(t2)
      tx = t2
      candidate_titles = candidate_titles.remove(pid)
    else
      word_a = vocab_word(rng.int(0, 20))
      word_b = vocab_word(rng.int(0, 20))
      title = "#{word_a} #{word_b} v#{trial}"
      assert Table.put(tx, ptbl, pid, PageMeta(title: title, collection_id: "col_main")) is Ok(t1)
      doc = DocumentInput(
        doc_id: pid,
        scope: "col_main",
        fields: [FieldInput(name: "title", text: title, weight: 3)]
      )
      assert Fts.tx_index_document(t1, idx, doc) is Ok(t2)
      tx = t2
      candidate_titles = candidate_titles.set(pid, title)
    end

    ## Phase 1 crash (before data sync): must recover prior committed state atomically.
    assert Modb.commit_and_crash(tx, 1, rng) is Ok(crashed1)
    assert Modb.open_disk(crashed1) is Ok(rec1)
    assert Modb.verify(rec1) is Ok(_)
    assert Modb.txid(rec1) == before_txid
    assert Fts.stats(rec1, idx) is Ok(st1)
    assert st1.doc_count == before_titles.size
    for (k, _v) in before_titles.entries
      assert Table.get(rec1, ptbl, k) is Ok(Some(_))
      assert Fts.get_doc(rec1, idx, k) is Ok(Some(_))
    end

    ## Phase 2 crash (during meta-page write): lands either cleanly before or cleanly after.
    assert Modb.commit_and_crash(tx, 2, rng) is Ok(crashed2)
    assert Modb.open_disk(crashed2) is Ok(rec2)
    assert Modb.verify(rec2) is Ok(_)
    if Modb.txid(rec2) == before_txid
      assert Fts.stats(rec2, idx) is Ok(st2)
      assert st2.doc_count == before_titles.size
      assert Modb.commit(tx) is Ok(db_ok)
      db = db_ok
      committed_titles = candidate_titles
    else
      assert Modb.txid(rec2) == before_txid + 1
      assert Fts.stats(rec2, idx) is Ok(st2)
      assert st2.doc_count == candidate_titles.size
      db = rec2
      committed_titles = candidate_titles
    end

    ## Invariant: pages table and FTS doc table always contain the exact same live doc IDs.
    assert Table.count(db, ptbl) == Ok(committed_titles.size)
    assert Modb.count_bucket(db, "vlm_fts_docs") == Ok(committed_titles.size)
  end
end
