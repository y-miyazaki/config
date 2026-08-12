# Issue Triage Entity Loops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add LE entity-loop support with a working `issue-triage` axis (label FSM + analysis/questions) and stub skeletons for `issue-autofix` and `pr-revise`.

**Architecture:** New reusable `ci-loop-caller-entity.yaml` binds one GitHub entity event to a single-target matrix and reuses `ci-loop-agent`. Axis 1 ships detect + FSM helpers + skill + dogfood caller. Axes 2–3 ship stub detect/skill + skeleton callers that always skip.

**Tech Stack:** Bash detect scripts (`scripts/lib/all.sh`), Bats, GitHub Actions reusable workflows, APM skills under `.apm/packages/common/.apm/skills/`, Cursor/Claude engine via existing loop-execute.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-11-issue-triage-entity-loops-design.md` (D1–D27).
- Edit SoT under `.apm/packages/common/`; sync distributed copies only via existing sync scripts when required.
- **Do not create git commits** (user directive for this effort).
- TDD for all new Bash helpers and detect scripts: RED → run fail → GREEN → run pass.
- Temporary files under `tmp/` only.
- Stub axes: silent skip + run-log path (no “not implemented” Issue comment).
- Mentions are out of scope; no `@` trigger wiring.

## File Structure

| Path | Responsibility |
| --- | --- |
| `.apm/packages/common/.apm/skills/issue-triage/scripts/lib/label_fsm.sh` | Allowlist catalog, ensure-label, transition helpers (pure Bash + `gh`/`jq` seams) |
| `.apm/packages/common/.apm/skills/issue-triage/scripts/detect_issue.sh` | Entity detect: env → skip/facts JSON |
| `.apm/packages/common/.apm/skills/issue-triage/scripts/labels.json` | Allowlisted labels + color/description |
| `.apm/packages/common/.apm/skills/issue-triage/SKILL.md` | L1 triage workflow + prompt rules (no self-censorship; low-confidence → needs-triage) |
| `.apm/packages/common/.apm/skills/issue-triage/references/*` | Portable checklist / FSM / output notes |
| `.apm/packages/common/.apm/skills/issue-autofix/scripts/detect_autofix.sh` | Stub → always `skip: true` |
| `.apm/packages/common/.apm/skills/issue-autofix/SKILL.md` | Stub skill (DO NOT implement fixes yet) |
| `.apm/packages/common/.apm/skills/pr-revise/scripts/detect_pr_revise.sh` | Stub → always `skip: true` |
| `.apm/packages/common/.apm/skills/pr-revise/SKILL.md` | Stub skill |
| `scripts/lib/loop_entity_target.sh` (or action-local lib) | Build single-element `target_matrix` + prompt from detect JSON + caller inputs |
| `.github/actions/loop-entity-detect/action.yaml` | Composite: run detect_script once, budget check light-touch, emit `should_run` / `target_matrix` / handoff |
| `.github/workflows/ci-loop-caller-entity.yaml` | Reusable entity caller → entity-detect → `ci-loop-agent` matrix |
| `.github/workflows/on-loop-issue-triage.yaml` | Issue/comment events → entity caller |
| `.github/workflows/on-loop-issue-autofix.yaml` | `autofix` label / `workflow_dispatch` → stub |
| `.github/workflows/on-loop-pr-revise.yaml` | `workflow_dispatch` only skeleton |
| `test/bats/.apm/packages/common/issue-triage/*.bats` | FSM + detect tests |
| `test/bats/.apm/packages/common/issue-autofix/*.bats` | Stub detect |
| `test/bats/.apm/packages/common/pr-revise/*.bats` | Stub detect |
| `test/bats/scripts/lib/loop_entity_target.bats` | Matrix builder tests |
| `docs/explanation/loop-engineering/workflows/loop-issue-triage-workflow-design.md` | Workflow design |
| `docs/explanation/loop-engineering/loop-engineering-design.md` | Status row update |
| `docs/explanation/loop-engineering/loop-caller-reusable-design.md` | Document entity profile |

---

### Task 1: Label catalog + FSM helpers (TDD)

**Files:**
- Create: `.apm/packages/common/.apm/skills/issue-triage/scripts/labels.json`
- Create: `.apm/packages/common/.apm/skills/issue-triage/scripts/lib/label_fsm.sh`
- Test: `test/bats/.apm/packages/common/issue-triage/label_fsm.bats`

**Interfaces:**
- Consumes: none
- Produces:
  - `label_fsm_load_catalog <path>` → sets associative data via jq queries
  - `label_fsm_is_allowlisted <name>` → 0/1
  - `label_fsm_next_state <current_labels_json> <event>` → prints recommended labels to add/remove as JSON `{"add":[],"remove":[]}`
  - `label_fsm_ensure_labels_exist` is **not** unit-tested against live GitHub; test pure “would create” list from missing names vs catalog

- [ ] **Step 1: Write failing catalog/FSM tests**

```bash
# test/bats/.apm/packages/common/issue-triage/label_fsm.bats
@test "allowlist includes needs-triage bug feature triage:needs-info triage:ready" {
  run label_fsm_is_allowlisted "triage:needs-info"
  [ "$status" -eq 0 ]
  run label_fsm_is_allowlisted "random-label"
  [ "$status" -eq 1 ]
}

@test "opened event recommends needs-triage when unlabeled" {
  run label_fsm_next_state '[]' opened
  [ "$status" -eq 0 ]
  run jq -e '.add | index("needs-triage") != null' <<< "${output}"
  [ "$status" -eq 0 ]
}

@test "ready transition removes needs-info and needs-triage" {
  run label_fsm_next_state '["needs-triage","triage:needs-info","bug"]' mark_ready
  [ "$status" -eq 0 ]
  run jq -e '
    (.add | index("triage:ready") != null)
    and (.remove | index("triage:needs-info") != null)
    and (.remove | index("needs-triage") != null)
  ' <<< "${output}"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests — expect FAIL** (functions missing)

Run: `bats test/bats/.apm/packages/common/issue-triage/label_fsm.bats`  
Expected: FAIL / source errors

- [ ] **Step 3: Implement `labels.json` + `label_fsm.sh` minimally**

`labels.json` keys: `needs-triage`, `bug`, `feature`, `question`, `documentation`, `triage:needs-info`, `triage:ready`, `autofix` (catalog may include `autofix` for axis 2 even if triage does not apply it). Each entry: `color`, `description`.

Implement allowlist check + `label_fsm_next_state` for events: `opened`, `mark_needs_info`, `mark_ready`, `human_retriage` (clears ready when appropriate — keep minimal).

- [ ] **Step 4: Run tests — expect PASS**

Run: `bats test/bats/.apm/packages/common/issue-triage/label_fsm.bats`  
Expected: PASS

- [ ] **Step 5: No commit** (user directive)

---

### Task 2: `detect_issue.sh` (TDD)

**Files:**
- Create: `.apm/packages/common/.apm/skills/issue-triage/scripts/detect_issue.sh`
- Sync lib: ensure `scripts/lib` mirror via existing skill lib sync if required by package conventions
- Test: `test/bats/.apm/packages/common/issue-triage/detect_issue.bats`

**Interfaces:**
- Consumes: env `ISSUE_NUMBER`, `ISSUE_TITLE`, `ISSUE_BODY`, `ISSUE_LABELS_JSON`, `ISSUE_EVENT_NAME`, `ISSUE_EVENT_ACTION`, `ISSUE_COMMENT_ID` (optional), `ISSUE_ACTOR`, `ISSUE_ACTOR_TYPE`, `ISSUE_COMMENT_USER_TYPE` (optional)
- Produces stdout JSON:
  ```json
  {
    "status": "ok",
    "skip": false,
    "result": {
      "issue_number": 1,
      "title": "...",
      "body": "...",
      "labels": ["needs-triage"],
      "event_name": "issues",
      "event_action": "opened",
      "comment_id": null,
      "actor": "alice",
      "actor_type": "User"
    },
    "verifier_context": "Issue #1: ..."
  }
  ```

- [ ] **Step 1: Write failing detect tests**

```bash
@test "skips when actor_type is Bot" {
  run env ISSUE_NUMBER=1 ISSUE_TITLE=t ISSUE_BODY=b ISSUE_LABELS_JSON='[]' \
    ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
    ISSUE_ACTOR=dependabot ISSUE_ACTOR_TYPE=Bot \
    bash "${DETECT_SCRIPT}"
  [ "$status" -eq 0 ]
  run jq -e '.skip == true and .status == "ok"' <<< "${output}"
  [ "$status" -eq 0 ]
}

@test "emits facts for human opened issue" {
  run env ISSUE_NUMBER=42 ISSUE_TITLE='Crash on save' ISSUE_BODY='steps' \
    ISSUE_LABELS_JSON='[]' ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
    ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
    bash "${DETECT_SCRIPT}"
  [ "$status" -eq 0 ]
  run jq -e '.skip == false and .result.issue_number == 42' <<< "${output}"
  [ "$status" -eq 0 ]
}

@test "skips issue_comment from Bot" {
  run env ISSUE_NUMBER=1 ISSUE_TITLE=t ISSUE_BODY=b ISSUE_LABELS_JSON='["triage:needs-info"]' \
    ISSUE_EVENT_NAME=issue_comment ISSUE_EVENT_ACTION=created \
    ISSUE_COMMENT_ID=9 ISSUE_ACTOR=bot ISSUE_ACTOR_TYPE=User \
    ISSUE_COMMENT_USER_TYPE=Bot \
    bash "${DETECT_SCRIPT}"
  [ "$status" -eq 0 ]
  run jq -e '.skip == true' <<< "${output}"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bats test/bats/.apm/packages/common/issue-triage/detect_issue.bats`

- [ ] **Step 3: Implement detect_issue.sh**

Follow changelog/ci-sweeper header conventions; `set -euo pipefail`; source skill `lib/all.sh`; emit via `json_object` helpers. Missing `ISSUE_NUMBER` → `status=error` exit 1.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: No commit**

---

### Task 3: Entity target matrix builder (TDD)

**Files:**
- Create: `scripts/lib/loop_entity_target.sh`
- Test: `test/bats/scripts/lib/loop_entity_target.bats`
- Wire export from `scripts/lib/all.sh` only if required by action runtime (prefer action copies skill-synced lib OR source this file explicitly in the composite action)

**Interfaces:**
- Consumes: detect JSON path, `loop_name`, `skill_name`, `prompt_instructions`, `level`, `delivery`
- Produces: slim `target_matrix` JSON array with one element:
  - `handoff_key`: `entity:issue:<number>`
  - `prompt`: `Run the {skill} skill.` + `## Change Detection Result` + detect JSON + `## Instructions` + `## Constraints`
  - `target_json`: per spec sketch (`entity`, `event`, `from.ref` empty or default SHA, `to.branch`, `finalize: none`)
  - `verifier_context`: from detect

- [ ] **Step 1: Failing test — skip detect yields empty matrix helper return code**

```bash
@test "build_entity_target_matrix returns empty array when skip true" {
  printf '%s' '{"status":"ok","skip":true,"result":{}}' > "${BATS_TEST_TMPDIR}/d.json"
  run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-triage" "issue-triage" "triage pls" "L1" "none"
  [ "$status" -eq 0 ]
  run jq -e 'type == "array" and length == 0' <<< "${output}"
  [ "$status" -eq 0 ]
}

@test "build_entity_target_matrix emits one target when skip false" {
  printf '%s' '{"status":"ok","skip":false,"result":{"issue_number":7},"verifier_context":"Issue #7"}' \
    > "${BATS_TEST_TMPDIR}/d.json"
  run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-triage" "issue-triage" "do triage" "L1" "none"
  [ "$status" -eq 0 ]
  run jq -e 'length == 1 and .[0].handoff_key == "entity:issue:7"' <<< "${output}"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run — FAIL**
- [ ] **Step 3: Implement builder**
- [ ] **Step 4: Run — PASS**
- [ ] **Step 5: No commit**

---

### Task 4: `loop-entity-detect` composite + `ci-loop-caller-entity`

**Files:**
- Create: `.github/actions/loop-entity-detect/action.yaml`
- Create: `.github/workflows/ci-loop-caller-entity.yaml`
- Modify: `docs/explanation/loop-engineering/loop-caller-reusable-design.md` (entity profile section)
- Test: prefer contract assertions via Bats on builder (Task 3); validate YAML with `actionlint` when available locally (`mise` / existing validate path) — **do not** require live Actions run

**Interfaces:**
- Caller inputs (subset): mirror needed agent/*, `detect_script`, `loop_name`, `skill_name`, `prompt_instructions`, `level=L1`, `delivery=none`, `may_edit=false`, `write_target=report`, `allowlist` unused but required for agent parity (use `""` or `.loop/**` only if platform demands non-empty — match L1 patterns in docs), `engine`, `branch_state`, budget inputs, `detect_domain_env_json`
- Secrets: `AGENT_TOKEN`, bot app optional for run-log push

**Behavior:**
1. Checkout
2. Export `detect_domain_env_json` into env (copy pattern from `ci-loop-caller.yaml`)
3. Run `detect_script` → `tmp/detect.json`
4. Budget check: either call existing loop-detect budget helpers **or** defer full budget to a follow-up if coupling is too high — **minimum:** honor `budget_max_runs_per_day` with a small shell read of `.loop/loop-run-log.md` counts for `loop_name` (document limitation if simplified)
5. `build_entity_target_matrix` → outputs `should_run`, `target_matrix`, upload handoff artifact compatible with `ci-loop-agent` expectations (inspect `loop-detect` handoff format and match keys `result` / `verifier_context` per target)

- [ ] **Step 1: Inspect handoff artifact format** from `.github/actions/loop-detect` (or docs) and note required filenames/keys in the PR/plan scratch under `tmp/` notes if needed
- [ ] **Step 2: Implement composite action**
- [ ] **Step 3: Implement `ci-loop-caller-entity.yaml`** jobs: `detect` → `execute` (matrix `ci-loop-agent`) → optional `record-skip`
- [ ] **Step 4: Set execute permissions** including `issues: write` for triage side effects (entity profile default)
- [ ] **Step 5: `finalize_enabled: false`** when `delivery=none`
- [ ] **Step 6: Run actionlint / workflow validate if repo script exists**

Run (example): `bash scripts/...` or `actionlint .github/workflows/ci-loop-caller-entity.yaml`  
Expected: no errors

- [ ] **Step 7: No commit**

---

### Task 5: `issue-triage` skill + dogfood caller

**Files:**
- Create: `.apm/packages/common/.apm/skills/issue-triage/SKILL.md`
- Create: references (`category-fsm.md`, `category-prompt-rules.md`, `common-output-format` thin pointers)
- Create: `.github/workflows/on-loop-issue-triage.yaml`
- Create: `docs/explanation/loop-engineering/workflows/loop-issue-triage-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md` status for `issue-triage`

**Skill must encode:**
- Auto-classify when confident; else `needs-triage` only
- Questions via Issue comments; no AskUserQuestion reliance
- Forbid question self-censorship
- On `triage:ready`: guidance to add `autofix` / assign-command — do not start axis 2
- Use `gh` for labels/comments; ensure allowlisted labels via catalog
- Path: automation only for this cycle (Interactive optional later)

**Caller `on`:**

```yaml
on:
  issues:
    types: [opened, reopened, labeled, unlabeled]
  issue_comment:
    types: [created]
  workflow_dispatch:
    inputs:
      issue_number:
        required: true
        type: string
```

Map `github.event` → `detect_domain_env_json` fields in a prelude job or inline `jq` before `uses: ci-loop-caller-entity`.

- [ ] **Step 1: Write skill + references**
- [ ] **Step 2: Write workflow design doc (docs-updater template structure)**
- [ ] **Step 3: Write `on-loop-issue-triage.yaml` wiring entity caller**
- [ ] **Step 4: Update LE design status table** (`issue-triage` → Dogfood L1 / in progress)
- [ ] **Step 5: Sync skill lib if package requires** (`scripts/self/apm/sync_skill_lib.sh` for new skill)
- [ ] **Step 6: No commit**

---

### Task 6: Axis 2 & 3 stubs (TDD)

**Files:**
- Create stub skills + detect scripts as in File Structure
- Create `on-loop-issue-autofix.yaml` (`on: issues types: [labeled]` filtered in detect to `autofix` only + `workflow_dispatch`)
- Create `on-loop-pr-revise.yaml` (`workflow_dispatch` only)
- Tests: stub detect always skip

- [ ] **Step 1: Failing stub tests**

```bash
@test "detect_autofix always skips" {
  run bash "${DETECT_SCRIPT}"
  [ "$status" -eq 0 ]
  run jq -e '.skip == true and .status == "ok"' <<< "${output}"
  [ "$status" -eq 0 ]
}
```

Same for `detect_pr_revise`.

- [ ] **Step 2: Run — FAIL**
- [ ] **Step 3: Implement stub detects + minimal SKILL.md**
- [ ] **Step 4: Skeleton callers via `ci-loop-caller-entity`**
- [ ] **Step 5: Run — PASS**
- [ ] **Step 6: No commit**

---

### Task 7: Verification sweep

- [ ] **Step 1: Run all new Bats**

```bash
bats test/bats/.apm/packages/common/issue-triage/*.bats \
     test/bats/.apm/packages/common/issue-autofix/*.bats \
     test/bats/.apm/packages/common/pr-revise/*.bats \
     test/bats/scripts/lib/loop_entity_target.bats
```

Expected: all PASS

- [ ] **Step 2: actionlint entity + three on-loop workflows**
- [ ] **Step 3: Confirm no git commits were created for this work** (`git status` clean of accidental commit attempts; leave changes unstaged/staged as user prefers)
- [ ] **Step 4: Manual checklist in workflow design: dispatch dry-run requires secrets — document as deferred dogfood**

---

## Self-Review (plan vs spec)

| Spec item | Task |
| --- | --- |
| D6 three skeletons + axis1 body | Tasks 4–6 |
| D7 label FSM | Task 1 + skill Task 5 |
| D8/D9 labels vs `.loop/` | Tasks 1, 4, 5 |
| D10–D12 triggers / write / no mention | Task 5–6 callers |
| D13–D16 labels + events + bot skip | Tasks 1–2, 5 |
| D17–D20 autofix/revise stubs + draft future | Task 6 + docs |
| D21–D25 prompt rules | Task 5 skill |
| D26–D27 LE-native + entity caller | Task 4 |

Placeholders avoided; stub comment vs skip resolved to **silent skip**.

## Execution Handoff

Plan saved to `docs/superpowers/plans/2026-08-11-issue-triage-entity-loops.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — this session with executing-plans checkpoints  

Which approach?

**Note:** No git commits during execution (per your instruction).
