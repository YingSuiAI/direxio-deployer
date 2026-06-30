# Agent Runtime Notes

This skill is runtime-neutral. Claude, Codex/OpenAI, Gemini, Cursor, Copilot, OpenClaw, Hermes, and other shell-capable agents should use the same root entrypoint:

```text
SKILL.md
```

When an agent runtime supports skill metadata, point it at `SKILL.md` and use `scripts/orchestrate.sh` as the deployment command. Read `references/agent-targets.md` before installing this skill or wiring MCP/plugin access for a runtime. S6 writes current Direxio MCP/plugin variables and records the detected runtime plus target paths. After deployment, ask the user before installing or configuring the runtime-specific plugin and MCP service.

Recognition keywords:

- deploy Direxio
- resume Direxio deployment
- verify Direxio message server
- destroy Direxio AWS resources
- wire Direxio MCP/plugin
- refresh Direxio agent token

Required capabilities:

- Read local files.
- Run POSIX shell commands.
- Use `aws`, `jq`, `ssh`, `scp`, and `curl` after the user approves any missing installs.
- Preserve secrets outside the repository.
