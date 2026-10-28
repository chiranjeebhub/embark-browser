#!/usr/bin/env bash
# One-time setup for automatic updates. Run it on the Mac that signs Embark, from the repo:
#
#   scripts/setup-updates.sh
#
# It
#   1. creates the update signing key (EdDSA) in your login keychain, or reuses it,
#   2. saves its private half and the "Embark Local Dev" code signing identity as GitHub
#      repository secrets for the release workflow,
#   3. writes the public key into project.yml, which you then commit.
#
# Needs: gh signed in with access to the repository, and the identity that
# scripts/sign-local.sh creates (run that once first). macOS may ask to allow exporting the key.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${REPO:-chiranjeebhub/embark-browser}"
SPARKLE_VERSION=2.9.6
ACCOUNT=dev.embark.browser
SIGNING_DIR="$HOME/Library/Application Support/Embark/Signing"
KEYCHAIN="$SIGNING_DIR/embark-signing.keychain-db"

gh auth status >/dev/null || { echo "Sign in with 'gh auth login' first." >&2; exit 1; }
[ -f "$KEYCHAIN" ] || { echo "No signing identity yet. Run scripts/sign-local.sh on a built Embark.app first." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

echo "Downloading Sparkle $SPARKLE_VERSION tools"
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
  | tar -xJ -C "$WORK" ./bin/generate_keys

# Creates the key the first time; later runs print the same one.
"$WORK/bin/generate_keys" --account "$ACCOUNT" >/dev/null
PUBLIC_KEY="$("$WORK/bin/generate_keys" --account "$ACCOUNT" -p)"
"$WORK/bin/generate_keys" --account "$ACCOUNT" -x "$WORK/sparkle-private-key" >/dev/null

echo "Exporting the \"Embark Local Dev\" identity"
security unlock-keychain -p "$(cat "$SIGNING_DIR/keychain-password")" "$KEYCHAIN"
P12_PASSWORD="$(openssl rand -hex 24)"
security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$P12_PASSWORD" -o "$WORK/identity.p12"

echo "Saving repository secrets on $REPO"
gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$WORK/sparkle-private-key"
base64 < "$WORK/identity.p12" | tr -d '\n' | gh secret set EMBARK_SIGNING_P12 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set EMBARK_SIGNING_P12_PASSWORD --repo "$REPO"

sed -i '' -E "s|^( *SPARKLE_PUBLIC_KEY:).*|\1 \"$PUBLIC_KEY\"|" "$ROOT/project.yml"

cat <<DONE

Done. Public key: $PUBLIC_KEY
It is now in project.yml. Commit that change, then publish a release (docs/RELEASING.md).

Keep the private key safe: it stays in your login keychain (item "Private key for signing
Sparkle updates", account $ACCOUNT). Without it, installed copies can't verify new updates.
DONE
