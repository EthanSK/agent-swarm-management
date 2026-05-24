#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

./scripts/build-mac-app.sh

source_app="$repo_root/dist/Agent Swarm Management.app"
target_app="/Applications/Agent Swarm Management.app"

if [ ! -d "$source_app" ]; then
  echo "[install:mac] Missing built app at $source_app"
  exit 1
fi

if [ -d "$target_app" ]; then
  osascript -e 'tell application "Agent Swarm Management" to quit' >/dev/null 2>&1 &
  quit_pid=$!
  for _ in {1..20}; do
    if ! kill -0 "$quit_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
  if kill -0 "$quit_pid" >/dev/null 2>&1; then
    kill "$quit_pid" >/dev/null 2>&1 || true
  fi
  pkill -x AgentSwarmManagement >/dev/null 2>&1 || true
  trash_target="$HOME/.Trash/Agent Swarm Management $(date +%Y%m%d-%H%M%S).app"
  mv "$target_app" "$trash_target"
fi

ditto "$source_app" "$target_app"
xattr -dr com.apple.quarantine "$target_app" >/dev/null 2>&1 || true

echo "[install:mac] Installed $target_app"
