## Milestone 4 comprehensive verification suite:
## 1. Portable Export/Import round-trip, tamper detection, compaction & pinned-root export.
## 2. Full Experiment 18 multi-version replay parity (v1 buggy -> v2 fixed -> v3 move_count)
##    against independent real Oracle databases + negative control ("newest code for all calls").
## 3. Multi-agent Grant subtree exclusion (`ExcludeGrant`), `ExcludeWorld`, `ExcludeSeqs`,
##    `StopBeforeSeq`, discard, and stale-proposal concurrency protection.
## 4. 500-crash deterministic torn-write simulation across `Replay.execute` and `accept_proposal`.
module TestReplayExport
use Json
use Modb
use Modb.Export
use Modb.Grants
use Modb.Ledger
use Modb.Pager
use Modb.Replay
use Modb.Table
use Modb.World

struct Cust
  email: Text
  name: Text
end

struct Ord
  buyer_id: Int
  amount: Int
end

fn cust_email_idx() : Table.Index(Int, Cust, Text)
  Table.unique_text_index[Int, Cust]("cust_by_email", fn(c) c.email end)
end

fn cust_tbl() : Table.Table(Int, Cust)
  Table.int_key[Cust]("customers").with_index(cust_email_idx())
end

fn ord_buyer_idx() : Table.Index(Int, Ord, Int)
  Table.int_index[Int, Ord]("ord_by_buyer", fn(o) o.buyer_id end)
end

fn ord_tbl() : Table.Table(Int, Ord)
  Table.int_key[Ord]("orders").with_index(ord_buyer_idx())
end

test "1. Portable Export/Import: 150 rows + indexes + grants + compaction + tamper detection + pinned root"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T14:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T15:00:00Z") or stop "t1"
  custs = cust_tbl()
  ords = ord_tbl()
  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "init empty v1", fn(tx) Ok(tx) end)
  ).with_invariant(
    Ledger.row_invariant(
      "positive_amount",
      ords,
      fn(oid, o) if o.amount <= 0: Some("order ##{oid} non-positive") else: None end
    )
  )

  assert Ledger.open(files, "port-src.modb", sc, t0) is Ok(db0)
  var db = db0
  meta = Ledger.WriteMeta(principal: "admin:ada", action: "seed", reason: "load", at: t0)

  ## Populate 30 customers and 120 orders across multiple commits
  for i in 1..31
    assert Ledger.write(
      db,
      meta,
      "cust #{i}",
      i.to_json,
      fn(tx) Table.put(tx, custs, i, Cust(email: "u#{i}@modb.dev", name: "User #{i}")) end
    ) is
      Ok(next)
    db = next
  end
  for j in 1..121
    buyer = (j % 30) + 1
    assert Ledger.write(
      db,
      meta,
      "ord #{j}",
      j.to_json,
      fn(tx) Table.put(tx, ords, j, Ord(buyer_id: buyer, amount: j * 10)) end
    ) is
      Ok(next)
    db = next
  end

  ## Issue a root grant and delegated helper grant
  assert Grants.issue_root(
    db,
    Ledger.WriteMeta(principal: "admin:ada", action: "issue", reason: "grant", at: t0),
    Grants.GrantSpec(
      id: "g-root",
      principal: "agent:lead",
      allowed_actions: ["place_order"],
      max_calls: 20,
      expires_at: t1
    )
  ) is
    Ok((db_g, _))
  db = db_g

  ## Pin historical midpoint root (120 orders), then delete 60 orders to induce freelist fragmentation
  assert Modb.pin_root(Ledger.store(db), "midpoint") is Ok((s_pin, pin))
  db = Ledger.update_store(db, s_pin)
  for j in 61..121
    assert Ledger.write(db, meta, "del ord #{j}", j.to_json, fn(tx) Table.delete(tx, ords, j) end) is
      Ok(next)
    db = next
  end

  ## Export full DB (with internal ledger + grants; layout-dependent _modb_pins excluded)
  assert Export.export_db(db, true, t0) is Ok(snap)
  assert snap.format_version == Export.export_format_version
  assert snap.source_txid == Ledger.txid(db)
  assert snap.schema_version == 1
  for b in snap.buckets
    assert b.name != Modb.pins_bucket
  end

  ## Strict JSON round-trip
  wire = Json.encode(snap)
  assert Json.decode_strict[Export.PortableSnapshot](wire) == Ok(snap)

  ## Tamper controls MUST fail verification:
  ## (a) Altered source_txid
  var bad_txid = snap
  bad_txid.source_txid += 1
  assert Export.verify_snapshot(bad_txid) is Error(Export.ChecksumMismatch(expected: _, actual: _))

  ## (b) Altered format_version
  var bad_ver = snap
  bad_ver.format_version = 99
  assert Export.verify_snapshot(bad_ver) is Error(Export.UnsupportedFormat(found: 99, supported: 1))

  ## (c) Single-char tamper in one entry's value_hex
  first_b = snap.buckets.first or stop "expected bucket"
  first_e = first_b.entries.first or stop "expected entry"
  var bad_entry = first_e
  bad_entry.value_hex = "#{first_e.value_hex}00"
  var bad_b = first_b
  bad_b.entries = [bad_entry].concat(first_b.entries.drop(1))
  var bad_val = snap
  bad_val.buckets = [bad_b].concat(snap.buckets.drop(1))
  assert Export.verify_snapshot(bad_val) is Error(Export.ChecksumMismatch(expected: _, actual: _))

  ## (d) Smuggled _modb_pins bucket with matching recomputed digest STILL rejected!
  pins_b = Export.PortableBucket(name: Modb.pins_bucket, entries: [])
  smug_buckets = snap.buckets.append(pins_b)
  smug_digest = Export.compute_snapshot_digest(
    snap.format_version,
    snap.source_txid,
    snap.schema_version,
    snap.include_internal,
    snap.exported_at,
    smug_buckets
  )
  smug = Export.PortableSnapshot(
    format_version: snap.format_version,
    source_txid: snap.source_txid,
    schema_version: snap.schema_version,
    include_internal: snap.include_internal,
    exported_at: snap.exported_at,
    bucket_count: smug_buckets.size,
    entry_count: snap.entry_count,
    buckets: smug_buckets,
    sha256: smug_digest
  )
  assert Export.verify_snapshot(smug) is
    Error(Export.InvalidEncoding(bucket: "_modb_pins", detail: _))

  ## Import into brand-new compacted file -> exact logical parity + full verify_all + zero fragmentation
  assert Export.import_db(files, "port-dst.modb", sc, snap, t0) is Ok(db_imp)
  assert Ledger.txid(db_imp) == Ledger.txid(db)
  assert Ledger.audit_count(db_imp) == Ledger.audit_count(db)
  assert Modb.free_page_count(Ledger.store(db_imp)) == 0
  assert Modb.page_count(Ledger.store(db_imp)) < Modb.page_count(Ledger.store(db))
  assert Table.all(Ledger.store(db_imp), custs) == Table.all(Ledger.store(db), custs)
  assert Table.all(Ledger.store(db_imp), ords) == Table.all(Ledger.store(db), ords)
  assert Table.lookup_unique(Ledger.store(db_imp), custs, cust_email_idx(), "u15@modb.dev") ==
    Ok(Some((15, Cust(email: "u15@modb.dev", name: "User 15"))))
  assert Table.lookup(Ledger.store(db_imp), ords, ord_buyer_idx(), 5) ==
    Table.lookup(Ledger.store(db), ords, ord_buyer_idx(), 5)
  assert Grants.get(Ledger.store(db_imp), "g-root") == Grants.get(Ledger.store(db), "g-root")
  assert Ledger.verify_all(db_imp) is Ok(_)

  ## Historical pinned-root export recovers all 120 orders before deletes!
  assert Export.export_at_root(Ledger.store(db), pin.catalog_root, pin.txid, false, t0) is
    Ok(hist_snap)
  assert Export.import_file(files, "port-hist.modb", hist_snap) is Ok(hist_store)
  assert Table.count(hist_store, ords) == Ok(120)
  assert Table.count(hist_store, custs) == Ok(30)
end

## Experiment 18 types: named tallies + move counter introduced at schema v3.
struct BookAdd
  name: Text
  n: Int
end

struct BookMove
  from: Text
  to: Text
  n: Int
end

struct StoryCall
  version: Int
  caller: Text
  action: Text
  args: Json
end

fn tallies_tbl() : Table.Table(Text, Int)
  Table.text_key[Int]("tallies")
end

fn stats_tbl() : Table.Table(Text, Int)
  Table.text_key[Int]("stats")
end

fn book_add_fn(tx: Modb.WriteTx, args: Json) : Result((Modb.WriteTx, Json), Text)
  a = try Json.decode[BookAdd](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
  tbl = tallies_tbl()
  cur = (try Table.tx_get(tx, tbl, a.name).map_error(fn(e) e.to_text end)) or 0
  next = cur + a.n
  t1 = try Table.put(tx, tbl, a.name, next).map_error(fn(e) e.to_text end)
  Ok((t1, next.to_json))
end

## v1 move (BUGGY): does NOT check `from >= n`, allowing negative tallies!
fn book_move_v1(tx: Modb.WriteTx, args: Json) : Result((Modb.WriteTx, Json), Text)
  m = try Json.decode[BookMove](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
  tbl = tallies_tbl()
  f_cur = (try Table.tx_get(tx, tbl, m.from).map_error(fn(e) e.to_text end)) or 0
  t_cur = (try Table.tx_get(tx, tbl, m.to).map_error(fn(e) e.to_text end)) or 0
  f_next = f_cur - m.n
  t_next = t_cur + m.n
  t1 = try Table.put(tx, tbl, m.from, f_next).map_error(fn(e) e.to_text end)
  t2 = try Table.put(t1, tbl, m.to, t_next).map_error(fn(e) e.to_text end)
  Ok((t2, Json.Object({"from": f_next.to_json, "to": t_next.to_json})))
end

## v2 move (FIXED): refuses when `from < n`.
fn book_move_v2(tx: Modb.WriteTx, args: Json) : Result((Modb.WriteTx, Json), Text)
  m = try Json.decode[BookMove](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
  tbl = tallies_tbl()
  f_cur = (try Table.tx_get(tx, tbl, m.from).map_error(fn(e) e.to_text end)) or 0
  if f_cur < m.n
    return Error("insufficient '#{m.from}': have #{f_cur}, need #{m.n}")
  end
  t_cur = (try Table.tx_get(tx, tbl, m.to).map_error(fn(e) e.to_text end)) or 0
  f_next = f_cur - m.n
  t_next = t_cur + m.n
  t1 = try Table.put(tx, tbl, m.from, f_next).map_error(fn(e) e.to_text end)
  t2 = try Table.put(t1, tbl, m.to, t_next).map_error(fn(e) e.to_text end)
  Ok((t2, Json.Object({"from": f_next.to_json, "to": t_next.to_json})))
end

## v3 move (UPGRADED SHAPE): checks `from >= n` AND increments `stats["moves"]`.
fn book_move_v3(tx: Modb.WriteTx, args: Json) : Result((Modb.WriteTx, Json), Text)
  (t2, rep) = try book_move_v2(tx, args)
  st = stats_tbl()
  cur_m = (try Table.tx_get(t2, st, "moves").map_error(fn(e) e.to_text end)) or 0
  t3 = try Table.put(t2, st, "moves", cur_m + 1).map_error(fn(e) e.to_text end)
  Ok((t3, rep))
end

fn book_schema(target_ver: Int) : Ledger.Schema
  st = stats_tbl()
  var sc = Ledger.schema(target_ver).with_require_reason(true).with_migration(
    Ledger.migration(1, "v1 tallies book", fn(tx) Ok(tx) end)
  )
  if target_ver >= 2
    sc = sc.with_migration(Ledger.migration(2, "v2 fix overdraft check", fn(tx) Ok(tx) end))
  end
  if target_ver >= 3
    sc = sc.with_migration(
      Ledger.migration(3, "v3 add move counter", fn(tx) Table.put(tx, st, "moves", 0) end)
    )
  end
  sc
end

fn book_replay_catalog() : Replay.ReplayCatalog
  Replay.catalog().with_action("add", book_add_fn).with_versioned_action(1, "move", book_move_v1)
    .with_versioned_action(2, "move", book_move_v2).with_versioned_action(3, "move", book_move_v3)
end

fn exp18_story() : List(StoryCall)
  [
    ## --- Version 1 (6 calls: includes overdraft bug where x drops below 0!) ---
    StoryCall(version: 1, caller: "a", action: "add", args: BookAdd(name: "x", n: 5).to_json),
    StoryCall(version: 1, caller: "b", action: "add", args: BookAdd(name: "y", n: 10).to_json),
    StoryCall(
      version: 1,
      caller: "a",
      action: "move",
      args: BookMove(from: "x", to: "y", n: 8).to_json
    ),
    StoryCall(version: 1, caller: "b", action: "add", args: BookAdd(name: "x", n: 10).to_json),
    StoryCall(
      version: 1,
      caller: "c",
      action: "move",
      args: BookMove(from: "x", to: "z", n: 5).to_json
    ),
    StoryCall(
      version: 1,
      caller: "b",
      action: "move",
      args: BookMove(from: "y", to: "z", n: 6).to_json
    ),
    ## --- Version 2 (6 calls: move checks balance; b drains y causing c's move to be REFUSED!) ---
    StoryCall(version: 2, caller: "a", action: "add", args: BookAdd(name: "y", n: 4).to_json),
    StoryCall(
      version: 2,
      caller: "b",
      action: "move",
      args: BookMove(from: "y", to: "z", n: 15).to_json
    ),
    StoryCall(
      version: 2,
      caller: "c",
      action: "move",
      args: BookMove(from: "y", to: "x", n: 5).to_json
    ),
    StoryCall(version: 2, caller: "a", action: "add", args: BookAdd(name: "x", n: 6).to_json),
    StoryCall(
      version: 2,
      caller: "b",
      action: "move",
      args: BookMove(from: "z", to: "x", n: 4).to_json
    ),
    StoryCall(
      version: 2,
      caller: "c",
      action: "move",
      args: BookMove(from: "x", to: "y", n: 7).to_json
    ),
    ## --- Version 3 (6 calls: stats["moves"] counted from v2->v3 upgrade onward!) ---
    StoryCall(
      version: 3,
      caller: "a",
      action: "move",
      args: BookMove(from: "y", to: "z", n: 5).to_json
    ),
    StoryCall(version: 3, caller: "b", action: "add", args: BookAdd(name: "y", n: 8).to_json),
    StoryCall(
      version: 3,
      caller: "c",
      action: "move",
      args: BookMove(from: "y", to: "z", n: 6).to_json
    ),
    StoryCall(
      version: 3,
      caller: "a",
      action: "move",
      args: BookMove(from: "z", to: "x", n: 4).to_json
    ),
    StoryCall(
      version: 3,
      caller: "b",
      action: "move",
      args: BookMove(from: "x", to: "y", n: 3).to_json
    ),
    StoryCall(
      version: 3,
      caller: "c",
      action: "move",
      args: BookMove(from: "x", to: "z", n: 2).to_json
    )
  ]
end

fn run_real_upgraded_service(
  files: Files,
  path: Text,
  rc: Replay.ReplayCatalog,
  skip_caller: Option(Text),
  t0: Time
) : Ledger.Db
  story = exp18_story()
  assert Ledger.open(files, path, book_schema(1), t0) is Ok(db_v1)
  var db = db_v1
  var cur_v = 1
  var idx = 0
  for sc_call in story
    idx += 1
    if sc_call.version > cur_v
      assert Ledger.open(files, path, book_schema(sc_call.version), t0) is Ok(upgraded)
      db = upgraded
      cur_v = sc_call.version
    end
    skip? = case skip_caller
      Some(who): sc_call.caller == who
      None: false
    end
    if not skip?
      meta = Ledger.WriteMeta(
        principal: sc_call.caller,
        action: sc_call.action,
        reason: "story-#{idx}",
        at: t0
      )
      case Replay.execute_recording_refusals(db, rc, meta, sc_call.args)
        Ok((next, _rep, _rec)): db = next
        Error((next, _err)): db = next
      end
    end
  end
  db
end

fn must_int(store: Modb.Store, tbl: Table.Table(Text, Int), key: Text) : Int
  case Table.get(store, tbl, key)
    Ok(Some(v)): v
    Ok(None): 0
    Error(_): stop "unexpected table read error"
  end
end

fn read_book_state(db: Ledger.Db) : (Int, Int, Int, Int)
  t = tallies_tbl()
  st = stats_tbl()
  s = Ledger.store(db)
  (must_int(s, t, "x"), must_int(s, t, "y"), must_int(s, t, "z"), must_int(s, st, "moves"))
end

test "2. Experiment 18 parity: faithful multi-version replay, caller excision, bug-fix replay & negative control"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T14:30:00Z") or stop "t0"
  rc_hist = book_replay_catalog()

  ## Build primary real upgraded service (v1 -> v2 -> v3) with all 18 calls
  db_real = run_real_upgraded_service(files, "exp18-real.modb", rc_hist, None, t0)
  real_state = read_book_state(db_real)
  assert Ledger.verify_all(db_real) is Ok(_)
  assert Replay.call_count(Ledger.store(db_real)) == Ok(18)

  ## Build Oracle #1: real upgraded service that NEVER received caller 'b'
  db_oracle_no_b = run_real_upgraded_service(
    files,
    "exp18-oracle-no-b.modb",
    rc_hist,
    Some("b"),
    t0
  )
  oracle_no_b_state = read_book_state(db_oracle_no_b)
  assert oracle_no_b_state != real_state

  ## Build Oracle #2: real service that ran v1 calls under FIXED v2 move code, then v2 & v3!
  rc_fixed_v1 = rc_hist.with_override_for_version(1, "move", book_move_v2)
  db_oracle_bugfix = run_real_upgraded_service(
    files,
    "exp18-oracle-bugfix.modb",
    rc_fixed_v1,
    None,
    t0
  )
  oracle_bugfix_state = read_book_state(db_oracle_bugfix)
  assert oracle_bugfix_state != real_state

  ## --- RUN 1: Faithful rebuild reproduces exact live state with ZERO divergences ---
  assert Replay.preview_replay(
    db_real,
    rc_hist,
    Replay.ReplayAll,
    "prop-faithful",
    "Verify deterministic v1->v2->v3 replay",
    "admin:ada",
    t0
  ) is
    Ok(p_faith)
  assert p_faith.summary.total_calls == 18
  assert p_faith.summary.excluded == 0
  assert p_faith.summary.reply_changed == 0
  assert p_faith.summary.now_refused == 0
  assert p_faith.summary.now_accepted == 0
  assert p_faith.summary.migrations_run == [1, 2, 3]
  assert p_faith.bucket_diffs.empty?

  ## --- RUN 2: Excise caller 'b' -> matches Oracle #1 identically AND surfaces ReplyChanged + NowRefused + NowAccepted ---
  assert Export.export_db(db_real, true, t0) is Ok(snap_real)
  assert Export.import_db(files, "exp18-copy-no-b.modb", book_schema(3), snap_real, t0) is
    Ok(db_copy1)

  assert Replay.simulate_replay(
    db_copy1,
    rc_hist,
    Replay.ExcludePrincipal(principal: "b"),
    "prop-no-b",
    "Remove caller b across v1->v2->v3",
    "admin:ada",
    t0
  ) is
    Ok((db_copy1_sim, p_no_b))
  assert p_no_b.summary.excluded == 7
  assert p_no_b.summary.reply_changed > 0
  assert p_no_b.summary.now_refused > 0
  assert p_no_b.summary.now_accepted > 0
  ## Live copy is 100% UNTOUCHED until explicit Admin acceptance!
  assert read_book_state(db_copy1_sim) == real_state

  acc_meta = Ledger.WriteMeta(
    principal: "admin:ada",
    action: "accept_replay_proposal",
    reason: "excise caller b",
    at: t0
  )
  assert Replay.accept_proposal(db_copy1_sim, "prop-no-b", acc_meta) is Ok((db_copy1_done, _))
  assert read_book_state(db_copy1_done) == oracle_no_b_state
  assert Ledger.verify_all(db_copy1_done) is Ok(_)

  ## --- RUN 3: Bug-fix replay (v1 calls through v2 fixed move) -> matches Oracle #2 identically ---
  assert Export.import_db(files, "exp18-copy-bugfix.modb", book_schema(3), snap_real, t0) is
    Ok(db_copy2)

  assert Replay.simulate_replay(
    db_copy2,
    rc_fixed_v1,
    Replay.ReplayAll,
    "prop-bugfix",
    "Replay v1 calls through fixed v2 move handler",
    "admin:ada",
    t0
  ) is
    Ok((db_copy2_sim, p_bugfix))
  ## Call #3 (v1 overdraft move x: 5 - 8 = -3) MUST now be refused!
  assert p_bugfix.summary.now_refused >= 1
  assert p_bugfix.summary.reply_changed > 0
  assert read_book_state(db_copy2_sim) == real_state

  assert Replay.accept_proposal(db_copy2_sim, "prop-bugfix", acc_meta) is Ok((db_copy2_done, _))
  assert read_book_state(db_copy2_done) == oracle_bugfix_state
  assert Ledger.verify_all(db_copy2_done) is Ok(_)

  ## --- NEGATIVE CONTROL: Running the whole story through newest v3 code from an empty v3 state ---
  ## Must differ from BOTH real_state and oracle_bugfix_state because v3 counts moves from call #1
  ## instead of only after the v2 -> v3 schema migration (Experiment 18 control)!
  assert Ledger.open(files, "exp18-newest-only.modb", book_schema(3), t0) is Ok(db_v3_start)
  var db_newest = db_v3_start
  rc_v3_all = Replay.catalog().with_action("add", book_add_fn).with_action("move", book_move_v3)
  var n_idx = 0
  for sc_call in exp18_story()
    n_idx += 1
    meta = Ledger.WriteMeta(
      principal: sc_call.caller,
      action: sc_call.action,
      reason: "newest-#{n_idx}",
      at: t0
    )
    case Replay.execute_recording_refusals(db_newest, rc_v3_all, meta, sc_call.args)
      Ok((next, _rep, _rec)): db_newest = next
      Error((next, _err)): db_newest = next
    end
  end
  newest_state = read_book_state(db_newest)
  assert newest_state != real_state
  assert newest_state != oracle_bugfix_state
  assert newest_state.3 > oracle_bugfix_state.3
end

test "3. Multi-agent Grant subtree exclusion, ExcludeWorld/ExcludeSeqs/StopBeforeSeq, discard & staleness guard"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T15:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T16:00:00Z") or stop "t1"
  tbl = tallies_tbl()

  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "seed vault=100", fn(tx) Table.put(tx, tbl, "vault", 100) end)
  ).with_invariant(
    Ledger.row_invariant(
      "non_negative",
      tbl,
      fn(k, v) if v < 0: Some("tally '#{k}' < 0") else: None end
    )
  )

  wcat = World.catalog().with_query(
    "get_vault",
    fn(tx, _args)
      v = (try Table.tx_get(tx, tbl, "vault").map_error(fn(e) e.to_text end)) or 0
      Ok(v.to_json)
    end
  ).with_action("add", book_add_fn)

  rc = Replay.catalog().with_action("add", book_add_fn)

  assert Ledger.open(files, "grant-replay.modb", sc, t0) is Ok(db0)
  am = Ledger.WriteMeta(principal: "admin:ada", action: "grant", reason: "init", at: t0)

  ## Issue g-rogue -> g-child -> g-grandchild (3-level chain) AND independent g-good
  assert Grants.issue_root(
    db0,
    am,
    Grants.GrantSpec(
      id: "g-rogue",
      principal: "agent:rogue",
      allowed_actions: ["add"],
      max_calls: 10,
      expires_at: t1
    )
  ) is
    Ok((db1, _))
  assert Grants.delegate(
    db1,
    am,
    "g-rogue",
    Grants.GrantSpec(
      id: "g-child",
      principal: "helper:c1",
      allowed_actions: ["add"],
      max_calls: 6,
      expires_at: t1
    )
  ) is
    Ok((db2, _))
  assert Grants.delegate(
    db2,
    am,
    "g-child",
    Grants.GrantSpec(
      id: "g-grand",
      principal: "helper:c2",
      allowed_actions: ["add"],
      max_calls: 3,
      expires_at: t1
    )
  ) is
    Ok((db3, _))
  assert Grants.issue_root(
    db3,
    am,
    Grants.GrantSpec(
      id: "g-good",
      principal: "agent:good",
      allowed_actions: ["add"],
      max_calls: 10,
      expires_at: t1
    )
  ) is
    Ok((db4, _))

  ## Land 4 Worlds: g-rogue (-10), g-good (-5), g-child (-20), g-grand (-15) -> vault = 50
  var db = db4
  runs = [
    ("w1", "g-rogue", -10),
    ("w2", "g-good", -5),
    ("w3", "g-child", -20),
    ("w4", "g-grand", -15)
  ]
  for (wid, gid, delta) in runs
    assert World.open_world(db, wid, gid, t0, t1) is Ok((d_o, _))
    assert World.world_call(
      d_o,
      wcat,
      wid,
      "add",
      BookAdd(name: "vault", n: delta).to_json,
      "op #{wid}",
      t0
    ) is
      Ok((d_c, _))
    assert World.land_world(d_c, wcat, wid, "land #{wid}", t0) is Ok((d_l, _))
    db = d_l
  end
  assert Table.get(Ledger.store(db), tbl, "vault") == Ok(Some(50))
  assert Replay.call_count(Ledger.store(db)) == Ok(4)

  ## Preview ExcludeWorld, ExcludeSeqs, and StopBeforeSeq
  assert Replay.preview_replay(
    db,
    rc,
    Replay.ExcludeWorld(world_id: "w3"),
    "p-w3",
    "drop w3",
    "admin:ada",
    t0
  ) is
    Ok(pw3)
  assert pw3.summary.excluded == 1 and pw3.summary.reply_changed == 1

  assert Replay.preview_replay(
    db,
    rc,
    Replay.ExcludeSeqs(seqs: [1, 4]),
    "p-seqs",
    "drop 1 & 4",
    "admin:ada",
    t0
  ) is
    Ok(pseqs)
  assert pseqs.summary.excluded == 2 and pseqs.summary.reply_changed == 2

  assert Replay.preview_replay(
    db,
    rc,
    Replay.StopBeforeSeq(seq: 3),
    "p-stop",
    "point in time before seq 3",
    "admin:ada",
    t0
  ) is
    Ok(pstop)
  assert pstop.summary.excluded == 2 and pstop.summary.unchanged == 2

  ## Simulate ExcludeGrant("g-rogue") -> MUST excise g-rogue, g-child, AND g-grand (3 of 4 calls)!
  assert Replay.simulate_replay(
    db,
    rc,
    Replay.ExcludeGrant(grant_id: "g-rogue"),
    "prop-stale-test",
    "Remove g-rogue subtree",
    "admin:ada",
    t0
  ) is
    Ok((db_sim, p_sub))
  assert p_sub.summary.excluded == 3
  assert p_sub.summary.reply_changed == 1

  ## Concurrent write arrives BEFORE Admin accepts -> proposal MUST be rejected as ProposalStale!
  assert Replay.execute(
    db_sim,
    rc,
    Ledger.WriteMeta(principal: "agent:good", action: "add", reason: "concurrent", at: t0),
    BookAdd(name: "vault", n: -7).to_json
  ) is
    Ok((db_conc, _, _))
  assert Table.get(Ledger.store(db_conc), tbl, "vault") == Ok(Some(43))

  acc_meta = Ledger.WriteMeta(
    principal: "admin:ada",
    action: "accept_replay_proposal",
    reason: "clean rogue subtree",
    at: t0
  )
  assert Replay.accept_proposal(db_conc, "prop-stale-test", acc_meta) is
    Error(
      Replay.ProposalStale(
        id: "prop-stale-test",
        expected_audit_seq: _,
        actual_audit_seq: _,
        expected_call_seq: 4,
        actual_call_seq: 5
      )
    )

  ## Discard stale proposal cleanly -> cannot accept discarded proposal
  assert Replay.discard_proposal(db_conc, "prop-stale-test", "admin:ada", t0) is
    Ok((db_disc, disc_p))
  assert disc_p.status is Replay.Discarded(discarded_by: "admin:ada", discarded_at: _)
  assert Replay.accept_proposal(db_disc, "prop-stale-test", acc_meta) is
    Error(Replay.ProposalNotPending(id: "prop-stale-test", status: _))

  ## Fresh re-simulation incorporates concurrent write (-5 and -7 remain; rogue -10/-20/-15 excised -> vault=88!)
  assert Replay.simulate_replay(
    db_disc,
    rc,
    Replay.ExcludeGrant(grant_id: "g-rogue"),
    "prop-fresh",
    "Remove g-rogue subtree after concurrent write",
    "admin:ada",
    t0
  ) is
    Ok((db_fresh, p_fresh))
  assert p_fresh.summary.excluded == 3 and p_fresh.summary.reply_changed == 2
  assert Replay.accept_proposal(db_fresh, "prop-fresh", acc_meta) is Ok((db_final, _))
  assert Table.get(Ledger.store(db_final), tbl, "vault") == Ok(Some(88))
  assert Ledger.verify_all(db_final) is Ok(_)
end

test "4. Deterministic 500-crash torn-write simulation across Replay.execute and accept_proposal_and_crash"
  t0 = Time.parse("2026-11-25T16:00:00Z") or stop "t0"
  tbl = tallies_tbl()
  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "seed k=100", fn(tx) Table.put(tx, tbl, "k", 100) end)
  ).with_invariant(
    Ledger.row_invariant(
      "non_negative",
      tbl,
      fn(k, v) if v < 0: Some("tally '#{k}' < 0") else: None end
    )
  )
  rc = Replay.catalog().with_action("add", book_add_fn)

  rng = Random.seeded(40442)
  var accepted_count = 0
  var rolled_back_count = 0

  ## 5 independent epochs x 100 torn-write crashes = 500 deterministic crashes verified with full Ledger.verify_all
  for epoch in 1..6
    assert Ledger.open_disk(Pager.sim_empty(), sc, t0) is Ok(db0)
    assert Replay.execute(
      db0,
      rc,
      Ledger.WriteMeta(principal: "agent:rogue", action: "add", reason: "bad", at: t0),
      BookAdd(name: "k", n: -30).to_json
    ) is
      Ok((d1, _, _))
    assert Replay.execute(
      d1,
      rc,
      Ledger.WriteMeta(principal: "user:legit", action: "add", reason: "ok", at: t0),
      BookAdd(name: "k", n: 5).to_json
    ) is
      Ok((d2, _, _))
    var db = d2
    assert Table.get(Ledger.store(db), tbl, "k") == Ok(Some(75))

    for step in 1..101
      prop_id = "crash-prop-e#{epoch}-s#{step}"
      before_k = must_int(Ledger.store(db), tbl, "k")
      before_audit = Ledger.audit_count(db)
      ## Alternate between excluding rogue (target k=105) and full replay (target k=75)
      flt = if step % 2 == 1
        Replay.ExcludePrincipal(principal: "agent:rogue")
      else
        Replay.ReplayAll
      end
      expected_after_k = if step % 2 == 1: 105 else: 75

      assert Replay.simulate_replay(db, rc, flt, prop_id, "crash #{epoch}.#{step}", "admin:ada", t0) is
        Ok((db_sim, _))
      phase = if step % 3 == 0: 1 else: 2
      acc_meta = Ledger.WriteMeta(
        principal: "admin:ada",
        action: "accept_replay_proposal",
        reason: "e#{epoch}-s#{step}",
        at: t0
      )
      assert Replay.accept_proposal_and_crash(db_sim, prop_id, acc_meta, phase, rng) is Ok(crashed)

      ## Reopen from crashed disk and assert full storage + audit chain + invariant integrity!
      assert Ledger.open_disk(crashed, sc, t0) is Ok(rec)
      assert Ledger.verify_all(rec) is Ok(_)
      after_k = must_int(Ledger.store(rec), tbl, "k")
      after_audit = Ledger.audit_count(rec)
      if after_audit == before_audit
        assert after_k == before_k
        rolled_back_count += 1
      else
        assert after_audit == before_audit + 1
        assert after_k == expected_after_k
        accepted_count += 1
      end
      db = rec
    end
  end

  assert accepted_count + rolled_back_count == 500
  assert accepted_count > 50 and rolled_back_count > 50
end
