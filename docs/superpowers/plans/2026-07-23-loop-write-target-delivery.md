# Loop Write Target and Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple loop autonomy (`level`) from agent edit semantics (`may_edit`, `write_target`, `report_file`) and platform delivery (`delivery`), so fix loops and report loops share one contract without skill-specific allowlist hacks.

**Architecture:** Four planes per `docs/superpowers/specs/2026-07-23-loop-write-target-delivery-design.md`. Platform injects planes 2–3 into `## Constraints` via `build_constraints.sh`. `delivery` stays on caller/`loop-detect` only — never in skill envelopes. Bats-first changes in `.github/actions/`; skill source in `.apm/packages/common/`; sync with `apm install --update`.

**Tech Stack:** Bash (`build_constraints.sh`, `loop-detect`), GitHub Actions reusable workflows, Bats (`test/bats/github-actions/`), APM skills (Markdown references).

## Global Constraints

- Spec source of truth: `docs/superpowers/specs/2026-07-23-loop-write-target-delivery-design.md`.
- **Phase 4 (issue/notion adapters) is out of scope** — implement enum + validation + docs only; no `gh issue create` yet.
- Skill edits: `.apm/packages/common/.apm/skills/<name>/` only. Do not edit `.agents/`, `.cursor/`, etc. directly.
- After skill edits: `apm install --update`; verify with `apm audit --ci` when touching packages.
- Workflow `inputs` / `with:` keys: **alphabetically ordered**.
- Commit only when the user asks. Plan steps say **Do not commit** unless the user requested commits for that task.
- Context fetch: prefer lean-ctx for reads/searches.

## File map

| Path                                                                            | Responsibility                                                     |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `.github/actions/loop-prompt-generate/lib/build_constraints.sh`                 | Emit `## Constraints` (may_edit, write_target, report_file)        |
| `.github/actions/loop-prompt-generate/lib/validate_loop_write_contract.sh`      | Reject invalid may_edit × write_target × delivery × level combos   |
| `.github/actions/loop-detect/lib/matrix.sh`                                     | `build_prompt_text` passes explicit contract fields to constraints |
| `.github/actions/loop-detect/lib/detect.sh`                                     | Enrich `target_json.report_file` from detect JSON                  |
| `.github/actions/loop-detect/action.yml`                                        | New inputs: `may_edit`, `write_target`, `delivery`                 |
| `.github/actions/loop-prompt-generate/action.yml`                               | New inputs mirroring contract fields                               |
| `.github/workflows/ci-loop-caller.yaml`                                         | Caller inputs + wire to `loop-detect`                              |
| `.github/workflows/ci-loop-caller-pr-scan.yaml`                                 | Same inputs (parity)                                               |
| `.github/workflows/ci-loop-caller-full-github.yaml`                             | Same inputs (parity)                                               |
| `.github/workflows/on-loop-*.yaml`                                              | Explicit `may_edit`, `write_target`, `delivery` per loop           |
| `test/bats/github-actions/loop-prompt-generate.bats`                            | Constraints unit tests                                             |
| `test/bats/github-actions/loop-write-contract.bats`                             | Combination matrix tests                                           |
| `test/bats/github-actions/loop-detect-matrix.bats`                              | Prompt integration tests                                           |
| `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`   | New inputs documented                                              |
| `docs/explanation/loop-engineering/common-loop-triage-format.md`                | Four-plane summary                                                 |
| `.apm/packages/common/.apm/skills/*/references/category-automation-envelope.md` | Skill-visible contract (5 skills)                                  |

---

### Task 1: Contract validation library (TDD)

**Files:**

- Create: `.github/actions/loop-prompt-generate/lib/validate_loop_write_contract.sh`
- Create: `test/bats/github-actions/loop-write-contract.bats`
- Test: `test/bats/github-actions/loop-write-contract.bats`

**Interfaces:**

- Produces: `validate_loop_write_contract "<may_edit>" "<write_target>" "<delivery>" "<level>"` → exit 0 valid, exit 1 + stderr message invalid.

- [ ] **Step 1: Write failing Bats tests**

Create `test/bats/github-actions/loop-write-contract.bats`:

```bash
#!/usr/bin/env bats

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VALIDATE_LIB="$(bats_workspace_root)/.github/actions/loop-prompt-generate/lib/validate_loop_write_contract.sh"

setup() {
    # shellcheck disable=SC1090
    source "${VALIDATE_LIB}"
}

@test "validate accepts may_edit false delivery log at L1" {
    run validate_loop_write_contract "false" "" "log" "L1"
    [ "$status" -eq 0 ]
}

@test "validate accepts may_edit true write_target fix delivery open_pr at L2" {
    run validate_loop_write_contract "true" "fix" "open_pr" "L2"
    [ "$status" -eq 0 ]
}

@test "validate accepts may_edit true write_target report delivery open_pr at L2" {
    run validate_loop_write_contract "true" "report" "open_pr" "L2"
    [ "$status" -eq 0 ]
}

@test "validate rejects may_edit false delivery open_pr" {
    run validate_loop_write_contract "false" "" "open_pr" "L2"
    [ "$status" -eq 1 ]
    [[ "$output" == *"may_edit: false"* ]]
}

@test "validate rejects may_edit true without write_target" {
    run validate_loop_write_contract "true" "" "open_pr" "L2"
    [ "$status" -eq 1 ]
}

@test "validate rejects may_edit true write_target report delivery issue" {
    run validate_loop_write_contract "true" "report" "issue" "L2"
    [ "$status" -eq 1 ]
}

@test "validate rejects may_edit true write_target fix delivery log" {
    run validate_loop_write_contract "true" "fix" "log" "L2"
    [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `bats test/bats/github-actions/loop-write-contract.bats -v`

Expected: FAIL — `validate_loop_write_contract: command not found` or file missing.

- [ ] **Step 3: Implement validator**

Create `.github/actions/loop-prompt-generate/lib/validate_loop_write_contract.sh`:

```bash
#!/usr/bin/env bash

validate_loop_write_contract() {
    local may_edit="${1:-}"
    local write_target="${2:-}"
    local delivery="${3:-}"
    local level="${4:-}"

    case "${may_edit}" in
        true | false) ;;
        *)
            echo "::error::may_edit must be true or false (got: ${may_edit})" >&2
            return 1
            ;;
    esac

    case "${delivery}" in
        log | issue | notion | open_pr | none) ;;
        *)
            echo "::error::delivery must be log|issue|notion|open_pr|none (got: ${delivery})" >&2
            return 1
            ;;
    esac

    if [[ ${may_edit} == "false" ]]; then
        if [[ -n ${write_target} ]]; then
            echo "::warning::write_target ignored when may_edit is false" >&2
        fi
        case "${delivery}" in
            log | issue | notion | none) return 0 ;;
            open_pr)
                echo "::error::invalid: may_edit false with delivery open_pr" >&2
                return 1
                ;;
        esac
    fi

    case "${write_target}" in
        fix | report) ;;
        "")
            echo "::error::write_target required when may_edit is true (fix or report)" >&2
            return 1
            ;;
        *)
            echo "::error::write_target must be fix or report (got: ${write_target})" >&2
            return 1
            ;;
    esac

    case "${delivery}" in
        open_pr | none) return 0 ;;
        log | issue | notion)
            echo "::error::invalid: may_edit true with delivery ${delivery}" >&2
            return 1
            ;;
    esac
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `bats test/bats/github-actions/loop-write-contract.bats -v`

Expected: 7 tests, 0 failures.

- [ ] **Step 5: Do not commit**

---

### Task 2: Rewrite `build_constraints.sh` (TDD)

**Files:**

- Modify: `.github/actions/loop-prompt-generate/lib/build_constraints.sh`
- Modify: `test/bats/github-actions/loop-prompt-generate.bats`
- Modify: `test/bats/github-actions/loop-detect-matrix.bats`

**Interfaces:**

- **Old:** `emit_loop_constraints "<level>" "<allowlist>"`
- **New:** `emit_loop_constraints "<may_edit>" "<write_target>" "<allowlist>" "<report_file>"`
- **Legacy:** `emit_loop_constraints_from_level "<level>" "<allowlist>"` — maps level→may_edit, write_target=fix, logs `::warning::deprecated`

- [ ] **Step 1: Add failing tests for new contract emission**

Append to `test/bats/github-actions/loop-prompt-generate.bats`:

```bash
@test "emit_loop_constraints emits write_target report and report_file" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "true" "report" "docs/report/tech-debt/**/*.md" "docs/report/tech-debt/2026-07-23.md"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: true"* ]]
    [[ $output == *"write_target: report"* ]]
    [[ $output == *"report_file: docs/report/tech-debt/2026-07-23.md"* ]]
    [[ $output == *"Must persist report_file"* ]]
    [[ $output != *"report alone is not sufficient"* ]]
}

@test "emit_loop_constraints emits fix persistence obligation" {
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "true" "fix" "src/**" ""
    [ "$status" -eq 0 ]
    [[ $output == *"write_target: fix"* ]]
    [[ $output == *"Must persist fixes within allowlist"* ]]
    [[ $output != *"report_file:"* ]]
}

@test "emit_loop_constraints survey omits write_target" {
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "false" "" "CHANGELOG.md" ""
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: false"* ]]
    [[ $output != *"write_target:"* ]]
}
```

- [ ] **Step 2: Run new tests — expect FAIL**

Run: `bats test/bats/github-actions/loop-prompt-generate.bats -v`

Expected: new tests FAIL; old L1/L2 tests may still pass on legacy path.

- [ ] **Step 3: Implement new `emit_loop_constraints`**

Replace body of `build_constraints.sh` with:

```bash
emit_loop_constraints() {
    local may_edit="${1:-}"
    local write_target="${2:-}"
    local allowlist="${3:-}"
    local report_file="${4:-}"

    if [[ -z ${may_edit} && -z ${allowlist} ]]; then
        return 0
    fi

    case "${may_edit}" in
        true | false) ;;
        *)
            echo "::error::may_edit must be true or false (got: ${may_edit})" >&2
            return 1
            ;;
    esac

    echo "## Constraints"
    echo "may_edit: ${may_edit}"

    if [[ ${may_edit} == "true" ]]; then
        case "${write_target}" in
            fix)
                echo "write_target: fix"
                echo "You MUST persist fixes within allowlist; survey-only output is insufficient when may_edit is true."
                ;;
            report)
                echo "write_target: report"
                if [[ -n ${report_file} ]]; then
                    echo "report_file: ${report_file}"
                fi
                echo "You MUST persist report_file within allowlist; source fixes outside allowlist are forbidden unless the caller verifier explicitly allows closed-set paths."
                ;;
            *)
                echo "::error::write_target must be fix or report when may_edit is true" >&2
                return 1
                ;;
        esac
    fi

    echo "Do not claim files were modified unless git would show real changes."
    if [[ -n ${allowlist} ]]; then
        echo "Allowed paths: ${allowlist}."
        echo "Do NOT modify any other files."
    fi
}

emit_loop_constraints_from_level() {
    local level="${1:-}"
    local allowlist="${2:-}"
    local may_edit="false"
    echo "::warning::emit_loop_constraints_from_level is deprecated; pass may_edit and write_target explicitly" >&2
    case "${level}" in
        L1) may_edit="false" ;;
        L2 | L3) may_edit="true" ;;
        "")
            emit_loop_constraints "" "" "${allowlist}" ""
            return $?
            ;;
        *)
            echo "::error::Invalid level: ${level}" >&2
            return 1
            ;;
    esac
    if [[ ${may_edit} == "true" ]]; then
        emit_loop_constraints "${may_edit}" "fix" "${allowlist}" ""
    else
        emit_loop_constraints "${may_edit}" "" "${allowlist}" ""
    fi
}
```

- [ ] **Step 4: Update legacy tests to use explicit API or `emit_loop_constraints_from_level`**

Change existing L1/L2/L3 tests to call `emit_loop_constraints_from_level` OR update to explicit `emit_loop_constraints "false" "" ...` / `emit_loop_constraints "true" "fix" ...` and delete level-mapping tests that duplicate deprecated path.

- [ ] **Step 5: Run Bats — expect PASS**

Run: `bats test/bats/github-actions/loop-prompt-generate.bats -v`

- [ ] **Step 6: Do not commit**

---

### Task 3: Wire contract through `loop-detect` and `matrix.sh`

**Files:**

- Modify: `.github/actions/loop-detect/action.yml` — add inputs `delivery`, `may_edit`, `write_target` (alphabetically among inputs)
- Modify: `.github/actions/loop-detect/lib/detect.sh` — export env vars; call `validate_loop_write_contract` at startup; generalize target_json enrich for `report_file`
- Modify: `.github/actions/loop-detect/lib/matrix.sh` — extend `build_prompt_text` to accept `may_edit`, `write_target`, `report_file`; call new `emit_loop_constraints`
- Modify: `test/bats/github-actions/loop-detect-matrix.bats`

**Interfaces:**

- Consumes: Task 1 `validate_loop_write_contract`, Task 2 `emit_loop_constraints`
- `build_prompt_text` new trailing args: `$10 may_edit`, `$11 write_target`, `$12 report_file`
- `enrich_target_json_with_detect_fields target_json detect_result` adds `.report_file = detect.report_file` when non-empty

- [ ] **Step 1: Add `enrich_target_json_with_detect_fields` in `detect.sh`**

After `enrich_target_json_with_ci_context`, add:

```bash
function enrich_target_json_with_detect_fields {
    local target_json="$1"
    local detect_result="$2"
    local report_file
    report_file="$(jq -r '.report_file // ""' <<< "${detect_result}" 2>/dev/null || echo "")"
    if [[ -z ${report_file} ]]; then
        printf '%s' "${target_json}"
        return 0
    fi
    jq -c --arg rf "${report_file}" '. + {report_file: $rf}' <<< "${target_json}"
}
```

In `append_detect_candidate`, chain after CI enrich:

```bash
target_json="$(enrich_target_json_with_detect_fields "${target_json}" "${detect_result}")"
```

- [ ] **Step 2: Update `build_prompt_text` in `matrix.sh`**

Add parameters 10–12; replace line 87:

```bash
emit_loop_constraints "${may_edit}" "${write_target}" "${allowlist}" "${report_file}"
```

Pass `report_file` from `jq -r '.report_file // ""' <<< "${detect_result}"`.

- [ ] **Step 3: Add loop-detect action inputs and env**

In `action.yml` inputs (alphabetical):

```yaml
delivery:
  default: open_pr
  description: "Platform delivery: log | issue | notion | open_pr | none"
  required: false
may_edit:
  default: ""
  description: "Agent edit gate: true | false (empty = legacy level fallback)"
  required: false
write_target:
  default: ""
  description: "Agent artifact when may_edit true: fix | report (empty = legacy fix)"
  required: false
```

In detect `main`, resolve defaults when empty:

```bash
resolved_may_edit="${LOOP_MAY_EDIT:-}"
if [[ -z ${resolved_may_edit} ]]; then
  echo "::warning::may_edit omitted; deriving from level (deprecated)" >&2
  case "${LEVEL}" in L1) resolved_may_edit="false" ;; *) resolved_may_edit="true" ;; esac
fi
resolved_write_target="${LOOP_WRITE_TARGET:-}"
if [[ ${resolved_may_edit} == "true" && -z ${resolved_write_target} ]]; then
  resolved_write_target="fix"
fi
resolved_delivery="${LOOP_DELIVERY:-open_pr}"
validate_loop_write_contract "${resolved_may_edit}" "${resolved_write_target}" "${resolved_delivery}" "${LEVEL}"
```

- [ ] **Step 4: Update `loop-detect-matrix.bats`**

Add test for report mode prompt:

```bash
@test "build_prompt_text emits write_target report when configured" {
    run build_prompt_text "tech-debt" "L2" "docs/report/**" "" "abc" "def" \
        '{"report_file":"docs/report/tech-debt/2026-07-23.md"}' "" "0" \
        "true" "report" "docs/report/tech-debt/2026-07-23.md"
    [ "$status" -eq 0 ]
    [[ $output == *"write_target: report"* ]]
    [[ $output == *"report_file: docs/report/tech-debt/2026-07-23.md"* ]]
}
```

Update `build_prompt_text` function signature in test setup file if tests source a wrapper — match all existing call sites (append `"true" "fix" ""` for fix loops).

- [ ] **Step 5: Run Bats**

Run: `bats test/bats/github-actions/loop-detect-matrix.bats test/bats/github-actions/loop-write-contract.bats -v`

- [ ] **Step 6: Do not commit**

---

### Task 4: `ci-loop-caller` inputs and wiring

**Files:**

- Modify: `.github/workflows/ci-loop-caller.yaml`
- Modify: `.github/workflows/ci-loop-caller-pr-scan.yaml`
- Modify: `.github/workflows/ci-loop-caller-full-github.yaml`
- Modify: `.github/actions/loop-prompt-generate/action.yml`

**Interfaces:**

- New caller inputs (alphabetical, after `denylist`):

```yaml
delivery:
  default: open_pr
  description: "Platform delivery after APPROVE: log | issue | notion | open_pr | none"
  required: false
  type: string
may_edit:
  default: ""
  description: "Agent worktree edit gate: true | false"
  required: false
  type: string
write_target:
  default: ""
  description: "Agent artifact when may_edit true: fix | report"
  required: false
  type: string
```

- Pass to `loop-detect` `with:` as `delivery`, `may_edit`, `write_target`.

- [ ] **Step 1: Add inputs to all three caller workflows**

Insert keys in alphabetical order in `workflow_call.inputs`.

- [ ] **Step 2: Wire detect step `with:` block**

```yaml
delivery: ${{ inputs.delivery }}
may_edit: ${{ inputs.may_edit }}
write_target: ${{ inputs.write_target }}
```

- [ ] **Step 3: Update `loop-prompt-generate/action.yml`**

Add inputs `may_edit`, `report_file`, `write_target`; call `emit_loop_constraints "${MAY_EDIT}" "${WRITE_TARGET}" "${ALLOWLIST}" "${REPORT_FILE}"`.

- [ ] **Step 4: Shellcheck**

Run: `shellcheck .github/actions/loop-prompt-generate/lib/*.sh .github/actions/loop-detect/lib/matrix.sh`

- [ ] **Step 5: Do not commit**

---

### Task 5: Migrate dogfood `on-loop-*.yaml` callers

**Files:**

- Modify: `.github/workflows/on-loop-changelog.yaml`
- Modify: `.github/workflows/on-loop-ci-sweeper.yaml`
- Modify: `.github/workflows/on-loop-docs-triage.yaml`
- Modify: `.github/workflows/on-loop-refactor.yaml`
- Modify: `.github/workflows/on-loop-tech-debt.yaml`

**Interfaces:**

| Caller      | `delivery` | `may_edit` | `write_target` |
| ----------- | ---------- | ---------- | -------------- |
| changelog   | `open_pr`  | `true`     | `fix`          |
| ci-sweeper  | `open_pr`  | `true`     | `fix`          |
| docs-triage | `open_pr`  | `true`     | `fix`          |
| refactor    | `open_pr`  | `true`     | `fix`          |
| tech-debt   | `open_pr`  | `true`     | `report`       |

- [ ] **Step 1: Add three keys to each caller `with:` (alphabetical)**

Example for tech-debt:

```yaml
delivery: open_pr
may_edit: true
write_target: report
```

- [ ] **Step 2: Validate workflow syntax**

Run: `actionlint .github/workflows/on-loop-*.yaml` (if available) or `yamllint` per repo CI.

- [ ] **Step 3: Do not commit**

---

### Task 6: Platform documentation

**Files:**

- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`
- Modify: `docs/explanation/loop-engineering/common-loop-triage-format.md`
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md` — Graduated Autonomy table: L2 = "worktree + PR", not "file fix"
- Modify: `docs/explanation/loop-engineering/workflows/loop-tech-debt-workflow-design.md` — align Out of scope with `write_target: report` + optional closed-set allowlist

- [ ] **Step 1: Add Platform inputs table rows** for `delivery`, `may_edit`, `write_target` in caller inputs reference.

- [ ] **Step 2: Add four-plane section** to `common-loop-triage-format.md` linking to spec.

- [ ] **Step 3: Fix L2 wording** in loop-engineering-design and tech-debt workflow doc.

- [ ] **Step 4: Run markdown validation** per markdown-validation skill if docs are substantial.

- [ ] **Step 5: Do not commit**

---

### Task 7: Skill contract updates (APM source)

**Files:**

- Modify: `.apm/packages/common/.apm/skills/changelog/references/category-automation-envelope.md`
- Modify: `.apm/packages/common/.apm/skills/ci-sweeper/references/category-automation-envelope.md`
- Modify: `.apm/packages/common/.apm/skills/docs-updater/references/category-automation-envelope.md`
- Modify: `.apm/packages/common/.apm/skills/refactor/references/category-automation-envelope.md`
- Modify: `.apm/packages/common/.apm/skills/tech-debt/references/category-automation-envelope.md`
- Modify: corresponding `SKILL.md` Workflow tables (branch on `write_target` when `may_edit: true`)

**Interfaces:**

- Constraints table adds:

```markdown
| `write_target` | string | `fix` or `report` when `may_edit: true` |
| `report_file` | string | Required when `write_target: report` |
```

- Remove: "loop-prompt-generate maps level to may_edit" — replace with explicit caller-supplied fields.
- Add: "Do not branch on `level` or `delivery`."

- [ ] **Step 1: Update tech-debt envelope first** (template for report mode).

- [ ] **Step 2: Update fix-mode skills** (changelog, ci-sweeper, docs-updater, refactor) — `write_target: fix` default in examples.

- [ ] **Step 3: Update SKILL.md workflow steps** — when `may_edit: true` and `write_target: report`, write `report_file`; when `fix`, existing apply path.

- [ ] **Step 4: Sync install artifacts**

Run: `apm install --update && apm audit --ci`

- [ ] **Step 5: Do not commit**

---

### Task 8: Verifier criteria alignment

**Files:**

- Modify: `.github/actions/loop-execute/lib/agent_output_format_criteria.md`

- [ ] **Step 1: Add subsection** for `write_target: report` — require `### Changes` row for `report_file` when diff non-empty.

- [ ] **Step 2: Do not commit**

---

### Task 9: End-to-end verification

- [ ] **Step 1: Run all loop-related Bats**

Run: `bats test/bats/github-actions/loop-prompt-generate.bats test/bats/github-actions/loop-write-contract.bats test/bats/github-actions/loop-detect-matrix.bats -v`

Expected: all PASS.

- [ ] **Step 2: Mirror drift check**

Run: `bash scripts/self/apm/sync_apm_artifacts.sh --check`

Expected: no drift after Task 7 sync (or document expected drift if sync script not run).

- [ ] **Step 3: Do not commit**

---

## Spec coverage self-review

| Spec section                  | Task                                                                   |
| ----------------------------- | ---------------------------------------------------------------------- |
| Four planes                   | Task 6 docs, Task 2–4 code                                             |
| may_edit decoupled from level | Task 2–3 (legacy fallback + warning)                                   |
| write_target fix/report       | Task 2–5                                                               |
| report_file in target_json    | Task 3                                                                 |
| delivery platform-only        | Task 1, 4 (no skill changes)                                           |
| Valid combinations matrix     | Task 1                                                                 |
| Dogfood caller migration      | Task 5                                                                 |
| Skill envelope updates        | Task 7                                                                 |
| Phase 4 delivery adapters     | Deferred (validation accepts `issue`/`notion` for may_edit false only) |

## Deferred (Phase 4 — separate plan)

- `loop-finalize` adapter for `delivery: issue`
- Notion / Backlog connectors
- Composite delivery (`open_pr` + `issue`)
