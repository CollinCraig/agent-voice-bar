# Roadmap

Agent Voice Bar is beta software. The first release focuses on the core loop:
agents send messages through MCP, local TTS renders them, and the Mac app keeps a
replayable inbox.

Planned directions:

Near-term:

- App-owned playback, notifications, unread state, and stable inbox reloads.
- Message metadata: title, source agent, priority, status, and generated audio.
- Read/unread, pin, delete, and filters for the menu-bar inbox.
- Full message detail with original prompt, speech-normalized text, render errors,
  and replay controls.
- Notification policies for questions, blocked states, failures, and urgent items.

Next:

- Richer dashboard filters, search, saved views, and per-agent channels.
- Menu bar mini mode plus a more compact "Open Dashboard" flow.
- Per-agent voices, channels, and notification rules.
- Better remote setup helpers for reverse SSH tunnels and LaunchAgents.
- Local model picker with install/status checks for Qwen, Kokoro, Chatterbox, and
  other on-device TTS engines.
- Optional STT pairing for two-way local voice workflows.
- Signed/notarized beta builds.
