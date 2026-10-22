#!/usr/bin/env bash
# CI helper: turns an xcodebuild log into GitHub annotations so results are visible on the
# pull request without downloading logs. Usage: ci-summarize.sh <log> <label>
LOG="$1"; LABEL="$2"
[ -f "$LOG" ] || { echo "::error title=$LABEL::no build log"; exit 0; }
echo "::notice title=$LABEL toolchain::$(xcodebuild -version | tr '\n' ' ') on macOS $(sw_vers -productVersion)"
echo "::notice title=$LABEL result::$(grep -E 'BUILD (SUCCEEDED|FAILED)' "$LOG" | tail -1), $(grep -cE '^SwiftCompile|^CompileSwift|^CompileC' "$LOG") compile steps"
grep -E ': (error|warning): |^ld: |clang: error' "$LOG" | sort -u | head -60 | while IFS= read -r line; do
  line="${line#$GITHUB_WORKSPACE/}"
  case "$line" in
    *": warning: "*) echo "::warning title=$LABEL::$line" ;;
    *) echo "::error title=$LABEL::$line" ;;
  esac
done
