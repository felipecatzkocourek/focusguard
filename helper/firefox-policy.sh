#!/bin/bash
# Installs or removes FocusGuard's Firefox policy. Must run as root.
#
#   sudo helper/firefox-policy.sh install
#   sudo helper/firefox-policy.sh uninstall
#
# Why: Firefox keeps its own DNS cache, so after /etc/hosts changes it keeps using old
# answers for a minute or more. Blocking (and unblocking) only takes effect once that
# cache expires or Firefox restarts.
#
# The policy sets Firefox's DNS cache lifetime to 0, so every new connection asks macOS
# (which has its own fast cache, flushed by the helper on every change). Nothing else
# about Firefox's networking or security settings is touched.
#
# Only FocusGuard's keys are added or removed; other policies in the file are kept.
set -euo pipefail

readonly PLIST="/Library/Preferences/org.mozilla.firefox.plist"
readonly BUDDY="/usr/libexec/PlistBuddy"
readonly PREFS=(network.dnsCacheExpiration network.dnsCacheExpirationGracePeriod)

if [[ $EUID -ne 0 ]]; then
  echo "error: run with sudo" >&2
  exit 1
fi

# PlistBuddy "Delete" fails when the key is missing; that's fine here.
delete() { "$BUDDY" -c "Delete $1" "$PLIST" >/dev/null 2>&1 || true; }

case "${1:-}" in
  install)
    delete ":EnterprisePoliciesEnabled"
    "$BUDDY" -c "Add :EnterprisePoliciesEnabled bool true" "$PLIST"
    "$BUDDY" -c "Print :Preferences" "$PLIST" >/dev/null 2>&1 || "$BUDDY" -c "Add :Preferences dict" "$PLIST"
    for pref in "${PREFS[@]}"; do
      delete ":Preferences:$pref"
      "$BUDDY" -c "Add :Preferences:$pref dict" "$PLIST"
      "$BUDDY" -c "Add :Preferences:$pref:Value integer 0" "$PLIST"
      "$BUDDY" -c "Add :Preferences:$pref:Status string locked" "$PLIST"
    done
    chown root:wheel "$PLIST"
    chmod 644 "$PLIST"
    echo "Firefox policy installed. Restart Firefox once for it to take effect."
    ;;
  uninstall)
    [[ -f "$PLIST" ]] || exit 0
    for pref in "${PREFS[@]}"; do delete ":Preferences:$pref"; done
    # Remove what we created if nothing else is left in the file.
    if ! "$BUDDY" -c "Print :Preferences" "$PLIST" 2>/dev/null | grep -q " = "; then
      delete ":Preferences"
    fi
    if [[ "$("$BUDDY" -c "Print" "$PLIST" | grep -c " = ")" -le 1 ]]; then
      rm -f "$PLIST"
    fi
    echo "Firefox policy removed."
    ;;
  *)
    echo "usage: sudo $0 install|uninstall" >&2
    exit 1
    ;;
esac
