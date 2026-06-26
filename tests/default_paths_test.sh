#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
unset P2P_WORKDIR
unset DIREXIO_WORKDIR
export DOMAIN="IM.Example.test"

# shellcheck disable=SC1090
source "$ROOT/scripts/lib/state.sh"

[ "$P2P_WORKDIR" = "$HOME/.direxio/nodes/im.example.test" ]
[ "$STATE_JSON" = "$HOME/.direxio/nodes/im.example.test/state.json" ]

(
  unset P2P_WORKDIR
  export DIREXIO_WORKDIR="$HOME/.direxio/custom-workdir"
  # shellcheck disable=SC1090
  source "$ROOT/scripts/lib/state.sh"
  [ "$P2P_WORKDIR" = "$HOME/.direxio/custom-workdir" ]
  [ "$STATE_JSON" = "$HOME/.direxio/custom-workdir/state.json" ]
)

rm -rf "$HOME/.direxio"
(
  unset DOMAIN P2P_WORKDIR DIREXIO_WORKDIR
  HOME="$HOME" bash "$ROOT/scripts/orchestrate.sh" status >/dev/null 2>&1
)
[ ! -e "$HOME/.direxio/deploy" ]
[ ! -e "$HOME/.direxio/nodes/state.json" ]

mkdir -p "$HOME/.direxio/nodes/solo.example.test"
jq -n '{domain:"solo.example.test", phase:"S3_PROVISION", resources:{instance_id:"i-solo"}}' > "$HOME/.direxio/nodes/solo.example.test/state.json"
(
  unset DOMAIN P2P_WORKDIR DIREXIO_WORKDIR
  # shellcheck disable=SC1090
  source "$ROOT/scripts/lib/state.sh"
  [ "$P2P_WORKDIR" = "$HOME/.direxio/nodes" ]
  [ "$STATE_JSON" = "$HOME/.direxio/nodes/state.json" ]
)

mkdir -p "$HOME/.direxio/nodes/second.example.test"
jq -n '{domain:"second.example.test", phase:"S6_WIRE_LOCAL", resources:{instance_id:"i-second"}}' > "$HOME/.direxio/nodes/second.example.test/state.json"
status_output=$(
  unset DOMAIN P2P_WORKDIR DIREXIO_WORKDIR
  HOME="$HOME" bash "$ROOT/scripts/orchestrate.sh" status
)
[[ "$status_output" == *"solo.example.test"* ]]
[[ "$status_output" == *"second.example.test"* ]]
[[ "$status_output" == *"i-solo"* ]]
[[ "$status_output" == *"i-second"* ]]

echo "default paths ok"
