#!/usr/bin/env bash
# Creates a local, self-signed code-signing identity for building FocusGuard.
#
#   scripts/create-signing-identity.sh
#
# Why: ad-hoc signed builds get a new identity every time, so macOS forgets permissions
# such as Full Disk Access and Automation after each rebuild. Signing every build with
# the same certificate keeps the app's identity stable, so permissions stick.
#
# What it does:
#   1. Generates a self-signed certificate valid only for code signing (10 years).
#   2. Imports it with its private key into your login keychain, usable by codesign.
#   3. Trusts it for code signing in your user trust settings (macOS asks for your
#      password).
#
# It's only trusted on this Mac, by your user, for code signing. Remove it any time in
# Keychain Access (search "FocusGuard Local Signing").
set -euo pipefail

readonly NAME="FocusGuard Local Signing"
readonly KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "✓ \"$NAME\" already exists."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
password="$(uuidgen)"

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -out "$tmp/identity.p12" -passout "pass:$password"

security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$password" -T /usr/bin/codesign >/dev/null
echo "→ Trusting the certificate for code signing (macOS will ask for your password)…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "✓ Created \"$NAME\". scripts/build-app.sh will use it automatically."
else
  echo "error: the identity was imported but isn't valid for code signing." >&2
  exit 1
fi
