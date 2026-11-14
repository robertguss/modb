#!/usr/bin/env python3
"""The same job on SQLite alone, with the settings Mo's own store uses: change one row, read one row."""
import json
import pathlib
import sqlite3
import sys
import time

from measure import OUT, spread

ROW = "0123456789012345678901234567890123456789012345678901234567890123"
SETTINGS = ("PRAGMA journal_mode=DELETE; PRAGMA synchronous=EXTRA; "
            "PRAGMA locking_mode=EXCLUSIVE; PRAGMA cache_size=-256;")


def timed(action):
    began = time.perf_counter()
    action()
    return (time.perf_counter() - began) * 1000


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "yardstick.sqlite"
    for size in (int(n) for n in sys.argv[1].split(",")):
        path.unlink(missing_ok=True)
        db = sqlite3.connect(path, isolation_level=None)
        db.executescript(SETTINGS)
        db.execute("CREATE TABLE rows (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
        db.execute("BEGIN")
        db.executemany("INSERT INTO rows VALUES (?, ?)", ((i, ROW) for i in range(size)))
        db.execute("COMMIT")

        def write(i):
            db.execute("BEGIN")
            db.execute("UPDATE rows SET value = ? WHERE id = ?", (f"changed {i}", (i * 7919) % size))
            db.execute("COMMIT")

        reads = [timed(lambda: db.execute("SELECT value FROM rows WHERE id = ?",
                                          ((i * 7919) % size,)).fetchone()) for i in range(40)]
        writes = [timed(lambda: write(i)) for i in range(210)]
        db.close()
        print(json.dumps({"rows": size, "read_ms": spread(reads), "write_ms": spread(writes),
                          "file_mib": round(path.stat().st_size / 2**20, 1)}), flush=True)
    path.unlink()


if __name__ == "__main__":
    main()
