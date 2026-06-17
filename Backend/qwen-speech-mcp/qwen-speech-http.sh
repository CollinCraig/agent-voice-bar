#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${AGENT_VOICE_HOME:-$HOME/Library/Application Support/AgentVoiceBar}"
PORT="${AGENT_VOICE_PORT:-51090}"

exec "$APP_DIR/.venv/bin/python" "$APP_DIR/qwen_speech_mcp.py" --http --port "$PORT"
