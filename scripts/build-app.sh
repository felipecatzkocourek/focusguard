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
cp helper/install.sh helper/uninstall.sh helper/firefox-policy.sh "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist >"$APP/Contents/Info.plist"

# Use the stable local identity when it exists (see scripts/create-signing-identity.sh),
# so macOS keeps permissions like Full Disk Access across rebuilds. Otherwise ad-hoc.
IDENTITY="FocusGuard Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  SIGN_AS="$IDENTITY"
else
  SIGN_AS="-"
fi
echo "→ Signing ($([[ $SIGN_AS == - ]] && echo ad-hoc || echo "$SIGN_AS"))…"
codesign --force --sign "$SIGN_AS" "$APP/Contents/Resources/focusguard-helper"
codesign --force --sign "$SIGN_AS" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/FocusGuard.app"
  cp -R "$APP" "$HOME/Applications/"
  # Register the new build with Launch Services (login item, Finder, Spotlight).
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$HOME/Applications/FocusGuard.app"
  echo "✓ Installed to ~/Applications/FocusGuard.app"
else
  echo "✓ Built $APP"
fi

if [[ $SIGN_AS == - ]]; then
  echo
  echo "Note: this build is ad-hoc signed, so macOS treats it as a new app and forgets"
  echo "its permissions (Full Disk Access). Run scripts/create-signing-identity.sh once"
  echo "to sign every build the same way."
fi
