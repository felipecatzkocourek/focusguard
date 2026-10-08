#!/bin/bash
# Removes the FocusGuard helper, its sudoers rule, the Firefox policy, and
# FocusGuard's section of /etc/hosts (so nothing stays blocked). Must run as root.
#
#   sudo helper/uninstall.sh
set -euo pipefail

readonly DEST="/Library/PrivilegedHelperTools/com.felipekocourek.focusguard.helper"
readonly SUDOERS="/etc/sudoers.d/focusguard"

if [[ $EUID -ne 0 ]]; then
  echo "error: run with sudo" >&2
  exit 1
fi

if [[ -x "$DEST" ]]; then
  "$DEST" clear || echo "warning: could not clear FocusGuard's /etc/hosts section" >&2
fi
# Remove the Firefox policy too, if it was installed.
"$(dirname "$0")/firefox-policy.sh" uninstall || true
rm -f "$DEST" "$SUDOERS"
echo "FocusGuard helper uninstalled."
