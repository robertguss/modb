## Milestone 11 Search Scale Benchmark:
## - `Modb.Fts`: 1,000-doc atomic BM25 indexing + exact / multi-term / prefix queries
## - `Modb.Vec`: 1,000-doc 64-d Q16, 384-d Q16, and 384-d Q8 Cosine search (full & scoped)
## - `Modb.Vec.hybrid_search`: 1,000-doc BM25 + Vector RRF fusion queries
module BenchSearch
use Modb
use Modb.Fts
use Modb.Vec{HybridOptions, VecConfig, VecSearchOptions, VectorEncoding, VectorInput}

fn elapsed_ms(clock: Clock, start: Time) : Int
  (clock.now - start).in_milliseconds
end

fn word_at(i: Int) : Text
  words = [
    "database",
    "transaction",
    "checkpoint",
    "replication",
    "failover",
    "compaction",
    "snapshot",
    "audit",
    "ledger",
    "grant",
    "claim",
    "world",
    "diff",
    "hybrid",
    "search",
    "vector",
    "cosine",
    "index",
    "posting",
    "bucket",
    "manifest",
    "invariant",
    "replay",
    "export"
  ]
  words.get(i.floor_mod(words.size)) or "database"
end

fn lcg_step(seed: Int) : Int
  seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407)
end

fn pseudo_vec(seed0: Int, dims: Int) : (List(Float), Int)
  var raw = []
  var s = seed0
  for _ in 0..dims
    s = lcg_step(s)
    v = (s.floor_mod(2001) - 1000).to_float / 1000.0
    raw = raw.append(v)
  end
  (Vec.normalize(raw), s)
end

fn run_fts_bench(console: Console, files: Files, clock: Clock, doc_n: Int) : Result(
  (Modb.Store, Fts.FtsIndex, List(VectorInput)),
  Text
)
  db0 = try Modb.open(files, "bench-fts-vec.modb").map_error(fn(e) e.to_text end)
  f_idx = Fts.index("corpus")
  var seed = 20261126

  var fdocs = []
  var vdocs64 = []
  for i in 0..doc_n
    sc = "scope_#{i.floor_mod(10)}"
    w1 = word_at(i)
    w2 = word_at(i * 7 + 3)
    w3 = word_at(i * 13 + 5)
    w4 = word_at(i * 19 + 11)
    doc_id = "doc_#{i}"
    title = "#{w1} #{w2} item#{i}"
    body = "Section #{sc}: #{w1} #{w3} #{w4} telemetry verification note for #{w2} record #{i}"
    fdocs = fdocs.append(
      Fts.DocumentInput(
        doc_id: doc_id,
        scope: sc,
        fields: [
          Fts.FieldInput(name: "title", text: title, weight: 3),
          Fts.FieldInput(name: "body", text: body, weight: 1)
        ]
      )
    )
    (v64, next_s) = pseudo_vec(seed, 64)
    seed = next_s
    vdocs64 = vdocs64.append(VectorInput(doc_id: doc_id, scope: sc, values: v64))
  end

  t0 = clock.now
  db1 = try Fts.index_documents(db0, f_idx, fdocs).map_error(fn(e) Fts.to_text(e) end)
  idx_ms = elapsed_ms(clock, t0)
  console.print(
    "Fts index #{doc_n} docs (10 scopes): #{idx_ms} ms | pages=#{Modb.page_count(db1)} (#{Modb
      .page_count(db1) * 4} KiB)"
  )

  t_q1 = clock.now
  for i in 0..50
    w = word_at(i)
    _hits = try Fts.search(db1, f_idx, w, Fts.default_search_options(10)).map_error(fn(e)
      Fts.to_text(e)
    end)
  end
  q1_ms = elapsed_ms(clock, t_q1)

  t_q2 = clock.now
  for i in 0..50
    q = "#{word_at(i)} #{word_at(i + 5)}"
    _hits = try Fts.search(db1, f_idx, q, Fts.default_search_options(10)).map_error(fn(e)
      Fts.to_text(e)
    end)
  end
  q2_ms = elapsed_ms(clock, t_q2)

  t_qp = clock.now
  for i in 0..50
    w = word_at(i)
    pfx = Text.from_chars(w.chars.take(4))
    _hits = try Fts.search(
      db1,
      f_idx,
      pfx,
      Fts.SearchOptions(limit: 10, prefix_last_term?: true, required_scope: None)
    ).map_error(fn(e) Fts.to_text(e) end)
  end
  qp_ms = elapsed_ms(clock, t_qp)

  console.print(
    "Fts queries (50x each, top-10): exact_1term=#{q1_ms} ms | multi_2term=#{q2_ms} ms | prefix=#{qp_ms} ms"
  )
  Ok((db1, f_idx, vdocs64))
end

fn run_vec_variant(
  console: Console,
  db_in: Modb.Store,
  clock: Clock,
  label: Text,
  prefix: Text,
  dims: Int,
  encoding: VectorEncoding,
  docs: List(VectorInput)
) : Result((Modb.Store, Vec.VecIndex), Text)
  idx = try Vec.index_with_config(
    prefix,
    VecConfig(dimensions: dims, metric: Vec.Cosine, encoding: encoding)
  ).map_error(fn(e) Vec.to_text(e) end)
  var qs = dims * 997 + 17
  var queries = []
  for _ in 0..4
    (qv, ns) = pseudo_vec(qs, dims)
    qs = ns
    queries = queries.append(qv)
  end

  t0 = clock.now
  db1 = try Vec.put_vectors(db_in, idx, docs).map_error(fn(e) Vec.to_text(e) end)
  put_ms = elapsed_ms(clock, t0)
  vst = try Vec.stats(db1, idx).map_error(fn(e) Vec.to_text(e) end)

  tf = clock.now
  for i in 0..20
    qv = queries.get(i.floor_mod(4)) or []
    _hits = try Vec.search(db1, idx, qv, Vec.default_search_options(10)).map_error(fn(e)
      Vec.to_text(e)
    end)
  end
  full_ms = elapsed_ms(clock, tf)

  ts = clock.now
  for i in 0..20
    qv = queries.get(i.floor_mod(4)) or []
    _hits = try Vec.search(
      db1,
      idx,
      qv,
      VecSearchOptions(limit: 10, required_scope: Some("scope_3"), min_score: None)
    ).map_error(fn(e) Vec.to_text(e) end)
  end
  scoped_ms = elapsed_ms(clock, ts)

  console.print(
    "Vec #{label}: put(#{docs.size}) #{put_ms} ms | bytes=#{vst.total_bytes} | 20x full_cos=#{full_ms} ms | 20x scoped_cos(1/10)=#{scoped_ms} ms"
  )
  Ok((db1, idx))
end

fn run_bench(console: Console, files: Files, clock: Clock, doc_n: Int) : Result(Unit, Text)
  console.print("=== MoDB Milestone 11 Search Benchmark (#{doc_n} docs, synced 4 KiB CoW pages) ===")
  (db1, f_idx, vdocs64) = try run_fts_bench(console, files, clock, doc_n)
  (db2, v_idx64) = try run_vec_variant(console, db1, clock, "64d_Q16", "v64", 64, Vec.Quantized16, vdocs64)

  var s384 = 384384
  var docs384 = []
  for i in 0..doc_n
    (v384, ns) = pseudo_vec(s384, 384)
    s384 = ns
    docs384 = docs384.append(
      VectorInput(doc_id: "doc_#{i}", scope: "scope_#{i.floor_mod(10)}", values: v384)
    )
  end
  db_v384_a = try Modb.open(files, "bench-v384-q16.modb").map_error(fn(e) e.to_text end)
  (_db3a, _v384a) = try run_vec_variant(
    console,
    db_v384_a,
    clock,
    "384d_Q16",
    "v384q16",
    384,
    Vec.Quantized16,
    docs384
  )

  db_v384_b = try Modb.open(files, "bench-v384-q8.modb").map_error(fn(e) e.to_text end)
  (_db3b, _v384b) = try run_vec_variant(
    console,
    db_v384_b,
    clock,
    "384d_Q8",
    "v384q8",
    384,
    Vec.Quantized8,
    docs384
  )

  (q64, _qs) = pseudo_vec(555, 64)
  th = clock.now
  for i in 0..20
    q_txt = "#{word_at(i)} #{word_at(i + 5)}"
    _hh = try Vec.hybrid_search(
      db2,
      f_idx,
      v_idx64,
      q_txt,
      Some(q64),
      Vec.default_hybrid_options(10)
    ).map_error(fn(e) Vec.to_text(e) end)
  end
  hyb_ms = elapsed_ms(clock, th)

  ths = clock.now
  for i in 0..20
    q_txt = "#{word_at(i)} #{word_at(i + 5)}"
    opts = HybridOptions(
      limit: 10,
      prefix_last_term?: true,
      required_scope: Some("scope_3"),
      rrf_k: 60,
      fts_weight: 1.0.to_float,
      vec_weight: 1.0.to_float,
      candidate_limit: 40,
      min_vec_score: None
    )
    _hh = try Vec.hybrid_search(db2, f_idx, v_idx64, q_txt, Some(q64), opts).map_error(fn(e)
      Vec.to_text(e)
    end)
  end
  hyb_scoped_ms = elapsed_ms(clock, ths)
  console.print(
    "Hybrid BM25+64d RRF (20x, #{doc_n} docs): full=#{hyb_ms} ms | scoped(1/10)=#{hyb_scoped_ms} ms"
  )
  Ok(Unit)
end

fn main(args: Args, console: Console, files: Files, clock: Clock) : Int
  doc_n = case args.list.first
    Some(s):
      n = s.to_int or 1000
      if n > 0: n else: 1000
    None: 1000
  end
  case run_bench(console, files, clock, doc_n)
    Ok(Unit): 0
    Error(msg):
      console.error("bench-search failed: #{msg}")
      1
  end
end
