#!/usr/bin/env bash
# Downloads the latest stable Chromium Embedded Framework build for this Mac into Vendor/cef
# and builds libcef_dll_wrapper. Needs: curl, python3, cmake, Xcode command line tools.
#
# To use a CEF you built yourself (scripts/build-cef.sh, with H.264) instead of the prebuilt one:
#   CEF_ARCHIVE=/path/to/cef_binary_..._minimal.tar.bz2 scripts/fetch-cef.sh   # local file
#   CEF_URL=https://.../cef_binary_..._minimal.tar.bz2 scripts/fetch-cef.sh    # download
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/cef"
case "$(uname -m)" in
  arm64) PLATFORM=macosarm64 ;;
  x86_64) PLATFORM=macosx64 ;;
  *) echo "Unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$ROOT/Vendor"
if [ -n "${CEF_ARCHIVE:-}" ]; then
  ARCHIVE="$CEF_ARCHIVE"
  echo "Using $ARCHIVE"
else
  if [ -z "${CEF_URL:-}" ]; then
    INDEX_URL="https://cef-builds.spotifycdn.com/index.json"
    echo "Reading $INDEX_URL for $PLATFORM"
    FILE=$(curl -fsSL "$INDEX_URL" | python3 -c '
import json, sys
platform = sys.argv[1]
versions = json.load(sys.stdin)[platform]["versions"]
stable = next(v for v in versions if v["channel"] == "stable")
print(next(f["name"] for f in stable["files"] if f["type"] == "minimal"))
' "$PLATFORM")
    CEF_URL="https://cef-builds.spotifycdn.com/$FILE"
  fi
  ARCHIVE="$ROOT/Vendor/$(basename "$CEF_URL")"
  echo "Downloading $(basename "$CEF_URL")"
  curl -fL "$CEF_URL" -o "$ARCHIVE"
fi
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xjf "$ARCHIVE" -C "$DEST" --strip-components=1
[ -n "${CEF_ARCHIVE:-}" ] || rm "$ARCHIVE"

echo "Building libcef_dll_wrapper"
cmake -S "$DEST" -B "$DEST/build" -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH="$(uname -m)"
cmake --build "$DEST/build" --target libcef_dll_wrapper -j "$(sysctl -n hw.ncpu)"

echo "Done. CEF is in $DEST"
