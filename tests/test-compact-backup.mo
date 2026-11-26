## Milestone 9 Verification Suite:
## - Test 1: Online `Export.backup_db` snapshot (refuses overwrite, passes full `verify_all`,
##           supports `include_internal: true` and `false`).
## - Test 2: `Export.compact_db` with `include_internal: true` (audit preserved) and `false`
##           (bloat stripped + fresh `VerifyCheckpoint` + non-idempotent v1 seed migration safe).
## - Test 3: `Replay.compact_with_baseline` with `after_import` Grant hook, post-compaction
##           calls, O(diff) delta replay (`ExcludePrincipal`), and `accept_proposal`.
## - Test 4: Atomic rollback on `after_import` hook error leaves original DB untouched & clean.
module TestCompactBackup
use Json
use Modb.Export
use Modb.Grants
use Modb.Ledger{Schema, WriteMeta}
use Modb.Replay{ReplayCatalog}
use Modb.Table

struct ItemRow
  label: Text
  qty: Int
end

struct PutItemArgs
  id: Int
  label: Text
  qty: Int
end

fn items_table() : Table.Table(Int, ItemRow)
  Table.int_key[ItemRow]("items")
end

fn app_schema() : Schema
  tbl = items_table()
  Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(
      1,
      "seed initial item 1",
      fn(tx) Table.put(tx, tbl, 1, ItemRow(label: "seed-v1", qty: 100)) end
    )
  ).with_invariant(
    Ledger.row_invariant(
      "qty_non_negative",
      tbl,
      fn(id, r) if r.qty < 0: Some("item ##{id} qty < 0") else: None end
    )
  )
end

fn app_replay_catalog() : ReplayCatalog
  tbl = items_table()
  Replay.catalog().with_action(
    "put_item",
    fn(tx, args)
      a = try Json.decode[PutItemArgs](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      if a.qty < 0
        return Error("negative qty rejected: #{a.qty}")
      end
      row = ItemRow(label: a.label, qty: a.qty)
      t1 = try Table.put(tx, tbl, a.id, row).map_error(fn(e) e.to_text end)
      Ok((t1, row.to_json))
    end
  ).with_action(
    "del_item",
    fn(tx, args)
      id = try args.int_at("id").or_fail("missing id")
      t1 = try Table.delete(tx, tbl, id).map_error(fn(e) e.to_text end)
      Ok((t1, Json.Object({"deleted": Json.int(id)})))
    end
  )
end

test "1. Export.backup_db creates consistent verified online snapshots and refuses overwrite"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T00:00:00Z") or stop "t0"
  sc = app_schema()
  tbl = items_table()

  assert Ledger.open(files, "live.modb", sc, t0) is Ok(db0)
  meta = WriteMeta(principal: "admin:ada", action: "put_item", reason: "populate", at: t0)
  var db = db0
  ## Update seeded row #1 so we prove migration 1 never clobbers live updates!
  assert Ledger.write(
    db,
    meta,
    "update item 1",
    1.to_json,
    fn(tx) Table.put(tx, tbl, 1, ItemRow(label: "live-updated", qty: 55)) end
  ) is
    Ok(db1)
  db = db1
  for i in 2..40
    assert Ledger.write(
      db,
      meta,
      "add #{i}",
      i.to_json,
      fn(tx) Table.put(tx, tbl, i, ItemRow(label: "item-#{i}", qty: i)) end
    ) is
      Ok(next)
    db = next
  end

  ## Full online backup with audit ledger included
  assert Export.backup_db(files.read_only, "live.modb", files, "bak-full.modb", sc, true, t0) is
    Ok(brep)
  assert brep.include_internal
  assert brep.free_page_count == 0
  assert Ledger.open_read_only(files.read_only, "bak-full.modb", sc) is Ok(bak_db)
  assert Ledger.audit_count(bak_db) == Ledger.audit_count(db)
  assert Table.get(Ledger.store(bak_db), tbl, 1) == Ok(Some(ItemRow(label: "live-updated", qty: 55)))
  assert Table.count(Ledger.store(bak_db), tbl) == Ok(39)
  assert Ledger.verify_all(bak_db) is Ok(_)

  ## Clean data-only online backup preserves updated item 1 without re-running seed migration
  assert Export.backup_db(files.read_only, "live.modb", files, "bak-clean.modb", sc, false, t0) is
    Ok(crep)
  assert not crep.include_internal
  assert crep.free_page_count == 0
  assert Ledger.open_read_only(files.read_only, "bak-clean.modb", sc) is Ok(clean_db)
  assert Ledger.audit_count(clean_db) == 0
  assert Table.get(Ledger.store(clean_db), tbl, 1) == Ok(Some(ItemRow(label: "live-updated", qty: 55)))
  assert Table.count(Ledger.store(clean_db), tbl) == Ok(39)
  assert Ledger.verify_all(clean_db) is Ok(_)

  ## Overwrite guard
  assert Export.backup_db(files.read_only, "live.modb", files, "bak-clean.modb", sc, true, t0) is
    Error(Export.TargetNotEmpty(path: "bak-clean.modb"))
end

test "2. Export.compact_db reclaims pages in both audit-preserving and clean modes"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T00:05:00Z") or stop "t0"
  sc = app_schema()
  tbl = items_table()
  rc = app_replay_catalog()

  assert Ledger.open(files, "frag.modb", sc, t0) is Ok(db0)
  var db = db0
  meta = WriteMeta(principal: "admin:ada", action: "put_item", reason: "bloat", at: t0)
  del_meta = WriteMeta(principal: "admin:ada", action: "del_item", reason: "prune", at: t0)

  ## Update item 1 + insert 120 heavy rows then delete 100 of them to bloat pages & internal logs
  assert Replay.execute(db, rc, meta, PutItemArgs(id: 1, label: "kept-updated", qty: 77).to_json) is
    Ok((db1, _, _))
  db = db1
  for i in 2..120
    assert Replay.execute(
      db,
      rc,
      meta,
      PutItemArgs(id: i, label: "heavy-row-#{i}-padding-for-b-tree-pages", qty: i).to_json
    ) is
      Ok((next, _, _))
    db = next
  end
  for i in 20..120
    assert Replay.execute(db, rc, del_meta, Json.Object({"id": Json.int(i)})) is Ok((next, _, _))
    db = next
  end

  before_audit = Ledger.audit_count(db)
  assert before_audit > 200

  ## Compact preserving audit log
  assert Export.compact_db(files, "frag.modb", sc, true, true, t0) is Ok(r_full)
  assert r_full.include_internal
  assert r_full.checkpoint_recorded?
  assert not r_full.baseline_pinned?
  assert r_full.after_audit_entries == before_audit
  assert r_full.after_pages <= r_full.before_pages
  assert Ledger.open_read_only(files.read_only, "frag.modb", sc) is Ok(db_full)
  assert Table.get(Ledger.store(db_full), tbl, 1) == Ok(Some(ItemRow(label: "kept-updated", qty: 77)))
  assert Table.count(Ledger.store(db_full), tbl) == Ok(19)
  assert Ledger.verify_all(db_full) is Ok(_)
  assert Ledger.verify_fast(db_full, 16) is Ok(_)

  ## Compact stripping internal audit/replay bloat + verify updated seed 1 stayed intact
  assert Export.compact_db(files, "frag.modb", sc, false, true, t0) is Ok(r_clean)
  assert not r_clean.include_internal
  assert r_clean.checkpoint_recorded?
  assert r_clean.after_audit_entries == 0
  assert r_clean.after_pages < r_clean.before_pages
  assert Ledger.open_read_only(files.read_only, "frag.modb", sc) is Ok(db_clean)
  assert Table.get(Ledger.store(db_clean), tbl, 1) == Ok(Some(ItemRow(label: "kept-updated", qty: 77)))
  assert Table.count(Ledger.store(db_clean), tbl) == Ok(19)
  assert Ledger.verify_all(db_clean) is Ok(_)
  assert Ledger.verify_fast(db_clean, 16) is Ok(_)
end

test "3. Replay.compact_with_baseline preserves pre-compaction rows across post-compact O(diff) replay"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T00:10:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T12:00:00Z") or stop "t1"
  sc = app_schema()
  tbl = items_table()
  rc = app_replay_catalog()

  assert Ledger.open(files, "rb.modb", sc, t0) is Ok(db0)
  var db = db0
  meta = WriteMeta(principal: "admin:ada", action: "put_item", reason: "init", at: t0)
  del_meta = WriteMeta(principal: "admin:ada", action: "del_item", reason: "clean", at: t0)
  assert Replay.execute(db, rc, meta, PutItemArgs(id: 1, label: "base-one", qty: 42).to_json) is
    Ok((db1, _, _))
  db = db1
  for i in 2..60
    assert Replay.execute(db, rc, meta, PutItemArgs(id: i, label: "bulk-#{i}", qty: i).to_json) is
      Ok((next, _, _))
    db = next
  end
  for i in 10..60
    assert Replay.execute(db, rc, del_meta, Json.Object({"id": Json.int(i)})) is Ok((next, _, _))
    db = next
  end

  ## Compact via Replay.compact_with_baseline with an after_import hook provisioning a root grant
  hook_ran = fn(ldb)
    gm = WriteMeta(principal: "admin:ada", action: "issue", reason: "post-compact grant", at: t0)
    (ldb_g, _g) = try Grants.issue_root(
      ldb,
      gm,
      Grants.GrantSpec(
        id: "g-post",
        principal: "agent:helper",
        allowed_actions: ["put_item"],
        max_calls: 10,
        expires_at: t1
      )
    ).map_error(fn(e) Replay.GrantFailure(e) end)
    Ok(ldb_g)
  end

  assert Replay.compact_with_baseline(files, "rb.modb", sc, t0, hook_ran) is Ok(creport)
  assert creport.baseline_pinned?
  assert creport.checkpoint_recorded?
  assert creport.after_pages < creport.before_pages

  ## Open compacted DB, verify baseline + hook grant exist, then run post-compaction calls
  assert Ledger.open(files, "rb.modb", sc, t0) is Ok(db_c0)
  assert Replay.get_baseline(Ledger.store(db_c0)) is Ok(Some(bl))
  assert bl.schema_version == 1
  assert Grants.get(Ledger.store(db_c0), "g-post") is Ok(Some(_))
  assert Replay.call_count(Ledger.store(db_c0)) == Ok(0)

  m_rogue = WriteMeta(principal: "agent:rogue", action: "put_item", reason: "bad write", at: t0)
  m_good = WriteMeta(principal: "user:bob", action: "put_item", reason: "good write", at: t0)
  assert Replay.execute(db_c0, rc, m_rogue, PutItemArgs(id: 99, label: "rogue-junk", qty: 999).to_json) is
    Ok((db_c1, _, _))
  assert Replay.execute(db_c1, rc, m_good, PutItemArgs(id: 100, label: "good-item", qty: 12).to_json) is
    Ok((db_c2, _, _))

  ## Selective undo excludes rogue call 99 while preserving pre-compaction 1..9 and good post-compact 100!
  assert Replay.simulate_replay(
    db_c2,
    rc,
    Replay.ExcludePrincipal(principal: "agent:rogue"),
    "undo-rogue-post",
    "Remove agent:rogue after compaction",
    "admin:ada",
    t0
  ) is
    Ok((db_c3, prop))
  assert prop.proposed_delta is Some(ds) and not ds.empty?
  assert prop.summary.excluded == 1 and prop.summary.unchanged == 1

  acc_meta = WriteMeta(
    principal: "admin:ada",
    action: "accept_replay_proposal",
    reason: "clean rogue",
    at: t0
  )
  assert Replay.accept_proposal(db_c3, "undo-rogue-post", acc_meta) is Ok((db_c4, _))
  st4 = Ledger.store(db_c4)
  assert Table.get(st4, tbl, 1) == Ok(Some(ItemRow(label: "base-one", qty: 42)))
  assert Table.get(st4, tbl, 99) == Ok(None)
  assert Table.get(st4, tbl, 100) == Ok(Some(ItemRow(label: "good-item", qty: 12)))
  assert Ledger.verify_all(db_c4) is Ok(_)
end

test "4. Hook failure during compaction leaves original DB untouched and cleans staging temp file"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T00:15:00Z") or stop "t0"
  sc = app_schema()
  tbl = items_table()

  assert Ledger.open(files, "safe.modb", sc, t0) is Ok(db0)
  meta = WriteMeta(principal: "admin:ada", action: "put", reason: "seed", at: t0)
  assert Ledger.write(
    db0,
    meta,
    "put 2",
    2.to_json,
    fn(tx) Table.put(tx, tbl, 2, ItemRow(label: "intact", qty: 88)) end
  ) is
    Ok(_)

  res = Export.compact_db_with_hook(
    files,
    "safe.modb",
    sc,
    false,
    true,
    t0,
    fn(_ldb) Error(Export.PostImportFailed(detail: "simulated hook abort")) end
  )
  assert res is Error(Export.PostImportFailed(detail: "simulated hook abort"))
  assert not files.exists?("safe.modb.compact.tmp")

  assert Ledger.open_read_only(files.read_only, "safe.modb", sc) is Ok(after_db)
  assert Table.get(Ledger.store(after_db), tbl, 2) == Ok(Some(ItemRow(label: "intact", qty: 88)))
  assert Ledger.verify_all(after_db) is Ok(_)
end
