# Milestone 16 — Signed Hash-Chained Incremental Sync Replication & AES-256-GCM Off-Host Backup (`v0.8.0`)

## Goals

1. **Incremental CoW Replication Primitives (`Modb.Sync`):**
   - Persist registered sync peer cursors in `_modb_sync_peers` (`SyncPeer`), protected by a two-phase persistent root pin protocol:
     - `sync:<peer_id>`: last **acknowledged** base root (protects historical CoW pages against freelist reclamation across commits and restarts until the peer acknowledges receipt).
     - `sync_pending:<peer_id>`: exact `target_root` captured at `export_delta` time.
   - `export_delta` structurally diffs the peer's acknowledged root (or empty root `0` when `from_empty? == true` and `acked_seq == 0`) against the current committed `catalog_root` via `Modb.diff_roots`. It filters `_modb_pins`, `_modb_sync_peers`, and `_modb_*` (when `not include_internal?`), computes a canonical domain-separated SHA-256 `payload_hash` and chained `delta_hash`, atomically pins `sync_pending:<peer_id>`, and returns a `SyncDelta`.
   - Retrying `export_delta` before `ack_peer` is idempotent with respect to `acked_seq`/`acked_hash` and safely captures any newer concurrent writes into the updated pending pin.
   - `ack_peer` validates `(seq, delta_hash)` against the peer's pending cursor and atomically promotes `sync_pending:<peer_id>` -> `sync:<peer_id>` inside a single `WriteTx` (`tx_unpin_root` -> `tx_pin_existing_root` -> `tx_unpin_root`), preserving any concurrent writes made between `export_delta` and `ack_peer` for `seq + 1` while graduating older unpinned pages cleanly.

2. **Tamper-Evident Hash Chaining & Ledger Watermark Parity (`Modb.commit_at_least`):**
   - Every `SyncDelta` binds `(peer_id, seq, prev_hash, from_txid, target_txid, bucket_count, op_count, payload_hash)` into `delta_hash`.
   - `verify_delta` verifies format version, bucket/op counts, strict sorted canonical hex encoding, absence of `_modb_pins` / `_modb_sync_peers`, `payload_hash`, and `delta_hash`.
   - `apply_delta` / `apply_delta_tracked` enforces monotonic `seq` and exact `prev_hash` chaining (rejecting gaps, forks, and duplicate replays) and applies all puts/dels in a single atomic `WriteTx`.
   - `Modb.commit_at_least(tx, delta.target_txid)` advances the replica `txid` watermark (preserving strict alternating meta-page parity) so Ledger-backed `--include-internal` databases satisfy `entry.txid <= store_txid` and `cp.txid <= store_txid` under `Ledger.verify_all`.

3. **Authenticated AES-256-GCM Off-Host Envelopes & Full Chain Restore:**
   - `seal_delta` / `open_delta` and `seal_snapshot` / `open_snapshot` wrap JSON payloads in `SealedEnvelope` using Mo 0.3.0's OpenSSL-backed `Crypto.seal` / `Crypto.open`, fresh 12-byte `SecureRandom` nonces, strict 32-byte key length validation, and domain-separated AAD (`MODB-SEALED-V1|<fmt>|<kind>|<alg>|<key_id>|<aad>`). Plaintext digests (`payload_hash` / `delta_hash` / `sha256`) and key bytes are never exposed inside unencrypted envelope metadata.
   - `restore_chain` and `restore_sealed_chain` rebuild a verified MoDB file at `dst_path` (via temp staging + `Modb.verify` + atomic rename) from a base `PortableSnapshot` and an ordered delta chain (`1..N`).

4. **CLI, Workbench API/MCP (`v0.8.0`), and Host Integration:**
   - Add `modb sync` CLI commands (`init-peer`, `peers`, `base-snapshot`, `export`, `ack`, `apply`, `remove-peer`, `restore`) supporting `--key-file`, `--key-env`, `--encrypt`, `--decrypt`, `--key-id`, `--aad`, and `--from-empty`.
   - Add `/sync/peers*` routes and 5 MCP tools (`modb_sync_peers`, `modb_sync_init_peer`, `modb_sync_export`, `modb_sync_ack`, `modb_sync_remove_peer`) to `examples/agent-workbench.mo` (`serverInfo.version == "0.8.0"`).
