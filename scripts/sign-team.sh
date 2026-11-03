#!/usr/bin/env bash
# Signs a built Embark.app (the Chromium build) with an Apple Development identity of your team,
# instead of the self-signed identity scripts/sign-local.sh uses. Chromium's Touch ID passkeys
# need this: they keep their keys in the keychain group <team>.org.chromium.Chromium.webauthn,
# and macOS only lets an app with a team and a provisioning profile use a keychain group.
#
# Usage: EMBARK_TEAM=ABCDE12345 scripts/sign-team.sh path/to/Embark.app
#
# The provisioning profile is the newest macOS one Xcode has for the team that covers
# dev.embark.browser and this Mac. If there is none, build once in Xcode with the team selected
# (or run xcodebuild with -allowProvisioningUpdates DEVELOPMENT_TEAM=<team>) to make one.
# The app's code identity changes from the self-signed one, so macOS asks once more for the
# "Embark Safe Storage" keychain item.
set -euo pipefail

APP="${1:?usage: EMBARK_TEAM=<team id> scripts/sign-team.sh path/to/Embark.app}"
TEAM="${EMBARK_TEAM:?set EMBARK_TEAM to your Apple developer team ID}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
UDID="$(system_profiler SPHardwareDataType | awk '/Provisioning UDID/ { print $3 }')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The newest profile for the team whose app ID matches the bundle (exactly or by wildcard) and
# that lists this Mac.
PROFILE=""
NEWEST=""
for p in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.provisionprofile \
         "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile; do
  [ -e "$p" ] || continue
  security cms -D -i "$p" > "$WORK/profile.plist" 2>/dev/null || continue
  get() { /usr/libexec/PlistBuddy -c "Print :$1" "$WORK/profile.plist" 2>/dev/null; }
  [ "$(get 'TeamIdentifier:0')" = "$TEAM" ] || continue
  get 'Platform' | grep -q OSX || continue
  get 'ProvisionedDevices' | grep -q "$UDID" || continue
  APP_ID="$(get 'Entitlements:com.apple.application-identifier')"
  case "$TEAM.$BUNDLE_ID" in $APP_ID) ;; *) continue ;; esac
  EXPIRES="$(date -j -f '%a %b %d %T %Z %Y' "$(get ExpirationDate)" +%s 2>/dev/null || echo 0)"
  [ "$EXPIRES" -gt "$(date +%s)" ] || continue
  if [ -z "$NEWEST" ] || [ "$EXPIRES" -gt "$NEWEST" ]; then PROFILE="$p"; NEWEST="$EXPIRES"; fi
done
if [ -z "$PROFILE" ]; then
  echo "No macOS provisioning profile for $TEAM.$BUNDLE_ID that includes this Mac." >&2
  echo "Build once with: xcodebuild -scheme EmbarkChromium -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM" >&2
  exit 1
fi

# An Apple Development certificate whose organizational unit is the team.
IDENTITY=""
while read -r hash name; do
  if security find-certificate -c "$name" -p | openssl x509 -noout -subject 2>/dev/null | grep -q "OU *= *$TEAM"; then
    IDENTITY="$hash"
    break
  fi
done < <(security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]*\) "\(Apple Development: .*\)"$/\1 \2/p')
if [ -z "$IDENTITY" ]; then
  echo "No Apple Development signing identity for team $TEAM in the keychain." >&2
  exit 1
fi

cat > "$WORK/app.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.application-identifier</key>
	<string>$TEAM.$BUNDLE_ID</string>
	<key>com.apple.developer.team-identifier</key>
	<string>$TEAM</string>
	<key>keychain-access-groups</key>
	<array>
		<string>$TEAM.org.chromium.Chromium.webauthn</string>
	</array>
</dict>
</plist>
EOF

sign() { codesign --force --sign "$IDENTITY" --timestamp=none "$@"; }

# Inside out, as in scripts/sign-local.sh: the framework's libraries, the framework, each
# helper, Sparkle, then the app with its profile and entitlements.
FW="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
for lib in "$FW"/Versions/A/Libraries/*.dylib; do sign "$lib"; done
sign "$FW"
for helper in "$APP"/Contents/Frameworks/*.app; do sign --preserve-metadata=entitlements "$helper"; done
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  for xpc in "$SPARKLE"/Versions/B/XPCServices/*.xpc; do
    if [ -e "$xpc" ]; then sign --preserve-metadata=entitlements "$xpc"; fi
  done
  sign "$SPARKLE/Versions/B/Autoupdate"
  sign "$SPARKLE/Versions/B/Updater.app"
  sign "$SPARKLE"
fi
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
sign --preserve-metadata=identifier --entitlements "$WORK/app.entitlements" "$APP"

codesign --verify --deep --strict "$APP"
echo "Signed $APP for team $TEAM with $(basename "$PROFILE")"
