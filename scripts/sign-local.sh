#!/usr/bin/env bash
# Signs a built Embark.app (the Chromium build) with a local self-signed identity, so its code
# identity stays the same across builds. macOS then keeps the "Always Allow" given to the
# Chromium Safe Storage keychain item instead of asking again after every rebuild, which it
# does for ad-hoc signed apps because their identity is the hash of each build.
#
# The identity lives in its own keychain file outside the login keychain and the repo; it is
# created on first use. Usage: scripts/sign-local.sh path/to/Embark.app
#
# Release builds are signed with the same identity, so updates keep the app's identity too. The
# release workflow passes it in EMBARK_SIGNING_P12 (base64) and EMBARK_SIGNING_P12_PASSWORD;
# scripts/setup-updates.sh exports it from this Mac.
set -euo pipefail

APP="${1:?usage: scripts/sign-local.sh path/to/Embark.app}"
NAME="Embark Local Dev"
DIR="$HOME/Library/Application Support/Embark/Signing"
KEYCHAIN="$DIR/embark-signing.keychain-db"
PASSWORD_FILE="$DIR/keychain-password"

if [ -n "${EMBARK_SIGNING_P12:-}" ]; then
  # A throwaway keychain holding the identity from the environment.
  DIR="$(mktemp -d)"
  KEYCHAIN="$DIR/embark-signing.keychain-db"
  PASSWORD_FILE="$DIR/keychain-password"
  trap 'security delete-keychain "$KEYCHAIN" 2>/dev/null; rm -rf "$DIR"' EXIT
  (umask 077; openssl rand -hex 24 > "$PASSWORD_FILE"; printf '%s' "$EMBARK_SIGNING_P12" | base64 --decode > "$DIR/identity.p12")
  PASSWORD="$(cat "$PASSWORD_FILE")"
  security create-keychain -p "$PASSWORD" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
  security import "$DIR/identity.p12" -k "$KEYCHAIN" -P "${EMBARK_SIGNING_P12_PASSWORD:?}" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
elif [ ! -f "$KEYCHAIN" ]; then
  echo "Creating the \"$NAME\" signing identity in $KEYCHAIN"
  mkdir -p "$DIR"
  chmod 700 "$DIR"
  (umask 077; openssl rand -hex 24 > "$PASSWORD_FILE")
  PASSWORD="$(cat "$PASSWORD_FILE")"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
  openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout "pass:$PASSWORD"
  security create-keychain -p "$PASSWORD" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
  security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
# Sign by certificate hash: the self-signed certificate isn't trusted system-wide, and doesn't
# need to be for a stable identity.
HASH="$(security find-certificate -c "$NAME" -Z "$KEYCHAIN" | awk '/SHA-1 hash:/ { print $3 }')"

sign() { codesign --force --sign "$HASH" --keychain "$KEYCHAIN" --timestamp=none "$@"; }

# Inside out: the framework's libraries, the framework, each helper, then the app.
FW="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
for lib in "$FW"/Versions/A/Libraries/*.dylib; do sign "$lib"; done
sign "$FW"
for helper in "$APP"/Contents/Frameworks/*.app; do sign --preserve-metadata=entitlements "$helper"; done
# Sparkle, the updater: its installer tools first, then the framework.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  for xpc in "$SPARKLE"/Versions/B/XPCServices/*.xpc; do
    if [ -e "$xpc" ]; then sign --preserve-metadata=entitlements "$xpc"; fi
  done
  sign "$SPARKLE/Versions/B/Autoupdate"
  sign "$SPARKLE/Versions/B/Updater.app"
  sign "$SPARKLE"
fi
sign --preserve-metadata=identifier,entitlements "$APP"

codesign --verify --deep --strict "$APP"
echo "Signed $APP as \"$NAME\""
