#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${AGENT_VOICE_HOME:-$HOME/Library/Application Support/AgentVoiceBar}"

exec "$APP_DIR/.venv/bin/python" "$APP_DIR/qwen_speech_mcp.py"
