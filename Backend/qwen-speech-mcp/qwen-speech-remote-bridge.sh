#!/bin/bash
set -euo pipefail

PORT="${QWEN_SPEECH_MCP_PORT:-51090}"

while IFS= read -r line; do
  [ -z "$line" ] && continue
  response=$(
    curl -s --max-time 600 \
      -X POST "http://127.0.0.1:${PORT}" \
      -H "Content-Type: application/json" \
      -d "$line"
  )
  [ -n "$response" ] && printf '%s\n' "$response"
done
