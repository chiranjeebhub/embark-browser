#!/usr/bin/env bash
# Downloads the latest stable Chromium Embedded Framework build for this Mac into Vendor/cef
# and builds libcef_dll_wrapper. Needs: curl, python3, cmake, Xcode command line tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/cef"
case "$(uname -m)" in
  arm64) PLATFORM=macosarm64 ;;
  x86_64) PLATFORM=macosx64 ;;
  *) echo "Unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

INDEX_URL="https://cef-builds.spotifycdn.com/index.json"
echo "Reading $INDEX_URL for $PLATFORM"
FILE=$(curl -fsSL "$INDEX_URL" | python3 -c '
import json, sys
platform = sys.argv[1]
versions = json.load(sys.stdin)[platform]["versions"]
stable = next(v for v in versions if v["channel"] == "stable")
print(next(f["name"] for f in stable["files"] if f["type"] == "minimal"))
' "$PLATFORM")

echo "Downloading $FILE"
mkdir -p "$ROOT/Vendor"
curl -fL "https://cef-builds.spotifycdn.com/$FILE" -o "$ROOT/Vendor/$FILE"
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xjf "$ROOT/Vendor/$FILE" -C "$DEST" --strip-components=1
rm "$ROOT/Vendor/$FILE"

echo "Building libcef_dll_wrapper"
cmake -S "$DEST" -B "$DEST/build" -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH="$(uname -m)"
cmake --build "$DEST/build" --target libcef_dll_wrapper -j "$(sysctl -n hw.ncpu)"

echo "Done. CEF is in $DEST"
