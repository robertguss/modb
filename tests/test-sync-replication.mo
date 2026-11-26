## MoDB Milestone 16 (`v0.8.0`) Comprehensive Verification Suite (`Modb.Sync`):
## 1. 5-delta incremental replication parity + secondary indexes + `Modb.verify`
## 2. Multi-tx `Ledger` + `include_internal: true` batched replication + `Ledger.verify_all`
## 3. Retry idempotency & concurrent writes between `export_delta` and `ack_peer`
## 4. `from_empty?: true` full database bootstrap purely from deltas
## 5. Encrypted `seal_snapshot` + `seal_delta` + `restore_sealed_chain` + all negative controls
module TestSyncReplication
use Crypto
use Json
use Modb
use Modb.Export
use Modb.Ledger
use Modb.Sync
use Modb.Table

struct OrderRow
  buyer_id: Int
  total_cents: Int
  status: Text
end

fn order_buyer_idx() : Table.Index(Int, OrderRow, Int)
  Table.int_index[Int, OrderRow]("ord_by_buyer", fn(o) o.buyer_id end)
end

fn orders_table() : Table.Table(Int, OrderRow)
  Table.int_key[OrderRow]("orders").with_index(order_buyer_idx())
end

fn kv_table() : Table.Table(Text, Json)
  Table.text_key[Json]("kv")
end

fn assert_user_buckets_equal(a: Modb.Store, b: Modb.Store) : Unit
  assert Modb.buckets(a) is Ok(ab_raw)
  assert Modb.buckets(b) is Ok(bb_raw)
  ab = ab_raw.filter(fn(n) not n.starts_with?("_modb_") end)
  bb = bb_raw.filter(fn(n) not n.starts_with?("_modb_") end)
  assert ab == bb
  for bname in ab
    assert Modb.scan(a, bname, None, None, 0) is Ok(rows_a)
    assert Modb.scan(b, bname, None, None, 0) is Ok(rows_b)
    assert rows_a == rows_b
  end
  Unit
end

test "1. 5-delta incremental replication parity with typed tables, secondary indexes, and Modb.verify"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T10:00:00Z") or stop "t0"
  ords = orders_table()
  kvs = kv_table()

  assert Modb.open(files, "p1.modb") is Ok(s0)
  var primary = s0

  ## Seed initial state before registering sync peer
  tx_seed = Modb.begin_write(primary)
  assert Table.put(
    tx_seed,
    ords,
    1,
    OrderRow(buyer_id: 10, total_cents: 1200, status: "open")
  ) is Ok(tx_s1)
  assert Table.put(tx_s1, kvs, "cfg:mode", Json.String("prod")) is Ok(tx_s2)
  assert Modb.commit(tx_s2) is Ok(p_init)
  primary = p_init

  assert Sync.init_peer(primary, "mirror-a", false, false, t0) is Ok((p_peer, _))
  primary = p_peer
  assert Sync.export_peer_base_snapshot(primary, "mirror-a", t0) is Ok(base_snap)

  assert Export.import_file(files, "rep-a.modb", base_snap) is Ok(r0)
  var replica = r0
  var deltas = []

  ## 5 delta rounds mixing puts, overwrites, buyer re-indexing, and deletes
  for round in 1..6
    tx = Modb.begin_write(primary)
    oid_a = round * 10 + 1
    oid_b = round * 10 + 2
    assert Table.put(
      tx,
      ords,
      oid_a,
      OrderRow(buyer_id: round, total_cents: round * 500, status: "open")
    ) is Ok(t1)
    assert Table.put(
      t1,
      ords,
      oid_b,
      OrderRow(buyer_id: round + 100, total_cents: round * 900, status: "paid")
    ) is Ok(t2)
    assert Table.put(t2, kvs, "round:#{round}", Json.int(round)) is Ok(t3)
    var t4 = t3
    if round >= 2
      ## Re-index order 1 to a new buyer and delete previous round's second order
      assert Table.put(
        t4,
        ords,
        1,
        OrderRow(buyer_id: 20 + round, total_cents: 1200 + round, status: "shipped")
      ) is Ok(t4b)
      assert Table.delete(t4b, ords, (round - 1) * 10 + 2) is Ok(t4c)
      t4 = t4c
    end
    assert Modb.commit(t4) is Ok(p_next)
    primary = p_next

    t_delta = t0 + (round * 10).seconds
    assert Sync.export_delta(primary, "mirror-a", t_delta) is Ok((p_exp, d))
    assert d.seq == round
    assert Sync.ack_peer(p_exp, "mirror-a", d.seq, d.delta_hash, t_delta) is Ok((p_ack, _))
    primary = p_ack
    deltas = deltas.append(d)

    assert Sync.apply_delta_tracked(replica, d, t_delta) is Ok((r_next, _))
    replica = r_next
  end

  assert Modb.verify(primary) is Ok(_)
  assert Modb.verify(replica) is Ok(_)
  assert_user_buckets_equal(primary, replica)

  ## Also verify secondary index query parity directly on replica
  assert Table.lookup(replica, ords, order_buyer_idx(), 25) is Ok(found_reindexed)
  assert found_reindexed.size == 1

  ## Cold rebuild via restore_chain produces identical database
  assert Sync.restore_chain(files, "rebuilt-a.modb", base_snap, deltas) is Ok(rrep)
  assert rrep.deltas_applied == 5
  assert Modb.open_read_only(files.read_only, "rebuilt-a.modb") is Ok(rebuilt)
  assert Modb.verify(rebuilt) is Ok(_)
  assert_user_buckets_equal(primary, rebuilt)
end

test "2. Multi-tx Ledger + include_internal replication passes Ledger.verify_all on restored replica"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T11:00:00Z") or stop "t0"
  ords = orders_table()
  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "v1 schema", fn(tx) Ok(tx) end)
  ).with_invariant(
    Ledger.row_invariant(
      "positive_order_total",
      ords,
      fn(oid, o) if o.total_cents <= 0: Some("bad total on ##{oid}") else: None end
    )
  )

  assert Ledger.open(files, "ledger-src.modb", sc, t0) is Ok(db0)
  meta = Ledger.WriteMeta(principal: "ops:bot", action: "order_create", reason: "init", at: t0)
  assert Ledger.write(
    db0,
    meta,
    "seed order 1",
    Json.int(1),
    fn(tx) Table.put(tx, ords, 1, OrderRow(buyer_id: 7, total_cents: 2500, status: "open")) end
  ) is Ok(db1)

  ## Register include_internal peer via Sync.init_peer and reload Ledger handle
  assert Sync.init_peer(Ledger.store(db1), "ledger-dr", true, false, t0) is Ok((st_p, _))
  db2 = Ledger.update_store(db1, st_p)
  assert Sync.export_peer_base_snapshot(Ledger.store(db2), "ledger-dr", t0) is Ok(base_snap)

  ## Run 6 separate Ledger writes + checkpoint (primary txid advances by 7 while delta count = 1)
  var cur_db = db2
  for i in 2..8
    assert Ledger.write(
      cur_db,
      Ledger.WriteMeta(principal: "ops:bot", action: "order_create", reason: "batch #{i}", at: t0),
      "order ##{i}",
      Json.int(i),
      fn(tx)
        Table.put(tx, ords, i, OrderRow(buyer_id: i, total_cents: i * 100, status: "paid"))
      end
    ) is Ok(next_db)
    cur_db = next_db
  end
  assert Ledger.record_verify_checkpoint(cur_db, t0) is Ok((cur_db2, _cp))

  assert Sync.export_delta(Ledger.store(cur_db2), "ledger-dr", t0) is Ok((st_exp, delta_batch))
  assert Sync.ack_peer(st_exp, "ledger-dr", delta_batch.seq, delta_batch.delta_hash, t0) is Ok(_)
  assert delta_batch.target_txid - delta_batch.from_txid >= 7

  ## Restore snapshot + single batched delta and verify full Ledger audit chain & checkpoint invariants
  assert Sync.restore_chain(files, "ledger-dr.modb", base_snap, [delta_batch]) is Ok(rrep)
  assert rrep.final_txid >= delta_batch.target_txid
  assert Ledger.open(files, "ledger-dr.modb", sc, t0) is Ok(dr_db)
  assert Ledger.verify_all(dr_db) is Ok(full_rep)
  assert full_rep.audit.entry_count == Ledger.audit_count(cur_db2)
  assert_user_buckets_equal(Ledger.store(cur_db2), Ledger.store(dr_db))
end

test "3. Retry idempotency & concurrent write between export_delta and ack_peer"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T12:00:00Z") or stop "t0"

  assert Modb.open(files, "conc.modb") is Ok(s0)
  assert Sync.init_peer(s0, "worker-sync", false, false, t0) is Ok((s1, _))

  ## Write k1 and export d1_first, then write k2 before ack (retry supersedes without advancing acked)
  tx1 = Modb.begin_write(s1)
  assert Modb.tx_put(tx1, "items", "k1".bytes, "v1".bytes) is Ok(tx1b)
  assert Modb.commit(tx1b) is Ok(s2)

  assert Sync.export_delta(s2, "worker-sync", t0) is Ok((s3, d1_first))
  assert d1_first.seq == 1
  assert d1_first.op_count == 1

  tx2 = Modb.begin_write(s3)
  assert Modb.tx_put(tx2, "items", "k2".bytes, "v2".bytes) is Ok(tx2b)
  assert Modb.commit(tx2b) is Ok(s4)

  assert Sync.export_delta(s4, "worker-sync", t0) is Ok((s5, d1_retry))
  assert d1_retry.seq == 1
  assert d1_retry.prev_hash == Sync.genesis_hash
  assert d1_retry.op_count == 2

  ## Concurrent write k3 committed AFTER export d1_retry and BEFORE ack_peer!
  tx3 = Modb.begin_write(s5)
  assert Modb.tx_put(tx3, "items", "k3".bytes, "v3".bytes) is Ok(tx3b)
  assert Modb.commit(tx3b) is Ok(s6)

  ## Ack d1_retry: pin must freeze at s5's root, NOT s6's root!
  assert Sync.ack_peer(s6, "worker-sync", d1_retry.seq, d1_retry.delta_hash, t0) is Ok((s7, p1))
  assert p1.acked_seq == 1

  ## Next export captures ONLY k3 with prev_hash == d1_retry.delta_hash
  assert Sync.export_delta(s7, "worker-sync", t0) is Ok((s8, d2))
  assert d2.seq == 2
  assert d2.prev_hash == d1_retry.delta_hash
  assert d2.op_count == 1
  assert Sync.ack_peer(s8, "worker-sync", d2.seq, d2.delta_hash, t0) is Ok(_)

  ## Replicate d1_retry + d2 onto fresh empty store -> must have k1, k2, k3
  assert Modb.open(files, "conc-rep.modb") is Ok(r0)
  assert Sync.apply_delta_tracked(r0, d1_retry, t0) is Ok((r1, _))
  assert Sync.apply_delta_tracked(r1, d2, t0) is Ok((r2, _))
  assert Modb.get(r2, "items", "k1".bytes) == Ok(Some("v1".bytes))
  assert Modb.get(r2, "items", "k2".bytes) == Ok(Some("v2".bytes))
  assert Modb.get(r2, "items", "k3".bytes) == Ok(Some("v3".bytes))
end

test "4. from_empty bootstrap replicates pre-existing data purely from deltas"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T13:00:00Z") or stop "t0"

  assert Modb.open(files, "full.modb") is Ok(s0)
  tx0 = Modb.begin_write(s0)
  assert Modb.tx_put(tx0, "notes", "a".bytes, "alpha".bytes) is Ok(tx1)
  assert Modb.tx_put(tx1, "notes", "b".bytes, "beta".bytes) is Ok(tx2)
  assert Modb.commit(tx2) is Ok(s1)

  assert Sync.init_peer(s1, "cold", false, true, t0) is Ok((s2, _))
  assert Sync.export_peer_base_snapshot(s2, "cold", t0) is Ok(empty_snap)
  assert empty_snap.bucket_count == 0
  assert Sync.export_delta(s2, "cold", t0) is Ok((_, d1))
  assert d1.op_count == 2

  assert Sync.restore_chain(files, "cold-rebuilt.modb", empty_snap, [d1]) is Ok(rep)
  assert rep.puts_applied == 2
  assert Modb.open_read_only(files.read_only, "cold-rebuilt.modb") is Ok(rebuilt)
  assert Modb.get(rebuilt, "notes", "a".bytes) == Ok(Some("alpha".bytes))
  assert Modb.get(rebuilt, "notes", "b".bytes) == Ok(Some("beta".bytes))
  assert Modb.verify(rebuilt) is Ok(_)
end

fn flip_one_base64_char(s: Text) : Text
  cs = s.chars
  mid = cs.size / 2
  orig = cs.get(mid) or 'A'
  repl = if orig == 'A': 'B' else: 'A'
  Text.from_chars(cs.take(mid).append(repl).concat(cs.drop(mid + 1)))
end

test "5. Encrypted restore_sealed_chain & negative controls (tamper, wrong key, AAD, bad key len, seq gap, replay, forged hashes)"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T14:00:00Z") or stop "t0"
  srng = SecureRandom.seeded(777)
  good_key = Crypto.sha256("primary-backup-key".bytes)
  wrong_key = Crypto.sha256("wrong-backup-key".bytes)
  short_key = "too-short-16-byt".bytes

  assert Modb.open(files, "enc-src.modb") is Ok(s0)
  tx0 = Modb.begin_write(s0)
  assert Modb.tx_put(tx0, "secrets_meta", "s1".bytes, "ok".bytes) is Ok(tx0b)
  assert Modb.commit(tx0b) is Ok(s1)

  assert Sync.init_peer(s1, "offhost", false, false, t0) is Ok((s2, _))
  assert Sync.export_peer_base_snapshot(s2, "offhost", t0) is Ok(snap)

  tx1 = Modb.begin_write(s2)
  assert Modb.tx_put(tx1, "secrets_meta", "s2".bytes, "ok2".bytes) is Ok(tx1b)
  assert Modb.commit(tx1b) is Ok(s3)
  assert Sync.export_delta(s3, "offhost", t0) is Ok((s4, d1))
  assert Sync.ack_peer(s4, "offhost", d1.seq, d1.delta_hash, t0) is Ok((s5, _))

  tx2 = Modb.begin_write(s5)
  assert Modb.tx_put(tx2, "secrets_meta", "s3".bytes, "ok3".bytes) is Ok(tx2b)
  assert Modb.commit(tx2b) is Ok(s6)
  assert Sync.export_delta(s6, "offhost", t0) is Ok((s7, d2))
  assert Sync.ack_peer(s7, "offhost", d2.seq, d2.delta_hash, t0) is Ok((s8, _))

  assert Sync.seal_snapshot(srng, good_key, "k-main", "host:prod", snap, t0) is Ok(esnap)
  assert Sync.seal_delta(srng, good_key, "k-main", "host:prod", d1, t0) is Ok(ed1)
  assert Sync.seal_delta(srng, good_key, "k-main", "host:prod", d2, t0) is Ok(ed2)

  ## Happy path encrypted chain restore
  assert Sync.restore_sealed_chain(
    files,
    "enc-restored.modb",
    esnap,
    [ed1, ed2],
    good_key,
    "host:prod"
  ) is Ok(rep)
  assert rep.deltas_applied == 2
  assert Modb.open_read_only(files.read_only, "enc-restored.modb") is Ok(restored)
  assert Modb.get(restored, "secrets_meta", "s3".bytes) == Ok(Some("ok3".bytes))
  assert Modb.verify(restored) is Ok(_)
  assert_user_buckets_equal(s8, restored)

  ## Negative control A: 1-character tamper in ciphertext fails authentication
  var tampered_ed1 = ed1
  tampered_ed1.ciphertext_b64 = flip_one_base64_char(ed1.ciphertext_b64)
  assert Sync.open_delta(good_key, "host:prod", tampered_ed1) is Error(Sync.DecryptionFailed)

  ## Negative control B: wrong 32-byte key
  assert Sync.restore_sealed_chain(
    files,
    "fail-wrong-key.modb",
    esnap,
    [ed1],
    wrong_key,
    "host:prod"
  ) is Error(Sync.DecryptionFailed)

  ## Negative control C: wrong AAD
  assert Sync.open_delta(good_key, "host:wrong", ed1) is Error(Sync.DecryptionFailed)

  ## Negative control D: bad key length (16 bytes)
  assert Sync.seal_delta(srng, short_key, "k", "aad", d1, t0) is Error(
    Sync.InvalidKeyLength(expected: 32, got: 16)
  )
  assert Sync.open_delta(short_key, "host:prod", ed1) is Error(
    Sync.InvalidKeyLength(expected: 32, got: 16)
  )

  ## Negative control E: sequence gap on tracked replica
  assert Modb.open(files, "gap-rep.modb") is Ok(gr0)
  assert Sync.apply_delta_tracked(gr0, d2, t0) is Error(
    Sync.ChainMismatch(expected_seq: 1, actual_seq: 2, expected_prev_hash: _, actual_prev_hash: _)
  )

  ## Negative control F: duplicate replay on tracked replica
  assert Sync.apply_delta_tracked(gr0, d1, t0) is Ok((gr1, _))
  assert Sync.apply_delta_tracked(gr1, d1, t0) is Error(
    Sync.ChainMismatch(expected_seq: 2, actual_seq: 1, expected_prev_hash: _, actual_prev_hash: _)
  )

  ## Negative control G: forged payload_hash & forged delta_hash
  var forged_payload = d1
  forged_payload.payload_hash = "deadbeef"
  assert Sync.verify_delta(forged_payload) is Error(Sync.InvalidDelta(reason: _))

  var forged_delta = d1
  forged_delta.delta_hash = "deadbeef"
  assert Sync.verify_delta(forged_delta) is Error(Sync.InvalidDelta(reason: _))
end

test "Sync keyring rotation restores mixed-generation sealed chains across key_ids"
  files = Files.in_memory({})
  srng = SecureRandom.seeded(77)
  t0 = Time.parse("2026-11-26T23:00:00Z") or stop "time"
  assert Modb.open(files, "rot-src.modb") is Ok(db0)
  tx0 = Modb.begin_write(db0)
  assert Modb.tx_put(tx0, "cfg", "k0".bytes, "v0".bytes) is Ok(tx0b)
  assert Modb.commit(tx0b) is Ok(db1)

  assert Sync.init_peer(db1, "rot-peer", true, false, t0) is Ok((s2, _))
  assert Sync.export_peer_base_snapshot(s2, "rot-peer", t0) is Ok(base_snap)
  assert Bytes.from_hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20") is
    Some(k1)
  assert Bytes.from_hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") is
    Some(k2)
  assert Sync.seal_snapshot(srng, k1, "rot-v1", "host:rot", base_snap, t0) is Ok(esnap)

  tx1 = Modb.begin_write(s2)
  assert Modb.tx_put(tx1, "cfg", "k1".bytes, "v1".bytes) is Ok(tx1b)
  assert Modb.commit(tx1b) is Ok(s3)
  assert Sync.export_delta(s3, "rot-peer", t0) is Ok((s4, d1))
  assert Sync.ack_peer(s4, "rot-peer", d1.seq, d1.delta_hash, t0) is Ok((s5, _))
  assert Sync.seal_delta(srng, k1, "rot-v1", "host:rot", d1, t0) is Ok(ed1)

  ## Rotate active sealing key to rot-v2 / k2
  tx2 = Modb.begin_write(s5)
  assert Modb.tx_put(tx2, "cfg", "k2".bytes, "v2".bytes) is Ok(tx2b)
  assert Modb.commit(tx2b) is Ok(s6)
  assert Sync.export_delta(s6, "rot-peer", t0) is Ok((_s7, d2))
  assert Sync.seal_delta(srng, k2, "rot-v2", "host:rot", d2, t0) is Ok(ed2)

  csv_kr = "rot-v1=0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20,rot-v2=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  json_kr = "{\"rot-v1\":\"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20\",\"rot-v2\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}"
  assert Sync.parse_keyring_text(csv_kr) is Ok(kr_csv)
  assert Sync.parse_keyring_text(json_kr) is Ok(kr_json)
  assert kr_csv == kr_json
  assert Sync.parse_keyring_text("missing_equals") is Error(Sync.InvalidEnvelope(reason: _))

  ## Single wrong/incomplete key fails, while full keyring restores both generations cleanly
  assert Sync.restore_sealed_chain(files, "rot-single-fail.modb", esnap, [ed1, ed2], k1, "host:rot") is
    Error(Sync.DecryptionFailed)
  assert Sync.restore_sealed_chain_with_keyring(
    files,
    "rot-missing-id.modb",
    esnap,
    [ed1, ed2],
    {"rot-v1": k1},
    "host:rot"
  ) is
    Error(Sync.KeyNotFound(key_id: "rot-v2"))
  assert Sync.restore_sealed_chain_with_keyring(
    files,
    "rot-ok.modb",
    esnap,
    [ed1, ed2],
    kr_json,
    "host:rot"
  ) is
    Ok(rep)
  assert rep.deltas_applied == 2
  assert Modb.open_read_only(files.read_only, "rot-ok.modb") is Ok(restored)
  assert Modb.verify(restored) is Ok(_)
  assert Modb.get(restored, "cfg", "k0".bytes) == Ok(Some("v0".bytes))
  assert Modb.get(restored, "cfg", "k1".bytes) == Ok(Some("v1".bytes))
  assert Modb.get(restored, "cfg", "k2".bytes) == Ok(Some("v2".bytes))
end
