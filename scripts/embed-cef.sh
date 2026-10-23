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
FW="$FRAMEWORKS/Chromium Embedded Framework.framework"
rm -rf "${FW:?}"
cp -R "$CEF_FRAMEWORK" "$FRAMEWORKS/"

# CEF ships a flat framework (binary, Libraries/ and Resources/ at the top level), which Xcode's
# bundle validation rejects. Rebuild it in the standard versioned layout with top-level symlinks,
# so the paths Chromium uses still resolve.
if [ ! -d "$FW/Versions" ]; then
  mkdir -p "$FW/Versions/A"
  for entry in "$FW"/*; do
    [ "$(basename "$entry")" = "Versions" ] && continue
    mv "$entry" "$FW/Versions/A/"
  done
  ln -s A "$FW/Versions/Current"
  for entry in "$FW/Versions/A"/*; do
    ln -s "Versions/Current/$(basename "$entry")" "$FW/$(basename "$entry")"
  done
fi

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
