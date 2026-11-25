## Real-disk writer & verifier for the OS `kill -9` crash-survival loop (Gate 3).
module KillWriter
use Modb

fn expected_value(seq: Int) : Bytes
  if seq % 11 == 0
    ## Overflow value (5,000 bytes -> 2 overflow pages)
    Bytes.join([Bytes.from_i64_be(seq), Bytes.zeroed(4984), Bytes.from_i64_be(seq)])
  else
    "seq-#{seq}-payload".bytes
  end
end

fn run_write(console: Console, files: Files, db_path: Text, ledger_path: Text, max_commits: Int) : Result(
  Unit,
  Text
)
  db0 = case Modb.open(files, db_path)
    Ok(d): d
    Error(e): return Error("open failed: #{e.to_text}")
  end
  var db = db0
  var seq = case Modb.get(db, "meta", "last_seq".bytes)
    Ok(Some(raw)): raw.i64_be_at(0) or 0
    Ok(None): 0
    Error(e): return Error("read last_seq failed: #{e.to_text}")
  end
  console.print("ready #{seq}")

  for _step in 0..max_commits
    next_seq = seq + 1
    var tx = Modb.begin_write(db)
    tx = case Modb.tx_put(tx, "kv", Bytes.from_i64_be(next_seq), expected_value(next_seq))
      Ok(t): t
      Error(e): return Error("put kv failed: #{e.to_text}")
    end
    tx = case Modb.tx_put(tx, "meta", "last_seq".bytes, Bytes.from_i64_be(next_seq))
      Ok(t): t
      Error(e): return Error("put meta failed: #{e.to_text}")
    end
    ## Periodically overwrite an older key to exercise freelist reclamation across crashes.
    if next_seq > 20 and next_seq % 5 == 0
      old_k = Bytes.from_i64_be(next_seq - 20)
      tx = case Modb.tx_put(tx, "hot", old_k, expected_value(next_seq))
        Ok(t): t
        Error(e): return Error("put hot failed: #{e.to_text}")
      end
    end
    db = case Modb.commit(tx)
      Ok(d): d
      Error(e): return Error("commit failed: #{e.to_text}")
    end
    seq = next_seq
    ## Only after `Modb.commit` returns Ok do we record `seq` in the external ack ledger.
    case files.append_text(ledger_path, "#{seq}\n")
      Ok(_): Unit
      Error(e): return Error("ledger append failed: #{e.to_text}")
    end
  end
  console.print("finished #{seq}")
  Ok(Unit)
end

fn run_verify(console: Console, files: Files, db_path: Text, min_acked: Int) : Result(Unit, Text)
  db = case Modb.open(files, db_path)
    Ok(d): d
    Error(e): return Error("reopen failed: #{e.to_text}")
  end
  rep = case Modb.verify(db)
    Ok(r): r
    Error(e): return Error("verify failed: #{e.to_text}")
  end
  last_seq = case Modb.get(db, "meta", "last_seq".bytes)
    Ok(Some(raw)): raw.i64_be_at(0) or 0
    Ok(None): 0
    Error(e): return Error("get last_seq failed: #{e.to_text}")
  end
  if last_seq < min_acked
    return Error("LOST COMMIT: db last_seq=#{last_seq} < acked=#{min_acked}")
  end
  ## Verify every committed row 1..last_seq matches exact expected bytes.
  for s in 1..(last_seq + 1)
    got = case Modb.get(db, "kv", Bytes.from_i64_be(s))
      Ok(Some(v)): v
      Ok(None): return Error("missing committed key #{s} (last_seq=#{last_seq})")
      Error(e): return Error("read key #{s} failed: #{e.to_text}")
    end
    if got != expected_value(s)
      return Error("value mismatch at key #{s}")
    end
  end
  console.print(
    "ok txid=#{rep.txid} last_seq=#{last_seq} pages=#{rep.page_count} free=#{rep.free_entries}"
  )
  Ok(Unit)
end

fn main(args: Args, console: Console, files: Files) : Result(Unit, Text)
  argv = args.list
  mode = case argv.get(0)
    Some(m): m
    None: return Error("usage: write|verify ...")
  end
  if mode == "write"
    db_path = case argv.get(1)
      Some(p): p
      None: return Error("missing db_path")
    end
    ledger_path = case argv.get(2)
      Some(p): p
      None: return Error("missing ledger_path")
    end
    max_commits = (argv.get(3) or "10000").to_int or 10000
    run_write(console, files, db_path, ledger_path, max_commits)
  else if mode == "verify"
    db_path = case argv.get(1)
      Some(p): p
      None: return Error("missing db_path")
    end
    min_acked = (argv.get(2) or "0").to_int or 0
    run_verify(console, files, db_path, min_acked)
  else
    Error("unknown mode: #{mode}")
  end
end
