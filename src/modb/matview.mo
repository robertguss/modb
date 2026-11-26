## MoDB Milestone 15 (`v0.7.0`): Incremental Copy-on-Write Materialized Views (`Modb.Matview`).
##
## Persists grouped summary tables (`MatCount`, `MatSum`, `MatMin`, `MatMax` over `Decimal`-exact
## numbers) in `_modb_matview_meta` / `_modb_matview_rows`, using a persistent root pin
## `mv:<name>` + structural `Modb.diff_bucket_roots` to refresh in O(diff) with single-group
## recompute fallback on extremum (`MatMin`/`MatMax`) deletes/loosenings and full rebuild fallback
## on missing/stale pins after crashes or external root changes.
module Modb.Matview
expose meta_bucket,
rows_bucket,
MatAggOp(..),
MatAggSpec(..),
MatViewDef(..),
MatViewMeta(..),
MatGroupRow(..),
MatRefreshReport(..),
MatQueryResult(..),
MatViewError(..),
to_text,
define_matview,
rebuild_matview,
tx_apply_matview,
refresh_matview,
query_matview,
get_matview,
list_matviews,
drop_matview
use Json
use Modb{Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Table{Table}
use Modb.Tree{KeyDiff}

meta_bucket = "_modb_matview_meta"
rows_bucket = "_modb_matview_rows"

enum MatAggOp
  MatCount
  MatSum(field: Text)
  MatMin(field: Text)
  MatMax(field: Text)
end

struct MatAggSpec
  alias: Text
  op: MatAggOp
end

struct MatViewDef
  name: Text
  description: Text
  source_bucket: Text
  group_by: Text
  aggregates: List(MatAggSpec)
end

struct MatViewMeta
  def: MatViewDef
  last_txid: Int
  pin_aligned?: Bool
  group_count: Int
  source_rows_seen: Int
  rebuilds: Int
  incremental_refreshes: Int
  group_recomputes: Int
end

struct MatGroupRow
  mv_name: Text
  group_key: Text
  group_value: Json
  row_count: Int
  sums: Map(Text, Decimal)
  mins: Map(Text, Json)
  maxs: Map(Text, Json)
end

struct MatRefreshReport
  name: Text
  strategy: Text
  diffs_applied: Int
  groups_touched: Int
  group_recomputes: Int
  last_txid: Int
  group_count: Int
end

struct MatQueryResult
  name: Text
  last_txid: Int
  total_groups: Int
  returned_groups: Int
  suppressed_groups: Int
  rows: List(Json)
end

enum MatViewError
  Storage(ModbError)
  TableFailure(Table.TableError)
  UnknownMatView(name: Text)
  InvalidDefinition(reason: Text)
end

fn to_text(err: MatViewError) : Text
  case err
    Storage(e): e.to_text
    TableFailure(e): e.to_text
    UnknownMatView(name: n): "unknown materialized view '#{n}'"
    InvalidDefinition(reason: r): "invalid materialized view definition: #{r}"
  end
end

fn meta_table() : Table(Text, MatViewMeta)
  Table.text_key[MatViewMeta](meta_bucket)
end

fn rows_table() : Table(Text, MatGroupRow)
  Table.text_key[MatGroupRow](rows_bucket)
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, MatViewError)
  res.map_error(fn(e) Storage(e) end)
end

fn wrap_table(res: Result(T, Table.TableError)) : Result(T, MatViewError)
  res.map_error(fn(e) TableFailure(e) end)
end

fn pin_id(mv_name: Text) : Text
  "mv:#{mv_name}"
end

fn row_storage_key(mv_name: Text, group_key: Text) : Text
  "#{mv_name}\t#{group_key}"
end

fn row_prefix(mv_name: Text) : Text
  "#{mv_name}\t"
end

fn row_prefix_end(mv_name: Text) : Text
  "#{mv_name}\u{000a}"
end

fn validate_def(def: MatViewDef) : Result(Unit, MatViewError)
  clean_name = def.name.trim
  if clean_name.empty? or clean_name != def.name or clean_name.contains?("\t") or
    clean_name.contains?("\n")
    return Error(
      InvalidDefinition(reason: "matview name must be non-empty without tabs or newlines")
    )
  end
  if def.source_bucket.trim.empty? or def.source_bucket.starts_with?("_modb_")
    return Error(
      InvalidDefinition(
        reason: "source_bucket '#{def.source_bucket}' must be a non-empty user bucket"
      )
    )
  end
  if def.group_by.trim.empty?
    return Error(InvalidDefinition(reason: "group_by field cannot be empty"))
  end
  if def.aggregates.empty?
    return Error(InvalidDefinition(reason: "at least one aggregate must be declared"))
  end
  var seen = Set.empty
  for agg in def.aggregates
    if agg.alias.trim.empty?
      return Error(InvalidDefinition(reason: "aggregate alias cannot be empty"))
    end
    if agg.alias == def.group_by
      return Error(InvalidDefinition(reason: "aggregate alias '#{agg.alias}' collides with group_by"))
    end
    if seen.has?(agg.alias)
      return Error(InvalidDefinition(reason: "duplicate aggregate alias '#{agg.alias}'"))
    end
    seen = seen.add(agg.alias)
    case agg.op
      MatCount: Unit
      MatSum(field: f) | MatMin(field: f) | MatMax(field: f):
        if f.trim.empty?
          return Error(
            InvalidDefinition(reason: "aggregate '#{agg.alias}' requires a non-empty field")
          )
        end
    end
  end
  Ok(Unit)
end

fn decode_row_json(raw: Bytes) : Result(Json, MatViewError)
  txt = try raw.decode_utf8.or_fail(
    Storage(Corrupt(reason: "matview source row is not valid UTF-8"))
  )
  Json.parse(txt).map_error(fn(e)
    Storage(Corrupt(reason: "matview source row is not valid JSON: #{e}"))
  end)
end

fn json_decimal(v: Json) : Option(Decimal)
  case v
    Json.Number(n): n.to_decimal
    Json.Null | Json.Boolean(_) | Json.String(_) | Json.Array(_) | Json.Object(_): None
  end
end

fn compare_mat_json(a: Json, b: Json) : Int
  case (json_decimal(a), json_decimal(b))
    (Some(da), Some(db)):
      if da < db
        -1
      else if da > db
        1
      else
        0
      end
    (Some(_), None) | (None, Some(_)) | (None, None):
      sa = case a
        Json.String(t): t
        Json.Null | Json.Boolean(_) | Json.Number(_) | Json.Array(_) | Json.Object(_): a.to_text
      end
      sb = case b
        Json.String(t): t
        Json.Null | Json.Boolean(_) | Json.Number(_) | Json.Array(_) | Json.Object(_): b.to_text
      end
      if sa < sb
        -1
      else if sa > sb
        1
      else
        0
      end
  end
end

fn extract_group(row: Json, group_by: Text) : (Text, Json)
  gv = row.path(group_by) or Json.Null
  (gv.to_text, gv)
end

fn field_val(row: Json, field: Text) : Json
  row.path(field) or Json.Null
end

fn empty_group_row(mv_name: Text, gk: Text, gv: Json) : MatGroupRow
  MatGroupRow(
    mv_name: mv_name,
    group_key: gk,
    group_value: gv,
    row_count: 0,
    sums: {},
    mins: {},
    maxs: {}
  )
end

fn apply_insert_to_group(def: MatViewDef, g: MatGroupRow, row: Json) : MatGroupRow
  var next = g
  next.row_count += 1
  for agg in def.aggregates
    case agg.op
      MatCount: Unit
      MatSum(field: f):
        case json_decimal(field_val(row, f))
          Some(d):
            prev = next.sums.get(agg.alias) or 0.0
            next.sums = next.sums.set(agg.alias, prev + d)
          None: Unit
        end
      MatMin(field: f):
        fv = field_val(row, f)
        if not (fv is Json.Null)
          case next.mins.get(agg.alias)
            None: next.mins = next.mins.set(agg.alias, fv)
            Some(cur):
              if compare_mat_json(fv, cur) < 0
                next.mins = next.mins.set(agg.alias, fv)
              end
          end
        end
      MatMax(field: f):
        fv = field_val(row, f)
        if not (fv is Json.Null)
          case next.maxs.get(agg.alias)
            None: next.maxs = next.maxs.set(agg.alias, fv)
            Some(cur):
              if compare_mat_json(fv, cur) > 0
                next.maxs = next.maxs.set(agg.alias, fv)
              end
          end
        end
    end
  end
  next
end

## Returns `(updated_group, needs_group_recompute?)` when removing `row` from `g`.
fn apply_delete_from_group(def: MatViewDef, g: MatGroupRow, row: Json) : (MatGroupRow, Bool)
  var next = g
  next.row_count -= 1
  if next.row_count <= 0
    return (next, false)
  end
  var needs_recompute = false
  for agg in def.aggregates
    case agg.op
      MatCount: Unit
      MatSum(field: f):
        case json_decimal(field_val(row, f))
          Some(d):
            prev = next.sums.get(agg.alias) or 0.0
            next.sums = next.sums.set(agg.alias, prev - d)
          None: Unit
        end
      MatMin(field: f):
        fv = field_val(row, f)
        if not (fv is Json.Null)
          case next.mins.get(agg.alias)
            Some(cur):
              if compare_mat_json(fv, cur) == 0
                needs_recompute = true
              end
            None: Unit
          end
        end
      MatMax(field: f):
        fv = field_val(row, f)
        if not (fv is Json.Null)
          case next.maxs.get(agg.alias)
            Some(cur):
              if compare_mat_json(fv, cur) == 0
                needs_recompute = true
              end
            None: Unit
          end
        end
    end
  end
  (next, needs_recompute)
end

## Applies an in-place update `(old_row -> new_row)` inside the SAME group.
## Returns `(updated_group, needs_group_recompute?)`, avoiding recompute if a new value tightens
## or ties an existing extremum!
fn apply_update_same_group(
  def: MatViewDef,
  g: MatGroupRow,
  old_row: Json,
  new_row: Json
) : (MatGroupRow, Bool)
  var next = g
  var needs_recompute = false
  for agg in def.aggregates
    case agg.op
      MatCount: Unit
      MatSum(field: f):
        old_d = json_decimal(field_val(old_row, f)) or 0.0
        new_d = json_decimal(field_val(new_row, f)) or 0.0
        prev = next.sums.get(agg.alias) or 0.0
        next.sums = next.sums.set(agg.alias, prev - old_d + new_d)
      MatMin(field: f):
        ov = field_val(old_row, f)
        nv = field_val(new_row, f)
        cur_opt = next.mins.get(agg.alias)
        new_sets_tighter = case (cur_opt, nv)
          (_, Json.Null): false
          (None, _): true
          (Some(cur), _): compare_mat_json(nv, cur) <= 0
        end
        if new_sets_tighter
          next.mins = next.mins.set(agg.alias, nv)
        else
          # Only recompute if the removed old value equaled the stored minimum (and wasn't replaced <= cur)
          case (cur_opt, ov)
            (Some(cur), _) if not (ov is Json.Null):
              if compare_mat_json(ov, cur) == 0
                needs_recompute = true
              end
            (Some(_), _) | (None, _): Unit
          end
        end
      MatMax(field: f):
        ov = field_val(old_row, f)
        nv = field_val(new_row, f)
        cur_opt = next.maxs.get(agg.alias)
        new_sets_tighter = case (cur_opt, nv)
          (_, Json.Null): false
          (None, _): true
          (Some(cur), _): compare_mat_json(nv, cur) >= 0
        end
        if new_sets_tighter
          next.maxs = next.maxs.set(agg.alias, nv)
        else
          case (cur_opt, ov)
            (Some(cur), _) if not (ov is Json.Null):
              if compare_mat_json(ov, cur) == 0
                needs_recompute = true
              end
            (Some(_), _) | (None, _): Unit
          end
        end
    end
  end
  (next, needs_recompute)
end

fn render_group_json(def: MatViewDef, g: MatGroupRow) : Json
  var m = {}
  m = m.set(def.group_by, g.group_value)
  for agg in def.aggregates
    val = case agg.op
      MatCount: Json.int(g.row_count)
      MatSum(field: _): Json.decimal(g.sums.get(agg.alias) or 0.0)
      MatMin(field: _): g.mins.get(agg.alias) or Json.Null
      MatMax(field: _): g.maxs.get(agg.alias) or Json.Null
    end
    m = m.set(agg.alias, val)
  end
  Json.Object(m)
end

fn tx_set_pin_to_base(tx: WriteTx, id: Text) : Result((WriteTx, Modb.PinnedRoot), MatViewError)
  existing = try wrap_modb(Modb.get_pin(tx.base, id))
  tx1 = case existing
    Some(_): try wrap_modb(Modb.tx_unpin_root(tx, id))
    None: tx
  end
  wrap_modb(Modb.tx_pin_base_root(tx1, id))
end

fn tx_delete_mv_rows(tx: WriteTx, mv_name: Text) : Result(WriteTx, MatViewError)
  existing = try wrap_table(
    Table.scan(tx.base, rows_table(), Some(row_prefix(mv_name)), Some(row_prefix_end(mv_name)), 0)
  )
  var cur = tx
  for (rk, _rv) in existing
    cur = try wrap_table(Table.delete(cur, rows_table(), rk))
  end
  Ok(cur)
end

fn compute_all_groups(def: MatViewDef, store: Store) : Result(
  (Map(Text, MatGroupRow), Int),
  MatViewError
)
  raw_rows = try wrap_modb(Modb.scan(store, def.source_bucket, None, None, 0))
  var groups = {}
  var count = 0
  for (_k, raw_v) in raw_rows
    count += 1
    doc = try decode_row_json(raw_v)
    (gk, gv) = extract_group(doc, def.group_by)
    base = groups.get(gk) or empty_group_row(def.name, gk, gv)
    groups = groups.set(gk, apply_insert_to_group(def, base, doc))
  end
  Ok((groups, count))
end

fn recompute_single_group_from_tx(tx: WriteTx, def: MatViewDef, target_gk: Text) : Result(
  Option(MatGroupRow),
  MatViewError
)
  raw_rows = try wrap_modb(Modb.tx_scan(tx, def.source_bucket, None, None, 0))
  var acc_opt = None
  for (_k, raw_v) in raw_rows
    doc = try decode_row_json(raw_v)
    (gk, gv) = extract_group(doc, def.group_by)
    if gk == target_gk
      base = case acc_opt
        Some(prev): prev
        None: empty_group_row(def.name, gk, gv)
      end
      acc_opt = Some(apply_insert_to_group(def, base, doc))
    end
  end
  Ok(acc_opt)
end

## Full rebuild of `name` from committed `source_bucket`, aligning `mv:<name>` pin atomically.
fn rebuild_matview(store: Store, name: Text) : Result((Store, MatRefreshReport), MatViewError)
  meta = try (try wrap_table(Table.get(store, meta_table(), name))).or_fail(
    UnknownMatView(name: name)
  )
  def = meta.def
  (groups, seen_count) = try compute_all_groups(def, store)

  tx0 = Modb.begin_write(store)
  tx1 = try tx_delete_mv_rows(tx0, name)
  var tx = tx1
  for (gk, g) in groups.entries
    tx = try wrap_table(Table.put(tx, rows_table(), row_storage_key(name, gk), g))
  end
  (tx_pinned, pin) = try tx_set_pin_to_base(tx, pin_id(name))
  next_meta = MatViewMeta(
    def: def,
    last_txid: pin.txid,
    pin_aligned?: true,
    group_count: groups.size,
    source_rows_seen: seen_count,
    rebuilds: meta.rebuilds + 1,
    incremental_refreshes: meta.incremental_refreshes,
    group_recomputes: meta.group_recomputes
  )
  tx_final = try wrap_table(Table.put(tx_pinned, meta_table(), name, next_meta))
  committed = try wrap_modb(Modb.commit(tx_final))
  Ok(
    (
      committed,
      MatRefreshReport(
        name: name,
        strategy: "rebuild",
        diffs_applied: seen_count,
        groups_touched: groups.size,
        group_recomputes: 0,
        last_txid: pin.txid,
        group_count: groups.size
      )
    )
  )
end

## Defines (or updates) a materialized view and builds its initial snapshot + `mv:<name>` pin.
fn define_matview(store: Store, def: MatViewDef) : Result((Store, MatViewMeta), MatViewError)
  try validate_def(def)
  tx0 = Modb.begin_write(store)
  prev_opt = try wrap_table(Table.get(store, meta_table(), def.name))
  init_meta = case prev_opt
    Some(m):
      MatViewMeta(
        def: def,
        last_txid: m.last_txid,
        pin_aligned?: false,
        group_count: m.group_count,
        source_rows_seen: m.source_rows_seen,
        rebuilds: m.rebuilds,
        incremental_refreshes: m.incremental_refreshes,
        group_recomputes: m.group_recomputes
      )
    None:
      MatViewMeta(
        def: def,
        last_txid: -1,
        pin_aligned?: false,
        group_count: 0,
        source_rows_seen: 0,
        rebuilds: 0,
        incremental_refreshes: 0,
        group_recomputes: 0
      )
  end
  tx1 = try wrap_table(Table.put(tx0, meta_table(), def.name, init_meta))
  s1 = try wrap_modb(Modb.commit(tx1))
  (s2, _rep) = try rebuild_matview(s1, def.name)
  final_meta = try (try wrap_table(Table.get(s2, meta_table(), def.name))).or_fail(
    UnknownMatView(name: def.name)
  )
  Ok((s2, final_meta))
end

fn apply_key_diffs_in_tx(
  tx: WriteTx,
  meta: MatViewMeta,
  diffs: List(KeyDiff),
  next_last_txid: Int,
  align_pin?: Bool,
  strategy_name: Text
) : Result((WriteTx, MatRefreshReport), MatViewError)
  def = meta.def
  var loaded_groups = {}
  var recompute_needed = Set.empty
  var touched = Set.empty
  var total_rows_seen = meta.source_rows_seen

  for d in diffs
    case d
      Added(key: _, value: vb):
        doc = try decode_row_json(vb)
        (gk, gv) = extract_group(doc, def.group_by)
        cur = case loaded_groups.get(gk)
          Some(opt): opt or empty_group_row(def.name, gk, gv)
          None:
            (try wrap_table(Table.get(tx.base, rows_table(), row_storage_key(def.name, gk)))) or
              empty_group_row(def.name, gk, gv)
        end
        loaded_groups = loaded_groups.set(gk, Some(apply_insert_to_group(def, cur, doc)))
        touched = touched.add(gk)
        total_rows_seen += 1
      Removed(key: _, value: va):
        doc = try decode_row_json(va)
        (gk, _gv) = extract_group(doc, def.group_by)
        cur_opt = case loaded_groups.get(gk)
          Some(opt): opt
          None: try wrap_table(Table.get(tx.base, rows_table(), row_storage_key(def.name, gk)))
        end
        case cur_opt
          None: recompute_needed = recompute_needed.add(gk)
          Some(cur):
            (updated, need_rec) = apply_delete_from_group(def, cur, doc)
            if updated.row_count <= 0
              loaded_groups = loaded_groups.set(gk, None)
            else
              loaded_groups = loaded_groups.set(gk, Some(updated))
              if need_rec
                recompute_needed = recompute_needed.add(gk)
              end
            end
        end
        touched = touched.add(gk)
        if total_rows_seen > 0
          total_rows_seen -= 1
        end
      Modified(key: _, old_value: va, new_value: vb):
        old_doc = try decode_row_json(va)
        new_doc = try decode_row_json(vb)
        (old_gk, _old_gv) = extract_group(old_doc, def.group_by)
        (new_gk, new_gv) = extract_group(new_doc, def.group_by)
        if old_gk == new_gk
          cur_opt = case loaded_groups.get(old_gk)
            Some(opt): opt
            None: try wrap_table(
              Table.get(tx.base, rows_table(), row_storage_key(def.name, old_gk))
            )
          end
          case cur_opt
            None:
              loaded_groups = loaded_groups.set(
                old_gk,
                Some(apply_insert_to_group(def, empty_group_row(def.name, old_gk, new_gv), new_doc))
              )
              recompute_needed = recompute_needed.add(old_gk)
            Some(cur):
              (updated, need_rec) = apply_update_same_group(def, cur, old_doc, new_doc)
              loaded_groups = loaded_groups.set(old_gk, Some(updated))
              if need_rec
                recompute_needed = recompute_needed.add(old_gk)
              end
          end
          touched = touched.add(old_gk)
        else
          # Group key changed: remove from old_gk and insert into new_gk
          old_cur_opt = case loaded_groups.get(old_gk)
            Some(opt): opt
            None: try wrap_table(
              Table.get(tx.base, rows_table(), row_storage_key(def.name, old_gk))
            )
          end
          case old_cur_opt
            None: recompute_needed = recompute_needed.add(old_gk)
            Some(old_cur):
              (updated_old, need_rec) = apply_delete_from_group(def, old_cur, old_doc)
              if updated_old.row_count <= 0
                loaded_groups = loaded_groups.set(old_gk, None)
              else
                loaded_groups = loaded_groups.set(old_gk, Some(updated_old))
                if need_rec
                  recompute_needed = recompute_needed.add(old_gk)
                end
              end
          end
          new_cur = case loaded_groups.get(new_gk)
            Some(opt): opt or empty_group_row(def.name, new_gk, new_gv)
            None:
              (try wrap_table(
                Table.get(tx.base, rows_table(), row_storage_key(def.name, new_gk))
              )) or
                empty_group_row(def.name, new_gk, new_gv)
          end
          loaded_groups = loaded_groups.set(new_gk, Some(apply_insert_to_group(def, new_cur, new_doc)))
          touched = touched.add(old_gk).add(new_gk)
        end
    end
  end

  # Recompute only affected groups whose stored extremum (MatMin/MatMax) was deleted/loosened
  var rec_count = 0
  for gk in recompute_needed.to_list
    recomputed_opt = try recompute_single_group_from_tx(tx, def, gk)
    loaded_groups = loaded_groups.set(gk, recomputed_opt)
    rec_count += 1
  end

  var cur_tx = tx
  var group_delta = 0
  for (gk, row_opt) in loaded_groups.entries
    sk = row_storage_key(def.name, gk)
    had_before = (try wrap_table(Table.get(tx.base, rows_table(), sk))) is Some(_)
    case row_opt
      Some(gr) if gr.row_count > 0:
        cur_tx = try wrap_table(Table.put(cur_tx, rows_table(), sk, gr))
        if not had_before
          group_delta += 1
        end
      Some(_) | None:
        if had_before
          cur_tx = try wrap_table(Table.delete(cur_tx, rows_table(), sk))
          group_delta -= 1
        end
    end
  end

  new_group_count = if meta.group_count + group_delta < 0
    0
  else
    meta.group_count + group_delta
  end

  var tx_pin_step = cur_tx
  var actual_last_txid = next_last_txid
  if align_pin?
    (tp, pin) = try tx_set_pin_to_base(cur_tx, pin_id(def.name))
    tx_pin_step = tp
    actual_last_txid = pin.txid
  else
    existing_pin = try wrap_modb(Modb.get_pin(cur_tx.base, pin_id(def.name)))
    case existing_pin
      Some(_): tx_pin_step = try wrap_modb(Modb.tx_unpin_root(cur_tx, pin_id(def.name)))
      None: Unit
    end
  end

  next_meta = MatViewMeta(
    def: def,
    last_txid: actual_last_txid,
    pin_aligned?: align_pin?,
    group_count: new_group_count,
    source_rows_seen: total_rows_seen,
    rebuilds: meta.rebuilds,
    incremental_refreshes: meta.incremental_refreshes + 1,
    group_recomputes: meta.group_recomputes + rec_count
  )
  tx_done = try wrap_table(Table.put(tx_pin_step, meta_table(), def.name, next_meta))
  Ok(
    (
      tx_done,
      MatRefreshReport(
        name: def.name,
        strategy: strategy_name,
        diffs_applied: diffs.size,
        groups_touched: touched.size,
        group_recomputes: rec_count,
        last_txid: actual_last_txid,
        group_count: new_group_count
      )
    )
  )
end

## Incrementally updates `name` inside an open `WriteTx` based on uncommitted writes in `tx`
## (and any source commits since `mv:<name>` pin), leaving the materialized view atomic with `tx`.
fn tx_apply_matview(tx: WriteTx, name: Text) : Result(WriteTx, MatViewError)
  meta = try (try wrap_table(Table.get(tx.base, meta_table(), name))).or_fail(
    UnknownMatView(name: name)
  )
  base_root_opt = if (not meta.pin_aligned?) and meta.last_txid == Modb.txid(tx.base)
    Some(Modb.catalog_root(tx.base))
  else
    case try wrap_modb(Modb.get_pin(tx.base, pin_id(name)))
      Some(p) if meta.pin_aligned? and p.txid == meta.last_txid: Some(p.catalog_root)
      Some(_) | None: None
    end
  end
  base_root = case base_root_opt
    Some(br): br
    None: return Ok(tx)
  end
  bucket_diffs = try wrap_modb(Modb.diff_user_tx_from_root(tx, base_root))
  var source_changes = []
  for bd in bucket_diffs
    if bd.bucket == meta.def.source_bucket
      source_changes = bd.changes
      break
    end
  end
  return Ok(tx) if source_changes.empty?
  (tx_next, _rep) = try apply_key_diffs_in_tx(
    tx,
    meta,
    source_changes,
    Modb.txid(tx.base) + 1,
    false,
    "tx_incremental"
  )
  Ok(tx_next)
end

## Incrementally refreshes `name` in O(diff) using persistent pin `mv:<name>` and `Modb.diff_bucket_roots`,
## falling back cleanly to `rebuild_matview` if the pin is missing or out of sync after a crash.
fn refresh_matview(store: Store, name: Text) : Result((Store, MatRefreshReport), MatViewError)
  meta = try (try wrap_table(Table.get(store, meta_table(), name))).or_fail(
    UnknownMatView(name: name)
  )
  cur_txid = Modb.txid(store)

  # Case 1: synchronous `tx_apply_matview` left rows current at cur_txid but cleared stale pin
  if (not meta.pin_aligned?) and meta.last_txid == cur_txid
    tx0 = Modb.begin_write(store)
    (tx1, pin) = try tx_set_pin_to_base(tx0, pin_id(name))
    next_meta = MatViewMeta(
      def: meta.def,
      last_txid: pin.txid,
      pin_aligned?: true,
      group_count: meta.group_count,
      source_rows_seen: meta.source_rows_seen,
      rebuilds: meta.rebuilds,
      incremental_refreshes: meta.incremental_refreshes,
      group_recomputes: meta.group_recomputes
    )
    tx2 = try wrap_table(Table.put(tx1, meta_table(), name, next_meta))
    committed = try wrap_modb(Modb.commit(tx2))
    return Ok(
      (
        committed,
        MatRefreshReport(
          name: name,
          strategy: "pin_align",
          diffs_applied: 0,
          groups_touched: 0,
          group_recomputes: 0,
          last_txid: pin.txid,
          group_count: meta.group_count
        )
      )
    )
  end

  pin_opt = try wrap_modb(Modb.get_pin(store, pin_id(name)))
  pin = case pin_opt
    Some(p) if meta.pin_aligned? and p.txid == meta.last_txid: p
    Some(_) | None: return rebuild_matview(store, name)
  end

  diffs = try wrap_modb(
    Modb.diff_bucket_roots(store, pin.catalog_root, Modb.catalog_root(store), meta.def.source_bucket)
  )
  if diffs.empty?
    return Ok(
      (
        store,
        MatRefreshReport(
          name: name,
          strategy: "noop",
          diffs_applied: 0,
          groups_touched: 0,
          group_recomputes: 0,
          last_txid: meta.last_txid,
          group_count: meta.group_count
        )
      )
    )
  end

  tx0 = Modb.begin_write(store)
  (tx1, rep) = try apply_key_diffs_in_tx(tx0, meta, diffs, cur_txid, true, "incremental")
  committed = try wrap_modb(Modb.commit(tx1))
  Ok((committed, rep))
end

## Queries materialized groups for `name`, applying optional k-anonymity suppression
## (`min_group_size: Some(k)` drops groups with `row_count < k`).
fn query_matview(store: Store, name: Text, min_group_size: Option(Int)) : Result(
  MatQueryResult,
  MatViewError
)
  meta = try (try wrap_table(Table.get(store, meta_table(), name))).or_fail(
    UnknownMatView(name: name)
  )
  stored = try wrap_table(
    Table.scan(store, rows_table(), Some(row_prefix(name)), Some(row_prefix_end(name)), 0)
  )
  var out = []
  var suppressed = 0
  for (_k, gr) in stored
    allow? = case min_group_size
      Some(k) if k > 1: gr.row_count >= k
      Some(_) | None: true
    end
    if allow?
      out = out.append(render_group_json(meta.def, gr))
    else
      suppressed += 1
    end
  end
  Ok(
    MatQueryResult(
      name: name,
      last_txid: meta.last_txid,
      total_groups: stored.size,
      returned_groups: out.size,
      suppressed_groups: suppressed,
      rows: out
    )
  )
end

fn get_matview(store: Store, name: Text) : Result(Option(MatViewMeta), MatViewError)
  wrap_table(Table.get(store, meta_table(), name))
end

fn list_matviews(store: Store) : Result(List(MatViewMeta), MatViewError)
  pairs = try wrap_table(Table.all(store, meta_table()))
  Ok(pairs.map(fn(p) p.1 end))
end

fn drop_matview(store: Store, name: Text) : Result(Store, MatViewError)
  _meta = try (try wrap_table(Table.get(store, meta_table(), name))).or_fail(
    UnknownMatView(name: name)
  )
  tx0 = Modb.begin_write(store)
  tx1 = try tx_delete_mv_rows(tx0, name)
  tx2 = try wrap_table(Table.delete(tx1, meta_table(), name))
  tx3 = case try wrap_modb(Modb.get_pin(store, pin_id(name)))
    Some(_): try wrap_modb(Modb.tx_unpin_root(tx2, pin_id(name)))
    None: tx2
  end
  wrap_modb(Modb.commit(tx3))
end

test "Matview define, incremental refresh, extremum recompute, crash fallback, and k-anonymity"
  assert Modb.open(Files.in_memory({}), "mv.modb") is Ok(s0)
  orders = Table.int_key[Json]("orders")

  tx0 = Modb.begin_write(s0)
  assert Table.put(tx0, orders, 1, Json.Object({"dept": "ops".to_json, "cost": Json.decimal(10.50)})) is
    Ok(tx1)
  assert Table.put(tx1, orders, 2, Json.Object({"dept": "ops".to_json, "cost": Json.decimal(25.00)})) is
    Ok(tx2)
  assert Table.put(tx2, orders, 3, Json.Object({"dept": "ml".to_json, "cost": Json.decimal(50.25)})) is
    Ok(tx3)
  assert Modb.commit(tx3) is Ok(s1)

  mv_def = MatViewDef(
    name: "spend_by_dept",
    description: "Total/min/max spend by department",
    source_bucket: "orders",
    group_by: "dept",
    aggregates: [
      MatAggSpec(alias: "cnt", op: MatCount),
      MatAggSpec(alias: "total", op: MatSum(field: "cost")),
      MatAggSpec(alias: "min_cost", op: MatMin(field: "cost")),
      MatAggSpec(alias: "max_cost", op: MatMax(field: "cost"))
    ]
  )
  assert define_matview(s1, mv_def) is Ok((s2, m0))
  assert m0.group_count == 2 and m0.source_rows_seen == 3 and m0.pin_aligned?

  # Unchanged store -> noop
  assert refresh_matview(s2, "spend_by_dept") is Ok((_s2b, noop_rep))
  assert noop_rep.strategy == "noop"

  # Delete extremum row (id=1 cost=10.50 -> triggers single-group recompute) + insert new group "sec"
  tx4 = Modb.begin_write(s2)
  assert Table.delete(tx4, orders, 1) is Ok(tx5)
  assert Table.put(tx5, orders, 4, Json.Object({"dept": "ops".to_json, "cost": Json.decimal(12.25)})) is
    Ok(tx6)
  assert Table.put(tx6, orders, 5, Json.Object({"dept": "sec".to_json, "cost": Json.decimal(99.0)})) is
    Ok(tx7)
  assert Modb.commit(tx7) is Ok(s3)

  assert refresh_matview(s3, "spend_by_dept") is Ok((s4, rep_inc))
  assert rep_inc.strategy == "incremental" and rep_inc.group_recomputes == 1
  assert rep_inc.group_count == 3

  # k-anonymity suppression (ml=1 row, sec=1 row suppressed when min_group_size=2)
  assert query_matview(s4, "spend_by_dept", Some(2)) is Ok(kq)
  assert kq.total_groups == 3 and kq.returned_groups == 1 and kq.suppressed_groups == 2

  # Full query matches rebuild identically
  assert query_matview(s4, "spend_by_dept", None) is Ok(q_inc)
  assert rebuild_matview(s4, "spend_by_dept") is Ok((s5, rep_reb))
  assert rep_reb.strategy == "rebuild"
  assert query_matview(s5, "spend_by_dept", None) is Ok(q_reb)
  assert q_inc.rows == q_reb.rows

  # Crash recovery simulation: stale pin behind meta triggers safe rebuild fallback
  assert Modb.unpin_root(s5, "mv:spend_by_dept") is Ok(s6)
  assert refresh_matview(s6, "spend_by_dept") is Ok((s7, rep_rec))
  assert rep_rec.strategy == "rebuild"
  assert get_matview(s7, "spend_by_dept") is Ok(Some(m_rec)) and m_rec.pin_aligned?

  # Drop clears meta + pin + rows
  assert drop_matview(s7, "spend_by_dept") is Ok(s8)
  assert list_matviews(s8) is Ok([])
  assert Modb.get_pin(s8, "mv:spend_by_dept") is Ok(None)
end
