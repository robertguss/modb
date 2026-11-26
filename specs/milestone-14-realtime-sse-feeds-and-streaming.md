# Milestone 14 (`v0.6.0`): Real-Time SSE Push Change Feeds & Live Token-by-Token Streaming

Closes the reactive push-streaming loop across **MoDB** (`src/modb/feeds.mo`, `examples/agent-workbench.mo`, `examples/workbench-ui.mo`) and **Motet** (`llm.mo`, `server.mo`, `frontend/`), built directly on top of `mo`'s multi-worker chunked `SseBroker` ([#441](https://github.com/robertguss/mo/pull/441)) and outbound idle-timeout `SseRelay` ([#442](https://github.com/robertguss/mo/pull/442)), paired with native `Bytes.dot_u16_be_biased`/`dot_u8_biased` vector acceleration ([#443](https://github.com/robertguss/mo/pull/443)).

---

## 1. Pure-Mo Real-Time Feed Topics (`src/modb/feeds.mo`)

Without coupling `Modb.Feeds` to HTTP (`Api`), `feeds.mo` exposes deterministic pub/sub naming helpers:
- `feed_topic(feed_id)` -> `"feed:<feed_id>"`
- `bucket_topic(bucket)` -> `"bucket:<bucket>"`
- `feed_subscribe_topics(sub)` -> `["feeds", "feed:<sub.id>"]` + `"bucket:<b>"` for every subscribed bucket (or `"bucket:*"` when unfiltered)
- `commit_signal_json(txid, buckets, action)` -> structured JSON commit notification emitted alongside `Api.with_sse_publish_json`.

---

## 2. Live Multi-Worker `AgentWorkbench` SSE (`examples/agent-workbench.mo`, `examples/workbench-ui.mo`)

- `GET /events/stream`: Persistent cross-worker `Api.sse_stream_with` stream across `["workbench", "feeds", "governance", "taint", "bucket:*"]` with `Last-Event-ID` catchup and `retry: 2000`.
- `GET /feeds/:id/stream`: Persistent per-feed SSE stream subscribed to `Feeds.feed_subscribe_topics(sub)`, emitting an immediate sensitivity-filtered `event: feed.snapshot` followed by real-time `event: feed.delta` notifications whenever any worker commits mutations to matching buckets.
- All mutating HTTP handlers return standard JSON payloads decorated cleanly via `Api.with_sse_publish_json` (stripped by `mo serve` before leaving the server).
- `WorkbenchUi` replaces fixed polling with an auth-safe `fetch` + `ReadableStream` SSE subscriber (`LIVE SSE · tx N`) plus per-feed **Stream** controls.

---

## 3. Motet Real-Time SSE & Token-by-Token LLM Streaming (`motet/`)

- `Llm.build_stream_relay`: Multi-provider streaming relay builder (`Anthropic` -> `anthropic_sse`, `OpenAiCompat` -> `openai_sse`, `Gemini` -> `streamGenerateContent?alt=sse` `raw`) executed outside worker budgets via `Api.sse_relay_stream` without ever exposing API keys on the wire.
- `POST /v1/bots/:name/stream` & `POST /v1/sessions/:id/stream-commit`: Real-time token streaming into chat + durable commit to `motet.modb` + cross-worker `session:<id>` / `sessions` SSE broadcast.
- Upgraded `GET /v1/events/stream` (`["global", "inbox", "governance", "feeds", "sessions"]` + optional `session_id` / `feed_id`) and added `GET /v1/modb/feeds/:id/stream`.
- React Dashboard (`frontend/src/lib/sse.ts`, `App.tsx`, `ChatStudioView.tsx`, `AuditReplayView.tsx`): unified `Live` SSE control-plane sync, `Fast Stream` vs `Agent Tools` chat mode, and live `Stream Live` change-feed viewer.
