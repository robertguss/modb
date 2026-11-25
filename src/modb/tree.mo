## Pure Copy-on-Write (CoW) B+Tree over 4 KiB pages with O(1) size-tracked dirty-node buffering,
## right-edge sequential splitting, zero-decode raw lookups/scans, overflow chains, and rebalancing.
module Modb.Tree
expose Allocator(..),
KeyDiff(..),
DiffStats(..),
empty_allocator,
alloc_page,
free_page,
flush_dirty,
read_node_page,
get,
get_tx,
scan,
scan_tx,
count_entries,
put,
delete,
free_tree,
collect_tree_pages,
diff_trees,
diff_trees_with_stats
use Modb.Codec{
  BranchEntry,
  BranchNode,
  LeafEntry,
  LeafNode,
  OverflowPage,
  ValueRef,
  body_size,
  branch_lookup_child_raw,
  branch_scan_children_raw,
  decode_branch_unchecked,
  decode_branch_with_bytes_unchecked,
  decode_leaf_unchecked,
  decode_leaf_with_bytes_unchecked,
  decode_overflow,
  encode_branch,
  encode_leaf,
  encode_overflow,
  kind_branch,
  kind_leaf,
  leaf_lookup_entry_raw,
  leaf_scan_raw,
  max_inline_value,
  max_key_size,
  max_overflow_chunk,
  read_header_fast,
  verify_header,
  verify_leaf_raw
}
use Modb.Errors{ModbError}
use Modb.Pager{BlockStore, page_size, read_page, sim_empty}

## Thresholds for merging adjacent underfull sibling nodes after deletes.
merge_trigger_bytes = 1024
merge_target_bytes = 3800

## Buffered dirty leaf paired with its exact encoded body byte size and O(1) locality hint.
struct DirtyLeaf
  entries: List(LeafEntry)
  body_bytes: Int
  hint: Int
end

## Buffered dirty branch paired with its exact encoded body byte size.
struct DirtyBranch
  first_child: Int
  entries: List(BranchEntry)
  body_bytes: Int
end

## Per-transaction CoW page allocator and dirty-node buffer.
## Committed pages are never overwritten. Modified branch/leaf nodes stay decoded in
## `dirty_branches` / `dirty_leaves` during the transaction and are serialized + SHA-256
## sealed once at commit via `flush_dirty`.
struct Allocator
  next_page_id: Int
  reusable: List(Int)
  pending_free: List(Int)
  staged: Map(Int, Bytes)
  dirty_leaves: Map(Int, DirtyLeaf)
  dirty_branches: Map(Int, DirtyBranch)
end

## Single key-level difference between two B+Tree versions (`root_a -> root_b`).
enum KeyDiff
  Added(key: Bytes, value: Bytes)
  Removed(key: Bytes, value: Bytes)
  Modified(key: Bytes, old_value: Bytes, new_value: Bytes)
end

## Telemetry reported by `diff_trees_with_stats` proving untouched CoW subtrees are skipped.
struct DiffStats
  pages_read: Int
  subtrees_skipped: Int
end

## Internal branch child key-range descriptor used for O(diff) subtree alignment.
struct ChildSpan
  page_id: Int
  low: Option(Bytes)
  high: Option(Bytes)
end

## Internal result of recursive CoW insert.
enum PutResult
  PutUpdated(alloc: Allocator, page_id: Int)
  PutSplit(alloc: Allocator, left_id: Int, sep_key: Bytes, right_id: Int)
end

## Creates an allocator starting from the committed `page_count` and reusable freelist.
fn empty_allocator(page_count: Int, reusable: List(Int)) : Allocator
  Allocator(
    next_page_id: page_count,
    reusable: reusable,
    pending_free: [],
    staged: {},
    dirty_leaves: {},
    dirty_branches: {}
  )
end

## True if `page_id` was freshly allocated inside this uncommitted transaction.
fn is_tx_owned?(alloc: Allocator, page_id: Int) : Bool
  alloc.dirty_leaves.has?(page_id) or
    alloc.dirty_branches.has?(page_id) or
    alloc.staged.has?(page_id)
end

## Allocates a fresh page ID from `reusable` (popping from the end) or extends `next_page_id`.
fn alloc_page(alloc: Allocator) : (Allocator, Int)
  var next = alloc
  if not next.reusable.empty?
    idx = next.reusable.size - 1
    pid = next.reusable.last or stop "non-empty reusable"
    next.reusable = next.reusable.take(idx)
    (next, pid)
  else
    pid = next.next_page_id
    next.next_page_id = pid + 1
    (next, pid)
  end
end

## Frees a page ID: uncommitted tx-owned pages recycle immediately into `reusable`;
## committed pages go into `pending_free` so they stay intact on disk until commit.
fn free_page(alloc: Allocator, page_id: Int) : Allocator
  return alloc if page_id < 2
  var next = alloc
  if is_tx_owned?(next, page_id)
    next.dirty_leaves = next.dirty_leaves.remove(page_id)
    next.dirty_branches = next.dirty_branches.remove(page_id)
    next.staged = next.staged.remove(page_id)
    next.reusable = next.reusable.append(page_id)
  else
    next.pending_free = next.pending_free.append(page_id)
  end
  next
end

## Picks the destination page ID for rewriting `old_page_id`:
## reuses `old_page_id` in place if it was created in this uncommitted tx,
## otherwise allocates a new page and marks `old_page_id` pending free.
fn prepare_target(alloc: Allocator, old_page_id: Int) : (Allocator, Int)
  if old_page_id >= 2 and is_tx_owned?(alloc, old_page_id)
    (alloc, old_page_id)
  else
    next = if old_page_id >= 2: free_page(alloc, old_page_id) else: alloc
    alloc_page(next)
  end
end

## Encodes and SHA-256 seals all buffered dirty leaves and branches into `alloc.staged`.
fn flush_dirty(alloc: Allocator) : Result(Allocator, ModbError)
  var next = alloc
  for (pid, leaf) in next.dirty_leaves.entries
    raw = try encode_leaf(pid, LeafNode(entries: leaf.entries))
    next.staged = next.staged.set(pid, raw)
  end
  for (pid, branch) in next.dirty_branches.entries
    raw = try encode_branch(
      pid,
      BranchNode(first_child: branch.first_child, entries: branch.entries)
    )
    next.staged = next.staged.set(pid, raw)
  end
  next.dirty_leaves = {}
  next.dirty_branches = {}
  Ok(next)
end

## Reads a page, verifying SHA-256 once when loaded from cold disk (skipping re-hash on cache hits).
fn read_node_page(store: BlockStore, staged: Map(Int, Bytes), page_id: Int) : Result(
  Bytes,
  ModbError
)
  case staged.get(page_id)
    Some(raw): Ok(raw)
    None:
      case store.cache.get(page_id)
        Some(cached): Ok(cached)
        None:
          raw = try read_page(store, page_id)
          _ = try verify_header(raw, page_id)
          Ok(raw)
      end
  end
end

## Binary search over sorted `LeafEntry` list with O(1) right-edge and sequential-overwrite hints:
## returns `(index, found?)`.
fn leaf_search_hinted(entries: List(LeafEntry), target: Bytes, hint: Int) : (Int, Bool)
  n = entries.size
  return (0, false) if n == 0
  last_k = (entries.get(n - 1) or stop "valid leaf last").key
  if last_k < target
    return (n, false)
  end
  next_h = hint + 1
  if next_h >= 0 and next_h < n
    if (entries.get(next_h) or stop "valid leaf hint").key == target
      return (next_h, true)
    end
  end
  if last_k == target
    return (n - 1, true)
  end
  var lo = 0
  var hi = n - 1
  while lo < hi
    mid = lo + (hi - lo) / 2
    k = (entries.get(mid) or stop "valid leaf mid").key
    if k < target
      lo = mid + 1
    else if target < k
      hi = mid
    else
      return (mid, true)
    end
  end
  (lo, false)
end

## Binary search over sorted `LeafEntry` list with O(1) right-edge fast path: returns `(index, found?)`.
fn leaf_binary_search(entries: List(LeafEntry), target: Bytes) : (Int, Bool)
  leaf_search_hinted(entries, target, -2)
end

## Binary search over sorted `BranchEntry` list with O(1) right-edge fast path:
## returns child slot index `0..entries.size`.
fn branch_child_index(entries: List(BranchEntry), target: Bytes) : Int
  n = entries.size
  return 0 if n == 0
  last_sep = (entries.get(n - 1) or stop "valid branch last").key
  return n if target >= last_sep
  var lo = 0
  var hi = n - 1
  while lo < hi
    mid = lo + (hi - lo) / 2
    sep = (entries.get(mid) or stop "valid branch mid").key
    if target < sep
      hi = mid
    else
      lo = mid + 1
    end
  end
  lo
end

## Writes a large (>1,024 byte) value as a linked chain of overflow pages.
fn write_overflow_chain(alloc: Allocator, data: Bytes) : Result((Allocator, ValueRef), ModbError)
  if data.size <= max_inline_value
    return Ok((alloc, Inline(data: data)))
  end
  total = data.size
  chunks = (total + max_overflow_chunk - 1) / max_overflow_chunk
  var cur_alloc = alloc
  var next_pid = 0
  var i = chunks - 1
  while i >= 0
    start = i * max_overflow_chunk
    finish = (start + max_overflow_chunk).min(total)
    chunk = data.slice(start, finish)
    (a1, pid) = alloc_page(cur_alloc)
    raw = try encode_overflow(pid, OverflowPage(next_page: next_pid, data: chunk))
    var a2 = a1
    a2.staged = a2.staged.set(pid, raw)
    cur_alloc = a2
    next_pid = pid
    i -= 1
  end
  Ok((cur_alloc, Overflow(first_page: next_pid, total_len: total)))
end

## Reads a value reference, following overflow pages if needed.
fn materialize_value(store: BlockStore, staged: Map(Int, Bytes), vref: ValueRef) : Result(
  Bytes,
  ModbError
)
  case vref
    Inline(data: d): Ok(d)
    Overflow(first_page: first_pid, total_len: total_len):
      return Error(Corrupt(reason: "negative overflow total_len")) if total_len < 0
      max_steps = total_len / max_overflow_chunk + 2
      var parts = []
      var collected = 0
      var cur = first_pid
      var steps = 0
      while cur != 0
        steps += 1
        return Error(Corrupt(reason: "overflow chain cycle detected")) if steps > max_steps
        raw = try read_node_page(store, staged, cur)
        ov = try decode_overflow(raw, cur)
        parts = parts.append(ov.data)
        collected += ov.data.size
        cur = ov.next_page
      end
      if collected != total_len
        return Error(
          Corrupt(reason: "overflow length mismatch: expected #{total_len}, got #{collected}")
        )
      end
      Ok(Bytes.join(parts))
  end
end

## Frees every page in an overflow chain (no-op for inline values).
fn free_value_ref(store: BlockStore, alloc: Allocator, vref: ValueRef) : Result(
  Allocator,
  ModbError
)
  case vref
    Inline(data: _): Ok(alloc)
    Overflow(first_page: first_pid, total_len: total_len):
      max_steps = total_len / max_overflow_chunk + 2
      var cur_alloc = alloc
      var cur = first_pid
      var steps = 0
      while cur != 0
        steps += 1
        return Error(Corrupt(reason: "overflow chain cycle while freeing")) if steps > max_steps
        raw = try read_node_page(store, cur_alloc.staged, cur)
        ov = try decode_overflow(raw, cur)
        cur_alloc = free_page(cur_alloc, cur)
        cur = ov.next_page
      end
      Ok(cur_alloc)
  end
end

## Point lookup on committed pages using single-verify zero-decode inline binary search.
fn get(store: BlockStore, staged: Map(Int, Bytes), root_id: Int, key: Bytes) : Result(
  Option(Bytes),
  ModbError
)
  return Ok(None) if root_id == 0
  var cur = root_id
  var depth = 0
  while true
    depth += 1
    return Error(Corrupt(reason: "b-tree depth limit exceeded")) if depth > 64
    raw = try read_node_page(store, staged, cur)
    if raw.size != page_size
      return Error(Corrupt(reason: "page #{cur} size #{raw.size} != #{page_size}"))
    end
    kind = case raw.u16_be_at(0)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated kind"))
    end
    count = case raw.u16_be_at(2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated entry_count"))
    end
    if raw.i64_be_at(8) != Some(cur)
      return Error(Corrupt(reason: "page id mismatch on page #{cur}"))
    end
    if kind == kind_branch
      cur = try branch_lookup_child_raw(raw, count, key)
    else if kind == kind_leaf
      case try leaf_lookup_entry_raw(raw, count, key)
        None: return Ok(None)
        Some(Inline(data: d)): return Ok(Some(d))
        Some(vref):
          val = try materialize_value(store, staged, vref)
          return Ok(Some(val))
      end
    else
      return Error(Corrupt(reason: "unexpected page kind #{kind} at page #{cur}"))
    end
  end
  Ok(None)
end

## Point lookup inside an active WriteTx (sees buffered dirty nodes and staged overflows).
fn get_tx(store: BlockStore, alloc: Allocator, root_id: Int, key: Bytes) : Result(
  Option(Bytes),
  ModbError
)
  return Ok(None) if root_id == 0
  var cur = root_id
  var depth = 0
  while true
    depth += 1
    return Error(Corrupt(reason: "b-tree depth limit exceeded")) if depth > 64
    case alloc.dirty_branches.get(cur)
      Some(branch):
        idx = branch_child_index(branch.entries, key)
        cur = child_at(branch.first_child, branch.entries, idx)
        continue
      None: Unit
    end
    case alloc.dirty_leaves.get(cur)
      Some(leaf):
        (pos, found) = leaf_binary_search(leaf.entries, key)
        return Ok(None) if not found
        e = leaf.entries.get(pos) or stop "valid dirty leaf pos"
        case e.value
          Inline(data: d): return Ok(Some(d))
          Overflow(first_page: _, total_len: _):
            val = try materialize_value(store, alloc.staged, e.value)
            return Ok(Some(val))
        end
      None: Unit
    end
    raw = try read_node_page(store, alloc.staged, cur)
    if raw.size != page_size
      return Error(Corrupt(reason: "page #{cur} size #{raw.size} != #{page_size}"))
    end
    kind = case raw.u16_be_at(0)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated kind"))
    end
    count = case raw.u16_be_at(2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated entry_count"))
    end
    if raw.i64_be_at(8) != Some(cur)
      return Error(Corrupt(reason: "page id mismatch on page #{cur}"))
    end
    if kind == kind_branch
      cur = try branch_lookup_child_raw(raw, count, key)
    else if kind == kind_leaf
      case try leaf_lookup_entry_raw(raw, count, key)
        None: return Ok(None)
        Some(Inline(data: d)): return Ok(Some(d))
        Some(vref):
          val = try materialize_value(store, alloc.staged, vref)
          return Ok(Some(val))
      end
    else
      return Error(Corrupt(reason: "unexpected page kind #{kind} at page #{cur}"))
    end
  end
  Ok(None)
end

## Pruned recursive in-order scan on committed pages over `[start_key, end_key)`.
fn scan(
  store: BlockStore,
  staged: Map(Int, Bytes),
  root_id: Int,
  start_key: Option(Bytes),
  end_key: Option(Bytes),
  limit: Int
) : Result(List((Bytes, Bytes)), ModbError)
  return Ok([]) if root_id == 0
  scan_node(store, staged, {}, {}, root_id, start_key, end_key, limit, [], 0)
end

## Pruned recursive in-order scan inside an active WriteTx.
fn scan_tx(
  store: BlockStore,
  alloc: Allocator,
  root_id: Int,
  start_key: Option(Bytes),
  end_key: Option(Bytes),
  limit: Int
) : Result(List((Bytes, Bytes)), ModbError)
  return Ok([]) if root_id == 0
  scan_node(
    store,
    alloc.staged,
    alloc.dirty_leaves,
    alloc.dirty_branches,
    root_id,
    start_key,
    end_key,
    limit,
    [],
    0
  )
end

## Counts total key-value entries in a committed/staged tree by reading leaf headers only
## (zero cell, key, or value decoding).
fn count_entries(store: BlockStore, staged: Map(Int, Bytes), root_id: Int) : Result(Int, ModbError)
  return Ok(0) if root_id == 0
  count_node(store, staged, root_id, 0)
end

fn count_node(store: BlockStore, staged: Map(Int, Bytes), page_id: Int, depth: Int) : Result(
  Int,
  ModbError
)
  return Error(Corrupt(reason: "b-tree depth exceeded")) if depth > 64
  raw = case staged.get(page_id)
    Some(r): r
    None: try read_page(store, page_id)
  end
  hdr = try read_header_fast(raw, page_id)
  if hdr.kind == kind_leaf
    return Ok(hdr.entry_count)
  end
  if hdr.kind != kind_branch
    return Error(Corrupt(reason: "expected leaf or branch at page #{page_id}"))
  end
  children = try branch_scan_children_raw(raw, hdr.entry_count, None, None)
  var total = 0
  for cid in children
    total += try count_node(store, staged, cid, depth + 1)
  end
  Ok(total)
end

fn scan_leaf_entries(
  store: BlockStore,
  staged: Map(Int, Bytes),
  entries: List(LeafEntry),
  start_key: Option(Bytes),
  end_key: Option(Bytes),
  limit: Int,
  acc: List((Bytes, Bytes))
) : Result(List((Bytes, Bytes)), ModbError)
  var out = acc
  start_idx = case start_key
    Some(s): leaf_binary_search(entries, s).0
    None: 0
  end
  var i = start_idx
  while i < entries.size
    break if limit > 0 and out.size >= limit
    e = entries.get(i) or stop "valid scan leaf idx"
    at_or_past_end = case end_key
      Some(ek): e.key >= ek
      None: false
    end
    break if at_or_past_end
    val = try materialize_value(store, staged, e.value)
    out = out.append((e.key, val))
    i += 1
  end
  Ok(out)
end

fn scan_branch_node(
  store: BlockStore,
  staged: Map(Int, Bytes),
  dirty_leaves: Map(Int, DirtyLeaf),
  dirty_branches: Map(Int, DirtyBranch),
  first_child: Int,
  entries: List(BranchEntry),
  start_key: Option(Bytes),
  end_key: Option(Bytes),
  limit: Int,
  acc: List((Bytes, Bytes)),
  depth: Int
) : Result(List((Bytes, Bytes)), ModbError)
  var out = acc
  count = entries.size
  var child_idx = case start_key
    Some(s): branch_child_index(entries, s)
    None: 0
  end
  while child_idx <= count
    break if limit > 0 and out.size >= limit
    if child_idx > 0
      lower = (entries.get(child_idx - 1) or stop "valid branch index").key
      past_end = case end_key
        Some(ek): lower >= ek
        None: false
      end
      break if past_end
    end
    child_pid = child_at(first_child, entries, child_idx)
    out = try scan_node(
      store,
      staged,
      dirty_leaves,
      dirty_branches,
      child_pid,
      start_key,
      end_key,
      limit,
      out,
      depth + 1
    )
    child_idx += 1
  end
  Ok(out)
end

fn scan_node(
  store: BlockStore,
  staged: Map(Int, Bytes),
  dirty_leaves: Map(Int, DirtyLeaf),
  dirty_branches: Map(Int, DirtyBranch),
  page_id: Int,
  start_key: Option(Bytes),
  end_key: Option(Bytes),
  limit: Int,
  acc: List((Bytes, Bytes)),
  depth: Int
) : Result(List((Bytes, Bytes)), ModbError)
  return Error(Corrupt(reason: "b-tree depth limit exceeded during scan")) if depth > 64
  return Ok(acc) if limit > 0 and acc.size >= limit
  case dirty_leaves.get(page_id)
    Some(leaf): return scan_leaf_entries(
      store,
      staged,
      leaf.entries,
      start_key,
      end_key,
      limit,
      acc
    )
    None: Unit
  end
  case dirty_branches.get(page_id)
    Some(branch): return scan_branch_node(
      store,
      staged,
      dirty_leaves,
      dirty_branches,
      branch.first_child,
      branch.entries,
      start_key,
      end_key,
      limit,
      acc,
      depth
    )
    None: Unit
  end
  raw = try read_node_page(store, staged, page_id)
  if raw.size != page_size
    return Error(Corrupt(reason: "page #{page_id} size #{raw.size} != #{page_size}"))
  end
  kind = case raw.u16_be_at(0)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated kind"))
  end
  count = case raw.u16_be_at(2)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated entry_count"))
  end
  if raw.i64_be_at(8) != Some(page_id)
    return Error(Corrupt(reason: "page id mismatch on page #{page_id}"))
  end
  if kind == kind_leaf
    rem = if limit > 0: limit - acc.size else: 0
    raw_rows = try leaf_scan_raw(raw, count, start_key, end_key, rem)
    var out = acc
    for (k, vref) in raw_rows
      case vref
        Inline(data: d): out = out.append((k, d))
        Overflow(first_page: _, total_len: _):
          val = try materialize_value(store, staged, vref)
          out = out.append((k, val))
      end
    end
    Ok(out)
  else if kind == kind_branch
    children = try branch_scan_children_raw(raw, count, start_key, end_key)
    var out = acc
    for child_pid in children
      break if limit > 0 and out.size >= limit
      out = try scan_node(
        store,
        staged,
        dirty_leaves,
        dirty_branches,
        child_pid,
        start_key,
        end_key,
        limit,
        out,
        depth + 1
      )
    end
    Ok(out)
  else
    Error(Corrupt(reason: "unexpected page kind #{kind} at page #{page_id}"))
  end
end

fn leaf_entry_bytes(e: LeafEntry) : Int
  case e.value
    Inline(data: d): 8 + e.key.size + d.size
    Overflow(first_page: _, total_len: _): 22 + e.key.size
  end
end

fn branch_entry_bytes(e: BranchEntry) : Int
  12 + e.key.size
end

## Finds a split index `1 <= mid <= entries.size - 1` so both leaf halves fit within `body_size`,
## returning `(mid, left_bytes, right_bytes)`.
fn find_leaf_split(entries: List(LeafEntry), total: Int) : (Int, Int, Int)
  target = total / 2
  var left_bytes = 0
  var best = 1
  var best_left = leaf_entry_bytes(entries.first or stop "non-empty leaf split")
  for i in 0..(entries.size - 1)
    e = entries.get(i) or stop "valid leaf split index"
    left_bytes += leaf_entry_bytes(e)
    right_bytes = total - left_bytes
    if left_bytes <= body_size and right_bytes <= body_size
      best = i + 1
      best_left = left_bytes
      break if left_bytes >= target
    end
  end
  (best, best_left, total - best_left)
end

## Finds a promotion index `1 <= mid <= entries.size - 2` for splitting a branch node,
## returning `(mid, left_bytes, right_bytes)`. Uses `right_edge?` to pack sequential appends ~90%.
fn find_branch_split(entries: List(BranchEntry), total: Int, right_edge?: Bool) : (Int, Int, Int)
  target = if right_edge?: (total * 9) / 10 else: total / 2
  var left_bytes = 8
  var best = 1
  var best_left = 8 + branch_entry_bytes(entries.first or stop "non-empty branch split")
  var best_right = total - best_left
  for i in 0..(entries.size - 1)
    e = entries.get(i) or stop "valid branch split index"
    eb = branch_entry_bytes(e)
    if i >= 1 and i <= entries.size - 2
      right_bytes = total - left_bytes - eb + 8
      if left_bytes <= body_size and right_bytes <= body_size
        best = i
        best_left = left_bytes
        best_right = right_bytes
        break if left_bytes >= target
      end
    end
    left_bytes += eb
  end
  (best, best_left, best_right)
end

fn buffer_leaf_owned(
  alloc: Allocator,
  pid: Int,
  entries: List(LeafEntry),
  body_bytes: Int,
  hint: Int
) : (Allocator, Int)
  var a = alloc
  a.dirty_leaves = a.dirty_leaves.set(
    pid,
    DirtyLeaf(entries: entries, body_bytes: body_bytes, hint: hint)
  )
  (a, pid)
end

fn buffer_leaf(alloc: Allocator, old_pid: Int, entries: List(LeafEntry), body_bytes: Int, hint: Int) : (
  Allocator,
  Int
)
  (a1, dst) = prepare_target(alloc, old_pid)
  var a2 = a1
  a2.staged = a2.staged.remove(dst)
  a2.dirty_branches = a2.dirty_branches.remove(dst)
  a2.dirty_leaves = a2.dirty_leaves.set(
    dst,
    DirtyLeaf(entries: entries, body_bytes: body_bytes, hint: hint)
  )
  (a2, dst)
end

fn buffer_branch(
  alloc: Allocator,
  old_pid: Int,
  first_child: Int,
  entries: List(BranchEntry),
  body_bytes: Int
) : (Allocator, Int)
  (a1, dst) = prepare_target(alloc, old_pid)
  var a2 = a1
  a2.staged = a2.staged.remove(dst)
  a2.dirty_leaves = a2.dirty_leaves.remove(dst)
  a2.dirty_branches = a2.dirty_branches.set(
    dst,
    DirtyBranch(first_child: first_child, entries: entries, body_bytes: body_bytes)
  )
  (a2, dst)
end

## Inserts or updates `(key, value)` in the CoW B+Tree rooted at `root_id`.
fn put(store: BlockStore, alloc: Allocator, root_id: Int, key: Bytes, value: Bytes) : Result(
  (Allocator, Int),
  ModbError
)
  if key.size > max_key_size
    return Error(KeyTooLarge(size: key.size, max: max_key_size))
  end
  (a1, vref) = try write_overflow_chain(alloc, value)
  if root_id == 0
    entry = LeafEntry(key: key, value: vref)
    return Ok(buffer_leaf(a1, 0, [entry], leaf_entry_bytes(entry), 0))
  end
  case try put_node(store, a1, root_id, key, vref, 0)
    PutUpdated(alloc: a2, page_id: new_root): Ok((a2, new_root))
    PutSplit(alloc: a2, left_id: left_id, sep_key: sep, right_id: right_id):
      be = BranchEntry(key: sep, child: right_id)
      Ok(buffer_branch(a2, 0, left_id, [be], 8 + branch_entry_bytes(be)))
  end
end

fn put_node(
  store: BlockStore,
  alloc: Allocator,
  page_id: Int,
  key: Bytes,
  vref: ValueRef,
  depth: Int
) : Result(PutResult, ModbError)
  return Error(Corrupt(reason: "b-tree depth limit exceeded during put")) if depth > 64
  var cur_alloc = alloc
  case cur_alloc.dirty_leaves.get(page_id)
    Some(DirtyLeaf(entries: entries, body_bytes: bbytes, hint: hint)):
      ## Detach from `dirty_leaves` so `entries` has refcount == 1 for O(1) Perceus in-place mutation!
      cur_alloc.dirty_leaves = cur_alloc.dirty_leaves.remove(page_id)
      return put_in_leaf(store, cur_alloc, page_id, true, entries, bbytes, hint, key, vref)
    None: Unit
  end
  case cur_alloc.dirty_branches.get(page_id)
    Some(branch): return put_in_branch(
      store,
      cur_alloc,
      page_id,
      branch.first_child,
      branch.entries,
      branch.body_bytes,
      key,
      vref,
      depth
    )
    None: Unit
  end
  raw = try read_node_page(store, cur_alloc.staged, page_id)
  hdr = try read_header_fast(raw, page_id)
  if hdr.kind == kind_leaf
    (leaf, bbytes) = try decode_leaf_with_bytes_unchecked(raw, page_id)
    put_in_leaf(store, cur_alloc, page_id, false, leaf.entries, bbytes, -2, key, vref)
  else if hdr.kind == kind_branch
    (branch, bbytes) = try decode_branch_with_bytes_unchecked(raw, page_id)
    put_in_branch(
      store,
      cur_alloc,
      page_id,
      branch.first_child,
      branch.entries,
      bbytes,
      key,
      vref,
      depth
    )
  else
    Error(Corrupt(reason: "unexpected page kind #{hdr.kind} at page #{page_id}"))
  end
end

fn put_in_leaf(
  store: BlockStore,
  alloc: Allocator,
  page_id: Int,
  tx_owned?: Bool,
  entries: List(LeafEntry),
  old_bytes: Int,
  hint: Int,
  key: Bytes,
  vref: ValueRef
) : Result(PutResult, ModbError)
  var cur_alloc = alloc
  (pos, found) = leaf_search_hinted(entries, key, hint)
  new_entry = LeafEntry(key: key, value: vref)
  new_eb = leaf_entry_bytes(new_entry)
  next_bytes = if found
    existing = entries.get(pos) or stop "valid leaf index"
    old_eb = leaf_entry_bytes(existing)
    case existing.value
      Inline(data: _): Unit
      Overflow(first_page: _, total_len: _): cur_alloc = try free_value_ref(
        store,
        cur_alloc,
        existing.value
      )
    end
    old_bytes - old_eb + new_eb
  else
    old_bytes + new_eb
  end

  if next_bytes <= body_size
    updated = if found
      entries.set(pos, new_entry) or stop "valid leaf replace index"
    else if pos == entries.size
      entries.append(new_entry)
    else
      entries.take(pos).append(new_entry).concat(entries.drop(pos))
    end
    (a1, new_pid) = if tx_owned?
      buffer_leaf_owned(cur_alloc, page_id, updated, next_bytes, pos)
    else
      buffer_leaf(cur_alloc, page_id, updated, next_bytes, pos)
    end
    Ok(PutUpdated(alloc: a1, page_id: new_pid))
  else if not found and pos == entries.size and not entries.empty?
    ## Right-edge sequential split: keep left leaf ~98% packed without slicing, start right leaf cleanly!
    (a1, left_pid) = if tx_owned?
      buffer_leaf_owned(cur_alloc, page_id, entries, old_bytes, pos - 1)
    else
      buffer_leaf(cur_alloc, page_id, entries, old_bytes, pos - 1)
    end
    (a2, right_pid) = buffer_leaf(a1, 0, [new_entry], new_eb, 0)
    Ok(PutSplit(alloc: a2, left_id: left_pid, sep_key: new_entry.key, right_id: right_pid))
  else
    updated = if found
      entries.set(pos, new_entry) or stop "valid leaf replace index"
    else if pos == entries.size
      entries.append(new_entry)
    else
      entries.take(pos).append(new_entry).concat(entries.drop(pos))
    end
    (mid, left_bytes, right_bytes) = find_leaf_split(updated, next_bytes)
    left_entries = updated.take(mid)
    right_entries = updated.drop(mid)
    sep_key = (right_entries.first or stop "non-empty right leaf").key
    (a1, left_pid) = if tx_owned?
      buffer_leaf_owned(cur_alloc, page_id, left_entries, left_bytes, -2)
    else
      buffer_leaf(cur_alloc, page_id, left_entries, left_bytes, -2)
    end
    (a2, right_pid) = buffer_leaf(a1, 0, right_entries, right_bytes, -2)
    Ok(PutSplit(alloc: a2, left_id: left_pid, sep_key: sep_key, right_id: right_pid))
  end
end

fn put_in_branch(
  store: BlockStore,
  alloc: Allocator,
  page_id: Int,
  first_child: Int,
  entries: List(BranchEntry),
  old_bytes: Int,
  key: Bytes,
  vref: ValueRef,
  depth: Int
) : Result(PutResult, ModbError)
  idx = branch_child_index(entries, key)
  target_child = child_at(first_child, entries, idx)
  case try put_node(store, alloc, target_child, key, vref, depth + 1)
    PutUpdated(alloc: a1, page_id: new_child):
      ## Zero-mutation fast path: child stayed at same tx-owned page_id and branch is already dirty!
      if new_child == target_child and a1.dirty_branches.has?(page_id)
        return Ok(PutUpdated(alloc: a1, page_id: page_id))
      end
      if idx == 0
        (a2, new_pid) = buffer_branch(a1, page_id, new_child, entries, old_bytes)
        Ok(PutUpdated(alloc: a2, page_id: new_pid))
      else
        old_e = entries.get(idx - 1) or stop "valid branch index"
        updated_entries = entries.set(idx - 1, BranchEntry(key: old_e.key, child: new_child)) or
          stop "valid branch set"
        (a2, new_pid) = buffer_branch(a1, page_id, first_child, updated_entries, old_bytes)
        Ok(PutUpdated(alloc: a2, page_id: new_pid))
      end
    PutSplit(alloc: a1, left_id: left_id, sep_key: sep_key, right_id: right_id):
      var next_first = first_child
      var updated_entries = entries
      new_be = BranchEntry(key: sep_key, child: right_id)
      next_bytes = old_bytes + branch_entry_bytes(new_be)
      right_edge? = idx == entries.size
      if idx == 0
        next_first = left_id
        updated_entries = updated_entries.prepend(new_be)
      else
        old_e = updated_entries.get(idx - 1) or stop "valid branch index"
        updated_entries = updated_entries.set(idx - 1, BranchEntry(key: old_e.key, child: left_id)) or
          stop "valid branch set"
        if right_edge?
          updated_entries = updated_entries.append(new_be)
        else
          updated_entries = updated_entries.take(idx).append(new_be).concat(
            updated_entries.drop(idx)
          )
        end
      end
      if next_bytes <= body_size
        (a2, new_pid) = buffer_branch(a1, page_id, next_first, updated_entries, next_bytes)
        Ok(PutUpdated(alloc: a2, page_id: new_pid))
      else
        (mid, left_bytes, right_bytes) = find_branch_split(updated_entries, next_bytes, right_edge?)
        promoted = updated_entries.get(mid) or stop "valid promoted entry"
        left_entries = updated_entries.take(mid)
        right_entries = updated_entries.drop(mid + 1)
        (a2, left_pid) = buffer_branch(a1, page_id, next_first, left_entries, left_bytes)
        (a3, right_pid) = buffer_branch(a2, 0, promoted.child, right_entries, right_bytes)
        Ok(PutSplit(alloc: a3, left_id: left_pid, sep_key: promoted.key, right_id: right_pid))
      end
  end
end

## Deletes `key` from the CoW B+Tree, merging underfull siblings and collapsing single-child roots.
## Returns `(allocator, new_root_id, deleted?)` where `new_root_id == 0` when the tree is empty.
fn delete(store: BlockStore, alloc: Allocator, root_id: Int, key: Bytes) : Result(
  (Allocator, Int, Bool),
  ModbError
)
  return Ok((alloc, 0, false)) if root_id == 0
  delete_node(store, alloc, root_id, key, 0)
end

fn delete_in_leaf(
  store: BlockStore,
  alloc: Allocator,
  page_id: Int,
  entries: List(LeafEntry),
  old_bytes: Int,
  key: Bytes
) : Result((Allocator, Int, Bool), ModbError)
  (pos, found) = leaf_binary_search(entries, key)
  return Ok((alloc, page_id, false)) if not found
  removed = entries.get(pos) or stop "valid removed leaf entry"
  a1 = try free_value_ref(store, alloc, removed.value)
  remaining = entries.remove_at(pos) or stop "valid remove_at"
  if remaining.empty?
    a2 = free_page(a1, page_id)
    Ok((a2, 0, true))
  else
    (a2, new_pid) = buffer_leaf(a1, page_id, remaining, old_bytes - leaf_entry_bytes(removed), -2)
    Ok((a2, new_pid, true))
  end
end

fn delete_node(store: BlockStore, alloc: Allocator, page_id: Int, key: Bytes, depth: Int) : Result(
  (Allocator, Int, Bool),
  ModbError
)
  return Error(Corrupt(reason: "b-tree depth limit exceeded during delete")) if depth > 64
  case alloc.dirty_leaves.get(page_id)
    Some(leaf): return delete_in_leaf(store, alloc, page_id, leaf.entries, leaf.body_bytes, key)
    None: Unit
  end
  case alloc.dirty_branches.get(page_id)
    Some(branch): return delete_in_branch(
      store,
      alloc,
      page_id,
      branch.first_child,
      branch.entries,
      branch.body_bytes,
      key,
      depth
    )
    None: Unit
  end
  raw = try read_node_page(store, alloc.staged, page_id)
  hdr = try read_header_fast(raw, page_id)
  if hdr.kind == kind_leaf
    (leaf, bbytes) = try decode_leaf_with_bytes_unchecked(raw, page_id)
    delete_in_leaf(store, alloc, page_id, leaf.entries, bbytes, key)
  else if hdr.kind == kind_branch
    (branch, bbytes) = try decode_branch_with_bytes_unchecked(raw, page_id)
    delete_in_branch(store, alloc, page_id, branch.first_child, branch.entries, bbytes, key, depth)
  else
    Error(Corrupt(reason: "unexpected page kind #{hdr.kind} at page #{page_id}"))
  end
end

fn delete_in_branch(
  store: BlockStore,
  alloc: Allocator,
  page_id: Int,
  first_child: Int,
  entries: List(BranchEntry),
  old_bytes: Int,
  key: Bytes,
  depth: Int
) : Result((Allocator, Int, Bool), ModbError)
  idx = branch_child_index(entries, key)
  target_child = child_at(first_child, entries, idx)
  (a1, new_child, deleted?) = try delete_node(store, alloc, target_child, key, depth + 1)
  return Ok((a1, page_id, false)) if not deleted?

  var cur_alloc = a1
  var next_first = first_child
  var next_entries = entries
  var next_bytes = old_bytes

  if new_child == 0
    if idx == 0
      if next_entries.empty?
        cur_alloc = free_page(cur_alloc, page_id)
        return Ok((cur_alloc, 0, true))
      end
      first_e = next_entries.first or stop "non-empty branch entries"
      next_first = first_e.child
      next_entries = next_entries.drop(1)
      next_bytes -= branch_entry_bytes(first_e)
    else
      rem_e = next_entries.get(idx - 1) or stop "valid branch remove idx"
      next_entries = next_entries.remove_at(idx - 1) or stop "valid branch remove"
      next_bytes -= branch_entry_bytes(rem_e)
    end
  else
    if idx == 0
      next_first = new_child
    else
      old_e = next_entries.get(idx - 1) or stop "valid branch index"
      next_entries = next_entries.set(idx - 1, BranchEntry(key: old_e.key, child: new_child)) or
        stop "valid branch set"
    end
    (a_merged, mf, me, mb) = try maybe_merge_child(
      store,
      cur_alloc,
      next_first,
      next_entries,
      next_bytes,
      idx
    )
    cur_alloc = a_merged
    next_first = mf
    next_entries = me
    next_bytes = mb
  end

  if next_entries.empty?
    cur_alloc = free_page(cur_alloc, page_id)
    Ok((cur_alloc, next_first, true))
  else
    (a_done, new_pid) = buffer_branch(cur_alloc, page_id, next_first, next_entries, next_bytes)
    Ok((a_done, new_pid, true))
  end
end

fn child_at(first_child: Int, entries: List(BranchEntry), idx: Int) : Int
  if idx == 0
    first_child
  else
    (entries.get(idx - 1) or stop "valid child_at index").child
  end
end

fn load_leaf_for_merge(store: BlockStore, alloc: Allocator, pid: Int) : Result(
  Option(DirtyLeaf),
  ModbError
)
  case alloc.dirty_leaves.get(pid)
    Some(l): return Ok(Some(l))
    None: Unit
  end
  return Ok(None) if alloc.dirty_branches.has?(pid)
  raw = try read_node_page(store, alloc.staged, pid)
  hdr = try read_header_fast(raw, pid)
  if hdr.kind == kind_leaf
    (leaf, bbytes) = try decode_leaf_with_bytes_unchecked(raw, pid)
    Ok(Some(DirtyLeaf(entries: leaf.entries, body_bytes: bbytes, hint: -2)))
  else
    Ok(None)
  end
end

fn load_branch_for_merge(store: BlockStore, alloc: Allocator, pid: Int) : Result(
  Option(DirtyBranch),
  ModbError
)
  case alloc.dirty_branches.get(pid)
    Some(b): return Ok(Some(b))
    None: Unit
  end
  return Ok(None) if alloc.dirty_leaves.has?(pid)
  raw = try read_node_page(store, alloc.staged, pid)
  hdr = try read_header_fast(raw, pid)
  if hdr.kind == kind_branch
    (branch, bbytes) = try decode_branch_with_bytes_unchecked(raw, pid)
    Ok(
      Some(
        DirtyBranch(first_child: branch.first_child, entries: branch.entries, body_bytes: bbytes)
      )
    )
  else
    Ok(None)
  end
end

## Attempts to merge an underfull child at `idx` with its left or right sibling.
fn maybe_merge_child(
  store: BlockStore,
  alloc: Allocator,
  first_child: Int,
  entries: List(BranchEntry),
  parent_bytes: Int,
  idx: Int
) : Result((Allocator, Int, List(BranchEntry), Int), ModbError)
  return Ok((alloc, first_child, entries, parent_bytes)) if entries.empty?
  left_idx = if idx > 0: idx - 1 else: 0
  right_idx = left_idx + 1
  return Ok((alloc, first_child, entries, parent_bytes)) if right_idx > entries.size

  left_pid = child_at(first_child, entries, left_idx)
  right_pid = child_at(first_child, entries, right_idx)
  sep_entry = entries.get(left_idx) or stop "valid sep index"
  sep = sep_entry.key

  case (
    try load_leaf_for_merge(store, alloc, left_pid),
    try load_leaf_for_merge(store, alloc, right_pid)
  )
    (Some(ln), Some(rn)):
      lbytes = ln.body_bytes
      rbytes = rn.body_bytes
      if lbytes >= merge_trigger_bytes and rbytes >= merge_trigger_bytes
        return Ok((alloc, first_child, entries, parent_bytes))
      end
      if lbytes + rbytes > merge_target_bytes
        return Ok((alloc, first_child, entries, parent_bytes))
      end
      merged_entries = ln.entries.concat(rn.entries)
      a1 = free_page(alloc, right_pid)
      (a2, merged_pid) = buffer_leaf(a1, left_pid, merged_entries, lbytes + rbytes, -2)
      (nf, ne) = replace_merged_pair(first_child, entries, left_idx, merged_pid)
      return Ok((a2, nf, ne, parent_bytes - branch_entry_bytes(sep_entry)))
    _: Unit
  end

  case (
    try load_branch_for_merge(store, alloc, left_pid),
    try load_branch_for_merge(store, alloc, right_pid)
  )
    (Some(ln), Some(rn)):
      lbytes = ln.body_bytes
      rbytes = rn.body_bytes
      if lbytes >= merge_trigger_bytes and rbytes >= merge_trigger_bytes
        return Ok((alloc, first_child, entries, parent_bytes))
      end
      demoted = BranchEntry(key: sep, child: rn.first_child)
      merged_bytes = lbytes + rbytes - 8 + branch_entry_bytes(demoted)
      if merged_bytes > merge_target_bytes
        return Ok((alloc, first_child, entries, parent_bytes))
      end
      merged_entries = ln.entries.append(demoted).concat(rn.entries)
      a1 = free_page(alloc, right_pid)
      (a2, merged_pid) = buffer_branch(a1, left_pid, ln.first_child, merged_entries, merged_bytes)
      (nf, ne) = replace_merged_pair(first_child, entries, left_idx, merged_pid)
      return Ok((a2, nf, ne, parent_bytes - branch_entry_bytes(sep_entry)))
    _: Unit
  end

  Ok((alloc, first_child, entries, parent_bytes))
end

fn replace_merged_pair(first_child: Int, entries: List(BranchEntry), left_idx: Int, merged_pid: Int) : (
  Int,
  List(BranchEntry)
)
  var nf = first_child
  var ne = entries.remove_at(left_idx) or stop "valid merge sep remove"
  if left_idx == 0
    nf = merged_pid
  else
    prev = ne.get(left_idx - 1) or stop "valid left parent entry"
    ne = ne.set(left_idx - 1, BranchEntry(key: prev.key, child: merged_pid)) or
      stop "valid parent set"
  end
  (nf, ne)
end

## Frees every page (branch, leaf, overflow) belonging to a B+Tree (flushing dirty nodes first if needed).
fn free_tree(store: BlockStore, alloc: Allocator, root_id: Int) : Result(Allocator, ModbError)
  return Ok(alloc) if root_id == 0
  flushed = try flush_dirty(alloc)
  pages = try collect_tree_pages(store, flushed.staged, root_id)
  var cur = flushed
  for pid in pages
    cur = free_page(cur, pid)
  end
  Ok(cur)
end

## Walks and strictly SHA-256 verifies a B+Tree (checksums, sorted keys, branch key bounds,
## overflow chains), returning every reachable page ID.
fn collect_tree_pages(store: BlockStore, staged: Map(Int, Bytes), root_id: Int) : Result(
  List(Int),
  ModbError
)
  return Ok([]) if root_id == 0
  verify_walk(store, staged, root_id, None, None, [], 0)
end

fn verify_walk(
  store: BlockStore,
  staged: Map(Int, Bytes),
  page_id: Int,
  low: Option(Bytes),
  high: Option(Bytes),
  acc: List(Int),
  depth: Int
) : Result(List(Int), ModbError)
  return Error(Corrupt(reason: "b-tree depth exceeded in verify")) if depth > 64
  raw = case staged.get(page_id)
    Some(r): r
    None: try read_page(store, page_id)
  end
  hdr = try verify_header(raw, page_id)
  var pages = acc.append(page_id)
  if hdr.kind == kind_leaf
    overflows = try verify_leaf_raw(raw, hdr.entry_count, page_id, low, high)
    for (fp, tl) in overflows
      max_steps = tl / max_overflow_chunk + 2
      var cur = fp
      var steps = 0
      var seen_bytes = 0
      while cur != 0
        steps += 1
        return Error(Corrupt(reason: "overflow cycle in verify")) if steps > max_steps
        ov_raw = case staged.get(cur)
          Some(r): r
          None: try read_page(store, cur)
        end
        ov = try decode_overflow(ov_raw, cur)
        pages = pages.append(cur)
        seen_bytes += ov.data.size
        cur = ov.next_page
      end
      if seen_bytes != tl
        return Error(Corrupt(reason: "overflow size mismatch in verify"))
      end
    end
    Ok(pages)
  else if hdr.kind == kind_branch
    branch = try decode_branch_unchecked(raw, page_id)
    if branch.entries.empty?
      return Error(Corrupt(reason: "empty branch page #{page_id}"))
    end
    var prev_sep = None
    for i in 0..branch.entries.size
      e = branch.entries.get(i) or stop "valid verify branch idx"
      case prev_sep
        Some(ps): return Error(Corrupt(reason: "unsorted branch separators on page #{page_id}")) if e
          .key <=
          ps
        None: Unit
      end
      prev_sep = Some(e.key)
    end
    first_sep = (branch.entries.first or stop "non-empty branch").key
    pages = try verify_walk(
      store,
      staged,
      branch.first_child,
      low,
      Some(first_sep),
      pages,
      depth + 1
    )
    for i in 0..branch.entries.size
      e = branch.entries.get(i) or stop "valid verify branch idx"
      child_hi = if i + 1 < branch.entries.size
        Some((branch.entries.get(i + 1) or stop "valid next sep").key)
      else
        high
      end
      pages = try verify_walk(store, staged, e.child, Some(e.key), child_hi, pages, depth + 1)
    end
    Ok(pages)
  else
    Error(Corrupt(reason: "unexpected page kind #{hdr.kind} in verify"))
  end
end

fn branch_child_spans(branch: BranchNode, parent_low: Option(Bytes), parent_high: Option(Bytes)) : List(
  ChildSpan
)
  var spans = []
  n = branch.entries.size
  first_hi = if n > 0: Some((branch.entries.first or stop "branch first").key) else: parent_high
  spans = spans.append(ChildSpan(page_id: branch.first_child, low: parent_low, high: first_hi))
  for i in 0..n
    e = branch.entries.get(i) or stop "branch span idx"
    hi = if i + 1 < n
      Some((branch.entries.get(i + 1) or stop "branch next sep").key)
    else
      parent_high
    end
    spans = spans.append(ChildSpan(page_id: e.child, low: Some(e.key), high: hi))
  end
  spans
end

fn high_bound_less?(a: Option(Bytes), b: Option(Bytes)) : Bool
  case (a, b)
    (Some(x), Some(y)): x < y
    (Some(_), None): true
    (None, Some(_)) | (None, None): false
  end
end

fn diff_sorted_rows(rows_a: List((Bytes, Bytes)), rows_b: List((Bytes, Bytes)), acc: List(KeyDiff)) : List(
  KeyDiff
)
  var out = acc
  var i = 0
  var j = 0
  while i < rows_a.size and j < rows_b.size
    (ka, va) = rows_a.get(i) or stop "diff rows_a idx"
    (kb, vb) = rows_b.get(j) or stop "diff rows_b idx"
    if ka == kb
      if va != vb
        out = out.append(Modified(key: ka, old_value: va, new_value: vb))
      end
      i += 1
      j += 1
    else if ka < kb
      out = out.append(Removed(key: ka, value: va))
      i += 1
    else
      out = out.append(Added(key: kb, value: vb))
      j += 1
    end
  end
  while i < rows_a.size
    (ka, va) = rows_a.get(i) or stop "diff rows_a tail"
    out = out.append(Removed(key: ka, value: va))
    i += 1
  end
  while j < rows_b.size
    (kb, vb) = rows_b.get(j) or stop "diff rows_b tail"
    out = out.append(Added(key: kb, value: vb))
    j += 1
  end
  out
end

fn diff_leaf_entries(
  store: BlockStore,
  staged_a: Map(Int, Bytes),
  staged_b: Map(Int, Bytes),
  entries_a: List(LeafEntry),
  entries_b: List(LeafEntry),
  acc: List(KeyDiff)
) : Result(List(KeyDiff), ModbError)
  var out = acc
  var i = 0
  var j = 0
  while i < entries_a.size and j < entries_b.size
    ea = entries_a.get(i) or stop "diff leaf a"
    eb = entries_b.get(j) or stop "diff leaf b"
    if ea.key == eb.key
      same_ref = case (ea.value, eb.value)
        (Inline(data: da), Inline(data: db)): da == db
        (Overflow(first_page: fa, total_len: la), Overflow(first_page: fb, total_len: lb)): fa == fb and
          la == lb
        _: false
      end
      if not same_ref
        va = try materialize_value(store, staged_a, ea.value)
        vb = try materialize_value(store, staged_b, eb.value)
        if va != vb
          out = out.append(Modified(key: ea.key, old_value: va, new_value: vb))
        end
      end
      i += 1
      j += 1
    else if ea.key < eb.key
      va = try materialize_value(store, staged_a, ea.value)
      out = out.append(Removed(key: ea.key, value: va))
      i += 1
    else
      vb = try materialize_value(store, staged_b, eb.value)
      out = out.append(Added(key: eb.key, value: vb))
      j += 1
    end
  end
  while i < entries_a.size
    ea = entries_a.get(i) or stop "diff leaf a tail"
    va = try materialize_value(store, staged_a, ea.value)
    out = out.append(Removed(key: ea.key, value: va))
    i += 1
  end
  while j < entries_b.size
    eb = entries_b.get(j) or stop "diff leaf b tail"
    vb = try materialize_value(store, staged_b, eb.value)
    out = out.append(Added(key: eb.key, value: vb))
    j += 1
  end
  Ok(out)
end

fn diff_nodes(
  store: BlockStore,
  staged_a: Map(Int, Bytes),
  staged_b: Map(Int, Bytes),
  root_a: Int,
  root_b: Int,
  low: Option(Bytes),
  high: Option(Bytes),
  acc: List(KeyDiff),
  stats: DiffStats,
  depth: Int
) : Result((List(KeyDiff), DiffStats), ModbError)
  return Error(Corrupt(reason: "b-tree depth limit exceeded in diff")) if depth > 64
  if root_a == root_b and not staged_a.has?(root_a) and not staged_b.has?(root_b)
    var st = stats
    st.subtrees_skipped += 1
    return Ok((acc, st))
  end
  if root_a == 0
    rows_b = try scan(store, staged_b, root_b, low, high, 0)
    var out = acc
    for (k, v) in rows_b
      out = out.append(Added(key: k, value: v))
    end
    var st = stats
    st.pages_read += 1
    return Ok((out, st))
  end
  if root_b == 0
    rows_a = try scan(store, staged_a, root_a, low, high, 0)
    var out = acc
    for (k, v) in rows_a
      out = out.append(Removed(key: k, value: v))
    end
    var st = stats
    st.pages_read += 1
    return Ok((out, st))
  end

  raw_a = try read_node_page(store, staged_a, root_a)
  raw_b = try read_node_page(store, staged_b, root_b)
  var cur_stats = stats
  cur_stats.pages_read += 2
  hdr_a = try read_header_fast(raw_a, root_a)
  hdr_b = try read_header_fast(raw_b, root_b)

  if hdr_a.kind == kind_leaf and hdr_b.kind == kind_leaf
    la = try decode_leaf_unchecked(raw_a, root_a)
    lb = try decode_leaf_unchecked(raw_b, root_b)
    out = try diff_leaf_entries(store, staged_a, staged_b, la.entries, lb.entries, acc)
    return Ok((out, cur_stats))
  end

  if hdr_a.kind == kind_branch and hdr_b.kind == kind_branch
    ba = try decode_branch_unchecked(raw_a, root_a)
    bb = try decode_branch_unchecked(raw_b, root_b)
    spans_a = branch_child_spans(ba, low, high)
    spans_b = branch_child_spans(bb, low, high)
    var out = acc
    var i = 0
    var j = 0
    while i < spans_a.size and j < spans_b.size
      sa = spans_a.get(i) or stop "diff span a"
      sb = spans_b.get(j) or stop "diff span b"
      if sa.low == sb.low and sa.high == sb.high
        (next_out, next_stats) = try diff_nodes(
          store,
          staged_a,
          staged_b,
          sa.page_id,
          sb.page_id,
          sa.low,
          sa.high,
          out,
          cur_stats,
          depth + 1
        )
        out = next_out
        cur_stats = next_stats
        i += 1
        j += 1
      else
        ## Ranges diverged (e.g. split/merge shifted a separator): advance to the next common boundary.
        range_lo = sa.low
        var end_i = i
        var end_j = j
        var hi_a = sa.high
        var hi_b = sb.high
        while hi_a != hi_b
          if high_bound_less?(hi_a, hi_b)
            end_i += 1
            if end_i >= spans_a.size
              hi_a = high
              break
            end
            hi_a = (spans_a.get(end_i) or stop "sync span a").high
          else
            end_j += 1
            if end_j >= spans_b.size
              hi_b = high
              break
            end
            hi_b = (spans_b.get(end_j) or stop "sync span b").high
          end
        end
        sync_hi = hi_a
        rows_a = try scan(store, staged_a, root_a, range_lo, sync_hi, 0)
        rows_b = try scan(store, staged_b, root_b, range_lo, sync_hi, 0)
        cur_stats.pages_read += end_i - i + 1 + (end_j - j + 1)
        out = diff_sorted_rows(rows_a, rows_b, out)
        i = end_i + 1
        j = end_j + 1
      end
    end
    return Ok((out, cur_stats))
  end

  ## Mixed heights (Leaf vs Branch): compare pruned ranges directly.
  rows_a = try scan(store, staged_a, root_a, low, high, 0)
  rows_b = try scan(store, staged_b, root_b, low, high, 0)
  cur_stats.pages_read += 2
  Ok((diff_sorted_rows(rows_a, rows_b, acc), cur_stats))
end

## Computes exact sorted key diffs from `root_a` to `root_b`, skipping unchanged CoW subtrees in O(1),
## and returns `(diffs, stats)`.
fn diff_trees_with_stats(
  store: BlockStore,
  staged_a: Map(Int, Bytes),
  staged_b: Map(Int, Bytes),
  root_a: Int,
  root_b: Int
) : Result((List(KeyDiff), DiffStats), ModbError)
  diff_nodes(
    store,
    staged_a,
    staged_b,
    root_a,
    root_b,
    None,
    None,
    [],
    DiffStats(pages_read: 0, subtrees_skipped: 0),
    0
  )
end

## Computes exact sorted key diffs from `root_a` to `root_b`, skipping unchanged CoW subtrees in O(1).
fn diff_trees(
  store: BlockStore,
  staged_a: Map(Int, Bytes),
  staged_b: Map(Int, Bytes),
  root_a: Int,
  root_b: Int
) : Result(List(KeyDiff), ModbError)
  (diffs, _stats) = try diff_trees_with_stats(store, staged_a, staged_b, root_a, root_b)
  Ok(diffs)
end

test "CoW B+Tree handles multi-level splits, scans, overwrites, overflow values and full deletes"
  store = sim_empty()
  var alloc = empty_allocator(2, [])
  var root = 0

  for i in 0..250
    k = Bytes.from_u32_be(i)
    v = "value-#{i}".bytes
    assert put(store, alloc, root, k, v) is Ok((a1, r1))
    alloc = a1
    root = r1
  end

  big_val = Bytes.zeroed(10_000)
  assert put(store, alloc, root, Bytes.from_u32_be(125), big_val) is Ok((a_big, r_big))
  alloc = a_big
  root = r_big

  assert get_tx(store, alloc, root, Bytes.from_u32_be(0)) == Ok(Some("value-0".bytes))
  assert get_tx(store, alloc, root, Bytes.from_u32_be(125)) == Ok(Some(big_val))
  assert get_tx(store, alloc, root, Bytes.from_u32_be(249)) == Ok(Some("value-249".bytes))
  assert get_tx(store, alloc, root, Bytes.from_u32_be(999)) == Ok(None)

  assert flush_dirty(alloc) is Ok(flushed)
  alloc = flushed
  assert get(store, alloc.staged, root, Bytes.from_u32_be(125)) == Ok(Some(big_val))

  assert scan(
    store,
    alloc.staged,
    root,
    Some(Bytes.from_u32_be(10)),
    Some(Bytes.from_u32_be(20)),
    100
  ) is
    Ok(scanned)
  assert scanned.size == 10
  assert (scanned.first or stop "first").0 == Bytes.from_u32_be(10)
  assert (scanned.last or stop "last").0 == Bytes.from_u32_be(19)

  assert collect_tree_pages(store, alloc.staged, root) is Ok(pages)
  assert pages.size > 5
  assert count_entries(store, alloc.staged, root) == Ok(250)

  for i in 0..250
    assert delete(store, alloc, root, Bytes.from_u32_be(i)) is Ok((a_del, r_del, deleted?))
    assert deleted?
    alloc = a_del
    root = r_del
  end
  assert flush_dirty(alloc) is Ok(end_alloc)
  assert root == 0
  assert end_alloc.staged.empty?
end
