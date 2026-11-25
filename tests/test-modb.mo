## Comprehensive Layer 1 verification suite:
## - Gate 1: Differential correctness vs reference Map (1,200+ seeded ops across buckets,
##           overflows, snapshots, aborts, prefix/range scans)
## - Gate 2: Deterministic crash-fault simulation (500+ torn/dropped/reordered crashes + bit flips)
## - Freelist reclamation stability & boundary edge cases
module TestModb
use Modb
use Modb.Errors{ModbError}
use Modb.Pager{corrupt_byte, sim_empty}

fn make_value(rng: Random, step: Int) : Bytes
  kind = rng.int(0, 10)
  if kind == 0
    Bytes.empty
  else if kind <= 6
    "v-#{step}-#{rng.int(0, 100000)}".bytes
  else if kind == 7
    ## Exact inline boundary (1,024 bytes)
    Bytes.join([Bytes.from_u32_be(step), Bytes.zeroed(1020)])
  else if kind == 8
    ## Just above inline boundary (1,025 bytes -> 1 overflow page)
    Bytes.join([Bytes.from_u32_be(step), Bytes.zeroed(1021)])
  else
    ## Multi-page overflow (9,000 bytes -> 3 overflow pages)
    Bytes.join([Bytes.from_u32_be(step), Bytes.zeroed(8992), Bytes.from_u32_be(step)])
  end
end

fn bucket_name(idx: Int) : Text
  if idx == 0
    "alpha"
  else if idx == 1
    "beta"
  else
    "gamma"
  end
end

fn assert_bucket_matches(db: Modb.Store, bucket: Text, expected: Map(Bytes, Bytes))
  assert Modb.scan(db, bucket, None, None, 0) is Ok(rows)
  assert rows.size == expected.size
  for (k, v) in rows
    assert expected.get(k) == Some(v)
    assert Modb.get(db, bucket, k) == Ok(Some(v))
  end
end

fn assert_snapshot_matches(
  db: Modb.Store,
  snap: Modb.Snapshot,
  bucket: Text,
  expected: Map(Bytes, Bytes)
)
  assert Modb.snapshot_scan(db, snap, bucket, None, None, 0) is Ok(rows)
  assert rows.size == expected.size
  for (k, v) in rows
    assert expected.get(k) == Some(v)
    assert Modb.snapshot_get(db, snap, bucket, k) == Ok(Some(v))
  end
end

test "Gate 1: differential correctness over 1200 random ops, overflows, aborts and snapshots"
  rng = Random.seeded(20261123)
  files = Files.in_memory({})
  assert Modb.open(files, "diff.modb") is Ok(db0)
  var db = db0
  var ref_a = {}
  var ref_b = {}
  var ref_c = {}

  var pinned = []
  var pinned_refs = []

  for step in 0..400
    b_idx = rng.int(0, 3)
    bname = bucket_name(b_idx)
    op = rng.int(0, 20)

    if op == 0
      ## Rollback test: mutate several keys then abort; nothing should change.
      var tx = Modb.begin_write(db)
      assert Modb.tx_put(tx, bname, Bytes.from_u32_be(9999), "ghost".bytes) is Ok(t1)
      assert Modb.tx_delete(t1, bname, Bytes.from_u32_be(1)) is Ok(t2)
      db = Modb.rollback(t2)
    else if op == 1 and pinned.size < 4
      ## Take a snapshot pinning the current state of bucket alpha.
      (db_s, snap) = Modb.snapshot(db)
      db = db_s
      pinned = pinned.append(snap)
      pinned_refs = pinned_refs.append(ref_a)
    else if op == 2 and not pinned.empty?
      ## Verify oldest pinned snapshot, then release it.
      snap = pinned.first or stop "snap"
      expected_a = pinned_refs.first or stop "ref"
      assert_snapshot_matches(db, snap, "alpha", expected_a)
      assert Modb.release_snapshot(db, snap) is Ok(db_rel)
      db = db_rel
      pinned = pinned.drop(1)
      pinned_refs = pinned_refs.drop(1)
    else if op == 3
      ## Delete an entire bucket occasionally (only beta/gamma to keep alpha busy).
      if b_idx == 1
        assert Modb.write_tx(db, fn(tx) Modb.tx_delete_bucket(tx, "beta") end) is Ok(db_d)
        db = db_d
        ref_b = {}
      else if b_idx == 2
        assert Modb.write_tx(db, fn(tx) Modb.tx_delete_bucket(tx, "gamma") end) is Ok(db_d)
        db = db_d
        ref_c = {}
      end
    else
      ## Multi-operation atomic write_tx (3 ops per commit => ~1,200 ops total).
      var tx = Modb.begin_write(db)
      for sub in 0..3
        sb_idx = rng.int(0, 3)
        sb = bucket_name(sb_idx)
        key = Bytes.from_u32_be(rng.int(0, 120))
        if rng.int(0, 3) == 0
          assert Modb.tx_delete(tx, sb, key) is Ok(t_next)
          tx = t_next
          if sb_idx == 0
            ref_a = ref_a.remove(key)
          else if sb_idx == 1
            ref_b = ref_b.remove(key)
          else
            ref_c = ref_c.remove(key)
          end
        else
          val = make_value(rng, step * 10 + sub)
          assert Modb.tx_put(tx, sb, key, val) is Ok(t_next)
          tx = t_next
          if sb_idx == 0
            ref_a = ref_a.set(key, val)
          else if sb_idx == 1
            ref_b = ref_b.set(key, val)
          else
            ref_c = ref_c.set(key, val)
          end
        end
      end
      assert Modb.commit(tx) is Ok(db_c)
      db = db_c
    end

    if step % 40 == 0
      assert Modb.verify(db) is Ok(_)
      assert_bucket_matches(db, "alpha", ref_a)
    end
  end

  ## Verify all remaining snapshots, release them, then reopen from cold file.
  for i in 0..pinned.size
    snap = pinned.get(i) or stop "snap"
    expected_a = pinned_refs.get(i) or stop "ref"
    assert_snapshot_matches(db, snap, "alpha", expected_a)
    assert Modb.release_snapshot(db, snap) is Ok(db_rel)
    db = db_rel
  end

  assert Modb.verify(db) is Ok(_)
  assert Modb.open(files, "diff.modb") is Ok(cold)
  assert Modb.verify(cold) is Ok(_)
  assert_bucket_matches(cold, "alpha", ref_a)
  assert_bucket_matches(cold, "beta", ref_b)
  assert_bucket_matches(cold, "gamma", ref_c)
end

test "Gate 2: 500 deterministic crash-fault simulations (torn, dropped, reordered writes)"
  rng = Random.seeded(998877)
  assert Modb.open_disk(sim_empty()) is Ok(db0)
  var db = db0
  var committed = {}

  for trial in 0..250
    before_txid = Modb.txid(db)
    before_map = committed

    ## Build a multi-op write_tx (with inline & overflow values + deletes).
    var tx = Modb.begin_write(db)
    var candidate = before_map
    for j in 0..4
      k = Bytes.from_u32_be(rng.int(0, 80))
      if rng.int(0, 4) == 0
        assert Modb.tx_delete(tx, "data", k) is Ok(t1)
        tx = t1
        candidate = candidate.remove(k)
      else
        v = make_value(rng, trial * 10 + j)
        assert Modb.tx_put(tx, "data", k, v) is Ok(t1)
        tx = t1
        candidate = candidate.set(k, v)
      end
    end

    ## Phase 1 crash: power cut before data sync (meta-page untouched => MUST recover before_map).
    assert Modb.commit_and_crash(tx, 1, rng) is Ok(crashed1)
    assert Modb.open_disk(crashed1) is Ok(rec1)
    assert Modb.verify(rec1) is Ok(_)
    assert Modb.txid(rec1) == before_txid
    assert_bucket_matches(rec1, "data", before_map)

    ## Phase 2 crash: power cut after data sync, during meta-page write (torn/dropped/intact).
    ## Recovery MUST atomically land on either before_map or candidate, never partial.
    assert Modb.commit_and_crash(tx, 2, rng) is Ok(crashed2)
    assert Modb.open_disk(crashed2) is Ok(rec2)
    assert Modb.verify(rec2) is Ok(_)
    if Modb.txid(rec2) == before_txid
      assert_bucket_matches(rec2, "data", before_map)
      ## Commit cleanly now so state keeps advancing across trials.
      assert Modb.commit(tx) is Ok(db_ok)
      db = db_ok
      committed = candidate
    else
      assert Modb.txid(rec2) == before_txid + 1
      assert_bucket_matches(rec2, "data", candidate)
      db = rec2
      committed = candidate
    end
  end
end

test "Gate 2b: single-byte corruption detection and meta-page fallback"
  assert Modb.open_disk(sim_empty()) is Ok(db0)
  assert Modb.write_tx(db0, fn(tx) Modb.tx_put(tx, "k", "a".bytes, "v1".bytes) end) is Ok(db1)
  assert Modb.write_tx(db1, fn(tx) Modb.tx_put(tx, "k", "a".bytes, "v2".bytes) end) is Ok(db2)
  assert Modb.txid(db2) == 3

  ## Corrupt the active meta-page (slot 1 = txid 3): recovery must fall back cleanly to txid 2.
  assert corrupt_byte(db2.pager, 1, 20) is Ok(bad_meta_disk)
  assert Modb.open_disk(bad_meta_disk) is Ok(fallback)
  assert Modb.txid(fallback) == 2
  assert Modb.get(fallback, "k", "a".bytes) == Ok(Some("v1".bytes))
  assert Modb.verify(fallback) is Ok(_)

  ## Corrupt BOTH meta-pages: open must refuse with Corrupt.
  assert corrupt_byte(bad_meta_disk, 0, 20) is Ok(both_bad)
  assert Modb.open_disk(both_bad) is Error(Corrupt(reason: _))

  ## Corrupt a live B+Tree page: read & verify must refuse with Corrupt (never return bad data).
  assert corrupt_byte(db2.pager, db2.meta.catalog_root, 100) is Ok(bad_data_disk)
  assert Modb.open_disk(bad_data_disk) is Ok(opened_bad)
  assert Modb.get(opened_bad, "k", "a".bytes) is Error(Corrupt(reason: _))
  assert Modb.verify(opened_bad) is Error(Corrupt(reason: _))
end

test "Freelist reclamation bounds file growth and respects snapshot pins"
  files = Files.in_memory({})
  assert Modb.open(files, "reclaim.modb") is Ok(db0)
  var db = db0

  ## Seed 100 rows.
  var seed_tx = Modb.begin_write(db)
  for i in 0..100
    assert Modb.tx_put(seed_tx, "items", Bytes.from_u32_be(i), Bytes.zeroed(128)) is Ok(t1)
    seed_tx = t1
  end
  assert Modb.commit(seed_tx) is Ok(db1)
  db = db1

  ## Pin snapshot, do 30 single-key overwrites -> old pages must stay pinned.
  (db_s, snap) = Modb.snapshot(db)
  db = db_s
  for r in 0..30
    val = Bytes.join([Bytes.from_u32_be(r), Bytes.zeroed(124)])
    assert Modb.write_tx(db, fn(tx) Modb.tx_put(tx, "items", Bytes.from_u32_be(r % 100), val) end) is
      Ok(db_n)
    db = db_n
  end
  assert Modb.snapshot_get(db, snap, "items", Bytes.from_u32_be(0)) == Ok(Some(Bytes.zeroed(128)))
  assert Modb.release_snapshot(db, snap) is Ok(db_rel)
  db = db_rel

  ## After releasing snapshot, run 100 more overwrites: page_count must stabilize completely.
  pages_after_release = Modb.page_count(db)
  for r in 0..100
    val = Bytes.join([Bytes.from_u32_be(r + 1000), Bytes.zeroed(124)])
    assert Modb.write_tx(db, fn(tx) Modb.tx_put(tx, "items", Bytes.from_u32_be(r % 100), val) end) is
      Ok(db_n)
    db = db_n
  end
  assert Modb.page_count(db) <= pages_after_release + 4
  assert Modb.verify(db) is Ok(_)
end

test "Key/value boundary cases, prefix scans and validation"
  assert Modb.open_disk(sim_empty()) is Ok(db0)
  var db = db0

  ## Empty key & empty value, max 512B key, rejected 513B key, overflow boundaries.
  max_key = Bytes.zeroed(512)
  too_big_key = Bytes.zeroed(513)
  assert Modb.write_tx(db, fn(tx) Modb.tx_put(tx, "b", too_big_key, "x".bytes) end) is
    Error(KeyTooLarge(size: 513, max: 512))
  assert Modb.get(db, "", "x".bytes) is Error(InvalidArgument(reason: _))

  var tx = Modb.begin_write(db)
  assert Modb.tx_put(tx, "edge", Bytes.empty, Bytes.empty) is Ok(t1)
  assert Modb.tx_put(t1, "edge", max_key, Bytes.zeroed(4036)) is Ok(t2)
  assert Modb.tx_put(t2, "edge", "pre:a".bytes, Bytes.zeroed(4037)) is Ok(t3)
  assert Modb.tx_put(t3, "edge", "pre:b".bytes, Bytes.zeroed(8072)) is Ok(t4)
  assert Modb.tx_put(t4, "edge", "pre:c".bytes, Bytes.zeroed(8073)) is Ok(t5)
  assert Modb.tx_put(t5, "edge", Bytes.from_list([255, 255, 1]), "hi1".bytes) is Ok(t6)
  assert Modb.tx_put(t6, "edge", Bytes.from_list([255, 255, 2]), "hi2".bytes) is Ok(t7)
  assert Modb.commit(t7) is Ok(db1)
  db = db1

  assert Modb.get(db, "edge", Bytes.empty) == Ok(Some(Bytes.empty))
  assert Modb.get(db, "edge", max_key) == Ok(Some(Bytes.zeroed(4036)))
  assert Modb.get(db, "edge", "pre:a".bytes) == Ok(Some(Bytes.zeroed(4037)))
  assert Modb.get(db, "edge", "pre:b".bytes) == Ok(Some(Bytes.zeroed(8072)))
  assert Modb.get(db, "edge", "pre:c".bytes) == Ok(Some(Bytes.zeroed(8073)))

  assert Modb.prefix_scan(db, "edge", "pre:".bytes, 0) is Ok(pre_rows)
  assert pre_rows.size == 3
  assert Modb.prefix_scan(db, "edge", Bytes.from_list([255, 255]), 0) is Ok(ff_rows)
  assert ff_rows.size == 2
  assert Modb.verify(db) is Ok(_)
end
