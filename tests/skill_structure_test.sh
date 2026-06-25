#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

required=(
  SKILL.md
  README.md
  README_zh.md
  scripts/orchestrate.sh
  scripts/destroy.sh
  scripts/phases/s6_wire_local.sh
  references/agent-targets.md
  references/runtime-wiring.md
)

for path in "${required[@]}"; do
  [ -s "$path" ] || {
    echo "missing or empty required file: $path" >&2
    exit 1
  }
done

grep -q 'direxio/message-server:latest' SKILL.md
grep -q 'DIREXIO_DOMAIN' scripts/phases/s6_wire_local.sh
grep -q 'DIREXIO_AGENT_TOKEN' scripts/phases/s6_wire_local.sh
grep -q 'DIREXIO_AGENT_ROOM_ID' scripts/phases/s6_wire_local.sh
grep -q '@direxio/local-mcp' scripts/phases/s6_wire_local.sh
grep -q '@direxio/agent-plugins' SKILL.md
grep -q 'npx -y -p @direxio/agent-plugins@latest' scripts/phases/s6_wire_local.sh
grep -q '简体中文](README_zh.md)' README.md
grep -q '通用 Agent Skill' README_zh.md
grep -q 'PROJECT_ROOT/.cursor/skills/direxio-deployer' references/agent-targets.md
grep -q 'PROJECT_ROOT/.github/copilot/mcp.json' references/agent-targets.md

if grep -RE '(^|[^[:alnum:]_])([a-z0-9-]+\.)*example\.com([^[:alnum:]_]|$)' SKILL.md references scripts README.md README_zh.md >/dev/null; then
  echo "published docs/scripts must use placeholders such as __DOMAIN__, not example.com-style domains" >&2
  exit 1
fi

if grep -RE '(^|[^[:alnum:]_])([a-z0-9-]+\.)*direxio\.ai([^[:alnum:]_]|$)' SKILL.md references scripts README.md README_zh.md >/dev/null; then
  echo "published docs/scripts must use placeholders such as __DOMAIN__, not real Direxio-owned domains" >&2
  exit 1
fi

echo "skill structure ok"
