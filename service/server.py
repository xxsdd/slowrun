"""Optional personal voice/review service. Python standard library only.

No upstream request is made at startup. Provider calls require an authenticated,
explicit POST. Location coordinates are never accepted by the review endpoint.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import html
import json
import math
import os
import re
import ssl
import threading
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VOICES = {"zh-CN-XiaoxiaoNeural", "zh-CN-YunxiNeural", "zh-CN-XiaoyiNeural"}
MAX_BODY = 16_384


@dataclass(frozen=True)
class Config:
    token: str
    cache_dir: Path
    speech_key: str = ""
    speech_region: str = ""
    ai_key: str = ""
    ai_base_url: str = "https://api.openai.com/v1"
    ai_model: str = ""
    allow_local_ai: bool = False
    ai_thinking: str = ""

    @classmethod
    def from_env(cls) -> Config:
        return cls(token=os.getenv("SERVICE_ACCESS_TOKEN", ""),
                   cache_dir=Path(os.getenv("VOICE_CACHE_DIR", str(Path(__file__).parent / ".voice-cache"))),
                   speech_key=os.getenv("AZURE_SPEECH_KEY", ""), speech_region=os.getenv("AZURE_SPEECH_REGION", ""),
                   ai_key=os.getenv("AI_API_KEY", ""), ai_base_url=os.getenv("AI_BASE_URL", "https://api.openai.com/v1"),
                   ai_model=os.getenv("AI_MODEL", ""), allow_local_ai=os.getenv("AI_ALLOW_LOCAL_HTTP") == "1",
                   ai_thinking=os.getenv("AI_THINKING", ""))


class PublicError(Exception):
    def __init__(self, status: int, message: str):
        self.status = status
        self.message = message
        super().__init__(message)


def transport(url: str, headers: dict, body: bytes, timeout: float) -> tuple[bytes, str]:
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = response.read(5_000_001)
            if len(data) > 5_000_000:
                raise PublicError(502, "Upstream response too large")
            return data, response.headers.get_content_type()
    except urllib.error.HTTPError as exc:
        # Never expose upstream bodies, credentials or quota details in logs.
        if exc.code == 429:
            raise PublicError(429, "Provider rate or quota limit; not retried") from None
        raise PublicError(502, "Provider request failed; not retried") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise PublicError(504, "Provider connection failed; not retried") from None


def validate_summary(body: dict) -> dict:
    fields = {"plan", "distance_m", "duration_s", "splits_s", "effort", "completed"}
    if set(body) != fields:
        raise PublicError(422, "Only aggregate workout fields are accepted; no route data")
    if not isinstance(body["plan"], str) or not isinstance(body["effort"], str) or body["plan"] not in {"beginner", "week2", "week3", "week4", "week5", "week6", "week7", "week8", "week9", "freeRun", "threeK", "fiveK"} or body["effort"] not in {"easy", "right", "hard", "unspecified"}:
        raise PublicError(422, "Invalid plan or effort")
    for name, limit in (("distance_m", 100_000), ("duration_s", 86_400)):
        value = body[name]
        if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= limit:
            raise PublicError(422, "Invalid aggregate metric")
    splits = body["splits_s"]
    if not isinstance(splits, list) or len(splits) > 100 or any(type(x) not in (int, float) or not math.isfinite(x) or not 0 < x <= 10_000 for x in splits):
        raise PublicError(422, "Invalid kilometer splits")
    if type(body["completed"]) is not bool:
        raise PublicError(422, "Invalid completion state")
    return body


class Service:
    def __init__(self, config: Config, upstream=transport):
        self.config = config
        self.upstream = upstream
        self.voice_lock = threading.Lock()

    def health(self) -> dict:
        return {"ok": True, "speech_configured": bool(self.config.speech_key and self.config.speech_region),
                "ai_configured": bool(self.config.ai_key and self.config.ai_model)}

    def voice(self, body: dict) -> tuple[bytes, str]:
        if set(body) != {"text", "voice"} or not isinstance(body["text"], str) or not isinstance(body["voice"], str) or not 1 <= len(body["text"].strip()) <= 300 or body["voice"] not in VOICES:
            raise PublicError(422, "Expected short text and a supported Microsoft voice")
        region = self.config.speech_region
        if not self.config.speech_key or not re.fullmatch(r"[a-z][a-z0-9-]{1,48}", region):
            raise PublicError(503, "Microsoft Speech is not configured")
        text, voice = body["text"].strip(), body["voice"]
        digest = hashlib.sha256((voice + "\0" + text).encode("utf-8")).hexdigest()
        cache = self.config.cache_dir / (digest + ".mp3")
        # Serialize cache misses so simultaneous identical requests cannot double-spend.
        with self.voice_lock:
            if cache.is_file():
                return cache.read_bytes(), "audio/mpeg"
            temporary = cache.with_suffix(".pending")
            if temporary.exists():
                raise PublicError(503, "Previous paid audio is pending inspection; provider was not called again")
            self.config.cache_dir.mkdir(parents=True, exist_ok=True)
            ssml = (f'<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="zh-CN">'
                    f'<voice name="{voice}">{html.escape(text)}</voice></speak>').encode("utf-8")
            headers = {"Ocp-Apim-Subscription-Key": self.config.speech_key, "Content-Type": "application/ssml+xml",
                       "X-Microsoft-OutputFormat": "audio-24khz-48kbitrate-mono-mp3", "User-Agent": "SlowRunPersonal/1"}
            audio, mime = self.upstream(f"https://{region}.tts.speech.microsoft.com/cognitiveservices/v1", headers, ssml, 10)
            if not mime.startswith("audio/") or not audio:
                raise PublicError(502, "Invalid Microsoft audio response; not retried")
            temporary.write_bytes(audio)
            temporary.replace(cache)
            return audio, "audio/mpeg"

    def analysis(self, body: dict) -> tuple[bytes, str]:
        summary = validate_summary(body)
        if not self.config.ai_key or not self.config.ai_model:
            raise PublicError(503, "AI provider is not configured")
        if self.config.ai_thinking not in {"", "enabled", "disabled"}:
            raise PublicError(503, "AI_THINKING must be empty, enabled or disabled")
        base = urllib.parse.urlsplit(self.config.ai_base_url)
        local = self.config.allow_local_ai and base.hostname in {"localhost", "127.0.0.1", "::1"}
        if not base.hostname or base.username or base.password or base.query or base.fragment or (base.scheme != "https" and not (base.scheme == "http" and local)):
            raise PublicError(503, "AI base URL must use HTTPS")
        prompt = ("你是中文新手跑步记录解读助手。只依据提供的主要训练统计和体感，用不超过180个汉字给出一段复盘。"
                  "跑走计划内步行不是掉速失败；completed=false是提前结束，不能说完成了目标。"
                  "没有心率、路况和伤病数据，不能编造这些信息，也不能诊断或要求用户在疲劳时加速。"
                  "不承诺提高成绩。建议以重复当前阶段、舒服节奏、必要时步行和安排休息为主。"
                  "只输出纯文本建议，不要表格。")
        payload = {"model": self.config.ai_model, "messages": [{"role": "system", "content": prompt},
                   {"role": "user", "content": json.dumps(summary, ensure_ascii=False, allow_nan=False)}],
                   "max_tokens": 450, "stream": False}
        if self.config.ai_thinking:
            payload["thinking"] = {"type": self.config.ai_thinking}
        data, _ = self.upstream(self.config.ai_base_url.rstrip("/") + "/chat/completions",
                                {"Authorization": "Bearer " + self.config.ai_key, "Content-Type": "application/json"},
                                json.dumps(payload, ensure_ascii=False).encode("utf-8"), 30)
        try:
            value = json.loads(data)["choices"][0]["message"]["content"]
            if not isinstance(value, str) or not value.strip():
                raise ValueError()
        except (ValueError, KeyError, IndexError, TypeError):
            raise PublicError(502, "AI returned no usable text; not retried") from None
        return json.dumps({"analysis": value.strip()[:1_500]}, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8"


class Handler(BaseHTTPRequestHandler):
    server_version = "SlowRun/1"

    def log_message(self, *_):
        pass  # No request paths, payloads, tokens or provider responses in access logs.

    def reply(self, status: int, data: bytes, mime="application/json; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # A disconnected phone must not discard already generated audio.

    def do_GET(self):
        if self.path != "/health":
            self.reply(404, b'{"error":"Not found"}')
            return
        self.reply(200, json.dumps(self.server.service.health()).encode())

    def do_POST(self):
        try:
            auth = self.headers.get("Authorization", "")
            expected = "Bearer " + self.server.service.config.token
            if not self.server.service.config.token or not hmac.compare_digest(auth.encode(), expected.encode()):
                raise PublicError(401, "Unauthorized")
            if self.path not in {"/v1/voice", "/v1/analysis"}:
                raise PublicError(404, "Not found")
            if self.headers.get_content_type() != "application/json":
                raise PublicError(415, "Expected application/json")
            length = self.headers.get("Content-Length", "")
            if not length.isdigit() or len(length) > 5 or not 0 < int(length) <= MAX_BODY:
                raise PublicError(413, "Request body missing or too large")
            self.connection.settimeout(10)
            try:
                body = json.loads(self.rfile.read(int(length)).decode("utf-8"))
            except (ValueError, UnicodeError):
                raise PublicError(400, "Invalid JSON") from None
            if not isinstance(body, dict):
                raise PublicError(422, "Expected JSON object")
            service = self.server.service
            data, mime = service.voice(body) if self.path == "/v1/voice" else service.analysis(body)
            self.reply(200, data, mime)
        except PublicError as exc:
            self.reply(exc.status, json.dumps({"error": exc.message}).encode())
        except (TimeoutError, OSError):
            self.reply(503, b'{"error":"Service temporarily unavailable; not retried"}')
        except Exception:
            self.reply(500, b'{"error":"Internal service error"}')


def make_server(config: Config, host="127.0.0.1", port=8787, upstream=transport):
    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    server.service = Service(config, upstream)
    return server


def load_env(path: Path):
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        value = line.strip()
        if not value or value.startswith("#"):
            continue
        name, sep, content = value.partition("=")
        if not sep or not re.fullmatch(r"[A-Z][A-Z0-9_]*", name.strip()):
            raise ValueError("Invalid env-file entry")
        os.environ.setdefault(name.strip(), content.strip().strip('"').strip("'"))


def main():
    parser = argparse.ArgumentParser(description="SlowRun optional personal service")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--env-file", type=Path)
    parser.add_argument("--cert", type=Path)
    parser.add_argument("--key", type=Path)
    args = parser.parse_args()
    if args.env_file:
        load_env(args.env_file)
    config = Config.from_env()
    if len(config.token) < 24:
        parser.error("Set SERVICE_ACCESS_TOKEN to a private random token of at least 24 characters")
    if bool(args.cert) != bool(args.key):
        parser.error("Provide both --cert and --key")
    server = make_server(config, args.host, args.port)
    if args.cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.cert, args.key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print("SlowRun service ready. Provider calls occur only on authenticated POST requests.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
