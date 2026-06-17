#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$("$ROOT/scripts/build-app.sh")"
DEST="/Applications/Agent Voice Bar.app"

osascript -e 'tell application "Agent Voice Bar" to quit' >/dev/null 2>&1 || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
xattr -cr "$DEST" || true
codesign --force --deep --sign - "$DEST" >/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
open "$DEST"

echo "$DEST"
