#!/usr/bin/env python3
"""
api_loop.py — optional server-side OpenAI-compatible loop for Companion Channel.

Run this beside backend/app.py when you want the VPS to answer directly via an
LLM API instead of routing every message to the Claude Code channel plugin.

Relay flow:
  PWA POST /relay/app/send
    -> relay stores the human message
    -> when /relay/app/brain == "loop", relay POSTs here: /loop/ingest
    -> this loop builds persona + same-session history + current message
    -> model answer is POSTed back to relay /channel/out

All private values live in env/.env. This file contains no domain, key, or
personal identity.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import json
import os
import re
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

import httpx
import uvicorn
from fastapi import FastAPI, HTTPException, Request


def load_dotenv(path: Path) -> None:
    try:
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
    except FileNotFoundError:
        pass


HERE = Path(__file__).resolve().parent
load_dotenv(HERE / ".env")

LOOP_PORT = int(os.environ.get("LOOP_PORT", "3020"))
LOOP_CONFIG = Path(os.environ.get("LOOP_CONFIG", str(HERE / "api_loop.config.json")))
RELAY_DB = os.environ.get("RELAY_DB", str(HERE.parent / "backend" / "relay.db"))
RELAY_URL = os.environ.get("RELAY_URL", "http://127.0.0.1:3011").rstrip("/")
RELAY_SECRET = os.environ.get("RELAY_SECRET", "")
PERSONA_FILE = os.environ.get("PERSONA_FILE", "")
PERSONA = os.environ.get("PERSONA", "").strip()
HISTORY_N = int(os.environ.get("HISTORY_N", "24"))
MAX_TOKENS = int(os.environ.get("LLM_MAX_TOKENS", "2000"))
TEMPERATURE = float(os.environ.get("LLM_TEMPERATURE", "0.7"))
STREAM_OUTPUT = os.environ.get("LOOP_STREAM", "1").lower() not in {"0", "false", "no"}
FALLBACK_CODES = {401, 403, 404, 408, 409, 429, 500, 502, 503, 504}
MCP_URL = os.environ.get("MCP_URL", "").strip()
MCP_TOKEN = os.environ.get("MCP_TOKEN", "").strip()
MCP_TOOL_ROUNDS = int(os.environ.get("MCP_TOOL_ROUNDS", "8"))
MCP_RESULT_MAX = int(os.environ.get("MCP_RESULT_MAX", "20000"))
# Claude 原生路径（/v1/messages）：自己打 cache_control 断点做增量缓存。
# CACHE_TTL: 5m 写入溢价 1.25x / 1h 溢价 2x；THINKING_BUDGET>0 时开原生思考。
CACHE_TTL = os.environ.get("CACHE_TTL", "5m")
if CACHE_TTL not in {"5m", "1h"}:
    CACHE_TTL = "5m"
THINKING_BUDGET = int(os.environ.get("THINKING_BUDGET", "1024"))
# 缓存心跳保活：CACHE_TTL=1h 时，距上次真实聊天/心跳 >= AFTER_MIN 分钟就打一针
# 续 TTL；超过 MAX_IDLE_H 小时没有真实聊天就停（别给空气续费）。
KEEPALIVE_AFTER_MIN = int(os.environ.get("KEEPALIVE_AFTER_MIN", "50"))
KEEPALIVE_MAX_IDLE_H = float(os.environ.get("KEEPALIVE_MAX_IDLE_H", "6"))
KEEPALIVE_TEXT = "__cache_keepalive__ 系统缓存保活请求：不要调用任何工具，不要分析上下文，只输出 OK。"

if not PERSONA and PERSONA_FILE:
    try:
        PERSONA = Path(PERSONA_FILE).read_text(encoding="utf-8").strip()
    except OSError:
        PERSONA = ""
if not PERSONA:
    PERSONA = (
        "You are the user's private AI companion in a one-to-one chat. "
        "Reply naturally, warmly, and concisely unless the user asks for detail."
    )


class McpClient:
    """Minimal MCP Streamable-HTTP client: initialize / tools/list / tools/call.

    Speaks JSON-RPC over POST; handles both application/json and SSE-wrapped
    responses, and re-initializes when the server session expires.
    """

    def __init__(self, url: str, token: str = "") -> None:
        self.url = url
        self.token = token
        self.session_id = ""
        self.tools: list[dict[str, Any]] = []
        self._id = 0
        self._lock = asyncio.Lock()

    def _headers(self) -> dict[str, str]:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        return headers

    async def _rpc(self, method: str, params: dict[str, Any] | None = None, *, notify: bool = False) -> dict[str, Any]:
        payload: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        if not notify:
            self._id += 1
            payload["id"] = self._id
        async with httpx.AsyncClient(timeout=60, trust_env=False) as client:
            resp = await client.post(self.url, headers=self._headers(), json=payload)
        sid = resp.headers.get("mcp-session-id")
        if sid:
            self.session_id = sid
        if resp.status_code >= 400:
            raise RuntimeError(f"mcp HTTP {resp.status_code}")
        if notify:
            return {}
        # 响应可能是裸 JSON，也可能是 SSE 流（帧里还可能夹进度通知）——挑出带本次 id 的那条
        bodies: list[str] = []
        content_type = resp.headers.get("content-type") or ""
        if "text/event-stream" in content_type:
            for line in resp.text.splitlines():
                if line.startswith("data:"):
                    bodies.append(line[5:].strip())
        else:
            bodies.append(resp.text)
        for body in bodies:
            if not body:
                continue
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                continue
            if not isinstance(data, dict) or data.get("id") != payload.get("id"):
                continue
            if data.get("error"):
                err = data["error"]
                raise RuntimeError(f"mcp error: {err.get('message') if isinstance(err, dict) else err}")
            return data.get("result") or {}
        raise RuntimeError("mcp: no matching response in stream")

    async def ensure(self) -> list[dict[str, Any]]:
        async with self._lock:
            if self.tools and self.session_id:
                return self.tools
            self.session_id = ""
            await self._rpc("initialize", {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {"name": "companion-api-loop", "version": "1.0"},
            })
            await self._rpc("notifications/initialized", notify=True)
            listed = await self._rpc("tools/list")
            self.tools = listed.get("tools") or []
            return self.tools

    async def call(self, name: str, arguments: dict[str, Any]) -> str:
        result: dict[str, Any] = {}
        for attempt in (1, 2):
            try:
                result = await self._rpc("tools/call", {"name": name, "arguments": arguments})
                break
            except Exception:
                # 会话过期/掉线：重握手再试一次
                self.tools = []
                self.session_id = ""
                if attempt == 2:
                    raise
                await self.ensure()
        parts = [
            str(item.get("text") or "")
            for item in (result.get("content") or [])
            if isinstance(item, dict) and item.get("type") == "text"
        ]
        text = "\n".join(p for p in parts if p).strip()
        if result.get("isError") and not text:
            text = "tool reported an error"
        return text or json.dumps(result, ensure_ascii=False)[:2000]


MCP = McpClient(MCP_URL, MCP_TOKEN) if MCP_URL else None


def openai_tools(mcp_tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "type": "function",
            "function": {
                "name": t.get("name", ""),
                "description": (t.get("description") or "")[:1024],
                "parameters": t.get("inputSchema") or {"type": "object", "properties": {}},
            },
        }
        for t in mcp_tools
        if t.get("name")
    ]


def anthropic_tools(mcp_tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "name": t.get("name", ""),
            "description": (t.get("description") or "")[:1024],
            "input_schema": t.get("inputSchema") or {"type": "object", "properties": {}},
        }
        for t in mcp_tools
        if t.get("name")
    ]


async def mcp_tool_defs() -> list[dict[str, Any]] | None:
    """MCP 不可达时静默降级为无工具，不阻塞聊天。"""
    if not MCP or not tools_enabled():
        return None
    try:
        return (await MCP.ensure()) or None
    except Exception:
        return None


def to_anthropic(messages: list[dict[str, str]]) -> tuple[list[str], list[dict[str, Any]]]:
    """OpenAI 风格 [{role, content:str}] → (system 文本列表, Anthropic content-block 消息)。
    system 保持分块（persona / 摘要各一块，各配缓存断点：摘要翻页更新时不炸 persona 缓存）。
    同角色相邻合并、首条必须是 user——Anthropic 格式的硬要求。"""
    system_texts: list[str] = []
    convo: list[dict[str, Any]] = []
    for m in messages:
        role = m.get("role")
        text = str(m.get("content") or "").strip()
        if not text:
            continue
        if role == "system":
            system_texts.append(text)
            continue
        role = "assistant" if role == "assistant" else "user"
        if convo and convo[-1]["role"] == role:
            convo[-1]["content"].append({"type": "text", "text": text})
        else:
            convo.append({"role": role, "content": [{"type": "text", "text": text}]})
    if convo and convo[0]["role"] == "assistant":
        convo.insert(0, {"role": "user", "content": [{"type": "text", "text": "…"}]})
    return system_texts, convo


def mark_cache(convo: list[dict[str, Any]]) -> None:
    """把消息侧唯一的缓存断点挪到当前最后一个可标块上（thinking 块不能标）。
    固定锚点让历史只增不减，于是每轮都能读到上一轮写下的前缀。"""
    last: dict[str, Any] | None = None
    for msg in convo:
        for block in msg.get("content") or []:
            if not isinstance(block, dict):
                continue
            block.pop("cache_control", None)
            if block.get("type") not in {"thinking", "redacted_thinking"}:
                last = block
    if last is not None:
        last["cache_control"] = {"type": "ephemeral", "ttl": CACHE_TTL}


def env_routes() -> list[dict[str, str]]:
    routes: list[dict[str, str]] = []
    for suffix in ("", "_2", "_3", "_4"):
        base = os.environ.get(f"LLM_API_BASE{suffix}", "").rstrip("/")
        key = os.environ.get(f"LLM_API_KEY{suffix}", "")
        model = os.environ.get(f"LLM_MODEL{suffix}", "")
        if base and key and model:
            routes.append({"url": base, "key": key, "model": model})
    return routes


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def mask_key(key: str) -> str:
    key = str(key or "")
    if not key:
        return ""
    if len(key) <= 10:
        return "***"
    return key[:6] + "***" + key[-4:]


def load_config() -> dict[str, Any]:
    try:
        data = json.loads(LOOP_CONFIG.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except FileNotFoundError:
        return {}
    except Exception:
        return {}


def save_config(cfg: dict[str, Any]) -> None:
    LOOP_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    tmp = LOOP_CONFIG.with_suffix(LOOP_CONFIG.suffix + ".tmp")
    tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(LOOP_CONFIG)


def main_chain() -> list[dict[str, str]]:
    cfg = load_config()
    configured = cfg.get("main_chain")
    if isinstance(configured, list):
        rows = [r for r in configured if isinstance(r, dict) and r.get("url") and r.get("key") and r.get("model")]
        if rows:
            return rows
    return env_routes()


def history_n() -> int:
    try:
        return max(0, min(int(load_config().get("history_n", HISTORY_N)), 200))
    except Exception:
        return HISTORY_N


def tools_enabled() -> bool:
    try:
        return bool(load_config().get("tools_enabled", True))
    except Exception:
        return True


def keepalive_enabled() -> bool:
    try:
        return bool(load_config().get("keepalive_enabled", True))
    except Exception:
        return True


def session_rows() -> list[dict[str, Any]]:
    rows = load_config().get("sessions")
    if not isinstance(rows, list):
        return []
    out = []
    for item in rows:
        if isinstance(item, dict) and item.get("id"):
            out.append({
                "id": str(item.get("id")),
                "title": str(item.get("title") or "New chat"),
                "since_id": int(item.get("since_id") or 0),
                "created_at": item.get("created_at") or "",
                "pinned": bool(item.get("pinned", False)),
            })
    return out


def active_session_id() -> str:
    cfg = load_config()
    active = str(cfg.get("active_session") or "").strip()
    ids = {s["id"] for s in session_rows()}
    if active in ids:
        return active
    rows = session_rows()
    return rows[-1]["id"] if rows else ""


def save_sessions(rows: list[dict[str, Any]], active: str | None = None) -> dict[str, Any]:
    cfg = load_config()
    cfg["sessions"] = rows
    if active is not None:
        cfg["active_session"] = active
    save_config(cfg)
    return sessions_public()


def sessions_public() -> dict[str, Any]:
    return {"active_session": active_session_id(), "sessions": session_rows()}


def create_session(title: str = "New chat", since_id: int = 0, activate: bool = True) -> dict[str, Any]:
    rows = session_rows()
    sid = "api-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:4]
    row = {"id": sid, "title": title or "New chat", "since_id": int(since_id or 0), "created_at": now_iso()}
    rows.append(row)
    save_sessions(rows, sid if activate else None)
    return row


def patch_session(session_id: str, body: dict[str, Any]) -> dict[str, Any]:
    rows = session_rows()
    found = False
    for item in rows:
        if item["id"] != session_id:
            continue
        found = True
        if "title" in body:
            item["title"] = str(body.get("title") or item["title"]).strip() or item["title"]
        if "pinned" in body:
            item["pinned"] = bool(body.get("pinned"))
    if not found:
        raise HTTPException(status_code=404, detail="session not found")
    active = session_id if body.get("active") else None
    return save_sessions(rows, active)


def relay_rows(before_id: int | None, session_id: str, limit: int) -> list[dict[str, Any]]:
    # 固定锚点 + 只增窗口（缓存友好）：锚点不动时历史只往后长、前缀逐字稳定，
    # 上游 prompt cache 才有得命中；窗口涨到 2*limit 才「翻页」——锚点前移到只留
    # 最近 limit 条，用一次 cache miss 换接下来 limit 条全命中。
    # （对比旧滚动窗口：每条新消息挤掉最老一条，前缀每次都变，永远 miss。）
    path = Path(RELAY_DB)
    if not path.exists() or limit <= 0:
        return []
    key = session_id or "_default"
    cfg = load_config()
    anchors = dict(cfg.get("history_anchors")) if isinstance(cfg.get("history_anchors"), dict) else {}
    params: list[Any] = [int(anchors.get(key) or 0)]
    # meta.hidden = relay 内部帧（swap 交接等），不进上下文
    where = ["kind IN ('user','voice','reply')", "json_extract(meta, '$.hidden') IS NULL", "id > ?"]
    if before_id:
        where.append("id < ?")
        params.append(int(before_id))
    if session_id:
        where.append("json_extract(meta, '$.api_session') = ?")
        params.append(session_id)
    else:
        where.append("(json_extract(meta, '$.api_session') IS NULL OR json_extract(meta, '$.api_session') = '')")
    hard_cap = limit * 2
    sql = (
        "SELECT id, direction, kind, text, meta FROM messages "
        f"WHERE {' AND '.join(where)} ORDER BY id DESC LIMIT ?"
    )
    params.append(hard_cap)
    with sqlite3.connect(str(path)) as conn:
        conn.row_factory = sqlite3.Row
        rows = [dict(r) for r in reversed(conn.execute(sql, params).fetchall())]
    if len(rows) >= hard_cap:
        old_anchor = int(anchors.get(key) or 0)
        rows = rows[-limit:]
        new_anchor = int(rows[0]["id"]) - 1
        anchors[key] = new_anchor
        cfg["history_anchors"] = anchors
        # 被翻出窗口的 (old_anchor, new_anchor] 记成待摘要区间，后台压进滚动摘要
        pend = dict(cfg.get("pending_summary")) if isinstance(cfg.get("pending_summary"), dict) else {}
        prev = pend.get(key) if isinstance(pend.get(key), dict) else {}
        pend[key] = {
            "from": min(int(prev.get("from") or old_anchor), old_anchor),
            "to": new_anchor,
        }
        cfg["pending_summary"] = pend
        save_config(cfg)
    return rows


def session_summary(key: str) -> str:
    cfg = load_config()
    rows = cfg.get("summaries")
    if isinstance(rows, dict) and isinstance(rows.get(key), dict):
        return str(rows[key].get("text") or "")
    return ""


SUMMARY_INFLIGHT: set[str] = set()

SUMMARY_PROMPT = (
    "请把【旧摘要】与【新增对话】合并成一份更新后的对话摘要：300-500字；"
    "新近的内容详细一些，更早的压缩成一两句；保留事实、约定、称呼和情绪走向；"
    "直接输出摘要正文，不要任何前后缀。"
)


async def summarize_pending(key: str) -> None:
    """把翻页丢掉的旧对话压进滚动摘要（fire-and-forget，失败留到下次重试）。"""
    if key in SUMMARY_INFLIGHT:
        return
    cfg = load_config()
    pend_all = cfg.get("pending_summary") if isinstance(cfg.get("pending_summary"), dict) else {}
    pend = pend_all.get(key) if isinstance(pend_all.get(key), dict) else None
    routes = main_chain()
    if not pend or not routes:
        return
    SUMMARY_INFLIGHT.add(key)
    try:
        lo, hi = int(pend.get("from") or 0), int(pend.get("to") or 0)
        session_id = "" if key == "_default" else key
        params: list[Any] = [lo, hi]
        where = ["kind IN ('user','voice','reply')", "json_extract(meta, '$.hidden') IS NULL", "id > ?", "id <= ?"]
        if session_id:
            where.append("json_extract(meta, '$.api_session') = ?")
            params.append(session_id)
        else:
            where.append("(json_extract(meta, '$.api_session') IS NULL OR json_extract(meta, '$.api_session') = '')")
        with sqlite3.connect(RELAY_DB) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT direction, text FROM messages "
                f"WHERE {' AND '.join(where)} ORDER BY id ASC",
                params,
            ).fetchall()
        lines = [
            ("assistant：" if r["direction"] == "out" else "user：") + str(r["text"] or "").strip()
            for r in rows
            if str(r["text"] or "").strip()
        ]
        if not lines:
            new_text = session_summary(key)
        else:
            old = session_summary(key) or "（无）"
            user_text = f"【旧摘要】\n{old}\n\n【新增对话】\n" + "\n".join(lines) + f"\n\n{SUMMARY_PROMPT}"
            route = routes[0]
            if "claude" in str(route.get("model") or "").lower():
                out = await native_complete(route, {
                    "model": route["model"],
                    "max_tokens": 800,
                    "temperature": 0.3,
                    "system": "你是对话摘要器。",
                    "messages": [{"role": "user", "content": [{"type": "text", "text": user_text}]}],
                })
                new_text = "\n".join(
                    (b.get("text") or "") for b in out.get("content") or [] if b.get("type") == "text"
                ).strip()
            else:
                out = await complete_chat(route, [
                    {"role": "system", "content": "你是对话摘要器。"},
                    {"role": "user", "content": user_text},
                ])
                new_text = (out.get("text") or "").strip()
            if not new_text:
                return  # 摘要失败，pending 保留，下次再试
        cfg = load_config()
        summaries = dict(cfg.get("summaries")) if isinstance(cfg.get("summaries"), dict) else {}
        summaries[key] = {"text": new_text[:4000], "covers_to": hi, "updated_at": now_iso()}
        cfg["summaries"] = summaries
        pend_all = dict(cfg.get("pending_summary")) if isinstance(cfg.get("pending_summary"), dict) else {}
        cur = pend_all.get(key) if isinstance(pend_all.get(key), dict) else None
        if cur and int(cur.get("to") or 0) <= hi:
            pend_all.pop(key, None)  # 期间又翻页了就留着，下一轮接着压
        cfg["pending_summary"] = pend_all
        save_config(cfg)
    except Exception:
        pass
    finally:
        SUMMARY_INFLIGHT.discard(key)


def build_messages(text: str, *, before_id: int | None = None, session_id: str = "", use_context: bool = True) -> list[dict[str, str]]:
    messages = [{"role": "system", "content": PERSONA}]
    if use_context:
        summary = session_summary(session_id or "_default")
        if summary:
            messages.append({"role": "system", "content": "【早前对话摘要】\n" + summary})
        for row in relay_rows(before_id, session_id, history_n()):
            content = str(row.get("text") or "").strip()
            if not content:
                continue
            role = "assistant" if row.get("direction") == "out" else "user"
            messages.append({"role": role, "content": content})
    messages.append({"role": "user", "content": text})
    return messages


def api_presets() -> list[dict[str, Any]]:
    rows = load_config().get("api_presets")
    out = []
    if isinstance(rows, list):
        for item in rows:
            if isinstance(item, dict) and item.get("url") and item.get("key") and item.get("model"):
                out.append({
                    "name": str(item.get("name") or "未命名"),
                    "url": str(item["url"]).rstrip("/"),
                    "key": str(item["key"]),
                    "model": str(item["model"]),
                })
    if not out:
        # 没配过预设时，把当前主链第一条当作唯一预设展示
        chain = main_chain()
        if chain:
            out.append({"name": "当前接口", **{k: chain[0][k] for k in ("url", "key", "model")}})
    return out


def presets_public() -> list[dict[str, Any]]:
    chain = main_chain()
    cur = chain[0] if chain else {}
    rows = api_presets()
    # 有精确匹配（url+key+model 全中）时只亮它——同一家接口配多个模型预设不会一起亮；
    # 否则退回 url+key 匹配（模型被四按钮切走了，仍显示归属哪家）
    exact = {
        i for i, p in enumerate(rows)
        if cur and p["url"] == cur.get("url") and p["key"] == cur.get("key") and p["model"] == cur.get("model")
    }
    return [
        {
            "index": i,
            "name": p["name"],
            "url": p["url"],
            "model": p["model"],
            "key_masked": mask_key(p["key"]),
            "active": (i in exact) if exact else (
                bool(cur) and p["url"] == cur.get("url") and p["key"] == cur.get("key")
            ),
        }
        for i, p in enumerate(rows)
    ]


def public_config() -> dict[str, Any]:
    return {
        "history_n": history_n(),
        "tools_enabled": tools_enabled(),
        "keepalive_enabled": keepalive_enabled(),
        "cache_ttl": CACHE_TTL,
        "mcp_url": MCP_URL,
        "mcp_tools": [t.get("name") for t in (MCP.tools if MCP else [])],
        "api_presets": presets_public(),
        "active_session": active_session_id(),
        "sessions": session_rows(),
        "summaries": {
            k: {"covers_to": v.get("covers_to"), "updated_at": v.get("updated_at"), "chars": len(str(v.get("text") or ""))}
            for k, v in (load_config().get("summaries") or {}).items()
            if isinstance(v, dict)
        },
        "pending_summary": load_config().get("pending_summary") or {},
        "main_chain": [
            {"index": i, "model": r.get("model", ""), "url": r.get("url", ""), "key_masked": mask_key(r.get("key", ""))}
            for i, r in enumerate(main_chain())
        ],
    }


def update_config(body: dict[str, Any]) -> dict[str, Any]:
    cfg = load_config()
    if "history_n" in body:
        cfg["history_n"] = max(0, min(int(body.get("history_n") or 0), 200))
    if "tools_enabled" in body:
        cfg["tools_enabled"] = bool(body.get("tools_enabled"))
    if "keepalive_enabled" in body:
        cfg["keepalive_enabled"] = bool(body.get("keepalive_enabled"))
    if isinstance(body.get("api_presets"), list):
        # 全量替换；key 留空表示"沿用同名旧预设的 key"（手机上只显示掩码，编辑时不用回填）
        old_by_name = {p["name"]: p for p in api_presets()}
        new_rows = []
        for pos, item in enumerate(body["api_presets"]):
            if not isinstance(item, dict):
                continue
            name = str(item.get("name") or f"预设{pos + 1}").strip()
            key = str(item.get("key") or "").strip() or old_by_name.get(name, {}).get("key", "")
            entry = {
                "name": name,
                "url": str(item.get("url") or "").strip().rstrip("/"),
                "key": key,
                "model": str(item.get("model") or "").strip(),
            }
            if not (entry["url"] and entry["key"] and entry["model"]):
                raise HTTPException(status_code=400, detail=f"预设 {name}: url/key/model 都要有")
            new_rows.append(entry)
        cfg["api_presets"] = new_rows
    if "activate_preset" in body:
        presets = api_presets() if "api_presets" not in body else [
            {k: p[k] for k in ("name", "url", "key", "model")} for p in cfg.get("api_presets") or []
        ]
        try:
            chosen = presets[int(body.get("activate_preset"))]
        except (ValueError, TypeError, IndexError):
            raise HTTPException(status_code=400, detail="activate_preset: 无效序号")
        cfg["main_chain"] = [{"url": chosen["url"], "key": chosen["key"], "model": chosen["model"]}]
    if isinstance(body.get("main_chain"), list):
        old = main_chain()
        new_chain = []
        for pos, item in enumerate(body["main_chain"]):
            if not isinstance(item, dict):
                continue
            old_idx = int(item.get("index", pos) or 0)
            prev = old[old_idx] if 0 <= old_idx < len(old) else {}
            entry = {
                "model": str(item.get("model") or prev.get("model") or "").strip(),
                "url": str(item.get("url") or prev.get("url") or "").strip().rstrip("/"),
                "key": str(item.get("key") or prev.get("key") or ""),
            }
            if not (entry["model"] and entry["url"] and entry["key"]):
                raise HTTPException(status_code=400, detail=f"row {pos + 1}: model/url/key required")
            new_chain.append(entry)
        if new_chain:
            cfg["main_chain"] = new_chain
    save_config(cfg)
    return public_config()


async def relay_out(payload: dict[str, Any]) -> tuple[bool, Any]:
    if not RELAY_SECRET:
        return False, "RELAY_SECRET missing"
    async with httpx.AsyncClient(timeout=30, trust_env=False) as client:
        resp = await client.post(
            f"{RELAY_URL}/channel/out",
            headers={"Authorization": f"Bearer {RELAY_SECRET}", "Content-Type": "application/json"},
            json=payload,
        )
    try:
        body: Any = resp.json()
    except Exception:
        body = resp.text[:500]
    return resp.status_code < 300, body


async def stream_chat(route: dict[str, str], messages: list[dict[str, Any]], sink, tools: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    body = {
        "model": route["model"],
        "messages": messages,
        "temperature": TEMPERATURE,
        "max_tokens": MAX_TOKENS,
        "stream": True,
    }
    if tools:
        body["tools"] = tools
    text_parts: list[str] = []
    usage: dict[str, Any] = {}
    tool_calls: dict[int, dict[str, Any]] = {}
    async with httpx.AsyncClient(timeout=None, trust_env=False) as client:
        async with client.stream(
            "POST",
            route["url"].rstrip("/") + "/chat/completions",
            headers={"Authorization": f"Bearer {route['key']}", "Content-Type": "application/json"},
            json=body,
        ) as resp:
            if resp.status_code in FALLBACK_CODES:
                raise HTTPException(status_code=resp.status_code, detail="fallback")
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                line = line.strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    ev = json.loads(data)
                except json.JSONDecodeError:
                    continue
                if isinstance(ev.get("usage"), dict):
                    usage = ev["usage"]
                delta = (((ev.get("choices") or [{}])[0]).get("delta") or {})
                chunk = delta.get("content") or ""
                if chunk:
                    text_parts.append(chunk)
                    await sink(chunk)
                # tool_calls 走增量：id/name 首帧给，arguments 分片拼接
                for tc in delta.get("tool_calls") or []:
                    idx = int(tc.get("index") or 0)
                    slot = tool_calls.setdefault(idx, {"id": "", "type": "function", "function": {"name": "", "arguments": ""}})
                    if tc.get("id"):
                        slot["id"] = tc["id"]
                    fn = tc.get("function") or {}
                    if fn.get("name"):
                        slot["function"]["name"] = fn["name"]
                    if fn.get("arguments"):
                        slot["function"]["arguments"] += fn["arguments"]
    return {
        "text": "".join(text_parts).strip(),
        "usage": usage,
        "tool_calls": [tool_calls[i] for i in sorted(tool_calls)],
    }


async def complete_chat(route: dict[str, str], messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    body = {
        "model": route["model"],
        "messages": messages,
        "temperature": TEMPERATURE,
        "max_tokens": MAX_TOKENS,
        "stream": False,
    }
    if tools:
        body["tools"] = tools
    async with httpx.AsyncClient(timeout=120, trust_env=False) as client:
        resp = await client.post(
            route["url"].rstrip("/") + "/chat/completions",
            headers={"Authorization": f"Bearer {route['key']}", "Content-Type": "application/json"},
            json=body,
        )
    if resp.status_code in FALLBACK_CODES:
        raise HTTPException(status_code=resp.status_code, detail="fallback")
    resp.raise_for_status()
    data = resp.json()
    msg = ((data.get("choices") or [{}])[0]).get("message") or {}
    return {
        "text": (msg.get("content") or "").strip(),
        "usage": data.get("usage") or {},
        "tool_calls": msg.get("tool_calls") or [],
    }


def native_headers(route: dict[str, str]) -> dict[str, str]:
    return {
        "x-api-key": route["key"],
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
    }


def native_body(route: dict[str, str], system_texts: list[str], convo: list[dict[str, Any]], tools: list[dict[str, Any]] | None) -> dict[str, Any]:
    body: dict[str, Any] = {
        "model": route["model"],
        "max_tokens": MAX_TOKENS,
        "messages": convo,
    }
    if system_texts:
        # 每块一个断点（persona/摘要变化频率不同），最多标 3 个——第 4 个断点留给消息侧
        body["system"] = [
            {"type": "text", "text": t, **({"cache_control": {"type": "ephemeral", "ttl": CACHE_TTL}} if i < 3 else {})}
            for i, t in enumerate(system_texts)
        ]
    if tools:
        body["tools"] = tools
    if THINKING_BUDGET > 0:
        # thinking 开着时 temperature 必须缺省，max_tokens 必须大于预算
        body["thinking"] = {"type": "enabled", "budget_tokens": max(1024, THINKING_BUDGET)}
        body["max_tokens"] = MAX_TOKENS + max(1024, THINKING_BUDGET)
    else:
        body["temperature"] = TEMPERATURE
    if "openrouter.ai" in str(route.get("url") or ""):
        # OpenRouter 会把同一模型路由到 Anthropic/Bedrock/Vertex 多家上游，
        # 缓存跨上游不互通——锁定 Anthropic 直连，保证前缀缓存稳定命中
        body["provider"] = {"only": ["anthropic"], "allow_fallbacks": False}
    return body


async def native_complete(route: dict[str, str], body: dict[str, Any]) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=300, trust_env=False) as client:
        resp = await client.post(route["url"].rstrip("/") + "/messages", headers=native_headers(route), json=body)
    if resp.status_code in FALLBACK_CODES:
        raise HTTPException(status_code=resp.status_code, detail="fallback")
    resp.raise_for_status()
    data = resp.json()
    return {"content": data.get("content") or [], "usage": data.get("usage") or {}}


async def native_stream(route: dict[str, str], body: dict[str, Any], sink, think_sink=None) -> dict[str, Any]:
    body = {**body, "stream": True}
    blocks: dict[int, dict[str, Any]] = {}
    pending_json: dict[int, str] = {}
    usage: dict[str, Any] = {}
    async with httpx.AsyncClient(timeout=None, trust_env=False) as client:
        async with client.stream(
            "POST",
            route["url"].rstrip("/") + "/messages",
            headers=native_headers(route),
            json=body,
        ) as resp:
            if resp.status_code in FALLBACK_CODES:
                raise HTTPException(status_code=resp.status_code, detail="fallback")
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                line = line.strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    ev = json.loads(data)
                except json.JSONDecodeError:
                    continue
                etype = ev.get("type")
                if etype == "message_start":
                    usage.update((ev.get("message") or {}).get("usage") or {})
                elif etype == "content_block_start":
                    idx = int(ev.get("index") or 0)
                    blocks[idx] = dict(ev.get("content_block") or {})
                    pending_json[idx] = ""
                elif etype == "content_block_delta":
                    idx = int(ev.get("index") or 0)
                    delta = ev.get("delta") or {}
                    blk = blocks.setdefault(idx, {"type": "text", "text": ""})
                    dtype = delta.get("type")
                    if dtype == "text_delta":
                        chunk = delta.get("text") or ""
                        blk["text"] = (blk.get("text") or "") + chunk
                        if chunk:
                            await sink(chunk)
                    elif dtype == "thinking_delta":
                        tchunk = delta.get("thinking") or ""
                        blk["thinking"] = (blk.get("thinking") or "") + tchunk
                        if tchunk and think_sink is not None:
                            await think_sink(tchunk)
                    elif dtype == "signature_delta":
                        blk["signature"] = (blk.get("signature") or "") + (delta.get("signature") or "")
                    elif dtype == "input_json_delta":
                        pending_json[idx] = pending_json.get(idx, "") + (delta.get("partial_json") or "")
                elif etype == "message_delta":
                    usage.update(ev.get("usage") or {})
                elif etype == "error":
                    raise RuntimeError(f"anthropic stream error: {str(ev)[:300]}")
    for idx, blk in blocks.items():
        if blk.get("type") == "tool_use" and pending_json.get(idx):
            try:
                blk["input"] = json.loads(pending_json[idx])
            except json.JSONDecodeError:
                blk["input"] = {}
    return {"content": [blocks[i] for i in sorted(blocks)], "usage": usage}


async def run_route_native(route: dict[str, str], messages: list[dict[str, str]], sink=None, think_sink=None) -> dict[str, Any]:
    """Claude 原生工具循环：thinking 块原样传回（带签名），每轮把缓存断点推到最新。"""
    system_texts, convo = to_anthropic(messages)
    defs = await mcp_tool_defs()
    tools = anthropic_tools(defs) if defs else None
    usage_rounds: list[dict[str, Any]] = []
    tools_used: list[str] = []
    content: list[dict[str, Any]] = []
    thinking_parts: list[str] = []
    for round_no in range(MCP_TOOL_ROUNDS + 1):
        mark_cache(convo)
        body = native_body(route, system_texts, convo, tools)
        if sink is not None:
            out = await native_stream(route, body, sink, think_sink)
        else:
            out = await native_complete(route, body)
        if out.get("usage"):
            usage_rounds.append(out["usage"])
        content = out.get("content") or []
        thinking_parts.extend(
            str(b.get("thinking") or "").strip()
            for b in content
            if isinstance(b, dict) and b.get("type") == "thinking" and str(b.get("thinking") or "").strip()
        )
        tool_uses = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_use"]
        if not tool_uses or not MCP or round_no >= MCP_TOOL_ROUNDS:
            break
        # 空 text 块回传会被 API 拒（流式下 text 块可能只开了头没内容）
        carry = [
            b for b in content
            if isinstance(b, dict) and not (b.get("type") == "text" and not (b.get("text") or "").strip())
        ]
        convo.append({"role": "assistant", "content": carry})
        results = []
        for tu in tool_uses:
            name = str(tu.get("name") or "")
            args = tu.get("input") if isinstance(tu.get("input"), dict) else {}
            try:
                result_text = await MCP.call(name, args)
            except Exception as exc:
                result_text = f"(tool {name} failed: {type(exc).__name__}: {exc})"
            tools_used.append(name)
            results.append({
                "type": "tool_result",
                "tool_use_id": tu.get("id") or name,
                "content": result_text[:MCP_RESULT_MAX],
            })
        convo.append({"role": "user", "content": results})
    text = "\n".join((b.get("text") or "") for b in content if isinstance(b, dict) and b.get("type") == "text").strip()
    if usage_rounds:
        first = usage_rounds[0]
        KA_STATE["last_prefix"] = (
            int(first.get("input_tokens") or 0)
            + int(first.get("cache_read_input_tokens") or 0)
            + int(first.get("cache_creation_input_tokens") or 0)
        )
    ka_touch(real=True)
    return {
        "text": text,
        "thinking": "\n\n".join(thinking_parts),
        "usage": merge_usage(usage_rounds),
        "tools_used": tools_used,
    }


async def run_route_openai(route: dict[str, str], messages: list[dict[str, str]], sink=None) -> dict[str, Any]:
    defs = await mcp_tool_defs()
    tools = openai_tools(defs) if defs else None
    convo: list[dict[str, Any]] = list(messages)
    usage_rounds: list[dict[str, Any]] = []
    tools_used: list[str] = []
    out: dict[str, Any] = {}
    for round_no in range(MCP_TOOL_ROUNDS + 1):
        if sink is not None and STREAM_OUTPUT:
            out = await stream_chat(route, convo, sink, tools=tools)
        else:
            out = await complete_chat(route, convo, tools=tools)
        if out.get("usage"):
            usage_rounds.append(out["usage"])
        calls = out.get("tool_calls") or []
        if not calls or not MCP or round_no >= MCP_TOOL_ROUNDS:
            break
        convo.append({"role": "assistant", "content": out.get("text") or None, "tool_calls": calls})
        for tc in calls:
            fn = tc.get("function") or {}
            name = str(fn.get("name") or "")
            try:
                args = json.loads(fn.get("arguments") or "{}")
                if not isinstance(args, dict):
                    args = {}
            except json.JSONDecodeError:
                args = {}
            try:
                result_text = await MCP.call(name, args)
            except Exception as exc:
                result_text = f"(tool {name} failed: {type(exc).__name__}: {exc})"
            tools_used.append(name)
            convo.append({
                "role": "tool",
                "tool_call_id": tc.get("id") or name,
                "content": result_text[:MCP_RESULT_MAX],
            })
    return {"text": out.get("text") or "", "usage": merge_usage(usage_rounds), "tools_used": tools_used}


def merge_usage(rounds: list[dict[str, Any]]) -> dict[str, Any]:
    total: dict[str, Any] = {}
    for usage in rounds:
        for key, value in usage.items():
            if isinstance(value, (int, float)):
                total[key] = total.get(key, 0) + value
    return total


# ---- cache keepalive 心跳 ---------------------------------------------------
# 借鉴自「Prompt Cache + 后端心跳保活」方案：1h TTL 下，快到期时用一个不入库的
# 临时请求把稳定前缀读一遍（命中即续 TTL），比冷启动整段重写便宜一个量级。
# 铁律：心跳消息不写 relay.db、请求参数（thinking/工具/system）必须和真实聊天
# 完全一致——用同一套 build/native_body，天然一致。

KA_STATE: dict[str, Any] = {"last_real": None, "last_touch": None, "bad": 0, "events": []}


def ka_load() -> None:
    """启动时从 config 恢复心跳状态（重启别把 last_real 清零，不然自动心跳直接哑火）。"""
    cfg = load_config()
    saved = cfg.get("ka_state")
    if isinstance(saved, dict):
        KA_STATE["last_real"] = saved.get("last_real")
        KA_STATE["last_touch"] = saved.get("last_touch")
        KA_STATE["last_prefix"] = saved.get("last_prefix")
        KA_STATE["events"] = saved.get("events") if isinstance(saved.get("events"), list) else []


def ka_touch(real: bool, event: dict[str, Any] | None = None) -> None:
    now = time.time()
    KA_STATE["last_touch"] = now
    if real:
        KA_STATE["last_real"] = now
        KA_STATE["bad"] = 0  # 真实聊天通了=上游活着，自动解除心跳熔断
    if event is not None:
        KA_STATE["events"] = (KA_STATE["events"] + [event])[-50:]
    try:
        cfg = load_config()
        cfg["ka_state"] = {
            "last_real": KA_STATE["last_real"],
            "last_touch": KA_STATE["last_touch"],
            "last_prefix": KA_STATE.get("last_prefix"),
            "events": KA_STATE["events"][-20:],
        }
        save_config(cfg)
    except Exception:
        pass


ka_load()


async def relay_brain() -> str:
    try:
        async with httpx.AsyncClient(timeout=10, trust_env=False) as client:
            resp = await client.get(
                f"{RELAY_URL}/app/brain",
                headers={"Authorization": f"Bearer {RELAY_SECRET}"},
            )
        return str((resp.json() or {}).get("target") or "")
    except Exception:
        return ""


async def keepalive_due() -> str:
    """返回空串=该打心跳，否则返回跳过原因。"""
    if not keepalive_enabled():
        return "disabled"
    if CACHE_TTL != "1h":
        return "cache_ttl_not_1h"
    if KA_STATE["bad"] >= 2:
        return "circuit_broken"
    last_real = KA_STATE["last_real"]
    if not last_real:
        return "no_real_chat_since_start"
    # prompt 低于 Opus 缓存门槛（4096 tok）时上游根本没建缓存——心跳纯烧钱
    last_prefix = int(KA_STATE.get("last_prefix") or 0)
    if last_prefix and last_prefix < 4200:
        return "prefix_below_cache_min"
    now = time.time()
    if now - last_real > KEEPALIVE_MAX_IDLE_H * 3600:
        return "idle_too_long"
    if KA_STATE["last_touch"] and now - KA_STATE["last_touch"] < KEEPALIVE_AFTER_MIN * 60:
        return "not_due"
    if await relay_brain() != "loop":
        return "brain_not_loop"
    return ""


async def keepalive_beat(force: bool = False) -> dict[str, Any]:
    routes = main_chain()
    route = routes[0] if routes else None
    if not route or "claude" not in str(route.get("model") or "").lower():
        return {"ok": False, "reason": "no_claude_route"}
    session_id = active_session_id()
    # 和真实聊天同一条组装路径 → 前缀逐字一致；临时消息不落库
    messages = build_messages(KEEPALIVE_TEXT, session_id=session_id, use_context=True)
    system_texts, convo = to_anthropic(messages)
    defs = await mcp_tool_defs()
    tools = anthropic_tools(defs) if defs else None
    mark_cache(convo)
    body = native_body(route, system_texts, convo, tools)
    try:
        out = await native_complete(route, body)
    except Exception as exc:
        KA_STATE["bad"] += 1
        event = {"at": now_iso(), "status": "error", "error": f"{type(exc).__name__}: {exc}"[:200]}
        # 失败也推 last_touch：等满整个间隔再重试，别 5 分钟连环撞墙
        ka_touch(real=False, event=event)
        return {"ok": False, **event}
    usage = out.get("usage") or {}
    read = int(usage.get("cache_read_input_tokens") or 0)
    written = int(usage.get("cache_creation_input_tokens") or 0)
    status = "hit" if read > 0 else ("write" if written > 0 else "bad")
    KA_STATE["bad"] = 0 if status in {"hit", "write"} else KA_STATE["bad"] + 1
    event = {"at": now_iso(), "status": status, "read": read, "written": written,
             "output": int(usage.get("output_tokens") or 0), "forced": force}
    ka_touch(real=False, event=event)
    return {"ok": True, **event}


async def keepalive_watcher() -> None:
    while True:
        await asyncio.sleep(300)
        try:
            if not await keepalive_due():
                await keepalive_beat()
        except Exception:
            pass


async def run_model(messages: list[dict[str, str]], *, stream_id: str = "", session_id: str = "", emit_stream: bool = False) -> dict[str, Any]:
    tried = []
    last_error = ""
    sink = None
    think_sink = None
    if emit_stream and STREAM_OUTPUT:
        async def sink(chunk: str) -> None:
            await relay_out({
                "type": "reply_delta",
                "stream_id": stream_id,
                "text": chunk,
                "done": False,
                "api_session": session_id,
            })

        async def think_sink(chunk: str) -> None:
            await relay_out({
                "type": "thinking_delta",
                "stream_id": stream_id,
                "text": chunk,
                "done": False,
                "api_session": session_id,
            })
    for route in main_chain():
        tried.append(route.get("model"))
        try:
            # Claude 走原生 /v1/messages（自控 cache_control，缓存真命中）；其余走 OpenAI 格式
            if "claude" in str(route.get("model") or "").lower():
                out = await run_route_native(route, messages, sink, think_sink)
            else:
                out = await run_route_openai(route, messages, sink)
            out["model"] = route.get("model")
            out["tried"] = tried[:-1]
            return out
        except HTTPException as exc:
            if exc.status_code not in FALLBACK_CODES:
                raise
            last_error = f"HTTP {exc.status_code}"
        except Exception as exc:
            last_error = f"{type(exc).__name__}: {exc}"
    return {"text": "", "error": last_error or "all models failed", "tried": tried}


async def handle_ingest(text: str, msg_id: int | None, session_id: str, *, dry: bool = False) -> dict[str, Any]:
    stream_id = "api-" + uuid.uuid4().hex[:16]
    messages = build_messages(text, before_id=msg_id, session_id=session_id, use_context=True)
    out = await run_model(messages, stream_id=stream_id, session_id=session_id, emit_stream=not dry)
    reply = (out.get("text") or "").strip()
    if not reply:
        reply = "(The API loop did not produce a reply.)"
    meta = {
        "runtime": "api_loop",
        "model": out.get("model"),
        "fallback_from": out.get("tried") or [],
        "usage": out.get("usage") or {},
        "tools_used": out.get("tools_used") or [],
        "session": session_id,
    }
    asyncio.create_task(summarize_pending(session_id or "_default"))
    if dry:
        return {"ok": True, "reply": reply, "api": meta}
    if STREAM_OUTPUT and (out.get("thinking") or "").strip():
        # 思考块先定稿（relay 存成 kind=thinking，手机上合拢成思考条），再发正文
        await relay_out({
            "type": "thinking_delta",
            "stream_id": stream_id,
            "done": True,
            "final_text": out.get("thinking") or "",
            "api_session": session_id,
        })
    if STREAM_OUTPUT:
        ok, body = await relay_out({
            "type": "reply_delta",
            "stream_id": stream_id,
            "done": True,
            "final_text": reply,
            "api": meta,
            "api_session": session_id,
        })
    else:
        ok, body = await relay_out({"type": "reply", "text": reply, "api": meta, "api_session": session_id})
    return {"ok": ok, "relay": body, "api": meta}


app = FastAPI(title="companion-api-loop")


@app.on_event("startup")
async def _startup() -> None:
    asyncio.create_task(keepalive_watcher())


@app.get("/loop/keepalive")
async def keepalive_state():
    reason = await keepalive_due()
    return {
        "enabled": keepalive_enabled(),
        "cache_ttl": CACHE_TTL,
        "due": not reason,
        "skip_reason": reason,
        "last_real": KA_STATE["last_real"],
        "last_touch": KA_STATE["last_touch"],
        "last_prefix": KA_STATE.get("last_prefix"),
        "bad_count": KA_STATE["bad"],
        "events": KA_STATE["events"][-10:],
    }


@app.post("/loop/keepalive/run")
async def keepalive_run():
    """手动打一针（跳过 due 检查，测试用）。"""
    return await keepalive_beat(force=True)


@app.get("/healthz")
async def healthz():
    return {
        "ok": True,
        "models": [r.get("model") for r in main_chain()],
        "history_n": history_n(),
        "relay_db": RELAY_DB,
        "relay_secret_loaded": bool(RELAY_SECRET),
        "mcp_url": MCP_URL,
        "tools_enabled": tools_enabled(),
    }


# 估价（USD/百万 token，Anthropic 官方 Opus 档；中转按量倍率不同，仅供相对参考）
DEFAULT_PRICES = {"input": 15.0, "output": 75.0, "cache_read": 1.5, "cache_write_5m": 18.75, "cache_write_1h": 30.0}


def usage_normalize(usage: dict[str, Any]) -> dict[str, int]:
    read = int(usage.get("cache_read_input_tokens") or 0)
    written = int(usage.get("cache_creation_input_tokens") or 0)
    if not written:
        written = int(usage.get("claude_cache_creation_1_h_tokens") or 0) + int(usage.get("claude_cache_creation_5_m_tokens") or 0)
    raw_in = int(usage.get("input_tokens") or usage.get("prompt_tokens") or 0)
    # OpenAI 路径的 prompt_tokens 含缓存部分，原生 input_tokens 不含——尽量归一成"全价输入"
    plain_in = max(0, raw_in - read - written) if raw_in > read + written else raw_in
    out = max(int(usage.get("output_tokens") or 0), int(usage.get("completion_tokens") or 0))
    return {"input": plain_in, "output": out, "cache_read": read, "cache_write": written}


def usage_cost_usd(n: dict[str, int]) -> float:
    cfg_prices = load_config().get("prices")
    prices = {**DEFAULT_PRICES, **(cfg_prices if isinstance(cfg_prices, dict) else {})}
    write_price = prices["cache_write_1h"] if CACHE_TTL == "1h" else prices["cache_write_5m"]
    return (
        n["input"] * prices["input"]
        + n["output"] * prices["output"]
        + n["cache_read"] * prices["cache_read"]
        + n["cache_write"] * write_price
    ) / 1_000_000


@app.get("/loop/stats")
async def loop_stats():
    """API 身体用量统计：扫 relay.db 里 api_loop 的回复 meta.usage 聚合。"""
    rows = []
    path = Path(RELAY_DB)
    if path.exists():
        with sqlite3.connect(str(path)) as conn:
            conn.row_factory = sqlite3.Row
            # api_loop 的 meta 嵌在 'api' 键下（relay 存 body 剩余字段）；兼容两种路径
            rows = conn.execute(
                "SELECT id, ts, meta FROM messages "
                "WHERE kind = 'reply' AND (json_extract(meta, '$.api.runtime') = 'api_loop' "
                "OR json_extract(meta, '$.runtime') = 'api_loop') "
                "ORDER BY id DESC LIMIT 500"
            ).fetchall()
    total = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}
    recent = []
    count = 0
    for r in rows:
        try:
            meta = json.loads(r["meta"] or "{}")
        except json.JSONDecodeError:
            continue
        if isinstance(meta.get("api"), dict):
            meta = meta["api"]
        usage = meta.get("usage")
        if not isinstance(usage, dict) or not usage:
            continue
        n = usage_normalize(usage)
        count += 1
        for k in total:
            total[k] += n[k]
        if len(recent) < 20:
            recent.append({
                "id": r["id"], "ts": r["ts"], "model": meta.get("model"),
                "tools": meta.get("tools_used") or [], **n,
                "cost_usd": round(usage_cost_usd(n), 5),
            })
    total_cost = usage_cost_usd(total)
    ka_events = KA_STATE["events"]
    ka_cost = sum(
        usage_cost_usd({"input": 0, "output": e.get("output", 0), "cache_read": e.get("read", 0), "cache_write": e.get("written", 0)})
        for e in ka_events if e.get("status") in {"hit", "write"}
    )
    denom = total["input"] + total["cache_read"] + total["cache_write"]
    return {
        "messages": count,
        "total": total,
        "total_cost_usd": round(total_cost, 4),
        "avg_per_message": {
            **{k: (round(v / count) if count else 0) for k, v in total.items()},
            "cost_usd": round(total_cost / count, 5) if count else 0,
        },
        "cache_hit_rate": round(total["cache_read"] / denom, 3) if denom else 0,
        "keepalive": {"beats": len(ka_events), "cost_usd": round(ka_cost, 4), "bad_count": KA_STATE["bad"]},
        "cache_ttl": CACHE_TTL,
        "prices_note": "USD，按 Anthropic 官方价估算，中转实际计费可能有倍率",
        "recent": recent,
    }


@app.get("/loop/config")
async def loop_config():
    return public_config()


@app.post("/loop/config")
async def loop_config_update(request: Request):
    return update_config(await request.json())


@app.get("/loop/sessions")
async def loop_sessions():
    return sessions_public()


@app.post("/loop/sessions")
async def loop_sessions_create(request: Request):
    body = await request.json()
    row = create_session(
        title=str(body.get("title") or "New chat"),
        since_id=int(body.get("since_id") or 0),
        activate=bool(body.get("activate", True)),
    )
    return {**sessions_public(), "created": row}


@app.patch("/loop/sessions/{session_id}")
async def loop_sessions_patch(session_id: str, request: Request):
    return patch_session(session_id, await request.json())


@app.post("/loop/chat")
async def loop_chat(request: Request):
    body = await request.json()
    text = str(body.get("text") or body.get("message") or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="empty text")
    session_id = str(body.get("session_id") or body.get("api_session") or active_session_id() or "").strip()
    messages = build_messages(text, before_id=None, session_id=session_id, use_context=bool(body.get("use_context", True)))
    out = await run_model(messages, emit_stream=False)
    asyncio.create_task(summarize_pending(session_id or "_default"))
    return {"ok": True, "reply": out.get("text") or "", "api": out}


@app.post("/loop/ingest")
async def loop_ingest(request: Request):
    body = await request.json()
    text = str(body.get("text") or body.get("message") or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="empty text")
    msg_id = body.get("id")
    try:
        before_id = int(msg_id) if msg_id is not None else None
    except Exception:
        before_id = None
    session_id = str(body.get("session_id") or body.get("api_session") or active_session_id() or "").strip()
    dry = bool(body.get("dry"))
    return await handle_ingest(text, before_id, session_id, dry=dry)


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=LOOP_PORT)
