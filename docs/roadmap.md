# Roadmap

Agent Voice Bar is beta software. The product direction is an agent sidecar
first: agents send messages and questions through MCP, the Mac app stores the
history, local TTS handles inbox readouts, and Spokenly can own the interactive
prompt/recording surface.

Planned directions:

Near-term:

- Inbox-first menu-bar layout with message actions attached to the message list.
- App-owned playback, notifications, unread state, and stable inbox reloads.
- Agent Voice Bar as the single MCP interface for one-way speech and two-way
  question flows.
- Sidecar mode for Spokenly so interactive questions do not double-speak.
- Optional coordinated Qwen-then-Spokenly flow for users who prefer local
  question TTS.
- Agent Voice Bar Labs native prompt with microphone recording and Apple Speech
  transcription.
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
- Native mode polish: better overlay design, redo/cancel flows, silence
  detection, streaming status, local model STT options, and cloud fallback.
- Signed/notarized beta builds.
