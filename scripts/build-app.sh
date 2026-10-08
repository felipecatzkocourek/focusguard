#!/usr/bin/env bash
# Builds FocusGuard.app from the Swift package.
#
#   scripts/build-app.sh            # build into build/FocusGuard.app
#   scripts/build-app.sh --install  # ...and copy it to ~/Applications
#
# The app is ad-hoc signed, which is enough to run it on the machine that built it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="build/FocusGuard.app"

echo "→ Compiling (release)…"
swift build -c release --product FocusGuard
swift build -c release --product focusguard-helper
BIN="$(swift build -c release --show-bin-path)"

echo "→ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FocusGuard" "$APP/Contents/MacOS/FocusGuard"
cp "$BIN/focusguard-helper" "$APP/Contents/Resources/focusguard-helper"
cp helper/install.sh helper/uninstall.sh "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist >"$APP/Contents/Info.plist"

echo "→ Signing (ad-hoc)…"
codesign --force --sign - "$APP/Contents/Resources/focusguard-helper"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/FocusGuard.app"
  cp -R "$APP" "$HOME/Applications/"
  # Make sure Launch Services knows about the focusguard:// URL scheme.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$HOME/Applications/FocusGuard.app"
  echo "✓ Installed to ~/Applications/FocusGuard.app"
else
  echo "✓ Built $APP"
fi
