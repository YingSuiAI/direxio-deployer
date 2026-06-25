#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
mkdir -p "$HOME"

# shellcheck disable=SC1090
source "$ROOT/scripts/phases/s6_wire_local.sh"

[ -s "$ROOT/manifest.json" ]

jq -e '.quality_gates[] | select(.id == "openclaw_mcp_probe_passed")' "$ROOT/manifest.json" >/dev/null
jq -e '.operations[] | select(.id == "wire_local_agent_runtime") | .completion_gates[] | select(. == "agent_chat_round_trip_passed")' "$ROOT/manifest.json" >/dev/null

gates=$(_agent_runtime_required_gates openclaw native)
[[ "$gates" == *"openclaw_plugin_installed"* ]]
[[ "$gates" == *"openclaw_channel_configured"* ]]
[[ "$gates" == *"openclaw_channel_probe_passed"* ]]
[[ "$gates" == *"openclaw_mcp_registered"* ]]
[[ "$gates" == *"openclaw_mcp_probe_passed"* ]]
[[ "$gates" == *"agent_chat_round_trip_passed"* ]]

commands=$(_agent_runtime_verification_commands openclaw native "$HOME/.openclaw/direxio/nodes/codex-im/mcp.json")
[[ "$commands" == *"openclaw plugins install ./platforms/openclaw"* ]]
[[ "$commands" == *"openclaw channels status --probe"* ]]
[[ "$commands" == *"openclaw mcp set direxio"* ]]
[[ "$commands" == *"openclaw mcp reload"* ]]
[[ "$commands" == *"openclaw mcp probe direxio --json"* ]]

echo "runtime verification contract ok"
