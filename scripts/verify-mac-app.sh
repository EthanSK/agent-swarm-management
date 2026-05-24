#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$repo_root/dist/Agent Swarm Management.app}"
executable_path="$app_path/Contents/MacOS/AgentSwarmManagement"
sparkle_path="$app_path/Contents/Frameworks/Sparkle.framework"
sparkle_binary="$sparkle_path/Versions/B/Sparkle"

fail() {
  echo "[verify:mac] $*" >&2
  exit 1
}

[ -d "$app_path" ] || fail "App bundle missing: $app_path"
[ -x "$executable_path" ] || fail "Executable missing or not executable: $executable_path"
[ -d "$sparkle_path" ] || fail "Sparkle.framework missing from Contents/Frameworks"
[ -f "$sparkle_binary" ] || fail "Sparkle binary missing at $sparkle_binary"

# Guard against the exact crash class seen during local testing:
# dyld found an @rpath Sparkle dependency, but the bundled app did not expose
# Contents/Frameworks in the executable's runtime search paths.
otool -L "$executable_path" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle' \
  || fail "Executable is not linked against bundled Sparkle"

otool -l "$executable_path" | grep -q '@executable_path/../Frameworks' \
  || fail "Executable is missing @executable_path/../Frameworks LC_RPATH"

plutil -extract SUFeedURL raw -o - "$app_path/Contents/Info.plist" >/dev/null \
  || fail "Info.plist missing Sparkle SUFeedURL"

plutil -extract SUPublicEDKey raw -o - "$app_path/Contents/Info.plist" >/dev/null \
  || fail "Info.plist missing Sparkle SUPublicEDKey"

codesign --verify --strict "$sparkle_path"
codesign --verify --deep --strict "$app_path"

echo "[verify:mac] OK: $app_path"
