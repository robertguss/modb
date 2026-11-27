## MoDB Layer 2/4: Dynamic Schema Forward + Reverse-Relation Index Engine (`Modb.Dynindex`).
##
## Built cleanly for multi-tenant runtime/user-defined schemas (e.g., Kanban boards, Calendar date
## windows, exact Decimal properties, multi-value tags/relations, and reverse backlink lookups):
## - Tagged `DynVal` keys (`DynNull`, `DynBool`, `DynInt`, `DynDecimal`, `DynText`, `DynDate`, `DynRef`)
##   with collision-free `(1-byte tag || order-preserving payload)` framing.
## - Forward index entries `[namespace, prop_id, encoded_dyn_val, row_id] -> ""`.
## - Automatic reverse-relation entries `[target_id, namespace, prop_id, row_id] -> ""` for `DynRef`.
## - Diff-only updates in `tx_update_row`, strict type-tag isolation on range scans, O(N) grouped
##   Kanban counts without loading row payloads, and opaque keyset cursor pagination.
module Modb.Dynindex
expose DynVal(..),
DynEntry(..),
DynIndex(..),
DynPage(..),
DynGroupCount(..),
dyn_index,
default_dyn_index,
encode_dyn_val,
decode_dyn_val,
tx_update_row,
tx_delete_row,
tx_delete_namespace,
lookup,
tx_lookup,
snapshot_lookup,
lookup_page,
range_scan,
snapshot_range_scan,
range_page,
lookup_backlinks,
tx_lookup_backlinks,
count_exact,
count_groups
use Modb{Snapshot, Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Table{
  TableError,
  decode_bool_key,
  decode_decimal_key,
  decode_int_key,
  decode_text_key,
  decode_tuple_key,
  encode_bool_key,
  encode_decimal_key,
  encode_int_key,
  encode_text_key,
  encode_tuple_key,
  encode_tuple_prefix_bounds,
  encode_tuple_prefix_hi,
  next_byte_key
}

## Typed property cell value indexed in `Modb.DynIndex`.
enum DynVal
  DynNull
  DynBool(Bool)
  DynInt(Int)
  DynDecimal(Decimal)
  DynText(Text)
  DynDate(Text)
  DynRef(Text)
end

## One `(prop_id, value)` cell entry emitted by a dynamic row.
struct DynEntry
  prop_id: Text
  value: DynVal
end

## Bucket pair holding forward `(ns, prop_id, val, row_id)` and reverse `(target_id, ns, prop_id, row_id)` entries.
struct DynIndex
  bucket: Text
  reverse_bucket: Text
end

## Keyset-paginated slice of `row_id`s returned by `lookup_page` / `range_page`.
struct DynPage
  row_ids: List(Text)
  next_cursor: Option(Text)
  has_more: Bool
end

## Single grouped value count returned by `count_groups`.
struct DynGroupCount
  value: DynVal
  count: Int
end

## Declares a `DynIndex` with explicit forward and reverse-relation bucket names.
fn dyn_index(bucket: Text, reverse_bucket: Text) : DynIndex
  DynIndex(bucket: bucket, reverse_bucket: reverse_bucket)
end

## Declares a `DynIndex` with default buckets `"<prefix>_fwd"` and `"<prefix>_rev"`.
fn default_dyn_index(prefix: Text) : DynIndex
  DynIndex(bucket: "#{prefix}_fwd", reverse_bucket: "#{prefix}_rev")
end

fn dyn_tag(v: DynVal) : Int
  case v
    DynNull: 0
    DynBool(_): 1
    DynInt(_): 2
    DynDecimal(_): 3
    DynText(_): 4
    DynDate(_): 5
    DynRef(_): 6
  end
end

## Encodes `v` into `(1-byte type tag || order-preserving payload)`.
fn encode_dyn_val(v: DynVal) : Bytes
  t_byte = dyn_tag(v).to_byte or stop "valid dyn tag"
  prefix = Bytes.from_list([t_byte])
  payload = case v
    DynNull: Bytes.empty
    DynBool(b): encode_bool_key(b)
    DynInt(n): encode_int_key(n)
    DynDecimal(d): encode_decimal_key(d)
    DynText(s): encode_text_key(s)
    DynDate(s): encode_text_key(s)
    DynRef(s): encode_text_key(s)
  end
  Bytes.join([prefix, payload])
end

## Decodes a tagged `DynVal` byte string encoded by `encode_dyn_val`.
fn decode_dyn_val(raw: Bytes) : Result(DynVal, TableError)
  if raw.size == 0
    return Error(Table.DecodeKey(reason: "empty DynVal bytes"))
  end
  tag = (raw.get(0) or stop "tag within size >= 1").to_int
  rest = raw.slice(1, raw.size)
  if tag == 0
    if rest.size != 0
      return Error(Table.DecodeKey(reason: "DynNull must have empty payload"))
    end
    Ok(DynNull)
  else if tag == 1
    Ok(DynBool(try decode_bool_key(rest)))
  else if tag == 2
    Ok(DynInt(try decode_int_key(rest)))
  else if tag == 3
    Ok(DynDecimal(try decode_decimal_key(rest)))
  else if tag == 4
    Ok(DynText(try decode_text_key(rest)))
  else if tag == 5
    Ok(DynDate(try decode_text_key(rest)))
  else if tag == 6
    Ok(DynRef(try decode_text_key(rest)))
  else
    Error(Table.DecodeKey(reason: "unknown DynVal type tag #{tag}"))
  end
end

fn validate_idx(idx: DynIndex) : Result(Unit, TableError)
  if idx.bucket.trim.empty? or idx.reverse_bucket.trim.empty?
    return Error(Table.Storage(InvalidArgument(reason: "DynIndex bucket names cannot be empty")))
  end
  if idx.bucket == idx.reverse_bucket
    return Error(
      Table.Storage(
        InvalidArgument(reason: "DynIndex forward and reverse buckets must be distinct")
      )
    )
  end
  Ok(Unit)
end

fn build_forward_key(namespace: Text, prop_id: Text, val_bytes: Bytes, row_id: Text) : Bytes
  encode_tuple_key([namespace.bytes, prop_id.bytes, val_bytes, row_id.bytes])
end

fn build_reverse_key(target_id: Text, namespace: Text, prop_id: Text, row_id: Text) : Bytes
  encode_tuple_key([target_id.bytes, namespace.bytes, prop_id.bytes, row_id.bytes])
end

struct KeyPair
  fwd: Bytes
  rev: Option(Bytes)
end

fn dedup_entry_keys(namespace: Text, row_id: Text, entries: List(DynEntry)) : List(KeyPair)
  var seen = Set.empty
  var out = []
  for ent in entries
    vbytes = encode_dyn_val(ent.value)
    fk = build_forward_key(namespace, ent.prop_id, vbytes, row_id)
    if not seen.has?(fk)
      seen = seen.add(fk)
      rk = case ent.value
        DynRef(tid): Some(build_reverse_key(tid, namespace, ent.prop_id, row_id))
        DynNull | DynBool(_) | DynInt(_) | DynDecimal(_) | DynText(_) | DynDate(_): None
      end
      out = out.append(KeyPair(fwd: fk, rev: rk))
    end
  end
  out
end

fn fwd_key_set(pairs: List(KeyPair)) : Set(Bytes)
  var s = Set.empty
  for p in pairs
    s = s.add(p.fwd)
  end
  s
end

## Diff-only update of all dynamic index cells (forward + reverse `DynRef` links) for `(namespace, row_id)`.
## Unchanged cells perform zero CoW B+Tree writes or reads.
fn tx_update_row(
  tx: WriteTx,
  idx: DynIndex,
  namespace: Text,
  row_id: Text,
  old_entries: List(DynEntry),
  new_entries: List(DynEntry)
) : Result(WriteTx, TableError)
  try validate_idx(idx)
  old_pairs = dedup_entry_keys(namespace, row_id, old_entries)
  new_pairs = dedup_entry_keys(namespace, row_id, new_entries)
  old_set = fwd_key_set(old_pairs)
  new_set = fwd_key_set(new_pairs)

  var cur = tx
  for op in old_pairs
    if not new_set.has?(op.fwd)
      cur = try Modb.tx_delete(cur, idx.bucket, op.fwd)
      case op.rev
        Some(rk): cur = try Modb.tx_delete(cur, idx.reverse_bucket, rk)
        None: Unit
      end
    end
  end
  for np in new_pairs
    if not old_set.has?(np.fwd)
      cur = try Modb.tx_put(cur, idx.bucket, np.fwd, Bytes.empty)
      case np.rev
        Some(rk): cur = try Modb.tx_put(cur, idx.reverse_bucket, rk, Bytes.empty)
        None: Unit
      end
    end
  end
  Ok(cur)
end

## Removes all dynamic index cells (forward + reverse) associated with `(namespace, row_id)`.
fn tx_delete_row(
  tx: WriteTx,
  idx: DynIndex,
  namespace: Text,
  row_id: Text,
  old_entries: List(DynEntry)
) : Result(WriteTx, TableError)
  tx_update_row(tx, idx, namespace, row_id, old_entries, [])
end

## Removes an entire `namespace`'s forward and reverse-relation index entries inside `tx`.
fn tx_delete_namespace(tx: WriteTx, idx: DynIndex, namespace: Text) : Result(WriteTx, TableError)
  try validate_idx(idx)
  (lo, hi) = encode_tuple_prefix_bounds([namespace.bytes])
  rows = try Modb.tx_scan(tx, idx.bucket, Some(lo), Some(hi), 0)
  var cur = tx
  for (fk, _empty) in rows
    parts = try decode_tuple_key(fk)
    if parts.size == 4
      prop_b = parts.get(1) or Bytes.empty
      val_b = parts.get(2) or Bytes.empty
      rid_b = parts.get(3) or Bytes.empty
      case decode_dyn_val(val_b)
        Ok(DynRef(target_id)):
          rk = encode_tuple_key([target_id.bytes, namespace.bytes, prop_b, rid_b])
          cur = try Modb.tx_delete(cur, idx.reverse_bucket, rk)
        Ok(_) | Error(_): Unit
      end
    end
    cur = try Modb.tx_delete(cur, idx.bucket, fk)
  end
  Ok(cur)
end

fn decode_row_ids(idx_rows: List((Bytes, Bytes))) : Result(List(Text), TableError)
  var out = []
  for (fk, _empty) in idx_rows
    parts = try decode_tuple_key(fk)
    if parts.size != 4
      return Error(Table.DecodeKey(reason: "expected 4-part DynIndex key, found #{parts.size}"))
    end
    rid = try (parts.get(3) or Bytes.empty).decode_utf8.or_fail(
      Table.DecodeKey(reason: "invalid UTF-8 row_id in DynIndex")
    )
    out = out.append(rid)
  end
  Ok(out)
end

## Exact lookup returning ordered `row_id`s matching `(namespace, prop_id, val)`.
fn lookup(store: Store, idx: DynIndex, namespace: Text, prop_id: Text, val: DynVal, limit: Int) : Result(
  List(Text),
  TableError
)
  try validate_idx(idx)
  (lo, hi) = encode_tuple_prefix_bounds([namespace.bytes, prop_id.bytes, encode_dyn_val(val)])
  rows = try Modb.scan(store, idx.bucket, Some(lo), Some(hi), limit)
  decode_row_ids(rows)
end

## Exact lookup inside an active `WriteTx` (sees uncommitted cell mutations).
fn tx_lookup(tx: WriteTx, idx: DynIndex, namespace: Text, prop_id: Text, val: DynVal, limit: Int) : Result(
  List(Text),
  TableError
)
  try validate_idx(idx)
  (lo, hi) = encode_tuple_prefix_bounds([namespace.bytes, prop_id.bytes, encode_dyn_val(val)])
  rows = try Modb.tx_scan(tx, idx.bucket, Some(lo), Some(hi), limit)
  decode_row_ids(rows)
end

## Exact lookup against a pinned `Modb.Snapshot`.
fn snapshot_lookup(
  store: Store,
  snap: Snapshot,
  idx: DynIndex,
  namespace: Text,
  prop_id: Text,
  val: DynVal,
  limit: Int
) : Result(List(Text), TableError)
  try validate_idx(idx)
  (lo, hi) = encode_tuple_prefix_bounds([namespace.bytes, prop_id.bytes, encode_dyn_val(val)])
  rows = try Modb.snapshot_scan(store, snap, idx.bucket, Some(lo), Some(hi), limit)
  decode_row_ids(rows)
end

fn decode_dyn_cursor(cursor_opt: Option(Text)) : Result(Option(Bytes), TableError)
  case cursor_opt
    None: Ok(None)
    Some(tok):
      if tok.trim.empty?
        return Error(Table.DecodeKey(reason: "empty DynIndex pagination cursor"))
      end
      raw = try Bytes.from_base64url(tok).or_fail(
        Table.DecodeKey(reason: "invalid DynIndex pagination cursor")
      )
      if raw.size == 0
        return Error(Table.DecodeKey(reason: "empty decoded DynIndex pagination cursor"))
      end
      Ok(Some(raw))
  end
end

fn max_bytes_opt(a_opt: Option(Bytes), b_opt: Option(Bytes)) : Option(Bytes)
  case (a_opt, b_opt)
    (None, _): b_opt
    (_, None): a_opt
    (Some(a), Some(b)): Some(if a >= b: a else: b)
  end
end

## Keyset-paginated exact match over `(namespace, prop_id, val)`.
fn lookup_page(
  store: Store,
  idx: DynIndex,
  namespace: Text,
  prop_id: Text,
  val: DynVal,
  page_size: Int,
  after_cursor: Option(Text)
) : Result(DynPage, TableError)
  try validate_idx(idx)
  if page_size <= 0
    return Error(Table.Storage(InvalidArgument(reason: "page_size must be > 0")))
  end
  (base_lo, base_hi) = encode_tuple_prefix_bounds([
    namespace.bytes,
    prop_id.bytes,
    encode_dyn_val(val)
  ])
  after_raw = (try decode_dyn_cursor(after_cursor)).map(next_byte_key)
  eff_lo = max_bytes_opt(Some(base_lo), after_raw) or base_lo
  if eff_lo >= base_hi
    return Ok(DynPage(row_ids: [], next_cursor: None, has_more: false))
  end
  rows = try Modb.scan(store, idx.bucket, Some(eff_lo), Some(base_hi), page_size + 1)
  has_more = rows.size > page_size
  kept = if has_more: rows.take(page_size) else: rows
  row_ids = try decode_row_ids(kept)
  next_cur = if has_more: kept.last.map(fn(p) p.0.to_base64url end) else: None
  Ok(DynPage(row_ids: row_ids, next_cursor: next_cur, has_more: has_more))
end

fn tag_start_bound(ns: Text, prop_id: Text, tag: Int) : Bytes
  base = encode_tuple_key([ns.bytes, prop_id.bytes])
  if tag <= 0
    return base
  end
  tb = tag.to_byte or stop "valid dyn tag"
  Bytes.join([base, Bytes.from_list([tb])])
end

fn tag_end_bound(ns: Text, prop_id: Text, tag: Int) : Bytes
  base = encode_tuple_key([ns.bytes, prop_id.bytes])
  tb = (tag + 1).to_byte or stop "valid dyn tag + 1"
  Bytes.join([base, Bytes.from_list([tb])])
end

fn dyn_range_bounds(
  ns: Text,
  prop_id: Text,
  lo_opt: Option(DynVal),
  hi_opt: Option(DynVal),
  lo_inc: Bool,
  hi_inc: Bool
) : Result((Bytes, Bytes), TableError)
  case (lo_opt, hi_opt)
    (Some(lv), Some(hv)):
      if dyn_tag(lv) != dyn_tag(hv)
        return Error(
          Table.Storage(
            InvalidArgument(reason: "DynIndex range bounds must have matching DynVal types")
          )
        )
      end
      lo_b = if lo_inc
        encode_tuple_key([ns.bytes, prop_id.bytes, encode_dyn_val(lv)])
      else
        encode_tuple_prefix_hi([ns.bytes, prop_id.bytes, encode_dyn_val(lv)])
      end
      hi_b = if hi_inc
        encode_tuple_prefix_hi([ns.bytes, prop_id.bytes, encode_dyn_val(hv)])
      else
        encode_tuple_key([ns.bytes, prop_id.bytes, encode_dyn_val(hv)])
      end
      Ok((lo_b, hi_b))
    (Some(lv), None):
      lo_b = if lo_inc
        encode_tuple_key([ns.bytes, prop_id.bytes, encode_dyn_val(lv)])
      else
        encode_tuple_prefix_hi([ns.bytes, prop_id.bytes, encode_dyn_val(lv)])
      end
      hi_b = tag_end_bound(ns, prop_id, dyn_tag(lv))
      Ok((lo_b, hi_b))
    (None, Some(hv)):
      lo_b = tag_start_bound(ns, prop_id, dyn_tag(hv))
      hi_b = if hi_inc
        encode_tuple_prefix_hi([ns.bytes, prop_id.bytes, encode_dyn_val(hv)])
      else
        encode_tuple_key([ns.bytes, prop_id.bytes, encode_dyn_val(hv)])
      end
      Ok((lo_b, hi_b))
    (None, None): Ok(encode_tuple_prefix_bounds([ns.bytes, prop_id.bytes]))
  end
end

## Type-tag-isolated ordered range scan over `(namespace, prop_id)`.
fn range_scan(
  store: Store,
  idx: DynIndex,
  namespace: Text,
  prop_id: Text,
  lo: Option(DynVal),
  hi: Option(DynVal),
  lo_inclusive: Bool,
  hi_inclusive: Bool,
  limit: Int
) : Result(List(Text), TableError)
  try validate_idx(idx)
  (lo_b, hi_b) = try dyn_range_bounds(namespace, prop_id, lo, hi, lo_inclusive, hi_inclusive)
  return Ok([]) if lo_b >= hi_b
  rows = try Modb.scan(store, idx.bucket, Some(lo_b), Some(hi_b), limit)
  decode_row_ids(rows)
end

## Type-tag-isolated ordered range scan against a pinned `Modb.Snapshot`.
fn snapshot_range_scan(
  store: Store,
  snap: Snapshot,
  idx: DynIndex,
  namespace: Text,
  prop_id: Text,
  lo: Option(DynVal),
  hi: Option(DynVal),
  lo_inclusive: Bool,
  hi_inclusive: Bool,
  limit: Int
) : Result(List(Text), TableError)
  try validate_idx(idx)
  (lo_b, hi_b) = try dyn_range_bounds(namespace, prop_id, lo, hi, lo_inclusive, hi_inclusive)
  if lo_b >= hi_b
    _ = try Modb.snapshot_scan(store, snap, idx.bucket, None, None, 1)
    return Ok([])
  end
  rows = try Modb.snapshot_scan(store, snap, idx.bucket, Some(lo_b), Some(hi_b), limit)
  decode_row_ids(rows)
end

## Type-tag-isolated keyset-paginated range scan over `(namespace, prop_id)`.
fn range_page(
  store: Store,
  idx: DynIndex,
  namespace: Text,
  prop_id: Text,
  lo: Option(DynVal),
  hi: Option(DynVal),
  lo_inclusive: Bool,
  hi_inclusive: Bool,
  page_size: Int,
  after_cursor: Option(Text)
) : Result(DynPage, TableError)
  try validate_idx(idx)
  if page_size <= 0
    return Error(Table.Storage(InvalidArgument(reason: "page_size must be > 0")))
  end
  (base_lo, base_hi) = try dyn_range_bounds(namespace, prop_id, lo, hi, lo_inclusive, hi_inclusive)
  after_raw = (try decode_dyn_cursor(after_cursor)).map(next_byte_key)
  eff_lo = max_bytes_opt(Some(base_lo), after_raw) or base_lo
  if eff_lo >= base_hi
    return Ok(DynPage(row_ids: [], next_cursor: None, has_more: false))
  end
  rows = try Modb.scan(store, idx.bucket, Some(eff_lo), Some(base_hi), page_size + 1)
  has_more = rows.size > page_size
  kept = if has_more: rows.take(page_size) else: rows
  row_ids = try decode_row_ids(kept)
  next_cur = if has_more: kept.last.map(fn(p) p.0.to_base64url end) else: None
  Ok(DynPage(row_ids: row_ids, next_cursor: next_cur, has_more: has_more))
end

fn decode_backlink_tuples(rev_rows: List((Bytes, Bytes))) : Result(
  List((Text, Text, Text)),
  TableError
)
  var out = []
  for (rk, _empty) in rev_rows
    parts = try decode_tuple_key(rk)
    if parts.size != 4
      return Error(
        Table.DecodeKey(reason: "expected 4-part reverse DynIndex key, found #{parts.size}")
      )
    end
    ns = try (parts.get(1) or Bytes.empty).decode_utf8.or_fail(
      Table.DecodeKey(reason: "invalid UTF-8 namespace in reverse DynIndex")
    )
    prop = try (parts.get(2) or Bytes.empty).decode_utf8.or_fail(
      Table.DecodeKey(reason: "invalid UTF-8 prop_id in reverse DynIndex")
    )
    rid = try (parts.get(3) or Bytes.empty).decode_utf8.or_fail(
      Table.DecodeKey(reason: "invalid UTF-8 row_id in reverse DynIndex")
    )
    out = out.append((ns, prop, rid))
  end
  Ok(out)
end

fn backlink_prefix(target_id: Text, namespace_opt: Option(Text), prop_id_opt: Option(Text)) : (
  Bytes,
  Bytes
)
  var parts = [target_id.bytes]
  case namespace_opt
    Some(ns):
      parts = parts.append(ns.bytes)
      case prop_id_opt
        Some(pid): parts = parts.append(pid.bytes)
        None: Unit
      end
    None: Unit
  end
  encode_tuple_prefix_bounds(parts)
end

fn filter_backlinks(
  items: List((Text, Text, Text)),
  namespace_opt: Option(Text),
  prop_id_opt: Option(Text)
) : List((Text, Text, Text))
  var out = []
  for (ns, prop, rid) in items
    ns_ok = case namespace_opt
      Some(want): ns == want
      None: true
    end
    prop_ok = case prop_id_opt
      Some(want): prop == want
      None: true
    end
    if ns_ok and prop_ok
      out = out.append((ns, prop, rid))
    end
  end
  out
end

## Reverse-relation query returning `(namespace, prop_id, source_row_id)` tuples pointing at `target_id`.
fn lookup_backlinks(
  store: Store,
  idx: DynIndex,
  target_id: Text,
  namespace_opt: Option(Text),
  prop_id_opt: Option(Text)
) : Result(List((Text, Text, Text)), TableError)
  try validate_idx(idx)
  (lo, hi) = backlink_prefix(target_id, namespace_opt, prop_id_opt)
  rows = try Modb.scan(store, idx.reverse_bucket, Some(lo), Some(hi), 0)
  decoded = try decode_backlink_tuples(rows)
  Ok(filter_backlinks(decoded, namespace_opt, prop_id_opt))
end

## Reverse-relation query inside an active `WriteTx`.
fn tx_lookup_backlinks(
  tx: WriteTx,
  idx: DynIndex,
  target_id: Text,
  namespace_opt: Option(Text),
  prop_id_opt: Option(Text)
) : Result(List((Text, Text, Text)), TableError)
  try validate_idx(idx)
  (lo, hi) = backlink_prefix(target_id, namespace_opt, prop_id_opt)
  rows = try Modb.tx_scan(tx, idx.reverse_bucket, Some(lo), Some(hi), 0)
  decoded = try decode_backlink_tuples(rows)
  Ok(filter_backlinks(decoded, namespace_opt, prop_id_opt))
end

## Exact count of rows matching `(namespace, prop_id, val)` scanning only index keys.
fn count_exact(store: Store, idx: DynIndex, namespace: Text, prop_id: Text, val: DynVal) : Result(
  Int,
  TableError
)
  try validate_idx(idx)
  (lo, hi) = encode_tuple_prefix_bounds([namespace.bytes, prop_id.bytes, encode_dyn_val(val)])
  rows = try Modb.scan(store, idx.bucket, Some(lo), Some(hi), 0)
  Ok(rows.size)
end

## Single-pass O(N) Kanban/group count over `(namespace, prop_id)` returning counts in encoded `DynVal` order.
fn count_groups(store: Store, idx: DynIndex, namespace: Text, prop_id: Text) : Result(
  List(DynGroupCount),
  TableError
)
  try validate_idx(idx)
  (lo, hi) = encode_tuple_prefix_bounds([namespace.bytes, prop_id.bytes])
  rows = try Modb.scan(store, idx.bucket, Some(lo), Some(hi), 0)
  var out = []
  var cur_bytes_opt = None
  var cur_val_opt = None
  var cur_count = 0
  for (fk, _empty) in rows
    parts = try decode_tuple_key(fk)
    if parts.size != 4
      return Error(Table.DecodeKey(reason: "expected 4-part DynIndex key, found #{parts.size}"))
    end
    vb = parts.get(2) or Bytes.empty
    same? = case cur_bytes_opt
      Some(prev): prev == vb
      None: false
    end
    if same?
      cur_count += 1
    else
      case cur_val_opt
        Some(v): out = out.append(DynGroupCount(value: v, count: cur_count))
        None: Unit
      end
      dv = try decode_dyn_val(vb)
      cur_bytes_opt = Some(vb)
      cur_val_opt = Some(dv)
      cur_count = 1
    end
  end
  case cur_val_opt
    Some(v): out = out.append(DynGroupCount(value: v, count: cur_count))
    None: Unit
  end
  Ok(out)
end

test "DynIndex: tagged order, diff-only updates, type-isolated ranges, backlinks, and count_groups"
  # 1. Tagged value round-trip and tag separation
  d_pos = "42.50".to_decimal or stop "dec"
  vals = [
    DynNull,
    DynBool(false),
    DynBool(true),
    DynInt(-10),
    DynInt(5),
    DynDecimal("-1.5".to_decimal or stop "neg"),
    DynDecimal(d_pos),
    DynText("alpha"),
    DynDate("2026-11-20"),
    DynRef("proj:1")
  ]
  for i in 0..vals.size
    v = vals.get(i) or stop "val idx"
    enc = encode_dyn_val(v)
    assert decode_dyn_val(enc) == Ok(v)
    if i + 1 < vals.size
      nxt = vals.get(i + 1) or stop "nxt idx"
      assert enc < encode_dyn_val(nxt)
    end
  end

  # 2. Live Kanban + Calendar + Backlink + Diff-only test
  files = Files.in_memory({})
  assert Modb.open(files, "dyn-unit.modb") is Ok(s0)
  idx = default_dyn_index("vlm_cells")

  tx0 = Modb.begin_write(s0)
  assert tx_update_row(
    tx0,
    idx,
    "db1",
    "r1",
    [],
    [
      DynEntry(prop_id: "status", value: DynText("todo")),
      DynEntry(prop_id: "due", value: DynDate("2026-11-25")),
      DynEntry(prop_id: "budget", value: DynDecimal(d_pos)),
      DynEntry(prop_id: "rel", value: DynRef("page:root"))
    ]
  ) is
    Ok(tx1)
  assert tx_update_row(
    tx1,
    idx,
    "db1",
    "r2",
    [],
    [
      DynEntry(prop_id: "status", value: DynText("done")),
      DynEntry(prop_id: "due", value: DynDate("2026-11-28")),
      DynEntry(prop_id: "budget", value: DynInt(999)),
      DynEntry(prop_id: "rel", value: DynRef("page:root"))
    ]
  ) is
    Ok(tx2)
  assert Modb.commit(tx2) is Ok(s1)

  assert count_groups(s1, idx, "db1", "status") ==
    Ok([
      DynGroupCount(value: DynText("done"), count: 1),
      DynGroupCount(value: DynText("todo"), count: 1)
    ])
  assert range_scan(
    s1,
    idx,
    "db1",
    "due",
    Some(DynDate("2026-11-24")),
    Some(DynDate("2026-11-26")),
    true,
    true,
    0
  ) ==
    Ok(["r1"])
  # Mismatched Int value (999) in same property is isolated from Decimal open-upper scan!
  assert range_scan(s1, idx, "db1", "budget", Some(DynDecimal(0.0)), None, true, false, 0) ==
    Ok(["r1"])
  assert lookup_backlinks(s1, idx, "page:root", Some("db1"), None) ==
    Ok([("db1", "rel", "r1"), ("db1", "rel", "r2")])

  # Diff-only update: change only status todo -> done on r1; unchanged due/budget/rel write 0 pages
  r1_old = [
    DynEntry(prop_id: "status", value: DynText("todo")),
    DynEntry(prop_id: "due", value: DynDate("2026-11-25")),
    DynEntry(prop_id: "budget", value: DynDecimal(d_pos)),
    DynEntry(prop_id: "rel", value: DynRef("page:root"))
  ]
  r1_new = [
    DynEntry(prop_id: "status", value: DynText("done")),
    DynEntry(prop_id: "due", value: DynDate("2026-11-25")),
    DynEntry(prop_id: "budget", value: DynDecimal(d_pos)),
    DynEntry(prop_id: "rel", value: DynRef("page:root"))
  ]
  tx3 = Modb.begin_write_tracked(s1)
  assert tx_update_row(tx3, idx, "db1", "r1", r1_old, r1_new) is Ok(tx4)
  assert Modb.tx_touched_puts(tx4, idx.bucket).size == 1
  assert Modb.tx_touched_deletes(tx4, idx.bucket).size == 1
  assert Modb.tx_touched_puts(tx4, idx.reverse_bucket).empty?
  assert Modb.tx_touched_deletes(tx4, idx.reverse_bucket).empty?
  assert Modb.commit(tx4) is Ok(s2)

  assert count_exact(s2, idx, "db1", "status", DynText("done")) == Ok(2)
  assert range_page(
    s2,
    idx,
    "db1",
    "status",
    Some(DynText("done")),
    Some(DynText("done")),
    true,
    true,
    1,
    None
  ) is
    Ok(p1)
  assert p1.row_ids == ["r1"] and p1.has_more
  assert range_page(
    s2,
    idx,
    "db1",
    "status",
    Some(DynText("done")),
    Some(DynText("done")),
    true,
    true,
    1,
    p1.next_cursor
  ) is
    Ok(p2)
  assert p2.row_ids == ["r2"] and (not p2.has_more)
  assert Modb.verify(s2) is Ok(_)
end
