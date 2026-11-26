## MoDB Reactive Change Feeds: Persistent CoW-Pinned `txid`-Cursor Subscriptions.
## Delivers exact O(diff) bucket/key deltas, O(1) idle polling, sensitivity gating without descending
## into restricted buckets, optimistic `txid` CAS acknowledgement, and deferred freelist reclamation.
module Modb.Feeds
expose feeds_bucket,
feed_pin_id,
FeedSpec(..),
FeedSubscription(..),
ChangeOp(..),
FeedEvent(..),
FeedBatch(..),
FeedError(..),
to_text,
get_feed,
list_feeds,
subscribe,
poll_feed,
ack_feed,
consume_feed,
resync_feed,
unsubscribe,
subscribe_locked,
poll_feed_locked,
ack_feed_locked,
consume_feed_locked,
resync_feed_locked,
unsubscribe_locked
use Json
use Modb{Store, pins_bucket}
use Modb.Errors{ModbError}
use Modb.Grants
use Modb.Ledger{Db, LedgerError, Schema, WriteMeta}
use Modb.Policy
use Modb.Table{Table, TableError}
use Modb.Tree{KeyDiff}

## Reserved internal bucket holding active reactive feed subscriptions.
feeds_bucket = "_modb_feeds"

## Deterministic Layer 1 persistent CoW root pin name for a subscription.
fn feed_pin_id(id: Text) : Text
  "feed:#{id}"
end

## Specification to register a reactive change-feed subscription.
struct FeedSpec
  id: Text
  principal: Text
  grant_id: Option(Text)
  buckets: List(Text)
  include_internal: Bool
  from_beginning: Bool
end

## Persisted subscription metadata stored in `_modb_feeds`.
struct FeedSubscription
  id: Text
  principal: Text
  grant_id: Option(Text)
  buckets: List(Text)
  include_internal: Bool
  pin_id: Text
  cursor_txid: Int
  bootstrapped: Bool
  created_at: Time
  last_acked_at: Option(Time)
  events_delivered: Int
end

## Mutation kind for one emitted key delta.
enum ChangeOp
  OpAdded
  OpModified
  OpRemoved
end

## Single structural key delta emitted by `poll_feed` / `consume_feed`.
struct FeedEvent
  bucket: Text
  op: ChangeOp
  key_hex: Text
  key_text: Option(Text)
  old_value_hex: Option(Text)
  new_value_hex: Option(Text)
  old_value_text: Option(Text)
  new_value_text: Option(Text)
end

## Ordered batch of structural changes returned by `poll_feed` / `consume_feed`.
struct FeedBatch
  feed_id: Text
  from_txid: Int
  to_txid: Int
  clearance: Policy.Sensitivity
  events: List(FeedEvent)
  truncated: Bool
  filtered_buckets: List(Text)
  pages_read: Int
  subtrees_skipped: Int
end

## Every failure returned by `Modb.Feeds` operations.
enum FeedError
  LedgerFailure(LedgerError)
  GrantFailure(Grants.GrantError)
  PolicyFailure(Policy.PolicyError)
  InvalidFeed(reason: Text)
  FeedAlreadyExists(id: Text)
  FeedNotFound(id: Text)
  PinMissing(feed_id: Text, pin_id: Text)
  CursorStale(feed_id: Text, expected_txid: Int, actual_txid: Int)
end

## Formats a `FeedError` as a human-readable diagnostic.
fn to_text(err: FeedError) : Text
  case err
    LedgerFailure(e): e.to_text
    GrantFailure(e): e.to_text
    PolicyFailure(e): Policy.to_text(e)
    InvalidFeed(reason: r): "invalid change feed: #{r}"
    FeedAlreadyExists(id: i): "change feed '#{i}' already exists"
    FeedNotFound(id: i): "change feed '#{i}' not found"
    PinMissing(feed_id: fid, pin_id: pid): "change feed '#{fid}' pin '#{pid}' is missing (call resync_feed after compaction/restore)"
    CursorStale(feed_id: fid, expected_txid: exp, actual_txid: act): "stale feed ack for '#{fid}': expected txid #{exp}, committed head is #{act}"
  end
end

fn feeds_table() : Table(Text, FeedSubscription)
  Table.text_key[FeedSubscription](feeds_bucket)
end

fn wrap_table(res: Result(T, TableError)) : Result(T, FeedError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, FeedError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(Table.Storage(e))) end)
end

fn decode_printable_text(raw: Bytes) : Option(Text)
  case raw.decode_utf8
    None: None
    Some(s):
      for c in s.chars
        if c < ' ' and c != '\t' and c != '\n' and c != '\r'
          return None
        end
      end
      Some(s)
  end
end

fn sort_unique_texts(xs: List(Text)) : List(Text)
  var seen = Set.empty
  var sorted = []
  for raw in xs
    t = raw.trim
    if not t.empty? and not seen.has?(t)
      seen = seen.add(t)
      var pos = 0
      while pos < sorted.size
        cur = sorted.get(pos) or ""
        break if t < cur
        pos += 1
      end
      sorted = sorted.take(pos).append(t).concat(sorted.drop(pos))
    end
  end
  sorted
end

fn should_watch_bucket?(sub: FeedSubscription, bname: Text) : Bool
  if sub.buckets.empty?
    if bname == pins_bucket or bname == feeds_bucket
      false
    else if not sub.include_internal and bname.starts_with?("_modb_")
      false
    else
      true
    end
  else
    sub.buckets.any?(fn(w) w == bname end)
  end
end

## Looks up a feed subscription by ID.
fn get_feed(store: Store, id: Text) : Result(Option(FeedSubscription), FeedError)
  wrap_table(Table.get(store, feeds_table(), id))
end

## Lists all active feed subscriptions in sorted ID order.
fn list_feeds(store: Store) : Result(List(FeedSubscription), FeedError)
  rows = try wrap_table(Table.all(store, feeds_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Registers a persistent reactive change feed anchored at the current committed root (`from_beginning == false`)
## or configured for initial full-snapshot bootstrap (`from_beginning == true`).
fn subscribe(
  db: Db,
  spec: FeedSpec,
  reason: Text,
  now: Time
) : Result((Db, FeedSubscription), FeedError)
  fid = spec.id.trim
  if fid.empty?
    return Error(InvalidFeed(reason: "feed id cannot be empty"))
  end
  who = spec.principal.trim
  if who.empty?
    return Error(InvalidFeed(reason: "principal cannot be empty"))
  end
  watched = sort_unique_texts(spec.buckets)
  pin_id = feed_pin_id(fid)
  next_txid = Ledger.txid(db) + 1
  meta_reason = if reason.trim.empty?: "subscribe feed '#{fid}'" else: reason
  meta = WriteMeta(principal: who, action: "feed_subscribe", reason: meta_reason, at: now)
  payload = Json.Object({
    "feed_id": Json.String(fid),
    "buckets": Json.Array(watched.map(fn(b) Json.String(b) end)),
    "from_beginning": Json.Boolean(spec.from_beginning)
  })
  (db1, sub) = try Ledger.transact(
    db,
    meta,
    "subscribe feed '#{fid}'",
    payload,
    fn(e) LedgerFailure(e) end,
    fn(tx)
      if (try wrap_table(Table.tx_get(tx, feeds_table(), fid))) is Some(_)
        return Error(FeedAlreadyExists(id: fid))
      end
      case spec.grant_id
        Some(gid):
          _ = try Grants.tx_verify_active(tx, gid, now).map_error(fn(e) GrantFailure(e) end)
        None: Unit
      end
      target_txid = if spec.from_beginning: 0 else: next_txid
      rec = FeedSubscription(
        id: fid,
        principal: who,
        grant_id: spec.grant_id,
        buckets: watched,
        include_internal: spec.include_internal,
        pin_id: pin_id,
        cursor_txid: target_txid,
        bootstrapped: not spec.from_beginning,
        created_at: now,
        last_acked_at: None,
        events_delivered: 0
      )
      t1 = try wrap_table(Table.put(tx, feeds_table(), fid, rec))
      Ok((t1, rec))
    end
  )
  if spec.from_beginning
    Ok((db1, sub))
  else
    (next_store, _pin) = try wrap_modb(Modb.pin_root(Ledger.store(db1), pin_id))
    Ok((Ledger.update_store(db1, next_store), sub))
  end
end

fn to_feed_event(bucket: Text, kd: KeyDiff) : FeedEvent
  case kd
    Added(key: k, value: v):
      FeedEvent(
        bucket: bucket,
        op: OpAdded,
        key_hex: k.to_hex,
        key_text: decode_printable_text(k),
        old_value_hex: None,
        new_value_hex: Some(v.to_hex),
        old_value_text: None,
        new_value_text: decode_printable_text(v)
      )
    Removed(key: k, value: v):
      FeedEvent(
        bucket: bucket,
        op: OpRemoved,
        key_hex: k.to_hex,
        key_text: decode_printable_text(k),
        old_value_hex: Some(v.to_hex),
        new_value_hex: None,
        old_value_text: decode_printable_text(v),
        new_value_text: None
      )
    Modified(key: k, old_value: ov, new_value: nv):
      FeedEvent(
        bucket: bucket,
        op: OpModified,
        key_hex: k.to_hex,
        key_text: decode_printable_text(k),
        old_value_hex: Some(ov.to_hex),
        new_value_hex: Some(nv.to_hex),
        old_value_text: decode_printable_text(ov),
        new_value_text: decode_printable_text(nv)
      )
  end
end

fn poll_feed_with_state(
  store: Store,
  pol: Policy.SensitivityPolicy,
  feed_id: Text,
  is_admin: Bool,
  limit: Int,
  now: Time
) : Result((FeedSubscription, Int, FeedBatch), FeedError)
  sub = try (try get_feed(store, feed_id)).or_fail(FeedNotFound(id: feed_id))
  case sub.grant_id
    Some(gid):
      _ = try Grants.tx_verify_active(Modb.begin_write(store), gid, now).map_error(
        fn(e) GrantFailure(e) end
      )
    None: Unit
  end
  eff = try Policy.effective_clearance(store, pol, sub.grant_id, is_admin).map_error(
    fn(e) PolicyFailure(e) end
  )
  cur_txid = Modb.txid(store)
  cur_root = Modb.catalog_root(store)

  (from_txid, base_root) = if not sub.bootstrapped
    (0, 0)
  else
    case try wrap_modb(Modb.get_pin(store, sub.pin_id))
      Some(p): (p.txid, p.catalog_root)
      None: return Error(PinMissing(feed_id: sub.id, pin_id: sub.pin_id))
    end
  end

  if sub.bootstrapped and base_root == cur_root
    return Ok((
      sub,
      base_root,
      FeedBatch(
        feed_id: sub.id,
        from_txid: from_txid,
        to_txid: cur_txid,
        clearance: eff,
        events: [],
        truncated: false,
        filtered_buckets: [],
        pages_read: 0,
        subtrees_skipped: 0
      )
    ))
  end

  candidates = if not sub.bootstrapped
    try wrap_modb(Modb.buckets(store))
  else
    changed_set = try wrap_modb(Modb.changed_buckets_between_roots(store, base_root, cur_root))
    sort_unique_texts(changed_set.to_list)
  end

  var permitted = []
  var filtered = []
  for bname in candidates
    if should_watch_bucket?(sub, bname)
      bsens = Policy.bucket_sensitivity(pol, bname)
      if Policy.permits?(eff, bsens)
        permitted = permitted.append(bname)
      else
        filtered = filtered.append(bname)
      end
    end
  end

  var events = []
  var pages_read = 0
  var subtrees_skipped = 0
  var truncated? = false

  for bname in permitted
    (kdiffs, dstats) = try wrap_modb(
      Modb.diff_bucket_roots_with_stats(store, base_root, cur_root, bname)
    )
    pages_read += dstats.pages_read
    subtrees_skipped += dstats.subtrees_skipped
    for kd in kdiffs
      if limit > 0 and events.size >= limit
        truncated? = true
        break
      end
      events = events.append(to_feed_event(bname, kd))
    end
    break if truncated?
  end

  Ok((
    sub,
    base_root,
    FeedBatch(
      feed_id: sub.id,
      from_txid: from_txid,
      to_txid: cur_txid,
      clearance: eff,
      events: events,
      truncated: truncated?,
      filtered_buckets: filtered,
      pages_read: pages_read,
      subtrees_skipped: subtrees_skipped
    )
  ))
end

## Pure read-only O(diff) poll returning structural changes since the feed's pinned cursor.
## Returns immediately with `pages_read: 0` when nothing changed; skips restricted buckets without
## reading a single B+Tree page.
fn poll_feed(
  store: Store,
  pol: Policy.SensitivityPolicy,
  feed_id: Text,
  is_admin: Bool,
  limit: Int,
  now: Time
) : Result(FeedBatch, FeedError)
  (_sub, _br, batch) = try poll_feed_with_state(store, pol, feed_id, is_admin, limit, now)
  Ok(batch)
end

## Atomically acknowledges delivery up to `up_to_txid` (optimistic CAS against current `txid`),
## moves the persistent CoW pin `"feed:<id>"` to `current_root`, and graduates deferred freelist
## pages. Uses direct `Modb.commit` to avoid appending self-triggering entries to `_modb_audit`.
fn ack_feed(
  db: Db,
  feed_id: Text,
  up_to_txid: Int,
  delivered_count: Int,
  now: Time
) : Result((Db, FeedSubscription), FeedError)
  store = Ledger.store(db)
  sub = try (try get_feed(store, feed_id)).or_fail(FeedNotFound(id: feed_id))
  cur_txid = Modb.txid(store)
  if up_to_txid < sub.cursor_txid
    return Error(
      InvalidFeed(reason: "up_to_txid #{up_to_txid} precedes current cursor #{sub.cursor_txid}")
    )
  end
  if up_to_txid > cur_txid
    return Error(
      InvalidFeed(reason: "up_to_txid #{up_to_txid} exceeds committed head #{cur_txid}")
    )
  end
  if up_to_txid < cur_txid
    return Error(CursorStale(feed_id: feed_id, expected_txid: up_to_txid, actual_txid: cur_txid))
  end

  var tx = Modb.begin_write(store)
  case try wrap_modb(Modb.get_pin(store, sub.pin_id))
    Some(_p): tx = try wrap_modb(Modb.tx_unpin_root(tx, sub.pin_id))
    None: Unit
  end
  (tx1, _pin) = try wrap_modb(Modb.tx_pin_base_root(tx, sub.pin_id))
  var next_sub = sub
  next_sub.cursor_txid = cur_txid
  next_sub.bootstrapped = true
  next_sub.last_acked_at = Some(now)
  if delivered_count > 0
    next_sub.events_delivered += delivered_count
  end
  tx2 = try wrap_table(Table.put(tx1, feeds_table(), feed_id, next_sub))
  committed = try wrap_modb(Modb.commit(tx2))
  Ok((Ledger.update_store(db, committed), next_sub))
end

## Polls and atomically advances the cursor when `truncated == false` in one operation.
## Zero-write no-op when already caught up at the current catalog root.
fn consume_feed(
  db: Db,
  pol: Policy.SensitivityPolicy,
  feed_id: Text,
  is_admin: Bool,
  limit: Int,
  now: Time
) : Result((Db, FeedBatch, FeedSubscription), FeedError)
  store = Ledger.store(db)
  (sub, base_root, batch) = try poll_feed_with_state(store, pol, feed_id, is_admin, limit, now)
  if batch.truncated or (sub.bootstrapped and base_root == Modb.catalog_root(store))
    return Ok((db, batch, sub))
  end
  (next_db, next_sub) = try ack_feed(db, feed_id, batch.to_txid, batch.events.size, now)
  Ok((next_db, batch, next_sub))
end

## Re-anchors a feed's CoW pin after compaction or snapshot restore (`PinMissing` recovery).
fn resync_feed(
  db: Db,
  feed_id: Text,
  from_beginning: Bool,
  now: Time
) : Result((Db, FeedSubscription), FeedError)
  store = Ledger.store(db)
  sub = try (try get_feed(store, feed_id)).or_fail(FeedNotFound(id: feed_id))
  cur_txid = Modb.txid(store)
  var tx = Modb.begin_write(store)
  case try wrap_modb(Modb.get_pin(store, sub.pin_id))
    Some(_p): tx = try wrap_modb(Modb.tx_unpin_root(tx, sub.pin_id))
    None: Unit
  end
  var next_tx = tx
  if not from_beginning
    (t_pin, _p) = try wrap_modb(Modb.tx_pin_base_root(next_tx, sub.pin_id))
    next_tx = t_pin
  end
  var next_sub = sub
  next_sub.bootstrapped = not from_beginning
  next_sub.cursor_txid = if from_beginning: 0 else: cur_txid
  next_sub.last_acked_at = Some(now)
  t_done = try wrap_table(Table.put(next_tx, feeds_table(), feed_id, next_sub))
  committed = try wrap_modb(Modb.commit(t_done))
  Ok((Ledger.update_store(db, committed), next_sub))
end

## Removes a feed subscription from `_modb_feeds`, releases its CoW pin, and audits unsubscription.
fn unsubscribe(db: Db, feed_id: Text, meta: WriteMeta) : Result(Db, FeedError)
  payload = Json.Object({"feed_id": Json.String(feed_id)})
  (next_db, _u) = try Ledger.transact(
    db,
    meta,
    "unsubscribe feed '#{feed_id}'",
    payload,
    fn(e) LedgerFailure(e) end,
    fn(tx)
      s_opt = try wrap_table(Table.tx_get(tx, feeds_table(), feed_id))
      sub = try s_opt.or_fail(FeedNotFound(id: feed_id))
      t1 = try wrap_table(Table.delete(tx, feeds_table(), feed_id))
      t2 = case try wrap_modb(Modb.get_pin(tx.base, sub.pin_id))
        Some(_p): try wrap_modb(Modb.tx_unpin_root(t1, sub.pin_id))
        None: t1
      end
      Ok((t2, Unit))
    end
  )
  Ok(next_db)
end

## Lock-coordinated multi-worker wrappers.
fn subscribe_locked(
  files: Files,
  path: Text,
  sc: Schema,
  spec: FeedSpec,
  reason: Text,
  now: Time
) : Result(FeedSubscription, FeedError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, sub) = try subscribe(db, spec, reason, now)
      Ok(sub)
    end
  )
end

fn poll_feed_locked(
  rf: ReadFiles,
  path: Text,
  sc: Schema,
  pol: Policy.SensitivityPolicy,
  feed_id: Text,
  is_admin: Bool,
  limit: Int,
  now: Time
) : Result(FeedBatch, FeedError)
  Ledger.read_locked(
    rf,
    path,
    sc,
    fn(e) LedgerFailure(e) end,
    fn(db) poll_feed(Ledger.store(db), pol, feed_id, is_admin, limit, now) end
  )
end

fn ack_feed_locked(
  files: Files,
  path: Text,
  sc: Schema,
  feed_id: Text,
  up_to_txid: Int,
  delivered_count: Int,
  now: Time
) : Result(FeedSubscription, FeedError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, sub) = try ack_feed(db, feed_id, up_to_txid, delivered_count, now)
      Ok(sub)
    end
  )
end

fn consume_feed_locked(
  files: Files,
  path: Text,
  sc: Schema,
  pol: Policy.SensitivityPolicy,
  feed_id: Text,
  is_admin: Bool,
  limit: Int,
  now: Time
) : Result((FeedBatch, FeedSubscription), FeedError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, batch, sub) = try consume_feed(db, pol, feed_id, is_admin, limit, now)
      Ok((batch, sub))
    end
  )
end

fn resync_feed_locked(
  files: Files,
  path: Text,
  sc: Schema,
  feed_id: Text,
  from_beginning: Bool,
  now: Time
) : Result(FeedSubscription, FeedError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, sub) = try resync_feed(db, feed_id, from_beginning, now)
      Ok(sub)
    end
  )
end

fn unsubscribe_locked(
  files: Files,
  path: Text,
  sc: Schema,
  feed_id: Text,
  meta: WriteMeta
) : Result(Unit, FeedError)
  Ledger.locked(
    files,
    path,
    sc,
    meta.at,
    fn(e) LedgerFailure(e) end,
    fn(db)
      _next = try unsubscribe(db, feed_id, meta)
      Ok(Unit)
    end
  )
end

struct FeedRec
  msg: Text
end

test "Modb.Feeds: subscribe, O(1) idle poll, O(diff) events, sensitivity skip, CAS & freelist reclaim"
  files = Files.in_memory({})
  t0 = Time.parse("2026-11-26T16:20:00Z") or stop "t0"
  t1 = Time.parse("2026-11-26T18:00:00Z") or stop "t1"
  sc = Ledger.schema(0).with_require_reason(false)
  pub_t = Table.text_key[FeedRec]("events")
  sec_t = Table.text_key[FeedRec]("secrets")
  pol = Policy.policy().with_bucket_sensitivity("secrets", Policy.Secret)

  assert Ledger.open(files, "feeds.modb", sc, t0) is Ok(db0)
  m = Ledger.WriteMeta(principal: "admin", action: "seed", reason: "init", at: t0)
  assert Ledger.write(db0, m, "seed", Json.Null, fn(tx)
    Table.put(tx, pub_t, "k1", FeedRec(msg: "one"))
  end) is
    Ok(db1)

  assert Grants.issue_root(
    db1,
    m,
    Grants.GrantSpec(
      id: "g-watch",
      principal: "agent:watcher",
      allowed_actions: ["noop"],
      max_calls: 10,
      expires_at: t1
    )
  ) is
    Ok((db2, _))

  ## Tail subscription anchored at current root
  assert subscribe(
    db2,
    FeedSpec(
      id: "sub-tail",
      principal: "agent:watcher",
      grant_id: Some("g-watch"),
      buckets: [],
      include_internal: false,
      from_beginning: false
    ),
    "watch events",
    t0
  ) is
    Ok((db3, _sub0))

  ## Idle poll reads 0 pages
  assert poll_feed(Ledger.store(db3), pol, "sub-tail", false, 100, t0) is Ok(idle_b)
  assert idle_b.events.empty? and idle_b.pages_read == 0

  ## Mutate both `events` and `secrets`
  assert Ledger.write(db3, m, "mutate", Json.Null, fn(tx)
    t_a = try Table.put(tx, pub_t, "k1", FeedRec(msg: "one-updated"))
    t_b = try Table.put(t_a, pub_t, "k2", FeedRec(msg: "two"))
    Table.put(t_b, sec_t, "s1", FeedRec(msg: "api-key"))
  end) is
    Ok(db4)

  assert poll_feed(Ledger.store(db4), pol, "sub-tail", false, 100, t0) is Ok(b1)
  assert b1.events.size == 2 and b1.filtered_buckets == ["secrets"]

  ## Concurrent write makes old txid ack return CursorStale!
  assert Ledger.write(db4, m, "more", Json.Null, fn(tx)
    Table.delete(tx, pub_t, "k1")
  end) is
    Ok(db5)
  assert ack_feed(db5, "sub-tail", b1.to_txid, 2, t0) is
    Error(CursorStale(feed_id: "sub-tail", expected_txid: _, actual_txid: _))

  ## Atomic consume_feed reads updated delta and advances pin cleanly
  assert consume_feed(db5, pol, "sub-tail", false, 100, t0) is Ok((db6, b2, sub2))
  assert b2.events.size == 2 and sub2.bootstrapped and sub2.events_delivered == 2
  assert poll_feed(Ledger.store(db6), pol, "sub-tail", false, 100, t0) is Ok(b3)
  assert b3.events.empty? and b3.pages_read == 0

  assert Ledger.verify_all(db6) is Ok(_)
  assert unsubscribe(db6, "sub-tail", m) is Ok(db7)
  assert Ledger.verify_all(db7) is Ok(_)
end
