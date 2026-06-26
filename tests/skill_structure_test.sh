#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

required=(
  AGENTS.md
  SKILL.md
  README.md
  README_zh.md
  scripts/orchestrate.sh
  scripts/orchestrate.ps1
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
grep -q 'DIREXIO_CC_CONNECT_REPO' scripts/phases/s6_wire_local.sh
grep -q 'DIREXIO_LOCAL_PATH_STYLE' scripts/phases/s6_wire_local.sh
grep -q 'PLATFORMS_INCLUDE=matrix' scripts/phases/s6_wire_local.sh
grep -q 'YingSuiAI/connect.git' scripts/phases/s6_wire_local.sh
grep -q 'DIREXIO_CC_CONNECT_AGENT' scripts/phases/s6_wire_local.sh
grep -q 'orchestrate.ps1' README.md
grep -q 'cc-connect' SKILL.md
if grep -R '@direxio/agent-plugins\|@direxio/local-mcp' SKILL.md scripts README.md README_zh.md references >/dev/null; then
  echo "current docs/scripts must not reference legacy agent plugin or local MCP packages" >&2
  exit 1
fi
grep -q '简体中文](README_zh.md)' README.md
grep -q '通用 Agent Skill' README_zh.md
grep -q 'PROJECT_ROOT/.cursor/skills/direxio-deployer' references/agent-targets.md
grep -q '@direxio/connent' references/agent-targets.md
grep -q 'direxio-connect daemon install' references/agent-targets.md
grep -q 'acp antigravity claudecode codex copilot cursor devin gemini iflow kimi opencode pi qoder reasonix tmux' references/agent-targets.md

if grep -R 'YingSuiAI/cc-connect\|github.com/YingSuiAI/cc-connect' SKILL.md scripts README.md README_zh.md references AGENTS.md >/dev/null; then
  echo "current docs/scripts must use YingSuiAI/connect, not the old YingSuiAI/cc-connect repository" >&2
  exit 1
fi

if grep -RE '(^|[^[:alnum:]_])([a-z0-9-]+\.)*example\.com([^[:alnum:]_]|$)' SKILL.md references scripts README.md README_zh.md >/dev/null; then
  echo "published docs/scripts must use placeholders such as __DOMAIN__, not example.com-style domains" >&2
  exit 1
fi

if grep -RE '(^|[^[:alnum:]_])([a-z0-9-]+\.)*direxio\.ai([^[:alnum:]_]|$)' SKILL.md references scripts README.md README_zh.md >/dev/null; then
  echo "published docs/scripts must use placeholders such as __DOMAIN__, not real Direxio-owned domains" >&2
  exit 1
fi

if grep -RE 'agentp2p\.im|54\.161\.73\.211' SKILL.md references scripts README.md README_zh.md >/dev/null; then
  echo "published docs/scripts must use placeholders such as __DOMAIN__ and __EIP__, not session-specific domains or IPs" >&2
  exit 1
fi

if grep -R 'DIREXIO_CREDENTIALS_FILE' SKILL.md references scripts README.md README_zh.md >/dev/null; then
  echo "published docs/scripts must not use DIREXIO_CREDENTIALS_FILE for the local bridge; use direct DIREXIO_* env" >&2
  exit 1
fi

if grep -RE 'fixed order.*\.codex.*\.hermes|\.codex.*checked before.*\.hermes' SKILL.md references scripts README.md README_zh.md >/dev/null; then
  echo "published docs/scripts must not describe stale Codex-before-Hermes runtime detection" >&2
  exit 1
fi

echo "skill structure ok"
