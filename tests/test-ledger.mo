## Milestone 2A Verification Suite for `Modb.Ledger` (Layer 3):
## - Accountable writes, indexed audit queries, snapshots, and hash-chain verification
## - Commit-time invariant enforcement and full rollback on failure
## - Tamper detection on modified/deleted audit entries and metadata
## - Atomic multi-step schema migrations, rollback on failure, and `SchemaTooNew` guard
## - 500-crash deterministic fault-injection simulation over accountable ledger commits
module TestLedger
use Json
use Modb
use Modb.Ledger
use Modb.Pager
use Modb.Table

struct Account
  owner: Text
  email: Text
  balance: Int
end

struct TransferPayload
  from_id: Int
  to_id: Int
  amount: Int
end

struct LedgerItem
  title: Text
  tag: Text
  qty: Int
end

enum AppError
  Db(Ledger.LedgerError)
  InsufficientFunds(available: Int, needed: Int)
  MissingAccount(id: Int)
end

fn accounts_by_email() : Table.Index(Int, Account, Text)
  Table.unique_text_index[Int, Account]("accounts_by_email", fn(a) a.email end)
end

fn accounts_table() : Table.Table(Int, Account)
  Table.int_key[Account]("accounts").with_index(accounts_by_email())
end

fn items_table() : Table.Table(Int, LedgerItem)
  Table.int_key[LedgerItem]("items")
end

fn bank_schema() : Ledger.Schema
  acct = accounts_table()
  Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(
      1,
      "create treasury account",
      fn(tx)
        Table.put(
          tx,
          acct,
          1,
          Account(owner: "Treasury", email: "treasury@bank.local", balance: 1000)
        )
      end
    )
  ).with_invariant(
    Ledger.row_invariant(
      "non_negative_balance",
      acct,
      fn(id, a) if a.balance < 0: Some("account ##{id} balance #{a.balance} < 0") else: None end
    )
  ).with_invariant(
    Ledger.invariant(
      "conservation_of_money",
      fn(tx)
        rows = try Table.tx_scan(tx, acct, None, None, 0)
        var total = 0
        for (_id, a) in rows
          total += a.balance
        end
        if total != 1000
          Ok(Some("total balance drifted to #{total}, expected 1000"))
        else
          Ok(None)
        end
      end
    )
  )
end

fn transfer(db: Ledger.Db, from_id: Int, to_id: Int, amount: Int, who: Text, reason: Text, at: Time) : Result(
  (Ledger.Db, Int),
  AppError
)
  acct = accounts_table()
  meta = Ledger.WriteMeta(principal: who, action: "transfer", reason: reason, at: at)
  payload = TransferPayload(from_id: from_id, to_id: to_id, amount: amount).to_json
  Ledger.transact(
    db,
    meta,
    "transfer #{amount} from ##{from_id} to ##{to_id}",
    payload,
    fn(e) Db(e) end,
    fn(tx)
      src_opt = try Table.tx_get(tx, acct, from_id).map_error(fn(e) Db(Ledger.TableFailure(e)) end)
      src = try src_opt.or_fail(MissingAccount(id: from_id))
      dst_opt = try Table.tx_get(tx, acct, to_id).map_error(fn(e) Db(Ledger.TableFailure(e)) end)
      dst = try dst_opt.or_fail(MissingAccount(id: to_id))
      if src.balance < amount
        return Error(InsufficientFunds(available: src.balance, needed: amount))
      end
      var next_src = src
      next_src.balance -= amount
      var next_dst = dst
      next_dst.balance += amount
      t1 = try Table.put(tx, acct, from_id, next_src).map_error(
        fn(e) Db(Ledger.TableFailure(e)) end
      )
      t2 = try Table.put(t1, acct, to_id, next_dst).map_error(fn(e) Db(Ledger.TableFailure(e)) end)
      Ok((t2, next_dst.balance))
    end
  )
end

test "1. accountable writes, indexed audit queries, snapshots, and cold reopen hash verification"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T03:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T03:01:00Z") or stop "t1"
  t2 = Time.parse("2026-11-25T03:02:00Z") or stop "t2"
  acct = accounts_table()
  sc = bank_schema()

  assert Ledger.open(files, "bank.modb", sc, t0) is Ok(db0)
  assert Ledger.audit_count(db0) == 1

  ## Open Ada and Grace accounts (0 balance preserves total=1000 invariant)
  assert Ledger.write(
    db0,
    Ledger.WriteMeta(
      principal: "clerk:ada",
      action: "open_account",
      reason: "onboarding #1",
      at: t1
    ),
    "open account #2 for Ada",
    Json.Object({"id": 2.to_json}),
    fn(tx) Table.put(tx, acct, 2, Account(owner: "Ada", email: "ada@bank.local", balance: 0)) end
  ) is
    Ok(db1)

  assert Ledger.write(
    db1,
    Ledger.WriteMeta(
      principal: "clerk:grace",
      action: "open_account",
      reason: "onboarding #2",
      at: t1
    ),
    "open account #3 for Grace",
    Json.Object({"id": 3.to_json}),
    fn(tx) Table.put(tx, acct, 3, Account(owner: "Grace", email: "grace@bank.local", balance: 0)) end
  ) is
    Ok(db2)

  ## Pin snapshot at seq=3 before transfers
  (db2_pinned, snap) = Ledger.snapshot(db2)

  assert transfer(db2_pinned, 1, 2, 400, "agent:payroll", "payroll-nov", t2) is Ok((db3, 400))
  assert transfer(db3, 2, 3, 150, "clerk:ada", "invoice-99", t2) is Ok((db4, 150))

  assert Ledger.audit_count(db4) == 5
  assert Ledger.verify_all(db4) is Ok(rep)
  assert rep.audit.entry_count == 5
  assert rep.audit.last_seq == 5
  assert rep.invariants_checked == 2

  ## Snapshot still sees only first 3 audit entries
  assert Ledger.snapshot_audit_tail(db4, snap, 10) is Ok(snap_entries)
  assert snap_entries.size == 3
  assert Ledger.release_snapshot(db4, snap) is Ok(db5)

  ## Indexed principal and action queries
  assert Ledger.audit_by_principal(db5, "clerk:ada") is Ok(ada_logs)
  assert ada_logs.size == 2
  assert ada_logs.map(fn(e) e.action end) == ["open_account", "transfer"]

  assert Ledger.audit_by_action(db5, "transfer") is Ok(tx_logs)
  assert tx_logs.size == 2
  assert tx_logs.map(fn(e) e.principal end) == ["agent:payroll", "clerk:ada"]

  assert Ledger.audit_since(db5, 3, 10) is Ok(after3)
  assert after3.map(fn(e) e.seq end) == [4, 5]

  assert Ledger.audit_tail(db5, 2) is Ok(tail2)
  assert tail2.map(fn(e) e.seq end) == [4, 5]

  ## Cold reopen from Files verifies full SHA-256 chain from disk
  assert Ledger.open(files, "bank.modb", sc, t2) is Ok(reopened)
  assert Ledger.audit_count(reopened) == 5
  assert Ledger.verify_all(reopened) is Ok(rep2)
  assert rep2.audit.last_hash == rep.audit.last_hash
end

test "2. commit-time invariants, unique conflicts, and domain errors roll back atomically"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T03:00:00Z") or stop "t0"
  acct = accounts_table()
  sc = bank_schema()

  assert Ledger.open(files, "rollback.modb", sc, t0) is Ok(db0)
  assert Ledger.write(
    db0,
    Ledger.WriteMeta(principal: "admin", action: "open_account", reason: "init", at: t0),
    "open #2",
    Json.Null,
    fn(tx) Table.put(tx, acct, 2, Account(owner: "Ada", email: "ada@bank.local", balance: 0)) end
  ) is
    Ok(db1)
  txid_before = Ledger.txid(db1)

  ## 1) Cross-table conservation invariant blocks minting money out of thin air
  assert Ledger.write(
    db1,
    Ledger.WriteMeta(principal: "rogue", action: "mint", reason: "free money", at: t0),
    "mint +500",
    Json.Null,
    fn(tx) Table.put(tx, acct, 2, Account(owner: "Ada", email: "ada@bank.local", balance: 500)) end
  ) is
    Error(Ledger.InvariantViolation(name: "conservation_of_money", detail: _))

  ## 2) Row invariant blocks negative balance even when conservation holds
  assert Ledger.write(
    db1,
    Ledger.WriteMeta(principal: "rogue", action: "overdraft", reason: "cheat", at: t0),
    "steal 50",
    Json.Null,
    fn(tx)
      t1 = try Table.put(
        tx,
        acct,
        1,
        Account(owner: "Treasury", email: "treasury@bank.local", balance: 1050)
      )
      Table.put(t1, acct, 2, Account(owner: "Ada", email: "ada@bank.local", balance: -50))
    end
  ) is
    Error(Ledger.InvariantViolation(name: "non_negative_balance", detail: _))

  ## 3) Unique email conflict rolls back without adding an audit entry
  assert Ledger.write(
    db1,
    Ledger.WriteMeta(principal: "clerk", action: "open_account", reason: "dup", at: t0),
    "duplicate email",
    Json.Null,
    fn(tx) Table.put(tx, acct, 3, Account(owner: "Clone", email: "ada@bank.local", balance: 0)) end
  ) is
    Error(
      Ledger.TableFailure(Table.UniqueConflict(index: "accounts_by_email", value: "ada@bank.local"))
    )

  ## 4) Domain error from transact rolls back cleanly
  assert transfer(db1, 2, 1, 50, "clerk", "overdraft attempt", t0) is
    Error(InsufficientFunds(available: 0, needed: 50))

  ## Zero side effects across all 4 failed writes
  assert Ledger.txid(db1) == txid_before
  assert Ledger.audit_count(db1) == 2
  assert Table.get(Ledger.store(db1), acct, 2) ==
    Ok(Some(Account(owner: "Ada", email: "ada@bank.local", balance: 0)))
  assert Ledger.verify_all(db1) is Ok(_)
end

test "3. tamper detection catches modified entry, broken hash chain, or deleted audit record"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T03:00:00Z") or stop "t0"
  items = items_table()
  sc = Ledger.schema(0)

  assert Ledger.open(files, "tamper.modb", sc, t0) is Ok(db0)
  assert Ledger.write(
    db0,
    Ledger.WriteMeta(principal: "ada", action: "add", reason: "r1", at: t0),
    "add item 1",
    Json.Null,
    fn(tx) Table.put(tx, items, 1, LedgerItem(title: "One", tag: "a", qty: 1)) end
  ) is
    Ok(db1)
  assert Ledger.write(
    db1,
    Ledger.WriteMeta(principal: "grace", action: "add", reason: "r2", at: t0),
    "add item 2",
    Json.Null,
    fn(tx) Table.put(tx, items, 2, LedgerItem(title: "Two", tag: "b", qty: 2)) end
  ) is
    Ok(db2)
  assert Ledger.verify_audit(db2) is Ok(_)

  ## Tamper A: directly rewrite entry #1 summary in raw Layer 1 bucket (bypassing Ledger)
  assert Ledger.audit_get(db2, 1) is Ok(Some(orig1))
  var forged = orig1
  forged.summary = "FORGED SUMMARY"
  assert Modb.write_tx(
    Ledger.store(db2),
    fn(tx) Modb.tx_put(tx, Ledger.audit_bucket, Table.encode_int_key(1), Json.encode(forged).bytes) end
  ) is
    Ok(tampered_store_a)
  tampered_db_a = Ledger.Db(store: tampered_store_a, schema: sc, state: db2.state)
  assert Ledger.verify_audit(tampered_db_a) is Error(Ledger.AuditCorrupt(reason: _))

  ## Tamper B: delete entry #1 directly from `_modb_audit`
  assert Modb.write_tx(
    Ledger.store(db2),
    fn(tx) Modb.tx_delete(tx, Ledger.audit_bucket, Table.encode_int_key(1)) end
  ) is
    Ok(tampered_store_b)
  tampered_db_b = Ledger.Db(store: tampered_store_b, schema: sc, state: db2.state)
  assert Ledger.verify_audit(tampered_db_b) is Error(Ledger.AuditCorrupt(reason: _))
end

test "4. atomic multi-step schema migrations, rollback on failure, and SchemaTooNew guard"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-25T03:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T03:05:00Z") or stop "t1"
  items = items_table()

  ## Start at v1
  sc_v1 = Ledger.schema(1).with_migration(
    Ledger.migration(
      1,
      "seed v1 item",
      fn(tx) Table.put(tx, items, 1, LedgerItem(title: "Alpha", tag: "legacy", qty: 5)) end
    )
  )
  assert Ledger.open(files, "mig.modb", sc_v1, t0) is Ok(db_v1)
  assert Ledger.schema_version(db_v1) == 1
  assert Ledger.audit_count(db_v1) == 1

  ## Re-opening at v1 is a pure no-op (same txid, same audit count)
  txid_v1 = Ledger.txid(db_v1)
  assert Ledger.open(files, "mig.modb", sc_v1, t1) is Ok(db_v1_again)
  assert Ledger.txid(db_v1_again) == txid_v1
  assert Ledger.audit_count(db_v1_again) == 1

  ## Failed upgrade to v3 (v2 succeeds, v3 breaks invariant) rolls back cleanly to v1!
  sc_bad_v3 = sc_v1.with_migration(
    Ledger.migration(
      2,
      "add v2 item",
      fn(tx) Table.put(tx, items, 2, LedgerItem(title: "Beta", tag: "v2", qty: 3)) end
    )
  ).with_migration(
    Ledger.migration(
      3,
      "bad v3 negative qty",
      fn(tx) Table.put(tx, items, 3, LedgerItem(title: "Broken", tag: "v3", qty: -9)) end
    )
  ).with_invariant(
    Ledger.row_invariant(
      "qty_non_negative",
      items,
      fn(id, it) if it.qty < 0: Some("item #{id} has negative qty") else: None end
    )
  )
  var bad_sc = sc_bad_v3
  bad_sc.target_version = 3
  assert Ledger.open(files, "mig.modb", bad_sc, t1) is
    Error(Ledger.InvariantViolation(name: "qty_non_negative", detail: _))

  ## Verify database remained completely untouched at v1
  assert Ledger.open(files, "mig.modb", sc_v1, t1) is Ok(still_v1)
  assert Ledger.schema_version(still_v1) == 1
  assert Ledger.audit_count(still_v1) == 1
  assert Table.get(Ledger.store(still_v1), items, 2) == Ok(None)

  ## Valid atomic upgrade v1 -> v2 -> v3
  var sc_v3 = Ledger.schema(3).with_migration(
    Ledger.migration(
      1,
      "seed v1 item",
      fn(tx) Table.put(tx, items, 1, LedgerItem(title: "Alpha", tag: "legacy", qty: 5)) end
    )
  ).with_migration(
    Ledger.migration(
      2,
      "retag legacy items",
      fn(tx)
        rows = try Table.tx_scan(tx, items, None, None, 0)
        var cur = tx
        for (id, it) in rows
          var upgraded = it
          upgraded.tag = "migrated-v2"
          cur = try Table.put(cur, items, id, upgraded)
        end
        Ok(cur)
      end
    )
  ).with_migration(
    Ledger.migration(
      3,
      "add v3 item",
      fn(tx) Table.put(tx, items, 2, LedgerItem(title: "Gamma", tag: "v3", qty: 7)) end
    )
  ).with_invariant(
    Ledger.row_invariant(
      "qty_non_negative",
      items,
      fn(id, it) if it.qty < 0: Some("item #{id} has negative qty") else: None end
    )
  )
  assert Ledger.open(files, "mig.modb", sc_v3, t1) is Ok(db_v3)
  assert Ledger.schema_version(db_v3) == 3
  assert Ledger.audit_count(db_v3) == 3
  assert Table.get(Ledger.store(db_v3), items, 1) ==
    Ok(Some(LedgerItem(title: "Alpha", tag: "migrated-v2", qty: 5)))
  assert Table.get(Ledger.store(db_v3), items, 2) ==
    Ok(Some(LedgerItem(title: "Gamma", tag: "v3", qty: 7)))
  assert Ledger.verify_all(db_v3) is Ok(_)

  ## Opening v3 DB with older v1 schema is rejected with SchemaTooNew
  assert Ledger.open(files, "mig.modb", sc_v1, t1) is
    Error(Ledger.SchemaTooNew(found: 3, supported: 1))

  ## Schema with missing migration step is rejected
  gap_sc = Ledger.schema(2).with_migration(Ledger.migration(2, "missing v1", fn(tx) Ok(tx) end))
  files2 = Files.in_memory({})
  assert Ledger.open(files2, "gap.modb", gap_sc, t0) is Error(Ledger.InvalidMigration(reason: _))
end

test "5. 500-crash deterministic fault-injection simulation preserves atomic data+audit parity"
  rng = Random.seeded(20261125)
  t0 = Time.parse("2026-11-25T03:00:00Z") or stop "t0"
  acct = accounts_table()
  sc = bank_schema()

  ## Initialize a simulated disk with Treasury (#1: 1000) and Ada (#2: 0)
  assert Ledger.open_disk(Pager.sim_empty(), sc, t0) is Ok(db0)
  assert Ledger.write(
    db0,
    Ledger.WriteMeta(principal: "init", action: "open_account", reason: "seed", at: t0),
    "open #2",
    Json.Null,
    fn(tx) Table.put(tx, acct, 2, Account(owner: "Ada", email: "ada@bank.local", balance: 0)) end
  ) is
    Ok(db1)

  var db = db1
  var committed_ada = 0
  var committed_seq = 2
  var phase2_survived = 0
  var phase2_rolled_back = 0

  for i in 0..500
    phase = if i % 2 == 0: 1 else: 2
    delta = if committed_ada >= 500: -1 else: 1
    next_ada = committed_ada + delta
    next_treasury = 1000 - next_ada
    meta = Ledger.WriteMeta(
      principal: if i % 3 == 0: "agent:a" else: "agent:b",
      action: "move",
      reason: "crash-step-#{i}",
      at: t0
    )

    assert Ledger.write_and_crash(
      db,
      meta,
      "ada -> #{next_ada}",
      next_ada.to_json,
      phase,
      rng,
      fn(tx)
        t1 = try Table.put(
          tx,
          acct,
          1,
          Account(owner: "Treasury", email: "treasury@bank.local", balance: next_treasury)
        )
        Table.put(t1, acct, 2, Account(owner: "Ada", email: "ada@bank.local", balance: next_ada))
      end
    ) is
      Ok(crashed_disk)

    ## Reopen from crashed disk and assert full B+Tree + audit hash-chain + invariant verification
    assert Ledger.open_disk(crashed_disk, sc, t0) is Ok(rec)
    assert Ledger.verify_all(rec) is Ok(rep)
    assert Table.get(Ledger.store(rec), acct, 2) is Ok(Some(rec_ada))

    if phase == 1
      ## Crash before data sync MUST always roll back cleanly to committed state
      assert rec_ada.balance == committed_ada
      assert rep.audit.last_seq == committed_seq
    else
      ## Crash after data sync & meta write MUST either cleanly commit BOTH or roll back BOTH
      if rep.audit.last_seq == committed_seq + 1
        assert rec_ada.balance == next_ada
        committed_ada = next_ada
        committed_seq = rep.audit.last_seq
        phase2_survived += 1
      else
        assert rep.audit.last_seq == committed_seq
        assert rec_ada.balance == committed_ada
        phase2_rolled_back += 1
      end
    end
    db = rec
  end

  ## Ensure our crash simulation genuinely exercised both atomic commit and atomic rollback paths
  assert phase2_survived > 0
  assert phase2_rolled_back > 0
end
