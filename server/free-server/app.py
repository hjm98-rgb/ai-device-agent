"""免费小模型服务器：把本机 Ollama 包装成 OpenAI 兼容接口，任何人无需密钥即可使用。

启动：
    OLLAMA=http://127.0.0.1:11434 uvicorn app:app --host 0.0.0.0 --port 8080
"""
import json
import os
import time
from collections import defaultdict

import httpx
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

OLLAMA = os.environ.get("OLLAMA", "http://127.0.0.1:11434")
PORT = int(os.environ.get("PORT", "8080"))

# 允许对外提供的模型（名字 -> 展示信息）
CATALOG = {
    "qwen2.5:0.5b": {"name": "通义千问 0.5B", "note": "最轻量，秒回，适合闲聊", "size": "400MB"},
    "qwen2.5:1.5b": {"name": "通义千问 1.5B", "note": "中文最顺，日常够用", "size": "1GB"},
    "llama3.2:1b":  {"name": "Llama 3.2 1B", "note": "英文强，速度快", "size": "1.3GB"},
    "qwen2.5:3b":   {"name": "通义千问 3B", "note": "更聪明，稍慢", "size": "2GB"},
    "deepseek-r1:1.5b": {"name": "DeepSeek R1 1.5B", "note": "会写思考过程", "size": "1.1GB"},
}

app = FastAPI(title="Free Small Model Server")
app.add_cors = None
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_hits = defaultdict(list)


def rate_ok(ip: str) -> bool:
    now = time.time()
    _hits[ip] = [t for t in _hits[ip] if now - t < 60]
    if len(_hits[ip]) >= 40:
        return False
    _hits[ip].append(now)
    return True


@app.get("/health")
async def health():
    try:
        async with httpx.AsyncClient(timeout=6) as c:
            r = await c.get(f"{OLLAMA}/api/tags")
            tags = r.json().get("models", [])
        return {"ok": True, "upstream": OLLAMA, "loaded": len(tags)}
    except Exception as e:
        return JSONResponse({"ok": False, "error": str(e)}, status_code=503)


@app.get("/api/models")
async def models():
    available = set()
    try:
        async with httpx.AsyncClient(timeout=8) as c:
            r = await c.get(f"{OLLAMA}/api/tags")
            for m in r.json().get("models", []):
                available.add(m.get("name"))
    except Exception:
        pass

    out = []
    for mid, meta in CATALOG.items():
        present = any(a == mid for a in available)
        out.append({
            "id": mid,
            "name": meta["name"],
            "note": meta["note"] + ("" if present else "（未下载）"),
            "size": meta["size"],
            "ready": present,
        })
    return {"models": out}


@app.post("/v1/chat/completions")
async def chat(request: Request):
    ip = request.client.host if request.client else "?"
    if not rate_ok(ip):
        return JSONResponse({"error": {"message": "请求太快了，歇一分钟再来"}}, status_code=429)

    body = await request.json()
    model = body.get("model") or "qwen2.5:1.5b"
    if model not in CATALOG:
        model = "qwen2.5:1.5b"
    body["model"] = model
    if body.get("max_tokens") is None:
        body["max_tokens"] = 1024
    stream = bool(body.get("stream"))

    url = f"{OLLAMA}/v1/chat/completions"

    if not stream:
        try:
            async with httpx.AsyncClient(timeout=180) as c:
                r = await c.post(url, json=body)
                return JSONResponse(r.json(), status_code=r.status_code)
        except Exception as e:
            return JSONResponse({"error": {"message": f"模型服务出错：{e}"}}, status_code=502)

    async def gen():
        try:
            async with httpx.AsyncClient(timeout=180) as c:
                async with c.stream("POST", url, json=body) as r:
                    async for line in r.aiter_lines():
                        if line:
                            yield line + "\n\n"
        except Exception as e:
            yield "data: " + json.dumps({"error": {"message": str(e)}}, ensure_ascii=False) + "\n\n"

    return StreamingResponse(gen(), media_type="text/event-stream")
