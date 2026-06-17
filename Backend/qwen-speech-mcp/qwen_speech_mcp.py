#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


APP_DIR = Path(os.environ.get("AGENT_VOICE_HOME", Path.home() / "Library" / "Application Support" / "AgentVoiceBar"))
OUT_DIR = APP_DIR / "out"
PRONUNCIATIONS_FILE = APP_DIR / "pronunciations.json"
CONFIG_FILE = APP_DIR / "config.json"
STATE_FILE = APP_DIR / "state.json"
QUEUE_FILE = APP_DIR / "queue.jsonl"
MODEL = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
VOICE = "Chelsie"
LANG = "English"
SPEED = "1.35"
TEMPERATURE = "0.45"
TOP_P = "0.85"
GENERATION_QUEUE = queue.Queue()

DEFAULT_CONFIG = {
    "mode": "autoplay",
    "voice": VOICE,
    "speed": SPEED,
    "replay_speed": "1.00",
    "temperature": TEMPERATURE,
    "top_p": TOP_P,
    "max_chars": 1200,
}

NORMALIZATIONS = {
    "SSH": "S S H",
    "MCP": "M C P",
    "API": "A P I",
    "ASR": "A S R",
    "TTS": "T T S",
    "STT": "S T T",
    "JSON": "J son",
    "URL": "U R L",
    "HTTP": "H T T P",
    "HTTPS": "H T T P S",
    "CLI": "C L I",
    "UI": "U I",
    "Qwen": "Quen",
    "qwen": "Quen",
    "Codex": "Co dex",
    "Claude": "Claude",
    "Spokenly": "Spokenly",
    "Glaido": "Glide oh",
    "Gliado": "Glide oh",
    "localhost": "local host",
    "Homebrew": "Home brew",
    "LaunchAgent": "Launch Agent",
    "LaunchAgents": "Launch Agents",
    "launchctl": "launch control",
    "mlx": "M L X",
    "MLX": "M L X",
    "Qwen3": "Quen three",
    "Qwen3-TTS": "Quen three T T S",
    "qwen_speech": "Quen speech",
    "spokenly": "Spokenly",
    "mcp__qwen_speech__speak_text": "Quen speech, speak text",
    "mcp__spokenly__ask_user_dictation": "Spokenly, ask user dictation",
}


def load_user_pronunciations():
    try:
        if PRONUNCIATIONS_FILE.exists():
            data = json.loads(PRONUNCIATIONS_FILE.read_text())
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
    except Exception:
        return {}
    return {}


def read_json(path, fallback):
    try:
        if path.exists():
            data = json.loads(path.read_text())
            if isinstance(data, dict):
                return {**fallback, **data}
    except Exception:
        pass
    return dict(fallback)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def load_config():
    config = read_json(CONFIG_FILE, DEFAULT_CONFIG)
    if config.get("mode") not in {"autoplay", "notify", "silent"}:
        config["mode"] = "autoplay"
    return config


def publish_state(item):
    updated_at = item.get("ready_at") or item.get("created_at") or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    state = {
        "last": item,
        "updated_at": updated_at,
        "config": load_config(),
    }
    write_json(STATE_FILE, state)
    with QUEUE_FILE.open("a") as f:
        f.write(json.dumps(item, sort_keys=True) + "\n")


def notify(title, message):
    script = (
        'display notification '
        + json.dumps(message[:220])
        + ' with title '
        + json.dumps(title)
        + ' subtitle "Agent Voice Bar"'
    )
    subprocess.Popen(["/usr/bin/osascript", "-e", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def apply_phrase_map(text, phrase_map):
    for src in sorted(phrase_map, key=len, reverse=True):
        dst = phrase_map[src]
        if not src:
            continue
        pattern = re.compile(rf"(?<![A-Za-z0-9]){re.escape(src)}(?![A-Za-z0-9])")
        text = pattern.sub(dst, text)
    return text


def spell_acronyms(text):
    def repl(match):
        token = match.group(0)
        return " ".join(token)

    return re.sub(r"\b[A-Z]{2,6}\b", repl, text)


def soften_code_tokens(text):
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"https?://", "", text)
    text = text.replace("127.0.0.1", "one twenty seven dot zero dot zero dot one")
    text = text.replace("::1", "I P v six local host")
    text = text.replace("_", " ")
    text = text.replace("/", " slash ")
    text = text.replace("\\", " slash ")
    text = text.replace("~", "home")
    text = re.sub(r"(?<=[a-z])-(?=[a-z])", " ", text)
    text = re.sub(r"(?<=[A-Za-z])\.(?=[A-Za-z])", " dot ", text)
    return text


def normalize_for_tts(text):
    text = text.replace("local-only", "local only")
    text = text.replace("text-to-speech", "text to speech")
    text = text.replace("speech-to-text", "speech to text")
    text = apply_phrase_map(text, {**NORMALIZATIONS, **load_user_pronunciations()})
    text = soften_code_tokens(text)
    text = spell_acronyms(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def response(req_id, result=None, error=None):
    payload = {"jsonrpc": "2.0", "id": req_id}
    if error is not None:
        payload["error"] = error
    else:
        payload["result"] = result
    return payload


def initialize(req_id):
    return response(
        req_id,
        {
            "protocolVersion": "2025-11-25",
            "serverInfo": {"name": "qwen_speech", "version": "1.0.0"},
            "capabilities": {"tools": {}},
        },
    )


def tools_list(req_id):
    return response(
        req_id,
        {
            "tools": [
                {
                    "name": "speak_text",
                    "description": "Submit an agent inbox message and render it for local speech playback when enabled.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "text": {
                                "type": "string",
                                "description": "Message body to store in the inbox and render as speech.",
                            },
                            "title": {
                                "type": "string",
                                "description": "Optional short title for the inbox message.",
                            },
                            "source": {
                                "type": "string",
                                "description": "Optional agent/source name, such as Codex, Claude, or Ubuntu.",
                            },
                            "priority": {
                                "type": "string",
                                "description": "Optional priority label: low, normal, high, or urgent.",
                            },
                        },
                        "required": ["text"],
                    },
                }
            ]
        },
    )


def generate_and_deliver(item):
    wav_path = Path(item["file"])
    try:
        if not wav_path.exists():
            item["status"] = "generating"
            publish_state(item)
            cmd = [
                str(APP_DIR / ".venv" / "bin" / "mlx_audio.tts.generate"),
                "--model",
                MODEL,
                "--text",
                item["speech_text"],
                "--voice",
                item["voice"],
                "--lang_code",
                LANG,
                "--speed",
                item["speed"],
                "--temperature",
                item["temperature"],
                "--top_p",
                item["top_p"],
                "--output_path",
                str(OUT_DIR),
                "--file_prefix",
                wav_path.stem,
                "--join_audio",
            ]
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        item["status"] = "ready"
        item["ready_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        publish_state(item)
    except Exception as exc:
        item["status"] = "failed"
        item["error"] = str(exc)
        item["ready_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        publish_state(item)


def generation_worker():
    while True:
        item = GENERATION_QUEUE.get()
        try:
            generate_and_deliver(item)
        finally:
            GENERATION_QUEUE.task_done()


def clean_label(value, fallback, max_len=80):
    value = " ".join(str(value or "").split())
    return (value or fallback)[:max_len]


def synthesize_and_play(text, metadata=None):
    metadata = metadata or {}
    text = " ".join((text or "").split())
    if not text:
        raise ValueError("text is required")
    config = load_config()
    max_chars = int(config.get("max_chars") or DEFAULT_CONFIG["max_chars"])
    if len(text) > max_chars:
        text = text[:max_chars]
    speech_text = normalize_for_tts(text)
    voice = str(config.get("voice") or VOICE)
    speed = str(config.get("speed") or SPEED)
    temperature = str(config.get("temperature") or TEMPERATURE)
    top_p = str(config.get("top_p") or TOP_P)
    mode = str(config.get("mode") or "autoplay")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(f"{voice}|{speed}|{temperature}|{top_p}|{speech_text}".encode()).hexdigest()[:16]
    prefix = f"qwen_{voice.lower()}_{digest}"
    wav_path = OUT_DIR / f"{prefix}.wav"

    item = {
        "id": str(uuid.uuid4()),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": clean_label(metadata.get("source"), "mcp", 40),
        "title": clean_label(metadata.get("title"), "", 120),
        "priority": clean_label(metadata.get("priority"), "normal", 20).lower(),
        "mode": mode,
        "status": "ready" if wav_path.exists() else "queued",
        "voice": voice,
        "speed": speed,
        "temperature": temperature,
        "top_p": top_p,
        "text": text,
        "speech_text": speech_text,
        "file": str(wav_path),
    }
    publish_state(item)

    if wav_path.exists():
        return {
            "accepted": True,
            "spoken": False,
            "notified": mode == "notify",
            "mode": mode,
            "status": "ready",
            "voice": voice,
            "file": str(wav_path),
        }

    GENERATION_QUEUE.put(item)

    return {
        "accepted": True,
        "spoken": False,
        "notified": mode == "notify",
        "mode": mode,
        "status": "queued",
        "voice": voice,
        "file": str(wav_path),
    }


def tools_call(req_id, params):
    name = params.get("name")
    args = params.get("arguments") or {}
    if name != "speak_text":
        return response(req_id, error={"code": -32601, "message": f"Unknown tool: {name}"})

    try:
        result = synthesize_and_play(args.get("text", ""), args)
        return response(
            req_id,
            {
                "content": [
                    {
                        "type": "text",
                        "text": f"Spoke text with {result['voice']}.",
                    }
                ],
                "structuredContent": result,
            },
        )
    except Exception as exc:
        return response(req_id, error={"code": -32000, "message": str(exc)})


def handle_jsonrpc(payload):
    method = payload.get("method")
    req_id = payload.get("id")
    params = payload.get("params") or {}

    if method == "initialize":
        return initialize(req_id)
    if method == "notifications/initialized":
        return None
    if method == "tools/list":
        return tools_list(req_id)
    if method == "tools/call":
        return tools_call(req_id, params)
    return response(req_id, error={"code": -32601, "message": f"Method not found: {method}"})


def run_stdio():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
            result = handle_jsonrpc(payload)
        except Exception as exc:
            result = response(None, error={"code": -32700, "message": str(exc)})
        if result is not None:
            print(json.dumps(result), flush=True)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            result = handle_jsonrpc(json.loads(raw))
            body = b"" if result is None else json.dumps(result).encode()
            self.send_response(204 if result is None else 200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as exc:
            body = json.dumps(response(None, error={"code": -32700, "message": str(exc)})).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, _format, *args):
        return


def run_http(port):
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    threading.Thread(target=generation_worker, daemon=True).start()
    parser = argparse.ArgumentParser()
    parser.add_argument("--http", action="store_true")
    parser.add_argument("--port", type=int, default=51090)
    ns = parser.parse_args()
    if ns.http:
        run_http(ns.port)
    else:
        run_stdio()
