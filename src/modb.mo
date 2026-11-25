## MoDB Layer 1: Single-file Copy-on-Write B+Tree ordered key-value database in pure Mo.
module Modb
expose Store(..),
WriteTx(..),
Snapshot(..),
VerifyReport(..),
open,
open_file,
open_disk,
txid,
page_count,
free_page_count,
buckets,
get,
scan,
prefix_scan,
begin_write,
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
verify,
commit_and_crash
use Modb.Codec{
  FreelistPage,
  MetaPage,
  decode_freelist,
  decode_meta,
  encode_freelist,
  encode_meta,
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
  alloc_page,
  collect_tree_pages,
  empty_allocator,
  flush_dirty,
  free_page,
  free_tree
}

## Pages freed at commit `txid`, held back until no open snapshot predates `txid`.
struct DeferredFree
  txid: Int
  pages: List(Int)
end

## Open database handle holding committed meta state, freelist bookkeeping, and snapshot pins.
struct Store
  pager: BlockStore
  meta: MetaPage
  freelist_pages: List(Int)
  ready_free: List(Int)
  deferred_frees: List(DeferredFree)
  snapshots: Map(Int, Snapshot)
  next_snapshot_id: Int
end

## Uncommitted write transaction staging CoW pages before atomic meta-page flip.
struct WriteTx
  base: Store
  alloc: Allocator
  catalog_root: Int
  dirty_buckets: Map(Text, Int)
  dirty: Bool
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

## Opens or initializes a MoDB database on an already-open `Files.File` handle.
fn open_file(file: Files.File) : Result(Store, ModbError)
  open_disk(from_file(file))
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
      next_snapshot_id: 1
    )
  )
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
  (chain_pids, free_entries) = try load_freelist(store, chosen.freelist_root, chosen.page_count)
  Ok(
    Store(
      pager: store,
      meta: chosen,
      freelist_pages: chain_pids,
      ready_free: free_entries,
      deferred_frees: [],
      snapshots: {},
      next_snapshot_id: 1
    )
  )
end

fn load_freelist(store: BlockStore, freelist_root: Int, max_pages: Int) : Result(
  (List(Int), List(Int)),
  ModbError
)
  return Ok(([], [])) if freelist_root == 0
  var chain = []
  var entries = []
  var cur = freelist_root
  var steps = 0
  while cur != 0
    steps += 1
    return Error(Corrupt(reason: "freelist cycle detected")) if steps > max_pages
    raw = try read_page(store, cur)
    fl = try decode_freelist(raw, cur)
    chain = chain.append(cur)
    for pid in fl.pages
      if pid < 2 or pid >= max_pages
        return Error(Corrupt(reason: "freelist page id #{pid} out of bounds"))
      end
      entries = entries.append(pid)
    end
    cur = fl.next_page
  end
  Ok((chain, entries))
end

## Current committed transaction ID.
fn txid(store: Store) : Int
  store.meta.txid
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

## Starts an uncommitted write transaction.
fn begin_write(store: Store) : WriteTx
  WriteTx(
    base: store,
    alloc: empty_allocator(store.meta.page_count, store.ready_free),
    catalog_root: store.meta.catalog_root,
    dirty_buckets: {},
    dirty: false
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

## Inserts or updates `(key, value)` in `bucket`, creating the bucket if needed.
fn tx_put(tx: WriteTx, bucket: Text, key: Bytes, value: Bytes) : Result(WriteTx, ModbError)
  bucket_root = try tx_bucket_root(tx, bucket)
  (a1, new_bucket_root) = try Tree.put(tx.base.pager, tx.alloc, bucket_root, key, value)
  var next = tx
  next.alloc = a1
  next.dirty_buckets = next.dirty_buckets.set(bucket, new_bucket_root)
  next.dirty = true
  Ok(next)
end

## Deletes `key` from `bucket`. Removes the bucket from the catalog if it becomes empty.
fn tx_delete(tx: WriteTx, bucket: Text, key: Bytes) : Result(WriteTx, ModbError)
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

## Deletes an entire bucket and frees all of its pages.
fn tx_delete_bucket(tx: WriteTx, bucket: Text) : Result(WriteTx, ModbError)
  bucket_root = try tx_bucket_root(tx, bucket)
  return Ok(tx) if bucket_root == 0
  a1 = try free_tree(tx.base.pager, tx.alloc, bucket_root)
  var next = tx
  next.alloc = a1
  next.dirty_buckets = next.dirty_buckets.set(bucket, 0)
  next.dirty = true
  Ok(next)
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

fn freelist_pages_needed(entry_count: Int) : Int
  if entry_count <= 0: 0 else: (entry_count + max_freelist_entries - 1) / max_freelist_entries
end

## Stages the persisted freelist chain pages, preserving the exact disk page partition invariant.
fn stage_freelist(alloc: Allocator, other_free: List(Int)) : Result(
  (Allocator, Int, List(Int)),
  ModbError
)
  var cur_alloc = alloc
  var chain_pids = []
  while freelist_pages_needed(cur_alloc.reusable.size + other_free.size) > chain_pids.size
    (a1, pid) = alloc_page(cur_alloc)
    cur_alloc = a1
    chain_pids = chain_pids.append(pid)
  end
  return Ok((cur_alloc, 0, [])) if chain_pids.empty?
  all_entries = cur_alloc.reusable.concat(other_free)
  var i = chain_pids.size - 1
  var next_pid = 0
  while i >= 0
    pid = chain_pids.get(i) or stop "valid freelist chain pid"
    start = i * max_freelist_entries
    slice_entries = if start >= all_entries.size
      []
    else
      all_entries.drop(start).take(max_freelist_entries)
    end
    raw = try encode_freelist(pid, FreelistPage(next_page: next_pid, pages: slice_entries))
    cur_alloc.staged = cur_alloc.staged.set(pid, raw)
    next_pid = pid
    i -= 1
  end
  Ok((cur_alloc, next_pid, chain_pids))
end

## Computes the lowest pinned snapshot txid, or `new_txid` if no snapshot is open.
fn min_snapshot_txid(snapshots: Map(Int, Snapshot), fallback: Int) : Int
  var lowest = fallback
  for snap in snapshots.values
    lowest = lowest.min(snap.txid)
  end
  lowest
end

## Atomically commits a `WriteTx`:
## 1. Stages freelist pages (without overwriting the previous commit's freelist chain).
## 2. Writes all staged CoW pages and calls `sync`.
## 3. Writes the alternating meta-page (`new_txid % 2`) and calls `sync`.
fn commit(tx: WriteTx) : Result(Store, ModbError)
  return Ok(tx.base) if not tx.dirty
  new_txid = tx.base.meta.txid + 1

  (a_dirty, final_catalog_root) = try finalize_tx_pages(tx)

  ## Free the previous commit's freelist chain pages (kept intact on disk during this commit).
  var cur_alloc = a_dirty
  for old_fl_pid in tx.base.freelist_pages
    cur_alloc = free_page(cur_alloc, old_fl_pid)
  end

  ## Gather all free pages not in `reusable` (previously deferred + freed during this commit).
  var other_free = []
  for df in tx.base.deferred_frees
    other_free = other_free.concat(df.pages)
  end
  other_free = other_free.concat(cur_alloc.pending_free)

  (a_fl, new_fl_root, new_fl_chain) = try stage_freelist(cur_alloc, other_free)

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

  ## Graduate deferred frees once no open snapshot predates them.
  all_deferred = if a_fl.pending_free.empty?
    tx.base.deferred_frees
  else
    tx.base.deferred_frees.append(DeferredFree(txid: new_txid, pages: a_fl.pending_free))
  end
  min_pin = min_snapshot_txid(tx.base.snapshots, new_txid)
  var next_ready = a_fl.reusable
  var next_deferred = []
  for df in all_deferred
    if df.txid <= min_pin
      next_ready = next_ready.concat(df.pages)
    else
      next_deferred = next_deferred.append(df)
    end
  end

  Ok(
    Store(
      pager: pager,
      meta: new_meta,
      freelist_pages: new_fl_chain,
      ready_free: next_ready,
      deferred_frees: next_deferred,
      snapshots: tx.base.snapshots,
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
  min_pin = min_snapshot_txid(next.snapshots, next.meta.txid)
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

## Full structural & page-accounting integrity check:
## verifies every reachable page checksum, sorted key order, and exact disjoint partition
## `{0, 1} U catalog U buckets U freelist_chain U freelist_entries == {0 .. page_count - 1}`.
fn verify(store: Store) : Result(VerifyReport, ModbError)
  cold_pager = clear_cache(store.pager)
  var seen = Set.empty.add(0).add(1)
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
      live_count += 1
    end
  end

  (fl_chain, fl_entries) = try load_freelist(
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
  for pid in fl_entries
    if seen.has?(pid)
      return Error(Corrupt(reason: "freelist entry #{pid} overlaps live or duplicate free page"))
    end
    seen = seen.add(pid)
  end

  if seen.size != store.meta.page_count
    return Error(
      Corrupt(
        reason: "page leak detected: accounted #{seen.size} of #{store.meta.page_count} pages"
      )
    )
  end

  Ok(
    VerifyReport(
      txid: store.meta.txid,
      page_count: store.meta.page_count,
      bucket_count: catalog_rows.size,
      live_pages: live_count,
      freelist_chain_pages: fl_chain.size,
      free_entries: fl_entries.size
    )
  )
end

## Runs the real commit write sequence up to a crash boundary on a simulated disk and injects
## a power cut via `simulate_crash`:
## - `phase == 1`: writes staged CoW/freelist pages, crashes BEFORE syncing them (meta untouched).
## - `phase == 2`: writes and syncs CoW/freelist pages, writes meta-page, crashes BEFORE syncing meta.
fn commit_and_crash(tx: WriteTx, phase: Int, rng: Random) : Result(BlockStore, ModbError)
  return Ok(simulate_crash(tx.base.pager, rng)) if not tx.dirty
  new_txid = tx.base.meta.txid + 1
  (a_dirty, final_catalog_root) = try finalize_tx_pages(tx)
  var cur_alloc = a_dirty
  for old_fl_pid in tx.base.freelist_pages
    cur_alloc = free_page(cur_alloc, old_fl_pid)
  end
  var other_free = []
  for df in tx.base.deferred_frees
    other_free = other_free.concat(df.pages)
  end
  other_free = other_free.concat(cur_alloc.pending_free)
  (a_fl, new_fl_root, _new_fl_chain) = try stage_freelist(cur_alloc, other_free)

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
