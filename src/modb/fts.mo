## MoDB Full-Text Search: crash-safe, transactional pure-Mo BM25 inverted index
## built on top of `Modb` and `Modb.Table` composite keys.
module Modb.Fts
expose FtsError(..),
FtsConfig(..),
FtsIndex(..),
FieldInput(..),
DocumentInput(..),
Posting(..),
IndexedDoc(..),
FtsStats(..),
SearchOptions(..),
SearchHit(..),
to_text,
default_config,
index,
index_with_config,
empty_stats,
default_search_options,
tokenize,
ln_pos,
bm25_idf,
bm25_tf_score,
tx_index_document,
tx_remove_document,
index_document,
index_documents,
remove_document,
stats,
get_doc,
term_df,
search,
search_filtered
use Json
use Modb{Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Table

ln2 = 0.6931471805599453.to_float
ln2_hi = 0.6931471803691238.to_float
sqrt2 = 1.4142135623730951.to_float
inv_sqrt2 = 0.7071067811865476.to_float

## Every failure returned by `Modb.Fts` operations.
enum FtsError
  Storage(ModbError)
  TableFailure(Table.TableError)
  InvalidConfig(reason: Text)
  InvalidDocument(reason: Text)
end

## Formats an `FtsError` as a human-readable diagnostic.
fn to_text(err: FtsError) : Text
  case err
    Storage(e): e.to_text
    TableFailure(e): e.to_text
    InvalidConfig(reason: r): "invalid FTS config: #{r}"
    InvalidDocument(reason: r): "invalid FTS document: #{r}"
  end
end

## BM25 scoring and tokenization configuration for an `FtsIndex`.
struct FtsConfig
  k1: Float
  b: Float
  max_prefix_expansions: Int
  max_token_bytes: Int
end

## Handle identifying a namespaced full-text index inside a `Modb` store.
struct FtsIndex
  prefix: Text
  config: FtsConfig
end

## One weighted text field belonging to an indexed document (e.g. `title` weight 3, `body` weight 1).
struct FieldInput
  name: Text
  text: Text
  weight: Int
end

## Document payload indexed atomically into an `FtsIndex`.
struct DocumentInput
  doc_id: Text
  scope: Text
  fields: List(FieldInput)
end

## Per-(term, doc) posting stored in `{prefix}_fts_postings`.
struct Posting
  tf: Int
  weighted_tf: Int
  fields: List(Text)
end

## Stored per-document summary enabling $O(\text{unique\_terms})$ updates/deletes and scope filtering.
struct IndexedDoc
  doc_id: Text
  scope: Text
  token_count: Int
  weighted_len: Int
  terms: List(Text)
end

## Exact integer corpus statistics stored at key `"stats"` in `{prefix}_fts_meta`.
struct FtsStats
  doc_count: Int
  total_tokens: Int
  total_weighted_len: Int
end

## Query options controlling hit limit, trailing-token prefix expansion, and optional scope filtering.
struct SearchOptions
  limit: Int
  prefix_last_term?: Bool
  required_scope: Option(Text)
end

## Ranked BM25 search hit returned by `search` and `search_filtered`.
struct SearchHit
  doc_id: Text
  scope: Text
  score: Float
  matched_terms: List(Text)
  matched_fields: List(Text)
end

struct HitAcc
  scope: Text
  score: Float
  terms: List(Text)
  fields: List(Text)
end

## Default BM25 configuration (`k1 = 1.2`, `b = 0.75`, `max_prefix_expansions = 32`, `max_token_bytes = 64`).
fn default_config() : FtsConfig
  FtsConfig(k1: 1.2.to_float, b: 0.75.to_float, max_prefix_expansions: 32, max_token_bytes: 64)
end

## Constructs an `FtsIndex` using `prefix` and `default_config()`.
fn index(prefix: Text) : FtsIndex
  FtsIndex(prefix: prefix, config: default_config())
end

## Constructs and validates an `FtsIndex` with explicit `config`.
fn index_with_config(prefix: Text, config: FtsConfig) : Result(FtsIndex, FtsError)
  if prefix.empty?
    return Error(InvalidConfig(reason: "index prefix cannot be empty"))
  end
  if config.k1.nan? or config.k1.infinite? or config.k1 < 0.0
    return Error(InvalidConfig(reason: "k1 must be finite and >= 0"))
  end
  if config.b.nan? or config.b.infinite? or config.b < 0.0 or config.b > 1.0
    return Error(InvalidConfig(reason: "b must be finite in [0, 1]"))
  end
  if config.max_prefix_expansions <= 0
    return Error(InvalidConfig(reason: "max_prefix_expansions must be > 0"))
  end
  if config.max_token_bytes < 4
    return Error(InvalidConfig(reason: "max_token_bytes must be >= 4"))
  end
  Ok(FtsIndex(prefix: prefix, config: config))
end

## Empty corpus statistics (`0` documents, `0` tokens, `0` weighted length).
fn empty_stats() : FtsStats
  FtsStats(doc_count: 0, total_tokens: 0, total_weighted_len: 0)
end

## Default search options with `limit`, exact term matching, and no required scope filter.
fn default_search_options(limit: Int) : SearchOptions
  SearchOptions(limit: limit, prefix_last_term?: false, required_scope: None)
end

fn postings_bucket(idx: FtsIndex) : Text
  "#{idx.prefix}_fts_postings"
end

fn docs_bucket(idx: FtsIndex) : Text
  "#{idx.prefix}_fts_docs"
end

fn df_bucket(idx: FtsIndex) : Text
  "#{idx.prefix}_fts_df"
end

fn meta_bucket(idx: FtsIndex) : Text
  "#{idx.prefix}_fts_meta"
end

fn docs_table(idx: FtsIndex) : Table.Table(Text, IndexedDoc)
  Table.text_key[IndexedDoc](docs_bucket(idx))
end

fn df_table(idx: FtsIndex) : Table.Table(Text, Int)
  Table.text_key[Int](df_bucket(idx))
end

fn meta_table(idx: FtsIndex) : Table.Table(Text, FtsStats)
  Table.text_key[FtsStats](meta_bucket(idx))
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, FtsError)
  res.map_error(fn(e) Storage(e) end)
end

fn wrap_table(res: Result(T, Table.TableError)) : Result(T, FtsError)
  res.map_error(fn(e) TableFailure(e) end)
end

fn fold_word_char(ch: Char) : Option(Char)
  return Some(ch.ascii_lowercase) if ch.ascii_letter? or ch.ascii_digit?
  c = ch.code
  return None if c < 192 or c == 215 or c == 247
  return None if c >= 8192 and c <= 8303
  if (c >= 192 and c <= 214) or (c >= 216 and c <= 222)
    return (c + 32).to_char
  end
  Some(ch)
end

## Tokenizes `text` into lowercase normalized word tokens bounded to `max_token_bytes` UTF-8 bytes.
fn tokenize(text: Text, max_token_bytes: Int) : List(Text)
  examples
    tokenize("Hello, World!", 64) == ["hello", "world"]
    tokenize("Arvo.Oidc + deploy_prod-v2", 64) == ["arvo", "oidc", "deploy", "prod", "v2"]
    tokenize("Café “Résumé”—v1", 64) == ["café", "résumé", "v1"]
    tokenize("abcdef", 4) == ["abcd"]
    tokenize("   ... --- ", 64) == []
  end

  cap = if max_token_bytes < 4: 4 else: max_token_bytes
  var tokens = []
  var cur_chars = []
  var cur_bytes = 0

  for ch in text.chars
    case fold_word_char(ch)
      Some(wc):
        cb = wc.to_text.byte_count
        if cur_bytes + cb <= cap
          cur_chars = cur_chars.append(wc)
          cur_bytes += cb
        end
      None:
        if not cur_chars.empty?
          tokens = tokens.append(Text.from_chars(cur_chars))
          cur_chars = []
          cur_bytes = 0
        end
    end
  end

  if not cur_chars.empty?
    tokens = tokens.append(Text.from_chars(cur_chars))
  end
  tokens
end

fn pow2_step(n: Int) : Float
  var acc = 1.0.to_float
  var base = if n >= 0: 2.0.to_float else: 0.5.to_float
  var rem = n.abs
  while rem > 0
    if rem.floor_mod(2) == 1
      acc = acc * base
    end
    base = base * base
    rem = rem.floor_div(2)
  end
  acc
end

## Pure-Mo natural logarithm `ln(x)` for positive finite inputs (returns `0.0` otherwise).
fn ln_pos(x: Float) : Float
  examples
    ln_pos(1.0) == 0.0
    (ln_pos(2.718281828459045) - 1.0).abs < 0.000000000001
    ln_pos(0.0) == 0.0
    ln_pos(-3.0) == 0.0
  end

  promise "ln_pos is always finite and equals 0 for x == 1"
    not result.nan? and not result.infinite?
    x == 1.0 implies result == 0.0
  end

  return 0.0 if x.nan? or x.infinite? or x <= 0.0 or x == 1.0

  p64 = pow2_step(64)
  p16 = pow2_step(16)
  p4 = pow2_step(4)
  inv_p64 = pow2_step(-64)
  inv_p16 = pow2_step(-16)
  inv_p4 = pow2_step(-4)

  var m = x
  var k = 0

  while m >= p64
    m = m * inv_p64
    k += 64
  end
  while m >= p16
    m = m * inv_p16
    k += 16
  end
  while m >= p4
    m = m * inv_p4
    k += 4
  end
  while m > sqrt2
    m = m * 0.5
    k += 1
  end

  while m < inv_p64
    m = m * p64
    k -= 64
  end
  while m < inv_p16
    m = m * p16
    k -= 16
  end
  while m < inv_p4
    m = m * p4
    k -= 4
  end
  while m < inv_sqrt2
    m = m * 2.0
    k -= 1
  end

  t = (m - 1.0) / (m + 1.0)
  t2 = t * t
  var term = t
  var series = t
  var denom = 1
  for _ in 0..14
    denom += 2
    term = term * t2
    series += term / denom.to_float
  end

  out = 2.0 * series + k.to_float * ln2
  if out.nan? or out.infinite?: 0.0 else: out
end

## Non-negative BM25+ inverse document frequency `ln(1 + (N - df + 0.5) / (df + 0.5))`.
fn bm25_idf(doc_count: Int, df: Int) : Float
  examples
    bm25_idf(0, 0) == 0.0
    bm25_idf(10, 0) == 0.0
    bm25_idf(10, 1) > bm25_idf(10, 5)
    bm25_idf(1, 1) > 0.0
  end

  promise "idf is finite and non-negative"
    not result.nan? and not result.infinite? and result >= 0.0
  end

  return 0.0 if doc_count <= 0 or df <= 0
  n = doc_count.to_float
  d = df.to_float
  eff_d = if d > n: n else: d
  raw = ln_pos(1.0 + (n - eff_d + 0.5) / (eff_d + 0.5))
  if raw < 0.0 or raw.nan? or raw.infinite?: 0.0 else: raw
end

## BM25 term-frequency saturation component normalized by document length.
fn bm25_tf_score(weighted_tf: Int, weighted_len: Int, avg_weighted_len: Float, k1: Float, b: Float) : Float
  examples
    bm25_tf_score(0, 10, 10.0, 1.2, 0.75) == 0.0
    bm25_tf_score(3, 10, 10.0, 1.2, 0.75) > bm25_tf_score(1, 10, 10.0, 1.2, 0.75)
    bm25_tf_score(1, 5, 20.0, 1.2, 0.75) > bm25_tf_score(1, 40, 20.0, 1.2, 0.75)
  end

  promise "tf score is finite and non-negative"
    not result.nan? and not result.infinite? and result >= 0.0
  end

  return 0.0 if weighted_tf <= 0
  tf = weighted_tf.to_float
  dl = if weighted_len > 0: weighted_len.to_float else: 1.0.to_float
  avgdl = if avg_weighted_len > 0.0 and not avg_weighted_len.nan? and not avg_weighted_len.infinite?
    avg_weighted_len
  else
    dl
  end
  eff_k1 = if k1 >= 0.0 and not k1.nan? and not k1.infinite?: k1 else: 1.2.to_float
  eff_b = if b >= 0.0 and b <= 1.0 and not b.nan?: b else: 0.75.to_float
  denom = tf + eff_k1 * (1.0 - eff_b + eff_b * (dl / avgdl))
  return 0.0 if denom <= 0.0 or denom.nan? or denom.infinite?
  score = (tf * (eff_k1 + 1.0)) / denom
  if score < 0.0 or score.nan? or score.infinite?: 0.0 else: score
end

fn validate_index(idx: FtsIndex) : Result(Unit, FtsError)
  _ = try index_with_config(idx.prefix, idx.config)
  Ok(Unit)
end

fn validate_document(doc: DocumentInput) : Result(Unit, FtsError)
  if doc.doc_id.empty?
    return Error(InvalidDocument(reason: "doc_id cannot be empty"))
  end
  for field in doc.fields
    if field.name.empty?
      return Error(InvalidDocument(reason: "field name cannot be empty"))
    end
    if field.weight <= 0
      return Error(InvalidDocument(reason: "field '#{field.name}' weight must be >= 1"))
    end
  end
  Ok(Unit)
end

fn append_unique_text(xs: List(Text), item: Text) : List(Text)
  if xs.contains?(item): xs else: xs.append(item)
end

fn concat_unique_texts(base: List(Text), extra: List(Text)) : List(Text)
  var out = base
  for item in extra
    out = append_unique_text(out, item)
  end
  out
end

fn max_int(a: Int, b: Int) : Int
  if a > b: a else: b
end

fn load_stats_tx(tx: WriteTx, idx: FtsIndex) : Result(FtsStats, FtsError)
  res = try wrap_table(Table.tx_get(tx, meta_table(idx), "stats"))
  Ok(res or empty_stats())
end

## Removes `doc_id` and all of its postings/df contributions inside `tx` (idempotent if absent).
fn tx_remove_document(tx: WriteTx, idx: FtsIndex, doc_id: Text) : Result(WriteTx, FtsError)
  _ = try validate_index(idx)
  return Ok(tx) if doc_id.empty?

  case try wrap_table(Table.tx_get(tx, docs_table(idx), doc_id))
    None: Ok(tx)
    Some(old_doc):
      var cur = tx
      dft = df_table(idx)
      for term in old_doc.terms
        pkey = Table.encode_composite_key(term.bytes, doc_id.bytes)
        cur = try wrap_modb(Modb.tx_delete(cur, postings_bucket(idx), pkey))
        cur_df = (try wrap_table(Table.tx_get(cur, dft, term))) or 0
        if cur_df <= 1
          cur = try wrap_table(Table.delete(cur, dft, term))
        else
          cur = try wrap_table(Table.put(cur, dft, term, cur_df - 1))
        end
      end

      cur = try wrap_table(Table.delete(cur, docs_table(idx), doc_id))
      prev_stats = try load_stats_tx(cur, idx)
      next_docs = max_int(0, prev_stats.doc_count - 1)
      if next_docs == 0
        wrap_table(Table.delete(cur, meta_table(idx), "stats"))
      else
        next_stats = FtsStats(
          doc_count: next_docs,
          total_tokens: max_int(0, prev_stats.total_tokens - old_doc.token_count),
          total_weighted_len: max_int(0, prev_stats.total_weighted_len - old_doc.weighted_len)
        )
        wrap_table(Table.put(cur, meta_table(idx), "stats", next_stats))
      end
  end
end

## Atomically indexes (or replaces) `doc` inside `tx`, updating postings, df, docs, and stats.
fn tx_index_document(tx: WriteTx, idx: FtsIndex, doc: DocumentInput) : Result(WriteTx, FtsError)
  _ = try validate_index(idx)
  _ = try validate_document(doc)

  var cur = try tx_remove_document(tx, idx, doc.doc_id)
  var token_count = 0
  var weighted_len = 0
  var postings = {}

  for field in doc.fields
    tokens = tokenize(field.text, idx.config.max_token_bytes)
    token_count += tokens.size
    weighted_len += tokens.size * field.weight
    for tok in tokens
      prev = postings.get(tok) or Posting(tf: 0, weighted_tf: 0, fields: [])
      next_fields = append_unique_text(prev.fields, field.name)
      postings = postings.set(
        tok,
        Posting(tf: prev.tf + 1, weighted_tf: prev.weighted_tf + field.weight, fields: next_fields)
      )
    end
  end

  unique_terms = postings.keys.sort
  dft = df_table(idx)
  pbucket = postings_bucket(idx)

  for term in unique_terms
    posting = postings.get(term) or Posting(tf: 0, weighted_tf: 0, fields: [])
    sorted_posting = Posting(
      tf: posting.tf,
      weighted_tf: posting.weighted_tf,
      fields: posting.fields.sort
    )
    pkey = Table.encode_composite_key(term.bytes, doc.doc_id.bytes)
    cur = try wrap_modb(Modb.tx_put(cur, pbucket, pkey, Json.encode(sorted_posting).bytes))
    prev_df = (try wrap_table(Table.tx_get(cur, dft, term))) or 0
    cur = try wrap_table(Table.put(cur, dft, term, prev_df + 1))
  end

  indexed = IndexedDoc(
    doc_id: doc.doc_id,
    scope: doc.scope,
    token_count: token_count,
    weighted_len: weighted_len,
    terms: unique_terms
  )
  cur = try wrap_table(Table.put(cur, docs_table(idx), doc.doc_id, indexed))

  prev_stats = try load_stats_tx(cur, idx)
  next_stats = FtsStats(
    doc_count: prev_stats.doc_count + 1,
    total_tokens: prev_stats.total_tokens + token_count,
    total_weighted_len: prev_stats.total_weighted_len + weighted_len
  )
  wrap_table(Table.put(cur, meta_table(idx), "stats", next_stats))
end

## Indexes or replaces a single `doc` in its own atomic `Modb` commit.
fn index_document(store: Store, idx: FtsIndex, doc: DocumentInput) : Result(Store, FtsError)
  tx = Modb.begin_write(store)
  tx1 = try tx_index_document(tx, idx, doc)
  wrap_modb(Modb.commit(tx1))
end

## Indexes or replaces a batch of `docs` in a single atomic `Modb` commit.
fn index_documents(store: Store, idx: FtsIndex, docs: List(DocumentInput)) : Result(Store, FtsError)
  var tx = Modb.begin_write(store)
  for doc in docs
    tx = try tx_index_document(tx, idx, doc)
  end
  wrap_modb(Modb.commit(tx))
end

## Removes `doc_id` from `idx` in its own atomic `Modb` commit.
fn remove_document(store: Store, idx: FtsIndex, doc_id: Text) : Result(Store, FtsError)
  tx = Modb.begin_write(store)
  tx1 = try tx_remove_document(tx, idx, doc_id)
  wrap_modb(Modb.commit(tx1))
end

## Reads committed corpus statistics from `idx` (returns `empty_stats()` if empty).
fn stats(store: Store, idx: FtsIndex) : Result(FtsStats, FtsError)
  _ = try validate_index(idx)
  res = try wrap_table(Table.get(store, meta_table(idx), "stats"))
  Ok(res or empty_stats())
end

## Reads the committed `IndexedDoc` metadata for `doc_id`, if indexed.
fn get_doc(store: Store, idx: FtsIndex, doc_id: Text) : Result(Option(IndexedDoc), FtsError)
  _ = try validate_index(idx)
  wrap_table(Table.get(store, docs_table(idx), doc_id))
end

## Returns the committed document frequency (`df`) of normalized `term` (0 if absent).
fn term_df(store: Store, idx: FtsIndex, term: Text) : Result(Int, FtsError)
  _ = try validate_index(idx)
  tokens = tokenize(term, idx.config.max_token_bytes)
  return Ok(0) if tokens.empty?
  norm = tokens.first or ""
  res = try wrap_table(Table.get(store, df_table(idx), norm))
  Ok(res or 0)
end

fn dedup_preserve_order(items: List(Text)) : List(Text)
  var seen = Set.empty
  var out = []
  for item in items
    if not seen.has?(item)
      seen = seen.add(item)
      out = out.append(item)
    end
  end
  out
end

fn decode_posting(raw: Bytes) : Result(Posting, FtsError)
  case Json.decode[Posting](raw)
    Ok(p): Ok(p)
    Error(e): Error(TableFailure(Table.DecodeValue(e)))
  end
end

fn decode_df_int(raw: Bytes) : Result(Int, FtsError)
  case Json.decode[Int](raw)
    Ok(n): Ok(n)
    Error(e): Error(TableFailure(Table.DecodeValue(e)))
  end
end

fn expand_query_terms(store: Store, idx: FtsIndex, q_terms: List(Text), prefix_last?: Bool) : Result(
  List((Text, Int)),
  FtsError
)
  var seen = Set.empty
  var out = []
  dft = df_table(idx)
  dbucket = df_bucket(idx)
  last_i = q_terms.size - 1

  for (i, q_term) in q_terms.enumerate
    if prefix_last? and i == last_i
      raw_matches = try wrap_modb(
        Modb.prefix_scan(store, dbucket, q_term.bytes, idx.config.max_prefix_expansions)
      )
      for (kb, vb) in raw_matches
        term_text = try wrap_table(Table.decode_text_key(kb))
        df_val = try decode_df_int(vb)
        if df_val > 0 and not seen.has?(term_text)
          seen = seen.add(term_text)
          out = out.append((term_text, df_val))
        end
      end
    else if not seen.has?(q_term)
      case try wrap_table(Table.get(store, dft, q_term))
        None: Unit
        Some(df_val):
          if df_val > 0
            seen = seen.add(q_term)
            out = out.append((q_term, df_val))
          end
      end
    end
  end
  Ok(out)
end

## Searches `idx` using BM25 ranking while filtering candidates fail-closed through `allow_doc(doc_id, scope)`.
fn search_filtered(
  store: Store,
  idx: FtsIndex,
  query: Text,
  opts: SearchOptions,
  allow_doc: fn(Text, Text) : Bool
) : Result(List(SearchHit), FtsError)
  _ = try validate_index(idx)
  return Ok([]) if opts.limit <= 0

  q_terms = dedup_preserve_order(tokenize(query, idx.config.max_token_bytes))
  return Ok([]) if q_terms.empty?

  st = try stats(store, idx)
  return Ok([]) if st.doc_count <= 0

  avg_weighted_len = if st.total_weighted_len > 0
    st.total_weighted_len.to_float / st.doc_count.to_float
  else
    1.0.to_float
  end

  expanded = try expand_query_terms(store, idx, q_terms, opts.prefix_last_term?)
  return Ok([]) if expanded.empty?

  pbucket = postings_bucket(idx)
  dtbl = docs_table(idx)
  var doc_cache = {}
  var acc_map = {}

  for (term, df_val) in expanded
    idf = bm25_idf(st.doc_count, df_val)
    term_prefix = Table.encode_composite_key(term.bytes, Bytes.empty)
    raw_postings = try wrap_modb(Modb.prefix_scan(store, pbucket, term_prefix, 0))

    for (comp_key, raw_posting) in raw_postings
      (_tk, doc_id_b) = try wrap_table(Table.decode_composite_key(comp_key))
      doc_id = try wrap_table(Table.decode_text_key(doc_id_b))

      doc_opt = case doc_cache.get(doc_id)
        Some(cached): cached
        None:
          loaded = try wrap_table(Table.get(store, dtbl, doc_id))
          doc_cache = doc_cache.set(doc_id, loaded)
          loaded
      end

      case doc_opt
        None: Unit
        Some(doc):
          scope_ok = case opts.required_scope
            Some(req): doc.scope == req
            None: true
          end
          if scope_ok and allow_doc(doc_id, doc.scope)
            posting = try decode_posting(raw_posting)
            tf_score = bm25_tf_score(
              posting.weighted_tf,
              doc.weighted_len,
              avg_weighted_len,
              idx.config.k1,
              idx.config.b
            )
            term_score = idf * tf_score
            prev = acc_map.get(doc_id) or
              HitAcc(scope: doc.scope, score: 0.0.to_float, terms: [], fields: [])
            acc_map = acc_map.set(
              doc_id,
              HitAcc(
                scope: doc.scope,
                score: prev.score + term_score,
                terms: append_unique_text(prev.terms, term),
                fields: concat_unique_texts(prev.fields, posting.fields)
              )
            )
          end
      end
    end
  end

  var hits = []
  for (doc_id, acc) in acc_map.entries
    hits = hits.append(
      SearchHit(
        doc_id: doc_id,
        scope: acc.scope,
        score: acc.score,
        matched_terms: acc.terms.sort,
        matched_fields: acc.fields.sort
      )
    )
  end

  ordered = hits.sort_by(fn(h) h.doc_id end).sort_by_desc(fn(h) h.score end)
  Ok(ordered.take(opts.limit))
end

## Searches `idx` using BM25 ranking without an extra per-document predicate (still respects `opts.required_scope`).
fn search(store: Store, idx: FtsIndex, query: Text, opts: SearchOptions) : Result(
  List(SearchHit),
  FtsError
)
  search_filtered(store, idx, query, opts, fn(_id, _scope) true end)
end

test "Modb.Fts basic BM25 indexing, search, reindex, prefix, and removal"
  files = Files.in_memory({})
  assert Modb.open(files, "fts-smoke.modb") is Ok(db0)
  idx = index("vellum")

  docs = [
    DocumentInput(
      doc_id: "pag_1",
      scope: "col_eng",
      fields: [
        FieldInput(name: "title", text: "Deploy Runbook", weight: 3),
        FieldInput(name: "body", text: "Run mo serve to deploy production.", weight: 1)
      ]
    ),
    DocumentInput(
      doc_id: "pag_2",
      scope: "col_eng",
      fields: [
        FieldInput(name: "title", text: "Database Notes", weight: 3),
        FieldInput(
          name: "body",
          text: "We sometimes deploy migrations during deployment windows.",
          weight: 1
        )
      ]
    ),
    DocumentInput(
      doc_id: "pag_3",
      scope: "col_hr",
      fields: [
        FieldInput(name: "title", text: "Deploy Onboarding", weight: 3),
        FieldInput(name: "body", text: "Secret HR deployment steps.", weight: 1)
      ]
    )
  ]

  assert index_documents(db0, idx, docs) is Ok(db1)
  assert stats(db1, idx) == Ok(FtsStats(doc_count: 3, total_tokens: 23, total_weighted_len: 35))
  assert term_df(db1, idx, "deploy") == Ok(3)
  assert term_df(db1, idx, "deployment") == Ok(2)

  ## Title match beats body-only match inside col_eng; col_hr is excluded by required_scope.
  eng_opts = SearchOptions(limit: 10, prefix_last_term?: false, required_scope: Some("col_eng"))
  assert search(db1, idx, "deploy", eng_opts) is Ok(hits1)
  assert hits1.size == 2
  assert (hits1.first or stop "hit 0").doc_id == "pag_1"
  assert (hits1.first or stop "hit 0").matched_fields == ["body", "title"]

  ## Prefix expansion matches both deploy and deployment, ranking pag_2 highest because it matches both.
  pref_opts = SearchOptions(limit: 10, prefix_last_term?: true, required_scope: Some("col_eng"))
  assert search(db1, idx, "depl", pref_opts) is Ok(pref_hits)
  assert pref_hits.size == 2
  assert (pref_hits.first or stop "hit 0").doc_id == "pag_2"
  assert (pref_hits.first or stop "hit 0").matched_terms == ["deploy", "deployment"]
  assert (pref_hits.get(1) or stop "hit 1").doc_id == "pag_1"
  assert (pref_hits.get(1) or stop "hit 1").matched_terms == ["deploy"]

  ## Remove all documents -> stats and buckets become completely empty.
  assert remove_document(db1, idx, "pag_1") is Ok(db2)
  assert remove_document(db2, idx, "pag_2") is Ok(db3)
  assert remove_document(db3, idx, "pag_3") is Ok(db4)
  assert stats(db4, idx) == Ok(empty_stats())
  assert Modb.count_bucket(db4, postings_bucket(idx)) == Ok(0)
  assert Modb.count_bucket(db4, docs_bucket(idx)) == Ok(0)
  assert Modb.count_bucket(db4, df_bucket(idx)) == Ok(0)
end
