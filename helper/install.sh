#!/bin/bash
# Installs the FocusGuard privileged helper. Must run as root.
#
#   sudo helper/install.sh <path-to-focusguard-helper-binary> <username>
#
# What it does:
#   1. Copies the helper to /Library/PrivilegedHelperTools, owned by root and not
#      writable by anyone else (so it can't be swapped for something malicious).
#   2. Adds /etc/sudoers.d/focusguard, which lets <username> run *only that binary*
#      as root without a password. The rule is syntax-checked with visudo first.
#
# The FocusGuard app runs this through the standard macOS admin password prompt.
set -euo pipefail

readonly DEST="/Library/PrivilegedHelperTools/com.felipekocourek.focusguard.helper"
readonly SUDOERS="/etc/sudoers.d/focusguard"

if [[ $EUID -ne 0 ]]; then
  echo "error: run with sudo" >&2
  exit 1
fi
if [[ $# -ne 2 ]]; then
  echo "usage: sudo $0 <helper-binary> <username>" >&2
  exit 1
fi

src="$1"
user="$2"

if [[ ! -f "$src" ]]; then
  echo "error: helper binary not found: $src" >&2
  exit 1
fi
if [[ ! "$user" =~ ^[a-z_][a-z0-9_.-]*$ ]] || ! id -u "$user" >/dev/null 2>&1; then
  echo "error: invalid user: $user" >&2
  exit 1
fi

install -d -o root -g wheel -m 755 "$(dirname "$DEST")"
install -o root -g wheel -m 755 "$src" "$DEST"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '# Managed by FocusGuard. Lets %s rewrite FocusGuard'"'"'s section of /etc/hosts.\n%s ALL=(root) NOPASSWD: %s\n' \
  "$user" "$user" "$DEST" >"$tmp"
visudo -cf "$tmp" >/dev/null
install -o root -g wheel -m 440 "$tmp" "$SUDOERS"

if sudo -l -U "$user" "$DEST" >/dev/null 2>&1; then
  echo "FocusGuard helper installed for $user."
else
  echo "warning: helper installed, but sudo does not pick up $SUDOERS." >&2
  echo "         Check that /etc/sudoers contains '#includedir /private/etc/sudoers.d'." >&2
  exit 2
fi
