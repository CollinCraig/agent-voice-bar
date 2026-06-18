# MCP And SSH Setup

Agent Voice Bar exposes local MCP tools through its backend. Any MCP-capable
agent can call them, including Codex, Claude Code, and remote sessions that can
reach a forwarded localhost port.

Available tools:

- `speak_text`: send a one-way inbox message that can be spoken, notified, or
  saved silently.
- `ask_user_voice`: speak one question, wait for playback to finish, then open
  Spokenly dictation and return the answer.
- `ask_user_voice_batch`: ask multiple questions one by one and return
  structured answers.

The backend is still named `qwen_speech` in the examples for compatibility. It
is the Agent Voice Bar MCP interface.

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
the reverse tunnel, and your Mac generates, queues, plays, or prompts locally.
For `ask_user_voice`, Spokenly runs on your Mac after local speech playback
finishes, so the remote agent still gets a single answer through the same MCP
call.

## Test Payload

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"speak_text","arguments":{"text":"Agent Voice Bar remote MCP test."}}}' \
  | ~/.local/bin/qwen-speech-remote-bridge.sh
```

## Ask Payload

This will speak the question locally, wait for playback, open Spokenly
dictation, and return the transcript:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ask_user_voice","arguments":{"question":"Should I keep going with this release?","title":"Remote question","source":"Ubuntu"}}}' \
  | ~/.local/bin/qwen-speech-remote-bridge.sh
```

Do not use voice question tools for passwords, API keys, recovery codes, or
other secrets. MCP clients and servers should keep the user in control of what
data is shared.
