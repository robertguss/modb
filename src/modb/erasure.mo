## MoDB Layer 4: Dual-Layer Verifiable Historical Erasure ("Right to Be Forgotten")
## (`design.md` §4.8, `wiki/ideas/deleting-personal-data-from-history.md`).
##
## Combines:
##   1. Layer A — O(1) Per-Subject AES-256-GCM Crypto-Shredding (`Crypto.seal` / `Crypto.open`)
##      so shredding a subject's 32-byte key in `_modb_erasure_keys` immediately destroys
##      confidentiality across every snapshot and backup without waiting for compaction;
##   2. Layer B — Atomic Multi-Store Scrubbing (`_modb_subject_refs`, live tables, `Modb.Fts`,
##      `Modb.Vec`, `Modb.Replay` call history, `Modb.Views` read log) + hash-chain-preserving
##      `_modb_audit` tombstone redaction & deterministic re-chaining, followed by optional physical
##      CoW page eviction (`compact_after_erasure`) and verifiable `ErasureReceipt`s.
module Modb.Erasure
expose erasure_keys_bucket,
subject_refs_bucket,
erasure_receipts_bucket,
SubjectKeyRecord(..),
SubjectRefRecord(..),
ErasureRequest(..),
ErasureReceipt(..),
ErasureError(..),
to_text,
erasure_request,
get_subject_key,
provision_subject_key,
seal_for_subject,
open_for_subject,
shred_subject_key,
tx_register_subject_ref,
register_subject_ref,
list_erasure_receipts,
get_erasure_receipt,
erase_subject,
compact_after_erasure,
provision_subject_key_locked,
shred_subject_key_locked,
register_subject_ref_locked,
erase_subject_locked
use Crypto
use Json
use Modb{Store, WriteTx}
use Modb.Errors{ModbError}
use Modb.Export
use Modb.Fts
use Modb.Ledger{AuditEntry, Db, LedgerError, Schema, SchemaState, WriteMeta}
use Modb.Replay
use Modb.Table{Index, Table, TableError}
use Modb.Vec
use Modb.Views

## Reserved internal buckets for crypto-shredding keys, subject ref tracking, and erasure receipts.
erasure_keys_bucket = "_modb_erasure_keys"
subject_refs_bucket = "_modb_subject_refs"
erasure_receipts_bucket = "_modb_erasure_receipts"

enc_prefix = "modb-enc:v1:"

## Per-subject AES-256-GCM data encryption key record persisted in `_modb_erasure_keys`.
struct SubjectKeyRecord
  subject_id: Text
  key_b64: Text
  shredded?: Bool
  created_at: Time
  shredded_at: Option(Time)
  shredded_by: Option(Text)
end

## Tracks one persisted live row (and optional FTS/Vec `doc_id`) owned by a data subject.
struct SubjectRefRecord
  ref_id: Text
  subject_id: Text
  bucket: Text
  key_hex: Text
  doc_id: Option(Text)
end

## Complete multi-store erasure specification for one data subject.
struct ErasureRequest
  receipt_id: Text
  subject_id: Text
  match_tokens: List(Text)
  extra_bucket_keys: List((Text, Bytes))
  fts_indexes: List((Fts.FtsIndex, Text))
  vec_indexes: List((Vec.VecIndex, Text))
  shred_key?: Bool
  scrub_audit?: Bool
  scrub_replay?: Bool
  scrub_read_log?: Bool
end

## Tamper-evident erasure receipt stored in `_modb_erasure_receipts` (carries zero raw PII).
struct ErasureReceipt
  id: Text
  subject_id_sha256: Text
  erased_by: Text
  reason: Text
  at: Time
  key_shredded?: Bool
  rows_deleted: Int
  fts_docs_deleted: Int
  vec_docs_deleted: Int
  replay_calls_scrubbed: Int
  read_logs_scrubbed: Int
  audit_entries_redacted: Int
  pre_erasure_tip_hash: Text
  post_erasure_tip_hash: Text
  compacted?: Bool
end

## Every failure returned by `Modb.Erasure` operations.
enum ErasureError
  LedgerFailure(LedgerError)
  ExportFailure(Export.ExportError)
  FtsFailure(Fts.FtsError)
  VecFailure(Vec.VecError)
  InvalidRequest(reason: Text)
  KeyNotFound(subject_id: Text)
  KeyShredded(subject_id: Text)
  CryptoFailure(detail: Text)
  ErasureDenied(reason: Text)
  ReceiptAlreadyExists(id: Text)
  ReceiptNotFound(id: Text)
end

## Formats an `ErasureError` as a human-readable diagnostic.
fn to_text(err: ErasureError) : Text
  case err
    LedgerFailure(e): e.to_text
    ExportFailure(e): Export.to_text(e)
    FtsFailure(e): Fts.to_text(e)
    VecFailure(e): Vec.to_text(e)
    InvalidRequest(reason: r): "invalid erasure request: #{r}"
    KeyNotFound(subject_id: s): "no crypto-shredding key provisioned for subject '#{s}'"
    KeyShredded(subject_id: s): "subject '#{s}' encryption key has been permanently shredded"
    CryptoFailure(detail: d): "crypto failure: #{d}"
    ErasureDenied(reason: r): "erasure denied: #{r}"
    ReceiptAlreadyExists(id: i): "erasure receipt '#{i}' already exists"
    ReceiptNotFound(id: i): "erasure receipt '#{i}' not found"
  end
end

fn erasure_keys_table() : Table(Text, SubjectKeyRecord)
  Table.text_key[SubjectKeyRecord](erasure_keys_bucket)
end

fn refs_by_subject_index() : Index(Text, SubjectRefRecord, Text)
  Table.text_index[Text, SubjectRefRecord]("_modb_subject_refs_by_subj", fn(r) r.subject_id end)
end

fn subject_refs_table() : Table(Text, SubjectRefRecord)
  Table.text_key[SubjectRefRecord](subject_refs_bucket).with_index(refs_by_subject_index())
end

fn erasure_receipts_table() : Table(Text, ErasureReceipt)
  Table.text_key[ErasureReceipt](erasure_receipts_bucket)
end

fn wrap_table(res: Result(T, TableError)) : Result(T, ErasureError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(e)) end)
end

fn wrap_modb(res: Result(T, ModbError)) : Result(T, ErasureError)
  res.map_error(fn(e) LedgerFailure(Ledger.TableFailure(Table.Storage(e))) end)
end

## Builds a default `ErasureRequest` enabling key shredding, audit redaction, replay, and read-log scrubbing.
fn erasure_request(receipt_id: Text, subject_id: Text) : ErasureRequest
  ErasureRequest(
    receipt_id: receipt_id,
    subject_id: subject_id,
    match_tokens: [],
    extra_bucket_keys: [],
    fts_indexes: [],
    vec_indexes: [],
    shred_key?: true,
    scrub_audit?: true,
    scrub_replay?: true,
    scrub_read_log?: true
  )
end

## Looks up a subject's persisted encryption key record in `_modb_erasure_keys`.
fn get_subject_key(store: Store, subject_id: Text) : Result(Option(SubjectKeyRecord), ErasureError)
  wrap_table(Table.get(store, erasure_keys_table(), subject_id))
end

## Lists all `ErasureReceipt`s persisted in `_modb_erasure_receipts`.
fn list_erasure_receipts(store: Store) : Result(List(ErasureReceipt), ErasureError)
  rows = try wrap_table(Table.all(store, erasure_receipts_table()))
  Ok(rows.map(fn(p) p.1 end))
end

## Looks up a single `ErasureReceipt` by ID.
fn get_erasure_receipt(store: Store, id: Text) : Result(Option(ErasureReceipt), ErasureError)
  wrap_table(Table.get(store, erasure_receipts_table(), id))
end

## Pre-generated 32-byte key variant for lock-coordinated callers (keeps `SecureRandom` out of closure).
fn provision_subject_key_raw(
  db: Db,
  subject_id: Text,
  dek_b64: Text,
  meta: WriteMeta
) : Result((Db, SubjectKeyRecord), ErasureError)
  sid = subject_id.trim
  return Error(InvalidRequest(reason: "subject_id cannot be empty")) if sid.empty?
  case try get_subject_key(Ledger.store(db), sid)
    Some(rec):
      return Error(KeyShredded(subject_id: sid)) if rec.shredded?
      Ok((db, rec))
    None:
      sub_hash = Crypto.sha256(sid.bytes).to_hex
      rec = SubjectKeyRecord(
        subject_id: sid,
        key_b64: dek_b64,
        shredded?: false,
        created_at: meta.at,
        shredded_at: None,
        shredded_by: None
      )
      Ledger.transact(
        db,
        meta,
        "provision erasure key (#{Text.from_chars(sub_hash.chars.take(12))})",
        Json.Object({"subject_sha256": Json.String(sub_hash)}),
        fn(e) LedgerFailure(e) end,
        fn(tx)
          if (try wrap_table(Table.tx_get(tx, erasure_keys_table(), sid))) is Some(ex)
            return Error(KeyShredded(subject_id: sid)) if ex.shredded?
            return Ok((tx, ex))
          end
          t1 = try wrap_table(Table.put(tx, erasure_keys_table(), sid, rec))
          Ok((t1, rec))
        end
      )
  end
end

## Provisions a 32-byte AES-256-GCM key for `subject_id` (fails with `KeyShredded` if previously shredded).
fn provision_subject_key(
  db: Db,
  srng: SecureRandom,
  subject_id: Text,
  meta: WriteMeta
) : Result((Db, SubjectKeyRecord), ErasureError)
  dek = srng.bytes(32).to_base64url
  provision_subject_key_raw(db, subject_id, dek, meta)
end

fn decode_subject_key(store: Store, subject_id: Text) : Result(Bytes, ErasureError)
  sid = subject_id.trim
  rec = try (try get_subject_key(store, sid)).or_fail(KeyNotFound(subject_id: sid))
  return Error(KeyShredded(subject_id: sid)) if rec.shredded?
  raw = try Bytes.from_base64url(rec.key_b64).or_fail(
    CryptoFailure(detail: "corrupt base64 key for '#{sid}'")
  )
  return Error(CryptoFailure(detail: "invalid AES-256 key length")) if raw.size != 32
  Ok(raw)
end

## Encrypts UTF-8 `plaintext` under `subject_id`'s AES-256-GCM DEK with domain-separated AAD.
fn seal_for_subject(
  store: Store,
  srng: SecureRandom,
  subject_id: Text,
  field_aad: Text,
  plaintext: Text
) : Result(Text, ErasureError)
  key = try decode_subject_key(store, subject_id)
  nonce = srng.bytes(12)
  aad = "modb:erase:v1:#{subject_id.trim}:#{field_aad.trim}".bytes
  ct = try Crypto.seal(key, nonce, plaintext.bytes, aad).map_error(fn(e)
    CryptoFailure(detail: "AES-GCM seal failed: #{e}")
  end)
  Ok("#{enc_prefix}#{nonce.to_base64url}:#{ct.to_base64url}")
end

## Decrypts an envelope encrypted for `subject_id`. Fails immediately with `KeyShredded` once shredded.
fn open_for_subject(store: Store, subject_id: Text, field_aad: Text, encoded: Text) : Result(
  Text,
  ErasureError
)
  key = try decode_subject_key(store, subject_id)
  body = try encoded.drop_prefix(enc_prefix).or_fail(
    CryptoFailure(detail: "ciphertext missing modb-enc:v1 prefix")
  )
  parts = body.split(":")
  return Error(CryptoFailure(detail: "malformed encrypted envelope")) if parts.size != 2
  nonce = try Bytes.from_base64url(parts.first or "").or_fail(
    CryptoFailure(detail: "invalid envelope nonce")
  )
  ct = try Bytes.from_base64url(parts.get(1) or "").or_fail(
    CryptoFailure(detail: "invalid envelope ciphertext")
  )
  aad = "modb:erase:v1:#{subject_id.trim}:#{field_aad.trim}".bytes
  plain = try Crypto.open(key, nonce, ct, aad).map_error(fn(e)
    CryptoFailure(detail: "AES-GCM open failed: #{e}")
  end)
  plain.decode_utf8.or_fail(CryptoFailure(detail: "decrypted bytes are not valid UTF-8"))
end

## Admin-only $O(1)$ shredding of `subject_id`'s AES-256-GCM key without compacting history.
fn shred_subject_key(
  db: Db,
  subject_id: Text,
  reviewer: Text,
  is_admin: Bool,
  reason: Text,
  now: Time
) : Result((Db, SubjectKeyRecord), ErasureError)
  if not is_admin
    return Error(ErasureDenied(reason: "admin required to shred encryption key"))
  end
  sid = subject_id.trim
  who = reviewer.trim
  return Error(InvalidRequest(reason: "subject_id cannot be empty")) if sid.empty?
  return Error(ErasureDenied(reason: "reviewer cannot be empty")) if who.empty?
  sub_hash = Crypto.sha256(sid.bytes).to_hex
  eff_reason = if reason.trim.empty?: "crypto-shred subject #{Text.from_chars(sub_hash.chars.take(12))}" else: reason
    .trim
  meta = WriteMeta(principal: who, action: "erasure_key_shredded", reason: eff_reason, at: now)
  payload = Json.Object({"subject_sha256": Json.String(sub_hash)})
  Ledger.transact(
    db,
    meta,
    "crypto-shred subject (#{Text.from_chars(sub_hash.chars.take(12))})",
    payload,
    fn(e) LedgerFailure(e) end,
    fn(tx)
      r_opt = try wrap_table(Table.tx_get(tx, erasure_keys_table(), sid))
      rec = try r_opt.or_fail(KeyNotFound(subject_id: sid))
      if rec.shredded?
        return Ok((tx, rec))
      end
      var next_rec = rec
      next_rec.key_b64 = ""
      next_rec.shredded? = true
      next_rec.shredded_at = Some(now)
      next_rec.shredded_by = Some(who)
      t1 = try wrap_table(Table.put(tx, erasure_keys_table(), sid, next_rec))
      Ok((t1, next_rec))
    end
  )
end

## Registers a `(bucket, key_bytes)` row (and optional `doc_id`) owned by `subject_id` inside `tx`.
fn tx_register_subject_ref(
  tx: WriteTx,
  subject_id: Text,
  bucket: Text,
  key_bytes: Bytes,
  doc_id_opt: Option(Text)
) : Result(WriteTx, ErasureError)
  sid = subject_id.trim
  return Error(InvalidRequest(reason: "subject_id cannot be empty")) if sid.empty?
  khex = key_bytes.to_hex
  rid = "#{sid}\u{1f}#{bucket}\u{1f}#{khex}"
  rec = SubjectRefRecord(
    ref_id: rid,
    subject_id: sid,
    bucket: bucket,
    key_hex: khex,
    doc_id: doc_id_opt
  )
  wrap_table(Table.put(tx, subject_refs_table(), rid, rec))
end

## Accountable standalone wrapper registering a subject's persisted row reference.
fn register_subject_ref(
  db: Db,
  subject_id: Text,
  bucket: Text,
  key_bytes: Bytes,
  doc_id_opt: Option(Text),
  meta: WriteMeta
) : Result(Db, ErasureError)
  sub_hash = Crypto.sha256(subject_id.trim.bytes).to_hex
  (next_db, _u) = try Ledger.transact(
    db,
    meta,
    "register subject ref (#{Text.from_chars(sub_hash.chars.take(12))})",
    Json.Object({"bucket": Json.String(bucket), "subject_sha256": Json.String(sub_hash)}),
    fn(e) LedgerFailure(e) end,
    fn(tx)
      tx1 = try tx_register_subject_ref(tx, subject_id, bucket, key_bytes, doc_id_opt)
      Ok((tx1, Unit))
    end
  )
  Ok(next_db)
end

fn text_matches_any_token?(haystack: Text, tokens: List(Text)) : Bool
  return false if haystack.empty?
  tokens.any?(fn(tok) not tok.empty? and haystack.contains?(tok) end)
end

fn collect_match_tokens(req: ErasureRequest) : List(Text)
  var out = []
  sid = req.subject_id.trim
  if not sid.empty?
    out = out.append(sid)
  end
  for raw in req.match_tokens
    t = raw.trim
    if not t.empty? and not out.any?(fn(x) x == t end)
      out = out.append(t)
    end
  end
  out
end

fn audit_entry_matches?(entry: AuditEntry, tokens: List(Text)) : Bool
  text_matches_any_token?(entry.principal, tokens) or
    text_matches_any_token?(entry.reason, tokens) or
    text_matches_any_token?(entry.summary, tokens) or
    text_matches_any_token?(Json.encode(entry.payload), tokens)
end

fn call_record_matches?(c: Replay.CallRecord, tokens: List(Text)) : Bool
  text_matches_any_token?(c.principal, tokens) or
    text_matches_any_token?(c.reason, tokens) or
    text_matches_any_token?(Json.encode(c.args), tokens) or
    text_matches_any_token?(Json.encode(c.outcome), tokens)
end

fn read_log_matches?(r: Views.ReadLogEntry, tokens: List(Text)) : Bool
  text_matches_any_token?(r.principal, tokens) or
    text_matches_any_token?(Json.encode(r.request_json), tokens)
end

## Atomically executes dual-layer verifiable subject erasure:
## 1. Verifies existing `_modb_audit` hash chain integrity BEFORE modifying history.
## 2. Shreds subject key in `_modb_erasure_keys` (if provisioned & `shred_key?`), deletes all
##    live `_modb_subject_refs` + `extra_bucket_keys` rows, removes FTS + Vec documents, scrubs
##    matching `_modb_replay_calls` and `_modb_read_log` PII, and redacts + deterministically
##    re-chains `_modb_audit` (plus `_modb_checkpoints` / `_modb_meta`).
## 3. Appends an `"erasure_executed"` audit entry (SHA-256 subject ref only) and persists
##    an `ErasureReceipt` in `_modb_erasure_receipts`.
fn erase_subject(
  db: Db,
  req: ErasureRequest,
  reviewer: Text,
  is_admin: Bool,
  reason: Text,
  now: Time
) : Result((Db, ErasureReceipt), ErasureError)
  if not is_admin
    return Error(ErasureDenied(reason: "human admin required to execute subject erasure"))
  end
  rid = req.receipt_id.trim
  sid = req.subject_id.trim
  who = reviewer.trim
  return Error(InvalidRequest(reason: "receipt_id cannot be empty")) if rid.empty?
  return Error(InvalidRequest(reason: "subject_id cannot be empty")) if sid.empty?
  return Error(ErasureDenied(reason: "reviewer cannot be empty")) if who.empty?

  # Verify integrity before any redaction so erasure can never mask prior corruption.
  _ = try Ledger.verify_audit(db).map_error(fn(e) LedgerFailure(e) end)
  st = Ledger.store(db)
  if (try get_erasure_receipt(st, rid)) is Some(_)
    return Error(ReceiptAlreadyExists(id: rid))
  end

  tokens = collect_match_tokens(req)
  subj_hash = Crypto.sha256(sid.bytes).to_hex
  short_hash = Text.from_chars(subj_hash.chars.take(12))
  eff_reason = if reason.trim.empty?: "erase subject #{short_hash}" else: reason.trim
  pre_tip = db.state.last_audit_hash
  expected_txid = Ledger.txid(db) + 1
  var tx = Modb.begin_write(st)

  # 1. Layer A: Crypto-shred subject key if present
  var key_shredded? = false
  if req.shred_key?
    case try wrap_table(Table.tx_get(tx, erasure_keys_table(), sid))
      Some(krec):
        if not krec.shredded?
          var next_k = krec
          next_k.key_b64 = ""
          next_k.shredded? = true
          next_k.shredded_at = Some(now)
          next_k.shredded_by = Some(who)
          tx = try wrap_table(Table.put(tx, erasure_keys_table(), sid, next_k))
        end
        key_shredded? = true
      None: Unit
    end
  end

  # 2. Layer B1: Delete registered live rows & ref records + explicit extra keys
  var rows_deleted = 0
  var doc_ids = []
  refs = try wrap_table(Table.lookup(st, subject_refs_table(), refs_by_subject_index(), sid))
  for (ref_k, ref_rec) in refs
    case Bytes.from_hex(ref_rec.key_hex)
      Some(kb):
        case try wrap_modb(Modb.tx_get(tx, ref_rec.bucket, kb))
          Some(_existing):
            tx = try wrap_modb(Modb.tx_delete(tx, ref_rec.bucket, kb))
            rows_deleted += 1
          None: Unit
        end
      None: Unit
    end
    case ref_rec.doc_id
      Some(did) if not did.trim.empty? and not doc_ids.any?(fn(x) x == did.trim end):
        doc_ids = doc_ids.append(did.trim)
      Some(_) | None: Unit
    end
    tx = try wrap_table(Table.delete(tx, subject_refs_table(), ref_k))
  end

  for (bname, kb) in req.extra_bucket_keys
    case try wrap_modb(Modb.tx_get(tx, bname, kb))
      Some(_existing):
        tx = try wrap_modb(Modb.tx_delete(tx, bname, kb))
        rows_deleted += 1
      None: Unit
    end
  end

  # 3. Layer B2: Remove FTS & Vec documents
  var fts_deleted = 0
  for (fidx, did) in req.fts_indexes
    if (try Fts.get_doc(st, fidx, did).map_error(fn(e) FtsFailure(e) end)) is Some(_)
      tx = try Fts.tx_remove_document(tx, fidx, did).map_error(fn(e) FtsFailure(e) end)
      fts_deleted += 1
    end
  end
  var vec_deleted = 0
  for (vidx, did) in req.vec_indexes
    if (try Vec.get_doc(st, vidx, did).map_error(fn(e) VecFailure(e) end)) is Some(_)
      tx = try Vec.tx_remove_vector(tx, vidx, did).map_error(fn(e) VecFailure(e) end)
      vec_deleted += 1
    end
  end

  # 4. Layer B3: Scrub Replay calls & Read logs
  var calls_scrubbed = 0
  if req.scrub_replay?
    calls_tbl = Replay.replay_calls_table()
    crows = try wrap_table(Table.tx_scan(tx, calls_tbl, None, None, 0))
    for (_seq, crec) in crows
      if call_record_matches?(crec, tokens)
        var next_c = crec
        if text_matches_any_token?(next_c.principal, tokens)
          next_c.principal = "erased:#{short_hash}"
        end
        next_c.args = Json.Object({
          "erased": Json.Boolean(true),
          "subject_sha256": Json.String(subj_hash)
        })
        next_c.reason = "[erased:#{short_hash}]"
        next_c.outcome = Replay.OrigOk(reply: Json.Object({"erased": Json.Boolean(true)}))
        tx = try wrap_table(Table.put(tx, calls_tbl, crec.seq, next_c))
        calls_scrubbed += 1
      end
    end
  end

  var read_logs_scrubbed = 0
  if req.scrub_read_log?
    rlog_tbl = Views.read_log_table()
    rrows = try wrap_table(Table.tx_scan(tx, rlog_tbl, None, None, 0))
    for (_seq, rrec) in rrows
      if read_log_matches?(rrec, tokens)
        var next_r = rrec
        if text_matches_any_token?(next_r.principal, tokens)
          next_r.principal = "erased:#{short_hash}"
        end
        next_r.request_json = Json.Object({
          "erased": Json.Boolean(true),
          "subject_sha256": Json.String(subj_hash)
        })
        tx = try wrap_table(Table.put(tx, rlog_tbl, rrec.seq, next_r))
        read_logs_scrubbed += 1
      end
    end
  end

  # 5. Layer B4: Redact matching `_modb_audit` entries and deterministically re-chain hashes
  audit_tbl = Ledger.audit_table()
  arows = try wrap_table(Table.tx_scan(tx, audit_tbl, None, None, 0))
  cp_opt = try Ledger.latest_checkpoint(db).map_error(fn(e) LedgerFailure(e) end)
  var audit_redacted = 0
  var prev_h = Ledger.genesis_hash
  var cp_new_hash = None
  for (_kseq, aentry) in arows
    matched? = req.scrub_audit? and audit_entry_matches?(aentry, tokens)
    eff_principal = if matched? and text_matches_any_token?(aentry.principal, tokens)
      "erased:#{short_hash}"
    else
      aentry.principal
    end
    eff_a_reason = if matched?: "[erased:#{short_hash}]" else: aentry.reason
    eff_summary = if matched?: "[erased]" else: aentry.summary
    eff_payload = if matched?
      Json.Object({"erased": Json.Boolean(true), "subject_sha256": Json.String(subj_hash)})
    else
      aentry.payload
    end
    if matched?
      audit_redacted += 1
    end
    new_eh = Ledger.compute_entry_hash(
      aentry.seq,
      aentry.txid,
      aentry.schema_version,
      eff_principal,
      aentry.action,
      eff_a_reason,
      aentry.at,
      eff_summary,
      eff_payload,
      prev_h
    )
    if matched? or aentry.prev_hash != prev_h or aentry.entry_hash != new_eh
      var next_a = aentry
      next_a.principal = eff_principal
      next_a.reason = eff_a_reason
      next_a.summary = eff_summary
      next_a.payload = eff_payload
      next_a.prev_hash = prev_h
      next_a.entry_hash = new_eh
      tx = try wrap_table(Table.put(tx, audit_tbl, aentry.seq, next_a))
    end
    case cp_opt
      Some(cp) if cp.seq == aentry.seq: cp_new_hash = Some(new_eh)
      Some(_) | None: Unit
    end
    prev_h = new_eh
  end

  # Append the non-PII `erasure_executed` audit entry at the new tail & update `_modb_meta`
  next_seq = db.state.next_audit_seq
  cur_ver = db.state.version
  exec_summary = "erase subject #{short_hash}"
  exec_payload = Json.Object({
    "receipt_id": Json.String(rid),
    "subject_sha256": Json.String(subj_hash),
    "key_shredded": Json.Boolean(key_shredded?),
    "rows_deleted": Json.int(rows_deleted),
    "fts_docs_deleted": Json.int(fts_deleted),
    "vec_docs_deleted": Json.int(vec_deleted),
    "replay_calls_scrubbed": Json.int(calls_scrubbed),
    "read_logs_scrubbed": Json.int(read_logs_scrubbed),
    "audit_entries_redacted": Json.int(audit_redacted)
  })
  exec_hash = Ledger.compute_entry_hash(
    next_seq,
    expected_txid,
    cur_ver,
    who,
    "erasure_executed",
    eff_reason,
    now,
    exec_summary,
    exec_payload,
    prev_h
  )
  exec_entry = AuditEntry(
    seq: next_seq,
    txid: expected_txid,
    schema_version: cur_ver,
    principal: who,
    action: "erasure_executed",
    reason: eff_reason,
    at: now,
    summary: exec_summary,
    payload: exec_payload,
    prev_hash: prev_h,
    entry_hash: exec_hash
  )
  tx = try wrap_table(Table.put(tx, audit_tbl, next_seq, exec_entry))

  next_state = SchemaState(version: cur_ver, next_audit_seq: next_seq + 1, last_audit_hash: exec_hash)
  tx = try wrap_table(Table.put(tx, Ledger.meta_table(), "state", next_state))

  case (cp_opt, cp_new_hash)
    (Some(cp), Some(new_ch)) if new_ch != cp.audit_hash:
      var next_cp = cp
      next_cp.audit_hash = new_ch
      tx = try wrap_table(Table.put(tx, Ledger.checkpoint_table(), "latest", next_cp))
    _: Unit
  end

  receipt = ErasureReceipt(
    id: rid,
    subject_id_sha256: subj_hash,
    erased_by: who,
    reason: eff_reason,
    at: now,
    key_shredded?: key_shredded?,
    rows_deleted: rows_deleted,
    fts_docs_deleted: fts_deleted,
    vec_docs_deleted: vec_deleted,
    replay_calls_scrubbed: calls_scrubbed,
    read_logs_scrubbed: read_logs_scrubbed,
    audit_entries_redacted: audit_redacted,
    pre_erasure_tip_hash: pre_tip,
    post_erasure_tip_hash: exec_hash,
    compacted?: false
  )
  tx = try wrap_table(Table.put(tx, erasure_receipts_table(), rid, receipt))

  committed = try wrap_modb(Modb.commit(tx))
  if Modb.txid(committed) != expected_txid
    return Error(
      LedgerFailure(
        Ledger.AuditCorrupt(
          reason: "erasure txid mismatch: expected #{expected_txid}, got #{Modb.txid(committed)}"
        )
      )
    )
  end
  Ok((Db(store: committed, schema: db.schema, state: next_state), receipt))
end

## Physically rewrites the database file to evict pre-erasure dead CoW B+Tree pages from disk
## (preserving `_modb_audit` and `_modb_erasure_receipts`), and sets `receipt.compacted? = true`.
fn compact_after_erasure(
  files: Files,
  path: Text,
  sc: Schema,
  receipt_id: Text,
  now: Time
) : Result((Export.CompactReport, ErasureReceipt), ErasureError)
  crep = try Export.compact_db(files, path, sc, true, true, now).map_error(fn(e)
    ExportFailure(e)
  end)
  rec = try Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      st = Ledger.store(db)
      r_opt = try get_erasure_receipt(st, receipt_id)
      r = try r_opt.or_fail(ReceiptNotFound(id: receipt_id))
      var next_r = r
      next_r.compacted? = true
      tx0 = Modb.begin_write(st)
      tx1 = try wrap_table(Table.put(tx0, erasure_receipts_table(), receipt_id, next_r))
      _committed = try wrap_modb(Modb.commit(tx1))
      Ok(next_r)
    end
  )
  Ok((crep, rec))
end

## Lock-coordinated multi-worker wrappers.
fn provision_subject_key_locked(
  files: Files,
  path: Text,
  sc: Schema,
  srng: SecureRandom,
  subject_id: Text,
  meta: WriteMeta
) : Result(SubjectKeyRecord, ErasureError)
  dek = srng.bytes(32).to_base64url
  Ledger.locked(
    files,
    path,
    sc,
    meta.at,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, rec) = try provision_subject_key_raw(db, subject_id, dek, meta)
      Ok(rec)
    end
  )
end

fn shred_subject_key_locked(
  files: Files,
  path: Text,
  sc: Schema,
  subject_id: Text,
  reviewer: Text,
  is_admin: Bool,
  reason: Text,
  now: Time
) : Result(SubjectKeyRecord, ErasureError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, rec) = try shred_subject_key(db, subject_id, reviewer, is_admin, reason, now)
      Ok(rec)
    end
  )
end

fn register_subject_ref_locked(
  files: Files,
  path: Text,
  sc: Schema,
  subject_id: Text,
  bucket: Text,
  key_bytes: Bytes,
  doc_id_opt: Option(Text),
  meta: WriteMeta
) : Result(Unit, ErasureError)
  Ledger.locked(
    files,
    path,
    sc,
    meta.at,
    fn(e) LedgerFailure(e) end,
    fn(db)
      _next = try register_subject_ref(db, subject_id, bucket, key_bytes, doc_id_opt, meta)
      Ok(Unit)
    end
  )
end

fn erase_subject_locked(
  files: Files,
  path: Text,
  sc: Schema,
  req: ErasureRequest,
  reviewer: Text,
  is_admin: Bool,
  reason: Text,
  now: Time
) : Result(ErasureReceipt, ErasureError)
  Ledger.locked(
    files,
    path,
    sc,
    now,
    fn(e) LedgerFailure(e) end,
    fn(db)
      (_next, rec) = try erase_subject(db, req, reviewer, is_admin, reason, now)
      Ok(rec)
    end
  )
end

struct UserProfile
  id: Text
  email: Text
  secret_note_enc: Text
end

test "Modb.Erasure: crypto-shredding, live+FTS+Vec+Audit scrubbing, chain re-anchor & compaction"
  files = Files.in_memory({})
  srng = SecureRandom.seeded(77)
  t0 = Time.parse("2026-11-26T18:10:00Z") or stop "t0"
  sc = Ledger.schema(0).with_require_reason(false)
  tbl = Table.text_key[UserProfile]("profiles")
  fidx = Fts.index("prof")
  vidx = Vec.index("prof", 4)

  assert Ledger.open(files, "erase.modb", sc, t0) is Ok(db0)
  m_adm = WriteMeta(principal: "admin", action: "provision", reason: "gdpr setup", at: t0)
  assert provision_subject_key(db0, srng, "alice", m_adm) is Ok((db1, _))
  assert provision_subject_key(db1, srng, "bob", m_adm) is Ok((db2, _))

  assert seal_for_subject(Ledger.store(db2), srng, "alice", "note", "Alice secret SSN 123-45") is
    Ok(a_enc)
  assert seal_for_subject(Ledger.store(db2), srng, "bob", "note", "Bob private note 999") is
    Ok(b_enc)
  assert open_for_subject(Ledger.store(db2), "alice", "note", a_enc) == Ok("Alice secret SSN 123-45")

  m_alice = WriteMeta(
    principal: "user:alice",
    action: "profile_save",
    reason: "save alice@example.com profile",
    at: t0
  )
  assert Ledger.write(
    db2,
    m_alice,
    "save profile alice@example.com",
    Json.Object({"email": Json.String("alice@example.com")}),
    fn(tx)
      p = UserProfile(id: "alice", email: "alice@example.com", secret_note_enc: a_enc)
      t1 = try Table.put(tx, tbl, "alice", p)
      t2 = try tx_register_subject_ref(
        t1,
        "alice",
        "profiles",
        Table.encode_text_key("alice"),
        Some("alice")
      ).map_error(fn(e) Table.DecodeKey(reason: to_text(e)) end)
      t3 = try Fts.tx_index_document(
        t2,
        fidx,
        Fts.DocumentInput(
          doc_id: "alice",
          scope: "alice",
          fields: [Fts.FieldInput(name: "email", text: "alice@example.com", weight: 2)]
        )
      ).map_error(fn(e) Table.DecodeKey(reason: Fts.to_text(e)) end)
      Vec.tx_put_vector(
        t3,
        vidx,
        Vec.VectorInput(
          doc_id: "alice",
          scope: "alice",
          values: [1.0.to_float, 0.0.to_float, 0.0.to_float, 0.0.to_float]
        )
      ).map_error(fn(e) Table.DecodeKey(reason: Vec.to_text(e)) end)
    end
  ) is
    Ok(db3)

  assert Ledger.write(
    db3,
    WriteMeta(principal: "user:bob", action: "profile_save", reason: "save bob@example.com", at: t0),
    "save profile bob@example.com",
    Json.Object({"email": Json.String("bob@example.com")}),
    fn(tx)
      t1 = try Table.put(
        tx,
        tbl,
        "bob",
        UserProfile(id: "bob", email: "bob@example.com", secret_note_enc: b_enc)
      )
      Fts.tx_index_document(
        t1,
        fidx,
        Fts.DocumentInput(
          doc_id: "bob",
          scope: "bob",
          fields: [Fts.FieldInput(name: "email", text: "bob@example.com", weight: 2)]
        )
      ).map_error(fn(e) Table.DecodeKey(reason: Fts.to_text(e)) end)
    end
  ) is
    Ok(db4)

  var req = erasure_request("gdpr-alice-1", "alice")
  req.match_tokens = ["alice@example.com", "user:alice"]
  req.fts_indexes = [(fidx, "alice")]
  req.vec_indexes = [(vidx, "alice")]

  # Non-admin denied
  assert erase_subject(db4, req, "user:alice", false, "self erase", t0) is
    Error(ErasureDenied(reason: _))

  assert erase_subject(db4, req, "admin", true, "GDPR Art. 17 erasure", t0) is Ok((db5, rec)) and
    rec.key_shredded? and
    rec.rows_deleted == 1 and
    rec.fts_docs_deleted == 1 and
    rec.vec_docs_deleted == 1 and
    rec.audit_entries_redacted >= 1

  # Crypto-shredding immediately invalidates old ciphertext; Bob stays readable
  assert open_for_subject(Ledger.store(db5), "alice", "note", a_enc) is Error(KeyShredded(subject_id: "alice"))
  assert open_for_subject(Ledger.store(db5), "bob", "note", b_enc) == Ok("Bob private note 999")
  assert Table.get(Ledger.store(db5), tbl, "alice") == Ok(None)
  assert Table.get(Ledger.store(db5), tbl, "bob") is Ok(Some(_))
  assert Fts.search(Ledger.store(db5), fidx, "alice", Fts.default_search_options(10)) == Ok([])
  assert Ledger.verify_all(db5) is Ok(_)
  assert Ledger.verify_fast(db5, 16) is Ok(_)

  # Physical compaction evicts dead pre-erasure CoW pages completely!
  assert compact_after_erasure(files, "erase.modb", sc, "gdpr-alice-1", t0) is Ok((_crep, rec2)) and
    rec2.compacted?
  assert Ledger.open(files, "erase.modb", sc, t0) is Ok(db6)
  assert Ledger.verify_all(db6) is Ok(_) and Ledger.verify_fast(db6, 16) is Ok(_)
  assert Table.get(Ledger.store(db6), tbl, "bob") is Ok(Some(_))
  assert files.read_only.read_bytes("erase.modb") is Ok(raw_disk)
  assert raw_disk.to_hex.contains?("alice@example.com".bytes.to_hex) == false
end
