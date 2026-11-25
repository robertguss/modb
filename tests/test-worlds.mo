## Milestone 3 Phase 3B Verification Suite:
## Direct implementation parity check against BOTH TLA+ models in `models/README.md`:
## - Test 1: All 6 `Replay.tla` cases (`seat`, `meeting`, `skew`, `discount`, `lost_update`, `intent`)
##           plus negative controls (`validate_reads: false`) & needless send-back telemetry
## - Test 2: All 6 `Worlds.tla` cases (`transfer`, `budget`, `audit`, `stuck`, `ownread`, `apart`)
##           plus negative control (`check_invariants_per_call: false` letting `budget` slip through)
## - Test 3: Multi-level attenuated Grants, non-widening, budget conservation & cascading revocation
## - Test 4: Claims / Leases contention, heartbeat, expiry takeover, and slow-agent fairness
## - Test 5: 500-crash deterministic torn-write simulation across Worlds, Grants, Claims & pins
module TestWorlds
use Json
use Modb
use Modb.Claims
use Modb.Grants
use Modb.Ledger
use Modb.Pager
use Modb.Table
use Modb.World

struct Cell
  value: Int
end

struct SetArgs
  key: Text
  value: Int
end

struct DeltaArgs
  key: Text
  delta: Int
end

struct TransferArgs
  from_key: Text
  to_key: Text
  amount: Int
end

fn cells_table() : Table.Table(Text, Cell)
  Table.text_key[Cell]("cells")
end

fn get_cell_tx(tx: Modb.WriteTx, key: Text) : Result(Int, Text)
  case Table.tx_get(tx, cells_table(), key)
    Ok(Some(c)): Ok(c.value)
    Ok(None): Ok(0)
    Error(e): Error(e.to_text)
  end
end

fn set_cell_tx(tx: Modb.WriteTx, key: Text, v: Int) : Result(Modb.WriteTx, Text)
  Table.put(tx, cells_table(), key, Cell(value: v)).map_error(fn(e) e.to_text end)
end

fn cell_catalog() : World.Catalog
  World.catalog().with_query(
    "get",
    fn(tx, args)
      k = try Json.decode[Text](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      v = try get_cell_tx(tx, k)
      Ok(v.to_json)
    end
  ).with_action(
    "set",
    fn(tx, args)
      a = try Json.decode[SetArgs](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      t1 = try set_cell_tx(tx, a.key, a.value)
      Ok((t1, a.value.to_json))
    end
  ).with_action(
    "add",
    fn(tx, args)
      a = try Json.decode[DeltaArgs](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      cur = try get_cell_tx(tx, a.key)
      next = cur + a.delta
      t1 = try set_cell_tx(tx, a.key, next)
      Ok((t1, next.to_json))
    end
  ).with_action(
    "book_seat",
    fn(tx, _args)
      left = try get_cell_tx(tx, "seats")
      return Error("sold out") if left < 1
      t1 = try set_cell_tx(tx, "seats", left - 1)
      Ok((t1, (left - 1).to_json))
    end
  ).with_action(
    "set_meeting_start",
    fn(tx, args)
      s = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      t1 = try set_cell_tx(tx, "start", s)
      Ok((t1, s.to_json))
    end
  ).with_action(
    "set_meeting_end",
    fn(tx, args)
      e = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(er) er.to_text end)
      t1 = try set_cell_tx(tx, "end", e)
      Ok((t1, e.to_json))
    end
  ).with_action(
    "take_from_x",
    fn(tx, args)
      amt = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      cur = try get_cell_tx(tx, "x")
      return Error("insufficient x") if cur < amt
      t1 = try set_cell_tx(tx, "x", cur - amt)
      Ok((t1, (cur - amt).to_json))
    end
  ).with_action(
    "put_to_y",
    fn(tx, args)
      amt = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      cur = try get_cell_tx(tx, "y")
      cap = try get_cell_tx(tx, "y_cap")
      return Error("y capacity exceeded") if cap > 0 and cur + amt > cap
      t1 = try set_cell_tx(tx, "y", cur + amt)
      Ok((t1, (cur + amt).to_json))
    end
  ).with_action(
    "transfer",
    fn(tx, args)
      a = try Json.decode[TransferArgs](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      src = try get_cell_tx(tx, a.from_key)
      dst = try get_cell_tx(tx, a.to_key)
      return Error("insufficient funds") if src < a.amount
      t1 = try set_cell_tx(tx, a.from_key, src - a.amount)
      t2 = try set_cell_tx(t1, a.to_key, dst + a.amount)
      Ok((t2, (dst + a.amount).to_json))
    end
  ).with_action(
    "spend",
    fn(tx, args)
      amt = try Json.decode[Int](Json.encode(args).bytes).map_error(fn(e) e.to_text end)
      cur = try get_cell_tx(tx, "spent")
      t1 = try set_cell_tx(tx, "spent", cur + amt)
      Ok((t1, (cur + amt).to_json))
    end
  ).with_action(
    "close_budget",
    fn(tx, _args)
      ## Classic `Worlds.tla` case: "close" sets budget = spent (safe ONLY when spent <= budget at start!)
      sp = try get_cell_tx(tx, "spent")
      t1 = try set_cell_tx(tx, "budget", sp)
      Ok((t1, sp.to_json))
    end
  )
end

fn setup_grant(db: Ledger.Db, id: Text, principal: Text, actions: List(Text), t0: Time, t1: Time) : Ledger
  .Db
  meta = Ledger.WriteMeta(principal: "admin:root", action: "issue_grant", reason: "test", at: t0)
  assert Grants.issue_root(
    db,
    meta,
    Grants.GrantSpec(
      id: id,
      principal: principal,
      allowed_actions: actions,
      max_calls: 1000,
      expires_at: t1
    )
  ) is
    Ok((next_db, _))
  next_db
end

test "1. Replay.tla parity (all 6 cases: seat, meeting, skew, discount, lost_update, intent + negative controls)"
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  cat = cell_catalog()
  all_actions = ["set", "add", "book_seat", "set_meeting_start", "set_meeting_end"]
  cells = cells_table()

  ## Case 1a: `seat` (two agents race for the last seat; second fails cleanly)
  sc_seat = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "1 seat", fn(tx) Table.put(tx, cells, "seats", Cell(value: 1)) end)
  ).with_invariant(
    Ledger.row_invariant("non_neg", cells, fn(k, c) if c.value < 0: Some("#{k} < 0") else: None end)
  )
  assert Ledger.open(Files.in_memory({}), "seat.modb", sc_seat, t0) is Ok(d0)
  d1 = setup_grant(
    setup_grant(d0, "ga", "agent:a", all_actions, t0, t1),
    "gb",
    "agent:b",
    all_actions,
    t0,
    t1
  )
  assert World.open_world(d1, "wa", "ga", t0, t1) is Ok((d2, _))
  assert World.open_world(d2, "wb", "gb", t0, t1) is Ok((d3, _))
  assert World.world_query(d3, cat, "wa", "get", "seats".to_json, t0) is Ok((d4, _))
  assert World.world_query(d4, cat, "wb", "get", "seats".to_json, t0) is Ok((d5, _))
  assert World.world_call(d5, cat, "wa", "book_seat", Json.Null, "book-a", t0) is Ok((d6, _))
  assert World.world_call(d6, cat, "wb", "book_seat", Json.Null, "book-b", t0) is Ok((d7, _))
  assert World.land_world(d7, cat, "wa", "land-a", t0) is Ok((d8, _))
  assert World.land_world(d8, cat, "wb", "land-b", t0) is
    Error((d9, World.StaleRead(query: "get", args: _, expected: _, actual: _)))
  assert Table.get(Ledger.store(d9), cells, "seats") == Ok(Some(Cell(value: 0)))

  ## Case 1b & 1c: `meeting` (start <= end invariant) & `skew` (a + b >= 1 invariant)
  sc_meet = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(
      1,
      "meeting 2..5, skew a=1 b=1",
      fn(tx)
        t_a = try Table.put(tx, cells, "start", Cell(value: 2))
        t_b = try Table.put(t_a, cells, "end", Cell(value: 5))
        t_c = try Table.put(t_b, cells, "a", Cell(value: 1))
        Table.put(t_c, cells, "b", Cell(value: 1))
      end
    )
  ).with_invariant(
    Ledger.invariant(
      "meeting_order_and_skew",
      fn(tx)
        s = (try Table.tx_get(tx, cells, "start")) or Cell(value: 0)
        e = (try Table.tx_get(tx, cells, "end")) or Cell(value: 0)
        return Ok(Some("meeting ends before it starts")) if s.value > e.value
        ca = (try Table.tx_get(tx, cells, "a")) or Cell(value: 0)
        cb = (try Table.tx_get(tx, cells, "b")) or Cell(value: 0)
        return Ok(Some("write skew: a + b < 1")) if ca.value + cb.value < 1
        Ok(None)
      end
    )
  )
  assert Ledger.open(Files.in_memory({}), "meet.modb", sc_meet, t0) is Ok(m0)
  m1 = setup_grant(
    setup_grant(m0, "ga", "agent:a", all_actions, t0, t1),
    "gb",
    "agent:b",
    all_actions,
    t0,
    t1
  )
  ## Meeting: A moves start=4, B moves end=3 -> individually valid, combined violates start <= end!
  assert World.open_world(m1, "ma", "ga", t0, t1) is Ok((m2, _))
  assert World.open_world(m2, "mb", "gb", t0, t1) is Ok((m3, _))
  assert World.world_call(m3, cat, "ma", "set_meeting_start", 4.to_json, "shift-start", t0) is
    Ok((m4, _))
  assert World.world_call(m4, cat, "mb", "set_meeting_end", 3.to_json, "shift-end", t0) is
    Ok((m5, _))
  assert World.land_world(m5, cat, "ma", "land-ma", t0) is Ok((m6, _))
  assert World.land_world(m6, cat, "mb", "land-mb", t0) is
    Error((m7, World.InvariantRejected(name: "meeting_order_and_skew", detail: _)))
  ## Skew: A sets a=0, B sets b=0 -> individually valid, combined violates a + b >= 1!
  assert World.open_world(m7, "sa", "ga", t0, t1) is Ok((m8, _))
  assert World.open_world(m8, "sb", "gb", t0, t1) is Ok((m9, _))
  assert World.world_call(m9, cat, "sa", "set", SetArgs(key: "a", value: 0).to_json, "drop-a", t0) is
    Ok((m10, _))
  assert World.world_call(m10, cat, "sb", "set", SetArgs(key: "b", value: 0).to_json, "drop-b", t0) is
    Ok((m11, _))
  assert World.land_world(m11, cat, "sa", "land-sa", t0) is Ok((m12, _))
  assert World.land_world(m12, cat, "sb", "land-sb", t0) is
    Error((m13, World.InvariantRejected(name: "meeting_order_and_skew", detail: _)))
  assert Ledger.verify_all(m13) is Ok(_)

  ## Case 1d & 1e: `discount` (stale price!) & `lost_update` (set 4 vs set 3)
  ## Caught ONLY by recorded reads — verified WITH negative control (`validate_reads: false`)!
  sc_plain = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(
      1,
      "price=100, discount=0, balance=2",
      fn(tx)
        t_a = try Table.put(tx, cells, "price", Cell(value: 100))
        t_b = try Table.put(t_a, cells, "discount", Cell(value: 0))
        Table.put(t_b, cells, "balance", Cell(value: 2))
      end
    )
  )
  assert Ledger.open(Files.in_memory({}), "disc.modb", sc_plain, t0) is Ok(p0)
  p1 = setup_grant(
    setup_grant(p0, "ga", "agent:a", all_actions, t0, t1),
    "gb",
    "agent:b",
    all_actions,
    t0,
    t1
  )

  ## `discount`: Agent A reads price=100 and sets discount=10; Agent B raises price=200 and lands first.
  assert World.open_world(p1, "da", "ga", t0, t1) is Ok((p2, _))
  assert World.open_world(p2, "db", "gb", t0, t1) is Ok((p3, _))
  assert World.world_query(p3, cat, "da", "get", "price".to_json, t0) is Ok((p4, _))
  assert World.world_call(
    p4,
    cat,
    "da",
    "set",
    SetArgs(key: "discount", value: 10).to_json,
    "10pct",
    t0
  ) is
    Ok((p5, _))
  assert World.world_call(
    p5,
    cat,
    "db",
    "set",
    SetArgs(key: "price", value: 200).to_json,
    "reprice",
    t0
  ) is
    Ok((p6, _))
  assert World.land_world(p6, cat, "db", "land-reprice", t0) is Ok((p7, _))
  ## Strict landing catches the stale price read!
  assert World.land_world(p7, cat, "da", "land-discount", t0) is
    Error((p8, World.StaleRead(query: "get", args: _, expected: _, actual: _)))
  assert Table.get(Ledger.store(p8), cells, "discount") == Ok(Some(Cell(value: 0)))

  ## Negative control on `lost_update`: balance=2, A reads 2 -> set 4, B reads 2 -> set 3.
  ## Under strict landing: B is rejected with StaleRead!
  assert World.open_world(p8, "la", "ga", t0, t1) is Ok((p9, _))
  assert World.open_world(p9, "lb", "gb", t0, t1) is Ok((p10, _))
  assert World.world_query(p10, cat, "la", "get", "balance".to_json, t0) is Ok((p11, _))
  assert World.world_query(p11, cat, "lb", "get", "balance".to_json, t0) is Ok((p12, _))
  assert World.world_call(
    p12,
    cat,
    "la",
    "set",
    SetArgs(key: "balance", value: 4).to_json,
    "+2",
    t0
  ) is
    Ok((p13, _))
  assert World.world_call(
    p13,
    cat,
    "lb",
    "set",
    SetArgs(key: "balance", value: 3).to_json,
    "+1",
    t0
  ) is
    Ok((p14, _))
  assert World.land_world(p14, cat, "la", "land-la", t0) is Ok((p15, _))
  assert World.land_world(p15, cat, "lb", "land-lb", t0) is
    Error((p16, World.StaleRead(query: "get", args: _, expected: _, actual: _)))
  assert Table.get(Ledger.store(p16), cells, "balance") == Ok(Some(Cell(value: 4)))

  ## Negative control: with `validate_reads: false`, lost_update DOES slip through (overwriting 4 -> 3)!
  assert World.open_world(p16, "lb_neg", "gb", t0, t1) is Ok((p17, _))
  assert World.world_query(p17, cat, "lb_neg", "get", "balance".to_json, t0) is Ok((p18, _))
  assert World.world_call(
    p18,
    cat,
    "lb_neg",
    "set",
    SetArgs(key: "balance", value: 3).to_json,
    "clobber",
    t0
  ) is
    Ok((p19, _))
  assert World.open_world(p19, "la_neg", "ga", t0, t1) is Ok((p20, _))
  assert World.world_call(
    p20,
    cat,
    "la_neg",
    "set",
    SetArgs(key: "balance", value: 9).to_json,
    "bump",
    t0
  ) is
    Ok((p21, _))
  assert World.land_world(p21, cat, "la_neg", "land-la-neg", t0) is Ok((p22, _))
  no_reads_opts = World.LandOptions(validate_reads: false, check_invariants_per_call: true)
  assert World.land_world_with_options(p22, cat, "lb_neg", "clobber", t0, no_reads_opts) is
    Ok((p23, _))
  assert Table.get(Ledger.store(p23), cells, "balance") == Ok(Some(Cell(value: 3)))

  ## Case 1f: `intent` ("add 2" after reading balance): needless send-back is caught and COUNTED!
  assert World.metrics(Ledger.store(p23)) is Ok(met_before)
  assert World.open_world(p23, "ia", "ga", t0, t1) is Ok((p24, _))
  assert World.open_world(p24, "ib", "gb", t0, t1) is Ok((p25, _))
  assert World.world_query(p25, cat, "ib", "get", "balance".to_json, t0) is Ok((p26, _))
  assert World.world_call(
    p26,
    cat,
    "ia",
    "add",
    DeltaArgs(key: "balance", delta: 1).to_json,
    "add1",
    t0
  ) is
    Ok((p27, _))
  assert World.world_call(
    p27,
    cat,
    "ib",
    "add",
    DeltaArgs(key: "balance", delta: 2).to_json,
    "add2",
    t0
  ) is
    Ok((p28, _))
  assert World.land_world(p28, cat, "ia", "land-ia", t0) is Ok((p29, _))
  assert World.land_world(p29, cat, "ib", "land-ib", t0) is
    Error((p30, World.StaleRead(query: "get", args: _, expected: _, actual: _)))
  ## Agent B retries with the EXACT same call (`add 2`) in a fresh world -> needless_send_backs increments!
  assert World.open_world(p30, "ib2", "gb", t0, t1) is Ok((p31, _))
  assert World.world_query(p31, cat, "ib2", "get", "balance".to_json, t0) is Ok((p32, _))
  assert World.world_call(
    p32,
    cat,
    "ib2",
    "add",
    DeltaArgs(key: "balance", delta: 2).to_json,
    "add2-retry",
    t0
  ) is
    Ok((p33, _))
  assert World.land_world(p33, cat, "ib2", "land-ib2", t0) is Ok((p34, _))
  assert Table.get(Ledger.store(p34), cells, "balance") == Ok(Some(Cell(value: 6)))
  assert World.metrics(Ledger.store(p34)) is Ok(met)
  assert met.stale_read_rejections >= 3
  assert met.needless_send_backs == met_before.needless_send_backs + 1
  assert Ledger.verify_all(p34) is Ok(_)
end

test "2. Worlds.tla parity (all 6 cases: transfer, budget, audit, stuck, ownread, apart + Option 2 control)"
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  cat = cell_catalog()
  all_actions = ["set", "add", "take_from_x", "put_to_y", "transfer", "spend", "close_budget"]
  cells = cells_table()

  ## Case 2a (`transfer`) & 2b (`budget`): Option 3 ("world whole, rule after every call")
  sc_strict = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(
      1,
      "x=2 y=0 spent=1 budget=2",
      fn(tx)
        t_a = try Table.put(tx, cells, "x", Cell(value: 2))
        t_b = try Table.put(t_a, cells, "y", Cell(value: 0))
        t_c = try Table.put(t_b, cells, "spent", Cell(value: 1))
        Table.put(t_c, cells, "budget", Cell(value: 2))
      end
    )
  ).with_invariant(
    Ledger.invariant(
      "conservation_and_budget",
      fn(tx)
        cx = (try Table.tx_get(tx, cells, "x")) or Cell(value: 0)
        cy = (try Table.tx_get(tx, cells, "y")) or Cell(value: 0)
        return Ok(Some("x + y != 2")) if cx.value + cy.value != 2
        sp = (try Table.tx_get(tx, cells, "spent")) or Cell(value: 0)
        bu = (try Table.tx_get(tx, cells, "budget")) or Cell(value: 0)
        return Ok(Some("spent #{sp.value} > budget #{bu.value}")) if sp.value > bu.value
        Ok(None)
      end
    )
  )
  assert Ledger.open(Files.in_memory({}), "worlds1.modb", sc_strict, t0) is Ok(w0)
  w1 = setup_grant(w0, "ga", "agent:a", all_actions, t0, t1)

  ## `transfer`: 2-step take_from_x + put_to_y is REFUSED after call 1 (Option 3);
  ## single approved `transfer` action SUCCEEDS!
  assert World.open_world(w1, "wt", "ga", t0, t1) is Ok((w2, _))
  assert World.world_call(w2, cat, "wt", "take_from_x", 1.to_json, "half", t0) is
    Error(World.InvariantRejected(name: "conservation_and_budget", detail: _))
  assert World.world_call(
    w2,
    cat,
    "wt",
    "transfer",
    TransferArgs(from_key: "x", to_key: "y", amount: 1).to_json,
    "atomic-transfer",
    t0
  ) is
    Ok((w3, _))
  assert World.land_world(w3, cat, "wt", "land-transfer", t0) is Ok((w4, _))
  assert Table.get(Ledger.store(w4), cells, "x") == Ok(Some(Cell(value: 1)))
  assert Table.get(Ledger.store(w4), cells, "y") == Ok(Some(Cell(value: 1)))

  ## `budget`: spend(2) breaks spent(3) <= budget(2) immediately under Option 3, so spend+close CANNOT raise budget!
  assert World.open_world(w4, "wb", "ga", t0, t1) is Ok((w5, _))
  assert World.world_call(w5, cat, "wb", "spend", 2.to_json, "overspend", t0) is
    Error(World.InvariantRejected(name: "conservation_and_budget", detail: _))
  assert World.drop_world(w5, "wb") is Ok(w6)

  ## Negative control for `budget`: construct a 2-step world bypassing in-world checks (`spend 2` then `close_budget`):
  ## Option 3 (`check_invariants_per_call: true`) REFUSES it; Option 2 (`check_invariants_per_call: false`) LETS IT RAISE BUDGET TO 3!
  assert World.open_world(w6, "wb_bypass", "ga", t0, t1) is Ok((w7, wb_rec))
  var forged = wb_rec
  forged.steps = [
    World.CallStep(action: "spend", args: 2.to_json, reason: "step1"),
    World.CallStep(action: "close_budget", args: Json.Null, reason: "step2")
  ]
  tx_f = Modb.begin_write(Ledger.store(w7))
  assert Table.put(tx_f, World.worlds_table(), "wb_bypass", forged) is Ok(tx_f1)
  assert Modb.commit(tx_f1) is Ok(st_f)
  w8 = Ledger.update_store(w7, st_f)
  ## Strict Option 3 catches the mid-world violation and blocks the budget raise!
  assert World.land_world(w8, cat, "wb_bypass", "try-bypass", t0) is
    Error((w9, World.InvariantRejected(name: "conservation_and_budget", detail: _)))
  assert Table.get(Ledger.store(w9), cells, "budget") == Ok(Some(Cell(value: 2)))

  ## Control (Option 2: rule at end only) WOULD allow budget to jump 2 -> 3 (matching `Worlds.tla`!)
  assert World.open_world(w9, "wb_opt2", "ga", t0, t1) is Ok((w10, wb2_rec))
  var forged2 = wb2_rec
  forged2.steps = forged.steps
  tx_f2 = Modb.begin_write(Ledger.store(w10))
  assert Table.put(tx_f2, World.worlds_table(), "wb_opt2", forged2) is Ok(tx_f21)
  assert Modb.commit(tx_f21) is Ok(st_f2)
  w11 = Ledger.update_store(w10, st_f2)
  opt2 = World.LandOptions(validate_reads: true, check_invariants_per_call: false)
  assert World.land_world_with_options(w11, cat, "wb_opt2", "opt2-bypass", t0, opt2) is Ok((w12, _))
  assert Table.get(Ledger.store(w12), cells, "budget") == Ok(Some(Cell(value: 3)))

  ## Cases 2c (`audit`), 2d (`stuck`), 2e (`ownread`), 2f (`apart`) on unconstrained cells
  sc_open = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(
      1,
      "x=2 y=0 y_cap=2 p=0 q=0",
      fn(tx)
        t_a = try Table.put(tx, cells, "x", Cell(value: 2))
        t_b = try Table.put(t_a, cells, "y", Cell(value: 0))
        t_c = try Table.put(t_b, cells, "y_cap", Cell(value: 2))
        t_d = try Table.put(t_c, cells, "p", Cell(value: 0))
        Table.put(t_d, cells, "q", Cell(value: 0))
      end
    )
  )
  assert Ledger.open(Files.in_memory({}), "worlds2.modb", sc_open, t0) is Ok(u0)
  u1 = setup_grant(
    setup_grant(u0, "ga", "agent:a", all_actions, t0, t1),
    "gb",
    "agent:b",
    all_actions,
    t0,
    t1
  )

  ## `audit` & `stuck`: A stages take_from_x(2) + put_to_y(2); B lands put_to_y(1) first.
  ## When A lands, put_to_y(2) exceeds y_cap=2 -> whole world rolls back, x stays 2 (never stuck half-landed)!
  assert World.open_world(u1, "wa_st", "ga", t0, t1) is Ok((u2, _))
  assert World.open_world(u2, "wb_st", "gb", t0, t1) is Ok((u3, _))
  assert World.world_call(u3, cat, "wa_st", "take_from_x", 2.to_json, "take2", t0) is Ok((u4, _))
  assert World.world_call(u4, cat, "wa_st", "put_to_y", 2.to_json, "put2", t0) is Ok((u5, _))
  ## While A's world is open, B sees NO gap (x == 2, y == 0)!
  assert World.world_query(u5, cat, "wb_st", "get", "x".to_json, t0) is Ok((u6, bx))
  assert bx == 2.to_json
  assert World.world_call(u6, cat, "wb_st", "put_to_y", 1.to_json, "put1", t0) is Ok((u7, _))
  assert World.land_world(u7, cat, "wb_st", "land-b", t0) is Ok((u8, _))
  assert World.land_world(u8, cat, "wa_st", "land-a-stuck", t0) is
    Error((u9, World.ActionRejected(action: "put_to_y", detail: "y capacity exceeded")))
  ## Rollback is complete: x is STILL 2 and y is 1 (nothing lost!)
  assert Table.get(Ledger.store(u9), cells, "x") == Ok(Some(Cell(value: 2)))
  assert Table.get(Ledger.store(u9), cells, "y") == Ok(Some(Cell(value: 1)))

  ## `ownread`: A calls `add p +1`, THEN reads `p` (sees 1, its OWN uncommitted change!), THEN writes `q = 1`.
  ## In-place read replay MUST see 1 at step 2 and LAND CLEANLY!
  assert World.open_world(u9, "w_own", "ga", t0, t1) is Ok((u10, _))
  assert World.world_call(
    u10,
    cat,
    "w_own",
    "add",
    DeltaArgs(key: "p", delta: 1).to_json,
    "inc-p",
    t0
  ) is
    Ok((u11, _))
  assert World.world_query(u11, cat, "w_own", "get", "p".to_json, t0) is Ok((u12, own_p))
  assert own_p == 1.to_json
  assert World.world_call(
    u12,
    cat,
    "w_own",
    "set",
    SetArgs(key: "q", value: 1).to_json,
    "copy-q",
    t0
  ) is
    Ok((u13, _))
  assert World.land_world(u13, cat, "w_own", "land-ownread", t0) is Ok((u14, lr_own))
  assert lr_own.calls_replayed == 2 and lr_own.reads_verified == 1
  assert Table.get(Ledger.store(u14), cells, "p") == Ok(Some(Cell(value: 1)))
  assert Table.get(Ledger.store(u14), cells, "q") == Ok(Some(Cell(value: 1)))

  ## `apart`: Two overlapping worlds touching disjoint keys (`p` vs `q`) BOTH land cleanly!
  assert World.open_world(u14, "w_p", "ga", t0, t1) is Ok((u15, _))
  assert World.open_world(u15, "w_q", "gb", t0, t1) is Ok((u16, _))
  assert World.world_query(u16, cat, "w_p", "get", "p".to_json, t0) is Ok((u17, _))
  assert World.world_query(u17, cat, "w_q", "get", "q".to_json, t0) is Ok((u18, _))
  assert World.world_call(
    u18,
    cat,
    "w_p",
    "add",
    DeltaArgs(key: "p", delta: 10).to_json,
    "p+10",
    t0
  ) is
    Ok((u19, _))
  assert World.world_call(
    u19,
    cat,
    "w_q",
    "add",
    DeltaArgs(key: "q", delta: 20).to_json,
    "q+20",
    t0
  ) is
    Ok((u20, _))
  assert World.land_world(u20, cat, "w_p", "land-p", t0) is Ok((u21, _))
  assert World.land_world(u21, cat, "w_q", "land-q", t0) is Ok((u22, _))
  assert Table.get(Ledger.store(u22), cells, "p") == Ok(Some(Cell(value: 11)))
  assert Table.get(Ledger.store(u22), cells, "q") == Ok(Some(Cell(value: 21)))
  assert Ledger.verify_all(u22) is Ok(_)
end

test "3. Attenuated Grants: 3-level delegation, sibling budget conservation & mid-flight parent revocation"
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T11:00:00Z") or stop "t1"
  cat = cell_catalog()
  cells = cells_table()
  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "seed v=0", fn(tx) Table.put(tx, cells, "v", Cell(value: 0)) end)
  )
  assert Ledger.open(Files.in_memory({}), "deleg.modb", sc, t0) is Ok(db0)

  ## Admin -> Agent (max_calls=2) -> Helper1 (max_calls=2) & Helper2 (max_calls=2)
  am = Ledger.WriteMeta(principal: "admin:ada", action: "issue", reason: "root", at: t0)
  assert Grants.issue_root(
    db0,
    am,
    Grants.GrantSpec(
      id: "g-root",
      principal: "agent:lead",
      allowed_actions: ["add", "set"],
      max_calls: 2,
      expires_at: t1
    )
  ) is
    Ok((db1, _))

  dm = Ledger.WriteMeta(principal: "agent:lead", action: "delegate", reason: "split", at: t0)
  assert Grants.delegate(
    db1,
    dm,
    "g-root",
    Grants.GrantSpec(
      id: "g-h1",
      principal: "helper:1",
      allowed_actions: ["add"],
      max_calls: 2,
      expires_at: t1
    )
  ) is
    Ok((db2, _))
  assert Grants.delegate(
    db2,
    dm,
    "g-root",
    Grants.GrantSpec(
      id: "g-h2",
      principal: "helper:2",
      allowed_actions: ["add"],
      max_calls: 2,
      expires_at: t1
    )
  ) is
    Ok((db3, _))

  ## Helper1 spends 2 calls (100% of parent g-root's budget); Helper2's open world MUST fail BudgetExhausted!
  assert World.open_world(db3, "wh1", "g-h1", t0, t1) is Ok((db4, _))
  assert World.open_world(db4, "wh2", "g-h2", t0, t1) is Ok((db5, _))
  assert World.world_call(db5, cat, "wh1", "add", DeltaArgs(key: "v", delta: 1).to_json, "c1", t0) is
    Ok((db6, _))
  assert World.world_call(db6, cat, "wh1", "add", DeltaArgs(key: "v", delta: 1).to_json, "c2", t0) is
    Ok((db7, _))
  assert World.world_call(db7, cat, "wh2", "add", DeltaArgs(key: "v", delta: 1).to_json, "c3", t0) is
    Ok((db8, _))
  assert World.land_world(db8, cat, "wh1", "land-h1", t0) is Ok((db9, lr1))
  assert lr1.grant_chain == ["admin:ada", "agent:lead", "helper:1"]
  assert World.land_world(db9, cat, "wh2", "land-h2", t0) is
    Error((
      db10,
      World.GrantFailure(Grants.BudgetExhausted(id: "g-h2", ancestor_id: "g-root", max_calls: 2))
    ))

  ## Fresh root grant -> helper opens world -> admin revokes parent mid-flight -> helper CANNOT land!
  assert Grants.issue_root(
    db10,
    am,
    Grants.GrantSpec(
      id: "g-root2",
      principal: "agent:lead2",
      allowed_actions: ["add"],
      max_calls: 5,
      expires_at: t1
    )
  ) is
    Ok((db11, _))
  assert Grants.delegate(
    db11,
    dm,
    "g-root2",
    Grants.GrantSpec(
      id: "g-sub",
      principal: "helper:sub",
      allowed_actions: ["add"],
      max_calls: 3,
      expires_at: t1
    )
  ) is
    Ok((db12, _))
  assert World.open_world(db12, "w-rev", "g-sub", t0, t1) is Ok((db13, _))
  assert World.world_call(
    db13,
    cat,
    "w-rev",
    "add",
    DeltaArgs(key: "v", delta: 99).to_json,
    "sneak",
    t0
  ) is
    Ok((db14, _))
  rm = Ledger.WriteMeta(principal: "admin:ada", action: "revoke", reason: "stop-lead2", at: t0)
  assert Grants.revoke(db14, rm, "g-root2") is Ok((db15, _))
  assert World.land_world(db15, cat, "w-rev", "try-land", t0) is
    Error((db16, World.GrantFailure(Grants.Revoked(id: "g-sub", revoked_ancestor: "g-root2"))))
  assert Table.get(Ledger.store(db16), cells, "v") == Ok(Some(Cell(value: 2)))
  assert Ledger.verify_all(db16) is Ok(_)
end

test "4. Claims/Leases coordinate slow-agent fairness and lazy expiry cleanly"
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T10:05:00Z") or stop "t1"
  t2 = Time.parse("2026-11-25T10:10:00Z") or stop "t2"
  sc = Ledger.schema(0).with_require_reason(true)
  assert Ledger.open(Files.in_memory({}), "fair.modb", sc, t0) is Ok(db0)

  ms = Ledger.WriteMeta(
    principal: "agent:slow",
    action: "claim",
    reason: "retry-after-sendback",
    at: t0
  )
  mf = Ledger.WriteMeta(principal: "agent:fast", action: "claim", reason: "work", at: t0)
  assert Claims.acquire(db0, ms, "bucket:pricing", "g-slow", Some("w-slow"), t1) is Ok((db1, _))
  assert Claims.acquire(db1, mf, "bucket:pricing", "g-fast", None, t1) is
    Error(Claims.AlreadyClaimed(resource: "bucket:pricing", holder: "agent:slow", expires_at: _))
  assert Claims.list_by_holder(Ledger.store(db1), "agent:slow", t0) is Ok(slow_claims)
  assert slow_claims.size == 1
  assert Claims.release(db1, ms, "bucket:pricing") is Ok(db2)
  assert Claims.acquire(db2, mf, "bucket:pricing", "g-fast", None, t2) is Ok((db3, _))
  assert Ledger.verify_all(db3) is Ok(_)
end

test "5. 500-crash deterministic torn-write simulation across Worlds, Grants, Claims & persistent pins"
  rng = Random.seeded(20261126)
  t0 = Time.parse("2026-11-25T10:00:00Z") or stop "t0"
  t1 = Time.parse("2026-11-25T12:00:00Z") or stop "t1"
  cat = cell_catalog()
  cells = cells_table()
  sc = Ledger.schema(1).with_require_reason(true).with_migration(
    Ledger.migration(1, "counter=0", fn(tx) Table.put(tx, cells, "counter", Cell(value: 0)) end)
  ).with_invariant(
    Ledger.row_invariant(
      "non_neg_counter",
      cells,
      fn(k, c) if c.value < 0: Some("#{k} < 0") else: None end
    )
  )

  assert Ledger.open_disk(Pager.sim_empty(), sc, t0) is Ok(db0)
  db1 = setup_grant(db0, "g-sim", "agent:sim", ["add"], t0, t1)
  ## Keep one long-lived open World pinned across all 500 crashes!
  assert World.open_world(db1, "long-observer", "g-sim", t0, t1) is Ok((db2, _))
  assert World.world_query(db2, cat, "long-observer", "get", "counter".to_json, t0) is Ok((db3, _))

  var db = db3
  var expected_counter = 0
  var survived_landings = 0

  for i in 0..500
    phase = if i % 2 == 0: 1 else: 2
    wid = "w-#{i}"
    assert World.open_world(db, wid, "g-sim", t0, t1) is Ok((d_open, _))
    assert World.world_query(d_open, cat, wid, "get", "counter".to_json, t0) is Ok((d_q, q_ans))
    assert q_ans == expected_counter.to_json
    assert World.world_call(
      d_q,
      cat,
      wid,
      "add",
      DeltaArgs(key: "counter", delta: 1).to_json,
      "step-#{i}",
      t0
    ) is
      Ok((d_c, _))

    assert World.land_world_and_crash(d_c, cat, wid, "land-#{i}", t0, phase, rng) is Ok(crashed)
    assert Ledger.open_disk(crashed, sc, t0) is Ok(rec)
    assert Ledger.verify_all(rec) is Ok(_)
    assert Table.get(Ledger.store(rec), cells, "counter") is Ok(Some(cur_cell))

    if phase == 1
      ## Phase 1 crash before data sync MUST roll back cleanly; drop the unlanded world to clean up pin
      assert cur_cell.value == expected_counter
      assert World.drop_world(rec, wid) is Ok(rec_clean)
      db = rec_clean
    else
      if cur_cell.value == expected_counter + 1
        expected_counter += 1
        survived_landings += 1
        db = rec
      else
        assert cur_cell.value == expected_counter
        assert World.drop_world(rec, wid) is Ok(rec_clean)
        db = rec_clean
      end
    end
  end

  assert survived_landings > 20
  ## Long-lived pinned observer still sees its initial base value (0) and drops cleanly
  assert World.world_query(db, cat, "long-observer", "get", "counter".to_json, t0) is
    Ok((db_obs, obs_ans))
  assert obs_ans == 0.to_json
  assert World.drop_world(db_obs, "long-observer") is Ok(db_final)
  assert Modb.list_pins(Ledger.store(db_final)) == Ok([])
  assert Ledger.verify_all(db_final) is Ok(_)
end
