## MoDB Vector & Hybrid Search: crash-safe, transactional pure-Mo vector storage (Q16/Q8),
## quantized Int64 scoring (`Cosine`, `DotProduct`, `Euclidean`), and BM25 + Vector RRF fusion.
module Modb.Vec
expose VecError(..),
DistanceMetric(..),
VectorEncoding(..),
VecConfig(..),
VecIndex(..),
VectorInput(..),
VecDocMeta(..),
VecStats(..),
VecSearchOptions(..),
VecHit(..),
HybridOptions(..),
HybridHit(..),
to_text,
default_config,
index,
index_with_config,
empty_stats,
default_search_options,
default_hybrid_options,
l2_norm,
normalize,
dot_product,
cosine_similarity,
euclidean_distance,
text_sketch_embedding,
decode_vector_bytes,
tx_put_vector,
tx_remove_vector,
put_vector,
put_vectors,
remove_vector,
stats,
get_doc,
get_vector,
search,
search_filtered,
hybrid_search,
hybrid_search_filtered
use Modb{Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Fts
use Modb.Table

## Every failure returned by `Modb.Vec` operations.
enum VecError
  Storage(ModbError)
  TableFailure(Table.TableError)
  FtsFailure(Fts.FtsError)
  InvalidConfig(reason: Text)
  InvalidVector(reason: Text)
  DimensionMismatch(expected: Int, actual: Int)
end

## Similarity / distance metric used to rank vectors inside a `VecIndex`.
enum DistanceMetric
  Cosine
  DotProduct
  Euclidean
end

## Binary packed quantization format stored directly in `{prefix}_vec_data`.
enum VectorEncoding
  Quantized16
  Quantized8
end

## Vector dimension, metric, and binary packing configuration for a `VecIndex`.
struct VecConfig
  dimensions: Int
  metric: DistanceMetric
  encoding: VectorEncoding
end

## Handle identifying a namespaced vector index inside a `Modb` store.
struct VecIndex
  prefix: Text
  config: VecConfig
end

## Vector document payload stored atomically inside a `VecIndex`.
struct VectorInput
  doc_id: Text
  scope: Text
  values: List(Float)
end

## Per-document vector metadata enabling $O(1)$ scope cleanup, exact decoding, and norm scaling.
struct VecDocMeta
  doc_id: Text
  scope: Text
  dimensions: Int
  norm: Float
  scale: Float
  zero_norm?: Bool
end

## Corpus metadata and byte footprint stored at key `"stats"` in `{prefix}_vec_meta`.
struct VecStats
  doc_count: Int
  dimensions: Int
  metric: DistanceMetric
  encoding: VectorEncoding
  total_bytes: Int
end

## Query options controlling top-K limit, scope prefix-scan, and optional minimum score threshold.
struct VecSearchOptions
  limit: Int
  required_scope: Option(Text)
  min_score: Option(Float)
end

## Ranked vector search hit returned by `search` and `search_filtered`.
struct VecHit
  doc_id: Text
  scope: Text
  score: Float
end

## Options controlling weighted Reciprocal Rank Fusion across `Modb.Fts` and `Modb.Vec`.
struct HybridOptions
  limit: Int
  prefix_last_term?: Bool
  required_scope: Option(Text)
  rrf_k: Int
  fts_weight: Float
  vec_weight: Float
  candidate_limit: Int
  min_vec_score: Option(Float)
end

## Combined hybrid hit carrying overall RRF score alongside per-channel ranks and match metadata.
struct HybridHit
  doc_id: Text
  scope: Text
  score: Float
  fts_rank: Option(Int)
  fts_score: Option(Float)
  vec_rank: Option(Int)
  vec_score: Option(Float)
  matched_terms: List(Text)
  matched_fields: List(Text)
end

struct PreparedQuery
  q_ints: List(Int)
  q_scale: Float
  q_floats: List(Float)
  zero_norm?: Bool
end

struct HybridAcc
  scope: Text
  score: Float
  fts_rank: Option(Int)
  fts_score: Option(Float)
  vec_rank: Option(Int)
  vec_score: Option(Float)
  matched_terms: List(Text)
  matched_fields: List(Text)
end

## Formats a `VecError` as a human-readable diagnostic.
fn to_text(err: VecError) : Text
  case err
    Storage(e): e.to_text
    TableFailure(e): e.to_text
    FtsFailure(e): Fts.to_text(e)
    InvalidConfig(reason: r): "invalid vector config: #{r}"
    InvalidVector(reason: r): "invalid vector: #{r}"
    DimensionMismatch(expected: exp, actual: act): "vector dimension mismatch: expected #{exp}, got #{act}"
  end
end

## Default vector configuration (`Cosine` similarity, `Quantized16` 2-byte/dim packing).
fn default_config(dimensions: Int) : VecConfig
  VecConfig(dimensions: dimensions, metric: Cosine, encoding: Quantized16)
end

## Constructs a `VecIndex` with `prefix` and `default_config(dimensions)`.
fn index(prefix: Text, dimensions: Int) : VecIndex
  VecIndex(prefix: prefix, config: default_config(dimensions))
end

## Constructs and validates a `VecIndex` with explicit `config`.
fn index_with_config(prefix: Text, config: VecConfig) : Result(VecIndex, VecError)
  if prefix.empty?
    return Error(InvalidConfig(reason: "index prefix cannot be empty"))
  end
  if prefix.starts_with?("_modb_")
    return Error(InvalidConfig(reason: "index prefix cannot start with '_modb_'"))
  end
  if config.dimensions <= 0 or config.dimensions > 4096
    return Error(
      InvalidConfig(reason: "dimensions must be in 1..4096, got #{config.dimensions}")
    )
  end
  Ok(VecIndex(prefix: prefix, config: config))
end

## Empty corpus statistics matching `cfg`.
fn empty_stats(cfg: VecConfig) : VecStats
  VecStats(
    doc_count: 0,
    dimensions: cfg.dimensions,
    metric: cfg.metric,
    encoding: cfg.encoding,
    total_bytes: 0
  )
end

## Default vector search options with `limit`, no scope filter, and no minimum score filter.
fn default_search_options(limit: Int) : VecSearchOptions
  VecSearchOptions(limit: limit, required_scope: None, min_score: None)
end

## Default hybrid BM25 + Vector RRF options (`rrf_k = 60`, equal 1.0 weights, prefix enabled).
fn default_hybrid_options(limit: Int) : HybridOptions
  cand = if limit * 4 > 20: limit * 4 else: 20
  HybridOptions(
    limit: limit,
    prefix_last_term?: true,
    required_scope: None,
    rrf_k: 60,
    fts_weight: 1.0.to_float,
    vec_weight: 1.0.to_float,
    candidate_limit: cand,
    min_vec_score: None
  )
end

fn data_bucket(idx: VecIndex) : Text
  "#{idx.prefix}_vec_data"
end

fn docs_table(idx: VecIndex) : Table.Table(Text, VecDocMeta)
  Table.text_key[VecDocMeta]("#{idx.prefix}_vec_docs")
end

fn meta_table(idx: VecIndex) : Table.Table(Text, VecStats)
  Table.text_key[VecStats]("#{idx.prefix}_vec_meta")
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, VecError)
  res.map_error(fn(e) Storage(e) end)
end

fn wrap_table(res: Result(T, Table.TableError)) : Result(T, VecError)
  res.map_error(fn(e) TableFailure(e) end)
end

fn wrap_fts(res: Result(T, Fts.FtsError)) : Result(T, VecError)
  res.map_error(fn(e) FtsFailure(e) end)
end

fn validate_index(idx: VecIndex) : Result(Unit, VecError)
  _ = try index_with_config(idx.prefix, idx.config)
  Ok(Unit)
end

fn validate_finite_list(xs: List(Float), label: Text) : Result(Unit, VecError)
  for (i, x) in xs.enumerate
    if x.nan? or x.infinite?
      return Error(InvalidVector(reason: "#{label} element #{i} is not finite"))
    end
  end
  Ok(Unit)
end

fn validate_vector_values(values: List(Float), expected_dims: Int, label: Text) : Result(
  Unit,
  VecError
)
  if values.size != expected_dims
    return Error(DimensionMismatch(expected: expected_dims, actual: values.size))
  end
  validate_finite_list(values, label)
end

## Euclidean L2 norm `sqrt(sum(v_i^2))`.
fn l2_norm(v: List(Float)) : Float
  examples
    l2_norm([3.0, 4.0]) == 5.0
    l2_norm([]) == 0.0
  end

  promise
    not result.nan? and not result.infinite? and result >= 0.0
  end

  var sum_sq = 0.0.to_float
  for x in v
    if not x.nan? and not x.infinite?
      sum_sq += x * x
    end
  end
  res = sum_sq.sqrt
  if res.nan? or res.infinite?: 0.0 else: res
end

## Unit-normalizes `v` (returning all zeros when `l2_norm(v) == 0.0`).
fn normalize(v: List(Float)) : List(Float)
  examples
    normalize([0.0, 0.0]) == [0.0, 0.0]
    (l2_norm(normalize([3.0, 4.0])) - 1.0).abs < 0.000001
  end

  n = l2_norm(v)
  return v.map(fn(_x) 0.0.to_float end) if n <= 0.0
  v.map(fn(x) x / n end)
end

## Exact dot product between equal-prefix slices of `a` and `b`.
fn dot_product(a: List(Float), b: List(Float)) : Float
  examples
    dot_product([1.0, 2.0, 3.0], [4.0, -5.0, 6.0]) == 12.0
  end

  var acc = 0.0.to_float
  for (x, y) in a.zip(b)
    if not x.nan? and not x.infinite? and not y.nan? and not y.infinite?
      acc += x * y
    end
  end
  if acc.nan? or acc.infinite?: 0.0 else: acc
end

## Cosine similarity clamped to `[-1.0, 1.0]` (`0.0` if either vector is zero).
fn cosine_similarity(a: List(Float), b: List(Float)) : Float
  examples
    cosine_similarity([1.0, 0.0], [1.0, 0.0]) == 1.0
    cosine_similarity([1.0, 0.0], [-1.0, 0.0]) == -1.0
    cosine_similarity([0.0, 0.0], [1.0, 0.0]) == 0.0
  end

  promise
    not result.nan? and not result.infinite? and result >= -1.0 and result <= 1.0
  end

  na = l2_norm(a)
  nb = l2_norm(b)
  return 0.0 if na <= 0.0 or nb <= 0.0
  raw = dot_product(a, b) / (na * nb)
  if raw.nan? or raw.infinite?
    0.0
  else if raw > 1.0
    1.0
  else if raw < -1.0
    -1.0
  else
    raw
  end
end

## Euclidean L2 distance `sqrt(sum((a_i - b_i)^2))`.
fn euclidean_distance(a: List(Float), b: List(Float)) : Float
  examples
    euclidean_distance([0.0, 0.0], [3.0, 4.0]) == 5.0
    euclidean_distance([2.0, 2.0], [2.0, 2.0]) == 0.0
  end

  promise
    not result.nan? and not result.infinite? and result >= 0.0
  end

  var sum_sq = 0.0.to_float
  for (x, y) in a.zip(b)
    d = x - y
    sum_sq += d * d
  end
  res = sum_sq.sqrt
  if res.nan? or res.infinite?: 0.0 else: res
end

fn fnv1a_text(seed: Int, chars: List(Char)) : Int
  var h = seed
  for c in chars
    h = h.wrapping_mul(16777619).wrapping_add(c.code)
  end
  h
end

## Deterministic pure-Mo lexical/subword unit-sphere sketch embedding via signed FNV-1a hashed
## word tokens and character 3-grams. Intended for offline tests and zero-dependency demos;
## production callers with neural encoders pass native `List(Float)` embeddings directly.
fn text_sketch_embedding(text: Text, dimensions: Int) : List(Float)
  examples
    text_sketch_embedding("", 8).size == 8
    cosine_similarity(
      text_sketch_embedding("database failover drill", 32),
      text_sketch_embedding("database failover drill", 32)
    ) >
      0.999
  end

  return [] if dimensions <= 0
  tokens = Fts.tokenize(text, 64)
  var acc = {}
  for (ti, tok) in tokens.enumerate
    hw = fnv1a_text(2166136261 + ti.wrapping_mul(31), tok.chars)
    bi = hw.floor_mod(dimensions)
    sgn = if hw.floor_div(dimensions).floor_mod(2) == 0: 1.0.to_float else: -1.0.to_float
    acc = acc.set(bi, (acc.get(bi) or 0.0.to_float) + sgn)

    cs = tok.chars
    if cs.size >= 3
      for j in 0..(cs.size - 2)
        g = [cs.get(j) or ' ', cs.get(j + 1) or ' ', cs.get(j + 2) or ' ']
        hg = fnv1a_text(33554467, g)
        gi = hg.floor_mod(dimensions)
        gsgn = if hg.floor_div(dimensions).floor_mod(2) == 0: 0.5.to_float else: -0.5.to_float
        acc = acc.set(gi, (acc.get(gi) or 0.0.to_float) + gsgn)
      end
    end
  end
  var raw = []
  for i in 0..dimensions
    raw = raw.append(acc.get(i) or 0.0.to_float)
  end
  normalize(raw)
end

fn float_to_clamped_int(x: Float, lo: Int, hi: Int) : Int
  return 0 if x.nan? or x.infinite?
  lo_f = lo.to_float
  hi_f = hi.to_float
  clamped = if x < lo_f: lo_f else if x > hi_f: hi_f else: x
  n = case clamped.round.to_decimal
    Some(d): d.to_int or 0
    None: 0
  end
  if n < lo: lo else if n > hi: hi else: n
end

fn u8_byte(v: Int) : Byte
  c = if v < 0: 0 else if v > 255: 255 else: v
  c.to_byte or (0.to_byte or stop "zero byte")
end

fn quant_max_level(enc: VectorEncoding) : Int
  case enc
    Quantized16: 32767
    Quantized8: 127
  end
end

fn quantize_values(values: List(Float), enc: VectorEncoding) : (List(Int), Float)
  var max_abs = 0.0.to_float
  for x in values
    ax = x.abs
    if ax > max_abs
      max_abs = ax
    end
  end
  max_q = quant_max_level(enc)
  if max_abs <= 0.0
    return (values.map(fn(_x) 0 end), 0.0.to_float)
  end
  scale = max_abs / max_q.to_float
  var ints = []
  for x in values
    ints = ints.append(float_to_clamped_int(x / scale, -max_q, max_q))
  end
  (ints, scale)
end

fn pack_quantized_ints(ints: List(Int), enc: VectorEncoding) : Bytes
  var out = []
  case enc
    Quantized16:
      for q in ints
        u = q + 32767
        out = out.append(u8_byte(u.floor_div(256))).append(u8_byte(u.floor_mod(256)))
      end
    Quantized8:
      for q in ints
        out = out.append(u8_byte(q + 127))
      end
  end
  Bytes.from_list(out)
end

fn decode_lane_signed_int(raw: Bytes, enc: VectorEncoding, lane: Int) : Int
  case enc
    Quantized16:
      u = raw.u16_be_at(lane * 2) or 32767
      u - 32767
    Quantized8:
      b = case raw.get(lane)
        Some(bv): bv.to_int
        None: 127
      end
      b - 127
  end
end

## Decodes raw packed quantized vector bytes back into approximate `Float` elements.
fn decode_vector_bytes(raw: Bytes, encoding: VectorEncoding, dims: Int, scale: Float) : List(Float)
  var out = []
  for i in 0..dims
    q = decode_lane_signed_int(raw, encoding, i)
    out = out.append(q.to_float * scale)
  end
  out
end

fn prepare_values_for_metric(values: List(Float), metric: DistanceMetric) : (
  List(Float),
  Float,
  Bool
)
  norm = l2_norm(values)
  zero? = norm <= 0.0
  prepared = case metric
    Cosine: if zero?: values else: normalize(values)
    DotProduct | Euclidean: values
  end
  (prepared, norm, zero?)
end

fn prepare_query(values: List(Float), cfg: VecConfig) : PreparedQuery
  (prepared, _norm, zero?) = prepare_values_for_metric(values, cfg.metric)
  (q_ints, q_scale) = quantize_values(prepared, cfg.encoding)
  PreparedQuery(q_ints: q_ints, q_scale: q_scale, q_floats: prepared, zero_norm?: zero?)
end

fn score_encoded_vector(
  raw: Bytes,
  meta: VecDocMeta,
  cfg: VecConfig,
  pq: PreparedQuery
) : Result(Float, VecError)
  if meta.dimensions != cfg.dimensions
    return Error(DimensionMismatch(expected: cfg.dimensions, actual: meta.dimensions))
  end
  dims = cfg.dimensions
  expected_bytes = case cfg.encoding
    Quantized16: dims * 2
    Quantized8: dims
  end
  if raw.size != expected_bytes
    return Error(
      InvalidVector(
        reason: "corrupt packed vector '#{meta.doc_id}': expected #{expected_bytes} bytes, got #{raw.size}"
      )
    )
  end

  case cfg.metric
    Cosine:
      return Ok(0.0) if pq.zero_norm? or meta.zero_norm? or meta.scale <= 0.0 or pq.q_scale <= 0.0
      var acc = 0
      for i in 0..dims
        vi = decode_lane_signed_int(raw, cfg.encoding, i)
        qi = pq.q_ints.get(i) or 0
        acc += vi * qi
      end
      s = acc.to_float * meta.scale * pq.q_scale
      if s.nan? or s.infinite?
        Ok(0.0)
      else if s > 1.0
        Ok(1.0)
      else if s < -1.0
        Ok(-1.0)
      else
        Ok(s)
      end
    DotProduct:
      return Ok(0.0) if meta.scale <= 0.0 or pq.q_scale <= 0.0
      var acc = 0
      for i in 0..dims
        vi = decode_lane_signed_int(raw, cfg.encoding, i)
        qi = pq.q_ints.get(i) or 0
        acc += vi * qi
      end
      s = acc.to_float * meta.scale * pq.q_scale
      Ok(if s.nan? or s.infinite?: 0.0 else: s)
    Euclidean:
      var sum_sq = 0.0.to_float
      for i in 0..dims
        vi = decode_lane_signed_int(raw, cfg.encoding, i).to_float * meta.scale
        qi = pq.q_floats.get(i) or 0.0
        d = vi - qi
        sum_sq += d * d
      end
      dist = sum_sq.sqrt
      Ok(if dist.nan? or dist.infinite?: 0.0 else: 1.0 / (1.0 + dist))
  end
end

fn load_stats_tx(tx: WriteTx, idx: VecIndex) : Result(VecStats, VecError)
  res = try wrap_table(Table.tx_get(tx, meta_table(idx), "stats"))
  Ok(res or empty_stats(idx.config))
end

fn check_compatible_stats(st: VecStats, cfg: VecConfig) : Result(Unit, VecError)
  return Ok(Unit) if st.doc_count == 0
  if st.dimensions != cfg.dimensions
    return Error(DimensionMismatch(expected: st.dimensions, actual: cfg.dimensions))
  end
  if st.metric != cfg.metric or st.encoding != cfg.encoding
    return Error(InvalidConfig(reason: "index metric/encoding does not match persisted metadata"))
  end
  Ok(Unit)
end

## Removes `doc_id` from `idx` inside `tx` (idempotent if absent, cleans up across any old scope).
fn tx_remove_vector(tx: WriteTx, idx: VecIndex, doc_id: Text) : Result(WriteTx, VecError)
  _ = try validate_index(idx)
  return Ok(tx) if doc_id.empty?

  dtbl = docs_table(idx)
  case try wrap_table(Table.tx_get(tx, dtbl, doc_id))
    None: Ok(tx)
    Some(old_meta):
      dkey = Table.encode_composite_key(old_meta.scope.bytes, doc_id.bytes)
      cur0 = try wrap_modb(Modb.tx_delete(tx, data_bucket(idx), dkey))
      cur1 = try wrap_table(Table.delete(cur0, dtbl, doc_id))
      prev_st = try load_stats_tx(cur1, idx)
      removed_bytes = case prev_st.encoding
        Quantized16: old_meta.dimensions * 2
        Quantized8: old_meta.dimensions
      end
      next_docs = if prev_st.doc_count > 1: prev_st.doc_count - 1 else: 0
      if next_docs == 0
        wrap_table(Table.delete(cur1, meta_table(idx), "stats"))
      else
        next_bytes = if prev_st.total_bytes > removed_bytes
          prev_st.total_bytes - removed_bytes
        else
          0
        end
        next_st = VecStats(
          doc_count: next_docs,
          dimensions: prev_st.dimensions,
          metric: prev_st.metric,
          encoding: prev_st.encoding,
          total_bytes: next_bytes
        )
        wrap_table(Table.put(cur1, meta_table(idx), "stats", next_st))
      end
  end
end

## Atomically stores (or replaces, including cross-scope moves) `input` inside `tx`.
fn tx_put_vector(tx: WriteTx, idx: VecIndex, input: VectorInput) : Result(WriteTx, VecError)
  _ = try validate_index(idx)
  if input.doc_id.empty?
    return Error(InvalidVector(reason: "doc_id cannot be empty"))
  end
  _ = try validate_vector_values(input.values, idx.config.dimensions, "document '#{input.doc_id}'")

  cur_st = try load_stats_tx(tx, idx)
  try check_compatible_stats(cur_st, idx.config)

  var cur = try tx_remove_vector(tx, idx, input.doc_id)
  (prepared, norm, zero?) = prepare_values_for_metric(input.values, idx.config.metric)
  (q_ints, scale) = quantize_values(prepared, idx.config.encoding)
  packed = pack_quantized_ints(q_ints, idx.config.encoding)

  dkey = Table.encode_composite_key(input.scope.bytes, input.doc_id.bytes)
  cur = try wrap_modb(Modb.tx_put(cur, data_bucket(idx), dkey, packed))

  meta = VecDocMeta(
    doc_id: input.doc_id,
    scope: input.scope,
    dimensions: idx.config.dimensions,
    norm: norm,
    scale: scale,
    zero_norm?: zero?
  )
  cur = try wrap_table(Table.put(cur, docs_table(idx), input.doc_id, meta))

  prev_after = try load_stats_tx(cur, idx)
  next_st = VecStats(
    doc_count: prev_after.doc_count + 1,
    dimensions: idx.config.dimensions,
    metric: idx.config.metric,
    encoding: idx.config.encoding,
    total_bytes: prev_after.total_bytes + packed.size
  )
  wrap_table(Table.put(cur, meta_table(idx), "stats", next_st))
end

## Stores or replaces a single vector in its own atomic `Modb` commit.
fn put_vector(store: Store, idx: VecIndex, input: VectorInput) : Result(Store, VecError)
  tx = Modb.begin_write(store)
  tx1 = try tx_put_vector(tx, idx, input)
  wrap_modb(Modb.commit(tx1))
end

## Stores or replaces a batch of vectors in one atomic `Modb` commit.
fn put_vectors(store: Store, idx: VecIndex, inputs: List(VectorInput)) : Result(Store, VecError)
  var tx = Modb.begin_write(store)
  for inp in inputs
    tx = try tx_put_vector(tx, idx, inp)
  end
  wrap_modb(Modb.commit(tx))
end

## Removes `doc_id` from `idx` in its own atomic `Modb` commit.
fn remove_vector(store: Store, idx: VecIndex, doc_id: Text) : Result(Store, VecError)
  tx = Modb.begin_write(store)
  tx1 = try tx_remove_vector(tx, idx, doc_id)
  wrap_modb(Modb.commit(tx1))
end

## Reads committed vector index statistics (returns `empty_stats(idx.config)` when empty).
fn stats(store: Store, idx: VecIndex) : Result(VecStats, VecError)
  _ = try validate_index(idx)
  res = try wrap_table(Table.get(store, meta_table(idx), "stats"))
  Ok(res or empty_stats(idx.config))
end

## Reads committed metadata for `doc_id`, if indexed.
fn get_doc(store: Store, idx: VecIndex, doc_id: Text) : Result(Option(VecDocMeta), VecError)
  _ = try validate_index(idx)
  wrap_table(Table.get(store, docs_table(idx), doc_id))
end

## Reconstructs the approximate stored vector for `doc_id` (restoring `norm` scaling for `Cosine`).
fn get_vector(store: Store, idx: VecIndex, doc_id: Text) : Result(Option(List(Float)), VecError)
  _ = try validate_index(idx)
  case try get_doc(store, idx, doc_id)
    None: Ok(None)
    Some(meta):
      dkey = Table.encode_composite_key(meta.scope.bytes, doc_id.bytes)
      case try wrap_modb(Modb.get(store, data_bucket(idx), dkey))
        None: Ok(None)
        Some(raw):
          decoded = decode_vector_bytes(raw, idx.config.encoding, meta.dimensions, meta.scale)
          restored = case idx.config.metric
            Cosine:
              if meta.zero_norm?: decoded else: decoded.map(fn(x) x * meta.norm end)
            DotProduct | Euclidean: decoded
          end
          Ok(Some(restored))
      end
  end
end

## Searches `idx` while gating every candidate fail-closed through `allow_doc(doc_id, scope)`.
fn search_filtered(
  store: Store,
  idx: VecIndex,
  query_vec: List(Float),
  opts: VecSearchOptions,
  allow_doc: fn(Text, Text) : Bool
) : Result(List(VecHit), VecError)
  _ = try validate_index(idx)
  try validate_vector_values(query_vec, idx.config.dimensions, "query vector")
  return Ok([]) if opts.limit <= 0

  st = try stats(store, idx)
  try check_compatible_stats(st, idx.config)
  return Ok([]) if st.doc_count <= 0

  pq = prepare_query(query_vec, idx.config)
  dbucket = data_bucket(idx)
  raw_entries = case opts.required_scope
    Some(req_scope):
      pfx = Table.encode_composite_key(req_scope.bytes, Bytes.empty)
      try wrap_modb(Modb.prefix_scan(store, dbucket, pfx, 0))
    None: try wrap_modb(Modb.scan(store, dbucket, None, None, 0))
  end

  dtbl = docs_table(idx)
  var hits = []
  for (comp_key, raw_bytes) in raw_entries
    (scope_b, doc_id_b) = try wrap_table(Table.decode_composite_key(comp_key))
    scope = try wrap_table(Table.decode_text_key(scope_b))
    doc_id = try wrap_table(Table.decode_text_key(doc_id_b))
    if allow_doc(doc_id, scope)
      case try wrap_table(Table.get(store, dtbl, doc_id))
        None: Unit
        Some(meta):
          sc = try score_encoded_vector(raw_bytes, meta, idx.config, pq)
          passes_min? = case opts.min_score
            Some(ms): sc >= ms
            None: true
          end
          if passes_min?
            hits = hits.append(VecHit(doc_id: doc_id, scope: meta.scope, score: sc))
          end
      end
    end
  end

  ordered = hits.sort_by(fn(h) h.doc_id end).sort_by_desc(fn(h) h.score end)
  Ok(ordered.take(opts.limit))
end

## Searches `idx` by similarity/score (respecting `opts.required_scope` and `opts.min_score`).
fn search(store: Store, idx: VecIndex, query_vec: List(Float), opts: VecSearchOptions) : Result(
  List(VecHit),
  VecError
)
  search_filtered(store, idx, query_vec, opts, fn(_id, _scope) true end)
end

## Executes fail-closed hybrid search over `fts_idx` (BM25+) and `vec_idx`, fusing ranks via
## weighted Reciprocal Rank Fusion (`w_fts / (k + r_fts) + w_vec / (k + r_vec)`).
fn hybrid_search_filtered(
  store: Store,
  fts_idx: Fts.FtsIndex,
  vec_idx: VecIndex,
  query_text: Text,
  query_vec: Option(List(Float)),
  opts: HybridOptions,
  allow_doc: fn(Text, Text) : Bool
) : Result(List(HybridHit), VecError)
  _ = try validate_index(vec_idx)
  if opts.rrf_k < 1
    return Error(InvalidConfig(reason: "rrf_k must be >= 1, got #{opts.rrf_k}"))
  end
  if opts.fts_weight.nan? or opts.fts_weight.infinite? or opts.fts_weight < 0.0
    return Error(InvalidConfig(reason: "fts_weight must be finite and >= 0"))
  end
  if opts.vec_weight.nan? or opts.vec_weight.infinite? or opts.vec_weight < 0.0
    return Error(InvalidConfig(reason: "vec_weight must be finite and >= 0"))
  end
  return Ok([]) if opts.limit <= 0

  cand_lim = if opts.candidate_limit > opts.limit: opts.candidate_limit else: opts.limit * 4

  fts_hits = if opts.fts_weight > 0.0 and not query_text.trim.empty?
    fopts = Fts.SearchOptions(
      limit: cand_lim,
      prefix_last_term?: opts.prefix_last_term?,
      required_scope: opts.required_scope
    )
    try wrap_fts(Fts.search_filtered(store, fts_idx, query_text, fopts, allow_doc))
  else
    []
  end

  vec_hits = case query_vec
    Some(qv) if opts.vec_weight > 0.0 and not qv.empty?:
      vopts = VecSearchOptions(
        limit: cand_lim,
        required_scope: opts.required_scope,
        min_score: opts.min_vec_score
      )
      try search_filtered(store, vec_idx, qv, vopts, allow_doc)
    Some(_) | None: []
  end

  k_f = opts.rrf_k.to_float
  var acc_map = {}

  for (i, fh) in fts_hits.enumerate
    rank = i + 1
    contrib = opts.fts_weight / (k_f + rank.to_float)
    acc_map = acc_map.set(
      fh.doc_id,
      HybridAcc(
        scope: fh.scope,
        score: contrib,
        fts_rank: Some(rank),
        fts_score: Some(fh.score),
        vec_rank: None,
        vec_score: None,
        matched_terms: fh.matched_terms,
        matched_fields: fh.matched_fields
      )
    )
  end

  for (i, vh) in vec_hits.enumerate
    rank = i + 1
    contrib = opts.vec_weight / (k_f + rank.to_float)
    prev_opt = acc_map.get(vh.doc_id)
    next = case prev_opt
      Some(p):
        HybridAcc(
          scope: p.scope,
          score: p.score + contrib,
          fts_rank: p.fts_rank,
          fts_score: p.fts_score,
          vec_rank: Some(rank),
          vec_score: Some(vh.score),
          matched_terms: p.matched_terms,
          matched_fields: p.matched_fields
        )
      None:
        HybridAcc(
          scope: vh.scope,
          score: contrib,
          fts_rank: None,
          fts_score: None,
          vec_rank: Some(rank),
          vec_score: Some(vh.score),
          matched_terms: [],
          matched_fields: []
        )
    end
    acc_map = acc_map.set(vh.doc_id, next)
  end

  var out = []
  for (doc_id, acc) in acc_map.entries
    out = out.append(
      HybridHit(
        doc_id: doc_id,
        scope: acc.scope,
        score: acc.score,
        fts_rank: acc.fts_rank,
        fts_score: acc.fts_score,
        vec_rank: acc.vec_rank,
        vec_score: acc.vec_score,
        matched_terms: acc.matched_terms,
        matched_fields: acc.matched_fields
      )
    )
  end

  ordered = out.sort_by(fn(h) h.doc_id end).sort_by_desc(fn(h) h.score end)
  Ok(ordered.take(opts.limit))
end

## Executes hybrid BM25 + Vector RRF search without a custom predicate filter.
fn hybrid_search(
  store: Store,
  fts_idx: Fts.FtsIndex,
  vec_idx: VecIndex,
  query_text: Text,
  query_vec: Option(List(Float)),
  opts: HybridOptions
) : Result(List(HybridHit), VecError)
  hybrid_search_filtered(store, fts_idx, vec_idx, query_text, query_vec, opts, fn(_id, _s) true end)
end

test "Modb.Vec Q16/Q8 cosine, dot, euclidean, cross-scope move, delete, and hybrid RRF"
  files = Files.in_memory({})
  assert Modb.open(files, "vec-smoke.modb") is Ok(db0)
  v_idx = index("docs", 4)
  f_idx = Fts.index("docs")

  inputs = [
    VectorInput(doc_id: "d1", scope: "eng", values: [1.0, 0.2, 0.0, 0.0]),
    VectorInput(doc_id: "d2", scope: "eng", values: [0.2, 1.0, 0.0, 0.0]),
    VectorInput(doc_id: "d3", scope: "sales", values: [0.95, 0.05, 0.0, 0.0])
  ]
  assert put_vectors(db0, v_idx, inputs) is Ok(db1)
  assert stats(db1, v_idx) is Ok(st1) and st1.doc_count == 3 and st1.total_bytes == 24

  assert search(db1, v_idx, [1.0, 0.0, 0.0, 0.0], default_search_options(10)) is Ok(hits)
  assert hits.size == 3
  assert (hits.first or stop "h0").doc_id == "d3"
  assert (hits.get(1) or stop "h1").doc_id == "d1"
  assert (hits.get(2) or stop "h2").doc_id == "d2"

  # Move d2 to "ops" scope and confirm old "eng" scope no longer matches d2
  assert put_vector(db1, v_idx, VectorInput(doc_id: "d2", scope: "ops", values: [0.99, 0.01, 0.0, 0.0])) is
    Ok(db2)
  eng_opts = VecSearchOptions(limit: 10, required_scope: Some("eng"), min_score: None)
  assert search(db2, v_idx, [1.0, 0.0, 0.0, 0.0], eng_opts) is Ok(eng_hits)
  assert eng_hits.size == 1 and (eng_hits.first or stop "eh").doc_id == "d1"

  # Euclidean + Quantized8 smoke check
  e_idx = index_with_config("euc", VecConfig(dimensions: 2, metric: Euclidean, encoding: Quantized8))
  assert e_idx is Ok(euc)
  assert put_vectors(
    db2,
    euc,
    [
      VectorInput(doc_id: "near", scope: "s", values: [1.0, 1.0]),
      VectorInput(doc_id: "far", scope: "s", values: [8.0, 8.0])
    ]
  ) is
    Ok(db3)
  assert search(db3, euc, [1.0, 1.0], default_search_options(2)) is Ok(eh)
  assert (eh.first or stop "e0").doc_id == "near" and (eh.first or stop "e0").score > 0.99

  # Hybrid BM25 + Vector RRF boost when both channels agree
  f_docs = [
    Fts.DocumentInput(
      doc_id: "d1",
      scope: "eng",
      fields: [Fts.FieldInput(name: "title", text: "database failover runbook", weight: 3)]
    ),
    Fts.DocumentInput(
      doc_id: "d3",
      scope: "sales",
      fields: [Fts.FieldInput(name: "title", text: "quarterly enterprise pipeline", weight: 3)]
    )
  ]
  assert Fts.index_documents(db3, f_idx, f_docs) is Ok(db4)
  assert hybrid_search(
    db4,
    f_idx,
    v_idx,
    "database failover",
    Some([0.96, 0.15, 0.0, 0.0]),
    default_hybrid_options(5)
  ) is
    Ok(hhits)
  assert (hhits.first or stop "hh0").doc_id == "d1"
  assert (hhits.first or stop "hh0").fts_rank == Some(1)
  assert (hhits.first or stop "hh0").vec_rank is Some(_)

  assert remove_vector(db4, v_idx, "d1") is Ok(db5)
  assert get_doc(db5, v_idx, "d1") == Ok(None)
end
