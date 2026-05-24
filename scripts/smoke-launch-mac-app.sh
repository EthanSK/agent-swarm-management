#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$repo_root/dist/Agent Swarm Management.app}"
health_url="${AGENT_SWARM_HEALTH_URL:-http://127.0.0.1:17391/health}"
keep_running=false

if [ "${2:-}" = "--keep-running" ]; then
  keep_running=true
fi

if [ ! -d "$app_path" ]; then
  echo "[smoke:mac] App bundle missing: $app_path" >&2
  exit 1
fi

before_count="$(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'AgentSwarmManagement-*.ips' 2>/dev/null | wc -l | tr -d ' ')"

osascript -e 'tell application "Agent Swarm Management" to quit' >/dev/null 2>&1 || true
pkill -x AgentSwarmManagement >/dev/null 2>&1 || true
open -n "$app_path"

for _ in {1..20}; do
  if curl -fsS "$health_url" >/tmp/agent-swarm-management-health.json 2>/tmp/agent-swarm-management-health.err; then
    after_count="$(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'AgentSwarmManagement-*.ips' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$after_count" != "$before_count" ]; then
      echo "[smoke:mac] New crash report appeared during launch smoke." >&2
      cat /tmp/agent-swarm-management-health.err >&2 || true
      exit 1
    fi

    echo "[smoke:mac] Launch OK: $health_url"
    cat /tmp/agent-swarm-management-health.json
    echo

    if [ "$keep_running" != "true" ]; then
      osascript -e 'tell application "Agent Swarm Management" to quit' >/dev/null 2>&1 || true
      pkill -x AgentSwarmManagement >/dev/null 2>&1 || true
    fi
    exit 0
  fi
  sleep 0.5
done

cat /tmp/agent-swarm-management-health.err >&2 || true
echo "[smoke:mac] Launch did not produce a healthy local endpoint." >&2
exit 1
