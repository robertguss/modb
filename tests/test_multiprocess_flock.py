#!/usr/bin/env python3
"""Multi-process OS PID `flock` + optimistic CoW read + SIGKILL crash test for MoDB."""
import os
import subprocess
import sys
import tempfile
import threading
import time


WORKER_MO = """module Worker
use Json
use Modb.Ledger
use Modb.Table

fn counters_table() : Table(Text, Int)
  Table.text_key[Int]("counters")
end

fn test_schema() : Ledger.Schema
  Ledger.schema(1)
    .with_require_reason(true)
    .with_migration(Ledger.migration(1, "init counters", fn(tx)
      t1 = try Table.put(tx, counters_table(), "total", 0)
      Ok(t1)
    end))
    .with_invariant(Ledger.row_invariant("non_negative", counters_table(), fn(k, v)
      if v < 0: Some("counter '#{k}' went negative: #{v}") else: None
    end))
end

fn cmd_init(files: Files, clock: Clock, console: Console, path: Text) : Int
  case Ledger.init_locked(files, path, test_schema(), clock.now)
    Ok((txid, st)):
      console.print("INIT ok txid=#{txid} ver=#{st.version}")
      0
    Error(err):
      console.error("INIT failed: #{err.to_text}")
      1
  end
end

fn cmd_write(
  files: Files,
  clock: Clock,
  console: Console,
  path: Text,
  wid: Text,
  count: Int
) : Int
  tbl = counters_table()
  for idx in 0..count
    i = idx + 1
    now = clock.now
    meta = Ledger.WriteMeta(principal: wid, action: "inc", reason: "step #{i}", at: now)
    case Ledger.transact_locked(
      files,
      path,
      test_schema(),
      meta,
      "inc #{wid} step #{i}",
      Json.int(i),
      fn(e) e end,
      fn(tx)
        cur_w = (try Table.tx_get(tx, tbl, wid).map_error(fn(e) Ledger.TableFailure(e) end)) or 0
        cur_t = (try Table.tx_get(tx, tbl, "total").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
        t1 = try Table.put(tx, tbl, wid, cur_w + 1).map_error(fn(e) Ledger.TableFailure(e) end)
        t2 = try Table.put(t1, tbl, "total", cur_t + 1).map_error(fn(e) Ledger.TableFailure(e) end)
        Ok((t2, cur_w + 1))
      end
    )
      Ok(next_w):
        console.print("ACK #{wid} #{next_w}")
      Error(err):
        console.error("WRITE failed (#{wid} #{i}): #{err.to_text}")
        return 1
    end
  end
  0
end

fn cmd_read(
  rf: ReadFiles,
  clock: Clock,
  console: Console,
  path: Text,
  count: Int
) : Int
  tbl = counters_table()
  var last_total = -1
  for idx in 0..count
    i = idx + 1
    case Ledger.read_locked(rf, path, test_schema(), fn(e) e end, fn(db)
      st = Ledger.store(db)
      tot = (try Table.get(st, tbl, "total").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
      wa = (try Table.get(st, tbl, "wA").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
      wb = (try Table.get(st, tbl, "wB").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
      wc = (try Table.get(st, tbl, "wC").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
      wd = (try Table.get(st, tbl, "wD").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
      Ok((tot, wa, wb, wc, wd, Ledger.audit_count(db)))
    end)
      Ok((tot, wa, wb, wc, wd, aud)):
        if tot < 0 or tot < last_total
          console.error("READ monotonic violation at #{i}: tot=#{tot} last=#{last_total}")
          return 1
        end
        if wa + wb + wc + wd != tot
          console.error("READ sum violation at #{i}: #{wa}+#{wb}+#{wc}+#{wd} != #{tot} (audit=#{aud})")
          return 1
        end
        last_total = tot
      Error(err):
        console.error("READ failed at #{i}: #{err.to_text}")
        return 1
    end
    clock.sleep(1.milliseconds)
  end
  console.print("READ ok last_total=#{last_total}")
  0
end

fn cmd_verify(rf: ReadFiles, console: Console, path: Text) : Int
  tbl = counters_table()
  case Ledger.read_locked(rf, path, test_schema(), fn(e) e end, fn(db)
    rep = try Ledger.verify_all(db)
    st = Ledger.store(db)
    tot = (try Table.get(st, tbl, "total").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
    wa = (try Table.get(st, tbl, "wA").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
    wb = (try Table.get(st, tbl, "wB").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
    wc = (try Table.get(st, tbl, "wC").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
    wd = (try Table.get(st, tbl, "wD").map_error(fn(e) Ledger.TableFailure(e) end)) or 0
    Ok((rep, tot, wa, wb, wc, wd))
  end)
    Ok((rep, tot, wa, wb, wc, wd)):
      console.print(
        "OK txid=#{rep.storage.txid} pages=#{rep.storage.page_count} audit=#{rep.audit.entry_count} inv=#{rep.invariants_checked} total=#{tot} wA=#{wa} wB=#{wb} wC=#{wc} wD=#{wd}"
      )
      0
    Error(err):
      console.error("VERIFY failed: #{err.to_text}")
      1
  end
end

fn main(args: Args, console: Console, files: Files, clock: Clock) : Int
  argv = args.list
  cmd = argv.first or ""
  path = argv.get(1) or "shared.modb"
  if cmd == "init"
    return cmd_init(files, clock, console, path)
  end
  if cmd == "write"
    wid = argv.get(2) or "w"
    cnt = (argv.get(3) or "1").to_int or 1
    return cmd_write(files, clock, console, path, wid, cnt)
  end
  if cmd == "read"
    cnt = (argv.get(2) or "1").to_int or 1
    return cmd_read(files.read_only, clock, console, path, cnt)
  end
  if cmd == "verify"
    return cmd_verify(files.read_only, console, path)
  end
  console.error("unknown command: #{cmd}")
  2
end
"""


def parse_verify_line(line: str) -> dict[str, int]:
    parts = {}
    for tok in line.strip().split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            parts[k] = int(v)
    return parts


def run_worker(mo_bin: str, tmpdir: str, *worker_args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [mo_bin, "run", "--root", tmpdir, os.path.join(tmpdir, "worker.mo"), *worker_args],
        cwd=tmpdir,
        capture_output=True,
        text=True,
        check=False,
    )


def main() -> int:
    mo_bin = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/code/mo/target/release/mo")
    modb_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    with tempfile.TemporaryDirectory(prefix="modb-flock-") as tmpdir:
        with open(os.path.join(tmpdir, "mo.toml"), "w", encoding="utf-8") as f:
            f.write(
                f'[package]\nname = "flock_test"\nversion = "0.1.0"\n\n'
                f'[dependencies]\nmodb = {{ path = "{modb_root}" }}\n'
            )
        worker_mo = os.path.join(tmpdir, "worker.mo")
        with open(worker_mo, "w", encoding="utf-8") as f:
            f.write(WORKER_MO)

        init_res = run_worker(mo_bin, tmpdir, "init", "shared.modb")
        if init_res.returncode != 0:
            raise AssertionError(f"init failed: {init_res.stdout}\n{init_res.stderr}")

        p_wa = subprocess.Popen(
            [mo_bin, "run", "--root", tmpdir, worker_mo, "write", "shared.modb", "wA", "30"],
            cwd=tmpdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        p_wb = subprocess.Popen(
            [mo_bin, "run", "--root", tmpdir, worker_mo, "write", "shared.modb", "wB", "30"],
            cwd=tmpdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        p_wc = subprocess.Popen(
            [mo_bin, "run", "--root", tmpdir, worker_mo, "write", "shared.modb", "wC", "100"],
            cwd=tmpdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        p_r1 = subprocess.Popen(
            [mo_bin, "run", "--root", tmpdir, worker_mo, "read", "shared.modb", "60"],
            cwd=tmpdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        p_r2 = subprocess.Popen(
            [mo_bin, "run", "--root", tmpdir, worker_mo, "read", "shared.modb", "60"],
            cwd=tmpdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        # Wait until Writer C commits and flushes at least 3 durable ACKs, then SIGKILL it mid-burst.
        wc_acks = []

        def drain_wc():
            assert p_wc.stdout is not None
            for line in p_wc.stdout:
                line = line.strip()
                if line.startswith("ACK wC "):
                    wc_acks.append(int(line.split()[-1]))

        t_wc = threading.Thread(target=drain_wc, daemon=True)
        t_wc.start()

        deadline = time.monotonic() + 20.0
        while len(wc_acks) < 3 and time.monotonic() < deadline:
            if p_wc.poll() is not None:
                break
            time.sleep(0.01)
        if len(wc_acks) < 3:
            raise AssertionError(f"Writer C produced fewer than 3 ACKs before timeout/exit: {wc_acks}")

        acked_wc = wc_acks[-1]
        p_wc.kill()
        p_wc.wait(timeout=10)
        t_wc.join(timeout=2)
        wc_err = p_wc.stderr.read() if p_wc.stderr else ""

        # Immediately verify integrity while/after SIGKILLed writer exited.
        mid_verify = run_worker(mo_bin, tmpdir, "verify", "shared.modb")
        if mid_verify.returncode != 0 or not mid_verify.stdout.startswith("OK "):
            raise AssertionError(
                f"post-SIGKILL immediate verify failed:\nstdout={mid_verify.stdout}\nstderr={mid_verify.stderr}\nwc_stderr={wc_err}"
            )

        # Wait for concurrent writers A & B and readers 1 & 2, then launch Writer D.
        out_wa, err_wa = p_wa.communicate(timeout=30)
        out_wb, err_wb = p_wb.communicate(timeout=30)
        out_r1, err_r1 = p_r1.communicate(timeout=30)
        out_r2, err_r2 = p_r2.communicate(timeout=30)

        for label, proc, out, err in [
            ("wA", p_wa, out_wa, err_wa),
            ("wB", p_wb, out_wb, err_wb),
            ("r1", p_r1, out_r1, err_r1),
            ("r2", p_r2, out_r2, err_r2),
        ]:
            if proc.returncode != 0:
                raise AssertionError(f"{label} failed ({proc.returncode}):\nstdout={out}\nstderr={err}")

        res_wd = run_worker(mo_bin, tmpdir, "write", "shared.modb", "wD", "20")
        if res_wd.returncode != 0:
            raise AssertionError(f"wD failed ({res_wd.returncode}):\nstdout={res_wd.stdout}\nstderr={res_wd.stderr}")

        final_verify = run_worker(mo_bin, tmpdir, "verify", "shared.modb")
        if final_verify.returncode != 0 or not final_verify.stdout.startswith("OK "):
            raise AssertionError(f"final verify failed:\nstdout={final_verify.stdout}\nstderr={final_verify.stderr}")

        stats = parse_verify_line(final_verify.stdout)
        assert stats["wA"] == 30, f"expected wA=30, got {stats}"
        assert stats["wB"] == 30, f"expected wB=30, got {stats}"
        assert stats["wD"] == 20, f"expected wD=20, got {stats}"
        assert stats["wC"] >= acked_wc, f"lost ACKed wC: committed={stats['wC']} < acked={acked_wc}"
        expected_total = stats["wA"] + stats["wB"] + stats["wC"] + stats["wD"]
        assert stats["total"] == expected_total, f"sum mismatch: {stats}"
        assert stats["audit"] == expected_total + 1, f"audit count mismatch: {stats}"

        print(
            f"PASS test_multiprocess_flock: acked_wC={acked_wc} final={final_verify.stdout.strip()}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
