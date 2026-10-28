#!/usr/bin/env bash
# Builds the Chromium Embedded Framework from source with H.264/AAC (proprietary codecs) and
# installs it into Vendor/cef, the same place scripts/fetch-cef.sh puts the prebuilt one.
#
# Prebuilt CEF from cef-builds.spotifycdn.com leaves proprietary codecs out, so MP4/H.264 and
# AAC video does not play. Building Chromium yourself is the only way to turn them on.
#
# Needs: macOS with Xcode (not just the command line tools), python3, git, cmake.
# Takes: about 120 GB of free disk, 16 GB+ of RAM, and roughly 4-10 hours on Apple silicon.
# Safe to re-run: the checkout and build output are kept, and a re-run picks up where it stopped.
#
# Settings (environment variables):
#   CEF_WORK_DIR   where Chromium is checked out and built (default ~/cef-build)
#   CEF_BRANCH     CEF/Chromium branch to build, e.g. 7258 (default: branch of current stable CEF)
#   CEF_NO_UPDATE  set to 1 to rebuild the existing checkout without fetching anything
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${CEF_WORK_DIR:-$HOME/cef-build}"
NEEDED_GB=120

case "$(uname -m)" in
  arm64) PLATFORM=macosarm64 ARCH_FLAG=--arm64-build ;;
  x86_64) PLATFORM=macosx64 ARCH_FLAG=--x64-build ;;
  *) echo "Unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

if ! xcode-select -p | grep -q "Xcode.*\.app"; then
  echo "Chromium needs the full Xcode selected (sudo xcode-select -s /Applications/Xcode.app)." >&2
  exit 1
fi

mkdir -p "$WORK"
FREE_GB=$(df -g "$WORK" | awk 'NR==2 {print $4}')
if [ ! -d "$WORK/chromium/src" ] && [ "$FREE_GB" -lt "$NEEDED_GB" ]; then
  echo "Only ${FREE_GB} GB free at $WORK; building Chromium needs about ${NEEDED_GB} GB." >&2
  echo "Free some space or point CEF_WORK_DIR at a bigger disk." >&2
  exit 1
fi

if [ -z "${CEF_BRANCH:-}" ]; then
  # Chromium 139.0.7258.x is CEF branch 7258.
  CEF_BRANCH=$(curl -fsSL https://cef-builds.spotifycdn.com/index.json | python3 -c '
import json, sys
versions = json.load(sys.stdin)[sys.argv[1]]["versions"]
stable = next(v for v in versions if v["channel"] == "stable")
print(stable["chromium_version"].split(".")[2])
' "$PLATFORM")
fi
echo "Building CEF branch $CEF_BRANCH for $PLATFORM in $WORK"

curl -fsSL https://raw.githubusercontent.com/chromiumembedded/cef/master/tools/automate/automate-git.py \
  -o "$WORK/automate-git.py"

# proprietary_codecs + ffmpeg_branding=Chrome is what turns on H.264, AAC and MP4.
# is_official_build matches how the prebuilt CEF is built (optimized, no debug checks).
# Warnings are not errors so a newer Xcode SDK than the branch was tested with still builds.
export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome treat_warnings_as_errors=false"
export CEF_ARCHIVE_FORMAT=tar.bz2

UPDATE_FLAGS=()
[ "${CEF_NO_UPDATE:-0}" = 1 ] && UPDATE_FLAGS=(--no-update --force-build)

# Keep the Mac awake for the whole build.
caffeinate -dimsu python3 "$WORK/automate-git.py" \
  --download-dir="$WORK" \
  --branch="$CEF_BRANCH" \
  "$ARCH_FLAG" \
  --no-chromium-history \
  --with-pgo-profiles \
  --no-debug-build \
  --minimal-distrib-only \
  --no-distrib-docs \
  --no-distrib-symbols \
  --distrib-subdir=embark \
  ${UPDATE_FLAGS[@]+"${UPDATE_FLAGS[@]}"}

ARCHIVE=$(ls -t "$WORK"/chromium/src/cef/binary_distrib/embark/*_minimal.tar.bz2 2>/dev/null | head -1 || true)
if [ -z "$ARCHIVE" ]; then
  echo "Build finished but no minimal distribution was found in $WORK/chromium/src/cef/binary_distrib/embark" >&2
  exit 1
fi
echo "Built $ARCHIVE"

CEF_ARCHIVE="$ARCHIVE" "$ROOT/scripts/fetch-cef.sh"
