## Binary page encoding, decoding, SHA-256 verification, and zero-decode slotted lookups/scans.
module Modb.Codec
expose format_version,
kind_branch,
kind_leaf,
kind_overflow,
kind_freelist,
kind_deferred_freelist,
header_size,
body_size,
max_key_size,
max_inline_value,
max_overflow_chunk,
max_freelist_entries,
max_deferred_freelist_entries,
MetaPage(..),
PageHeader(..),
BranchEntry(..),
BranchNode(..),
ValueRef(..),
LeafEntry(..),
LeafNode(..),
OverflowPage(..),
FreelistPage(..),
DeferredPageEntry(..),
DeferredFreelistPage(..),
FreelistChunk(..),
encode_meta,
decode_meta,
verify_header,
read_header_fast,
branch_body_size,
leaf_body_size,
encode_branch,
decode_branch,
decode_branch_unchecked,
decode_branch_with_bytes_unchecked,
branch_lookup_child,
branch_lookup_child_unchecked,
branch_lookup_child_raw,
branch_scan_children_raw,
encode_leaf,
decode_leaf,
decode_leaf_unchecked,
decode_leaf_with_bytes_unchecked,
leaf_lookup_entry,
leaf_lookup_entry_unchecked,
leaf_lookup_entry_raw,
leaf_scan_raw,
verify_leaf_raw,
encode_overflow,
decode_overflow,
encode_freelist,
decode_freelist,
encode_deferred_freelist,
decode_freelist_chunk
use Crypto
use Modb.Errors{ModbError}
use Modb.Pager{page_size}

format_version = 1
kind_branch = 1
kind_leaf = 2
kind_overflow = 3
kind_freelist = 4
kind_deferred_freelist = 5

header_size = 48
body_size = 4048
max_key_size = 512
max_inline_value = 1024
max_overflow_chunk = 4036
max_freelist_entries = 505
max_deferred_freelist_entries = 252

## Superblock stored alternately in Page 0 (even txid) and Page 1 (odd txid).
struct MetaPage
  txid: Int
  catalog_root: Int
  freelist_root: Int
  page_count: Int
end

## Decoded and verified 48-byte common header for Pages >= 2.
struct PageHeader
  kind: Int
  entry_count: Int
  page_id: Int
end

## Separator key + right child page ID in a branch node.
struct BranchEntry
  key: Bytes
  child: Int
end

## Decoded internal B+Tree branch node.
struct BranchNode
  first_child: Int
  entries: List(BranchEntry)
end

## Value stored either inline in a leaf or across a linked overflow page chain.
enum ValueRef
  Inline(data: Bytes)
  Overflow(first_page: Int, total_len: Int)
end

## Key + value reference in a leaf node.
struct LeafEntry
  key: Bytes
  value: ValueRef
end

## Decoded B+Tree leaf node.
struct LeafNode
  entries: List(LeafEntry)
end

## Single page of an overflow value chain.
struct OverflowPage
  next_page: Int
  data: Bytes
end

## Single page of the persisted freelist chain (immediately reusable page IDs).
struct FreelistPage
  next_page: Int
  pages: List(Int)
end

## One deferred-free entry recording the commit `txid` that freed `page_id`.
struct DeferredPageEntry
  txid: Int
  page_id: Int
end

## Single page of the persisted deferred-free chain (pages protected by active root pins).
struct DeferredFreelistPage
  next_page: Int
  entries: List(DeferredPageEntry)
end

## Decoded chunk from the persisted freelist chain (`kind_freelist` or `kind_deferred_freelist`).
enum FreelistChunk
  ReadyChunk(next_page: Int, pages: List(Int))
  DeferredChunk(next_page: Int, entries: List(DeferredPageEntry))
end

fn meta_magic() : Bytes
  "MODB0001".bytes
end

fn read_u16(raw: Bytes, offset: Int, label: Text) : Result(Int, ModbError)
  case raw.u16_be_at(offset)
    Some(v): Ok(v)
    None: Error(Corrupt(reason: "truncated #{label} at offset #{offset}"))
  end
end

fn read_u32(raw: Bytes, offset: Int, label: Text) : Result(Int, ModbError)
  case raw.u32_be_at(offset)
    Some(v): Ok(v)
    None: Error(Corrupt(reason: "truncated #{label} at offset #{offset}"))
  end
end

fn read_i64(raw: Bytes, offset: Int, label: Text) : Result(Int, ModbError)
  case raw.i64_be_at(offset)
    Some(v): Ok(v)
    None: Error(Corrupt(reason: "truncated #{label} at offset #{offset}"))
  end
end

## Encodes a 4,096-byte checksummed meta-page.
fn encode_meta(meta: MetaPage) : Bytes
  prefix = Bytes.join([
    meta_magic(),
    Bytes.from_u32_be(format_version),
    Bytes.from_u32_be(page_size),
    Bytes.from_i64_be(meta.txid),
    Bytes.from_i64_be(meta.catalog_root),
    Bytes.from_i64_be(meta.freelist_root),
    Bytes.from_i64_be(meta.page_count)
  ])
  checksum = Crypto.sha256(prefix)
  Bytes.join([prefix, checksum, Bytes.zeroed(page_size - 80)])
end

## Decodes and SHA-256 verifies a 4,096-byte meta-page.
fn decode_meta(raw: Bytes) : Result(MetaPage, ModbError)
  if raw.size != page_size
    return Error(Corrupt(reason: "meta page size #{raw.size} != #{page_size}"))
  end
  if raw.compare_slice_at(0, 8, meta_magic()) != Some(Equal)
    return Error(Corrupt(reason: "bad meta magic"))
  end
  ver = try read_u32(raw, 8, "format_version")
  return Error(Corrupt(reason: "unsupported format version #{ver}")) if ver != format_version
  ps = try read_u32(raw, 12, "page_size")
  return Error(Corrupt(reason: "unexpected page size #{ps}")) if ps != page_size
  txid = try read_i64(raw, 16, "txid")
  catalog_root = try read_i64(raw, 24, "catalog_root")
  freelist_root = try read_i64(raw, 32, "freelist_root")
  page_count = try read_i64(raw, 40, "page_count")
  computed_sum = Crypto.sha256(raw.slice(0, 48))
  return Error(Corrupt(reason: "meta checksum mismatch")) if raw.compare_slice_at(
    48,
    32,
    computed_sum
  ) !=
    Some(Equal)
  return Error(Corrupt(reason: "invalid meta txid #{txid}")) if txid < 1
  return Error(Corrupt(reason: "invalid meta page_count #{page_count}")) if page_count < 2
  if catalog_root < 0 or catalog_root >= page_count or catalog_root == 1
    return Error(Corrupt(reason: "invalid meta catalog_root #{catalog_root}"))
  end
  if freelist_root < 0 or freelist_root >= page_count or freelist_root == 1
    return Error(Corrupt(reason: "invalid meta freelist_root #{freelist_root}"))
  end
  Ok(
    MetaPage(
      txid: txid,
      catalog_root: catalog_root,
      freelist_root: freelist_root,
      page_count: page_count
    )
  )
end

## Seals flat body chunks (`body_len <= 4,048`) into a checksummed 4,096-byte page in a single
## hash-buffer assembly pass (zero per-cell `Bytes.join` and zero redundant 4 KiB page copies).
fn seal_parts(kind: Int, entry_count: Int, page_id: Int, body_parts: List(Bytes), body_len: Int) : Result(
  Bytes,
  ModbError
)
  if body_len > body_size
    return Error(InvalidArgument(reason: "page body overflow: #{body_len} > #{body_size}"))
  end
  head_parts = [
    Bytes.from_u32_be(kind * 65536 + entry_count),
    Bytes.from_u32_be(0),
    Bytes.from_i64_be(page_id)
  ]
  all_parts = if body_len == body_size
    head_parts.concat(body_parts)
  else
    head_parts.concat(body_parts).append(Bytes.zeroed(body_size - body_len))
  end
  hash_buf = Bytes.join(all_parts)
  checksum = Crypto.sha256(hash_buf)
  Ok(Bytes.join([hash_buf.slice(0, 16), checksum, hash_buf.slice(16, 4064)]))
end

## Verifies a non-meta page's size, self page_id, and SHA-256 digest.
fn verify_header(raw: Bytes, expected_page_id: Int) : Result(PageHeader, ModbError)
  if raw.size != page_size
    return Error(Corrupt(reason: "page #{expected_page_id} size #{raw.size} != #{page_size}"))
  end
  kind = case raw.u16_be_at(0)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated kind"))
  end
  entry_count = case raw.u16_be_at(2)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated entry_count"))
  end
  pid = case raw.i64_be_at(8)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated page_id"))
  end
  if pid != expected_page_id
    return Error(Corrupt(reason: "page id mismatch: expected #{expected_page_id}, got #{pid}"))
  end
  computed_sum = Crypto.sha256(Bytes.join([raw.slice(0, 16), raw.slice(48, page_size)]))
  if raw.compare_slice_at(16, 32, computed_sum) != Some(Equal)
    return Error(Corrupt(reason: "checksum mismatch on page #{expected_page_id}"))
  end
  Ok(PageHeader(kind: kind, entry_count: entry_count, page_id: pid))
end

## Reads a page header without recomputing SHA-256 (for pages already verified when loaded).
fn read_header_fast(raw: Bytes, expected_page_id: Int) : Result(PageHeader, ModbError)
  if raw.size != page_size
    return Error(Corrupt(reason: "page #{expected_page_id} size #{raw.size} != #{page_size}"))
  end
  kind = case raw.u16_be_at(0)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated kind"))
  end
  entry_count = case raw.u16_be_at(2)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated entry_count"))
  end
  pid = case raw.i64_be_at(8)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated page_id"))
  end
  if pid != expected_page_id
    return Error(Corrupt(reason: "page id mismatch: expected #{expected_page_id}, got #{pid}"))
  end
  Ok(PageHeader(kind: kind, entry_count: entry_count, page_id: pid))
end

## Byte size required in the 4,048-byte body for a branch node's entries.
fn branch_body_size(entries: List(BranchEntry)) : Int
  var total = 8
  for e in entries
    total += 2 + 10 + e.key.size
  end
  total
end

## Byte size required in the 4,048-byte body for a leaf node's entries.
fn leaf_body_size(entries: List(LeafEntry)) : Int
  var total = 0
  for e in entries
    cell_size = case e.value
      Inline(data: d): 6 + e.key.size + d.size
      Overflow(first_page: _, total_len: _): 20 + e.key.size
    end
    total += 2 + cell_size
  end
  total
end

## Encodes a branch node into a 4,096-byte slotted page in a single flat buffer pass.
fn encode_branch(page_id: Int, node: BranchNode) : Result(Bytes, ModbError)
  count = node.entries.size
  var slot_parts = [Bytes.from_i64_be(node.first_child)]
  var cell_parts = []
  var cursor = header_size + 8 + count * 2
  for e in node.entries
    slot_parts = slot_parts.append(Bytes.from_u16_be(cursor))
    cell_parts = cell_parts.append(Bytes.from_u16_be(e.key.size)).append(Bytes.from_i64_be(e.child))
      .append(e.key)
    cursor += 10 + e.key.size
  end
  seal_parts(kind_branch, count, page_id, slot_parts.concat(cell_parts), cursor - header_size)
end

## Decodes a verified branch page into a `BranchNode`.
fn decode_branch(raw: Bytes, expected_page_id: Int) : Result(BranchNode, ModbError)
  hdr = try verify_header(raw, expected_page_id)
  (node, _bytes) = try decode_branch_with_header(raw, hdr, expected_page_id)
  Ok(node)
end

## Decodes a branch page whose SHA-256 was already verified.
fn decode_branch_unchecked(raw: Bytes, expected_page_id: Int) : Result(BranchNode, ModbError)
  hdr = try read_header_fast(raw, expected_page_id)
  (node, _bytes) = try decode_branch_with_header(raw, hdr, expected_page_id)
  Ok(node)
end

## Decodes a branch page whose SHA-256 was already verified, also returning its exact body byte size.
fn decode_branch_with_bytes_unchecked(raw: Bytes, expected_page_id: Int) : Result(
  (BranchNode, Int),
  ModbError
)
  hdr = try read_header_fast(raw, expected_page_id)
  decode_branch_with_header(raw, hdr, expected_page_id)
end

fn decode_branch_with_header(raw: Bytes, hdr: PageHeader, expected_page_id: Int) : Result(
  (BranchNode, Int),
  ModbError
)
  if hdr.kind != kind_branch
    return Error(Corrupt(reason: "expected branch page #{expected_page_id}, got kind #{hdr.kind}"))
  end
  first_child = case raw.i64_be_at(header_size)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated branch first_child"))
  end
  count = hdr.entry_count
  slot_base = header_size + 8
  min_cell = slot_base + count * 2
  var entries = []
  var total_bytes = 8
  for i in 0..count
    off = case raw.u16_be_at(slot_base + i * 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated branch slot"))
    end
    if off < min_cell or off + 10 > page_size
      return Error(Corrupt(reason: "branch slot offset #{off} out of bounds"))
    end
    klen = case raw.u16_be_at(off)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated branch key_len"))
    end
    if off + 10 + klen > page_size
      return Error(Corrupt(reason: "branch key overflows page"))
    end
    child = case raw.i64_be_at(off + 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated branch child"))
    end
    key = raw.slice(off + 10, off + 10 + klen)
    entries = entries.append(BranchEntry(key: key, child: child))
    total_bytes += 12 + klen
  end
  Ok((BranchNode(first_child: first_child, entries: entries), total_bytes))
end

## Zero-allocation raw binary search on an already-validated branch page (`count = entry_count`).
fn branch_lookup_child_raw(raw: Bytes, count: Int, target: Bytes) : Result(Int, ModbError)
  first_child = case raw.i64_be_at(header_size)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated branch first_child"))
  end
  return Ok(first_child) if count == 0
  slot_base = header_size + 8
  min_cell = slot_base + count * 2
  var lo = 0
  var hi = count
  while lo < hi
    mid = lo + (hi - lo) / 2
    off = case raw.u16_be_at(slot_base + mid * 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated branch slot"))
    end
    return Error(Corrupt(reason: "branch slot out of bounds")) if off < min_cell or
      off + 10 > page_size
    klen = case raw.u16_be_at(off)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated branch key_len"))
    end
    case raw.compare_slice_at(off + 10, klen, target)
      None: return Error(Corrupt(reason: "branch key out of bounds"))
      Some(ord):
        case ord
          Greater: hi = mid
          Less | Equal: lo = mid + 1
        end
    end
  end
  if lo == 0
    Ok(first_child)
  else
    idx = lo - 1
    off = case raw.u16_be_at(slot_base + idx * 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated branch slot"))
    end
    return Error(Corrupt(reason: "branch slot out of bounds")) if off < min_cell or
      off + 10 > page_size
    case raw.i64_be_at(off + 2)
      Some(v): Ok(v)
      None: Error(Corrupt(reason: "truncated branch child"))
    end
  end
end

## Fast binary search on a raw branch page without allocating a full entry list.
## Returns the child page ID that may contain `target`.
fn branch_lookup_child(raw: Bytes, expected_page_id: Int, target: Bytes) : Result(Int, ModbError)
  hdr = try verify_header(raw, expected_page_id)
  if hdr.kind != kind_branch
    return Error(Corrupt(reason: "expected branch page #{expected_page_id}, got kind #{hdr.kind}"))
  end
  branch_lookup_child_raw(raw, hdr.entry_count, target)
end

## Same as `branch_lookup_child`, skipping SHA-256 when caller already verified the page.
fn branch_lookup_child_unchecked(raw: Bytes, expected_page_id: Int, target: Bytes) : Result(
  Int,
  ModbError
)
  hdr = try read_header_fast(raw, expected_page_id)
  if hdr.kind != kind_branch
    return Error(Corrupt(reason: "expected branch page #{expected_page_id}, got kind #{hdr.kind}"))
  end
  branch_lookup_child_raw(raw, hdr.entry_count, target)
end

## Zero-decode raw branch child range selector for `[start_key, end_key)`:
## binary-searches `start_key` directly in raw bytes and returns ONLY overlapping child page IDs.
fn branch_scan_children_raw(
  raw: Bytes,
  count: Int,
  start_key: Option(Bytes),
  end_key: Option(Bytes)
) : Result(List(Int), ModbError)
  first_child = case raw.i64_be_at(header_size)
    Some(v): v
    None: return Error(Corrupt(reason: "truncated branch first_child"))
  end
  return Ok([first_child]) if count == 0
  slot_base = header_size + 8
  min_cell = slot_base + count * 2

  var child_idx = 0
  case start_key
    Some(s):
      var lo = 0
      var hi = count
      while lo < hi
        mid = lo + (hi - lo) / 2
        off = case raw.u16_be_at(slot_base + mid * 2)
          Some(v): v
          None: return Error(Corrupt(reason: "truncated branch slot"))
        end
        return Error(Corrupt(reason: "branch slot out of bounds")) if off < min_cell or
          off + 10 > page_size
        klen = case raw.u16_be_at(off)
          Some(v): v
          None: return Error(Corrupt(reason: "truncated branch key_len"))
        end
        case raw.compare_slice_at(off + 10, klen, s)
          None: return Error(Corrupt(reason: "branch key out of bounds"))
          Some(ord):
            case ord
              Greater: hi = mid
              Less | Equal: lo = mid + 1
            end
        end
      end
      child_idx = lo
    None: Unit
  end

  var children = []
  while child_idx <= count
    if child_idx == 0
      children = children.append(first_child)
    else
      off = case raw.u16_be_at(slot_base + (child_idx - 1) * 2)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated branch slot"))
      end
      return Error(Corrupt(reason: "branch slot out of bounds")) if off < min_cell or
        off + 10 > page_size
      case end_key
        Some(ek):
          klen = case raw.u16_be_at(off)
            Some(v): v
            None: return Error(Corrupt(reason: "truncated branch key_len"))
          end
          case raw.compare_slice_at(off + 10, klen, ek)
            None: return Error(Corrupt(reason: "branch key out of bounds"))
            Some(ord):
              case ord
                Greater | Equal: break
                Less: Unit
              end
          end
        None: Unit
      end
      child = case raw.i64_be_at(off + 2)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated branch child"))
      end
      children = children.append(child)
    end
    child_idx += 1
  end
  Ok(children)
end

## Encodes a leaf node into a 4,096-byte slotted page in a single flat buffer pass.
fn encode_leaf(page_id: Int, node: LeafNode) : Result(Bytes, ModbError)
  count = node.entries.size
  var slot_parts = []
  var cell_parts = []
  var cursor = header_size + count * 2
  for e in node.entries
    slot_parts = slot_parts.append(Bytes.from_u16_be(cursor))
    klen = e.key.size
    case e.value
      Inline(data: d):
        cell_parts = cell_parts.append(Bytes.from_u32_be(klen)).append(Bytes.from_u16_be(d.size))
          .append(e.key).append(d)
        cursor += 6 + klen + d.size
      Overflow(first_page: fp, total_len: tl):
        cell_parts = cell_parts.append(Bytes.from_u32_be(65536 + klen)).append(
          Bytes.from_i64_be(fp)
        ).append(Bytes.from_i64_be(tl)).append(e.key)
        cursor += 20 + klen
    end
  end
  seal_parts(kind_leaf, count, page_id, slot_parts.concat(cell_parts), cursor - header_size)
end

## Decodes a verified leaf page into a `LeafNode`.
fn decode_leaf(raw: Bytes, expected_page_id: Int) : Result(LeafNode, ModbError)
  hdr = try verify_header(raw, expected_page_id)
  (node, _bytes) = try decode_leaf_with_header(raw, hdr, expected_page_id)
  Ok(node)
end

## Decodes a leaf page whose SHA-256 was already verified.
fn decode_leaf_unchecked(raw: Bytes, expected_page_id: Int) : Result(LeafNode, ModbError)
  hdr = try read_header_fast(raw, expected_page_id)
  (node, _bytes) = try decode_leaf_with_header(raw, hdr, expected_page_id)
  Ok(node)
end

## Decodes a leaf page whose SHA-256 was already verified, also returning its exact body byte size.
fn decode_leaf_with_bytes_unchecked(raw: Bytes, expected_page_id: Int) : Result(
  (LeafNode, Int),
  ModbError
)
  hdr = try read_header_fast(raw, expected_page_id)
  decode_leaf_with_header(raw, hdr, expected_page_id)
end

fn decode_leaf_with_header(raw: Bytes, hdr: PageHeader, expected_page_id: Int) : Result(
  (LeafNode, Int),
  ModbError
)
  if hdr.kind != kind_leaf
    return Error(Corrupt(reason: "expected leaf page #{expected_page_id}, got kind #{hdr.kind}"))
  end
  count = hdr.entry_count
  min_cell = header_size + count * 2
  var entries = []
  var total_bytes = 0
  for i in 0..count
    off = case raw.u16_be_at(header_size + i * 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf slot"))
    end
    if off < min_cell or off + 6 > page_size
      return Error(Corrupt(reason: "leaf slot offset #{off} out of bounds"))
    end
    vkind = case raw.u16_be_at(off)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf val_kind"))
    end
    klen = case raw.u16_be_at(off + 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf key_len"))
    end
    if vkind == 0
      vlen = case raw.u16_be_at(off + 4)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated leaf val_len"))
      end
      if off + 6 + klen + vlen > page_size
        return Error(Corrupt(reason: "inline leaf cell overflows page"))
      end
      key = raw.slice(off + 6, off + 6 + klen)
      val = raw.slice(off + 6 + klen, off + 6 + klen + vlen)
      entries = entries.append(LeafEntry(key: key, value: Inline(data: val)))
      total_bytes += 8 + klen + vlen
    else if vkind == 1
      if off + 20 + klen > page_size
        return Error(Corrupt(reason: "overflow leaf cell overflows page"))
      end
      fp = case raw.i64_be_at(off + 4)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated overflow first_page"))
      end
      tl = case raw.i64_be_at(off + 12)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated overflow total_len"))
      end
      key = raw.slice(off + 20, off + 20 + klen)
      entries = entries.append(LeafEntry(key: key, value: Overflow(first_page: fp, total_len: tl)))
      total_bytes += 22 + klen
    else
      return Error(Corrupt(reason: "unknown leaf value kind #{vkind}"))
    end
  end
  Ok((LeafNode(entries: entries), total_bytes))
end

## Zero-allocation raw binary search on an already-validated leaf page (`count = entry_count`).
fn leaf_lookup_entry_raw(raw: Bytes, count: Int, target: Bytes) : Result(
  Option(ValueRef),
  ModbError
)
  return Ok(None) if count == 0
  min_cell = header_size + count * 2
  var lo = 0
  var hi = count
  while lo < hi
    mid = lo + (hi - lo) / 2
    off = case raw.u16_be_at(header_size + mid * 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf slot"))
    end
    if off < min_cell or off + 6 > page_size
      return Error(Corrupt(reason: "leaf slot offset out of bounds"))
    end
    vkind = case raw.u16_be_at(off)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf val_kind"))
    end
    klen = case raw.u16_be_at(off + 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf key_len"))
    end
    kstart = if vkind == 0
      off + 6
    else if vkind == 1
      off + 20
    else
      return Error(Corrupt(reason: "unknown leaf value kind #{vkind}"))
    end
    case raw.compare_slice_at(kstart, klen, target)
      None: return Error(Corrupt(reason: "leaf key overflows page"))
      Some(ord):
        case ord
          Less: lo = mid + 1
          Greater: hi = mid
          Equal:
            if vkind == 0
              vlen = case raw.u16_be_at(off + 4)
                Some(v): v
                None: return Error(Corrupt(reason: "truncated leaf val_len"))
              end
              if kstart + klen + vlen > page_size
                return Error(Corrupt(reason: "inline leaf cell overflows page"))
              end
              return Ok(Some(Inline(data: raw.slice(kstart + klen, kstart + klen + vlen))))
            else
              fp = case raw.i64_be_at(off + 4)
                Some(v): v
                None: return Error(Corrupt(reason: "truncated overflow first_page"))
              end
              tl = case raw.i64_be_at(off + 12)
                Some(v): v
                None: return Error(Corrupt(reason: "truncated overflow total_len"))
              end
              return Ok(Some(Overflow(first_page: fp, total_len: tl)))
            end
        end
    end
  end
  Ok(None)
end

## Fast binary search on a raw leaf page without decoding non-matching entries.
fn leaf_lookup_entry(raw: Bytes, expected_page_id: Int, target: Bytes) : Result(
  Option(ValueRef),
  ModbError
)
  hdr = try verify_header(raw, expected_page_id)
  if hdr.kind != kind_leaf
    return Error(Corrupt(reason: "expected leaf page #{expected_page_id}, got kind #{hdr.kind}"))
  end
  leaf_lookup_entry_raw(raw, hdr.entry_count, target)
end

## Same as `leaf_lookup_entry`, skipping SHA-256 when caller already verified the page.
fn leaf_lookup_entry_unchecked(raw: Bytes, expected_page_id: Int, target: Bytes) : Result(
  Option(ValueRef),
  ModbError
)
  hdr = try read_header_fast(raw, expected_page_id)
  if hdr.kind != kind_leaf
    return Error(Corrupt(reason: "expected leaf page #{expected_page_id}, got kind #{hdr.kind}"))
  end
  leaf_lookup_entry_raw(raw, hdr.entry_count, target)
end

## Zero-decode raw leaf range scan over `[start_key, end_key)` taking at most `remaining_limit`
## entries (`<= 0` = unbounded). Never allocates `LeafNode` or slices skipped keys/values.
fn leaf_scan_raw(
  raw: Bytes,
  count: Int,
  start_key: Option(Bytes),
  end_key: Option(Bytes),
  remaining_limit: Int
) : Result(List((Bytes, ValueRef)), ModbError)
  return Ok([]) if count == 0
  min_cell = header_size + count * 2

  var start_idx = 0
  case start_key
    Some(s):
      var lo = 0
      var hi = count
      while lo < hi
        mid = lo + (hi - lo) / 2
        off = case raw.u16_be_at(header_size + mid * 2)
          Some(v): v
          None: return Error(Corrupt(reason: "truncated leaf slot"))
        end
        if off < min_cell or off + 6 > page_size
          return Error(Corrupt(reason: "leaf slot offset out of bounds"))
        end
        vkind = case raw.u16_be_at(off)
          Some(v): v
          None: return Error(Corrupt(reason: "truncated leaf val_kind"))
        end
        klen = case raw.u16_be_at(off + 2)
          Some(v): v
          None: return Error(Corrupt(reason: "truncated leaf key_len"))
        end
        kstart = if vkind == 0
          off + 6
        else if vkind == 1
          off + 20
        else
          return Error(Corrupt(reason: "unknown leaf value kind #{vkind}"))
        end
        case raw.compare_slice_at(kstart, klen, s)
          None: return Error(Corrupt(reason: "leaf key overflows page"))
          Some(ord):
            case ord
              Less: lo = mid + 1
              Greater | Equal: hi = mid
            end
        end
      end
      start_idx = lo
    None: Unit
  end

  var out = []
  var i = start_idx
  while i < count
    break if remaining_limit > 0 and out.size >= remaining_limit
    off = case raw.u16_be_at(header_size + i * 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf slot"))
    end
    if off < min_cell or off + 6 > page_size
      return Error(Corrupt(reason: "leaf slot offset out of bounds"))
    end
    vkind = case raw.u16_be_at(off)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf val_kind"))
    end
    klen = case raw.u16_be_at(off + 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf key_len"))
    end
    kstart = if vkind == 0
      off + 6
    else if vkind == 1
      off + 20
    else
      return Error(Corrupt(reason: "unknown leaf value kind #{vkind}"))
    end
    case end_key
      Some(ek):
        case raw.compare_slice_at(kstart, klen, ek)
          None: return Error(Corrupt(reason: "leaf key overflows page"))
          Some(ord):
            case ord
              Greater | Equal: break
              Less: Unit
            end
        end
      None: Unit
    end
    if vkind == 0
      vlen = case raw.u16_be_at(off + 4)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated leaf val_len"))
      end
      if kstart + klen + vlen > page_size
        return Error(Corrupt(reason: "inline leaf cell overflows page"))
      end
      key = raw.slice(kstart, kstart + klen)
      val = raw.slice(kstart + klen, kstart + klen + vlen)
      out = out.append((key, Inline(data: val)))
    else
      if off + 20 + klen > page_size
        return Error(Corrupt(reason: "overflow leaf cell overflows page"))
      end
      fp = case raw.i64_be_at(off + 4)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated overflow first_page"))
      end
      tl = case raw.i64_be_at(off + 12)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated overflow total_len"))
      end
      key = raw.slice(kstart, kstart + klen)
      out = out.append((key, Overflow(first_page: fp, total_len: tl)))
    end
    i += 1
  end
  Ok(out)
end

## Zero-value-allocation structural leaf verifier for `Modb.verify`:
## validates all slot offsets, cell bounds, strict ascending key order, `[low, high)` bounds,
## and collects `(first_page, total_len)` overflow descriptors without slicing inline values.
fn verify_leaf_raw(raw: Bytes, count: Int, page_id: Int, low: Option(Bytes), high: Option(Bytes)) : Result(
  List((Int, Int)),
  ModbError
)
  min_cell = header_size + count * 2
  var prev_key = None
  var overflows = []
  for i in 0..count
    off = case raw.u16_be_at(header_size + i * 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf slot on page #{page_id}"))
    end
    if off < min_cell or off + 6 > page_size
      return Error(Corrupt(reason: "leaf slot offset #{off} out of bounds on page #{page_id}"))
    end
    vkind = case raw.u16_be_at(off)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf val_kind on page #{page_id}"))
    end
    klen = case raw.u16_be_at(off + 2)
      Some(v): v
      None: return Error(Corrupt(reason: "truncated leaf key_len on page #{page_id}"))
    end
    kstart = if vkind == 0
      vlen = case raw.u16_be_at(off + 4)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated leaf val_len on page #{page_id}"))
      end
      if off + 6 + klen + vlen > page_size
        return Error(Corrupt(reason: "inline leaf cell overflows page #{page_id}"))
      end
      off + 6
    else if vkind == 1
      if off + 20 + klen > page_size
        return Error(Corrupt(reason: "overflow leaf cell overflows page #{page_id}"))
      end
      fp = case raw.i64_be_at(off + 4)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated overflow first_page on page #{page_id}"))
      end
      tl = case raw.i64_be_at(off + 12)
        Some(v): v
        None: return Error(Corrupt(reason: "truncated overflow total_len on page #{page_id}"))
      end
      overflows = overflows.append((fp, tl))
      off + 20
    else
      return Error(Corrupt(reason: "unknown leaf value kind #{vkind} on page #{page_id}"))
    end
    case prev_key
      Some(pk):
        case raw.compare_slice_at(kstart, klen, pk)
          None: return Error(Corrupt(reason: "leaf key overflows page #{page_id}"))
          Some(ord):
            case ord
              Greater: Unit
              Less | Equal: return Error(Corrupt(reason: "unsorted keys on leaf #{page_id}"))
            end
        end
      None:
        case low
          Some(lo):
            case raw.compare_slice_at(kstart, klen, lo)
              None: return Error(Corrupt(reason: "leaf key overflows page #{page_id}"))
              Some(ord):
                case ord
                  Less: return Error(
                    Corrupt(reason: "key below branch lower bound on leaf #{page_id}")
                  )
                  Equal | Greater: Unit
                end
            end
          None: Unit
        end
    end
    if i == count - 1
      case high
        Some(hi):
          case raw.compare_slice_at(kstart, klen, hi)
            None: return Error(Corrupt(reason: "leaf key overflows page #{page_id}"))
            Some(ord):
              case ord
                Less: Unit
                Equal | Greater: return Error(
                  Corrupt(reason: "key >= branch upper bound on leaf #{page_id}")
                )
              end
          end
        None: Unit
      end
    end
    prev_key = Some(raw.slice(kstart, kstart + klen))
  end
  Ok(overflows)
end

## Encodes one page of an overflow value chain.
fn encode_overflow(page_id: Int, page: OverflowPage) : Result(Bytes, ModbError)
  if page.data.size > max_overflow_chunk
    return Error(
      InvalidArgument(reason: "overflow chunk #{page.data.size} > #{max_overflow_chunk}")
    )
  end
  parts = [Bytes.from_i64_be(page.next_page), Bytes.from_u32_be(page.data.size), page.data]
  seal_parts(kind_overflow, 1, page_id, parts, 12 + page.data.size)
end

## Decodes a verified overflow page.
fn decode_overflow(raw: Bytes, expected_page_id: Int) : Result(OverflowPage, ModbError)
  hdr = try verify_header(raw, expected_page_id)
  if hdr.kind != kind_overflow
    return Error(
      Corrupt(reason: "expected overflow page #{expected_page_id}, got kind #{hdr.kind}")
    )
  end
  next_page = try read_i64(raw, header_size, "overflow next_page")
  chunk_len = try read_u32(raw, header_size + 8, "overflow chunk_len")
  if chunk_len > max_overflow_chunk
    return Error(Corrupt(reason: "overflow chunk_len #{chunk_len} exceeds max"))
  end
  data = raw.slice(header_size + 12, header_size + 12 + chunk_len)
  Ok(OverflowPage(next_page: next_page, data: data))
end

## Encodes one page of the persisted freelist chain.
fn encode_freelist(page_id: Int, page: FreelistPage) : Result(Bytes, ModbError)
  if page.pages.size > max_freelist_entries
    return Error(
      InvalidArgument(
        reason: "freelist page has #{page.pages.size} entries (max #{max_freelist_entries})"
      )
    )
  end
  var parts = [Bytes.from_i64_be(page.next_page)]
  for pid in page.pages
    parts = parts.append(Bytes.from_i64_be(pid))
  end
  seal_parts(kind_freelist, page.pages.size, page_id, parts, 8 + page.pages.size * 8)
end

## Decodes a verified freelist page.
fn decode_freelist(raw: Bytes, expected_page_id: Int) : Result(FreelistPage, ModbError)
  hdr = try verify_header(raw, expected_page_id)
  if hdr.kind != kind_freelist
    return Error(
      Corrupt(reason: "expected freelist page #{expected_page_id}, got kind #{hdr.kind}")
    )
  end
  if hdr.entry_count > max_freelist_entries
    return Error(Corrupt(reason: "freelist entry_count #{hdr.entry_count} exceeds max"))
  end
  next_page = try read_i64(raw, header_size, "freelist next_page")
  var pages = []
  for i in 0..hdr.entry_count
    pid = try read_i64(raw, header_size + 8 + i * 8, "freelist entry")
    pages = pages.append(pid)
  end
  Ok(FreelistPage(next_page: next_page, pages: pages))
end

## Encodes one page of the persisted deferred-free chain (`(txid, page_id)` pairs).
fn encode_deferred_freelist(page_id: Int, page: DeferredFreelistPage) : Result(Bytes, ModbError)
  if page.entries.size > max_deferred_freelist_entries
    return Error(
      InvalidArgument(
        reason: "deferred freelist page has #{page.entries.size} entries (max #{max_deferred_freelist_entries})"
      )
    )
  end
  var parts = [Bytes.from_i64_be(page.next_page)]
  for e in page.entries
    parts = parts.append(Bytes.from_i64_be(e.txid)).append(Bytes.from_i64_be(e.page_id))
  end
  seal_parts(kind_deferred_freelist, page.entries.size, page_id, parts, 8 + page.entries.size * 16)
end

## Decodes either a ready (`kind_freelist`) or deferred (`kind_deferred_freelist`) freelist page.
fn decode_freelist_chunk(raw: Bytes, expected_page_id: Int) : Result(FreelistChunk, ModbError)
  hdr = try verify_header(raw, expected_page_id)
  if hdr.kind == kind_freelist
    if hdr.entry_count > max_freelist_entries
      return Error(Corrupt(reason: "freelist entry_count #{hdr.entry_count} exceeds max"))
    end
    next_page = try read_i64(raw, header_size, "freelist next_page")
    var pages = []
    for i in 0..hdr.entry_count
      pid = try read_i64(raw, header_size + 8 + i * 8, "freelist entry")
      pages = pages.append(pid)
    end
    Ok(ReadyChunk(next_page: next_page, pages: pages))
  else if hdr.kind == kind_deferred_freelist
    if hdr.entry_count > max_deferred_freelist_entries
      return Error(Corrupt(reason: "deferred freelist entry_count #{hdr.entry_count} exceeds max"))
    end
    next_page = try read_i64(raw, header_size, "deferred freelist next_page")
    var entries = []
    for i in 0..hdr.entry_count
      base = header_size + 8 + i * 16
      t = try read_i64(raw, base, "deferred txid")
      pid = try read_i64(raw, base + 8, "deferred page_id")
      entries = entries.append(DeferredPageEntry(txid: t, page_id: pid))
    end
    Ok(DeferredChunk(next_page: next_page, entries: entries))
  else
    Error(Corrupt(reason: "expected freelist page #{expected_page_id}, got kind #{hdr.kind}"))
  end
end

test "meta page round-trips and detects single-byte corruption"
  meta = MetaPage(txid: 7, catalog_root: 3, freelist_root: 5, page_count: 10)
  raw = encode_meta(meta)
  assert raw.size == page_size
  assert decode_meta(raw) == Ok(meta)
  bad = Bytes.join([raw.slice(0, 20), Bytes.from_list([99]), raw.slice(21, page_size)])
  assert decode_meta(bad) is Error(Corrupt(reason: _))
end

test "branch and leaf slotted pages round-trip and binary-search accurately"
  leaf = LeafNode(
    entries: [
      LeafEntry(key: "a".bytes, value: Inline(data: "alpha".bytes)),
      LeafEntry(key: "m".bytes, value: Overflow(first_page: 9, total_len: 5000)),
      LeafEntry(key: "z".bytes, value: Inline(data: "omega".bytes))
    ]
  )
  assert encode_leaf(4, leaf) is Ok(raw_leaf)
  assert decode_leaf(raw_leaf, 4) == Ok(leaf)
  assert leaf_lookup_entry(raw_leaf, 4, "a".bytes) == Ok(Some(Inline(data: "alpha".bytes)))
  assert leaf_lookup_entry(raw_leaf, 4, "m".bytes) ==
    Ok(Some(Overflow(first_page: 9, total_len: 5000)))
  assert leaf_lookup_entry(raw_leaf, 4, "b".bytes) == Ok(None)
  assert decode_leaf(raw_leaf, 5) is Error(Corrupt(reason: _))

  branch = BranchNode(
    first_child: 10,
    entries: [
      BranchEntry(key: "d".bytes, child: 11),
      BranchEntry(key: "m".bytes, child: 12),
      BranchEntry(key: "t".bytes, child: 13)
    ]
  )
  assert encode_branch(2, branch) is Ok(raw_branch)
  assert decode_branch(raw_branch, 2) == Ok(branch)
  assert branch_lookup_child(raw_branch, 2, "a".bytes) == Ok(10)
  assert branch_lookup_child(raw_branch, 2, "d".bytes) == Ok(11)
  assert branch_lookup_child(raw_branch, 2, "k".bytes) == Ok(11)
  assert branch_lookup_child(raw_branch, 2, "m".bytes) == Ok(12)
  assert branch_lookup_child(raw_branch, 2, "z".bytes) == Ok(13)
end

test "overflow and freelist pages round-trip"
  ov = OverflowPage(next_page: 12, data: "hello overflow".bytes)
  assert encode_overflow(8, ov) is Ok(raw_ov)
  assert decode_overflow(raw_ov, 8) == Ok(ov)

  fl = FreelistPage(next_page: 0, pages: [3, 4, 7, 19])
  assert encode_freelist(6, fl) is Ok(raw_fl)
  assert decode_freelist(raw_fl, 6) == Ok(fl)
end
