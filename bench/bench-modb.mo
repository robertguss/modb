## Milestone 1 Benchmarks:
## - Gate 4: 100k row load + 100k overwrites (freelist stability)
## - Gate 5: Head-to-head vs Mo's built-in Sqlite on the same disk
module BenchModb
use Modb

fn elapsed_ms(clock: Clock, start: Time) : Int
  (clock.now - start).in_milliseconds
end

fn make_row_val(i: Int) : Bytes
  Bytes.join([Bytes.from_i64_be(i), Bytes.zeroed(56)])
end

fn bench_modb(console: Console, files: Files, clock: Clock, total_rows: Int) : Result(Unit, Text)
  console.print("=== MoDB Benchmark (#{total_rows} rows, 64B values) ===")
  t0 = clock.now
  db0 = case Modb.open(files, "bench.modb")
    Ok(d): d
    Error(e): return Error("open failed: #{e.to_text}")
  end
  var db = db0

  ## Load in batches of 1,000 rows
  batch = 1000
  batches = total_rows / batch
  for b in 0..batches
    var tx = Modb.begin_write(db)
    base = b * batch
    for j in 0..batch
      idx = base + j
      tx = case Modb.tx_put(tx, "rows", Bytes.from_i64_be(idx), make_row_val(idx))
        Ok(t): t
        Error(e): return Error("put failed: #{e.to_text}")
      end
    end
    db = case Modb.commit(tx)
      Ok(d): d
      Error(e): return Error("commit failed: #{e.to_text}")
    end
  end
  load_ms = elapsed_ms(clock, t0)
  console.print(
    "load #{total_rows} rows (#{batches} x #{batch} synced batches): #{load_ms} ms | pages=#{Modb
      .page_count(db)} (#{Modb.page_count(db) * 4} KiB)"
  )

  ## Verify integrity after bulk load
  tv = clock.now
  rep = case Modb.verify(db)
    Ok(r): r
    Error(e): return Error("verify failed: #{e.to_text}")
  end
  console.print(
    "verify: #{elapsed_ms(clock, tv)} ms | live=#{rep.live_pages}, fl_chain=#{rep
      .freelist_chain_pages}, free=#{rep.free_entries}"
  )

  ## Warm point gets (1,000 lookups)
  t_warm = clock.now
  for i in 0..1000
    k = Bytes.from_i64_be((i * 97) % total_rows)
    case Modb.get(db, "rows", k)
      Ok(Some(_)): Unit
      Ok(None): return Error("missing key on warm get")
      Error(e): return Error("warm get failed: #{e.to_text}")
    end
  end
  console.print("warm point get (1,000x): #{elapsed_ms(clock, t_warm)} ms")

  ## Cold point gets (reopened fresh with empty cache, 1,000 lookups)
  cold_db = case Modb.open(files, "bench.modb")
    Ok(d): d
    Error(e): return Error("cold reopen failed: #{e.to_text}")
  end
  t_cold = clock.now
  for i in 0..1000
    k = Bytes.from_i64_be((i * 97) % total_rows)
    case Modb.get(cold_db, "rows", k)
      Ok(Some(_)): Unit
      Ok(None): return Error("missing key on cold get")
      Error(e): return Error("cold get failed: #{e.to_text}")
    end
  end
  console.print("cold point get (1,000x, no cache): #{elapsed_ms(clock, t_cold)} ms")

  ## Range scan (100 rows x 100 scans)
  t_scan = clock.now
  for i in 0..100
    start_k = Bytes.from_i64_be((i * 773) % (total_rows - 200))
    rows = case Modb.scan(db, "rows", Some(start_k), None, 100)
      Ok(r): r
      Error(e): return Error("scan failed: #{e.to_text}")
    end
    return Error("short scan #{rows.size}") if rows.size != 100
  end
  console.print("100-row range scan (100x): #{elapsed_ms(clock, t_scan)} ms")

  ## Single-row synced write_tx (100 commits)
  t_single = clock.now
  for i in 0..100
    idx = (i * 131) % total_rows
    val = make_row_val(idx + 1_000_000)
    db = case Modb.write_tx(db, fn(tx) Modb.tx_put(tx, "rows", Bytes.from_i64_be(idx), val) end)
      Ok(d): d
      Error(e): return Error("single write failed: #{e.to_text}")
    end
  end
  console.print("single-row synced write_tx (100x): #{elapsed_ms(clock, t_single)} ms")

  ## 100k overwrites (100 batches of 1,000) to verify freelist page-count stability
  pages_start = Modb.page_count(db)
  t_ow = clock.now
  for b in 0..batches
    var tx = Modb.begin_write(db)
    base = b * batch
    for j in 0..batch
      idx = base + j
      tx = case Modb.tx_put(tx, "rows", Bytes.from_i64_be(idx), make_row_val(idx + 2_000_000))
        Ok(t): t
        Error(e): return Error("overwrite put failed: #{e.to_text}")
      end
    end
    db = case Modb.commit(tx)
      Ok(d): d
      Error(e): return Error("overwrite commit failed: #{e.to_text}")
    end
    if b == batches / 4 or b == batches / 2 or b == (batches * 3) / 4 or b == batches - 1
      console.print(
        "  overwrite batch #{b + 1}/#{batches}: pages=#{Modb.page_count(db)}, free=#{Modb
          .free_page_count(db)}"
      )
    end
  end
  ow_ms = elapsed_ms(clock, t_ow)
  console.print(
    "overwrite #{total_rows} rows: #{ow_ms} ms | pages #{pages_start} -> #{Modb.page_count(db)}"
  )
  case Modb.verify(db)
    Ok(_): console.print("final verify: OK")
    Error(e): return Error("final verify failed: #{e.to_text}")
  end
  Ok(Unit)
end

fn bench_sqlite(console: Console, sqlite: Sqlite, clock: Clock, total_rows: Int) : Result(
  Unit,
  Text
)
  console.print("=== SQLite Benchmark (#{total_rows} rows, 64B values, synchronous=FULL) ===")
  sdb = case sqlite.open("bench.sqlite")
    Ok(d): d
    Error(e): return Error("sqlite open failed: #{e}")
  end
  case sdb.run("PRAGMA journal_mode=WAL", [])
    Ok(_): Unit
    Error(e): return Error("pragma wal: #{e}")
  end
  case sdb.run("PRAGMA synchronous=FULL", [])
    Ok(_): Unit
    Error(e): return Error("pragma sync: #{e}")
  end
  case sdb.run("CREATE TABLE IF NOT EXISTS rows (k INTEGER PRIMARY KEY, v BLOB NOT NULL)", [])
    Ok(_): Unit
    Error(e): return Error("create table: #{e}")
  end

  batch = 1000
  batches = total_rows / batch
  t0 = clock.now
  for b in 0..batches
    case sdb.run("BEGIN IMMEDIATE", [])
      Ok(_): Unit
      Error(e): return Error("begin: #{e}")
    end
    base = b * batch
    for j in 0..batch
      idx = base + j
      case sdb.run(
        "INSERT OR REPLACE INTO rows (k, v) VALUES (?1, ?2)",
        [Sqlite.Integer(idx), Sqlite.Blob(make_row_val(idx))]
      )
        Ok(_): Unit
        Error(e): return Error("insert: #{e}")
      end
    end
    case sdb.run("COMMIT", [])
      Ok(_): Unit
      Error(e): return Error("commit: #{e}")
    end
  end
  console.print(
    "load #{total_rows} rows (#{batches} x #{batch} synced batches): #{elapsed_ms(clock, t0)} ms"
  )

  t_get = clock.now
  for i in 0..1000
    idx = (i * 97) % total_rows
    case sdb.query("SELECT v FROM rows WHERE k = ?1", [Sqlite.Integer(idx)])
      Ok(res): return Error("missing sqlite row") if res.rows.size != 1
      Error(e): return Error("select: #{e}")
    end
  end
  console.print("point get (1,000x): #{elapsed_ms(clock, t_get)} ms")

  t_scan = clock.now
  for i in 0..100
    start_k = (i * 773) % (total_rows - 200)
    case sdb.query(
      "SELECT k, v FROM rows WHERE k >= ?1 ORDER BY k LIMIT 100",
      [Sqlite.Integer(start_k)]
    )
      Ok(res): return Error("short sqlite scan") if res.rows.size != 100
      Error(e): return Error("scan: #{e}")
    end
  end
  console.print("100-row range scan (100x): #{elapsed_ms(clock, t_scan)} ms")

  t_single = clock.now
  for i in 0..100
    idx = (i * 131) % total_rows
    case sdb.run(
      "UPDATE rows SET v = ?2 WHERE k = ?1",
      [Sqlite.Integer(idx), Sqlite.Blob(make_row_val(idx + 1_000_000))]
    )
      Ok(_): Unit
      Error(e): return Error("update: #{e}")
    end
  end
  console.print("single-row synced update (100x): #{elapsed_ms(clock, t_single)} ms")

  t_ow = clock.now
  for b in 0..batches
    case sdb.run("BEGIN IMMEDIATE", [])
      Ok(_): Unit
      Error(e): return Error("begin ow: #{e}")
    end
    base = b * batch
    for j in 0..batch
      idx = base + j
      case sdb.run(
        "UPDATE rows SET v = ?2 WHERE k = ?1",
        [Sqlite.Integer(idx), Sqlite.Blob(make_row_val(idx + 2_000_000))]
      )
        Ok(_): Unit
        Error(e): return Error("update ow: #{e}")
      end
    end
    case sdb.run("COMMIT", [])
      Ok(_): Unit
      Error(e): return Error("commit ow: #{e}")
    end
  end
  console.print("overwrite #{total_rows} rows: #{elapsed_ms(clock, t_ow)} ms")
  Ok(Unit)
end

fn main(args: Args, console: Console, files: Files, sqlite: Sqlite, clock: Clock) : Result(
  Unit,
  Text
)
  total_rows = case args.list.first
    Some(s): s.to_int or 10000
    None: 10000
  end
  try bench_modb(console, files, clock, total_rows)
  try bench_sqlite(console, sqlite, clock, total_rows)
  Ok(Unit)
end
