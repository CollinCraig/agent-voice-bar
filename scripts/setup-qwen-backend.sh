#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${AGENT_VOICE_HOME:-$HOME/Library/Application Support/AgentVoiceBar}"
LEGACY_DIR="$HOME/Library/Application Support/CodexSpeech"
BACKEND_DIR="$ROOT/Backend/qwen-speech-mcp"
PLIST="$HOME/Library/LaunchAgents/dev.agentvoicebar.qwen-speech-mcp.plist"
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.collincraig.qwen-speech-mcp.plist"

mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"

launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" >/dev/null 2>&1 || true
pkill -f "$LEGACY_DIR/qwen_speech_mcp.py" >/dev/null 2>&1 || true

cp "$BACKEND_DIR/qwen_speech_mcp.py" "$APP_DIR/qwen_speech_mcp.py"
cp "$BACKEND_DIR/qwen-speech-http.sh" "$APP_DIR/qwen-speech-http.sh"
cp "$BACKEND_DIR/qwen-speech-mcp.sh" "$APP_DIR/qwen-speech-mcp.sh"
chmod +x "$APP_DIR/qwen-speech-"*.sh "$APP_DIR/qwen_speech_mcp.py"

if [ ! -f "$APP_DIR/config.json" ]; then
  if [ -f "$LEGACY_DIR/config.json" ]; then
    cp "$LEGACY_DIR/config.json" "$APP_DIR/config.json"
  else
    cp "$BACKEND_DIR/config.example.json" "$APP_DIR/config.json"
  fi
fi

if [ ! -f "$APP_DIR/pronunciations.json" ]; then
  if [ -f "$LEGACY_DIR/pronunciations.json" ]; then
    cp "$LEGACY_DIR/pronunciations.json" "$APP_DIR/pronunciations.json"
  else
    cp "$BACKEND_DIR/pronunciations.example.json" "$APP_DIR/pronunciations.json"
  fi
fi

if [ -d "$LEGACY_DIR/out" ]; then
  mkdir -p "$APP_DIR/out"
  rsync -a "$LEGACY_DIR/out/" "$APP_DIR/out/"
fi

python3 - "$LEGACY_DIR" "$APP_DIR" <<'PY'
import json
import sys
from pathlib import Path

legacy = Path(sys.argv[1])
app = Path(sys.argv[2])
old_queue = legacy / "queue.jsonl"
new_queue = app / "queue.jsonl"
old_prefix = str(legacy)
new_prefix = str(app)
items = {}

def item_time(item):
    return item.get("ready_at") or item.get("created_at") or ""

for path in [old_queue, new_queue]:
    if not path.exists():
        continue
    for line in path.read_text().splitlines():
        try:
            item = json.loads(line)
        except Exception:
            continue
        if isinstance(item.get("file"), str):
            item["file"] = item["file"].replace(old_prefix, new_prefix)
        item_id = item.get("id") or f"manual:{item_time(item)}:{item.get('text', '')}"
        previous = items.get(item_id)
        if previous is None or item.get("status") == "ready" or item_time(item) >= item_time(previous):
            items[item_id] = item

rows = sorted(items.values(), key=item_time)
if rows:
    new_queue.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows))
    state = {"last": rows[-1], "updated_at": item_time(rows[-1]), "config": {}}
    config_path = app / "config.json"
    if config_path.exists():
        try:
            state["config"] = json.loads(config_path.read_text())
        except Exception:
            pass
    (app / "state.json").write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY

if [ ! -x "$APP_DIR/.venv/bin/python" ]; then
  if [ -x "$LEGACY_DIR/.venv/bin/python" ]; then
    ln -sfn "$LEGACY_DIR/.venv" "$APP_DIR/.venv"
  else
    python3 -m venv "$APP_DIR/.venv"
  fi
fi

"$APP_DIR/.venv/bin/python" -m ensurepip --upgrade >/dev/null
"$APP_DIR/.venv/bin/python" -m pip install --upgrade pip wheel >/dev/null
"$APP_DIR/.venv/bin/python" -m pip install --upgrade mlx-audio >/dev/null

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.agentvoicebar.qwen-speech-mcp</string>

  <key>ProgramArguments</key>
  <array>
    <string>$APP_DIR/qwen-speech-http.sh</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/tmp/agent-voice-bar-qwen.out.log</string>

  <key>StandardErrorPath</key>
  <string>/tmp/agent-voice-bar-qwen.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/dev.agentvoicebar.qwen-speech-mcp"

echo "Installed Agent Voice Bar Qwen backend at: $APP_DIR"
echo "HTTP MCP bridge: http://127.0.0.1:51090"
echo "Stdio MCP command: $APP_DIR/qwen-speech-mcp.sh"
