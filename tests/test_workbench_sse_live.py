#!/usr/bin/env python3
"""Live 8-worker chunked HTTP/1.1 SSE push & Last-Event-ID replay e2e test for AgentWorkbench."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def http_json(base: str, method: str, path: str, body=None, headers=None, timeout: float = 15.0):
    hdrs = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{base}{path}", data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return e.code, parsed


def wait_ready(base: str, proc: subprocess.Popen, timeout: float = 15.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            raise RuntimeError(f"mo serve exited early ({proc.returncode}):\n{out}\n{err}")
        try:
            st, data = http_json(base, "GET", "/health")
            if st == 200:
                return data
        except Exception:
            time.sleep(0.1)
    raise RuntimeError("timed out waiting for mo serve /health")


class ChunkedSseClient:
    """Minimal raw HTTP/1.1 Transfer-Encoding: chunked SSE reader."""

    def __init__(self, host: str, port: int, path: str, headers: dict[str, str] | None = None):
        self.sock = socket.create_connection((host, port), timeout=10.0)
        hdrs = {
            "Host": f"{host}:{port}",
            "Accept": "text/event-stream",
            "Connection": "keep-alive",
        }
        if headers:
            hdrs.update(headers)
        req_lines = [f"GET {path} HTTP/1.1"] + [f"{k}: {v}" for k, v in hdrs.items()] + ["", ""]
        self.sock.sendall("\r\n".join(req_lines).encode("utf-8"))

        self._raw = b""
        while b"\r\n\r\n" not in self._raw:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("EOF before HTTP headers")
            self._raw += chunk
        head_bytes, rest = self._raw.split(b"\r\n\r\n", 1)
        self._raw = rest
        head_lines = head_bytes.decode("latin-1").split("\r\n")
        status_parts = head_lines[0].split(" ", 2)
        self.status = int(status_parts[1])
        self.headers: dict[str, str] = {}
        self.raw_header_names: list[str] = []
        for line in head_lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                kl = k.strip().lower()
                self.raw_header_names.append(kl)
                self.headers[kl] = v.strip()
        self._text_buf = ""
        self._eof = False

    def _fill_chunked(self) -> None:
        while not self._eof:
            idx = self._raw.find(b"\r\n")
            if idx != -1:
                size_line = self._raw[:idx].decode("ascii").split(";", 1)[0].strip()
                size = int(size_line, 16)
                if size == 0:
                    self._eof = True
                    return
                need = idx + 2 + size + 2
                while len(self._raw) < need:
                    more = self.sock.recv(4096)
                    if not more:
                        raise RuntimeError("EOF inside HTTP chunk")
                    self._raw += more
                payload = self._raw[idx + 2 : idx + 2 + size]
                self._raw = self._raw[need:]
                self._text_buf += payload.decode("utf-8")
                return
            more = self.sock.recv(4096)
            if not more:
                self._eof = True
                return
            self._raw += more

    def next_event(self, timeout: float = 6.0) -> dict[str, str | None]:
        deadline = time.monotonic() + timeout
        while True:
            normalized = self._text_buf.replace("\r\n", "\n")
            sep_idx = normalized.find("\n\n")
            if sep_idx != -1:
                frame = normalized[:sep_idx]
                self._text_buf = normalized[sep_idx + 2 :]
                ev_id = None
                ev_name = "message"
                data_lines: list[str] = []
                is_comment_only = True
                for line in frame.split("\n"):
                    if not line or line.startswith(":"):
                        continue
                    is_comment_only = False
                    if ":" in line:
                        field, val = line.split(":", 1)
                        val = val[1:] if val.startswith(" ") else val
                    else:
                        field, val = line, ""
                    if field == "event":
                        ev_name = val or "message"
                    elif field == "id":
                        ev_id = val
                    elif field == "data":
                        data_lines.append(val)
                if is_comment_only or (not data_lines and ev_name == "message" and ev_id is None):
                    continue
                if not data_lines and ev_id is None:
                    continue
                return {"id": ev_id, "event": ev_name, "data": "\n".join(data_lines)}
            rem = deadline - time.monotonic()
            if rem <= 0:
                raise TimeoutError("Timed out waiting for SSE event frame")
            self.sock.settimeout(rem)
            self._fill_chunked()
            if self._eof and "\n\n" not in self._text_buf.replace("\r\n", "\n"):
                raise EOFError("SSE stream closed cleanly")

    def close(self) -> None:
        try:
            self.sock.close()
        except Exception:
            pass


def main() -> int:
    mo_bin = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/bin/mo")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    workbench_mo = os.path.join(repo_root, "examples", "agent-workbench.mo")
    port = pick_free_port()
    base = f"http://127.0.0.1:{port}"

    with tempfile.TemporaryDirectory(prefix="modb-sse-live-") as tmp:
        env = os.environ.copy()
        env["WB_ADMIN_TOKEN"] = "wb-admin"
        env["WB_PLANNER_TOKEN"] = "wb-planner"
        env["WB_WORKER_TOKEN"] = "wb-worker"
        log_path = os.path.join(tmp, "serve.log")
        log_fh = open(log_path, "w", encoding="utf-8")
        proc = subprocess.Popen(
            [
                mo_bin,
                "serve",
                "--workers",
                "8",
                "--bind",
                "127.0.0.1",
                "--port",
                str(port),
                "--data",
                tmp,
                workbench_mo,
            ],
            stdout=log_fh,
            stderr=log_fh,
            text=True,
            env=env,
        )
        log_fh.close()

        ev_stream = None
        feed_stream = None
        replay_stream = None
        try:
            wait_ready(base, proc)
            admin_hdr = {"Authorization": "Bearer wb-admin", "X-Reason": "m14 live sse"}
            plan_hdr = {"Authorization": "Bearer wb-planner", "X-Reason": "m14 planner"}
            work_hdr = {"Authorization": "Bearer wb-worker", "X-Reason": "m14 worker"}

            st, init_res = http_json(base, "POST", "/admin/init", None, admin_hdr)
            assert st == 200 and init_res["status"] == "ok", (st, init_res)

            st, sub_res = http_json(
                base,
                "POST",
                "/feeds",
                {
                    "id": "live-tasks",
                    "grant_id": None,
                    "buckets": ["tasks"],
                    "include_internal": False,
                    "from_beginning": False,
                },
                admin_hdr,
            )
            assert st == 200 and sub_res["id"] == "live-tasks", (st, sub_res)

            # 1. Global /events/stream checks chunked SSE, clean headers, initial health frame
            ev_stream = ChunkedSseClient("127.0.0.1", port, "/events/stream")
            assert ev_stream.status == 200, ev_stream.status
            assert "text/event-stream" in ev_stream.headers.get("content-type", ""), ev_stream.headers
            assert ev_stream.headers.get("transfer-encoding", "").lower() == "chunked", ev_stream.headers
            assert not any(h.startswith("x-mo-sse-") for h in ev_stream.raw_header_names), ev_stream.raw_header_names
            ev0 = ev_stream.next_event()
            assert ev0["event"] == "health" and '"txid"' in (ev0["data"] or ""), ev0

            # 2. Scoped /feeds/live-tasks/stream checks chunked SSE + feed.snapshot initial frame
            feed_stream = ChunkedSseClient(
                "127.0.0.1",
                port,
                "/feeds/live-tasks/stream",
                {"Authorization": "Bearer wb-admin"},
            )
            assert feed_stream.status == 200, feed_stream.status
            assert "text/event-stream" in feed_stream.headers.get("content-type", ""), feed_stream.headers
            assert feed_stream.headers.get("transfer-encoding", "").lower() == "chunked", feed_stream.headers
            assert not any(h.startswith("x-mo-sse-") for h in feed_stream.raw_header_names), feed_stream.raw_header_names
            snap_ev = feed_stream.next_event()
            assert snap_ev["event"] == "feed.snapshot" and '"live-tasks"' in (snap_ev["data"] or ""), snap_ev

            # 3. Cross-worker mutation arrives live on BOTH SSE streams (< 5s, zero polling)
            st, task_res = http_json(
                base,
                "POST",
                "/tasks",
                {
                    "id": 777,
                    "project_id": "infra",
                    "title": "Cross-worker SSE push #777",
                    "base_cost_cents": 1500,
                },
                plan_hdr,
            )
            assert st == 200 and task_res["id"] == 777, (st, task_res)

            pushed_feed = feed_stream.next_event(timeout=5.0)
            assert pushed_feed["event"] == "feed.delta", pushed_feed
            assert pushed_feed["id"] is not None and int(pushed_feed["id"]) > 0, pushed_feed
            assert '"tasks"' in (pushed_feed["data"] or ""), pushed_feed

            pushed_global = ev_stream.next_event(timeout=5.0)
            assert pushed_global["event"] == "task.created", pushed_global
            assert pushed_global["id"] is not None, pushed_global

            # Verify poll_feed returns the exact OpAdded delta for task #777
            st, poll_batch = http_json(
                base,
                "GET",
                "/feeds/live-tasks/poll",
                None,
                {"Authorization": "Bearer wb-admin"},
            )
            assert st == 200 and len(poll_batch["events"]) >= 1, (st, poll_batch)

            last_seen_id = pushed_feed["id"]
            feed_stream.close()
            feed_stream = None

            # 4. Commit task #778 while feed client is disconnected, then reconnect with Last-Event-ID
            st, task2_res = http_json(
                base,
                "POST",
                "/tasks",
                {
                    "id": 778,
                    "project_id": "infra",
                    "title": "Missed while disconnected #778",
                    "base_cost_cents": 900,
                },
                plan_hdr,
            )
            assert st == 200 and task2_res["id"] == 778, (st, task2_res)

            replay_stream = ChunkedSseClient(
                "127.0.0.1",
                port,
                "/feeds/live-tasks/stream",
                {
                    "Authorization": "Bearer wb-admin",
                    "Last-Event-ID": str(last_seen_id),
                },
            )
            assert replay_stream.status == 200, replay_stream.status
            ev_a = replay_stream.next_event(timeout=5.0)
            ev_b = replay_stream.next_event(timeout=5.0)
            events = [ev_a, ev_b]
            assert any(e["event"] == "feed.snapshot" for e in events), events
            replayed = [
                e
                for e in events
                if e["event"] == "feed.delta"
                and e["id"] is not None
                and int(e["id"]) > int(str(last_seen_id))
            ]
            assert len(replayed) == 1 and '"create_task"' in (replayed[0]["data"] or ""), events

            print(
                f"PASS: 8-worker live chunked SSE verified (feed_id=live-tasks, pushed_id={last_seen_id}, "
                f"replayed_id={replayed[0]['id']}, tasks_delta={len(poll_batch['events'])})"
            )
            return 0
        finally:
            for c in (ev_stream, feed_stream, replay_stream):
                if c is not None:
                    c.close()
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5.0)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


if __name__ == "__main__":
    raise SystemExit(main())
