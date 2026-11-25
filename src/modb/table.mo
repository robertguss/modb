## MoDB Layer 2: Typed tables, order-preserving key codecs, and atomic secondary indexes
## built in pure Mo on top of the Layer 1 CoW B+Tree (`Modb`).
module Modb.Table
expose TableError(..),
KeyCodec(..),
IndexSpec,
Index(..),
Table(..),
RowDiff(..),
to_text,
int64_min,
int64_max,
encode_int_key,
decode_int_key,
encode_text_key,
decode_text_key,
encode_bytes_key,
decode_bytes_key,
encode_composite_key,
decode_composite_key,
int_codec,
text_codec,
bytes_codec,
custom_codec,
table,
int_key,
text_key,
bytes_key,
strict,
with_index,
index,
int_index,
text_index,
bytes_index,
unique_index,
unique_int_index,
unique_text_index,
unique_bytes_index,
index_spec,
write_tx,
transact,
put,
put_many,
put_indexed,
put_specs,
delete,
delete_many,
delete_indexed,
delete_specs,
tx_get,
tx_scan,
tx_lookup,
tx_lookup_unique,
get,
scan,
range,
all,
count,
lookup,
lookup_unique,
range_by,
snapshot_get,
snapshot_scan,
snapshot_all,
snapshot_lookup,
snapshot_lookup_unique,
snapshot_range_by,
get_at_root,
scan_at_root,
all_at_root,
diff_roots
use Json{JsonDecodeError}
use Modb{Snapshot, Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Tree{KeyDiff}

## Minimum signed 64-bit integer (`-2^63`), flipped to `0x0000000000000000` in key bytes.
int64_min = -9223372036854775808

## Maximum signed 64-bit integer (`2^63 - 1`), flipped to `0xFFFFFFFFFFFFFFFF` in key bytes.
int64_max = 9223372036854775807

## Every failure returned by typed `Modb.Table` operations.
enum TableError
  Storage(ModbError)
  DecodeValue(JsonDecodeError)
  DecodeKey(reason: Text)
  UniqueConflict(index: Text, value: Text)
  CorruptIndex(index: Text, reason: Text)
end

## Formats a `TableError` as a readable diagnostic.
fn to_text(err: TableError) : Text
  case err
    Storage(e): e.to_text
    DecodeValue(e): "value JSON decode error: #{e.to_text}"
    DecodeKey(reason: r): "key decode error: #{r}"
    UniqueConflict(index: idx, value: v): "unique index conflict on '#{idx}': duplicate key '#{v}'"
    CorruptIndex(index: idx, reason: r): "corrupt secondary index '#{idx}': #{r}"
  end
end

## Order-preserving binary codec for keys of type `K`.
## Whenever `a < b` in `K`'s logical order, `encode(a) < encode(b)` must hold in unsigned `Bytes` order.
struct KeyCodec(K)
  encode: fn(K) : Bytes
  decode: fn(Bytes) : Result(K, TableError)
  describe: fn(K) : Text
end

## Type-erased index maintenance specification bound to `(K, V)`.
struct IndexSpec(K, V)
  bucket: Text
  unique: Bool
  encode_key: fn(V) : Bytes
  describe_key: fn(V) : Text
end

## Typed secondary index over table `(K, V)` extracting an indexed key of type `I`.
struct Index(K, V, I)
  bucket: Text
  unique: Bool
  key_codec: KeyCodec(I)
  extract: fn(V) : I
end

## Typed table backed by a `Modb` bucket with `Json` value encoding and optional attached indexes.
struct Table(K, V)
  bucket: Text
  key_codec: KeyCodec(K)
  encode_value: fn(V) : Bytes
  decode_value: fn(Bytes) : Result(V, JsonDecodeError)
  indexes: List(IndexSpec(K, V))
end

## Typed row-level difference between two catalog roots for a `Table(K, V)`.
enum RowDiff(K, V)
  RowAdded(key: K, value: V)
  RowRemoved(key: K, value: V)
  RowModified(key: K, old_value: V, new_value: V)
end

## Encodes a signed 64-bit `Int` into 8 big-endian bytes with the sign bit flipped,
## so unsigned bytewise comparison matches signed integer order (`INT64_MIN < -1 < 0 < 1 < INT64_MAX`).
fn encode_int_key(n: Int) : Bytes
  Bytes.from_i64_be(n.wrapping_add(-9223372036854775808))
end

## Decodes an 8-byte sign-flipped big-endian `Int` key.
fn decode_int_key(raw: Bytes) : Result(Int, TableError)
  if raw.size != 8
    return Error(DecodeKey(reason: "expected 8-byte Int key, found #{raw.size} bytes"))
  end
  flipped = try raw.i64_be_at(0).or_fail(DecodeKey(reason: "truncated 8-byte Int key"))
  Ok(flipped.wrapping_add(-9223372036854775808))
end

## Encodes `Text` as UTF-8 bytes (order-preserving with respect to Unicode code points).
fn encode_text_key(s: Text) : Bytes
  s.bytes
end

## Decodes UTF-8 `Bytes` back into a `Text` key.
fn decode_text_key(raw: Bytes) : Result(Text, TableError)
  raw.decode_utf8.or_fail(DecodeKey(reason: "invalid UTF-8 in Text key"))
end

## Identity codec for raw `Bytes` keys.
fn encode_bytes_key(b: Bytes) : Bytes
  b
end

## Identity decoder for raw `Bytes` keys.
fn decode_bytes_key(raw: Bytes) : Result(Bytes, TableError)
  Ok(raw)
end

fn has_zero_byte?(raw: Bytes) : Bool
  for i in 0..raw.size
    b = raw.get(i) or stop "index within raw.size"
    return true if b.to_int == 0
  end
  false
end

## Escapes `index_key` (`0x00` -> `0x00 0xFF`) and appends a `0x00 0x00` terminator
## (or `0x00 <term_tail>` for exclusive prefix upper bounds).
fn frame_index_prefix(index_key: Bytes, term_tail: Int) : Bytes
  tail_byte = term_tail.to_byte or stop "valid terminator tail byte"
  zero_byte = 0.to_byte or stop "valid zero byte"
  ff_byte = 255.to_byte or stop "valid 0xFF byte"
  if not has_zero_byte?(index_key)
    return Bytes.join([index_key, Bytes.from_list([zero_byte, tail_byte])])
  end
  var escaped = []
  for i in 0..index_key.size
    b = index_key.get(i) or stop "index within index_key.size"
    if b.to_int == 0
      escaped = escaped.append(zero_byte).append(ff_byte)
    else
      escaped = escaped.append(b)
    end
  end
  Bytes.from_list(escaped.append(zero_byte).append(tail_byte))
end

## Encodes a collision-free, order-preserving composite key `(index_key, primary_key)`
## for non-unique secondary indexes using null-escaped framing (`0x00 -> 0x00 0xFF`, terminated by `0x00 0x00`).
fn encode_composite_key(index_key: Bytes, primary_key: Bytes) : Bytes
  Bytes.join([frame_index_prefix(index_key, 0), primary_key])
end

## Splits a composite non-unique index key back into `(index_key, primary_key)`.
fn decode_composite_key(raw: Bytes) : Result((Bytes, Bytes), TableError)
  zero_byte = 0.to_byte or stop "valid zero byte"
  var i = 0
  var had_escape = false
  var unescaped = []
  while i < raw.size
    b = raw.get(i) or stop "index within raw.size"
    if b.to_int != 0
      if had_escape
        unescaped = unescaped.append(b)
      end
      i += 1
    else
      if i + 1 >= raw.size
        return Error(DecodeKey(reason: "truncated escape in composite index key"))
      end
      next_b = (raw.get(i + 1) or stop "index+1 within raw.size").to_int
      if next_b == 0
        ik = if had_escape: Bytes.from_list(unescaped) else: raw.slice(0, i)
        pk = raw.slice(i + 2, raw.size)
        return Ok((ik, pk))
      else if next_b == 255
        if not had_escape
          unescaped = raw.slice(0, i).to_list
          had_escape = true
        end
        unescaped = unescaped.append(zero_byte)
        i += 2
      else
        return Error(DecodeKey(reason: "invalid escape byte #{next_b} in composite index key"))
      end
    end
  end
  Error(DecodeKey(reason: "missing terminator in composite index key"))
end

## Order-preserving `KeyCodec` for signed 64-bit `Int`.
fn int_codec() : KeyCodec(Int)
  KeyCodec(encode: encode_int_key, decode: decode_int_key, describe: fn(n) n.to_text end)
end

## Order-preserving `KeyCodec` for UTF-8 `Text`.
fn text_codec() : KeyCodec(Text)
  KeyCodec(encode: encode_text_key, decode: decode_text_key, describe: fn(s) s end)
end

## Order-preserving `KeyCodec` for raw `Bytes`.
fn bytes_codec() : KeyCodec(Bytes)
  KeyCodec(encode: encode_bytes_key, decode: decode_bytes_key, describe: fn(b) b.to_hex end)
end

## Builds a custom `KeyCodec(K)` from user-supplied order-preserving `encode` and `decode` functions.
fn custom_codec(encode: fn(K) : Bytes, decode: fn(Bytes) : Result(K, TableError)) : KeyCodec(K)
  KeyCodec(encode: encode, decode: decode, describe: fn(k) encode(k).to_hex end)
end

## Declares a typed `Table(K, V)` with a custom `KeyCodec(K)` and automatic `Json` value encoding.
fn table(bucket: Text, key_codec: KeyCodec(K)) : Table(K, V) where V: Json
  Table(
    bucket: bucket,
    key_codec: key_codec,
    encode_value: fn(v) Json.encode(v).bytes end,
    decode_value: fn(raw) Json.decode[V](raw) end,
    indexes: []
  )
end

## Declares a typed `Table(Int, V)` with signed order-preserving `Int` keys.
fn int_key(bucket: Text) : Table(Int, V) where V: Json
  table(bucket, int_codec())
end

## Declares a typed `Table(Text, V)` with UTF-8 `Text` keys.
fn text_key(bucket: Text) : Table(Text, V) where V: Json
  table(bucket, text_codec())
end

## Declares a typed `Table(Bytes, V)` with raw `Bytes` keys.
fn bytes_key(bucket: Text) : Table(Bytes, V) where V: Json
  table(bucket, bytes_codec())
end

## Configures `tbl` to reject unknown JSON object fields on read (`Json.decode_strict[V]`).
fn strict(tbl: Table(K, V)) : Table(K, V) where V: Json
  var next = tbl
  next.decode_value = fn(raw) Json.decode_strict[V](raw) end
  next
end

## Converts a typed `Index(K, V, I)` into a type-erased `IndexSpec(K, V)` for heterogeneous maintenance.
fn index_spec(idx: Index(K, V, I)) : IndexSpec(K, V)
  enc = idx.key_codec.encode
  desc = idx.key_codec.describe
  ext = idx.extract
  IndexSpec(
    bucket: idx.bucket,
    unique: idx.unique,
    encode_key: fn(v) enc(ext(v)) end,
    describe_key: fn(v) desc(ext(v)) end
  )
end

## Attaches a secondary index to `tbl` so `Table.put` and `Table.delete` maintain it automatically.
## Multiple calls chain cleanly across indexes with different key types (`Int`, `Text`, `Bytes`).
fn with_index(tbl: Table(K, V), idx: Index(K, V, I)) : Table(K, V)
  spec = index_spec(idx)
  for existing in tbl.indexes
    return tbl if existing.bucket == spec.bucket
  end
  var next = tbl
  next.indexes = next.indexes.append(spec)
  next
end

## Declares a non-unique secondary index using a custom `KeyCodec(I)`.
fn index(bucket: Text, key_codec: KeyCodec(I), extract: fn(V) : I) : Index(K, V, I)
  Index(bucket: bucket, unique: false, key_codec: key_codec, extract: extract)
end

## Declares a non-unique secondary index over a signed `Int` field or projection.
fn int_index(bucket: Text, extract: fn(V) : Int) : Index(K, V, Int)
  index(bucket, int_codec(), extract)
end

## Declares a non-unique secondary index over a `Text` field or projection.
fn text_index(bucket: Text, extract: fn(V) : Text) : Index(K, V, Text)
  index(bucket, text_codec(), extract)
end

## Declares a non-unique secondary index over a `Bytes` field or projection.
fn bytes_index(bucket: Text, extract: fn(V) : Bytes) : Index(K, V, Bytes)
  index(bucket, bytes_codec(), extract)
end

## Declares a unique secondary index using a custom `KeyCodec(I)`.
fn unique_index(bucket: Text, key_codec: KeyCodec(I), extract: fn(V) : I) : Index(K, V, I)
  Index(bucket: bucket, unique: true, key_codec: key_codec, extract: extract)
end

## Declares a unique secondary index over a signed `Int` field or projection.
fn unique_int_index(bucket: Text, extract: fn(V) : Int) : Index(K, V, Int)
  unique_index(bucket, int_codec(), extract)
end

## Declares a unique secondary index over a `Text` field or projection.
fn unique_text_index(bucket: Text, extract: fn(V) : Text) : Index(K, V, Text)
  unique_index(bucket, text_codec(), extract)
end

## Declares a unique secondary index over a `Bytes` field or projection.
fn unique_bytes_index(bucket: Text, extract: fn(V) : Bytes) : Index(K, V, Bytes)
  unique_index(bucket, bytes_codec(), extract)
end

## Runs a typed write transaction atomically, rolling back cleanly on any `TableError`.
fn write_tx(store: Store, work: fn(WriteTx) : Result(WriteTx, TableError)) : Result(
  Store,
  TableError
)
  tx = Modb.begin_write(store)
  updated = try work(tx)
  Ok(try Modb.commit(updated))
end

## Runs an atomic transaction that returns an application value `R` alongside the committed `Store`
## and propagates domain errors `E` directly (rolling back on any `Error`).
fn transact(
  store: Store,
  wrap_error: fn(TableError) : E,
  work: fn(WriteTx) : Result((WriteTx, R), E)
) : Result((Store, R), E)
  tx = Modb.begin_write(store)
  (updated, result) = try work(tx)
  committed = try Modb.commit(updated).map_error(fn(e) wrap_error(Storage(e)) end)
  Ok((committed, result))
end

fn merge_specs(base: List(IndexSpec(K, V)), extra: List(IndexSpec(K, V))) : List(IndexSpec(K, V))
  return base if extra.empty?
  return extra if base.empty?
  var merged = base
  for spec in extra
    var seen = false
    for existing in merged
      if existing.bucket == spec.bucket
        seen = true
      end
    end
    if not seen
      merged = merged.append(spec)
    end
  end
  merged
end

fn validate_specs(table_bucket: Text, specs: List(IndexSpec(K, V))) : Result(Unit, TableError)
  if table_bucket.empty?
    return Error(Storage(InvalidArgument(reason: "table bucket name cannot be empty")))
  end
  var seen = Set.empty
  for spec in specs
    if spec.bucket.empty?
      return Error(Storage(InvalidArgument(reason: "index bucket name cannot be empty")))
    end
    if spec.bucket == table_bucket
      return Error(
        Storage(
          InvalidArgument(
            reason: "index bucket '#{spec.bucket}' cannot share primary table bucket name"
          )
        )
      )
    end
    if seen.has?(spec.bucket)
      return Error(
        Storage(InvalidArgument(reason: "duplicate index bucket '#{spec.bucket}' on table"))
      )
    end
    seen = seen.add(spec.bucket)
  end
  Ok(Unit)
end

fn remove_index_entry(tx: WriteTx, spec: IndexSpec(K, V), old_ik: Bytes, pk_bytes: Bytes) : Result(
  WriteTx,
  TableError
)
  if spec.unique
    case try Modb.tx_get(tx, spec.bucket, old_ik)
      Some(owner) if owner == pk_bytes: Ok(try Modb.tx_delete(tx, spec.bucket, old_ik))
      Some(_) | None: Ok(tx)
    end
  else
    comp = encode_composite_key(old_ik, pk_bytes)
    Ok(try Modb.tx_delete(tx, spec.bucket, comp))
  end
end

fn insert_index_entry(
  tx: WriteTx,
  spec: IndexSpec(K, V),
  new_ik: Bytes,
  pk_bytes: Bytes,
  new_val: V
) : Result(WriteTx, TableError)
  if spec.unique
    case try Modb.tx_get(tx, spec.bucket, new_ik)
      Some(owner) if owner != pk_bytes: Error(
        UniqueConflict(index: spec.bucket, value: spec.describe_key(new_val))
      )
      Some(_): Ok(tx)
      None: Ok(try Modb.tx_put(tx, spec.bucket, new_ik, pk_bytes))
    end
  else
    comp = encode_composite_key(new_ik, pk_bytes)
    case try Modb.tx_get(tx, spec.bucket, comp)
      Some(_): Ok(tx)
      None: Ok(try Modb.tx_put(tx, spec.bucket, comp, Bytes.empty))
    end
  end
end

## Inserts or updates `(key, value)` in `tbl` and atomically maintains `specs`.
fn put_specs(tx: WriteTx, tbl: Table(K, V), specs: List(IndexSpec(K, V)), key: K, value: V) : Result(
  WriteTx,
  TableError
)
  all_specs = merge_specs(tbl.indexes, specs)
  try validate_specs(tbl.bucket, all_specs)
  pk_bytes = tbl.key_codec.encode(key)
  val_bytes = tbl.encode_value(value)
  if all_specs.empty?
    return Ok(try Modb.tx_put(tx, tbl.bucket, pk_bytes, val_bytes))
  end

  old_val_opt = case try Modb.tx_get(tx, tbl.bucket, pk_bytes)
    None: None
    Some(old_raw): Some(try tbl.decode_value(old_raw))
  end

  var cur_tx = tx
  for spec in all_specs
    new_ik = spec.encode_key(value)
    case old_val_opt
      Some(old_val):
        old_ik = spec.encode_key(old_val)
        if old_ik != new_ik
          cur_tx = try remove_index_entry(cur_tx, spec, old_ik, pk_bytes)
        end
        cur_tx = try insert_index_entry(cur_tx, spec, new_ik, pk_bytes, value)
      None: cur_tx = try insert_index_entry(cur_tx, spec, new_ik, pk_bytes, value)
    end
  end
  Ok(try Modb.tx_put(cur_tx, tbl.bucket, pk_bytes, val_bytes))
end

## Inserts or updates `(key, value)` in `tbl`, maintaining any indexes attached via `with_index`.
fn put(tx: WriteTx, tbl: Table(K, V), key: K, value: V) : Result(WriteTx, TableError)
  put_specs(tx, tbl, [], key, value)
end

## Inserts or updates a batch of `(key, value)` pairs in `tbl` atomically inside `tx`.
fn put_many(tx: WriteTx, tbl: Table(K, V), entries: List((K, V))) : Result(WriteTx, TableError)
  var cur = tx
  for (k, v) in entries
    cur = try put(cur, tbl, k, v)
  end
  Ok(cur)
end

## Inserts or updates `(key, value)` in `tbl`, atomically maintaining `indexes` (plus any attached indexes).
fn put_indexed(tx: WriteTx, tbl: Table(K, V), indexes: List(Index(K, V, I)), key: K, value: V) : Result(
  WriteTx,
  TableError
)
  put_specs(tx, tbl, indexes.map(index_spec), key, value)
end

## Deletes `key` from `tbl` and atomically removes all of its entries across `specs`.
fn delete_specs(tx: WriteTx, tbl: Table(K, V), specs: List(IndexSpec(K, V)), key: K) : Result(
  WriteTx,
  TableError
)
  all_specs = merge_specs(tbl.indexes, specs)
  try validate_specs(tbl.bucket, all_specs)
  pk_bytes = tbl.key_codec.encode(key)
  if all_specs.empty?
    return Ok(try Modb.tx_delete(tx, tbl.bucket, pk_bytes))
  end

  case try Modb.tx_get(tx, tbl.bucket, pk_bytes)
    None: Ok(tx)
    Some(old_raw):
      old_val = try tbl.decode_value(old_raw)
      var cur_tx = tx
      for spec in all_specs
        old_ik = spec.encode_key(old_val)
        cur_tx = try remove_index_entry(cur_tx, spec, old_ik, pk_bytes)
      end
      Ok(try Modb.tx_delete(cur_tx, tbl.bucket, pk_bytes))
  end
end

## Deletes `key` from `tbl`, removing all entries from indexes attached via `with_index`.
fn delete(tx: WriteTx, tbl: Table(K, V), key: K) : Result(WriteTx, TableError)
  delete_specs(tx, tbl, [], key)
end

## Deletes a batch of primary `keys` from `tbl` atomically inside `tx`.
fn delete_many(tx: WriteTx, tbl: Table(K, V), keys: List(K)) : Result(WriteTx, TableError)
  var cur = tx
  for k in keys
    cur = try delete(cur, tbl, k)
  end
  Ok(cur)
end

## Deletes `key` from `tbl`, atomically cleaning up `indexes` (plus any attached indexes).
fn delete_indexed(tx: WriteTx, tbl: Table(K, V), indexes: List(Index(K, V, I)), key: K) : Result(
  WriteTx,
  TableError
)
  delete_specs(tx, tbl, indexes.map(index_spec), key)
end

fn decode_rows(tbl: Table(K, V), raw_rows: List((Bytes, Bytes))) : Result(List((K, V)), TableError)
  var out = []
  for (kb, vb) in raw_rows
    k = try tbl.key_codec.decode(kb)
    v = try tbl.decode_value(vb)
    out = out.append((k, v))
  end
  Ok(out)
end

fn empty_bounds?(lo: Option(Bytes), hi: Option(Bytes)) : Bool
  case (lo, hi)
    (Some(a), Some(b)): a >= b
    (Some(_), None) | (None, Some(_)) | (None, None): false
  end
end

fn fetch_indexed_row(tbl: Table(K, V), idx_bucket: Text, pk_bytes: Bytes, raw_opt: Option(Bytes)) : Result(
  (K, V),
  TableError
)
  raw_val = try raw_opt.or_fail(
    CorruptIndex(
      index: idx_bucket,
      reason: "dangling reference to missing primary key #{pk_bytes.to_hex}"
    )
  )
  k = try tbl.key_codec.decode(pk_bytes)
  v = try tbl.decode_value(raw_val)
  Ok((k, v))
end

## Point lookup inside an active `WriteTx` (sees uncommitted writes in `tx`).
fn tx_get(tx: WriteTx, tbl: Table(K, V), key: K) : Result(Option(V), TableError)
  case try Modb.tx_get(tx, tbl.bucket, tbl.key_codec.encode(key))
    None: Ok(None)
    Some(raw): Ok(Some(try tbl.decode_value(raw)))
  end
end

## Ordered primary-key range scan `[start_key, end_key)` inside an active `WriteTx`.
fn tx_scan(tx: WriteTx, tbl: Table(K, V), start_key: Option(K), end_key: Option(K), limit: Int) : Result(
  List((K, V)),
  TableError
)
  lo = start_key.map(tbl.key_codec.encode)
  hi = end_key.map(tbl.key_codec.encode)
  return Ok([]) if empty_bounds?(lo, hi)
  raw_rows = try Modb.tx_scan(tx, tbl.bucket, lo, hi, limit)
  decode_rows(tbl, raw_rows)
end

## Exact secondary-index lookup inside an active `WriteTx`.
fn tx_lookup(tx: WriteTx, tbl: Table(K, V), idx: Index(K, V, I), index_key: I) : Result(
  List((K, V)),
  TableError
)
  ik_bytes = idx.key_codec.encode(index_key)
  if idx.unique
    case try Modb.tx_get(tx, idx.bucket, ik_bytes)
      None: Ok([])
      Some(pk_bytes):
        raw_opt = try Modb.tx_get(tx, tbl.bucket, pk_bytes)
        pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
        Ok([pair])
    end
  else
    lo = frame_index_prefix(ik_bytes, 0)
    hi = frame_index_prefix(ik_bytes, 1)
    idx_rows = try Modb.tx_scan(tx, idx.bucket, Some(lo), Some(hi), 0)
    var out = []
    for (comp_bytes, _empty) in idx_rows
      (_ik, pk_bytes) = try decode_composite_key(comp_bytes)
      raw_opt = try Modb.tx_get(tx, tbl.bucket, pk_bytes)
      pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
      out = out.append(pair)
    end
    Ok(out)
  end
end

## Exact lookup on a unique secondary index inside an active `WriteTx`.
fn tx_lookup_unique(tx: WriteTx, tbl: Table(K, V), idx: Index(K, V, I), index_key: I) : Result(
  Option((K, V)),
  TableError
)
  if not idx.unique
    return Error(
      Storage(
        InvalidArgument(
          reason: "tx_lookup_unique requires a unique index, got non-unique '#{idx.bucket}'"
        )
      )
    )
  end
  ik_bytes = idx.key_codec.encode(index_key)
  case try Modb.tx_get(tx, idx.bucket, ik_bytes)
    None: Ok(None)
    Some(pk_bytes):
      raw_opt = try Modb.tx_get(tx, tbl.bucket, pk_bytes)
      Ok(Some(try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)))
  end
end

## Point lookup by primary key `K` on committed `Store` state.
fn get(store: Store, tbl: Table(K, V), key: K) : Result(Option(V), TableError)
  case try Modb.get(store, tbl.bucket, tbl.key_codec.encode(key))
    None: Ok(None)
    Some(raw): Ok(Some(try tbl.decode_value(raw)))
  end
end

## Ordered primary-key range scan over `[start_key, end_key)` (`limit <= 0` returns all matches).
fn scan(store: Store, tbl: Table(K, V), start_key: Option(K), end_key: Option(K), limit: Int) : Result(
  List((K, V)),
  TableError
)
  lo = start_key.map(tbl.key_codec.encode)
  hi = end_key.map(tbl.key_codec.encode)
  return Ok([]) if empty_bounds?(lo, hi)
  raw_rows = try Modb.scan(store, tbl.bucket, lo, hi, limit)
  decode_rows(tbl, raw_rows)
end

## Ordered range scan over half-open primary-key interval `[start_key, end_key)`.
fn range(store: Store, tbl: Table(K, V), start_key: K, end_key: K) : Result(
  List((K, V)),
  TableError
)
  scan(store, tbl, Some(start_key), Some(end_key), 0)
end

## Returns all `(K, V)` entries in `tbl` sorted by primary key `K`.
fn all(store: Store, tbl: Table(K, V)) : Result(List((K, V)), TableError)
  scan(store, tbl, None, None, 0)
end

## Counts committed rows in `tbl` without decoding row payloads.
fn count(store: Store, tbl: Table(K, V)) : Result(Int, TableError)
  n = try Modb.count_bucket(store, tbl.bucket)
  Ok(n)
end

## Exact secondary-index match returning all matching `(K, V)` pairs sorted by primary key `K`.
fn lookup(store: Store, tbl: Table(K, V), idx: Index(K, V, I), index_key: I) : Result(
  List((K, V)),
  TableError
)
  ik_bytes = idx.key_codec.encode(index_key)
  if idx.unique
    case try Modb.get(store, idx.bucket, ik_bytes)
      None: Ok([])
      Some(pk_bytes):
        raw_opt = try Modb.get(store, tbl.bucket, pk_bytes)
        pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
        Ok([pair])
    end
  else
    lo = frame_index_prefix(ik_bytes, 0)
    hi = frame_index_prefix(ik_bytes, 1)
    idx_rows = try Modb.scan(store, idx.bucket, Some(lo), Some(hi), 0)
    var out = []
    for (comp_bytes, _empty) in idx_rows
      (_ik, pk_bytes) = try decode_composite_key(comp_bytes)
      raw_opt = try Modb.get(store, tbl.bucket, pk_bytes)
      pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
      out = out.append(pair)
    end
    Ok(out)
  end
end

## Exact lookup on a unique secondary index returning `Option((K, V))`.
fn lookup_unique(store: Store, tbl: Table(K, V), idx: Index(K, V, I), index_key: I) : Result(
  Option((K, V)),
  TableError
)
  if not idx.unique
    return Error(
      Storage(
        InvalidArgument(
          reason: "lookup_unique requires a unique index, got non-unique '#{idx.bucket}'"
        )
      )
    )
  end
  ik_bytes = idx.key_codec.encode(index_key)
  case try Modb.get(store, idx.bucket, ik_bytes)
    None: Ok(None)
    Some(pk_bytes):
      raw_opt = try Modb.get(store, tbl.bucket, pk_bytes)
      Ok(Some(try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)))
  end
end

## Ordered range scan over secondary index `idx` on `[start_key, end_key)` (`limit <= 0` returns all).
fn range_by(
  store: Store,
  tbl: Table(K, V),
  idx: Index(K, V, I),
  start_key: Option(I),
  end_key: Option(I),
  limit: Int
) : Result(List((K, V)), TableError)
  if idx.unique
    lo = start_key.map(idx.key_codec.encode)
    hi = end_key.map(idx.key_codec.encode)
    return Ok([]) if empty_bounds?(lo, hi)
    idx_rows = try Modb.scan(store, idx.bucket, lo, hi, limit)
    var out = []
    for (_ik_bytes, pk_bytes) in idx_rows
      raw_opt = try Modb.get(store, tbl.bucket, pk_bytes)
      pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
      out = out.append(pair)
    end
    Ok(out)
  else
    lo = start_key.map(fn(s) frame_index_prefix(idx.key_codec.encode(s), 0) end)
    hi = end_key.map(fn(e) frame_index_prefix(idx.key_codec.encode(e), 0) end)
    return Ok([]) if empty_bounds?(lo, hi)
    idx_rows = try Modb.scan(store, idx.bucket, lo, hi, limit)
    var out = []
    for (comp_bytes, _empty) in idx_rows
      (_ik, pk_bytes) = try decode_composite_key(comp_bytes)
      raw_opt = try Modb.get(store, tbl.bucket, pk_bytes)
      pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
      out = out.append(pair)
    end
    Ok(out)
  end
end

## Point lookup by primary key against a pinned `Modb.Snapshot`.
fn snapshot_get(store: Store, snap: Snapshot, tbl: Table(K, V), key: K) : Result(
  Option(V),
  TableError
)
  case try Modb.snapshot_get(store, snap, tbl.bucket, tbl.key_codec.encode(key))
    None: Ok(None)
    Some(raw): Ok(Some(try tbl.decode_value(raw)))
  end
end

## Ordered primary-key range scan `[start_key, end_key)` against a pinned `Modb.Snapshot`.
fn snapshot_scan(
  store: Store,
  snap: Snapshot,
  tbl: Table(K, V),
  start_key: Option(K),
  end_key: Option(K),
  limit: Int
) : Result(List((K, V)), TableError)
  lo = start_key.map(tbl.key_codec.encode)
  hi = end_key.map(tbl.key_codec.encode)
  if empty_bounds?(lo, hi)
    ## Still validate that `snap` is an active snapshot on `store`.
    _ = try Modb.snapshot_scan(store, snap, tbl.bucket, None, None, 1)
    return Ok([])
  end
  raw_rows = try Modb.snapshot_scan(store, snap, tbl.bucket, lo, hi, limit)
  decode_rows(tbl, raw_rows)
end

## Returns all `(K, V)` rows in `tbl` as of `snap`.
fn snapshot_all(store: Store, snap: Snapshot, tbl: Table(K, V)) : Result(List((K, V)), TableError)
  snapshot_scan(store, snap, tbl, None, None, 0)
end

## Point lookup by primary key against an explicit committed/pinned `cat_root`.
fn get_at_root(store: Store, cat_root: Int, tbl: Table(K, V), key: K) : Result(
  Option(V),
  TableError
)
  case try Modb.get_at_root(store, cat_root, tbl.bucket, tbl.key_codec.encode(key))
    None: Ok(None)
    Some(raw): Ok(Some(try tbl.decode_value(raw)))
  end
end

## Ordered primary-key range scan `[start_key, end_key)` against an explicit committed/pinned `cat_root`.
fn scan_at_root(
  store: Store,
  cat_root: Int,
  tbl: Table(K, V),
  start_key: Option(K),
  end_key: Option(K),
  limit: Int
) : Result(List((K, V)), TableError)
  lo = start_key.map(tbl.key_codec.encode)
  hi = end_key.map(tbl.key_codec.encode)
  return Ok([]) if empty_bounds?(lo, hi)
  raw_rows = try Modb.scan_at_root(store, cat_root, tbl.bucket, lo, hi, limit)
  decode_rows(tbl, raw_rows)
end

## Returns all `(K, V)` rows in `tbl` at an explicit committed/pinned `cat_root`.
fn all_at_root(store: Store, cat_root: Int, tbl: Table(K, V)) : Result(List((K, V)), TableError)
  scan_at_root(store, cat_root, tbl, None, None, 0)
end

## Structural O(diff) typed row diff for `tbl` between two committed/pinned catalog roots.
fn diff_roots(store: Store, tbl: Table(K, V), root_a: Int, root_b: Int) : Result(
  List(RowDiff(K, V)),
  TableError
)
  raw_diffs = try Modb.diff_bucket_roots(store, root_a, root_b, tbl.bucket)
  var out = []
  for d in raw_diffs
    case d
      Added(key: kb, value: vb):
        k = try tbl.key_codec.decode(kb)
        v = try tbl.decode_value(vb)
        out = out.append(RowAdded(key: k, value: v))
      Removed(key: kb, value: va):
        k = try tbl.key_codec.decode(kb)
        v = try tbl.decode_value(va)
        out = out.append(RowRemoved(key: k, value: v))
      Modified(key: kb, old_value: va, new_value: vb):
        k = try tbl.key_codec.decode(kb)
        ov = try tbl.decode_value(va)
        nv = try tbl.decode_value(vb)
        out = out.append(RowModified(key: k, old_value: ov, new_value: nv))
    end
  end
  Ok(out)
end

## Exact secondary-index lookup against a pinned `Modb.Snapshot`.
fn snapshot_lookup(
  store: Store,
  snap: Snapshot,
  tbl: Table(K, V),
  idx: Index(K, V, I),
  index_key: I
) : Result(List((K, V)), TableError)
  ik_bytes = idx.key_codec.encode(index_key)
  if idx.unique
    case try Modb.snapshot_get(store, snap, idx.bucket, ik_bytes)
      None: Ok([])
      Some(pk_bytes):
        raw_opt = try Modb.snapshot_get(store, snap, tbl.bucket, pk_bytes)
        pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
        Ok([pair])
    end
  else
    lo = frame_index_prefix(ik_bytes, 0)
    hi = frame_index_prefix(ik_bytes, 1)
    idx_rows = try Modb.snapshot_scan(store, snap, idx.bucket, Some(lo), Some(hi), 0)
    var out = []
    for (comp_bytes, _empty) in idx_rows
      (_ik, pk_bytes) = try decode_composite_key(comp_bytes)
      raw_opt = try Modb.snapshot_get(store, snap, tbl.bucket, pk_bytes)
      pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
      out = out.append(pair)
    end
    Ok(out)
  end
end

## Exact unique-index lookup against a pinned `Modb.Snapshot`.
fn snapshot_lookup_unique(
  store: Store,
  snap: Snapshot,
  tbl: Table(K, V),
  idx: Index(K, V, I),
  index_key: I
) : Result(Option((K, V)), TableError)
  if not idx.unique
    return Error(
      Storage(
        InvalidArgument(
          reason: "snapshot_lookup_unique requires a unique index, got non-unique '#{idx.bucket}'"
        )
      )
    )
  end
  ik_bytes = idx.key_codec.encode(index_key)
  case try Modb.snapshot_get(store, snap, idx.bucket, ik_bytes)
    None: Ok(None)
    Some(pk_bytes):
      raw_opt = try Modb.snapshot_get(store, snap, tbl.bucket, pk_bytes)
      Ok(Some(try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)))
  end
end

## Secondary-index range scan `[start_key, end_key)` against a pinned `Modb.Snapshot`.
fn snapshot_range_by(
  store: Store,
  snap: Snapshot,
  tbl: Table(K, V),
  idx: Index(K, V, I),
  start_key: Option(I),
  end_key: Option(I),
  limit: Int
) : Result(List((K, V)), TableError)
  if idx.unique
    lo = start_key.map(idx.key_codec.encode)
    hi = end_key.map(idx.key_codec.encode)
    if empty_bounds?(lo, hi)
      _ = try Modb.snapshot_scan(store, snap, idx.bucket, None, None, 1)
      return Ok([])
    end
    idx_rows = try Modb.snapshot_scan(store, snap, idx.bucket, lo, hi, limit)
    var out = []
    for (_ik_bytes, pk_bytes) in idx_rows
      raw_opt = try Modb.snapshot_get(store, snap, tbl.bucket, pk_bytes)
      pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
      out = out.append(pair)
    end
    Ok(out)
  else
    lo = start_key.map(fn(s) frame_index_prefix(idx.key_codec.encode(s), 0) end)
    hi = end_key.map(fn(e) frame_index_prefix(idx.key_codec.encode(e), 0) end)
    if empty_bounds?(lo, hi)
      _ = try Modb.snapshot_scan(store, snap, idx.bucket, None, None, 1)
      return Ok([])
    end
    idx_rows = try Modb.snapshot_scan(store, snap, idx.bucket, lo, hi, limit)
    var out = []
    for (comp_bytes, _empty) in idx_rows
      (_ik, pk_bytes) = try decode_composite_key(comp_bytes)
      raw_opt = try Modb.snapshot_get(store, snap, tbl.bucket, pk_bytes)
      pair = try fetch_indexed_row(tbl, idx.bucket, pk_bytes, raw_opt)
      out = out.append(pair)
    end
    Ok(out)
  end
end

struct MiniUser
  email: Text
  role: Text
end

test "order-preserving Int and composite key codecs"
  ordered = [int64_min, -1000, -1, 0, 1, 1000, int64_max]
  for i in 0..ordered.size
    v = ordered.get(i) or stop "in bounds"
    enc = encode_int_key(v)
    assert decode_int_key(enc) == Ok(v)
    if i + 1 < ordered.size
      nxt = ordered.get(i + 1) or stop "in bounds"
      assert enc < encode_int_key(nxt)
    end
  end

  b0 = 0.to_byte or stop "byte"
  bff = 255.to_byte or stop "byte"
  k1 = Bytes.from_list([b0, bff])
  pk1 = Bytes.from_list([bff, b0])
  comp = encode_composite_key(k1, pk1)
  assert decode_composite_key(comp) == Ok((k1, pk1))
end

test "basic Table CRUD and secondary index maintenance"
  files = Files.in_memory({})
  assert Modb.open(files, "unit.modb") is Ok(db0)
  by_email = unique_text_index[Int, MiniUser]("users_by_email", fn(u) u.email end)
  by_role = text_index[Int, MiniUser]("users_by_role", fn(u) u.role end)
  users = int_key[MiniUser]("users").with_index(by_email).with_index(by_role)

  assert write_tx(
    db0,
    fn(tx)
      t1 = try put(tx, users, 1, MiniUser(email: "ada@ex.org", role: "admin"))
      put(t1, users, 2, MiniUser(email: "grace@ex.org", role: "admin"))
    end
  ) is
    Ok(db1)

  assert get(db1, users, 1) == Ok(Some(MiniUser(email: "ada@ex.org", role: "admin")))
  assert lookup_unique(db1, users, by_email, "ada@ex.org") ==
    Ok(Some((1, MiniUser(email: "ada@ex.org", role: "admin"))))
  assert lookup(db1, users, by_role, "admin") ==
    Ok([
      (1, MiniUser(email: "ada@ex.org", role: "admin")),
      (2, MiniUser(email: "grace@ex.org", role: "admin"))
    ])
  assert Modb.verify(db1) is Ok(_)
end
