#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Agent Voice Bar.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

swiftc \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  -framework Foundation \
  -framework Speech \
  -framework UserNotifications \
  "$ROOT/Sources/AgentVoiceBar.swift" \
  -o "$MACOS/Agent Voice Bar"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$ROOT/Assets/AgentVoiceBarIcon.png" "$RESOURCES/AgentVoiceBarIcon.png"

dot_clean -m "$APP" >/dev/null 2>&1 || true
xattr -cr "$APP" || true
find "$APP" -exec xattr -c {} \; >/dev/null 2>&1 || true
xattr -d com.apple.FinderInfo "$APP" >/dev/null 2>&1 || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" >/dev/null 2>&1 || true
xattr -dr com.apple.provenance "$APP" >/dev/null 2>&1 || true
find "$APP" -print0 | xargs -0 xattr -d com.apple.FinderInfo >/dev/null 2>&1 || true
find "$APP" -print0 | xargs -0 xattr -d 'com.apple.fileprovider.fpfs#P' >/dev/null 2>&1 || true
find "$APP" -print0 | xargs -0 xattr -d com.apple.provenance >/dev/null 2>&1 || true
xattr -cr "$APP" || true
find "$APP" -name '._*' -delete >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP" >/dev/null

echo "$APP"
