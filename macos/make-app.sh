#!/usr/bin/env bash
# Build the release binary and assemble ClaudeQuota.app under build/.
# Prints the absolute path to the assembled .app on success.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Claude Quota"
APP="$ROOT/build/$APP_NAME.app"

swift build -c release --package-path "$ROOT" >&2
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/ClaudeQuota"

# Generate the app icon (build/AppIcon.icns) if it isn't there yet. Cheap, so
# regenerate when missing; delete build/AppIcon.icns to force a rebuild.
ICNS="$ROOT/build/AppIcon.icns"
if [[ ! -f "$ICNS" ]]; then
    "$ROOT/make-icon.sh" >&2
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeQuota"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc codesign so Gatekeeper/TCC treat it as a stable identity across rebuilds.
codesign --force --sign - "$APP" >&2 2>/dev/null || true

echo "$APP"
