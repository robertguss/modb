## Milestone 3 Phase 3A Verification Suite:
## - Crash-safe persistent root pins across hundreds of commits, reopens, and 500 simulated power cuts
## - Full space reclamation on unpin (`Modb.verify` exact disjoint partition + pinned subtree validation)
## - O(diff) structural CoW B+Tree diff (`Modb.diff_roots`, `Table.diff_roots`, `Modb.diff_tx_from_root`)
##   verified against naive full-scan diffs plus subtree-skip proof
module TestPinsDiff
use Modb
use Modb.Errors{ModbError}
use Modb.Pager
use Modb.Table
use Modb.Tree{KeyDiff}

struct Item
  name: Text
  qty: Int
end

fn items_table() : Table.Table(Int, Item)
  Table.int_key[Item]("items")
end

fn naive_diff(before: Map(Bytes, Bytes), after: Map(Bytes, Bytes)) : List(KeyDiff)
  var keys_set = Set.empty
  for k in before.keys
    keys_set = keys_set.add(k)
  end
  for k in after.keys
    keys_set = keys_set.add(k)
  end
  ## Sort keys via insertion sort (test-only reference oracle)
  var sorted = []
  for k in keys_set
    var pos = 0
    while pos < sorted.size
      cur = sorted.get(pos) or stop "sort idx"
      break if k < cur
      pos += 1
    end
    sorted = sorted.take(pos).append(k).concat(sorted.drop(pos))
  end
  var out = []
  for k in sorted
    case (before.get(k), after.get(k))
      (None, Some(v)): out = out.append(Added(key: k, value: v))
      (Some(v), None): out = out.append(Removed(key: k, value: v))
      (Some(ov), Some(nv)):
        if ov != nv
          out = out.append(Modified(key: k, old_value: ov, new_value: nv))
        end
      (None, None): Unit
    end
  end
  out
end

test "1. Persistent root pins survive overwrites, deletes, reopens, and reclaim 100% on unpin"
  files = Files.in_memory({})
  assert Modb.open(files, "pins.modb") is Ok(db0)
  var db = db0

  ## Seed 80 rows including overflow values
  assert Modb.write_tx(
    db,
    fn(tx)
      var cur = tx
      for i in 0..80
        v = if i % 20 == 0
          Bytes.join([Bytes.from_u32_be(i), Bytes.zeroed(2500)])
        else
          "v0-#{i}".bytes
        end
        cur = try Modb.tx_put(cur, "kv", Bytes.from_u32_be(i), v)
      end
      Ok(cur)
    end
  ) is
    Ok(db1)
  db = db1

  ## Pin v0 persistently
  assert Modb.pin_root(db, "pin-v0") is Ok((db_p0, pin0))
  db = db_p0
  assert Modb.verify(db) is Ok(_)
  assert Modb.get_pin(db, "pin-v0") == Ok(Some(pin0))

  ## Duplicate pin id is refused; raw write to _modb_pins is refused
  assert Modb.pin_root(db, "pin-v0") is Error(InvalidArgument(reason: _))
  assert Modb.write_tx(db, fn(tx) Modb.tx_put(tx, Modb.pins_bucket, "bad".bytes, "x".bytes) end) is
    Error(InvalidArgument(reason: _))

  ## Overwrite and delete across 40 commits while pin-v0 stays active
  for step in 0..40
    assert Modb.write_tx(
      db,
      fn(tx)
        var cur = tx
        for j in 0..10
          idx = (step * 7 + j) % 80
          if j % 3 == 0
            cur = try Modb.tx_delete(cur, "kv", Bytes.from_u32_be(idx))
          else
            cur = try Modb.tx_put(cur, "kv", Bytes.from_u32_be(idx), "step-#{step}-#{idx}".bytes)
          end
        end
        Ok(cur)
      end
    ) is
      Ok(next_db)
    db = next_db
    if step == 19
      assert Modb.pin_root(db, "pin-v20") is Ok((db_p20, _p20))
      db = db_p20
    end
  end

  assert Modb.verify(db) is Ok(_)

  ## Reopen cold from storage and verify BOTH pins survive intact with exact historical values
  assert Modb.open(files, "pins.modb") is Ok(reopened)
  assert Modb.verify(reopened) is Ok(_)
  assert Modb.list_pins(reopened) is Ok(reopened_pins)
  assert reopened_pins.size == 2
  assert Modb.get_pin(reopened, "pin-v0") == Ok(Some(pin0))

  for i in 0..80
    expected = if i % 20 == 0
      Bytes.join([Bytes.from_u32_be(i), Bytes.zeroed(2500)])
    else
      "v0-#{i}".bytes
    end
    assert Modb.get_at_root(reopened, pin0.catalog_root, "kv", Bytes.from_u32_be(i)) ==
      Ok(Some(expected))
  end

  ## Read-only open via ReadFiles also sees persisted pins cleanly
  assert Modb.open_read_only(files.read_only, "pins.modb") is Ok(ro_db)
  assert Modb.verify(ro_db) is Ok(_)
  assert Modb.get_at_root(ro_db, pin0.catalog_root, "kv", Bytes.from_u32_be(0)) ==
    Ok(Some(Bytes.join([Bytes.from_u32_be(0), Bytes.zeroed(2500)])))

  ## Unpin oldest pin first (partial graduation), then second pin (full graduation), then prove reuse
  assert Modb.unpin_root(reopened, "pin-v0") is Ok(db_u1)
  assert Modb.verify(db_u1) is Ok(_)
  assert Modb.unpin_root(db_u1, "pin-v20") is Ok(db_u2)
  assert Modb.verify(db_u2) is Ok(_)
  assert Modb.list_pins(db_u2) == Ok([])

  pages_after_unpin = Modb.page_count(db_u2)
  var db_reuse = db_u2
  for round in 0..25
    assert Modb.write_tx(
      db_reuse,
      fn(tx) Modb.tx_put(tx, "kv", Bytes.from_u32_be(round % 20), "reused-#{round}".bytes) end
    ) is
      Ok(dn)
    db_reuse = dn
  end
  assert Modb.verify(db_reuse) is Ok(_)
  ## Reclaimed deferred pages prevent file growth during steady-state overwrites
  assert Modb.page_count(db_reuse) == pages_after_unpin
end

test "2. 500-crash deterministic torn-write simulation preserves active persistent pins"
  rng = Random.seeded(20261125)
  assert Modb.open_disk(Pager.sim_empty()) is Ok(db0)
  assert Modb.write_tx(
    db0,
    fn(tx)
      var cur = tx
      for i in 0..30
        cur = try Modb.tx_put(cur, "state", Bytes.from_u32_be(i), "init-#{i}".bytes)
      end
      Ok(cur)
    end
  ) is
    Ok(db1)
  assert Modb.pin_root(db1, "anchor") is Ok((db2, anchor))

  var db = db2
  var committed_step = 0
  var active_extra_pin = None

  for i in 0..500
    phase = if i % 2 == 0: 1 else: 2
    next_step = committed_step + 1
    var tx = Modb.begin_write(db)
    assert Modb.tx_put(tx, "state", Bytes.from_u32_be(i % 30), "step-#{next_step}".bytes) is Ok(t1)
    tx = t1
    ## Periodically pin and unpin a second rolling pin across crash boundaries
    if i % 40 == 10 and active_extra_pin is None
      assert Modb.tx_pin_base_root(tx, "rolling-#{i}") is Ok((t2, _p))
      tx = t2
    else if i % 40 == 30
      case active_extra_pin
        Some(pid_name):
          assert Modb.tx_unpin_root(tx, pid_name) is Ok(t2)
          tx = t2
        None: Unit
      end
    end

    assert Modb.commit_and_crash(tx, phase, rng) is Ok(crashed)
    assert Modb.open_disk(crashed) is Ok(rec)
    assert Modb.verify(rec) is Ok(_)

    ## Anchor pin MUST ALWAYS remain readable with exact initial values after every crash
    assert Modb.get_pin(rec, "anchor") == Ok(Some(anchor))
    assert Modb.get_at_root(rec, anchor.catalog_root, "state", Bytes.from_u32_be(i % 30)) ==
      Ok(Some("init-#{i % 30}".bytes))

    ## Sync tracked state with whichever side of the atomic commit survived
    if Modb.txid(rec) > Modb.txid(db)
      committed_step = next_step
      active_extra_pin = None
      assert Modb.list_pins(rec) is Ok(rec_pins)
      for p in rec_pins
        if p.id != "anchor"
          active_extra_pin = Some(p.id)
        end
      end
    end
    db = rec
  end

  assert committed_step > 50
end

test "3. Structural CoW diff matches naive oracle and skips untouched subtrees in O(diff)"
  files = Files.in_memory({})
  assert Modb.open(files, "diff.modb") is Ok(db0)
  tbl = items_table()

  ## Build a multi-level B+Tree with 600 items (~15+ leaf pages, branch root)
  assert Table.write_tx(
    db0,
    fn(tx)
      var cur = tx
      for i in 0..600
        cur = try Table.put(cur, tbl, i, Item(name: "item-#{i}", qty: i))
      end
      Ok(cur)
    end
  ) is
    Ok(db1)

  ## Snapshot baseline rows for naive oracle
  assert Modb.scan(db1, "items", None, None, 0) is Ok(base_rows)
  var base_map = {}
  for (k, v) in base_rows
    base_map = base_map.set(k, v)
  end

  assert Modb.pin_root(db1, "base") is Ok((db2, base_pin))

  ## Modify ONLY 1 key in a 600-row B+Tree -> diff must skip almost all subtrees!
  assert Table.write_tx(
    db2,
    fn(tx) Table.put(tx, tbl, 300, Item(name: "item-300-edited", qty: 999)) end
  ) is
    Ok(db3)

  assert Modb.diff_roots_with_stats(db3, base_pin.catalog_root, Modb.catalog_root(db3)) is
    Ok((bdiffs_1, stats_1))
  assert bdiffs_1.size == 2
  assert stats_1.subtrees_skipped > 5
  assert stats_1.pages_read < 20

  assert Table.diff_roots(db3, tbl, base_pin.catalog_root, Modb.catalog_root(db3)) ==
    Ok([
      Table.RowModified(
        key: 300,
        old_value: Item(name: "item-300", qty: 300),
        new_value: Item(name: "item-300-edited", qty: 999)
      )
    ])

  ## Now apply a heavy mix of inserts, updates, deletes (causing splits & merges) and compare vs naive oracle
  assert Table.write_tx(
    db3,
    fn(tx)
      var cur = tx
      for i in 10..45
        cur = try Table.delete(cur, tbl, i)
      end
      for i in 200..220
        cur = try Table.put(cur, tbl, i, Item(name: "updated-#{i}", qty: i * 2))
      end
      for i in 600..640
        cur = try Table.put(cur, tbl, i, Item(name: "new-#{i}", qty: i))
      end
      Ok(cur)
    end
  ) is
    Ok(db4)

  assert Modb.scan(db4, "items", None, None, 0) is Ok(after_rows)
  var after_map = {}
  for (k, v) in after_rows
    after_map = after_map.set(k, v)
  end

  assert Modb.diff_bucket_roots(db4, base_pin.catalog_root, Modb.catalog_root(db4), "items") is
    Ok(actual_diffs)
  expected_diffs = naive_diff(base_map, after_map)
  assert actual_diffs == expected_diffs

  ## Speculative WriteTx rooted at base_pin cannot be committed, but CAN be diffed cleanly
  spec0 = Modb.begin_write_from_root(db4, base_pin.catalog_root)
  assert Table.put(spec0, tbl, 777, Item(name: "speculative", qty: 1)) is Ok(spec1)
  assert Modb.commit(spec1) is Error(InvalidArgument(reason: _))
  assert Modb.diff_tx_from_root(spec1, base_pin.catalog_root) is Ok(spec_bdiffs)
  assert spec_bdiffs.size == 1
  first_bd = spec_bdiffs.first or stop "spec diff"
  assert first_bd.bucket == "items" and first_bd.changes.size == 1
end
