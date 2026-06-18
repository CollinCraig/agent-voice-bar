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
RULES_FILE = APP_DIR / "rules.json"
STATE_FILE = APP_DIR / "state.json"
QUEUE_FILE = APP_DIR / "queue.jsonl"
PLAYBACK_FILE = APP_DIR / "playback.jsonl"
NATIVE_DIR = APP_DIR / "native"
NATIVE_PENDING_DIR = NATIVE_DIR / "pending"
NATIVE_ANSWERS_DIR = NATIVE_DIR / "answers"
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
    "question_voice": "spokenly",
    "dictation_backend": "spokenly",
    "native_question_timeout_seconds": 900,
    "ask_wait_for_speech_seconds": 180,
    "ask_dictation_timeout_seconds": 900,
    "spokenly_bridge": str(Path.home() / "Library" / "Application Support" / "Spokenly" / "mcp-bridge.sh"),
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
    if config.get("question_voice") not in {"spokenly", "agent_voice_bar", "silent"}:
        config["question_voice"] = "spokenly"
    if config.get("dictation_backend") not in {"spokenly", "native"}:
        config["dictation_backend"] = "spokenly"
    return config


def load_rules():
    try:
        if RULES_FILE.exists():
            data = json.loads(RULES_FILE.read_text())
            sources = data.get("sources") if isinstance(data, dict) else {}
            if isinstance(sources, dict):
                return {
                    str(source).strip().lower(): str(mode)
                    for source, mode in sources.items()
                    if str(mode) in {"autoplay", "notify", "silent"}
                }
    except Exception:
        pass
    return {}


def mode_for_source(source, fallback):
    source_key = str(source or "").strip().lower()
    if not source_key:
        return fallback
    return load_rules().get(source_key, fallback)


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
                },
                {
                    "name": "ask_user_voice",
                    "description": "Ask the user one question through Agent Voice Bar. By default this uses Spokenly as the prompt, TTS, and dictation surface so Agent Voice Bar does not speak over it. Set question_voice to agent_voice_bar to use local Qwen speech before dictation. Do not use for passwords, secrets, or sensitive information.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "question": {
                                "type": "string",
                                "description": "Question to speak and then show in the dictation prompt.",
                            },
                            "title": {
                                "type": "string",
                                "description": "Optional short title for the inbox/session.",
                            },
                            "source": {
                                "type": "string",
                                "description": "Optional agent/source name, such as Codex, Claude, or Ubuntu.",
                            },
                            "priority": {
                                "type": "string",
                                "description": "Optional priority label: low, normal, high, or urgent.",
                            },
                            "question_voice": {
                                "type": "string",
                                "enum": ["spokenly", "agent_voice_bar", "silent"],
                                "description": "Who should speak the question. spokenly is the default sidecar mode; agent_voice_bar uses local Qwen first; silent skips Agent Voice Bar TTS.",
                            },
                            "dictation_backend": {
                                "type": "string",
                                "enum": ["spokenly", "native"],
                                "description": "Who should record/transcribe the answer. spokenly is the stable default; native uses Agent Voice Bar Labs.",
                            },
                            "wait_for_speech": {
                                "type": "boolean",
                                "description": "For question_voice=agent_voice_bar, whether to wait for local speech playback to finish before recording. Defaults to true.",
                            },
                        },
                        "required": ["question"],
                    },
                },
                {
                    "name": "ask_user_voice_batch",
                    "description": "Ask the user multiple questions one by one through Agent Voice Bar. By default this uses Spokenly as the prompt, TTS, and dictation surface so Agent Voice Bar does not speak over it. Set question_voice to agent_voice_bar to use local Qwen speech before each dictation step. Do not use for passwords, secrets, or sensitive information.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "questions": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Questions to ask in order.",
                            },
                            "title": {
                                "type": "string",
                                "description": "Optional short title for the inbox/session.",
                            },
                            "source": {
                                "type": "string",
                                "description": "Optional agent/source name, such as Codex, Claude, or Ubuntu.",
                            },
                            "priority": {
                                "type": "string",
                                "description": "Optional priority label: low, normal, high, or urgent.",
                            },
                            "question_voice": {
                                "type": "string",
                                "enum": ["spokenly", "agent_voice_bar", "silent"],
                                "description": "Who should speak the questions. spokenly is the default sidecar mode; agent_voice_bar uses local Qwen first; silent skips Agent Voice Bar TTS.",
                            },
                            "dictation_backend": {
                                "type": "string",
                                "enum": ["spokenly", "native"],
                                "description": "Who should record/transcribe each answer. spokenly is the stable default; native uses Agent Voice Bar Labs.",
                            },
                            "wait_for_speech": {
                                "type": "boolean",
                                "description": "For question_voice=agent_voice_bar, whether to wait for each local speech playback to finish before recording. Defaults to true.",
                            },
                        },
                        "required": ["questions"],
                    },
                },
                {
                    "name": "ask_user_native",
                    "description": "Experimental Labs tool: ask the user one question with Agent Voice Bar's native prompt and Apple Speech transcription. Spokenly remains the stable default for ask_user_voice.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "question": {
                                "type": "string",
                                "description": "Question to show in the native Agent Voice Bar prompt.",
                            },
                            "title": {
                                "type": "string",
                                "description": "Optional short title for the prompt/session.",
                            },
                            "source": {
                                "type": "string",
                                "description": "Optional agent/source name, such as Codex, Claude, or Ubuntu.",
                            },
                            "priority": {
                                "type": "string",
                                "description": "Optional priority label: low, normal, high, or urgent.",
                            },
                            "question_voice": {
                                "type": "string",
                                "enum": ["agent_voice_bar", "silent"],
                                "description": "Whether Agent Voice Bar should speak the question locally before recording. Defaults to agent_voice_bar for this Labs tool.",
                            },
                        },
                        "required": ["question"],
                    },
                },
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
    source = clean_label(metadata.get("source"), "mcp", 40)
    requested_mode = str(metadata.get("mode") or metadata.get("delivery") or "")
    mode = requested_mode if requested_mode in {"autoplay", "notify", "silent"} else mode_for_source(source, str(config.get("mode") or "autoplay"))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(f"{voice}|{speed}|{temperature}|{top_p}|{speech_text}".encode()).hexdigest()[:16]
    prefix = f"qwen_{voice.lower()}_{digest}"
    wav_path = OUT_DIR / f"{prefix}.wav"

    item = {
        "id": str(uuid.uuid4()),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": source,
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


def read_playback_events():
    events = []
    try:
        if not PLAYBACK_FILE.exists():
            return events
        with PLAYBACK_FILE.open() as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except Exception:
                    continue
                if isinstance(event, dict):
                    events.append(event)
    except Exception:
        return events
    return events


def wait_for_playback(file_path, started_after, timeout_seconds):
    if not file_path or timeout_seconds <= 0:
        return {"waited": False, "event": None}

    terminal_events = {
        "finished",
        "watchdog_finished",
        "stopped",
        "skipped",
        "missing_file",
        "failed_load",
        "failed_start",
        "decode_failed",
    }
    deadline = time.monotonic() + timeout_seconds
    saw_started = False
    while time.monotonic() < deadline:
        for event in read_playback_events():
            if event.get("file") != file_path:
                continue
            event_time = str(event.get("at") or "")
            if event_time < started_after:
                continue
            name = event.get("event")
            if name == "started":
                saw_started = True
            if name in terminal_events:
                return {"waited": True, "event": event}
        time.sleep(0.5 if saw_started else 0.75)
    return {
        "waited": True,
        "event": {
            "event": "timeout",
            "file": file_path,
            "detail": f"No playback completion event after {timeout_seconds} seconds.",
        },
    }


def call_spokenly_dictation(questions, timeout_seconds):
    bridge = Path(str(load_config().get("spokenly_bridge") or DEFAULT_CONFIG["spokenly_bridge"])).expanduser()
    if not bridge.exists():
        raise RuntimeError(f"Spokenly MCP bridge not found: {bridge}")
    if not os.access(bridge, os.X_OK):
        raise RuntimeError(f"Spokenly MCP bridge is not executable: {bridge}")

    initialize_payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "agent-voice-bar", "version": "0.1.0"},
        },
    }
    call_payload = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "ask_user_dictation",
            "arguments": {"questions": questions},
        },
    }
    input_text = json.dumps(initialize_payload) + "\n" + json.dumps(call_payload) + "\n"
    proc = subprocess.Popen(
        [str(bridge)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        stdout, stderr = proc.communicate(input_text, timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise TimeoutError(f"Spokenly dictation timed out after {timeout_seconds} seconds")

    if proc.returncode not in (0, None):
        raise RuntimeError((stderr or "Spokenly dictation failed").strip())

    responses = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            responses.append(json.loads(line))
        except Exception:
            continue
    for item in reversed(responses):
        if item.get("id") == 2:
            if item.get("error"):
                raise RuntimeError(item["error"].get("message") or str(item["error"]))
            return item.get("result") or {}
    raise RuntimeError("Spokenly did not return a dictation result")


def extract_dictation_text(result):
    structured = result.get("structuredContent")
    if isinstance(structured, dict):
        for key in ("answer", "text", "transcript", "response"):
            value = structured.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        if isinstance(structured.get("answers"), list):
            return "\n".join(str(value).strip() for value in structured["answers"] if str(value).strip()).strip()

    content = result.get("content")
    if isinstance(content, list):
        texts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                value = str(block.get("text") or "").strip()
                if value:
                    texts.append(value)
        joined = "\n".join(texts).strip()
        if joined:
            try:
                parsed = json.loads(joined)
                if isinstance(parsed, dict):
                    for key in ("answer", "text", "transcript", "response"):
                        value = parsed.get(key)
                        if isinstance(value, str) and value.strip():
                            return value.strip()
            except Exception:
                pass
            return joined
    return ""


def dictation_backend_mode(metadata, config):
    requested = str(metadata.get("dictation_backend") or config.get("dictation_backend") or "spokenly")
    if requested not in {"spokenly", "native"}:
        return "spokenly"
    return requested


def question_voice_mode(metadata, config, dictation_backend):
    requested = str(metadata.get("question_voice") or config.get("question_voice") or "spokenly")
    if dictation_backend == "native" and "question_voice" not in metadata and requested == "spokenly":
        return "agent_voice_bar"
    if requested not in {"spokenly", "agent_voice_bar", "silent"}:
        return "spokenly"
    return requested


def append_question_item(question, metadata, question_voice):
    item = {
        "id": str(uuid.uuid4()),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ready_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": clean_label(metadata.get("source"), "mcp", 40),
        "title": clean_label(metadata.get("title"), "Question for you", 120),
        "priority": clean_label(metadata.get("priority"), "high", 20).lower(),
        "mode": "question",
        "status": "ready",
        "voice": question_voice,
        "speed": "",
        "temperature": "",
        "top_p": "",
        "text": f"Question: {question}",
        "speech_text": "",
        "file": None,
    }
    publish_state(item)
    return item


def append_answer_item(question, answer, metadata):
    answer = " ".join((answer or "").split())
    item = {
        "id": str(uuid.uuid4()),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ready_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": clean_label(metadata.get("source"), "User", 40),
        "title": clean_label(metadata.get("title"), "Voice answer", 120),
        "priority": clean_label(metadata.get("priority"), "normal", 20).lower(),
        "mode": "silent",
        "status": "ready",
        "voice": "",
        "speed": "",
        "temperature": "",
        "top_p": "",
        "text": f"Question: {question}\nAnswer: {answer or '(no answer captured)'}",
        "speech_text": "",
        "file": None,
    }
    publish_state(item)


def wait_for_native_dictation(question, metadata, timeout_seconds):
    question_id = str(uuid.uuid4())
    NATIVE_PENDING_DIR.mkdir(parents=True, exist_ok=True)
    NATIVE_ANSWERS_DIR.mkdir(parents=True, exist_ok=True)
    pending_path = NATIVE_PENDING_DIR / f"{question_id}.json"
    answer_path = NATIVE_ANSWERS_DIR / f"{question_id}.json"
    payload = {
        "id": question_id,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "question": question,
        "title": clean_label(metadata.get("title"), "Native question", 120),
        "source": clean_label(metadata.get("source"), "mcp", 40),
        "priority": clean_label(metadata.get("priority"), "high", 20).lower(),
        "timeout_seconds": timeout_seconds,
    }
    write_json(pending_path, payload)
    deadline = time.monotonic() + timeout_seconds
    try:
        while time.monotonic() < deadline:
            if answer_path.exists():
                answer = read_json(answer_path, {})
                status = str(answer.get("status") or "answered")
                if status == "cancelled":
                    return {
                        "content": [{"type": "text", "text": ""}],
                        "structuredContent": {
                            "answer": "",
                            "status": "cancelled",
                            "native_question_id": question_id,
                            "backend": "native",
                        },
                    }
                if status == "failed":
                    raise RuntimeError(str(answer.get("error") or "Native dictation failed"))
                text = str(answer.get("answer") or "")
                return {
                    "content": [{"type": "text", "text": text}],
                    "structuredContent": {
                        "answer": text,
                        "status": status,
                        "native_question_id": question_id,
                        "backend": "native",
                    },
                }
            time.sleep(0.5)
        raise TimeoutError(f"Native dictation timed out after {timeout_seconds} seconds")
    finally:
        try:
            pending_path.unlink()
        except FileNotFoundError:
            pass


def ask_one_question(question, metadata):
    question = " ".join((question or "").split())
    if not question:
        raise ValueError("question is required")
    config = load_config()
    wait_for_speech = metadata.get("wait_for_speech")
    wait_for_speech = True if wait_for_speech is None else bool(wait_for_speech)
    wait_seconds = int(config.get("ask_wait_for_speech_seconds") or DEFAULT_CONFIG["ask_wait_for_speech_seconds"])
    dictation_timeout = int(config.get("ask_dictation_timeout_seconds") or DEFAULT_CONFIG["ask_dictation_timeout_seconds"])
    native_timeout = int(config.get("native_question_timeout_seconds") or DEFAULT_CONFIG["native_question_timeout_seconds"])
    dictation_backend = dictation_backend_mode(metadata, config)
    question_voice = question_voice_mode(metadata, config, dictation_backend)

    question_item = append_question_item(question, metadata, question_voice)
    speech_result = {
        "accepted": False,
        "mode": "question",
        "status": "delegated" if question_voice == "spokenly" else "silent",
        "voice": question_voice,
        "file": None,
    }
    playback_result = {"waited": False, "event": None}
    if question_voice == "agent_voice_bar":
        ask_metadata = {
            **metadata,
            "mode": "autoplay",
            "title": clean_label(metadata.get("title"), "Question for you", 120),
            "priority": clean_label(metadata.get("priority"), "high", 20),
        }
        started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        speech_result = synthesize_and_play(question, ask_metadata)
        if wait_for_speech:
            playback_result = wait_for_playback(speech_result.get("file"), started_at, wait_seconds)

    if dictation_backend == "native":
        dictation_result = wait_for_native_dictation(question, metadata, native_timeout)
    else:
        dictation_result = call_spokenly_dictation([question], dictation_timeout)
    answer = extract_dictation_text(dictation_result)
    append_answer_item(question, answer, {**metadata, "source": "User", "title": f"Answer: {clean_label(metadata.get('title'), 'Question', 80)}"})
    return {
        "question": question,
        "answer": answer,
        "question_item_id": question_item.get("id"),
        "question_voice": question_voice,
        "dictation_backend": dictation_backend,
        "speech": speech_result,
        "playback": playback_result,
        "dictation": dictation_result,
    }


def ask_batch(questions, metadata):
    if not isinstance(questions, list) or not questions:
        raise ValueError("questions must be a non-empty array")
    answers = []
    for index, question in enumerate(questions, start=1):
        scoped = {
            **metadata,
            "title": metadata.get("title") or f"Question {index} of {len(questions)}",
        }
        result = ask_one_question(str(question), scoped)
        answers.append({
            "index": index,
            "question": result["question"],
            "answer": result["answer"],
            "question_voice": result["question_voice"],
            "dictation_backend": result["dictation_backend"],
            "playback": result["playback"],
        })
    return {"answers": answers}


def tools_call(req_id, params):
    name = params.get("name")
    args = params.get("arguments") or {}

    try:
        if name == "speak_text":
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
        if name == "ask_user_voice":
            result = ask_one_question(args.get("question", ""), args)
            return response(
                req_id,
                {
                    "content": [
                        {
                            "type": "text",
                            "text": result["answer"],
                        }
                    ],
                    "structuredContent": {
                        "question": result["question"],
                        "answer": result["answer"],
                        "question_voice": result["question_voice"],
                        "dictation_backend": result["dictation_backend"],
                        "playback": result["playback"],
                    },
                },
            )
        if name == "ask_user_voice_batch":
            result = ask_batch(args.get("questions"), args)
            return response(
                req_id,
                {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(result, indent=2),
                        }
                    ],
                    "structuredContent": result,
                },
            )
        if name == "ask_user_native":
            native_args = {**args, "dictation_backend": "native"}
            if "question_voice" not in native_args:
                native_args["question_voice"] = "agent_voice_bar"
            result = ask_one_question(native_args.get("question", ""), native_args)
            return response(
                req_id,
                {
                    "content": [
                        {
                            "type": "text",
                            "text": result["answer"],
                        }
                    ],
                    "structuredContent": {
                        "question": result["question"],
                        "answer": result["answer"],
                        "question_voice": result["question_voice"],
                        "dictation_backend": result["dictation_backend"],
                        "playback": result["playback"],
                    },
                },
            )
        return response(req_id, error={"code": -32601, "message": f"Unknown tool: {name}"})
    except Exception as exc:
        return response(
            req_id,
            error={"code": -32000, "message": str(exc)},
        )


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
