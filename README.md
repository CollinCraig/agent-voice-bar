# Agent Voice Bar

> Beta local agent inbox for macOS. Agents send structured messages; your Mac
> stores the history, notifies you, and optionally speaks updates aloud with
> local TTS.

![Agent Voice Bar hero](docs/assets/agent-voice-bar-hero.png)

Agent Voice Bar is a local-first macOS app for messages from AI agents. Codex,
Claude Code, or any MCP-capable tool can call a `speak_text` tool, and your Mac
stores that message in an inbox, renders a local voice clip, and lets the app
decide whether to speak, notify, or stay quiet.

It is especially useful when agents run in another terminal, another app, or a
remote SSH box. With a reverse SSH tunnel, a cloud/Ubuntu agent can still send
voice updates to the Mac on your desk.

## Status

This is beta software. The core loop works, but the app is still being polished:

- inbox-first menu-bar app and full Dashboard window
- local Qwen/MLX TTS backend
- MCP `speak_text` tool with optional title/source/priority metadata
- Speak/Notify/DND delivery modes
- app-owned playback and notifications
- direct voice, real talk-speed, model-speed, energy, and variety controls
- replayable scrolling inbox
- inbox search and source/channel filtering in the mini app and Dashboard
- expandable full-message bubbles during replay
- unread menu-bar count and archive/clear actions
- Setup Doctor report for notification, fallback, backend, and mode checks
- macOS notification fallback through `terminal-notifier`
- optional remote use over reverse SSH

## Why This Exists

Spokenly is great for speech-to-text: you talk, agents receive text.

Agent Voice Bar is the other direction: agents talk, you receive a local inbox.
Speech is an extra layer on top of the inbox, not the whole product.

Use it for:

- long-running agent status updates
- remote Codex or Claude Code sessions
- background coding/research agents
- "tell me when you need me" workflows
- local-only TTS without cloud accounts

## What It Does

- Stores agent messages in a local, replayable inbox.
- Shows message metadata like source, title, priority, mode, and render status.
- Filters history by message text and source, so multiple agents can share one
  local inbox without becoming a wall of noise.
- Renders speech locally through the bundled Qwen/MLX backend.
- Lets the app decide whether a ready message should speak, notify, or stay in
  DND.
- Keeps playback under app control so overlapping speech is avoidable.
- Clears stale playback state if macOS audio startup or finish callbacks misbehave.
- Works with remote agents through a reverse SSH tunnel to your Mac.

## Architecture

```text
AI agent
  |
  | MCP speak_text
  v
Qwen speech backend on Mac
  |
  | queue.jsonl + generated wav files
  v
Agent Voice Bar macOS app
  |
  | inbox / dashboard / notify / autoplay / silent
  v
Your ears + replayable inbox
```

Remote flow:

```text
Remote Codex/Claude
  |
  | MCP stdio bridge
  v
127.0.0.1:51090 on remote
  |
  | reverse SSH tunnel
  v
127.0.0.1:51090 on Mac
  |
  v
Local Qwen speech backend
```

## Requirements

- macOS 14+
- Apple Silicon recommended
- Xcode Command Line Tools for `swiftc`
- Homebrew
- Python 3
- `mlx-audio` for the bundled Qwen backend
- optional but recommended: `terminal-notifier`

The default beta backend uses:

```text
mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit
```

Default voice:

```text
Chelsie
```

## Quick Start

Build and install the app:

```bash
./scripts/install-local.sh
```

Install the local Qwen/MLX backend:

```bash
./scripts/setup-qwen-backend.sh
```

Check the local runtime:

```bash
./scripts/check-local-models.sh
```

Install the notification fallback:

```bash
brew install terminal-notifier
```

## MCP Setup

Local Codex:

```bash
codex mcp add qwen_speech -- "$HOME/Library/Application Support/AgentVoiceBar/qwen-speech-mcp.sh"
```

Local Claude Code:

```bash
claude mcp add qwen_speech -- "$HOME/Library/Application Support/AgentVoiceBar/qwen-speech-mcp.sh"
```

Then ask your agent to call `qwen_speech.speak_text`.

Basic tool payload:

```json
{
  "text": "Build finished and the tests passed.",
  "title": "Build finished",
  "source": "Codex",
  "priority": "normal"
}
```

Only `text` is required.

Full local/remote instructions are in [docs/mcp-and-ssh.md](docs/mcp-and-ssh.md).

## App Modes

- `Speak`: generate and play messages immediately.
- `Notify`: generate messages, notify you, and keep them in the inbox.
- `DND`: generate and keep messages without popping up or playing.

The menu-bar window is the quick control surface. Use `Dashboard` for a roomier
history view, full message detail, replay, archive, and clear controls.

Use `Doctor` in the menu-bar window when something feels off. It writes a local
report into the inbox with the current delivery mode, voice settings, native
notification status, `terminal-notifier` fallback status, backend reachability,
and bundle id.

Every message is stored locally in:

```text
~/Library/Application Support/AgentVoiceBar/
```

Important files:

- `config.json`: mode, voice, real talk-speed, model-speed, generation settings
- `pronunciations.json`: custom pronunciation replacements
- `queue.jsonl`: inbox history
- `state.json`: latest item and app state
- `out/`: generated WAV files

## Local Models

The beta ships with a Qwen/MLX backend because it sounds decent locally on a
capable Mac and exposes a simple MCP tool.

The backend is intentionally replaceable. Future versions should support a model
picker for engines such as Qwen, Kokoro, Chatterbox, and other local TTS models.

Run:

```bash
./scripts/check-local-models.sh
```

to verify Swift, Homebrew, terminal-notifier, the backend venv, `mlx-audio`, and
the local MCP HTTP bridge.

## Reverse SSH

Agent Voice Bar works well with remote agents if you expose your Mac's local
speech backend to the remote host through a reverse tunnel:

```bash
ssh -N -T \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -R 127.0.0.1:51090:127.0.0.1:51090 \
  user@your-remote-host
```

See [docs/mcp-and-ssh.md](docs/mcp-and-ssh.md) for the remote bridge setup.

## Build

```bash
./scripts/build-app.sh
```

The built app is written to:

```text
build/Agent Voice Bar.app
```

## Login Item

To start the app at login, adapt:

```text
examples/launch-agent.example.plist
```

Then copy it into:

```text
~/Library/LaunchAgents/
```

## Security And Privacy

- No hosted service is required.
- Messages and WAV files stay on your Mac by default.
- Remote use should be done through your own SSH tunnel.
- Do not commit your own LaunchAgents, hostnames, queue files, generated audio,
  or private MCP config.

## Roadmap

See [docs/roadmap.md](docs/roadmap.md).

High-level direction:

- polished menu bar utility
- full dashboard app
- local model picker
- richer inbox/history
- per-agent voices and notification rules
- easier SSH/MCP setup

## License

MIT
