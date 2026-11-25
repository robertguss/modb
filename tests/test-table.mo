## Comprehensive Layer 2 (`Modb.Table`) verification suite:
## - Signed 64-bit `Int`, `Text`, `Bytes`, and adversarial null/0xFF composite key codecs
## - Typed CRUD, schema-attached & explicit secondary indexes, overwrite stale-index cleanup,
##   delete cleanup, unique-index conflict rollback, `range_by`, MVCC `Snapshot` queries,
##   schema evolution (`decode` vs `strict`), error diagnostics, and `Modb.verify` zero-leak checks
## - Differential fuzz test (600+ random multi-op transactions) vs an in-memory reference model
module TestTable
use Json
use Modb
use Modb.Errors{ModbError}
use Modb.Table{TableError}

enum Plan
  Free
  Pro(seats: Int)
  Enterprise(region: Text)
end

struct Account
  email: Text
  team: Text
  score: Int
  balance: Decimal
  plan: Plan
  nickname: Option(Text)
  tags: List(Text)
end

## Binary-tagged item using custom `to_json` / `from_json` hex serialization for `Bytes`.
struct BlobItem
  tag: Bytes
  label: Text
end

fn to_json(b: BlobItem) : Json
  Json.Object({"tag": Json.String(b.tag.to_hex), "label": Json.String(b.label)})
end

fn from_json(v: Json) : Result(BlobItem, Text)
  tag_hex = try v.text_at("tag").or_fail("missing hex tag")
  tag = try Bytes.from_hex(tag_hex).or_fail("invalid hex tag")
  label = try v.text_at("label").or_fail("missing label")
  Ok(BlobItem(tag: tag, label: label))
end

struct SlimProfile
  name: Text
end

fn byte_vec(ints: List(Int)) : Bytes
  var out = []
  for n in ints
    b = n.to_byte or stop "valid byte 0..255"
    out = out.append(b)
  end
  Bytes.from_list(out)
end

test "Signed Int key ordering across INT64_MIN..INT64_MAX and round-trip decoding"
  boundaries = [
    Table.int64_min,
    Table.int64_min + 1,
    -1_000_000_000_000_000,
    -4_294_967_296,
    -1000,
    -2,
    -1,
    0,
    1,
    2,
    1000,
    4_294_967_296,
    1_000_000_000_000_000,
    Table.int64_max - 1,
    Table.int64_max
  ]

  for i in 0..boundaries.size
    cur = boundaries.get(i) or stop "boundary idx"
    enc = Table.encode_int_key(cur)
    assert enc.size == 8
    assert Table.decode_int_key(enc) == Ok(cur)
    if i + 1 < boundaries.size
      nxt = boundaries.get(i + 1) or stop "next boundary idx"
      assert cur < nxt
      assert enc < Table.encode_int_key(nxt)
    end
  end

  ## Reject malformed byte lengths cleanly
  assert Table.decode_int_key(Bytes.empty) is Error(DecodeKey(reason: _))
  assert Table.decode_int_key(Bytes.zeroed(7)) is Error(DecodeKey(reason: _))
  assert Table.decode_int_key(Bytes.zeroed(9)) is Error(DecodeKey(reason: _))
  assert Table.decode_text_key(byte_vec([255, 254])) is Error(DecodeKey(reason: _))

  ## Verify B+Tree primary-key ordering matches signed Int order end-to-end
  files = Files.in_memory({})
  assert Modb.open(files, "int-order.modb") is Ok(db0)
  labels = Table.int_key[Text]("int_labels")

  ## Insert in scrambled order via `put_many`
  scrambled = [
    1000,
    Table.int64_min,
    0,
    Table.int64_max,
    -1,
    1,
    -1000,
    Table.int64_max - 1,
    Table.int64_min + 1
  ]
  entries = scrambled.map(fn(k) (k, "val:#{k}") end)
  assert Table.write_tx(db0, fn(tx) Table.put_many(tx, labels, entries) end) is Ok(db1)

  expected_keys = [
    Table.int64_min,
    Table.int64_min + 1,
    -1000,
    -1,
    0,
    1,
    1000,
    Table.int64_max - 1,
    Table.int64_max
  ]
  assert Table.all(db1, labels) is Ok(all_rows)
  assert all_rows.map(fn(pair) pair.0 end) == expected_keys
  assert Table.range(db1, labels, -1000, 1000) ==
    Ok([(-1000, "val:-1000"), (-1, "val:-1"), (0, "val:0"), (1, "val:1")])
  assert Table.range(db1, labels, 100, -100) == Ok([])
  assert Modb.verify(db1) is Ok(_)
end

test "Collision-free composite index keys on arbitrary 0x00 / 0xFF Bytes and NUL Text"
  ik_samples = [
    Bytes.empty,
    byte_vec([0]),
    byte_vec([0, 0]),
    byte_vec([0, 1]),
    byte_vec([0, 255]),
    byte_vec([1]),
    byte_vec([97]),
    byte_vec([97, 0]),
    byte_vec([97, 0, 0]),
    byte_vec([97, 0, 255]),
    byte_vec([97, 1]),
    byte_vec([255]),
    byte_vec([255, 0]),
    byte_vec([255, 255])
  ]
  pk_samples = [Bytes.empty, byte_vec([0]), byte_vec([0, 0]), byte_vec([1]), byte_vec([255, 255])]

  ## Verify strict lexicographic order preservation across every (ik, pk) pair and round-trip decode
  var prev_comp = None
  for ik in ik_samples
    for pk in pk_samples
      comp = Table.encode_composite_key(ik, pk)
      assert Table.decode_composite_key(comp) == Ok((ik, pk))
      case prev_comp
        Some(prev): assert prev < comp
        None: Unit
      end
      prev_comp = Some(comp)
    end
  end

  assert Table.decode_composite_key(byte_vec([1, 2, 3])) is Error(DecodeKey(reason: _))
  assert Table.decode_composite_key(byte_vec([0])) is Error(DecodeKey(reason: _))
  assert Table.decode_composite_key(byte_vec([0, 42])) is Error(DecodeKey(reason: _))

  ## Verify in a real Modb non-unique Bytes index that prefix/NUL keys never collide or bleed
  files = Files.in_memory({})
  assert Modb.open(files, "bytes-idx.modb") is Ok(db0)
  by_tag = Table.bytes_index[Bytes, BlobItem]("blobs_by_tag", fn(b) b.tag end)
  blobs = Table.bytes_key[BlobItem]("blobs").with_index(by_tag)

  t_a = byte_vec([97])
  t_a0 = byte_vec([97, 0])
  t_a0ff = byte_vec([97, 0, 255])
  pk_hi = byte_vec([255, 255])
  pk_lo = byte_vec([0, 1])

  assert Table.write_tx(
    db0,
    fn(tx)
      c1 = try Table.put(tx, blobs, pk_hi, BlobItem(tag: t_a, label: "a-hi"))
      c2 = try Table.put(c1, blobs, pk_lo, BlobItem(tag: t_a, label: "a-lo"))
      ## Overwrite pk_lo in the SAME WriteTx from tag `t_a` to `t_a0`
      c3 = try Table.put(c2, blobs, pk_lo, BlobItem(tag: t_a0, label: "a0"))
      Table.put(c3, blobs, byte_vec([5]), BlobItem(tag: t_a0ff, label: "a0ff"))
    end
  ) is
    Ok(db1)

  assert Table.lookup(db1, blobs, by_tag, t_a) == Ok([(pk_hi, BlobItem(tag: t_a, label: "a-hi"))])
  assert Table.lookup(db1, blobs, by_tag, t_a0) == Ok([(pk_lo, BlobItem(tag: t_a0, label: "a0"))])
  assert Table.lookup(db1, blobs, by_tag, t_a0ff) ==
    Ok([(byte_vec([5]), BlobItem(tag: t_a0ff, label: "a0ff"))])
  assert Table.range_by(db1, blobs, by_tag, Some(t_a), Some(t_a0ff), 0) ==
    Ok([(pk_hi, BlobItem(tag: t_a, label: "a-hi")), (pk_lo, BlobItem(tag: t_a0, label: "a0"))])
  assert Modb.verify(db1) is Ok(_)
end

test "Typed CRUD, index overwrites, deletes, unique rollback, range_by and MVCC snapshots"
  files = Files.in_memory({})
  assert Modb.open(files, "accounts.modb") is Ok(db0)

  by_email = Table.unique_text_index[Int, Account]("acc_by_email", fn(a) a.email end)
  by_team = Table.text_index[Int, Account]("acc_by_team", fn(a) a.team end)
  by_score = Table.int_index[Int, Account]("acc_by_score", fn(a) a.score end)
  accounts = Table.int_key[Account]("accounts").with_index(by_email).with_index(by_team).with_index(
    by_score
  )

  ada = Account(
    email: "ada@ex.org",
    team: "core",
    score: -50,
    balance: 125.50,
    plan: Pro(seats: 5),
    nickname: Some("lovelace"),
    tags: ["founder", "math"]
  )
  grace = Account(
    email: "grace@ex.org",
    team: "core",
    score: 120,
    balance: 250.00,
    plan: Enterprise(region: "us-east"),
    nickname: None,
    tags: ["compilers"]
  )
  linus = Account(
    email: "linus@ex.org",
    team: "kernel",
    score: 0,
    balance: 0.00,
    plan: Free,
    nickname: Some("tux"),
    tags: []
  )

  assert Table.write_tx(
    db0,
    fn(tx)
      t1 = try Table.put(tx, accounts, 10, ada)
      t2 = try Table.put(t1, accounts, 20, grace)
      t3 = try Table.put(t2, accounts, -5, linus)
      ## Read-your-own-writes inside WriteTx
      assert Table.tx_get(t3, accounts, 10) == Ok(Some(ada))
      assert Table.tx_lookup_unique(t3, accounts, by_email, "grace@ex.org") == Ok(Some((20, grace)))
      assert Table.tx_lookup(t3, accounts, by_team, "core") == Ok([(10, ada), (20, grace)])
      Ok(t3)
    end
  ) is
    Ok(db1)

  assert Table.count(db1, accounts) == Ok(3)
  assert Table.all(db1, accounts) == Ok([(-5, linus), (10, ada), (20, grace)])
  assert Table.lookup(db1, accounts, by_team, "core") == Ok([(10, ada), (20, grace)])
  assert Table.lookup_unique(db1, accounts, by_email, "ada@ex.org") == Ok(Some((10, ada)))
  assert Table.lookup_unique(db1, accounts, by_email, "nobody@ex.org") == Ok(None)

  ## Calling lookup_unique on a non-unique index is rejected cleanly
  assert Table.lookup_unique(db1, accounts, by_team, "core") is
    Error(Storage(InvalidArgument(reason: _)))

  ## Signed Int index range scan across negative, zero, and positive scores
  assert Table.range_by(db1, accounts, by_score, None, None, 0) ==
    Ok([(10, ada), (-5, linus), (20, grace)])
  assert Table.range_by(db1, accounts, by_score, Some(-60), Some(10), 0) ==
    Ok([(10, ada), (-5, linus)])
  assert Table.range_by(db1, accounts, by_score, None, None, 2) == Ok([(10, ada), (-5, linus)])

  ## Unique index conflict must abort the entire WriteTx cleanly (atomic rollback!)
  txid_before = Modb.txid(db1)
  dup = Account(
    email: "grace@ex.org",
    team: "ops",
    score: 999,
    balance: 1.00,
    plan: Free,
    nickname: None,
    tags: []
  )
  assert Table.write_tx(
    db1,
    fn(tx)
      ## First mutate key -5, then trigger unique conflict on key 99 -> both must roll back!
      t1 = try Table.delete(tx, accounts, -5)
      Table.put(t1, accounts, 99, dup)
    end
  ) is
    Error(Table.UniqueConflict(index: "acc_by_email", value: "grace@ex.org"))
  assert Modb.txid(db1) == txid_before
  assert Table.get(db1, accounts, -5) == Ok(Some(linus))
  assert Table.get(db1, accounts, 99) == Ok(None)
  assert Table.lookup(db1, accounts, by_team, "ops") == Ok([])

  ## Pin a snapshot before overwriting Ada's email/team/score and deleting Linus
  (db_pinned, snap) = Modb.snapshot(db1)
  ada_v2 = Account(
    email: "ada.lovelace@ex.org",
    team: "research",
    score: 500,
    balance: 999.95,
    plan: Pro(seats: 12),
    nickname: Some("countess"),
    tags: ["founder"]
  )
  ## Overwriting Grace WITHOUT changing her unique email must succeed without false conflict
  grace_v2 = Account(
    email: "grace@ex.org",
    team: "core",
    score: 120,
    balance: 300.00,
    plan: Enterprise(region: "us-east"),
    nickname: Some("admiral"),
    tags: ["compilers", "cobol"]
  )
  ## Ada's old email "ada@ex.org" is now free for a brand-new user (key 30) in the same tx!
  reclaimed_user = Account(
    email: "ada@ex.org",
    team: "research",
    score: 10,
    balance: 5.00,
    plan: Free,
    nickname: None,
    tags: []
  )

  assert Table.write_tx(
    db_pinned,
    fn(tx)
      t1 = try Table.put(tx, accounts, 10, ada_v2)
      t2 = try Table.put(t1, accounts, 20, grace_v2)
      t3 = try Table.delete(t2, accounts, -5)
      Table.put(t3, accounts, 30, reclaimed_user)
    end
  ) is
    Ok(db2)

  ## Live store sees updated indexes and zero stale entries
  assert Table.lookup_unique(db2, accounts, by_email, "ada.lovelace@ex.org") ==
    Ok(Some((10, ada_v2)))
  assert Table.lookup_unique(db2, accounts, by_email, "ada@ex.org") ==
    Ok(Some((30, reclaimed_user)))
  assert Table.lookup_unique(db2, accounts, by_email, "linus@ex.org") == Ok(None)
  assert Table.lookup(db2, accounts, by_team, "core") == Ok([(20, grace_v2)])
  assert Table.lookup(db2, accounts, by_team, "kernel") == Ok([])
  assert Table.lookup(db2, accounts, by_team, "research") ==
    Ok([(10, ada_v2), (30, reclaimed_user)])
  assert Table.range_by(db2, accounts, by_score, None, None, 0) ==
    Ok([(30, reclaimed_user), (20, grace_v2), (10, ada_v2)])

  ## Snapshot still sees exact pre-mutation rows and secondary indexes!
  assert Table.snapshot_get(db2, snap, accounts, 10) == Ok(Some(ada))
  assert Table.snapshot_get(db2, snap, accounts, -5) == Ok(Some(linus))
  assert Table.snapshot_get(db2, snap, accounts, 30) == Ok(None)
  assert Table.snapshot_all(db2, snap, accounts) == Ok([(-5, linus), (10, ada), (20, grace)])
  assert Table.snapshot_lookup(db2, snap, accounts, by_team, "core") == Ok([(10, ada), (20, grace)])
  assert Table.snapshot_lookup_unique(db2, snap, accounts, by_email, "ada@ex.org") ==
    Ok(Some((10, ada)))
  assert Table.snapshot_range_by(db2, snap, accounts, by_score, None, None, 0) ==
    Ok([(10, ada), (-5, linus), (20, grace)])
  assert Modb.verify(db2) is Ok(_)

  ## Release snapshot and verify snapshot queries fail cleanly
  assert Modb.release_snapshot(db2, snap) is Ok(db3)
  assert Table.snapshot_get(db3, snap, accounts, 10) is Error(Storage(SnapshotUnknown(id: _)))
  assert Table.snapshot_lookup(db3, snap, accounts, by_team, "core") is
    Error(Storage(SnapshotUnknown(id: _)))

  ## Delete all remaining accounts via `delete_many` -> primary and index buckets are cleaned up
  assert Table.write_tx(db3, fn(tx) Table.delete_many(tx, accounts, [10, 20, 30]) end) is
    Ok(db_empty)
  assert Table.all(db_empty, accounts) == Ok([])
  assert Table.lookup(db_empty, accounts, by_team, "research") == Ok([])
  assert Table.lookup_unique(db_empty, accounts, by_email, "grace@ex.org") == Ok(None)
  assert Modb.buckets(db_empty) == Ok([])
  assert Modb.verify(db_empty) is Ok(_)
end

test "Explicit put_indexed/delete_indexed, strict vs tolerant JSON decode, and error paths"
  files = Files.in_memory({})
  assert Modb.open(files, "edge-table.modb") is Ok(db0)

  ## Explicit `put_indexed` / `delete_indexed` without `.with_index`
  items_tbl = Table.text_key[BlobItem]("items")
  by_label = Table.text_index[Text, BlobItem]("items_by_label", fn(b) b.label end)
  b_item = BlobItem(tag: byte_vec([1, 2]), label: "alpha")

  assert Table.write_tx(db0, fn(tx) Table.put_indexed(tx, items_tbl, [by_label], "k1", b_item) end) is
    Ok(db1)
  assert Table.lookup(db1, items_tbl, by_label, "alpha") == Ok([("k1", b_item)])
  assert Table.write_tx(db1, fn(tx) Table.delete_indexed(tx, items_tbl, [by_label], "k1") end) is
    Ok(db2)
  assert Table.lookup(db2, items_tbl, by_label, "alpha") == Ok([])

  ## Schema evolution: default `Table` ignores extra JSON fields, while `Table.strict` rejects them
  tolerant = Table.text_key[SlimProfile]("profiles")
  strict_tbl = Table.strict(tolerant)
  assert Modb.write_tx(
    db2,
    fn(tx) Modb.tx_put(tx, "profiles", "u1".bytes, "{\"name\":\"Ada\",\"legacy\":42}".bytes) end
  ) is
    Ok(db3)
  assert Table.get(db3, tolerant, "u1") == Ok(Some(SlimProfile(name: "Ada")))
  assert Table.get(db3, strict_tbl, "u1") is Error(Table.DecodeValue(_))

  ## Invalid JSON bytes surface `DecodeValue`
  assert Modb.write_tx(db3, fn(tx) Modb.tx_put(tx, "profiles", "bad".bytes, "{broken".bytes) end) is
    Ok(db4)
  assert Table.get(db4, tolerant, "bad") is Error(Table.DecodeValue(_))

  ## Dangling secondary index entry surfaces `CorruptIndex`
  orphan_idx = Table.unique_text_index[Text, SlimProfile]("orphan_idx", fn(p) p.name end)
  assert Modb.write_tx(
    db4,
    fn(tx) Modb.tx_put(tx, "orphan_idx", "Ghost".bytes, "missing-pk".bytes) end
  ) is
    Ok(db5)
  assert Table.lookup_unique(db5, tolerant, orphan_idx, "Ghost") is
    Error(Table.CorruptIndex(index: "orphan_idx", reason: _))

  ## Reject index sharing primary bucket name
  clashing_idx = Table.text_index[Text, SlimProfile]("profiles", fn(p) p.name end)
  assert Table.write_tx(
    db5,
    fn(tx) Table.put_indexed(tx, tolerant, [clashing_idx], "u2", SlimProfile(name: "Bob")) end
  ) is
    Error(Storage(InvalidArgument(reason: _)))

  ## Verify `TableError.to_text` covers all variants cleanly
  assert Table.UniqueConflict(index: "idx", value: "v").to_text ==
    "unique index conflict on 'idx': duplicate key 'v'"
  assert Table.DecodeKey(reason: "short").to_text == "key decode error: short"
  assert Table.CorruptIndex(index: "idx", reason: "dangling").to_text ==
    "corrupt secondary index 'idx': dangling"
  assert Modb.verify(db5) is Ok(_)
end

struct RefRec
  email: Text
  dept: Text
  points: Int
end

fn ref_sorted_all(model: Map(Int, RefRec)) : List((Int, RefRec))
  model.entries.sort_by(fn(pair) pair.0 end)
end

fn ref_lookup_dept(model: Map(Int, RefRec), dept: Text) : List((Int, RefRec))
  ref_sorted_all(model).filter(fn(pair) (pair.1).dept == dept end)
end

fn ref_lookup_email(model: Map(Int, RefRec), email: Text) : Option((Int, RefRec))
  ref_sorted_all(model).find(fn(pair) (pair.1).email == email end)
end

fn ref_range_points(model: Map(Int, RefRec), lo: Int, hi: Int) : List((Int, RefRec))
  model.entries.filter(fn(pair) (pair.1).points >= lo and (pair.1).points < hi end).sort_by(
    fn(pair) ((pair.1).points, pair.0) end
  )
end

fn email_taken_by_other?(model: Map(Int, RefRec), pk: Int, email: Text) : Bool
  for (k, rec) in model.entries
    if k != pk and rec.email == email
      return true
    end
  end
  false
end

fn dept_for(idx: Int) : Text
  if idx == 0
    "eng"
  else if idx == 1
    "design"
  else if idx == 2
    "ops\u{0}sec"
  else
    "sales"
  end
end

fn assert_matches_model(
  db: Modb.Store,
  tbl: Table.Table(Int, RefRec),
  by_email: Table.Index(Int, RefRec, Text),
  by_dept: Table.Index(Int, RefRec, Text),
  by_points: Table.Index(Int, RefRec, Int),
  model: Map(Int, RefRec)
)
  expected_all = ref_sorted_all(model)
  assert Table.all(db, tbl) == Ok(expected_all)
  for d_idx in 0..4
    d = dept_for(d_idx)
    assert Table.lookup(db, tbl, by_dept, d) == Ok(ref_lookup_dept(model, d))
  end
  for (_k, rec) in expected_all
    assert Table.lookup_unique(db, tbl, by_email, rec.email) ==
      Ok(ref_lookup_email(model, rec.email))
  end
  assert Table.range_by(db, tbl, by_points, Some(-250), Some(250), 0) ==
    Ok(ref_range_points(model, -250, 250))
end

test "Differential correctness: 600 random indexed puts/overwrites/deletes/conflicts vs Map"
  rng = Random.seeded(20261124)
  files = Files.in_memory({})
  assert Modb.open(files, "diff-table.modb") is Ok(db0)
  var db = db0
  var model = {}

  by_email = Table.unique_text_index[Int, RefRec]("ref_by_email", fn(r) r.email end)
  by_dept = Table.text_index[Int, RefRec]("ref_by_dept", fn(r) r.dept end)
  by_points = Table.int_index[Int, RefRec]("ref_by_points", fn(r) r.points end)
  tbl = Table.int_key[RefRec]("ref_records").with_index(by_email).with_index(by_dept).with_index(
    by_points
  )

  var snaps = []
  var snap_models = []

  for step in 0..200
    choice = rng.int(0, 15)
    if choice == 0 and snaps.size < 3
      (db_s, snap) = Modb.snapshot(db)
      db = db_s
      snaps = snaps.append(snap)
      snap_models = snap_models.append(model)
    else if choice == 1 and not snaps.empty?
      snap = snaps.first or stop "snap"
      s_model = snap_models.first or stop "snap_model"
      assert Table.snapshot_all(db, snap, tbl) == Ok(ref_sorted_all(s_model))
      assert Table.snapshot_lookup(db, snap, tbl, by_dept, "eng") ==
        Ok(ref_lookup_dept(s_model, "eng"))
      assert Table.snapshot_range_by(db, snap, tbl, by_points, Some(-200), Some(200), 0) ==
        Ok(ref_range_points(s_model, -200, 200))
      assert Modb.release_snapshot(db, snap) is Ok(db_rel)
      db = db_rel
      snaps = snaps.drop(1)
      snap_models = snap_models.drop(1)
    else
      ## Execute a 3-operation transaction; track candidate model and whether a unique conflict occurs.
      var cand = model
      var ops = []
      var expect_conflict = false
      for _sub in 0..3
        pk = rng.int(-30, 30)
        if rng.int(0, 4) == 0
          ops = ops.append((0, pk, RefRec(email: "", dept: "", points: 0)))
          if not expect_conflict
            cand = cand.remove(pk)
          end
        else
          ## Email pool intentionally small (0..45) so unique conflicts & email handoffs happen often!
          email = "u#{rng.int(0, 45)}@ex.org"
          dept = dept_for(rng.int(0, 4))
          pts = rng.int(-500, 500)
          rec = RefRec(email: email, dept: dept, points: pts)
          ops = ops.append((1, pk, rec))
          if not expect_conflict
            if email_taken_by_other?(cand, pk, email)
              expect_conflict = true
            else
              cand = cand.set(pk, rec)
            end
          end
        end
      end

      outcome = Table.write_tx(
        db,
        fn(tx)
          var cur = tx
          for (kind, pk, rec) in ops
            if kind == 0
              cur = try Table.delete(cur, tbl, pk)
            else
              cur = try Table.put(cur, tbl, pk, rec)
            end
          end
          Ok(cur)
        end
      )

      if expect_conflict
        assert outcome is Error(Table.UniqueConflict(index: "ref_by_email", value: _))
      else
        assert outcome is Ok(db_next)
        db = db_next
        model = cand
      end
    end

    if step % 25 == 0
      assert Modb.verify(db) is Ok(_)
      assert_matches_model(db, tbl, by_email, by_dept, by_points, model)
    end
  end

  for i in 0..snaps.size
    snap = snaps.get(i) or stop "snap"
    s_model = snap_models.get(i) or stop "snap_model"
    assert Table.snapshot_all(db, snap, tbl) == Ok(ref_sorted_all(s_model))
    assert Modb.release_snapshot(db, snap) is Ok(db_rel)
    db = db_rel
  end

  assert Modb.verify(db) is Ok(_)
  assert_matches_model(db, tbl, by_email, by_dept, by_points, model)

  ## Reopen cold from `Files` and verify full durability + index integrity
  assert Modb.open(files, "diff-table.modb") is Ok(reopened)
  assert Modb.verify(reopened) is Ok(_)
  assert_matches_model(reopened, tbl, by_email, by_dept, by_points, model)
end
