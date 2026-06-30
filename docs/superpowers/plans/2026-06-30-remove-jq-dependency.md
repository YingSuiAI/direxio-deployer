# Remove External JSON CLI Dependency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace all external JSON CLI usage with the deployer's Node.js JSON helper.

**Architecture:** Introduce a dependency-free Node helper plus a Bash resolver wrapper, migrate runtime scripts first, then tests and docs, and enforce the removal with structure tests and a repository-wide grep. The helper uses explicit subcommands instead of a general expression evaluator.

**Tech Stack:** Node.js ESM, Bash, existing shell tests.

---

## File Structure

- Create `scripts/json.mjs`: portable JSON helper CLI.
- Create `scripts/lib/json.sh`: Bash functions that locate Node and invoke `scripts/json.mjs`.
- Create `tests/json_helper_test.sh`: focused helper tests.
- Modify runtime scripts under `scripts/`: replace JSON construction, reads, assertions, and mutations.
- Modify tests under `tests/`: replace fixture construction and JSON assertions.
- Modify docs under `SKILL.md` and `references/`: remove external JSON CLI install guidance.
- Modify `tests/skill_structure_test.sh`: require new helper files and enforce no legacy JSON CLI references.

### Task 1: Helper Test

**Files:**
- Create: `tests/json_helper_test.sh`

- [x] **Step 1: Write failing tests**

Add tests that call `node scripts/json.mjs get`, `stdin-get`, `build`, `assert`, and `mutate`.

- [x] **Step 2: Verify red**

Run: `bash tests/json_helper_test.sh`
Expected: FAIL because `scripts/json.mjs` does not exist.

### Task 2: JSON Helper

**Files:**
- Create: `scripts/json.mjs`
- Create: `scripts/lib/json.sh`

- [x] **Step 1: Implement helper commands**

Implement the explicit command set needed by runtime scripts and tests.

- [x] **Step 2: Verify helper**

Run: `bash tests/json_helper_test.sh`
Expected: PASS.

### Task 3: Runtime Migration

**Files:**
- Modify: `scripts/lib/state.sh`
- Modify: `scripts/lib/aws.sh`
- Modify: `scripts/lib/ops.sh`
- Modify: `scripts/lib/operation_report.sh`
- Modify: `scripts/orchestrate.sh`
- Modify: `scripts/destroy.sh`
- Modify: `scripts/pricing-estimate.sh`
- Modify: `scripts/phases/s3_provision.sh`
- Modify: `scripts/phases/s5_init_tokens.sh`
- Modify: `scripts/phases/s6_wire_local.sh`
- Modify: `scripts/phases/s7_verify_e2e.sh`

- [x] **Step 1: Replace JSON reads and writes**

Use `json_get`, `json_stdin_get`, `json_build`, `json_assert`, and `json_mutate` from `scripts/lib/json.sh`.

- [x] **Step 2: Run focused runtime tests**

Run the existing targeted tests for state, S6, destroy, pricing, and status.

### Task 4: Test And Docs Migration

**Files:**
- Modify: `tests/*.sh`
- Modify: `SKILL.md`
- Modify: `references/*.md`
- Modify: `tests/skill_structure_test.sh`

- [x] **Step 1: Replace test fixtures and assertions**

Use `node scripts/json.mjs build ...` and `node scripts/json.mjs assert ...`.

- [x] **Step 2: Remove legacy JSON CLI docs**

Delete install instructions and troubleshooting guidance for the old external JSON CLI.

- [x] **Step 3: Enforce no legacy JSON CLI references**

Add a structure test scan that fails on old external JSON CLI references.

### Task 5: Verification And Commit

- [x] **Step 1: Run required validation**

Run:

```bash
bash tests/json_helper_test.sh
bash tests/skill_structure_test.sh
bash tests/s6_wire_local_test.sh
bash tests/render_userdata_remote_nodes_test.sh
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
git diff --check
```

- [x] **Step 2: Run repository-wide legacy JSON CLI scan**

Run:

```bash
rg -n '<legacy-json-cli-pattern>' scripts tests README.md README_zh.md SKILL.md references AGENTS.md package.json
```

Expected: no matches.

- [x] **Step 3: Commit**

Run:

```bash
git add scripts tests README.md README_zh.md SKILL.md references docs/superpowers/specs/<design-doc>.md docs/superpowers/plans/<plan-doc>.md
git commit -m "Replace legacy JSON CLI with Node JSON helper"
```
