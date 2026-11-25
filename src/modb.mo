## MoDB Layer 1: Single-file Copy-on-Write B+Tree ordered key-value database in pure Mo.
module Modb
expose Store(..),
WriteTx(..),
Snapshot(..),
PinnedRoot(..),
VerifyReport(..),
BucketDiff(..),
pins_bucket,
open,
open_read_only,
open_file,
open_file_read_only,
open_disk,
with_shared_lock,
with_exclusive_lock,
txid,
catalog_root,
page_count,
free_page_count,
buckets,
get,
scan,
prefix_scan,
get_at_root,
scan_at_root,
list_pins,
get_pin,
pin_root,
unpin_root,
tx_pin_base_root,
tx_unpin_root,
begin_write,
begin_write_from_root,
tx_get,
tx_scan,
tx_put,
tx_delete,
tx_delete_bucket,
commit,
rollback,
write_tx,
snapshot,
snapshot_get,
snapshot_scan,
release_snapshot,
diff_bucket_roots,
diff_roots,
diff_roots_with_stats,
diff_tx_from_root,
verify,
commit_and_crash
use Modb.Codec{
  DeferredFreelistPage,
  DeferredPageEntry,
  FreelistChunk,
  FreelistPage,
  MetaPage,
  decode_freelist_chunk,
  decode_meta,
  encode_deferred_freelist,
  encode_freelist,
  encode_meta,
  max_deferred_freelist_entries,
  max_freelist_entries
}
use Modb.Errors{ModbError, wrap_io}
use Modb.Pager{
  BlockStore,
  clear_cache,
  disk_page_count,
  from_file,
  page_size,
  read_page,
  simulate_crash,
  sync,
  write_page
}
use Modb.Tree{
  Allocator,
  DiffStats,
  KeyDiff,
  alloc_page,
  collect_tree_pages,
  diff_trees,
  diff_trees_with_stats,
  empty_allocator,
  flush_dirty,
  free_tree
}

## Reserved internal bucket holding crash-safe persisted root pins (`pin_id -> (txid, catalog_root)`).
pins_bucket = "_modb_pins"

## Pages freed at commit `txid`, held back until no open snapshot or persistent pin predates `txid`.
struct DeferredFree
  txid: Int
  pages: List(Int)
end

## Crash-safe persisted root pin protecting `catalog_root` (committed at `txid`) across restarts.
struct PinnedRoot
  id: Text
  txid: Int
  catalog_root: Int
end

## Per-bucket structural diff between two catalog roots.
struct BucketDiff
  bucket: Text
  changes: List(KeyDiff)
end

## Open database handle holding committed meta state, freelist bookkeeping, snapshot pins, and persisted pins.
struct Store
  pager: BlockStore
  meta: MetaPage
  freelist_pages: List(Int)
  ready_free: List(Int)
  deferred_frees: List(DeferredFree)
  snapshots: Map(Int, Snapshot)
  pinned_roots: Map(Text, PinnedRoot)
  pins_loaded: Bool
  next_snapshot_id: Int
end

## Uncommitted write transaction staging CoW pages before atomic meta-page flip.
struct WriteTx
  base: Store
  alloc: Allocator
  catalog_root: Int
  dirty_buckets: Map(Text, Int)
  dirty: Bool
  speculative: Bool
  added_pins: Map(Text, PinnedRoot)
  removed_pins: Set(Text)
end

## Immutable O(1) read snapshot pinning a committed `catalog_root` until released.
struct Snapshot
  id: Int
  txid: Int
  catalog_root: Int
end

## Summary returned by `Modb.verify`.
struct VerifyReport
  txid: Int
  page_count: Int
  bucket_count: Int
  live_pages: Int
  freelist_chain_pages: Int
  free_entries: Int
end

## Opens or creates a MoDB database file via Mo's `Files` capability.
fn open(files: Files, path: Text) : Result(Store, ModbError)
  fh = try wrap_io(files.open(path))
  open_file(fh)
end

## Opens an existing MoDB database file read-only via Mo's `ReadFiles` capability.
## Never creates or writes to the file; returns an error if missing or uninitialized.
fn open_read_only(rf: ReadFiles, path: Text) : Result(Store, ModbError)
  fh = try wrap_io(rf.open(path))
  open_file_read_only(fh)
end

## Opens or initializes a MoDB database on an already-open `Files.File` handle.
fn open_file(file: Files.File) : Result(Store, ModbError)
  open_disk(from_file(file))
end

## Opens an already-open read-only `Files.File` handle without ever initializing or writing.
fn open_file_read_only(file: Files.File) : Result(Store, ModbError)
  store = from_file(file)
  n_pages = try disk_page_count(store)
  if n_pages < 2
    return Error(
      Corrupt(reason: "read-only open requires an initialized database (found #{n_pages} pages)")
    )
  end
  recover_existing(store)
end

fn finish_locked(fh: Files.File, res: Result(R, E), wrap_error: fn(ModbError) : E) : Result(R, E)
  unlock_res = wrap_io(fh.unlock)
  case (res, unlock_res)
    (Ok(val), Ok(_)): Ok(val)
    (Ok(_), Error(e)): Error(wrap_error(e))
    (Error(e), _): Error(e)
  end
end

## Opens `path` read-only via `ReadFiles`, acquires an advisory shared lock (`flock`),
## loads a fresh committed view of the meta-pages, executes `work`, and always releases the lock.
fn with_shared_lock(
  rf: ReadFiles,
  path: Text,
  wrap_error: fn(ModbError) : E,
  work: fn(Store) : Result(R, E)
) : Result(R, E)
  fh = try wrap_io(rf.open(path)).map_error(wrap_error)
  try wrap_io(fh.lock_shared).map_error(wrap_error)
  res = case open_file_read_only(fh)
    Ok(s): work(s)
    Error(e): Error(wrap_error(e))
  end
  finish_locked(fh, res, wrap_error)
end

## Opens `path` read-write via `Files`, acquires an advisory exclusive lock (`flock`),
## reloads the latest committed meta-pages (or initializes a new file), executes `work`,
## and always releases the lock.
fn with_exclusive_lock(
  files: Files,
  path: Text,
  wrap_error: fn(ModbError) : E,
  work: fn(Store) : Result(R, E)
) : Result(R, E)
  fh = try wrap_io(files.open(path)).map_error(wrap_error)
  try wrap_io(fh.lock_exclusive).map_error(wrap_error)
  res = case open_file(fh)
    Ok(s): work(s)
    Error(e): Error(wrap_error(e))
  end
  finish_locked(fh, res, wrap_error)
end

## Opens or initializes a MoDB database on any `BlockStore` (real file or crash simulator).
fn open_disk(store: BlockStore) : Result(Store, ModbError)
  n_pages = try disk_page_count(store)
  if n_pages < 2
    init_empty(store)
  else
    recover_existing(store)
  end
end

fn init_empty(store: BlockStore) : Result(Store, ModbError)
  meta = MetaPage(txid: 1, catalog_root: 0, freelist_root: 0, page_count: 2)
  p0 = Bytes.zeroed(page_size)
  p1 = encode_meta(meta)
  s1 = try write_page(store, 0, p0)
  s2 = try write_page(s1, 1, p1)
  s3 = try sync(s2)
  Ok(
    Store(
      pager: s3,
      meta: meta,
      freelist_pages: [],
      ready_free: [],
      deferred_frees: [],
      snapshots: {},
      pinned_roots: {},
      pins_loaded: true,
      next_snapshot_id: 1
    )
  )
end

fn encode_pinned_root(pin: PinnedRoot) : Bytes
  Bytes.join([Bytes.from_i64_be(pin.txid), Bytes.from_i64_be(pin.catalog_root)])
end

fn decode_pinned_root(id: Text, raw: Bytes, max_pages: Int, max_txid: Int) : Result(
  PinnedRoot,
  ModbError
)
  if raw.size != 16
    return Error(Corrupt(reason: "invalid pinned root '#{id}' size #{raw.size} != 16"))
  end
  ptx = try raw.i64_be_at(0).or_fail(Corrupt(reason: "truncated pin txid for '#{id}'"))
  proot = try raw.i64_be_at(8).or_fail(Corrupt(reason: "truncated pin catalog_root for '#{id}'"))
  if ptx < 1 or ptx > max_txid
    return Error(Corrupt(reason: "pinned root '#{id}' txid #{ptx} out of range 1..#{max_txid}"))
  end
  if proot < 0 or proot >= max_pages or proot == 1
    return Error(Corrupt(reason: "pinned root '#{id}' catalog_root #{proot} out of bounds"))
  end
  Ok(PinnedRoot(id: id, txid: ptx, catalog_root: proot))
end

fn load_pinned_roots(store: BlockStore, cat_root: Int, max_pages: Int, max_txid: Int) : Result(
  Map(Text, PinnedRoot),
  ModbError
)
  pins_root = try lookup_bucket_root(store, {}, cat_root, pins_bucket)
  return Ok({}) if pins_root == 0
  rows = try Tree.scan(store, {}, pins_root, None, None, 0)
  var pins = {}
  for (kb, vb) in rows
    id = case kb.decode_utf8
      Some(s): s
      None: return Error(Corrupt(reason: "non-utf8 pin id in #{pins_bucket}"))
    end
    pin = try decode_pinned_root(id, vb, max_pages, max_txid)
    pins = pins.set(id, pin)
  end
  Ok(pins)
end

fn group_deferred_entries(entries: List(DeferredPageEntry)) : List(DeferredFree)
  return [] if entries.empty?
  var by_txid = {}
  var order = []
  for e in entries
    case by_txid.get(e.txid)
      Some(ps): by_txid = by_txid.set(e.txid, ps.append(e.page_id))
      None:
        by_txid = by_txid.set(e.txid, [e.page_id])
        order = order.append(e.txid)
    end
  end
  var out = []
  for t in order
    ps = by_txid.get(t) or []
    out = out.append(DeferredFree(txid: t, pages: ps))
  end
  out
end

fn flatten_deferred(deferred: List(DeferredFree)) : List(DeferredPageEntry)
  var out = []
  for df in deferred
    for pid in df.pages
      out = out.append(DeferredPageEntry(txid: df.txid, page_id: pid))
    end
  end
  out
end

fn min_pin_txid(snapshots: Map(Int, Snapshot), pinned_roots: Map(Text, PinnedRoot), fallback: Int) : Int
  var lowest = fallback
  for snap in snapshots.values
    lowest = lowest.min(snap.txid)
  end
  for pin in pinned_roots.values
    lowest = lowest.min(pin.txid)
  end
  lowest
end

fn recover_existing(store: BlockStore) : Result(Store, ModbError)
  m0 = case read_page(store, 0)
    Ok(raw0): decode_meta(raw0)
    Error(e): Error(e)
  end
  m1 = case read_page(store, 1)
    Ok(raw1): decode_meta(raw1)
    Error(e): Error(e)
  end
  chosen = case (m0, m1)
    (Ok(a), Ok(b)): if b.txid > a.txid: b else: a
    (Ok(a), Error(_)): a
    (Error(_), Ok(b)): b
    (Error(e0), Error(e1)): return Error(
      Corrupt(reason: "both meta-pages invalid: slot0=(#{e0.to_text}), slot1=(#{e1.to_text})")
    )
  end
  (chain_pids, ready_entries, raw_deferred) = try load_freelist(
    store,
    chosen.freelist_root,
    chosen.page_count
  )
  ## Load persisted pins eagerly only when deferred-free chunks exist (needed to partition
  ## ready vs deferred pages on open); otherwise load lazily on pin/commit access so normal
  ## opens stay O(1) and corrupt data pages remain inspectable via `get`/`verify`.
  if raw_deferred.empty?
    return Ok(
      Store(
        pager: store,
        meta: chosen,
        freelist_pages: chain_pids,
        ready_free: ready_entries,
        deferred_frees: [],
        snapshots: {},
        pinned_roots: {},
        pins_loaded: false,
        next_snapshot_id: 1
      )
    )
  end
  pins = try load_pinned_roots(store, chosen.catalog_root, chosen.page_count, chosen.txid)
  ## Any deferred entries held only by an ephemeral in-memory snapshot from a dead process
  ## graduate immediately into `ready_free`; persisted pins keep their pages safely deferred.
  min_pin = min_pin_txid({}, pins, chosen.txid)
  var ready = ready_entries
  var kept_deferred = []
  for df in raw_deferred
    if df.txid <= min_pin
      ready = ready.concat(df.pages)
    else
      kept_deferred = kept_deferred.append(df)
    end
  end
  Ok(
    Store(
      pager: store,
      meta: chosen,
      freelist_pages: chain_pids,
      ready_free: ready,
      deferred_frees: kept_deferred,
      snapshots: {},
      pinned_roots: pins,
      pins_loaded: true,
      next_snapshot_id: 1
    )
  )
end

fn ensure_pinned_roots(store: Store) : Result(Map(Text, PinnedRoot), ModbError)
  return Ok(store.pinned_roots) if store.pins_loaded
  load_pinned_roots(store.pager, store.meta.catalog_root, store.meta.page_count, store.meta.txid)
end

fn load_freelist(store: BlockStore, freelist_root: Int, max_pages: Int) : Result(
  (List(Int), List(Int), List(DeferredFree)),
  ModbError
)
  return Ok(([], [], [])) if freelist_root == 0
  var chain = []
  var ready_entries = []
  var deferred_entries = []
  var cur = freelist_root
  var steps = 0
  while cur != 0
    steps += 1
    return Error(Corrupt(reason: "freelist cycle detected")) if steps > max_pages
    raw = try read_page(store, cur)
    chunk = try decode_freelist_chunk(raw, cur)
    chain = chain.append(cur)
    case chunk
      ReadyChunk(next_page: np, pages: ps):
        for pid in ps
          if pid < 2 or pid >= max_pages
            return Error(Corrupt(reason: "freelist page id #{pid} out of bounds"))
          end
          ready_entries = ready_entries.append(pid)
        end
        cur = np
      DeferredChunk(next_page: np, entries: es):
        for e in es
          if e.page_id < 2 or e.page_id >= max_pages
            return Error(Corrupt(reason: "deferred freelist page id #{e.page_id} out of bounds"))
          end
          deferred_entries = deferred_entries.append(e)
        end
        cur = np
    end
  end
  Ok((chain, ready_entries, group_deferred_entries(deferred_entries)))
end

## Current committed transaction ID.
fn txid(store: Store) : Int
  store.meta.txid
end

## Current committed catalog root page ID (O(1) version identifier).
fn catalog_root(store: Store) : Int
  store.meta.catalog_root
end

## Total allocated 4 KiB pages in the database file.
fn page_count(store: Store) : Int
  store.meta.page_count
end

## Number of pages currently available for reuse in the freelist.
fn free_page_count(store: Store) : Int
  var total = store.ready_free.size
  for df in store.deferred_frees
    total += df.pages.size
  end
  total
end

fn decode_bucket_root(raw: Bytes) : Result(Int, ModbError)
  case raw.i64_be_at(0)
    Some(pid):
      return Error(Corrupt(reason: "invalid bucket root #{pid}")) if raw.size != 8 or pid < 0
      Ok(pid)
    None: Error(Corrupt(reason: "malformed bucket root entry"))
  end
end

fn lookup_bucket_root(pager: BlockStore, staged: Map(Int, Bytes), catalog_root: Int, bucket: Text) : Result(
  Int,
  ModbError
)
  return Error(InvalidArgument(reason: "bucket name cannot be empty")) if bucket.empty?
  case try Tree.get(pager, staged, catalog_root, bucket.bytes)
    None: Ok(0)
    Some(raw): decode_bucket_root(raw)
  end
end

## Lists all bucket names in sorted order.
fn buckets(store: Store) : Result(List(Text), ModbError)
  rows = try Tree.scan(store.pager, {}, store.meta.catalog_root, None, None, 0)
  var names = []
  for (k, _v) in rows
    name = case k.decode_utf8
      Some(s): s
      None: return Error(Corrupt(reason: "non-utf8 bucket name"))
    end
    names = names.append(name)
  end
  Ok(names)
end

## Point lookup in `bucket` on the current committed state.
fn get(store: Store, bucket: Text, key: Bytes) : Result(Option(Bytes), ModbError)
  bucket_root = try lookup_bucket_root(store.pager, {}, store.meta.catalog_root, bucket)
  Tree.get(store.pager, {}, bucket_root, key)
end

## Ordered range scan over `[start_key, end_key)` in `bucket`. `limit <= 0` returns all matches.
fn scan(store: Store, bucket: Text, start_key: Option(Bytes), end_key: Option(Bytes), limit: Int) : Result(
  List((Bytes, Bytes)),
  ModbError
)
  bucket_root = try lookup_bucket_root(store.pager, {}, store.meta.catalog_root, bucket)
  Tree.scan(store.pager, {}, bucket_root, start_key, end_key, limit)
end

## Computes the smallest byte string strictly greater than every key sharing `prefix`.
fn prefix_upper_bound(prefix: Bytes) : Option(Bytes)
  var raw = prefix.to_list
  var i = raw.size - 1
  while i >= 0
    b = (raw.get(i) or stop "valid prefix idx").to_int
    if b < 255
      inc = (b + 1).to_byte or stop "valid byte"
      return Some(Bytes.from_list(raw.take(i).append(inc)))
    end
    i -= 1
  end
  None
end

## Scans all keys in `bucket` starting with `prefix`.
fn prefix_scan(store: Store, bucket: Text, prefix: Bytes, limit: Int) : Result(
  List((Bytes, Bytes)),
  ModbError
)
  if prefix.empty?
    scan(store, bucket, None, None, limit)
  else
    scan(store, bucket, Some(prefix), prefix_upper_bound(prefix), limit)
  end
end

## Point lookup in `bucket` at an explicit committed/pinned `cat_root`.
fn get_at_root(store: Store, cat_root: Int, bucket: Text, key: Bytes) : Result(
  Option(Bytes),
  ModbError
)
  bucket_root = try lookup_bucket_root(store.pager, {}, cat_root, bucket)
  Tree.get(store.pager, {}, bucket_root, key)
end

## Ordered range scan over `[start_key, end_key)` in `bucket` at an explicit committed/pinned `cat_root`.
fn scan_at_root(
  store: Store,
  cat_root: Int,
  bucket: Text,
  start_key: Option(Bytes),
  end_key: Option(Bytes),
  limit: Int
) : Result(List((Bytes, Bytes)), ModbError)
  bucket_root = try lookup_bucket_root(store.pager, {}, cat_root, bucket)
  Tree.scan(store.pager, {}, bucket_root, start_key, end_key, limit)
end

## Lists all currently active persistent root pins.
fn list_pins(store: Store) : Result(List(PinnedRoot), ModbError)
  pins = try ensure_pinned_roots(store)
  Ok(pins.values)
end

## Looks up a persistent root pin by `id`.
fn get_pin(store: Store, id: Text) : Result(Option(PinnedRoot), ModbError)
  pins = try ensure_pinned_roots(store)
  Ok(pins.get(id))
end

## Starts an uncommitted write transaction against the current committed main line.
fn begin_write(store: Store) : WriteTx
  WriteTx(
    base: store,
    alloc: empty_allocator(store.meta.page_count, store.ready_free),
    catalog_root: store.meta.catalog_root,
    dirty_buckets: {},
    dirty: false,
    speculative: false,
    added_pins: {},
    removed_pins: Set.empty
  )
end

## Starts an isolated, non-committable speculative `WriteTx` rooted at a pinned `cat_root`
## (used by `Modb.World` to evaluate in-world reads and calls without touching the main line).
fn begin_write_from_root(store: Store, cat_root: Int) : WriteTx
  WriteTx(
    base: store,
    alloc: empty_allocator(store.meta.page_count, []),
    catalog_root: cat_root,
    dirty_buckets: {},
    dirty: false,
    speculative: true,
    added_pins: {},
    removed_pins: Set.empty
  )
end

fn tx_bucket_root(tx: WriteTx, bucket: Text) : Result(Int, ModbError)
  return Error(InvalidArgument(reason: "bucket name cannot be empty")) if bucket.empty?
  case tx.dirty_buckets.get(bucket)
    Some(pid): Ok(pid)
    None: lookup_bucket_root(tx.base.pager, tx.alloc.staged, tx.catalog_root, bucket)
  end
end

## Reads a key inside a write transaction (sees uncommitted writes in this tx).
fn tx_get(tx: WriteTx, bucket: Text, key: Bytes) : Result(Option(Bytes), ModbError)
  bucket_root = try tx_bucket_root(tx, bucket)
  Tree.get_tx(tx.base.pager, tx.alloc, bucket_root, key)
end

## Scans a key range inside a write transaction (sees uncommitted writes in this tx).
fn tx_scan(tx: WriteTx, bucket: Text, start_key: Option(Bytes), end_key: Option(Bytes), limit: Int) : Result(
  List((Bytes, Bytes)),
  ModbError
)
  bucket_root = try tx_bucket_root(tx, bucket)
  Tree.scan_tx(tx.base.pager, tx.alloc, bucket_root, start_key, end_key, limit)
end

fn tx_put_raw(tx: WriteTx, bucket: Text, key: Bytes, value: Bytes) : Result(WriteTx, ModbError)
  bucket_root = try tx_bucket_root(tx, bucket)
  (a1, new_bucket_root) = try Tree.put(tx.base.pager, tx.alloc, bucket_root, key, value)
  var next = tx
  next.alloc = a1
  next.dirty_buckets = next.dirty_buckets.set(bucket, new_bucket_root)
  next.dirty = true
  Ok(next)
end

fn tx_delete_raw(tx: WriteTx, bucket: Text, key: Bytes) : Result(WriteTx, ModbError)
  bucket_root = try tx_bucket_root(tx, bucket)
  return Ok(tx) if bucket_root == 0
  (a1, new_bucket_root, deleted?) = try Tree.delete(tx.base.pager, tx.alloc, bucket_root, key)
  return Ok(tx) if not deleted?
  var next = tx
  next.alloc = a1
  next.dirty_buckets = next.dirty_buckets.set(bucket, new_bucket_root)
  next.dirty = true
  Ok(next)
end

## Inserts or updates `(key, value)` in `bucket`, creating the bucket if needed.
fn tx_put(tx: WriteTx, bucket: Text, key: Bytes, value: Bytes) : Result(WriteTx, ModbError)
  if bucket == pins_bucket
    return Error(InvalidArgument(reason: "use tx_pin_base_root / tx_unpin_root to manage pins"))
  end
  tx_put_raw(tx, bucket, key, value)
end

## Deletes `key` from `bucket`. Removes the bucket from the catalog if it becomes empty.
fn tx_delete(tx: WriteTx, bucket: Text, key: Bytes) : Result(WriteTx, ModbError)
  if bucket == pins_bucket
    return Error(InvalidArgument(reason: "use tx_pin_base_root / tx_unpin_root to manage pins"))
  end
  tx_delete_raw(tx, bucket, key)
end

## Deletes an entire bucket and frees all of its pages.
fn tx_delete_bucket(tx: WriteTx, bucket: Text) : Result(WriteTx, ModbError)
  if bucket == pins_bucket
    return Error(InvalidArgument(reason: "cannot delete internal #{pins_bucket} bucket"))
  end
  bucket_root = try tx_bucket_root(tx, bucket)
  return Ok(tx) if bucket_root == 0
  a1 = try free_tree(tx.base.pager, tx.alloc, bucket_root)
  var next = tx
  next.alloc = a1
  next.dirty_buckets = next.dirty_buckets.set(bucket, 0)
  next.dirty = true
  Ok(next)
end

fn effective_pins(tx: WriteTx) : Result(Map(Text, PinnedRoot), ModbError)
  var pins = try ensure_pinned_roots(tx.base)
  for rid in tx.removed_pins
    pins = pins.remove(rid)
  end
  for (id, pin) in tx.added_pins.entries
    pins = pins.set(id, pin)
  end
  Ok(pins)
end

## Records a crash-safe persistent pin of `tx.base.meta.catalog_root` (at `tx.base.meta.txid`) inside `tx`.
fn tx_pin_base_root(tx: WriteTx, id: Text) : Result((WriteTx, PinnedRoot), ModbError)
  if id.trim.empty?
    return Error(InvalidArgument(reason: "pin id cannot be empty"))
  end
  if tx.speculative
    return Error(InvalidArgument(reason: "cannot persist pin inside a speculative WriteTx"))
  end
  cur_pins = try effective_pins(tx)
  if cur_pins.has?(id)
    return Error(InvalidArgument(reason: "pin '#{id}' already exists"))
  end
  pin = PinnedRoot(id: id, txid: tx.base.meta.txid, catalog_root: tx.base.meta.catalog_root)
  var next = try tx_put_raw(tx, pins_bucket, id.bytes, encode_pinned_root(pin))
  next.removed_pins = next.removed_pins.remove(id)
  next.added_pins = next.added_pins.set(id, pin)
  Ok((next, pin))
end

## Removes a crash-safe persistent root pin inside `tx`, allowing deferred pages to reclaim on commit.
fn tx_unpin_root(tx: WriteTx, id: Text) : Result(WriteTx, ModbError)
  if tx.speculative
    return Error(InvalidArgument(reason: "cannot unpin inside a speculative WriteTx"))
  end
  cur_pins = try effective_pins(tx)
  if not cur_pins.has?(id)
    return Error(InvalidArgument(reason: "unknown pin '#{id}'"))
  end
  var next = try tx_delete_raw(tx, pins_bucket, id.bytes)
  next.added_pins = next.added_pins.remove(id)
  next.removed_pins = next.removed_pins.add(id)
  Ok(next)
end

## Atomically persists a root pin of the current committed `Store` state.
fn pin_root(store: Store, id: Text) : Result((Store, PinnedRoot), ModbError)
  tx = begin_write(store)
  (t1, pin) = try tx_pin_base_root(tx, id)
  committed = try commit(t1)
  Ok((committed, pin))
end

## Atomically removes a persisted root pin and graduates any unpinned deferred pages for reuse.
fn unpin_root(store: Store, id: Text) : Result(Store, ModbError)
  tx = begin_write(store)
  t1 = try tx_unpin_root(tx, id)
  commit(t1)
end

## Applies all buffered bucket root updates into `catalog_root` and seals all dirty nodes once.
fn finalize_tx_pages(tx: WriteTx) : Result((Allocator, Int), ModbError)
  var cur_alloc = tx.alloc
  var cur_cat = tx.catalog_root
  for (bname, broot) in tx.dirty_buckets.entries
    if broot == 0
      (a1, next_cat, _d) = try Tree.delete(tx.base.pager, cur_alloc, cur_cat, bname.bytes)
      cur_alloc = a1
      cur_cat = next_cat
    else
      (a1, next_cat) = try Tree.put(
        tx.base.pager,
        cur_alloc,
        cur_cat,
        bname.bytes,
        Bytes.from_i64_be(broot)
      )
      cur_alloc = a1
      cur_cat = next_cat
    end
  end
  flushed = try flush_dirty(cur_alloc)
  Ok((flushed, cur_cat))
end

## Discards an uncommitted write transaction, returning the untouched `Store`.
fn rollback(tx: WriteTx) : Store
  tx.base
end

fn freelist_pages_needed(ready_count: Int, deferred_count: Int) : Int
  r_pages = if ready_count <= 0: 0 else: (ready_count + max_freelist_entries - 1) /
    max_freelist_entries
  d_pages = if deferred_count <= 0
    0
  else
    (deferred_count + max_deferred_freelist_entries - 1) / max_deferred_freelist_entries
  end
  r_pages + d_pages
end

## Stages the persisted freelist chain (ready `kind_freelist` chunks followed by deferred
## `kind_deferred_freelist` chunks), preserving exact crash-safe page partition invariants.
fn stage_freelist(
  alloc: Allocator,
  extra_ready: List(Int),
  deferred_entries: List(DeferredPageEntry)
) : Result((Allocator, Int, List(Int)), ModbError)
  var cur_alloc = alloc
  var chain_pids = []
  while freelist_pages_needed(cur_alloc.reusable.size + extra_ready.size, deferred_entries.size) >
    chain_pids.size
    (a1, pid) = alloc_page(cur_alloc)
    cur_alloc = a1
    chain_pids = chain_pids.append(pid)
  end
  return Ok((cur_alloc, 0, [])) if chain_pids.empty?

  all_ready = cur_alloc.reusable.concat(extra_ready)
  r_pages = if all_ready.size <= 0
    0
  else
    (all_ready.size + max_freelist_entries - 1) / max_freelist_entries
  end
  d_pages = if deferred_entries.size <= 0
    0
  else
    (deferred_entries.size + max_deferred_freelist_entries - 1) / max_deferred_freelist_entries
  end
  ## If allocating chain pages shrank `cur_alloc.reusable` below a chunk boundary, any trailing
  ## allocated chain page simply carries an empty `ReadyChunk` so every allocated page is accounted.
  total_ready_slots = chain_pids.size - d_pages

  var next_pid = 0
  var d_idx = d_pages - 1
  while d_idx >= 0
    pid = chain_pids.get(total_ready_slots + d_idx) or stop "valid deferred freelist chain pid"
    start = d_idx * max_deferred_freelist_entries
    slice_es = if start >= deferred_entries.size
      []
    else
      deferred_entries.drop(start).take(max_deferred_freelist_entries)
    end
    raw = try encode_deferred_freelist(
      pid,
      DeferredFreelistPage(next_page: next_pid, entries: slice_es)
    )
    cur_alloc.staged = cur_alloc.staged.set(pid, raw)
    next_pid = pid
    d_idx -= 1
  end

  var r_idx = total_ready_slots - 1
  while r_idx >= 0
    pid = chain_pids.get(r_idx) or stop "valid ready freelist chain pid"
    start = r_idx * max_freelist_entries
    slice_ps = if start >= all_ready.size or r_idx >= r_pages
      []
    else
      all_ready.drop(start).take(max_freelist_entries)
    end
    raw = try encode_freelist(pid, FreelistPage(next_page: next_pid, pages: slice_ps))
    cur_alloc.staged = cur_alloc.staged.set(pid, raw)
    next_pid = pid
    r_idx -= 1
  end
  Ok((cur_alloc, next_pid, chain_pids))
end

fn partition_deferred_for_commit(
  base_deferred: List(DeferredFree),
  new_txid: Int,
  tree_freed: List(Int),
  min_pin: Int
) : (List(Int), List(DeferredFree))
  all_deferred = if tree_freed.empty?
    base_deferred
  else
    base_deferred.append(DeferredFree(txid: new_txid, pages: tree_freed))
  end
  var graduated = []
  var kept = []
  for df in all_deferred
    if df.txid <= min_pin
      graduated = graduated.concat(df.pages)
    else
      kept = kept.append(df)
    end
  end
  (graduated, kept)
end

## Atomically commits a `WriteTx`:
## 1. Stages freelist pages (ready + pin-protected deferred chunks) without overwriting old freelist.
## 2. Writes all staged CoW pages and calls `sync`.
## 3. Writes the alternating meta-page (`new_txid % 2`) and calls `sync`.
fn commit(tx: WriteTx) : Result(Store, ModbError)
  if tx.speculative
    return Error(
      InvalidArgument(reason: "cannot commit a speculative WriteTx rooted at a pinned snapshot")
    )
  end
  return Ok(tx.base) if not tx.dirty
  new_txid = tx.base.meta.txid + 1

  (a_dirty, final_catalog_root) = try finalize_tx_pages(tx)
  next_pins = try effective_pins(tx)
  min_pin = min_pin_txid(tx.base.snapshots, next_pins, new_txid)

  ## Tree pages freed during this commit stay deferred while any snapshot or persisted pin < new_txid.
  ## Old freelist chain pages are never referenced by pinned catalog roots, so they become reusable on T+1.
  (graduated_ready, next_deferred) = partition_deferred_for_commit(
    tx.base.deferred_frees,
    new_txid,
    a_dirty.pending_free,
    min_pin
  )
  extra_ready = tx.base.freelist_pages.concat(graduated_ready)
  deferred_flat = flatten_deferred(next_deferred)

  (a_fl, new_fl_root, new_fl_chain) = try stage_freelist(a_dirty, extra_ready, deferred_flat)

  ## Step 3: write all staged CoW data, branch, overflow, and freelist pages.
  var pager = tx.base.pager
  for (pid, raw) in a_fl.staged.entries
    pager = try write_page(pager, pid, raw)
  end
  ## Step 4: sync all new pages BEFORE touching either meta-page.
  pager = try sync(pager)

  ## Step 5 & 6: flip the alternating meta-page and sync.
  new_meta = MetaPage(
    txid: new_txid,
    catalog_root: final_catalog_root,
    freelist_root: new_fl_root,
    page_count: a_fl.next_page_id
  )
  meta_slot = new_txid % 2
  pager = try write_page(pager, meta_slot, encode_meta(new_meta))
  pager = try sync(pager)

  next_ready = a_fl.reusable.concat(extra_ready)

  Ok(
    Store(
      pager: pager,
      meta: new_meta,
      freelist_pages: new_fl_chain,
      ready_free: next_ready,
      deferred_frees: next_deferred,
      snapshots: tx.base.snapshots,
      pinned_roots: next_pins,
      pins_loaded: true,
      next_snapshot_id: tx.base.next_snapshot_id
    )
  )
end

## Convenience wrapper executing a pure transaction callback atomically.
fn write_tx(store: Store, work: fn(WriteTx) : Result(WriteTx, ModbError)) : Result(Store, ModbError)
  tx = begin_write(store)
  updated = try work(tx)
  commit(updated)
end

## Takes an O(1) immutable snapshot pinning the current committed root.
fn snapshot(store: Store) : (Store, Snapshot)
  snap = Snapshot(
    id: store.next_snapshot_id,
    txid: store.meta.txid,
    catalog_root: store.meta.catalog_root
  )
  var next = store
  next.snapshots = next.snapshots.set(snap.id, snap)
  next.next_snapshot_id = snap.id + 1
  (next, snap)
end

## Point lookup against a pinned snapshot.
fn snapshot_get(store: Store, snap: Snapshot, bucket: Text, key: Bytes) : Result(
  Option(Bytes),
  ModbError
)
  if not store.snapshots.has?(snap.id)
    return Error(SnapshotUnknown(id: snap.id))
  end
  bucket_root = try lookup_bucket_root(store.pager, {}, snap.catalog_root, bucket)
  Tree.get(store.pager, {}, bucket_root, key)
end

## Range scan against a pinned snapshot.
fn snapshot_scan(
  store: Store,
  snap: Snapshot,
  bucket: Text,
  start_key: Option(Bytes),
  end_key: Option(Bytes),
  limit: Int
) : Result(List((Bytes, Bytes)), ModbError)
  if not store.snapshots.has?(snap.id)
    return Error(SnapshotUnknown(id: snap.id))
  end
  bucket_root = try lookup_bucket_root(store.pager, {}, snap.catalog_root, bucket)
  Tree.scan(store.pager, {}, bucket_root, start_key, end_key, limit)
end

## Releases a pinned snapshot and graduates any deferred free pages no longer pinned.
fn release_snapshot(store: Store, snap: Snapshot) : Result(Store, ModbError)
  if not store.snapshots.has?(snap.id)
    return Error(SnapshotUnknown(id: snap.id))
  end
  var next = store
  next.snapshots = next.snapshots.remove(snap.id)
  pins = try ensure_pinned_roots(next)
  next.pinned_roots = pins
  next.pins_loaded = true
  min_pin = min_pin_txid(next.snapshots, pins, next.meta.txid)
  var next_ready = next.ready_free
  var next_deferred = []
  for df in next.deferred_frees
    if df.txid <= min_pin
      next_ready = next_ready.concat(df.pages)
    else
      next_deferred = next_deferred.append(df)
    end
  end
  next.ready_free = next_ready
  next.deferred_frees = next_deferred
  Ok(next)
end

## Structural O(diff) comparison of a single bucket between two committed/pinned catalog roots.
fn diff_bucket_roots(store: Store, root_a: Int, root_b: Int, bucket: Text) : Result(
  List(KeyDiff),
  ModbError
)
  return Ok([]) if root_a == root_b
  ba = try lookup_bucket_root(store.pager, {}, root_a, bucket)
  bb = try lookup_bucket_root(store.pager, {}, root_b, bucket)
  diff_trees(store.pager, {}, {}, ba, bb)
end

fn diff_catalog_roots_internal(
  pager: BlockStore,
  staged_a: Map(Int, Bytes),
  staged_b: Map(Int, Bytes),
  root_a: Int,
  root_b: Int
) : Result((List(BucketDiff), DiffStats), ModbError)
  (cat_diffs, cat_stats) = try diff_trees_with_stats(pager, staged_a, staged_b, root_a, root_b)
  var stats = cat_stats
  var out = []
  for cd in cat_diffs
    case cd
      Added(key: kb, value: vb):
        bname = try kb.decode_utf8.or_fail(Corrupt(reason: "non-utf8 bucket name in diff"))
        bb = try decode_bucket_root(vb)
        (changes, st) = try diff_trees_with_stats(pager, staged_a, staged_b, 0, bb)
        stats.pages_read += st.pages_read
        stats.subtrees_skipped += st.subtrees_skipped
        if not changes.empty?
          out = out.append(BucketDiff(bucket: bname, changes: changes))
        end
      Removed(key: kb, value: va):
        bname = try kb.decode_utf8.or_fail(Corrupt(reason: "non-utf8 bucket name in diff"))
        ba = try decode_bucket_root(va)
        (changes, st) = try diff_trees_with_stats(pager, staged_a, staged_b, ba, 0)
        stats.pages_read += st.pages_read
        stats.subtrees_skipped += st.subtrees_skipped
        if not changes.empty?
          out = out.append(BucketDiff(bucket: bname, changes: changes))
        end
      Modified(key: kb, old_value: va, new_value: vb):
        bname = try kb.decode_utf8.or_fail(Corrupt(reason: "non-utf8 bucket name in diff"))
        ba = try decode_bucket_root(va)
        bb = try decode_bucket_root(vb)
        (changes, st) = try diff_trees_with_stats(pager, staged_a, staged_b, ba, bb)
        stats.pages_read += st.pages_read
        stats.subtrees_skipped += st.subtrees_skipped
        if not changes.empty?
          out = out.append(BucketDiff(bucket: bname, changes: changes))
        end
    end
  end
  Ok((out, stats))
end

## Structural O(diff) comparison across all buckets between two committed/pinned catalog roots,
## returning both bucket diffs and subtree-skip telemetry.
fn diff_roots_with_stats(store: Store, root_a: Int, root_b: Int) : Result(
  (List(BucketDiff), DiffStats),
  ModbError
)
  diff_catalog_roots_internal(store.pager, {}, {}, root_a, root_b)
end

## Structural O(diff) comparison across all buckets between two committed/pinned catalog roots.
fn diff_roots(store: Store, root_a: Int, root_b: Int) : Result(List(BucketDiff), ModbError)
  (diffs, _stats) = try diff_roots_with_stats(store, root_a, root_b)
  Ok(diffs)
end

## Structural O(diff) comparison from `base_root` to the uncommitted state staged in `tx`
## (without modifying disk).
fn diff_tx_from_root(tx: WriteTx, base_root: Int) : Result(List(BucketDiff), ModbError)
  (a_dirty, final_cat) = try finalize_tx_pages(tx)
  (diffs, _stats) = try diff_catalog_roots_internal(
    tx.base.pager,
    {},
    a_dirty.staged,
    base_root,
    final_cat
  )
  Ok(diffs)
end

## Full structural & page-accounting integrity check:
## verifies every reachable page checksum, sorted key order, exact disjoint partition
## `{0, 1} U catalog U buckets U freelist_chain U ready_free U deferred_frees == {0 .. page_count - 1}`,
## and verifies every persisted root pin in `_modb_pins` is intact and protected from reuse.
fn verify(store: Store) : Result(VerifyReport, ModbError)
  cold_pager = clear_cache(store.pager)
  var seen = Set.empty.add(0).add(1)
  var live_and_deferred = Set.empty.add(0).add(1)
  var live_count = 2

  catalog_pages = try collect_tree_pages(cold_pager, {}, store.meta.catalog_root)
  for pid in catalog_pages
    if pid < 2 or pid >= store.meta.page_count
      return Error(Corrupt(reason: "catalog page #{pid} out of bounds"))
    end
    if seen.has?(pid)
      return Error(Corrupt(reason: "duplicate reference to catalog page #{pid}"))
    end
    seen = seen.add(pid)
    live_and_deferred = live_and_deferred.add(pid)
    live_count += 1
  end

  catalog_rows = try Tree.scan(cold_pager, {}, store.meta.catalog_root, None, None, 0)
  for (_bname, raw_root) in catalog_rows
    broot = try decode_bucket_root(raw_root)
    bpages = try collect_tree_pages(cold_pager, {}, broot)
    for pid in bpages
      if pid < 2 or pid >= store.meta.page_count
        return Error(Corrupt(reason: "bucket page #{pid} out of bounds"))
      end
      if seen.has?(pid)
        return Error(Corrupt(reason: "duplicate reference to bucket page #{pid}"))
      end
      seen = seen.add(pid)
      live_and_deferred = live_and_deferred.add(pid)
      live_count += 1
    end
  end

  (fl_chain, fl_ready, fl_deferred) = try load_freelist(
    cold_pager,
    store.meta.freelist_root,
    store.meta.page_count
  )
  for pid in fl_chain
    if seen.has?(pid)
      return Error(Corrupt(reason: "freelist chain page #{pid} overlaps live tree"))
    end
    seen = seen.add(pid)
  end
  var free_total = 0
  for pid in fl_ready
    if seen.has?(pid)
      return Error(Corrupt(reason: "freelist entry #{pid} overlaps live or duplicate free page"))
    end
    seen = seen.add(pid)
    free_total += 1
  end
  for df in fl_deferred
    for pid in df.pages
      if seen.has?(pid)
        return Error(Corrupt(reason: "deferred free page #{pid} overlaps live or duplicate page"))
      end
      seen = seen.add(pid)
      live_and_deferred = live_and_deferred.add(pid)
      free_total += 1
    end
  end

  if seen.size != store.meta.page_count
    return Error(
      Corrupt(
        reason: "page leak detected: accounted #{seen.size} of #{store.meta.page_count} pages"
      )
    )
  end

  ## Verify every persisted root pin in `_modb_pins`: every reachable page must pass SHA-256
  ## verification and live in `current_trees U deferred_frees` (never in `ready_free` or `fl_chain`).
  pins = try load_pinned_roots(
    cold_pager,
    store.meta.catalog_root,
    store.meta.page_count,
    store.meta.txid
  )
  for pin in pins.values
    p_cat_pages = try collect_tree_pages(cold_pager, {}, pin.catalog_root)
    for pid in p_cat_pages
      if not live_and_deferred.has?(pid)
        return Error(
          Corrupt(
            reason: "pinned root '#{pin.id}' catalog page #{pid} is in ready_free/unprotected"
          )
        )
      end
    end
    p_cat_rows = try Tree.scan(cold_pager, {}, pin.catalog_root, None, None, 0)
    for (_pbname, prow) in p_cat_rows
      pbroot = try decode_bucket_root(prow)
      pbpages = try collect_tree_pages(cold_pager, {}, pbroot)
      for pid in pbpages
        if not live_and_deferred.has?(pid)
          return Error(
            Corrupt(
              reason: "pinned root '#{pin.id}' bucket page #{pid} is in ready_free/unprotected"
            )
          )
        end
      end
    end
  end

  Ok(
    VerifyReport(
      txid: store.meta.txid,
      page_count: store.meta.page_count,
      bucket_count: catalog_rows.size,
      live_pages: live_count,
      freelist_chain_pages: fl_chain.size,
      free_entries: free_total
    )
  )
end

## Runs the real commit write sequence up to a crash boundary on a simulated disk and injects
## a power cut via `simulate_crash`:
## - `phase == 1`: writes staged CoW/freelist pages, crashes BEFORE syncing them (meta untouched).
## - `phase == 2`: writes and syncs CoW/freelist pages, writes meta-page, crashes BEFORE syncing meta.
fn commit_and_crash(tx: WriteTx, phase: Int, rng: Random) : Result(BlockStore, ModbError)
  if tx.speculative
    return Error(InvalidArgument(reason: "cannot commit_and_crash a speculative WriteTx"))
  end
  return Ok(simulate_crash(tx.base.pager, rng)) if not tx.dirty
  new_txid = tx.base.meta.txid + 1
  (a_dirty, final_catalog_root) = try finalize_tx_pages(tx)
  next_pins = try effective_pins(tx)
  min_pin = min_pin_txid(tx.base.snapshots, next_pins, new_txid)
  (graduated_ready, next_deferred) = partition_deferred_for_commit(
    tx.base.deferred_frees,
    new_txid,
    a_dirty.pending_free,
    min_pin
  )
  extra_ready = tx.base.freelist_pages.concat(graduated_ready)
  (a_fl, new_fl_root, _new_fl_chain) = try stage_freelist(
    a_dirty,
    extra_ready,
    flatten_deferred(next_deferred)
  )

  var pager = tx.base.pager
  for (pid, raw) in a_fl.staged.entries
    pager = try write_page(pager, pid, raw)
  end
  return Ok(simulate_crash(pager, rng)) if phase <= 1

  pager = try sync(pager)
  new_meta = MetaPage(
    txid: new_txid,
    catalog_root: final_catalog_root,
    freelist_root: new_fl_root,
    page_count: a_fl.next_page_id
  )
  pager = try write_page(pager, new_txid % 2, encode_meta(new_meta))
  Ok(simulate_crash(pager, rng))
end

test "Modb basic lifecycle, snapshots, persistence and exact page accounting"
  files = Files.in_memory({})
  assert open(files, "app.modb") is Ok(db0)
  var db = db0
  assert verify(db) is Ok(_)

  assert write_tx(
    db,
    fn(tx)
      t1 = try tx_put(tx, "users", "u:1".bytes, "Ada".bytes)
      tx_put(t1, "users", "u:2".bytes, "Grace".bytes)
    end
  ) is
    Ok(db1)
  db = db1

  assert get(db, "users", "u:1".bytes) == Ok(Some("Ada".bytes))
  assert buckets(db) == Ok(["users"])
  assert verify(db) is Ok(_)

  ## Take snapshot before overwriting u:1
  (db_pinned, snap) = snapshot(db)
  db = db_pinned
  assert write_tx(db, fn(tx) tx_put(tx, "users", "u:1".bytes, "Ada Lovelace".bytes) end) is Ok(db2)
  db = db2

  assert get(db, "users", "u:1".bytes) == Ok(Some("Ada Lovelace".bytes))
  assert snapshot_get(db, snap, "users", "u:1".bytes) == Ok(Some("Ada".bytes))
  assert verify(db) is Ok(_)

  assert release_snapshot(db, snap) is Ok(db3)
  db = db3
  assert snapshot_get(db, snap, "users", "u:1".bytes) is Error(SnapshotUnknown(id: _))

  ## Reopen from the same Files capability and verify durability
  assert open(files, "app.modb") is Ok(reopened)
  assert get(reopened, "users", "u:1".bytes) == Ok(Some("Ada Lovelace".bytes))
  assert get(reopened, "users", "u:2".bytes) == Ok(Some("Grace".bytes))
  assert verify(reopened) is Ok(_)
end

test "Modb read-only open and advisory shared/exclusive lock helpers"
  files = Files.in_memory({})
  ro = files.read_only

  ## Missing file returns Io(NotFound) on ReadFiles.open
  assert open_read_only(ro, "missing.modb") is Error(Io(NotFound(path: _)))

  ## Create and write under exclusive lock
  assert with_exclusive_lock(
    files,
    "locked.modb",
    fn(e) e end,
    fn(db0)
      db1 = try write_tx(db0, fn(tx) tx_put(tx, "kv", "k1".bytes, "v1".bytes) end)
      Ok(txid(db1))
    end
  ) ==
    Ok(2)

  ## Read under shared lock via ReadFiles (never requires Files)
  assert with_shared_lock(
    ro,
    "locked.modb",
    fn(e) e end,
    fn(db_ro) get(db_ro, "kv", "k1".bytes) end
  ) ==
    Ok(Some("v1".bytes))

  ## Writing through a read-only Store is refused at the host boundary with Io(NotAllowed)
  assert open_read_only(ro, "locked.modb") is Ok(ro_store)
  assert write_tx(ro_store, fn(tx) tx_put(tx, "kv", "k2".bytes, "v2".bytes) end) is
    Error(Io(NotAllowed(path: _)))
end
