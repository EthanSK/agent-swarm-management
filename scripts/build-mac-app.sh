#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

app_name="Agent Swarm Management"
executable_name="AgentSwarmManagement"
version="$(node -p "require('./package.json').version")"
build_number="${AGENT_SWARM_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
commit_sha="${AGENT_SWARM_COMMIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}"
configuration="${CONFIGURATION:-release}"
dist_dir="$repo_root/dist"
release_dir="$repo_root/release"
app_path="$dist_dir/$app_name.app"
zip_name="Agent-Swarm-Management-${version}-mac-universal.zip"
zip_path="$release_dir/$zip_name"

echo "[build:mac] Building $app_name $version ($build_number / $commit_sha)"

npm run version:sync >/dev/null
npm run version:check

rm -rf "$dist_dir" "$release_dir"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks" "$release_dir"

swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"

cp "$bin_path/$executable_name" "$app_path/Contents/MacOS/$executable_name"
chmod +x "$app_path/Contents/MacOS/$executable_name"

sparkle_framework="$bin_path/Sparkle.framework"
if [ ! -d "$sparkle_framework" ]; then
  sparkle_framework="$(find "$repo_root/.build" -path '*/Sparkle.framework' -type d | head -1)"
fi
if [ ! -d "$sparkle_framework" ]; then
  echo "[build:mac] Sparkle.framework was not found after swift build."
  exit 1
fi
ditto "$sparkle_framework" "$app_path/Contents/Frameworks/Sparkle.framework"

APP_VERSION="$version" BUILD_NUMBER="$build_number" perl \
  -e 'while (<>) { s/__APP_VERSION__/$ENV{APP_VERSION}/g; s/__BUILD_NUMBER__/$ENV{BUILD_NUMBER}/g; print }' \
  < "$repo_root/Resources/Info.plist.template" \
  > "$app_path/Contents/Info.plist"

printf 'APPL????' > "$app_path/Contents/PkgInfo"

if ! otool -l "$app_path/Contents/MacOS/$executable_name" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$app_path/Contents/MacOS/$executable_name"
fi

identity="${CODE_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity="-"
fi

echo "[build:mac] Signing with identity: $identity"
codesign --force --options runtime --sign "$identity" "$app_path/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --options runtime --entitlements "$repo_root/build/entitlements.mac.plist" --sign "$identity" "$app_path"

"$repo_root/scripts/verify-mac-app.sh" "$app_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
shasum -a 256 "$zip_path" > "$zip_path.sha256"

if [ "${NOTARIZE:-false}" = "true" ]; then
  if [ "$identity" = "-" ]; then
    echo "[build:mac] NOTARIZE=true requires CODE_SIGN_IDENTITY."
    exit 1
  fi
  : "${APPLE_ID:?APPLE_ID is required for notarization}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required for notarization}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for notarization}"

  echo "[build:mac] Submitting for notarization"
  xcrun notarytool submit "$zip_path" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

  xcrun stapler staple "$app_path"
  rm -f "$zip_path" "$zip_path.sha256"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
  shasum -a 256 "$zip_path" > "$zip_path.sha256"
fi

cp "$zip_path" "$release_dir/Agent-Swarm-Management-latest-mac-universal.zip"
awk '{ print $1 "  Agent-Swarm-Management-latest-mac-universal.zip" }' "$zip_path.sha256" \
  > "$release_dir/Agent-Swarm-Management-latest-mac-universal.zip.sha256"

echo "[build:mac] Wrote $app_path"
echo "[build:mac] Wrote $zip_path"
