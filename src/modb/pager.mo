## Fixed-size 4 KiB paged block storage with real file backing and deterministic crash-fault simulation.
module Modb.Pager
expose page_size,
default_cache_limit,
Disk(..),
BlockStore(..),
from_file,
sim_empty,
disk_page_count,
read_page,
write_page,
sync,
clear_cache,
simulate_crash,
corrupt_byte,
pending_count
use Modb.Errors{ModbError, wrap_io}

page_size = 4096
default_cache_limit = 4096

## Underlying page device: either a real/in-memory `Files.File` capability or a pure-Mo
## crash-fault simulator separating durable pages from unsynced pending writes.
enum Disk
  Real(file: Files.File)
  Sim(durable: Map(Int, Bytes), pending: Map(Int, Bytes), page_count: Int)
end

## Paged storage handle with a bounded read/write cache.
struct BlockStore
  disk: Disk
  cache: Map(Int, Bytes)
  cache_limit: Int
end

## Wraps an open `Files.File` capability in a `BlockStore`.
fn from_file(file: Files.File) : BlockStore
  BlockStore(disk: Real(file: file), cache: {}, cache_limit: default_cache_limit)
end

## Creates an empty pure-Mo simulated disk for deterministic crash testing.
fn sim_empty() : BlockStore
  BlockStore(
    disk: Sim(durable: {}, pending: {}, page_count: 0),
    cache: {},
    cache_limit: default_cache_limit
  )
end

## Returns the number of complete 4 KiB pages currently present on the underlying disk.
fn disk_page_count(store: BlockStore) : Result(Int, ModbError)
  case store.disk
    Real(file: file):
      bytes_len = try wrap_io(file.size)
      Ok(bytes_len / page_size)
    Sim(durable: _, pending: _, page_count: count): Ok(count)
  end
end

## Reads a single 4 KiB page, checking the cache first.
fn read_page(store: BlockStore, page_id: Int) : Result(Bytes, ModbError)
  return Error(InvalidArgument(reason: "negative page id #{page_id}")) if page_id < 0
  case store.cache.get(page_id)
    Some(cached): return Ok(cached)
    None: Unit
  end
  case store.disk
    Real(file: file):
      raw = try wrap_io(file.read_at(page_id * page_size, page_size))
      if raw.size != page_size
        return Error(Corrupt(reason: "short read for page #{page_id}: got #{raw.size} bytes"))
      end
      Ok(raw)
    Sim(durable: durable, pending: pending, page_count: _):
      case pending.get(page_id)
        Some(raw): Ok(raw)
        None:
          case durable.get(page_id)
            Some(raw): Ok(raw)
            None: Error(Corrupt(reason: "missing simulated page #{page_id}"))
          end
      end
  end
end

## Writes a single 4 KiB page and updates the cache.
fn write_page(store: BlockStore, page_id: Int, data: Bytes) : Result(BlockStore, ModbError)
  return Error(InvalidArgument(reason: "negative page id #{page_id}")) if page_id < 0
  if data.size != page_size
    return Error(
      InvalidArgument(reason: "page #{page_id} must be #{page_size} bytes, got #{data.size}")
    )
  end
  var next = store
  case store.disk
    Real(file: file): try wrap_io(file.write_at(page_id * page_size, data))
    Sim(durable: durable, pending: pending, page_count: count):
      next_pending = pending.set(page_id, data)
      next_count = count.max(page_id + 1)
      next.disk = Sim(durable: durable, pending: next_pending, page_count: next_count)
  end
  if page_id < 2 or next.cache.has?(page_id) or next.cache.size < next.cache_limit
    next.cache = next.cache.set(page_id, data)
  else if next.cache_limit > 0
    ## Always keep branch pages (kind == 1) hot; drop cache cleanly if saturated.
    case data.u16_be_at(0)
      Some(1): next.cache = {}.set(page_id, data)
      Some(_) | None: Unit
    end
  end
  Ok(next)
end

## Flushes all pending writes to durable storage.
fn sync(store: BlockStore) : Result(BlockStore, ModbError)
  case store.disk
    Real(file: file):
      try wrap_io(file.sync)
      Ok(store)
    Sim(durable: durable, pending: pending, page_count: count):
      var next_durable = durable
      for (pid, data) in pending.entries
        next_durable = next_durable.set(pid, data)
      end
      var next = store
      next.disk = Sim(durable: next_durable, pending: {}, page_count: count)
      Ok(next)
  end
end

## Drops all cached pages (simulating cold reads after restart).
fn clear_cache(store: BlockStore) : BlockStore
  var next = store
  next.cache = {}
  next
end

## Number of unsynced pages in a simulated disk (0 for real disks).
fn pending_count(store: BlockStore) : Int
  case store.disk
    Real(file: _): 0
    Sim(durable: _, pending: pending, page_count: _): pending.size
  end
end

## Simulates a sudden power cut on a `Sim` disk using `rng`:
## each unsynced page is independently dropped, persisted whole, or torn at a random byte cut.
## The in-memory page cache is wiped clean to mirror a real restart.
fn simulate_crash(store: BlockStore, rng: Random) : BlockStore
  case store.disk
    Real(file: _): clear_cache(store)
    Sim(durable: durable, pending: pending, page_count: _):
      var survived = durable
      for (pid, new_bytes) in pending.entries
        outcome = rng.int(0, 3)
        if outcome == 1
          survived = survived.set(pid, new_bytes)
        else if outcome == 2
          cut = rng.int(1, page_size)
          base = durable.get(pid) or Bytes.zeroed(page_size)
          torn = Bytes.join([new_bytes.slice(0, cut), base.slice(cut, page_size)])
          survived = survived.set(pid, torn)
        end
      end
      var max_pid = 0
      for pid in survived.keys
        max_pid = max_pid.max(pid + 1)
      end
      BlockStore(
        disk: Sim(durable: survived, pending: {}, page_count: max_pid),
        cache: {},
        cache_limit: store.cache_limit
      )
  end
end

## Flips one byte on a durable simulated page (for testing checksum corruption detection).
fn corrupt_byte(store: BlockStore, page_id: Int, offset: Int) : Result(BlockStore, ModbError)
  if offset < 0 or offset >= page_size
    return Error(InvalidArgument(reason: "corrupt offset out of range"))
  end
  raw = try read_page(store, page_id)
  old_b = (raw.get(offset) or (0.to_byte or stop "zero byte")).to_int
  flipped_int = (old_b + 85) % 256
  flipped = Bytes.from_list([flipped_int.to_byte or stop "valid byte"])
  damaged = Bytes.join([raw.slice(0, offset), flipped, raw.slice(offset + 1, page_size)])
  case store.disk
    Real(file: file):
      try wrap_io(file.write_at(page_id * page_size, damaged))
      try wrap_io(file.sync)
      Ok(clear_cache(store))
    Sim(durable: durable, pending: pending, page_count: count):
      next_durable = durable.set(page_id, damaged)
      next_pending = if pending.has?(page_id): pending.set(page_id, damaged) else: pending
      Ok(
        BlockStore(
          disk: Sim(durable: next_durable, pending: next_pending, page_count: count),
          cache: {},
          cache_limit: store.cache_limit
        )
      )
  end
end

test "simulated disk keeps pending writes separate from durable until sync"
  var disk = sim_empty()
  p0 = Bytes.join([Bytes.from_u32_be(42), Bytes.zeroed(page_size - 4)])
  assert write_page(disk, 0, p0) is Ok(d1)
  disk = d1
  assert pending_count(disk) == 1
  assert read_page(disk, 0) == Ok(p0)
  assert sync(disk) is Ok(d2)
  disk = d2
  assert pending_count(disk) == 0
  assert read_page(clear_cache(disk), 0) == Ok(p0)
end

test "real in-memory file handle backs BlockStore cleanly"
  files = Files.in_memory({})
  assert files.open("pager.db") is Ok(fh)
  var disk = from_file(fh)
  assert disk_page_count(disk) == Ok(0)
  p0 = Bytes.join([Bytes.from_i64_be(999), Bytes.zeroed(page_size - 8)])
  assert write_page(disk, 0, p0) is Ok(d1)
  assert sync(d1) is Ok(d2)
  disk = d2
  assert disk_page_count(disk) == Ok(1)
  assert read_page(clear_cache(disk), 0) == Ok(p0)
end
