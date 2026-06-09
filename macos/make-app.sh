#!/usr/bin/env bash
# Build the release binary and assemble ClaudeQuota.app under build/.
# Prints the absolute path to the assembled .app on success.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Claude Quota"
APP="$ROOT/build/$APP_NAME.app"

swift build -c release --package-path "$ROOT" >&2
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/ClaudeQuota"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeQuota"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc codesign so Gatekeeper/TCC treat it as a stable identity across rebuilds.
codesign --force --sign - "$APP" >&2 2>/dev/null || true

echo "$APP"
