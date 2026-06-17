#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${AGENT_VOICE_HOME:-$HOME/Library/Application Support/AgentVoiceBar}"
BACKEND_DIR="$ROOT/Backend/qwen-speech-mcp"
PLIST="$HOME/Library/LaunchAgents/dev.agentvoicebar.qwen-speech-mcp.plist"

mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"
cp "$BACKEND_DIR/qwen_speech_mcp.py" "$APP_DIR/qwen_speech_mcp.py"
cp "$BACKEND_DIR/qwen-speech-http.sh" "$APP_DIR/qwen-speech-http.sh"
cp "$BACKEND_DIR/qwen-speech-mcp.sh" "$APP_DIR/qwen-speech-mcp.sh"
chmod +x "$APP_DIR/qwen-speech-"*.sh "$APP_DIR/qwen_speech_mcp.py"

if [ ! -f "$APP_DIR/config.json" ]; then
  cp "$BACKEND_DIR/config.example.json" "$APP_DIR/config.json"
fi

if [ ! -f "$APP_DIR/pronunciations.json" ]; then
  cp "$BACKEND_DIR/pronunciations.example.json" "$APP_DIR/pronunciations.json"
fi

if [ ! -x "$APP_DIR/.venv/bin/python" ]; then
  python3 -m venv "$APP_DIR/.venv"
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
