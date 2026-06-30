# Remove External JSON CLI Dependency Design

## Goal

Remove the old external JSON CLI dependency from deployer runtime scripts, tests, and documentation. JSON parsing, validation, construction, and state mutation should use Node.js, which is already part of the npm-distributed deployer contract.

## Scope

This migration covers every repository reference to the old external JSON CLI in:

- `scripts/`
- `tests/`
- `SKILL.md`
- `README.md`
- `README_zh.md`
- `references/`
- package validation docs and tests

The deployment state machine, destroy flow, pricing estimate, S6 local wiring, and runtime verification behavior must remain unchanged.

## Architecture

Add `scripts/json.mjs` as the portable JSON command-line helper. It is dependency-free Node.js and ships in the npm package. Bash scripts use `scripts/lib/json.sh` helper functions rather than invoking an external JSON CLI.

The helper supports:

- `get <file> <path> [default]`: read a dotted path from a JSON file.
- `stdin-get <path> [default]`: read a dotted path from stdin.
- `assert <file> <preset> [args...]`: validate common JSON predicates used by tests and runtime gates.
- `build <preset> [args...]`: emit structured JSON for payloads, state fixtures, credentials, MCP config, and pricing output.
- `mutate <file> <preset> [args...]`: atomically update a JSON file.
- `route53-zones`, `route53-record-present`, and other narrow commands for AWS JSON shapes that previously used external JSON filters.

The command surface is intentionally explicit. It should not implement a general JSON expression language for production scripts, because that recreates a hard-to-audit mini-language and makes quoting fragile across shells.

## Platform Rules

- Node is the JSON runtime for Windows PowerShell, Git Bash/MSYS2, Linux, and macOS.
- Scripts call Node through `scripts/lib/json.sh`, which resolves `node`, `node.exe`, or `NODE`.
- Windows path behavior remains owned by existing path helpers; JSON helper commands treat paths as ordinary strings and do not convert them unless explicitly asked elsewhere.
- Documentation must not instruct users to install an external JSON CLI.

## Testing

Add a focused helper test before migration:

```bash
bash tests/json_helper_test.sh
```

The test covers path reads, defaults, stdin reads, builders, assertions, and atomic mutation.

After migration, run:

```bash
rg -n '<legacy-json-cli-pattern>' scripts tests README.md README_zh.md SKILL.md references AGENTS.md package.json
bash tests/json_helper_test.sh
bash tests/skill_structure_test.sh
bash tests/s6_wire_local_test.sh
bash tests/render_userdata_remote_nodes_test.sh
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
git diff --check
```

The `rg` command must return no matches.
