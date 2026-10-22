#!/usr/bin/env bash
# Xcode build phase for EmbarkChromium: copies the Chromium framework and the helper apps
# into Embark.app/Contents/Frameworks, where CEF expects them.
set -euo pipefail

APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
FRAMEWORKS="$APP/Contents/Frameworks"
CEF_FRAMEWORK="$SRCROOT/Vendor/cef/$CONFIGURATION/Chromium Embedded Framework.framework"
[ -d "$CEF_FRAMEWORK" ] || CEF_FRAMEWORK="$SRCROOT/Vendor/cef/Release/Chromium Embedded Framework.framework"
HELPER="$BUILD_DIR/$CONFIGURATION/Embark Helper.app"

mkdir -p "$FRAMEWORKS"
rsync -a --delete "$CEF_FRAMEWORK" "$FRAMEWORKS/"

# Chromium launches differently named helpers for each process type.
for suffix in "" " (GPU)" " (Renderer)" " (Plugin)" " (Alerts)"; do
  name="Embark Helper$suffix"
  id_suffix=$(echo "$suffix" | tr -d ' ()' | tr '[:upper:]' '[:lower:]')
  dest="$FRAMEWORKS/$name.app"
  rm -rf "$dest"
  cp -R "$HELPER" "$dest"
  if [ "$name" != "Embark Helper" ]; then
    mv "$dest/Contents/MacOS/Embark Helper" "$dest/Contents/MacOS/$name"
  fi
  plutil -replace CFBundleExecutable -string "$name" "$dest/Contents/Info.plist"
  plutil -replace CFBundleName -string "$name" "$dest/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "dev.embark.browser.helper${id_suffix:+.$id_suffix}" "$dest/Contents/Info.plist"
done
