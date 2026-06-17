#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${AGENT_VOICE_HOME:-$HOME/Library/Application Support/AgentVoiceBar}"
PY="$APP_DIR/.venv/bin/python"
PORT="${AGENT_VOICE_PORT:-51090}"

echo "Agent Voice Bar local check"
echo "App data: $APP_DIR"

if command -v brew >/dev/null 2>&1; then
  echo "ok: Homebrew $(brew --version | head -n 1)"
else
  echo "missing: Homebrew"
fi

if command -v swiftc >/dev/null 2>&1; then
  echo "ok: swiftc $(swiftc --version 2>&1 | sed -n '1p')"
else
  echo "missing: swiftc"
fi

if command -v terminal-notifier >/dev/null 2>&1; then
  echo "ok: terminal-notifier $(command -v terminal-notifier)"
else
  echo "optional missing: terminal-notifier"
fi

if [ -x "$PY" ]; then
  echo "ok: backend python $($PY --version 2>&1)"
  if "$PY" - <<'PY' >/dev/null 2>&1
import mlx_audio
PY
  then
    echo "ok: mlx-audio import"
  else
    echo "missing: mlx-audio import failed"
  fi
else
  echo "missing: backend venv python"
fi

if curl -fsS --max-time 2 \
  -X POST "http://127.0.0.1:${PORT}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' >/dev/null
then
  echo "ok: local MCP HTTP bridge on 127.0.0.1:${PORT}"
else
  echo "missing: local MCP HTTP bridge on 127.0.0.1:${PORT}"
fi
