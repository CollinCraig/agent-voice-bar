# MCP And SSH Setup

Agent Voice Bar exposes a local `speak_text` MCP tool through the Qwen backend.
Any MCP-capable agent can call it, including Codex, Claude Code, and remote
sessions that can reach a forwarded localhost port.

## Local Codex

```bash
codex mcp add qwen_speech -- "$HOME/Library/Application Support/AgentVoiceBar/qwen-speech-mcp.sh"
```

## Local Claude Code

```bash
claude mcp add qwen_speech -- "$HOME/Library/Application Support/AgentVoiceBar/qwen-speech-mcp.sh"
```

## Remote Agents Over Reverse SSH

On your Mac, keep the local HTTP bridge running on `127.0.0.1:51090`, then open a
reverse tunnel to your remote box:

```bash
ssh -N -T \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -R 127.0.0.1:51090:127.0.0.1:51090 \
  user@your-remote-host
```

On the remote host, copy `Backend/qwen-speech-mcp/qwen-speech-remote-bridge.sh`
to a stable path, for example:

```bash
mkdir -p ~/.local/bin
cp qwen-speech-remote-bridge.sh ~/.local/bin/
chmod +x ~/.local/bin/qwen-speech-remote-bridge.sh
```

Then register it with an MCP client on the remote host:

```bash
codex mcp add qwen_speech -- ~/.local/bin/qwen-speech-remote-bridge.sh
claude mcp add qwen_speech -- ~/.local/bin/qwen-speech-remote-bridge.sh
```

The remote agent writes MCP JSON-RPC to the bridge, the bridge posts it through
the reverse tunnel, and your Mac generates or queues the voice message locally.

## Test Payload

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"speak_text","arguments":{"text":"Agent Voice Bar remote MCP test."}}}' \
  | ~/.local/bin/qwen-speech-remote-bridge.sh
```
