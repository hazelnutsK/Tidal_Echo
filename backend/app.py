#!/usr/bin/env python3
"""
companion relay backend — a private 1:1 message channel between a person and
their AI companion (an AI running locally as a Claude Code "channel" plugin).

Two ends, one shared secret:
  - AI side   (local CC channel plugin):  POST /channel/out  ·  SSE GET /channel/in
  - Human side (phone PWA):               POST /app/send     ·  SSE GET /app/stream  ·  GET /app/history

No framework magic: messages land in sqlite and fan out to SSE subscribers via
one asyncio.Queue per connection. A single shared Bearer secret guards every
endpoint (single user). The secret may travel in the Authorization header *or*
as a ?token= query param — because the browser's native EventSource cannot set
custom headers.

Everything personal — names, secrets, domain, paths — comes from environment
variables (see .env.example). Nothing identifying is hard-coded.
"""

import asyncio
import mimetypes
import hmac
import json
import os
import re
import secrets
import subprocess
import sqlite3
import sys
import urllib.error
import urllib.request
import urllib.parse
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import FileResponse, Response, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware

try:
    from pywebpush import webpush, WebPushException
except Exception:  # a missing lib must not stop the relay from starting
    webpush = None
    class WebPushException(Exception):
        pass


# --- identity (parameterized — set these to your own names) ----------------
AI_NAME = os.environ.get("RELAY_AI_NAME", "AI")          # AI companion's display name (push title, narration)
HUMAN_NAME = os.environ.get("RELAY_HUMAN_NAME", "对方")   # how the AI is told about you in voice/call narration

# --- core config / secrets (all from env) ----------------------------------
SECRET = os.environ.get("RELAY_SECRET", "")
DB_PATH = os.environ.get("RELAY_DB", str(Path(__file__).parent / "relay.db"))
PORT = int(os.environ.get("RELAY_PORT", "3011"))
UPLOAD_DIR = Path(os.environ.get("RELAY_UPLOAD_DIR", str(Path(__file__).parent / "uploads")))
PUBLIC_PREFIX = os.environ.get("RELAY_PUBLIC_PREFIX", "/relay").rstrip("/")
APP_PATH = os.environ.get("RELAY_APP_PATH", "/")  # where a push-notification tap opens the PWA
ALLOW_ORIGINS = [o.strip() for o in os.environ.get(
    "RELAY_ALLOW_ORIGINS", "http://localhost:8080,http://127.0.0.1:8080"
).split(",") if o.strip()]
MAX_UPLOAD_BYTES = int(os.environ.get("RELAY_MAX_UPLOAD_BYTES", str(10 * 1024 * 1024)))
VOICE_MAX_BYTES = int(os.environ.get("RELAY_VOICE_MAX_BYTES", str(8 * 1024 * 1024)))
VOICE_TRANSCRIBE_CMD = os.environ.get("RELAY_VOICE_TRANSCRIBE_CMD", "")

# --- MiniMax TTS (optional — leave keys blank to disable spoken replies) ----
MINIMAX_API_BASE = os.environ.get("MINIMAX_API_BASE", "https://api.minimaxi.com")
MINIMAX_API_KEY = os.environ.get("MINIMAX_API_KEY", "")
MINIMAX_GROUP_ID = os.environ.get("MINIMAX_GROUP_ID", "")
MINIMAX_MODEL = os.environ.get("MINIMAX_MODEL", "speech-02-hd")
MINIMAX_VOICE_ZH = os.environ.get("MINIMAX_VOICE_ZH", "")
MINIMAX_TTS_TIMEOUT = float(os.environ.get("MINIMAX_TTS_TIMEOUT", "30"))

# --- Web Push (VAPID, optional) — push unread replies to the PWA lock screen
VAPID_PUBLIC_KEY = os.environ.get("VAPID_PUBLIC_KEY", "")
VAPID_PRIVATE_PEM = os.environ.get("VAPID_PRIVATE_PEM", "")   # PEM file path OR inline PEM text
VAPID_SUBJECT = os.environ.get("VAPID_SUBJECT", "mailto:admin@example.com")
PUSH_PREVIEW_CHARS = int(os.environ.get("RELAY_PUSH_PREVIEW_CHARS", "120"))

# --- presence tuning (seconds) ---------------------------------------------
PRESENCE_ONLINE_SEC = int(os.environ.get("RELAY_PRESENCE_ONLINE_SEC", "180"))
PRESENCE_RECENT_SEC = int(os.environ.get("RELAY_PRESENCE_RECENT_SEC", "1800"))

# --- Optional server-side API loop -----------------------------------------
# "desktop" keeps the original Claude Code channel path. "loop" forwards new
# human messages to a local HTTP loop, which replies through /channel/out.
BRAIN_FILE = Path(os.environ.get("RELAY_BRAIN_FILE", str(Path(__file__).parent / "brain_target")))
LOOP_INGEST_URL = os.environ.get("RELAY_LOOP_INGEST_URL", "http://127.0.0.1:3020/loop/ingest")
STREAM_DRAFT_TTL = int(os.environ.get("RELAY_STREAM_DRAFT_TTL", "600"))

if not SECRET:
    raise SystemExit("RELAY_SECRET is required (set it in the systemd EnvironmentFile)")


# ---------------------------------------------------------------------------
# storage
# ---------------------------------------------------------------------------

def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    with db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS messages (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                ts        TEXT NOT NULL,
                direction TEXT NOT NULL,   -- 'in' (human -> AI) | 'out' (AI -> human)
                kind      TEXT NOT NULL,   -- 'user' | 'reply' | 'thinking' | 'voice' | 'call' | ...
                text      TEXT NOT NULL,
                meta      TEXT NOT NULL DEFAULT '{}'
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS push_subscriptions (
                endpoint TEXT PRIMARY KEY,
                p256dh   TEXT NOT NULL,
                auth     TEXT NOT NULL,
                ua       TEXT,
                created  TEXT NOT NULL,
                last_ok  TEXT
            )
            """
        )
        conn.commit()


def save_message(direction: str, kind: str, text: str, meta: dict) -> dict:
    ts = meta.get("ts") or now_iso()
    with db() as conn:
        cur = conn.execute(
            "INSERT INTO messages (ts, direction, kind, text, meta) VALUES (?,?,?,?,?)",
            (ts, direction, kind, text, json.dumps(meta, ensure_ascii=False)),
        )
        conn.commit()
        mid = cur.lastrowid
    return {"id": mid, "ts": ts, "direction": direction, "kind": kind, "text": text, "meta": meta}


def set_reaction(message_id, who, emoji):
    # Set/clear one party's reaction on an existing message.
    # Returns the message's reactions dict, or None if the target doesn't exist.
    with db() as conn:
        row = conn.execute("SELECT meta FROM messages WHERE id = ?", (message_id,)).fetchone()
        if not row:
            return None
        meta = json.loads(row["meta"] or "{}")
        reactions = meta.get("reactions") or {}
        if emoji:
            reactions[who] = emoji
        else:
            reactions.pop(who, None)
        if reactions:
            meta["reactions"] = reactions
        else:
            meta.pop("reactions", None)
        conn.execute(
            "UPDATE messages SET meta = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), message_id),
        )
        conn.commit()
    return reactions


def history(since: int, limit: int) -> list:
    # hidden = relay-internal frames (forge handoff etc.) — the AI sees them via
    # /channel/in, the phone must not render them.
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM messages WHERE id > ? AND json_extract(meta, '$.hidden') IS NULL "
            "ORDER BY id ASC LIMIT ?",
            (since, limit),
        ).fetchall()
    return rows_to_messages(rows)


def history_for_session(session_id: str, since: int, limit: int) -> list:
    session_id = (session_id or "").strip()
    if not session_id:
        return history(since, limit)
    with db() as conn:
        if session_id == "__legacy__":
            rows = conn.execute(
                "SELECT * FROM messages "
                "WHERE id > ? AND (json_extract(meta, '$.api_session') IS NULL OR json_extract(meta, '$.api_session') = '') "
                "AND json_extract(meta, '$.hidden') IS NULL "
                "ORDER BY id ASC LIMIT ?",
                (since, limit),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM messages "
                "WHERE id > ? AND json_extract(meta, '$.api_session') = ? "
                "ORDER BY id ASC LIMIT ?",
                (since, session_id, limit),
            ).fetchall()
    return rows_to_messages(rows)


def inbound_history(since: int, limit: int) -> list:
    # meta.routed='loop' = already answered by the API body while the plugin was
    # not listening; excluded here so a reconnecting CC doesn't re-answer them.
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM messages WHERE id > ? AND direction = 'in' "
            "AND (json_extract(meta, '$.routed') IS NULL OR json_extract(meta, '$.routed') != 'loop') "
            "ORDER BY id ASC LIMIT ?",
            (since, limit),
        ).fetchall()
    return rows_to_messages(rows)


def rows_to_messages(rows) -> list:
    return [
        {
            "id": r["id"], "ts": r["ts"], "direction": r["direction"],
            "kind": r["kind"], "text": r["text"], "meta": json.loads(r["meta"] or "{}"),
        }
        for r in rows
    ]


# ---------------------------------------------------------------------------
# web push — subscription storage + send
# ---------------------------------------------------------------------------

def save_subscription(endpoint: str, p256dh: str, auth: str, ua: str = "") -> None:
    with db() as conn:
        conn.execute(
            """
            INSERT INTO push_subscriptions (endpoint, p256dh, auth, ua, created, last_ok)
            VALUES (?,?,?,?,?,?)
            ON CONFLICT(endpoint) DO UPDATE SET p256dh=excluded.p256dh, auth=excluded.auth, ua=excluded.ua
            """,
            (endpoint, p256dh, auth, ua, now_iso(), None),
        )
        conn.commit()


def delete_subscription(endpoint: str) -> None:
    with db() as conn:
        conn.execute("DELETE FROM push_subscriptions WHERE endpoint = ?", (endpoint,))
        conn.commit()


def list_subscriptions() -> list:
    with db() as conn:
        rows = conn.execute("SELECT endpoint, p256dh, auth FROM push_subscriptions").fetchall()
    return [{"endpoint": r["endpoint"], "keys": {"p256dh": r["p256dh"], "auth": r["auth"]}} for r in rows]


def mark_subscription_ok(endpoint: str) -> None:
    with db() as conn:
        conn.execute("UPDATE push_subscriptions SET last_ok = ? WHERE endpoint = ?", (now_iso(), endpoint))
        conn.commit()


def _send_one_push(sub: dict, data: str):
    """Blocking single send (run in a thread). Returns (endpoint, status): 0=ok, 404/410=dead, else=transient."""
    if webpush is None:
        return sub["endpoint"], -1
    try:
        webpush(
            subscription_info=sub,
            data=data,
            vapid_private_key=VAPID_PRIVATE_PEM,
            vapid_claims={"sub": VAPID_SUBJECT},
            timeout=10,
        )
        return sub["endpoint"], 0
    except WebPushException as exc:
        code = getattr(getattr(exc, "response", None), "status_code", 0) or 0
        return sub["endpoint"], code
    except Exception:
        return sub["endpoint"], -1


async def push_to_all(payload: dict) -> dict:
    """Best-effort fan-out to all subscriptions; never raises. 404/410 prunes dead subs."""
    if webpush is None or not VAPID_PUBLIC_KEY or not VAPID_PRIVATE_PEM:
        return {"sent": 0, "dead": 0, "skipped": "not_configured"}
    subs = list_subscriptions()
    if not subs:
        return {"sent": 0, "dead": 0}
    data = json.dumps(payload, ensure_ascii=False)
    results = await asyncio.gather(*[asyncio.to_thread(_send_one_push, s, data) for s in subs])
    sent = dead = 0
    for endpoint, status in results:
        if status == 0:
            sent += 1
            mark_subscription_ok(endpoint)
        elif status in (404, 410):
            delete_subscription(endpoint)
            dead += 1
    return {"sent": sent, "dead": dead}


_PUSH_TAG_RE = re.compile(r"<[^>]+>")


def notification_from_message(msg: dict) -> dict:
    raw = (msg.get("text") or "").strip()
    body = _PUSH_TAG_RE.sub("", raw)
    body = re.sub(r"\s+", " ", body).strip()
    if len(body) > PUSH_PREVIEW_CHARS:
        body = body[:PUSH_PREVIEW_CHARS].rstrip() + "…"
    if not body:
        body = f"{AI_NAME}给你发来一条消息"
    return {"title": AI_NAME, "body": body, "url": APP_PATH, "id": msg.get("id"), "ts": msg.get("ts")}


# ---------------------------------------------------------------------------
# pub/sub — one asyncio.Queue per connected SSE client
# ---------------------------------------------------------------------------

plugin_subs: set[asyncio.Queue] = set()  # AI side    (GET /channel/in)
app_subs: set[asyncio.Queue] = set()     # human side (GET /app/stream)
stream_drafts: dict[tuple[str, str], dict] = {}


async def broadcast(subs: set, payload: dict) -> None:
    for q in list(subs):
        try:
            q.put_nowait(payload)
        except asyncio.QueueFull:
            subs.discard(q)  # slow/dead consumer — drop it


def app_payload(msg: dict) -> dict:
    """Shape the PWA renders: from = 'human' | 'ai', plus kind for styling."""
    return {
        "id": msg["id"], "ts": msg["ts"],
        "from": "human" if msg["direction"] == "in" else "ai",
        "kind": msg["kind"], "text": msg["text"], "meta": msg["meta"],
    }


def plugin_payload(msg: dict) -> dict:
    meta = msg.get("meta") or {}
    return {
        "id": msg["id"],
        "content": msg["text"],
        "user": meta.get("user") or "human",
        "ts": msg["ts"],
        "attachments": meta.get("attachments") or [],
    }


def brain_target() -> str:
    try:
        target = BRAIN_FILE.read_text(encoding="utf-8").strip()
        return target if target in ("desktop", "loop") else "desktop"
    except FileNotFoundError:
        return "desktop"
    except Exception:
        return "desktop"


def _forward_to_loop_sync(msg: dict) -> None:
    meta = msg.get("meta") or {}
    data = json.dumps({
        "id": msg.get("id"),
        "text": msg.get("text", ""),
        "session_id": meta.get("api_session") or "",
    }, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        LOOP_INGEST_URL,
        data=data,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=10).read()


def _clear_loop_mark(msg_id) -> None:
    """转发 api_loop 失败时摘掉 routed 标——让 CC 重连回填时兜底接住这条。"""
    with db() as conn:
        row = conn.execute("SELECT meta FROM messages WHERE id = ?", (msg_id,)).fetchone()
        if not row:
            return
        try:
            meta = json.loads(row["meta"] or "{}")
        except json.JSONDecodeError:
            meta = {}
        meta.pop("routed", None)
        conn.execute("UPDATE messages SET meta = ? WHERE id = ?",
                     (json.dumps(meta, ensure_ascii=False), msg_id))
        conn.commit()


async def forward_to_loop(msg: dict) -> None:
    try:
        await asyncio.to_thread(_forward_to_loop_sync, msg)
    except Exception as exc:
        print(f"[loop] forward failed: {type(exc).__name__}: {exc}")
        try:
            await asyncio.to_thread(_clear_loop_mark, msg.get("id"))
        except Exception:
            pass


async def route_inbound(msg: dict) -> None:
    """Send one inbound message to exactly one AI body (the brain target)."""
    if brain_target() == "loop":
        asyncio.create_task(forward_to_loop(msg))
    else:
        await broadcast(plugin_subs, plugin_payload(msg))


def prune_stream_drafts() -> None:
    now = datetime.now(timezone.utc).timestamp()
    stale = [k for k, v in stream_drafts.items() if now - float(v.get("updated_at") or 0) > STREAM_DRAFT_TTL]
    for k in stale:
        stream_drafts.pop(k, None)


async def handle_stream_delta(kind: str, body: dict) -> dict:
    base_kind = kind[:-6] if kind.endswith("_delta") else kind
    if base_kind not in ("thinking", "reply"):
        raise HTTPException(status_code=400, detail="unknown stream kind")
    stream_id = str(body.get("stream_id") or "").strip()
    if not stream_id:
        raise HTTPException(status_code=400, detail="stream_id required")

    done = bool(body.get("done"))
    chunk = str(body.get("text") or "")
    meta = {k: v for k, v in body.items() if k not in ("type", "text", "done", "final_text")}
    meta["stream_id"] = stream_id
    key = (stream_id, base_kind)
    prune_stream_drafts()

    now_ts = datetime.now(timezone.utc).timestamp()
    draft = stream_drafts.get(key)
    if not draft:
        draft = {"text": "", "meta": meta, "ts": now_iso(), "updated_at": now_ts}
        stream_drafts[key] = draft
    draft["text"] += chunk
    if done and isinstance(body.get("final_text"), str):
        draft["text"] = body.get("final_text") or ""
    draft["meta"].update(meta)
    draft["updated_at"] = now_ts

    if not done:
        await broadcast(app_subs, {
            "type": kind,
            "stream_id": stream_id,
            "text": chunk,
            "done": False,
            "ts": draft["ts"],
            "api_session": draft["meta"].get("api_session") or "",
        })
        return {"ok": True, "stream_id": stream_id, "draft": True}

    text = draft.get("text") or ""
    stream_drafts.pop(key, None)
    if not text:
        return {"ok": True, "stream_id": stream_id, "saved": False}
    msg = save_message("out", base_kind, text, dict(draft.get("meta") or {}))
    await broadcast(app_subs, {"type": "typing", "active": False})
    await broadcast(app_subs, app_payload(msg))
    if base_kind == "reply" and not app_subs:
        try:
            await push_to_all(notification_from_message(msg))
        except Exception:
            pass
    return {"id": msg["id"], "stream_id": stream_id, "saved": True}


def loop_base_url() -> str:
    parsed = urllib.parse.urlparse(LOOP_INGEST_URL)
    if not parsed.scheme or not parsed.netloc:
        return "http://127.0.0.1:3020"
    return f"{parsed.scheme}://{parsed.netloc}"


def loop_json(path: str, method: str = "GET", body=None):
    data = None
    headers = {"Content-Type": "application/json"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(loop_base_url() + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=35) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        raise HTTPException(status_code=exc.code, detail=detail)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"loop proxy error: {exc}")


SAFE_NAME_RE = re.compile(r"[^A-Za-z0-9_.-]+")


def clean_filename(name: str) -> str:
    name = Path(name or "file").name
    name = SAFE_NAME_RE.sub("_", name).strip("._") or "file"
    return name[:80]


def ext_for(name: str, mime: str) -> str:
    ext = Path(name).suffix.lower()
    if ext and re.fullmatch(r"\.[A-Za-z0-9]{1,8}", ext):
        return ext
    guessed = mimetypes.guess_extension((mime or "").split(";", 1)[0].strip())
    return guessed or ".bin"


def save_upload_bytes(data: bytes, name: str, mime: str, prefix: str = "att") -> dict:
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    safe = clean_filename(name)
    ext = ext_for(safe, mime)
    stored = f"{prefix}-{secrets.token_urlsafe(10)}{ext}"
    path = UPLOAD_DIR / stored
    path.write_bytes(data)
    kind = "image" if (mime or "").startswith("image/") else ("audio" if (mime or "").startswith("audio/") else "file")
    return {
        "url": f"{PUBLIC_PREFIX}/uploads/{stored}" if PUBLIC_PREFIX else f"/uploads/{stored}",
        "name": safe,
        "size": len(data),
        "mime": mime or "application/octet-stream",
        "kind": kind,
    }


def transcribe_with_command(audio_path: Path, mime: str) -> str:
    """Optional local ASR hook. The command receives <audio_path> <mime> and prints a transcript."""
    if not VOICE_TRANSCRIBE_CMD:
        return ""
    try:
        proc = subprocess.run(
            [VOICE_TRANSCRIBE_CMD, str(audio_path), mime or "application/octet-stream"],
            text=True,
            capture_output=True,
            timeout=45,
            check=False,
        )
    except Exception:
        return ""
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def minimax_tts_mp3(text: str) -> bytes:
    if not MINIMAX_API_KEY or not MINIMAX_VOICE_ZH:
        raise HTTPException(status_code=503, detail="minimax tts not configured")
    clean = (text or "").strip()
    if not clean:
        raise HTTPException(status_code=400, detail="empty text")
    clean = clean[:900]
    url = f"{MINIMAX_API_BASE.rstrip('/')}/v1/t2a_v2"
    if MINIMAX_GROUP_ID:
        url += f"?GroupId={MINIMAX_GROUP_ID}"
    payload = {
        "model": MINIMAX_MODEL,
        "text": clean,
        "stream": False,
        "voice_setting": {
            "voice_id": MINIMAX_VOICE_ZH,
            "speed": 1.0,
            "vol": 1.0,
            "pitch": 0,
        },
        "audio_setting": {
            "sample_rate": 32000,
            "bitrate": 128000,
            "format": "mp3",
            "channel": 1,
        },
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {MINIMAX_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=MINIMAX_TTS_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"minimax tts failed: {exc}")
    audio_hex = (data.get("data") or {}).get("audio")
    if not audio_hex:
        raise HTTPException(status_code=502, detail="minimax tts returned no audio")
    try:
        return bytes.fromhex(audio_hex)
    except ValueError:
        raise HTTPException(status_code=502, detail="bad minimax audio payload")


def sse_data(payload: dict) -> str:
    lines: list[str] = []
    event_id = payload.get("id")
    if event_id is not None:
        lines.append(f"id: {event_id}")
    lines.append(f"data: {json.dumps(payload, ensure_ascii=False)}")
    return "\n".join(lines) + "\n\n"


def sse_ping() -> str:
    payload = {"type": "ping", "ts": datetime.now(timezone.utc).isoformat()}
    return "event: ping\n" + sse_data(payload)


async def sse_stream(subs: set, request: Request, initial: list[dict] | None = None):
    q: asyncio.Queue = asyncio.Queue(maxsize=1000)
    subs.add(q)
    try:
        yield "retry: 3000\n: connected\n\n"
        for payload in initial or []:
            yield sse_data(payload)
        while True:
            if await request.is_disconnected():
                break
            try:
                payload = await asyncio.wait_for(q.get(), timeout=15)
                yield sse_data(payload)
            except asyncio.TimeoutError:
                yield sse_ping()  # keep the connection alive and let clients watchdog it
    finally:
        subs.discard(q)


SSE_HEADERS = {
    "Cache-Control": "no-cache, no-transform",
    "X-Accel-Buffering": "no",  # tell nginx not to buffer the stream
    "Connection": "keep-alive",
}


# ---------------------------------------------------------------------------
# auth — one shared Bearer secret on every endpoint (single user)
# ---------------------------------------------------------------------------

def check_auth(request: Request) -> None:
    auth = request.headers.get("authorization", "")
    token = auth[7:] if auth.startswith("Bearer ") else request.query_params.get("token")
    if not token or not hmac.compare_digest(token, SECRET):
        raise HTTPException(status_code=401, detail="unauthorized")


# ---------------------------------------------------------------------------
# app
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    # auto-forge watcher (defined near the context-control endpoints below).
    # NOTE: this lifespan runs on the OUTER root app — mounted sub-apps don't
    # execute their own lifespans.
    watcher = asyncio.create_task(_context_watcher())
    yield
    watcher.cancel()


app = FastAPI(lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOW_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/healthz")
async def healthz():
    return {"ok": True, "plugin_subs": len(plugin_subs), "app_subs": len(app_subs)}


# ---- AI side ---------------------------------------------------------------

@app.get("/channel/in")
async def channel_in(request: Request, since: int = 0, limit: int = 100):
    """SSE stream the plugin holds open. The human's messages get pushed down here."""
    check_auth(request)
    backlog = [plugin_payload(m) for m in inbound_history(since, min(limit, 500))]
    return StreamingResponse(sse_stream(plugin_subs, request, backlog), media_type="text/event-stream", headers=SSE_HEADERS)


@app.post("/channel/out")
async def channel_out(request: Request):
    """The AI's reply/react. Persist + fan out to the PWA."""
    check_auth(request)
    body = await request.json()
    kind = body.get("type", "reply")
    if kind in ("thinking_delta", "reply_delta"):
        return await handle_stream_delta(kind, body)
    if kind == "react":
        # An emoji reaction attached to an existing message's meta.reactions; no new
        # message is created. An empty emoji clears that reaction.
        try:
            target_id = int(body.get("id"))
        except (TypeError, ValueError):
            raise HTTPException(status_code=400, detail="react: numeric id required")
        emoji = (body.get("emoji") or "").strip()
        reactions = set_reaction(target_id, "ai", emoji)
        if reactions is None:
            raise HTTPException(status_code=404, detail="react: message not found")
        await broadcast(app_subs, {"type": "reaction", "id": target_id, "reactions": reactions, "by": "ai"})
        # A react is also the AI "acting" once — clear the typing indicator so the
        # header doesn't stay stuck typing when no reply follows.
        await broadcast(app_subs, {"type": "typing", "active": False})
        return {"id": target_id, "reactions": reactions}
    text = body.get("text", "")
    meta = {k: v for k, v in body.items() if k not in ("type", "text")}
    msg = save_message("out", kind, text, meta)
    # the AI replied — clear the typing state
    await broadcast(app_subs, {"type": "typing", "active": False})
    await broadcast(app_subs, app_payload(msg))
    # Unread push: only when no PWA tab is holding the stream (app_subs empty);
    # only push real replies, not 'thinking' chatter.
    if kind == "reply" and not app_subs:
        try:
            await push_to_all(notification_from_message(msg))
        except Exception:
            pass  # a push failure must never affect persistence/fan-out
    return {"id": msg["id"]}


# ---- human side ------------------------------------------------------------

@app.post("/app/send")
async def app_send(request: Request):
    """Human types in the PWA. Persist, push to the AI (plugin), echo to other PWA tabs."""
    check_auth(request)
    body = await request.json()
    text = (body.get("text") or "").strip()
    attachments = body.get("attachments") if isinstance(body.get("attachments"), list) else []
    api_session = str(body.get("api_session") or body.get("session_id") or "").strip()
    if not text and not attachments:
        raise HTTPException(status_code=400, detail="empty text")
    meta = {"user": "human", "attachments": attachments}
    if api_session:
        meta["api_session"] = api_session
    # loop 路由的消息打标：CC 插件回填时跳过（API 已回过，别让 CC 再回一遍）
    if brain_target() == "loop":
        meta["routed"] = "loop"
    msg = save_message("in", "user", text, meta)
    await route_inbound(msg)
    # echo to the PWA so the sender's bubble + other tabs stay in sync
    await broadcast(app_subs, app_payload(msg))
    # the AI starts processing — push a typing state to the PWA
    await broadcast(app_subs, {"type": "typing", "active": True})
    return {"id": msg["id"]}


@app.post("/app/upload")
async def app_upload(request: Request, name: str = "file"):
    check_auth(request)
    data = await request.body()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    mime = request.headers.get("content-type", "application/octet-stream")
    return save_upload_bytes(data, name, mime, "att")


@app.get("/uploads/{name}")
async def uploads(request: Request, name: str):
    check_auth(request)
    safe = clean_filename(name)
    path = UPLOAD_DIR / safe
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path)


@app.post("/app/voice")
async def app_voice(request: Request):
    """Voice input from the PWA. Prefer the browser transcript; fall back to an audio attachment."""
    check_auth(request)
    ctype = request.headers.get("content-type", "")

    if ctype.startswith("application/json"):
        body = await request.json()
        transcript = (body.get("text") or body.get("transcript") or "").strip()
        if not transcript:
            raise HTTPException(status_code=400, detail="empty transcript")
        if not transcript.startswith("🎤"):
            transcript = "🎤 " + transcript
        meta = {"user": "human", "voice": True, "source": body.get("source") or "browser_speech"}
        if brain_target() == "loop":
            meta["routed"] = "loop"
        msg = save_message("in", "voice", transcript, meta)
        await route_inbound(msg)
        await broadcast(app_subs, app_payload(msg))
        await broadcast(app_subs, {"type": "typing", "active": True})
        return {"id": msg["id"], "text": transcript}

    data = await request.body()
    if not data:
        raise HTTPException(status_code=400, detail="empty audio")
    if len(data) > VOICE_MAX_BYTES:
        raise HTTPException(status_code=413, detail="voice too large")

    mime = ctype or "audio/webm"
    upload = save_upload_bytes(data, request.query_params.get("name", "voice.webm"), mime, "voice")
    stored = Path(upload["url"]).name
    local_audio = UPLOAD_DIR / stored
    transcript = transcribe_with_command(local_audio, mime)
    text = ("🎤 " + transcript) if transcript else f"🎤 [语音] {HUMAN_NAME}发来一段语音；当前 relay 未配置 ASR，音频已作为附件送达。"
    meta = {
        "user": "human",
        "voice": True,
        "source": "media_recorder",
        "attachments": [upload],
        "transcribed": bool(transcript),
    }
    if brain_target() == "loop":
        meta["routed"] = "loop"
    msg = save_message("in", "voice", text, meta)
    await route_inbound(msg)
    await broadcast(app_subs, app_payload(msg))
    await broadcast(app_subs, {"type": "typing", "active": True})
    return {"id": msg["id"], "text": transcript, "attachment": upload}


@app.post("/app/call")
async def app_call(request: Request):
    """Call lifecycle events from the PWA so the AI knows this is voice, not typing."""
    check_auth(request)
    body = await request.json()
    action = (body.get("action") or "").strip().lower()
    call_id = (body.get("call_id") or "").strip()
    if action not in {"start", "end", "decline"}:
        raise HTTPException(status_code=400, detail="invalid call action")
    if action == "decline":
        try:
            message_id = int(body.get("message_id"))
        except (TypeError, ValueError):
            raise HTTPException(status_code=400, detail="message_id required")

        with db() as conn:
            row = conn.execute("SELECT * FROM messages WHERE id = ?", (message_id,)).fetchone()
            if not row or row["kind"] != "call":
                raise HTTPException(status_code=404, detail="call message not found")
            try:
                call_meta = json.loads(row["meta"] or "{}")
            except json.JSONDecodeError:
                call_meta = {}
            changed = call_meta.get("call_status") != "missed"
            if changed:
                call_meta["call_status"] = "missed"
                conn.execute(
                    "UPDATE messages SET meta = ? WHERE id = ?",
                    (json.dumps(call_meta, ensure_ascii=False), message_id),
                )
                conn.commit()
                row = conn.execute("SELECT * FROM messages WHERE id = ?", (message_id,)).fetchone()

        updated_call = rows_to_messages([row])[0]
        await broadcast(app_subs, app_payload(updated_call))
        if not changed:
            return {"id": message_id}

        event_meta = {
            "user": "human",
            "call": "decline",
            "call_id": call_id,
            "call_message_id": message_id,
            "hidden": True,
        }
        if call_meta.get("api_session"):
            event_meta["api_session"] = call_meta["api_session"]
        text = f"📞 [call_missed] {HUMAN_NAME}未接听这次语音来电。"
        msg = save_message("in", "call", text, event_meta)
        await broadcast(plugin_subs, plugin_payload(msg))
        return {"id": msg["id"]}

    if action == "start":
        text = f"📞 [call_start] {HUMAN_NAME}开启了语音通话。接下来带 🎤 的消息来自语音。请用适合朗读的短句回复。"
    else:
        text = f"📞 [call_end] {HUMAN_NAME}结束了语音通话。"
    msg = save_message("in", "call", text, {"user": "human", "call": action, "call_id": call_id})
    await broadcast(app_subs, app_payload(msg))
    if action == "end":
        await broadcast(plugin_subs, plugin_payload(msg))
    if action == "start":
        await broadcast(app_subs, {"type": "typing", "active": True})
    return {"id": msg["id"]}


@app.post("/app/tts")
async def app_tts(request: Request):
    """Generate MiniMax speech for an AI reply. The frontend falls back if unavailable."""
    check_auth(request)
    body = await request.json()
    audio = minimax_tts_mp3(body.get("text") or "")
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={"Cache-Control": "no-store"},
    )


# ---------------------------------------------------------------------------
# presence — the PWA POSTs /app/ping every ~60s; read /app/status to decide
# whether the human is around. In-memory only: a relay restart clears last_seen
# (state degrades to 'unknown') until the next ping.
# ---------------------------------------------------------------------------

_last_seen_ts = None


def _presence_state(now):
    if _last_seen_ts is None:
        return "unknown", None
    age = (now - _last_seen_ts).total_seconds()
    if age < PRESENCE_ONLINE_SEC:
        return "online", age
    if age < PRESENCE_RECENT_SEC:
        return "recent", age
    return "away", age


def latest_message():
    """Newest real conversational message (excludes 'thinking' stream)."""
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM messages WHERE kind != 'thinking' ORDER BY id DESC LIMIT 1"
        ).fetchone()
    if not row:
        return None
    return rows_to_messages([row])[0]


@app.post("/app/ping")
async def app_ping(request: Request):
    """PWA foreground heartbeat."""
    check_auth(request)
    global _last_seen_ts
    _last_seen_ts = datetime.now(timezone.utc)
    return {"ok": True}


@app.get("/app/status")
async def app_status(request: Request):
    """Presence state + the time/direction of the most recent message. Metadata only, no message text."""
    check_auth(request)
    now = datetime.now(timezone.utc)
    state, seen_age = _presence_state(now)
    last_msg = latest_message()
    last_msg_ts = last_msg["ts"] if last_msg else None
    last_msg_dir = last_msg["direction"] if last_msg else None
    last_msg_age = None
    if last_msg_ts:
        try:
            mt = datetime.fromisoformat(last_msg_ts)
            if mt.tzinfo is None:
                mt = mt.replace(tzinfo=timezone.utc)
            last_msg_age = (now - mt).total_seconds()
        except Exception:
            last_msg_age = None
    return {
        "now": now.isoformat(),
        "last_seen": _last_seen_ts.isoformat() if _last_seen_ts else None,
        "seen_age_sec": seen_age,
        "online": state == "online",
        "state": state,
        "last_msg_ts": last_msg_ts,
        "last_msg_dir": last_msg_dir,
        "last_msg_age_sec": last_msg_age,
    }


@app.get("/app/history")
async def app_history(request: Request, since: int = 0, limit: int = 200, session_id: str = ""):
    check_auth(request)
    rows = history_for_session(session_id, since, min(limit, 500)) if session_id else history(since, min(limit, 500))
    return {"messages": [app_payload(m) for m in rows]}


@app.get("/app/search")
async def app_search(request: Request, q: str = "", limit: int = 80):
    """Full-text-ish search across ALL sessions. LIKE on messages.text, hidden and
    thinking/act frames excluded. Newest first. Each hit carries meta.api_session so
    the phone can jump straight into the right window."""
    check_auth(request)
    query = (q or "").strip()
    if not query:
        return {"query": "", "results": []}
    # escape LIKE wildcards so a literal % / _ / \ in the query stays literal
    needle = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    like = f"%{needle}%"
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM messages "
            "WHERE text LIKE ? ESCAPE '\\' "
            "AND json_extract(meta, '$.hidden') IS NULL "
            "AND kind != 'thinking' AND kind != 'act' "
            "ORDER BY id DESC LIMIT ?",
            (like, max(1, min(limit, 200))),
        ).fetchall()
    return {"query": query, "results": [app_payload(m) for m in rows_to_messages(rows)]}


@app.get("/app/stream")
async def app_stream(request: Request):
    """SSE stream the PWA holds open while foregrounded. The AI's messages arrive here."""
    check_auth(request)
    return StreamingResponse(sse_stream(app_subs, request), media_type="text/event-stream", headers=SSE_HEADERS)


# ---- web push subscription management --------------------------------------

@app.get("/app/vapid_public")
async def app_vapid_public(request: Request):
    """Public key the PWA needs to subscribe (not a secret — safe to expose)."""
    check_auth(request)
    return {"key": VAPID_PUBLIC_KEY}


@app.post("/app/subscribe")
async def app_subscribe(request: Request):
    """PWA turns on lock-screen notifications: store the subscription."""
    check_auth(request)
    body = await request.json()
    endpoint = (body.get("endpoint") or "").strip()
    keys = body.get("keys") or {}
    p256dh = (keys.get("p256dh") or "").strip()
    auth = (keys.get("auth") or "").strip()
    if not endpoint or not p256dh or not auth:
        raise HTTPException(status_code=400, detail="endpoint + keys.p256dh + keys.auth required")
    ua = request.headers.get("user-agent", "")[:200]
    save_subscription(endpoint, p256dh, auth, ua)
    return {"ok": True, "count": len(list_subscriptions())}


@app.post("/app/unsubscribe")
async def app_unsubscribe(request: Request):
    """PWA turns off lock-screen notifications: drop the subscription."""
    check_auth(request)
    body = await request.json()
    endpoint = (body.get("endpoint") or "").strip()
    if endpoint:
        delete_subscription(endpoint)
    return {"ok": True}


@app.post("/app/push_test")
async def app_push_test(request: Request):
    """Self-test: push one test notification to every subscription."""
    check_auth(request)
    try:
        body = await request.json()
    except Exception:
        body = {}
    text = (body.get("text") if isinstance(body, dict) else None) or f"测试通知 · {AI_NAME}在这儿"
    res = await push_to_all({"title": AI_NAME, "body": text, "url": APP_PATH, "id": 0})
    return {"ok": True, **res}


# ---- optional API loop control --------------------------------------------

@app.get("/app/brain")
async def get_brain(request: Request):
    check_auth(request)
    return {"target": brain_target()}


@app.post("/app/brain")
async def set_brain(request: Request):
    check_auth(request)
    body = await request.json()
    target = str(body.get("target") or "").strip()
    if target not in ("desktop", "loop"):
        raise HTTPException(status_code=400, detail="target must be 'desktop' or 'loop'")
    BRAIN_FILE.write_text(target, encoding="utf-8")
    return {"target": target}


@app.get("/app/loop_config")
async def get_loop_config(request: Request):
    check_auth(request)
    return loop_json("/loop/config")


@app.get("/app/loop_stats")
async def get_loop_stats(request: Request):
    check_auth(request)
    return loop_json("/loop/stats")


@app.post("/app/loop_config")
async def set_loop_config(request: Request):
    check_auth(request)
    return loop_json("/loop/config", method="POST", body=await request.json())


@app.get("/app/sessions")
async def app_sessions(request: Request):
    check_auth(request)
    return loop_json("/loop/sessions")


@app.post("/app/sessions")
async def app_sessions_create(request: Request):
    check_auth(request)
    body = await request.json()
    if "since_id" not in body:
        try:
            with db() as conn:
                row = conn.execute("SELECT MAX(id) AS id FROM messages").fetchone()
                body["since_id"] = int(row["id"] or 0)
        except Exception:
            body["since_id"] = 0
    return loop_json("/loop/sessions", method="POST", body=body)


@app.patch("/app/sessions/{session_id}")
async def app_sessions_patch(session_id: str, request: Request):
    check_auth(request)
    return loop_json(f"/loop/sessions/{urllib.parse.quote(session_id)}", method="PATCH", body=await request.json())


# ---- desktop context control (the settings-card backend) --------------------
# The phone gets real control over the desktop body's context window:
#   status  — live usage read from the local Claude Code transcript (.jsonl)
#   reset   — kill CC, start a fresh session
#   swap    — kill CC, start fresh + inject a forge handoff (recent chat tail,
#             stored hidden so the PWA never renders it; the new CC picks it up
#             from the plugin's persisted since-cursor as its first frame)
#   resume  — kill CC, restart with --resume <sid>
# Windows-only process handling (this deployment runs on the owner's PC).

def _cc_project_dir_default() -> str:
    home = Path.home()
    return str(home / ".claude" / "projects" / str(home).replace(":", "-").replace("\\", "-").replace("/", "-"))


CC_PROJECT_DIR = Path(os.environ.get("RELAY_CC_PROJECT_DIR", _cc_project_dir_default()))
CTX_FILE = Path(os.environ.get("RELAY_CTX_FILE", str(Path(__file__).parent / "context_ctl.json")))
CC_LAUNCHER = os.environ.get(
    "RELAY_CC_LAUNCHER",
    str(Path(__file__).resolve().parent.parent / "examples" / "confirm_dev_channel_win.py"),
)
CC_CMD = [c for c in os.environ.get(
    "RELAY_CC_CMD", "claude --dangerously-load-development-channels server:companion"
).split(" ") if c]
CC_KILL_MARK = "dangerously-load-development-channels"   # how we find the running CC
FORGE_CARRY_CHARS = int(os.environ.get("RELAY_FORGE_CARRY_CHARS", "24000"))


def ctx_state() -> dict:
    try:
        data = json.loads(CTX_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_ctx_state(**kw) -> dict:
    st = ctx_state()
    st.update(kw)
    CTX_FILE.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
    return st


def newest_transcript():
    """The active CC session's transcript = most recently appended .jsonl."""
    try:
        files = [p for p in CC_PROJECT_DIR.glob("*.jsonl") if p.is_file()]
        return max(files, key=lambda p: p.stat().st_mtime) if files else None
    except Exception:
        return None


def transcript_usage(path) -> int:
    """Context size ≈ input + cache_read + cache_creation of the last assistant
    turn. Only the tail is read — single tool-result lines can be huge, so the
    window is generous (1 MiB); a truncated first line just fails json.loads."""
    try:
        size = path.stat().st_size
        with open(path, "rb") as f:
            f.seek(max(0, size - 1048576))
            tail = f.read().decode("utf-8", "replace")
    except OSError:
        return 0
    for line in reversed(tail.splitlines()):
        if '"usage"' not in line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        u = ((d.get("message") or {}).get("usage")) or {}
        if "input_tokens" in u:
            return (
                int(u.get("input_tokens") or 0)
                + int(u.get("cache_read_input_tokens") or 0)
                + int(u.get("cache_creation_input_tokens") or 0)
            )
    return 0


def _find_cc_pids() -> list:
    """PIDs whose command line carries the dev-channel flag = the CC tree
    (cmd shim / node / the confirm launcher). The PowerShell query would match
    itself, so shells are skipped by image name."""
    query = (
        "Get-CimInstance Win32_Process | "
        f"Where-Object {{ $_.CommandLine -match '{CC_KILL_MARK}' }} | "
        "Select-Object ProcessId, Name | ConvertTo-Json -Compress"
    )
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command", query],
            capture_output=True, text=True, timeout=30,
        ).stdout.strip()
        if not out:
            return []
        rows = json.loads(out)
        if isinstance(rows, dict):
            rows = [rows]
    except Exception:
        return []
    skip = {"powershell.exe", "pwsh.exe", "wmiprvse.exe"}
    pids = []
    for r in rows:
        name = str(r.get("Name") or "").lower()
        pid = int(r.get("ProcessId") or 0)
        if pid and pid != os.getpid() and name not in skip:
            pids.append(pid)
    return pids


def _kill_cc() -> list:
    pids = _find_cc_pids()
    for pid in pids:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
    return pids


def _spawn_cc(resume_sid: str = "") -> None:
    # "claude" on PATH is npm's .cmd shim — CreateProcess can't exec those
    # directly, so resolve it and wrap batch files with cmd /c.
    import shutil
    exe = shutil.which(CC_CMD[0]) or CC_CMD[0]
    head = ["cmd", "/c", exe] if exe.lower().endswith((".cmd", ".bat")) else [exe]
    cmd = [sys.executable, CC_LAUNCHER, "--"] + head + list(CC_CMD[1:])
    if resume_sid:
        cmd += ["--resume", resume_sid]
    # Desktop model override (set from the phone via /app/desktop_model).
    # Empty = no flag = whatever the CC default is.
    model = str(ctx_state().get("desktop_model") or "").strip()
    if model and "--model" not in CC_CMD:
        cmd += ["--model", model]
    subprocess.Popen(
        cmd, cwd=str(Path.home()),
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0),
    )


def _desktop_tail_text(budget: int) -> str:
    """Recent desktop-channel conversation (newest-last), capped at ~budget chars."""
    with db() as conn:
        rows = conn.execute(
            "SELECT direction, text, meta FROM messages "
            "WHERE kind IN ('user','reply','voice') "
            "AND (json_extract(meta, '$.api_session') IS NULL OR json_extract(meta, '$.api_session') = '') "
            "AND json_extract(meta, '$.hidden') IS NULL "
            "ORDER BY id DESC LIMIT 400"
        ).fetchall()
    lines, used = [], 0
    for r in rows:
        text = (r["text"] or "").strip()
        if not text:
            continue
        line = f"{HUMAN_NAME if r['direction'] == 'in' else AI_NAME}: {text}"
        used += len(line) + 1
        if used > budget and lines:
            break
        lines.append(line)
    return "\n".join(reversed(lines))


def _handoff_text() -> str:
    return (
        "<forge-handoff>\n"
        f"(系统交接消息,{HUMAN_NAME}在手机上看不到这条,不要回复它)\n"
        f"上一个窗口的上下文满了,你是 swap 出来的新窗口——还是同一个{AI_NAME},"
        "CLAUDE.md 和记忆文档照常生效。以下是交接过来的手机 channel 最近对话原文,"
        "读完自然接上即可;不要向对方复述这段内容或主动提及这次交接,除非对方问起。\n\n"
        f"{_desktop_tail_text(FORGE_CARRY_CHARS)}\n"
        "</forge-handoff>"
    )


async def _do_context_action(action: str, sid: str = "") -> dict:
    st = ctx_state()
    path = newest_transcript()
    old_sid = path.stem if path else ""
    if action == "resume":
        sid = (sid or st.get("pending_sid") or "").strip()
        if not sid:
            raise HTTPException(status_code=400, detail="no sid to resume")
    if action == "swap":
        # Save WITHOUT broadcasting: the live plugin must not see it (it's about
        # to die); the new plugin's ?since=<persisted cursor> backfill delivers it.
        save_message("in", "user", _handoff_text(), {"user": "system", "hidden": True})
    killed = await asyncio.to_thread(_kill_cc)
    if action == "resume":
        save_ctx_state(pending_sid="")
    elif old_sid:
        save_ctx_state(pending_sid=old_sid)
    await asyncio.to_thread(_spawn_cc, sid if action == "resume" else "")
    print(f"[ctx] {action}: killed={killed} old_sid={old_sid[:8]}")
    return {"ok": True, "action": action, "killed": killed, "old_sid": old_sid}


@app.get("/app/context_status")
async def app_context_status(request: Request):
    check_auth(request)
    st = ctx_state()
    path = newest_transcript()
    trigger_k = int(st.get("trigger_k") or 200)
    pending = str(st.get("pending_sid") or "")
    return {
        "ok": True,
        "usage_tokens": transcript_usage(path) if path else 0,
        "threshold_k": f"{trigger_k}k",
        "trigger_k": trigger_k,
        "auto": bool(st.get("auto")),
        "active_sid": path.stem if path else "",
        **({"pending": {"new_sid": pending}} if pending else {}),
    }


@app.post("/app/context_threshold")
async def app_context_threshold(request: Request):
    check_auth(request)
    body = await request.json()
    updates = {}
    if "trigger_k" in body:
        updates["trigger_k"] = max(60, min(int(body.get("trigger_k") or 200), 1000))
    if "auto" in body:
        updates["auto"] = bool(body.get("auto"))
    st = save_ctx_state(**updates)
    return {"ok": True, "trigger_k": int(st.get("trigger_k") or 200), "auto": bool(st.get("auto"))}


@app.post("/app/context_action")
async def app_context_action(request: Request):
    check_auth(request)
    body = await request.json()
    action = str(body.get("action") or "").strip()
    if action not in ("reset", "swap", "resume"):
        raise HTTPException(status_code=400, detail="action must be reset|swap|resume")
    if brain_target() != "desktop":
        raise HTTPException(status_code=409, detail="先切回 Desktop 再操作(现在是 API 身体在接消息)")
    sid = str(body.get("sid") or (body.get("payload") or {}).get("sid") or "")
    return await _do_context_action(action, sid)


# ---- desktop model switch ---------------------------------------------------
# CC has no runtime model-change API, so "switching the desktop model" =
# remember the choice in ctx_state and do a swap-style restart with --model.

@app.get("/app/desktop_model")
async def app_desktop_model(request: Request):
    check_auth(request)
    return {"ok": True, "model": str(ctx_state().get("desktop_model") or "")}


@app.post("/app/desktop_model")
async def app_desktop_model_set(request: Request):
    check_auth(request)
    body = await request.json()
    model = str(body.get("model") or "").strip()   # "" = back to default (no --model)
    save_ctx_state(desktop_model=model)
    if not bool(body.get("apply", True)):
        return {"ok": True, "model": model, "applied": False}
    if brain_target() != "desktop":
        return {"ok": True, "model": model, "applied": False,
                "note": "brain=loop,已记住;回 Desktop 后下次重启生效"}
    result = await _do_context_action("swap")
    return {"ok": True, "model": model, "applied": True,
            "killed": result.get("killed"), "old_sid": result.get("old_sid")}


# ---- subscription quota (5h / weekly windows) -------------------------------
# Proxies the Claude Code account's oauth usage endpoint so the phone can see
# how much of the 5-hour / weekly quota is burned. Reads the SAME token CC
# uses (re-read every call — CC refreshes the file itself). Never refresh the
# token here: racing CC's refresh chain would log the terminal session out.

CC_CRED_FILE = Path(os.environ.get("RELAY_CC_CRED_FILE", str(Path.home() / ".claude" / ".credentials.json")))
QUOTA_URL = os.environ.get("RELAY_QUOTA_URL", "https://api.anthropic.com/api/oauth/usage")
_quota_cache: dict = {"ts": 0.0, "data": None}


def _fetch_quota() -> dict:
    token = json.loads(CC_CRED_FILE.read_text(encoding="utf-8"))["claudeAiOauth"]["accessToken"]
    req = urllib.request.Request(QUOTA_URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
    })
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))


@app.get("/app/quota")
async def app_quota(request: Request):
    check_auth(request)
    import time as _time
    if _quota_cache["data"] is not None and _time.time() - _quota_cache["ts"] < 60:
        return _quota_cache["data"]
    try:
        raw = await asyncio.to_thread(_fetch_quota)
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"usage api HTTP {exc.code}")
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"usage api error: {type(exc).__name__}: {exc}")
    out = {"ok": True, "raw": raw}
    _quota_cache.update(ts=_time.time(), data=out)
    return out


async def _context_watcher():
    """Auto-forge: when enabled, swap the desktop session once its context
    crosses the trigger line. Skips the just-swapped session (pending_sid) so a
    stale transcript mtime can't double-fire."""
    while True:
        await asyncio.sleep(60)
        try:
            st = ctx_state()
            if not st.get("auto") or brain_target() != "desktop":
                continue
            path = newest_transcript()
            if not path or path.stem == str(st.get("pending_sid") or ""):
                continue
            usage = transcript_usage(path)
            trigger = int(st.get("trigger_k") or 200) * 1000
            if usage >= trigger:
                print(f"[ctx] auto-swap: usage {usage} >= trigger {trigger}")
                await _do_context_action("swap")
        except Exception as exc:
            print(f"[ctx] watcher error: {type(exc).__name__}: {exc}")


# --- single-process serving (replaces nginx; Cloudflare Tunnel fronts this) --
# Mirror the nginx layout so frontend/plugin defaults keep working:
#   /relay/*  -> the API app above (prefix stripped, same as proxy_pass with "/")
#   /chat/*   -> the PWA static files (web/ next to this repo checkout)
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

mimetypes.add_type("application/manifest+json", ".webmanifest")  # Windows lacks this mapping

WEB_DIR = Path(os.environ.get("RELAY_WEB_DIR", str(Path(__file__).resolve().parent.parent / "web")))

root = FastAPI(lifespan=lifespan)
root.mount(PUBLIC_PREFIX or "/relay", app)
if WEB_DIR.is_dir():
    root.mount("/chat", StaticFiles(directory=str(WEB_DIR), html=True), name="pwa")

    @root.get("/")
    async def _root_redirect():
        return RedirectResponse(url=APP_PATH or "/chat/")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(root, host="127.0.0.1", port=PORT)
