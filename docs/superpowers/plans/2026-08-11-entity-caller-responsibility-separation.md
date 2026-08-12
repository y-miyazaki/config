# Entity Caller Responsibility Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align entity loops with the responsibility-separation design: platform only consumes opaque `handoff_key`, detect owns event mapping and business skip, thin callers lose `prepare`, axis 2/3 intake targets branch/PR-head callers, and triage gains `triage:failed` stop.

**Architecture:** Keep `ci-loop-caller-entity` as the single-target profile. Generalize `scripts/lib/loop_entity_target.sh` to S1 (`handoff_key` from detect). Move GitHub event parsing into skill detect scripts (read `GITHUB_EVENT_PATH` / dispatch env). Retarget autofix/pr-revise skeletons to branch callers with H2-1 triggers. Document Y3 hook convention without implementing live dispatch.

**Tech Stack:** Bash, jq, Bats, GitHub Actions reusable workflows, APM skills under `.apm/packages/common/.apm/skills/`

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md` (E1–E18).
- Edit SoT under `.apm/packages/common/` and `scripts/lib/`; do not hand-edit distributed `.agents/` copies as source of truth (sync/generated artifacts may update via existing sync scripts if required).
- Work on **`main` checkout only** — do **not** create a git worktree.
- Do **not** create git commits unless the user explicitly asks.
- TDD for shell helpers and detect scripts (Bats RED→GREEN).
- No Backlog/Notion implementation; no live triage→autofix auto-dispatch body.

## File map

| Path | Responsibility |
| --- | --- |
| `scripts/lib/loop_entity_target.sh` | Build single-target matrix from detect JSON using opaque `result.handoff_key` |
| `test/bats/scripts/lib/loop_entity_target.bats` | S1 contract tests |
| `.apm/packages/common/.apm/skills/issue-triage/scripts/detect_issue.sh` | Event hydrate + `handoff_key` + `triage:failed` skip + existing bot skip |
| `.apm/packages/common/.apm/skills/issue-triage/scripts/labels.json` | Add `triage:failed` |
| `.apm/packages/common/.apm/skills/issue-triage/references/category-fsm.md` | Document failed stop + R2 |
| `.apm/packages/common/.apm/skills/issue-triage/SKILL.md` | Apply `triage:failed` on unsafe partial failure; no repository_dispatch |
| `test/bats/.apm/packages/common/issue-triage/detect_issue.bats` | handoff_key / failed / event_path tests |
| `.github/workflows/on-loop-issue-triage.yaml` | Thin caller: remove `prepare`; optional dispatch-only `detect_domain_env_json` |
| `.github/workflows/on-loop-issue-autofix.yaml` | H2-1 intake → `ci-loop-caller.yaml` (stub detect still skips) |
| `.github/workflows/on-loop-pr-revise.yaml` | R-A intake → `ci-loop-caller.yaml` (stub skip) |
| `.apm/packages/common/.apm/skills/issue-autofix/scripts/detect_autofix.sh` | Keep skip; accept ISSUE_NUMBER / event hydrate for future D4 |
| `docs/explanation/loop-engineering/loop-caller-reusable-design.md` | Entity section = E1–E18 |
| `docs/explanation/loop-engineering/workflows/loop-issue-triage-workflow-design.md` | Remove prepare; note event_path detect |
| `.apm/packages/common/.apm/skills/issue-autofix/scripts/hooks/README.md` (or short comment in SKILL) | Y3 path convention only |

---

### Task 1: S1 `handoff_key` in `loop_entity_target.sh`

**Files:**
- Modify: `scripts/lib/loop_entity_target.sh`
- Test: `test/bats/scripts/lib/loop_entity_target.bats`

**Interfaces:**
- Consumes: detect JSON with `skip`, optional `result.handoff_key`, opaque `result`, `verifier_context`
- Produces: `build_entity_target_matrix` → `[]` when skip; one element with `.handoff_key` copied from detect when skip=false; exit 1 if skip=false and `handoff_key` empty

- [ ] **Step 1: Write the failing tests**

Replace/extend `test/bats/scripts/lib/loop_entity_target.bats` so the success case requires detect-supplied `handoff_key` (not `issue_number`-derived), and add a failure case:

```bash
@test "build_entity_target_matrix uses detect handoff_key" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7","issue_number":7},"verifier_context":"Issue #7"}' \
        > "${BATS_TEST_TMPDIR}/d.json"
    run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-triage" "issue-triage" "do triage" "L1" "none"
    [ "$status" -eq 0 ]
    run jq -e 'length == 1 and .[0].handoff_key == "entity:issue:7"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "build_entity_target_matrix fails when skip false and handoff_key missing" {
    printf '%s' '{"status":"ok","skip":false,"result":{"issue_number":7}}' > "${BATS_TEST_TMPDIR}/d.json"
    run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-triage" "issue-triage" "x" "L1" "none"
    [ "$status" -ne 0 ]
}
```

Keep the existing skip→`[]` test.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats test/bats/scripts/lib/loop_entity_target.bats`  
Expected: FAIL on handoff_key / missing-key cases (current code synthesizes key from `issue_number`).

- [ ] **Step 3: Implement minimal S1 builder**

In `build_entity_target_matrix`:

1. After skip check, read `handoff_key="$(jq -r '.result.handoff_key // empty' <<< "${detect_json}")"`.
2. If empty, print error `build_entity_target_matrix: result.handoff_key required when skip=false` and return 1.
3. Remove requirement on `issue_number` for matrix identity (may still pass through in `result` / `target_json` if present).
4. Set matrix `.handoff_key` and `target_json.key` from that string.
5. Build `target_json.entity` generically from optional `result.entity` object if present; otherwise `{ "handoff_key": $handoff_key }` only — do **not** hardcode `kind: "issue"`.
6. In `build_entity_target_prompt`, remove the hardcoded line preferring GitHub Issue API; keep level/delivery/may_edit constraints only (skill owns API wording).

Example core identity extraction:

```bash
handoff_key="$(jq -r '.result.handoff_key // empty' <<< "${detect_json}")"
if [[ -z ${handoff_key} ]]; then
    echo "build_entity_target_matrix: result.handoff_key required when skip=false" >&2
    return 1
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats test/bats/scripts/lib/loop_entity_target.bats`  
Expected: PASS

- [ ] **Step 5: Stage only (no commit)**

```bash
git add scripts/lib/loop_entity_target.sh test/bats/scripts/lib/loop_entity_target.bats
git status
```

---

### Task 2: `triage:failed` catalog + detect skip + `handoff_key` emission

**Files:**
- Modify: `.apm/packages/common/.apm/skills/issue-triage/scripts/labels.json`
- Modify: `.apm/packages/common/.apm/skills/issue-triage/scripts/detect_issue.sh`
- Modify: `.apm/packages/common/.apm/skills/issue-triage/references/category-fsm.md`
- Modify: `.apm/packages/common/.apm/skills/issue-triage/SKILL.md`
- Test: `test/bats/.apm/packages/common/issue-triage/detect_issue.bats`

**Interfaces:**
- Consumes: `ISSUE_*` env and/or `GITHUB_EVENT_PATH` + `GITHUB_EVENT_NAME` (Task 3 may add hydrate; this task can emit `handoff_key` from `ISSUE_NUMBER` first)
- Produces: `result.handoff_key` = `entity:issue:${ISSUE_NUMBER}`; skip when labels contain `triage:failed`

- [ ] **Step 1: Write failing detect tests**

```bash
@test "emits handoff_key entity:issue:N for human opened issue" {
    run env ISSUE_NUMBER=42 ISSUE_TITLE='Crash on save' ISSUE_BODY='steps' \
        ISSUE_LABELS_JSON='[]' ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.handoff_key == "entity:issue:42"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips when triage:failed label present" {
    run env ISSUE_NUMBER=1 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["needs-triage","triage:failed"]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `bats test/bats/.apm/packages/common/issue-triage/detect_issue.bats`  
Expected: FAIL on new assertions.

- [ ] **Step 3: Implement label + detect changes**

Add to `labels.json`:

```json
"triage:failed": {
  "color": "b60205",
  "description": "Automated triage failed; human must clear before retry"
}
```

In `should_skip_issue` (or adjacent), if `ISSUE_LABELS_JSON` contains `triage:failed`, return skip.

In `build_result_json`, add:

```bash
handoff_key "entity:issue:${ISSUE_NUMBER}"
```

(via `json_object` string field — follow existing helper patterns).

Update `category-fsm.md` and `SKILL.md`: failed stop (E7); Agent may apply `triage:failed` on unsafe failure; must not `repository_dispatch` (X4).

- [ ] **Step 4: Run bats — expect PASS**

Run: `bats test/bats/.apm/packages/common/issue-triage/detect_issue.bats test/bats/.apm/packages/common/issue-triage/label_fsm.bats`

- [ ] **Step 5: Stage only (no commit)**

```bash
git add .apm/packages/common/.apm/skills/issue-triage/ \
  test/bats/.apm/packages/common/issue-triage/
```

---

### Task 3: Hydrate detect from `GITHUB_EVENT_PATH` (remove caller mapping)

**Files:**
- Modify: `.apm/packages/common/.apm/skills/issue-triage/scripts/detect_issue.sh`
- Test: `test/bats/.apm/packages/common/issue-triage/detect_issue.bats`
- Modify: `.github/workflows/on-loop-issue-triage.yaml`

**Interfaces:**
- Consumes: If `ISSUE_NUMBER` unset and `GITHUB_EVENT_PATH` is a file, parse issue/comment/sender into the same env fields; for `workflow_dispatch`, require `ISSUE_NUMBER` (from `detect_domain_env_json`) and optionally `gh api` fill of title/body/labels when those env vars empty
- Produces: same detect JSON as Task 2

- [ ] **Step 1: Write failing hydrate test**

```bash
@test "hydrates ISSUE_* from GITHUB_EVENT_PATH when ISSUE_NUMBER unset" {
    cat > "${BATS_TEST_TMPDIR}/event.json" <<'EOF'
{
  "action": "opened",
  "issue": {"number": 9, "title": "T", "body": "B", "labels": [{"name": "bug"}]},
  "sender": {"login": "alice", "type": "User"}
}
EOF
    run env -u ISSUE_NUMBER GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        GITHUB_EVENT_NAME=issues \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.handoff_key == "entity:issue:9" and .result.issue_number == 9' <<< "${output}"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement `hydrate_issue_env_from_event` in detect_issue.sh**

Before validation in `main`:

1. If `ISSUE_NUMBER` non-empty, keep current env-based path (tests + dispatch overrides).
2. Else if `GITHUB_EVENT_PATH` file exists, `jq` extract fields (same shape as former prepare job).
3. Else error `ISSUE_NUMBER or GITHUB_EVENT_PATH required`.

For `workflow_dispatch` with only `ISSUE_NUMBER`: if title/body/labels empty and `gh` + `GH_TOKEN`/`GITHUB_TOKEN` available, fetch issue; if fetch impossible in unit tests, tests pass explicit env.

- [ ] **Step 4: Thin `on-loop-issue-triage.yaml`**

Remove entire `prepare` job. Single `loop` job:

```yaml
jobs:
  loop:
    permissions:
      actions: write
      contents: write
      copilot-requests: write # zizmor: ignore[excessive-permissions]
      issues: write
      pull-requests: write
    uses: ./.github/workflows/ci-loop-caller-entity.yaml
    with:
      # ... existing agent/budget/skill fields ...
      detect_domain_env_json: ${{ github.event_name == 'workflow_dispatch' && format('{{"ISSUE_NUMBER":"{0}"}}', inputs.issue_number) || '{}' }}
      detect_script: .agents/skills/issue-triage/scripts/detect_issue.sh
```

Do **not** pass issue body through `detect_domain_env_json` (newline rejection). Rely on `GITHUB_EVENT_PATH` inside the reusable detect job checkout environment (Actions always sets it for `issues` / `issue_comment`).

- [ ] **Step 5: Run bats + actionlint on the workflow**

```bash
bats test/bats/.apm/packages/common/issue-triage/detect_issue.bats
actionlint .github/workflows/on-loop-issue-triage.yaml
```

Expected: PASS / no errors.

- [ ] **Step 6: Stage only (no commit)**

---

### Task 4: Axis 2/3 intake → branch caller (H2-1 / R-A stubs)

**Files:**
- Modify: `.github/workflows/on-loop-issue-autofix.yaml`
- Modify: `.github/workflows/on-loop-pr-revise.yaml`
- Modify: `.apm/packages/common/.apm/skills/issue-autofix/scripts/detect_autofix.sh` (comment + optional ISSUE_NUMBER accept; still `skip: true`)
- Modify: `.apm/packages/common/.apm/skills/pr-revise/SKILL.md` (note R-A)
- Test: existing stub bats must still pass

**Interfaces:**
- Autofix caller uses `ci-loop-caller.yaml` with stub detect, `may_edit: false` or true with empty allowlist — **keep stub skip** so execute does not run meaningfully
- Triggers: `issues: [labeled]`, `repository_dispatch` types include `loop-issue-autofix`, `workflow_dispatch`
- Concurrency: prefer `loop-autofix-${{ github.event.issue.number || github.event.client_payload.issue_number || inputs.issue_number || github.run_id }}` under group prefix documented in workflow comments (D4 partial; full Fixes #N skip deferred until autofix detect is real)

- [ ] **Step 1: Rewrite `on-loop-issue-autofix.yaml` without prepare**

Mirror thin branch callers (`on-loop-docs-updater.yaml` shape): one `loop` job → `ci-loop-caller.yaml`, stub detect path, low budget, `delivery: none` or `open_pr` left for future — for stub keep `delivery: none`, `may_edit: false`, detect always skips.

Add triggers:

```yaml
on:
  issues:
    types: [labeled]
  repository_dispatch:
    types: [loop-issue-autofix]
  workflow_dispatch:
    inputs:
      issue_number:
        description: Issue number
        required: false
        type: string
```

Pass minimal `detect_domain_env_json` for dispatch/label number when needed without bodies.

- [ ] **Step 2: Rewrite `on-loop-pr-revise.yaml` similarly → `ci-loop-caller.yaml`**

Keep stub detect; `workflow_dispatch` (+ optional future `repository_dispatch` type `loop-pr-revise`).

- [ ] **Step 3: Run stub bats + actionlint + ghalint on the two workflows**

```bash
bats test/bats/.apm/packages/common/issue-autofix/detect_autofix.bats \
     test/bats/.apm/packages/common/pr-revise/detect_pr_revise.bats
actionlint .github/workflows/on-loop-issue-autofix.yaml .github/workflows/on-loop-pr-revise.yaml
```

- [ ] **Step 4: Stage only (no commit)**

---

### Task 5: Y3 hook convention + docs sync

**Files:**
- Create: `.apm/packages/common/.apm/skills/issue-autofix/scripts/hooks/README.md` (convention only; no live dispatcher required)
- Modify: `docs/explanation/loop-engineering/loop-caller-reusable-design.md` (entity section)
- Modify: `docs/explanation/loop-engineering/workflows/loop-issue-triage-workflow-design.md`
- Modify: `docs/superpowers/specs/2026-08-11-issue-triage-entity-loops-design.md` — short pointer to responsibility-separation spec at top

**Interfaces:**
- Document hook path: `scripts/hooks/on_detect_dispatch.sh` (name locked here) invoked later by platform when `result.dispatch_requested == true`; **this task does not wire platform invoke yet** unless a 5-line optional no-op call is trivial — prefer document-only to avoid scope creep
- Docs must state: profile split = enumeration; branch = anchor; S1 handoff_key; no prepare; axis 2/3 = branch callers

- [ ] **Step 1: Write hooks README**

Content: X4/Y3; Agent never dispatches; detect sets flags; future platform runs allowlisted hook; `event_type: loop-issue-autofix`; payload must include `issue_number` for D4 concurrency.

- [ ] **Step 2: Update reusable design entity section**

Replace “GitHub object only / prepare map” wording with E1–E18 summary and link to `2026-08-11-entity-caller-responsibility-separation-design.md`.

- [ ] **Step 3: Update triage workflow design**

Caller shape:

```text
on-loop-issue-triage.yaml
  loop → ci-loop-caller-entity
    detect → loop-entity-detect (detect_issue.sh reads GITHUB_EVENT_PATH)
```

- [ ] **Step 4: markdown-link-check on touched docs if available**

```bash
# use repo's usual markdown validation entry if quick; otherwise note deferred
```

- [ ] **Step 5: Stage only (no commit)**

---

### Task 6: Verification sweep

**Files:** none new

- [ ] **Step 1: Run all related bats**

```bash
bats test/bats/scripts/lib/loop_entity_target.bats \
     test/bats/.apm/packages/common/issue-triage/detect_issue.bats \
     test/bats/.apm/packages/common/issue-triage/label_fsm.bats \
     test/bats/.apm/packages/common/issue-autofix/detect_autofix.bats \
     test/bats/.apm/packages/common/pr-revise/detect_pr_revise.bats
```

Expected: all PASS

- [ ] **Step 2: Lint workflows**

```bash
actionlint .github/workflows/on-loop-issue-triage.yaml \
  .github/workflows/on-loop-issue-autofix.yaml \
  .github/workflows/on-loop-pr-revise.yaml \
  .github/workflows/ci-loop-caller-entity.yaml
```

- [ ] **Step 3: Confirm no accidental commit; worktree not created**

```bash
git branch --show-current   # expect main
git status -sb
```

- [ ] **Step 4: Summarize residual risks**

- Live Actions dogfood still needs secrets  
- Y3 platform invoke not wired  
- D4 Fixes #N skip not in stub detect  
- Distributed `.agents/` copies may lag until sync  

---

## Self-review

1. **Spec coverage:** E14/E15→Task1; E4/E7→Task2; E17→Task3; E9/E10/E16→Task4; E12/E13 docs→Task5; E11 partial (concurrency comment + future detect).
2. **Placeholders:** none intentional; open items listed as deferred residuals.
3. **Type consistency:** `handoff_key` string on `result`; matrix `.handoff_key` mirrors it.

## Execution handoff

Plan saved to `docs/superpowers/plans/2026-08-11-entity-caller-responsibility-separation.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — this session, executing-plans style, checkpoints between tasks  

**Which approach?** (Reminder: stay on `main`, no worktree, no commits unless you ask.)
