# Loop PR Body Hybrid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compose human-readable loop PR bodies in `loop-finalize` from detect failures, domain changed files, and optional agent `## Summary`, without changing `pr_title`.

**Architecture:** Add pure `render_pr_body.sh` under `loop-finalize/lib/`. Extend `notify_context.json` with an `agent_report_summary` field extracted from implementer `## Summary` at execute time (STATUS_DIR is not available in the finalize job). Pass `detect_result_json` + `notify_context_json` into finalize; Create PR calls the renderer before `gh pr create`. Move Level/Target/Skip footer out of caller `pr_body` YAML into the renderer so section order matches the spec.

**Tech Stack:** bash, jq, bats, GitHub Actions composite/`workflow_call`

**Spec:** [Loop PR Body Hybrid Design](../specs/2026-07-17-loop-pr-body-hybrid-design.md)

## Global Constraints

- `pr_title` stays caller-static; do not make it dynamic.
- Do not add a top-level `scripts/render_pr_body.sh`; keep logic under `.github/actions/loop-finalize/lib/`.
- Failure context lists all `failures[]` (cap 5 + `… and N more`); never hide multiples behind only `Other failures: N`.
- Optional sections omit quietly; never fail finalize solely because Summary/failures/files are missing.
- Redact patterns must stay aligned with `loop-execute/lib/notify_context.sh`.
- Remote action pins (`@7a512711…`) do not pick up local action edits until bumped; bats verify logic in this PR. Live dogfood requires pin bump (or temporary `uses: ./…`) as a follow-up step noted in Task 4 — do not rewrite all loop action pins unless asked.

---

## File map

| File                                                                           | Responsibility                                                                                          |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `.github/actions/loop-finalize/lib/render_pr_body.sh`                          | Pure compose: prefix + Failure context + Changes + agent Summary + footer → stdout                      |
| `.github/actions/loop-finalize/action.yml`                                     | New inputs; Create PR step invokes renderer                                                             |
| `.github/actions/loop-execute/lib/notify_context.sh`                           | Add `agent_report_summary` from `## Summary` … next H2                                                  |
| `.github/workflows/ci-loop-agent.yaml`                                         | Pass `detect_result_json` + `notify_context_json` into finalize                                         |
| `.github/workflows/ci-loop-caller.yaml`                                        | Stop appending Level/Target/Skip into `pr_body`; pass discrete footer fields if needed via agent inputs |
| `.github/workflows/ci-loop-caller-full-github.yaml`                            | Same as caller                                                                                          |
| `test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats`              | Unit tests for renderer                                                                                 |
| `test/bats/.github/actions/loop-execute/lib/notify_context.bats`               | Extend or add tests for `agent_report_summary`                                                          |
| Loop design / inputs docs under `docs/explanation/loop-engineering/workflows/` | Document hybrid body                                                                                    |

---

### Task 1: `render_pr_body` pure library + bats (TDD)

**Files:**

- Create: `.github/actions/loop-finalize/lib/render_pr_body.sh`
- Create: `test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats`
- Test: same bats file

**Interfaces:**

- Consumes: env vars listed below
- Produces: functions callable from bats / Create PR step; `main` prints full markdown to stdout when script is executed

**Env contract (renderer):**

| Env                    | Meaning                                                      |
| ---------------------- | ------------------------------------------------------------ |
| `PR_BODY_PREFIX`       | Caller static prefix (may be empty)                          |
| `DETECT_RESULT_JSON`   | Detect JSON; use `.failures` array                           |
| `CHANGED_FILES_JSON`   | JSON string array of paths (from notify `changed_files`)     |
| `AGENT_REPORT_SUMMARY` | Pre-extracted agent Summary body text (no heading), or empty |
| `LEVEL`                | Footer level (e.g. `L2`)                                     |
| `TARGET_KEY`           | Footer target key (e.g. `integration:main`)                  |
| `SKIP_REASON`          | Footer skip reason                                           |
| `SUMMARY_MAX_CHARS`    | Default `4000`                                               |
| `FAILURES_MAX`         | Default `5`                                                  |

**Required functions (exact names):**

- `redact_sensitive_text "$text"` → stdout
- `truncate_text "$text" "$max"` → stdout
- `render_failure_context "$detect_json"` → stdout (empty if no failures)
- `render_changes_section "$changed_files_json"` → stdout (empty if `[]`/empty)
- `render_agent_summary_section "$summary_text"` → stdout (empty if blank; emits `## Summary\n` + text)
- `render_footer "$level" "$target_key" "$skip_reason"` → stdout
- `render_pr_body` → full body on stdout (reads env above)
- `main` → calls `render_pr_body`

- [ ] **Step 1: Write failing bats (core cases)**

Create `test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats`:

```bash
#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck source=/dev/null
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/render_pr_body.sh"
}

@test "render_failure_context empty when no failures" {
    run render_failure_context '{"failures":[]}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "render_failure_context lists one failure" {
    local json='{"failures":[{"workflow_name":"on-ci-push-markdown","run_url":"https://example/runs/1","job_name":"lint","failure_type":"regression","reason":"MD001"}]}'
    run render_failure_context "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Failure context"* ]]
    [[ "$output" == *"on-ci-push-markdown"* ]]
    [[ "$output" == *"https://example/runs/1"* ]]
    [[ "$output" == *"MD001"* ]]
}

@test "render_failure_context lists three failures fully" {
    local json
    json="$(jq -nc '{failures:[
      {workflow_name:"wf-a",run_url:"u1",job_name:"j1",failure_type:"regression",reason:"r1"},
      {workflow_name:"wf-b",run_url:"u2",job_name:"j2",failure_type:"regression",reason:"r2"},
      {workflow_name:"wf-c",run_url:"u3",job_name:"j3",failure_type:"flake",reason:"r3"}
    ]}')"
    run render_failure_context "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"wf-a"* && "$output" == *"wf-b"* && "$output" == *"wf-c"* ]]
    [[ "$output" != *"and "*" more"* ]]
}

@test "render_failure_context caps at five with overflow" {
    local json
    json="$(jq -nc '{failures:[range(1;8)|{workflow_name:("wf-\(.)"),run_url:("u\(.)"),job_name:("j\(.)"),failure_type:"regression",reason:("r\(.)")}]}')"
    FAILURES_MAX=5 run render_failure_context "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"wf-1"* && "$output" == *"wf-5"* ]]
    [[ "$output" != *"wf-6"* ]]
    [[ "$output" == *"… and 2 more"* ]]
}

@test "render_changes_section omitted when empty" {
    run render_changes_section '[]'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "render_changes_section lists files" {
    run render_changes_section '["docs/a.md","scripts/b.sh"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Changes"* ]]
    [[ "$output" == *"`docs/a.md`"* ]]
}

@test "render_agent_summary_section omitted when empty" {
    run render_agent_summary_section ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "render_agent_summary_section wraps heading" {
    run render_agent_summary_section $'- **Outcome:** fixed\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Summary"* ]]
    [[ "$output" == *"Outcome"* ]]
}

@test "redact_sensitive_text redacts github tokens" {
    run redact_sensitive_text 'token ghp_abcdefghijklmnopqrstuvwxyz0123456789' # pragma: allowlist secret
    [ "$status" -eq 0 ]
    [[ "$output" == *"[REDACTED]"* ]]
    [[ "$output" != *"ghp_abcdefghijklmnopqrstuvwxyz0123456789"* ]] # pragma: allowlist secret
}

@test "render_pr_body orders prefix failure changes summary footer" {
    export PR_BODY_PREFIX=$'## Summary\nPrefix only.\n'
    export DETECT_RESULT_JSON='{"failures":[{"workflow_name":"wf","run_url":"https://example/r","job_name":"job","failure_type":"regression","reason":"boom"}]}'
    export CHANGED_FILES_JSON='["docs/x.md"]'
    export AGENT_REPORT_SUMMARY=$'- **Fix applied:** tweak\n'
    export LEVEL=L2
    export TARGET_KEY=integration:main
    export SKIP_REASON=none
    run render_pr_body
    [ "$status" -eq 0 ]
    local prefix_i fail_i changes_i sum_i foot_i
    prefix_i="$(printf '%s\n' "$output" | grep -n 'Prefix only' | head -1 | cut -d: -f1)"
    fail_i="$(printf '%s\n' "$output" | grep -n '## Failure context' | head -1 | cut -d: -f1)"
    changes_i="$(printf '%s\n' "$output" | grep -n '## Changes' | head -1 | cut -d: -f1)"
    sum_i="$(printf '%s\n' "$output" | grep -n 'Fix applied' | head -1 | cut -d: -f1)"
    foot_i="$(printf '%s\n' "$output" | grep -n 'Level: L2' | head -1 | cut -d: -f1)"
    [ "$prefix_i" -lt "$fail_i" ]
    [ "$fail_i" -lt "$changes_i" ]
    [ "$changes_i" -lt "$sum_i" ]
    [ "$sum_i" -lt "$foot_i" ]
}
```

- [ ] **Step 2: Run bats — expect FAIL (missing script)**

Run:

```bash
bats test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats
```

Expected: FAIL (cannot source `render_pr_body.sh` / functions missing)

- [ ] **Step 3: Implement `render_pr_body.sh`**

Create `.github/actions/loop-finalize/lib/render_pr_body.sh` with header comment matching other action libs (`set -euo pipefail`, `umask 027`, `LC_ALL=C.UTF-8`).

Implementation sketch (must match env contract and bats):

```bash
#!/bin/bash
set -euo pipefail
umask 027
export LC_ALL=C.UTF-8

FAILURES_MAX="${FAILURES_MAX:-5}"
SUMMARY_MAX_CHARS="${SUMMARY_MAX_CHARS:-4000}"

function redact_sensitive_text {
    local text="$1"
    text=$(sed -E 's/gh[pousr]_[A-Za-z0-9_]{20,}/[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/(password|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]\"]+/\1=[REDACTED]/gi' <<< "${text}")
    text=$(sed -E 's/x-access-token:[A-Za-z0-9._-]+/x-access-token:[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/Bearer[[:space:]]+[A-Za-z0-9._-]+/Bearer [REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/Authorization:[[:space:]]*[^[:space:]\"]+/Authorization: [REDACTED]/gi' <<< "${text}")
    text=$(sed -E 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED-JWT]/g' <<< "${text}")
    text=$(sed -E 's/-----BEGIN [A-Z ]+-----[^-]*-----END [A-Z ]+-----/[REDACTED-PEM]/g' <<< "${text}")
    printf '%s' "${text}"
}

function truncate_text {
    local text="$1" max="$2"
    if [[ ${#text} -le ${max} ]]; then
        printf '%s' "${text}"
    else
        printf '%s' "${text:0:max}"
    fi
}

function render_failure_context {
    local detect_json="${1:-}"
    local count i max shown
    if [[ -z ${detect_json} ]] || ! jq -e '(.failures | type) == "array" and (.failures | length) > 0' <<< "${detect_json}" >/dev/null 2>&1; then
        return 0
    fi
    count="$(jq -r '.failures | length' <<< "${detect_json}")"
    max="${FAILURES_MAX}"
    printf '%s\n' "## Failure context"
    shown=0
    i=0
    while [[ ${i} -lt ${count} ]]; do
        if [[ ${shown} -ge ${max} ]]; then
            printf '%s\n' "… and $((count - shown)) more"
            break
        fi
        local wf url job typ reason
        wf="$(jq -r --argjson i "${i}" '.failures[$i].workflow_name // empty' <<< "${detect_json}")"
        url="$(jq -r --argjson i "${i}" '.failures[$i].run_url // empty' <<< "${detect_json}")"
        job="$(jq -r --argjson i "${i}" '.failures[$i].job_name // empty' <<< "${detect_json}")"
        typ="$(jq -r --argjson i "${i}" '.failures[$i].failure_type // empty' <<< "${detect_json}")"
        reason="$(jq -r --argjson i "${i}" '.failures[$i].reason // empty' <<< "${detect_json}")"
        reason="$(truncate_text "$(redact_sensitive_text "${reason}")" 500)"
        [[ -n ${wf} ]] && printf '%s\n' "- Workflow: \`${wf}\`"
        [[ -n ${url} ]] && printf '%s\n' "- Run: ${url}"
        [[ -n ${job} ]] && printf '%s\n' "- Job: \`${job}\`"
        [[ -n ${typ} ]] && printf '%s\n' "- Type: \`${typ}\`"
        [[ -n ${reason} ]] && printf '%s\n' "- Reason: ${reason}"
        printf '\n'
        shown=$((shown + 1))
        i=$((i + 1))
    done
}

function render_changes_section {
    local files_json="${1:-[]}"
    local n
    if ! jq -e 'type == "array" and length > 0' <<< "${files_json}" >/dev/null 2>&1; then
        return 0
    fi
    n="$(jq -r 'length' <<< "${files_json}")"
    printf '%s\n' "## Changes"
    jq -r '.[]' <<< "${files_json}" | head -n 20 | while IFS= read -r f; do
        [[ -z ${f} ]] && continue
        printf '%s\n' "- \`${f}\`"
    done
    if [[ ${n} -gt 20 ]]; then
        printf '%s\n' "- … (+$((n - 20)) more)"
    fi
    printf '\n'
}

function render_agent_summary_section {
    local text="${1:-}"
    text="$(truncate_text "$(redact_sensitive_text "${text}")" "${SUMMARY_MAX_CHARS}")"
    [[ -z ${text} ]] && return 0
    printf '%s\n' "## Summary"
    printf '%s\n' "${text}"
    printf '\n'
}

function render_footer {
    local level="${1:-}" target_key="${2:-}" skip_reason="${3:-}"
    [[ -z ${level}${target_key}${skip_reason} ]] && return 0
    [[ -n ${level} ]] && printf '%s\n' "- Level: ${level}"
    [[ -n ${target_key} ]] && printf '%s\n' "- Target: \`${target_key}\`"
    [[ -n ${skip_reason} ]] && printf '%s\n' "- Skip reason: ${skip_reason}"
}

function render_pr_body {
    local parts=() section
    if [[ -n ${PR_BODY_PREFIX:-} ]]; then
        printf '%s\n\n' "${PR_BODY_PREFIX%"${PR_BODY_PREFIX##*[![:space:]]}"}"
    fi
    section="$(render_failure_context "${DETECT_RESULT_JSON:-}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"
    section="$(render_changes_section "${CHANGED_FILES_JSON:-[]}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"
    section="$(render_agent_summary_section "${AGENT_REPORT_SUMMARY:-}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"
    render_footer "${LEVEL:-}" "${TARGET_KEY:-}" "${SKIP_REASON:-}"
}

function main {
    render_pr_body
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
```

Adjust whitespace so bats order assertions pass; keep Failure blocks separated clearly when multiple failures.

- [ ] **Step 4: Run bats — expect PASS**

```bash
bats test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats
```

Expected: all tests PASS

- [ ] **Step 5: Commit** (only if user requested commits)

```bash
git add .github/actions/loop-finalize/lib/render_pr_body.sh \
  test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats
git commit -m "$(cat <<'EOF'
feat(loop): add render_pr_body helper for hybrid PR summaries

EOF
)"
```

---

### Task 2: Extract agent `## Summary` into `notify_context_json`

**Files:**

- Modify: `.github/actions/loop-execute/lib/notify_context.sh`
- Create or modify: `test/bats/.github/actions/loop-execute/lib/notify_context.bats`

**Interfaces:**

- Consumes: existing `STATUS_DIR` / `agent-output.txt`
- Produces: `notify_context_json.agent_report_summary` (string; may be empty). Keep existing `agent_summary` (HTML comment) unchanged for notify-pr compatibility.

- [ ] **Step 1: Write failing test for `extract_agent_report_summary`**

Add to bats (create file if missing), sourcing `notify_context.sh`:

```bash
@test "extract_agent_report_summary takes ## Summary until next H2" {
    local f
    f="${BATS_TEST_TMPDIR}/agent-output.txt"
    cat >"$f" <<'EOF'
noise
## Summary
- **Root cause:** MD001
- **Outcome:** fixed

## Ignored
- none
EOF
    run extract_agent_report_summary "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Root cause"* ]]
    [[ "$output" != *"## Ignored"* ]]
    [[ "$output" != *"## Summary"* ]]
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
bats test/bats/.github/actions/loop-execute/lib/notify_context.bats
```

Expected: FAIL on missing `extract_agent_report_summary`

- [ ] **Step 3: Implement extraction + JSON field**

In `notify_context.sh` add:

```bash
function extract_agent_report_summary {
    local output_file="$1"
    [[ -f ${output_file} ]] || return 0
    awk '
      /^## Summary[[:space:]]*$/ {grab=1; next}
      /^## / {if (grab) exit}
      grab {print}
    ' "${output_file}" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}
```

In `main`, after resolving `last_output`:

```bash
agent_report_summary=""
if [[ -n ${last_output} ]]; then
    agent_report_summary="$(extract_agent_report_summary "${last_output}")"
    agent_report_summary="$(truncate_text "$(redact_sensitive_text "${agent_report_summary}")" 4000)"
fi
```

Extend the `jq -nc` object with `--arg agent_report_summary "${agent_report_summary}"` and field `agent_report_summary: $agent_report_summary`.

- [ ] **Step 4: Run bats — expect PASS**

```bash
bats test/bats/.github/actions/loop-execute/lib/notify_context.bats
```

- [ ] **Step 5: Commit** (only if user requested)

```bash
git add .github/actions/loop-execute/lib/notify_context.sh \
  test/bats/.github/actions/loop-execute/lib/notify_context.bats
git commit -m "$(cat <<'EOF'
feat(loop): expose agent ## Summary in notify_context_json

EOF
)"
```

---

### Task 3: Wire finalize Create PR + caller footer move

**Files:**

- Modify: `.github/actions/loop-finalize/action.yml` (inputs + Create PR step)
- Modify: `.github/workflows/ci-loop-agent.yaml` (finalize `with:`)
- Modify: `.github/workflows/ci-loop-caller.yaml` (pr_body footer removal; pass level already via detect outputs into agent — add finalize-facing fields on agent if missing)
- Modify: `.github/workflows/ci-loop-caller-full-github.yaml` (same)

**Interfaces:**

- Consumes: Task 1 `render_pr_body.sh`; Task 2 `notify_context_json.agent_report_summary` + `changed_files`
- Produces: `gh pr create --body` uses composed markdown

- [ ] **Step 1: Add finalize inputs**

In `loop-finalize/action.yml` inputs (keep alphabetical order):

```yaml
detect_result_json:
  default: "{}"
  description: "Detect script JSON (failures[]) for PR Failure context"
  required: false
level:
  default: ""
  description: "Loop level for PR footer (e.g. L2)"
  required: false
notify_context_json:
  default: "{}"
  description: "notify_context_json from loop-execute (changed_files, agent_report_summary)"
  required: false
```

(`skip_reason` and `target_json` already exist — derive `TARGET_KEY` from `target_json.key`.)

- [ ] **Step 2: Replace Create PR body assembly**

Replace the Create PR `run:` block so it builds body via the lib (keep title/labels/`gh pr create` behavior). Critical fragment:

```bash
NOTIFY_JSON="${NOTIFY_CONTEXT_JSON:-{}}"
if ! jq -e . >/dev/null 2>&1 <<< "${NOTIFY_JSON}"; then
  NOTIFY_JSON='{}'
fi
CHANGED_FILES_JSON="$(jq -c '.changed_files // []' <<< "${NOTIFY_JSON}")"
AGENT_REPORT_SUMMARY="$(jq -r '.agent_report_summary // empty' <<< "${NOTIFY_JSON}")"
TARGET_KEY="$(jq -r '.key // empty' <<< "${TARGET_JSON:-{}}" 2>/dev/null || true)"

export PR_BODY_PREFIX="${PR_BODY}"
export DETECT_RESULT_JSON
export CHANGED_FILES_JSON
export AGENT_REPORT_SUMMARY
export LEVEL
export TARGET_KEY
export SKIP_REASON

COMPOSED="$(bash "${GITHUB_ACTION_PATH}/lib/render_pr_body.sh")"
ARGS=( --repo "${GITHUB_REPOSITORY}" --base "${PR_BASE_BRANCH}" --head "${BRANCH}" --title "${PR_TITLE}" )
if [[ -n "${COMPOSED}" ]]; then
  ARGS+=(--body "${COMPOSED}")
fi
# labels unchanged
URL=$(gh pr create "${ARGS[@]}")
```

Pass env into the step:

```yaml
DETECT_RESULT_JSON: ${{ inputs.detect_result_json }}
LEVEL: ${{ inputs.level }}
NOTIFY_CONTEXT_JSON: ${{ inputs.notify_context_json }}
PR_BODY: ${{ inputs.pr_body }}
SKIP_REASON: ${{ inputs.skip_reason }}
TARGET_JSON: ${{ inputs.target_json }}
```

- [ ] **Step 3: Wire `ci-loop-agent.yaml` finalize**

Add to finalize action `with:` (alphabetical with existing keys):

```yaml
detect_result_json: ${{ inputs.detect_result_json }}
level: ${{ inputs.level }}
notify_context_json: ${{ needs.agent-l2.outputs.notify_context_json || '{}' }}
```

Ensure `agent-l2` job already exports `notify_context_json` (it does today).

- [ ] **Step 4: Remove footer from caller `pr_body` blocks**

In both `ci-loop-caller.yaml` and `ci-loop-caller-full-github.yaml`, change execute `pr_body` from:

```yaml
pr_body: |
  ${{ needs.detect.outputs.pr_body }}

  - Level: ${{ needs.detect.outputs.level }}
  - Target: `${{ matrix.target.target_json.key }}`
  - Skip reason: ${{ needs.detect.outputs.skip_reason }}
```

to:

```yaml
pr_body: ${{ needs.detect.outputs.pr_body }}
```

Footer is now owned by `render_pr_body` via `level` / `target_json` / `skip_reason` already passed into `ci-loop-agent`.

Confirm `ci-loop-agent` already receives `level` and `skip_reason` as inputs; if `level` is not passed to finalize today, Step 3 covers it.

- [ ] **Step 5: Sanity-check alphabetical `with:` / `inputs:` keys**

Run:

```bash
# spot-check; full workflow lint if available
actionlint .github/workflows/ci-loop-agent.yaml \
  .github/workflows/ci-loop-caller.yaml \
  .github/workflows/ci-loop-caller-full-github.yaml
```

Expected: no new errors from these edits

- [ ] **Step 6: Re-run unit bats**

```bash
bats test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats \
  test/bats/.github/actions/loop-execute/lib/notify_context.bats
```

Expected: PASS

- [ ] **Step 7: Commit** (only if user requested)

```bash
git add .github/actions/loop-finalize/action.yml \
  .github/workflows/ci-loop-agent.yaml \
  .github/workflows/ci-loop-caller.yaml \
  .github/workflows/ci-loop-caller-full-github.yaml
git commit -m "$(cat <<'EOF'
feat(loop): compose hybrid PR body in loop-finalize

EOF
)"
```

---

### Task 4: Documentation + dogfood pin note

**Files:**

- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`
- Modify: `docs/explanation/loop-engineering/workflows/loop-ci-sweeper-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/workflows/loop-changelog-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/workflows/loop-docs-triage-workflow-design.md`
- Optional one-liner in: `docs/reference/loop-notify-pr-specification.md` (PR body vs notify ownership)

- [ ] **Step 1: Update inputs reference**

Change `pr_body` description from “Static markdown prefix for finalize PR body” to:

> Static markdown prefix. `loop-finalize` composes the final PR body: prefix + Failure context (from `detect_result.failures[]` when present) + Changes + optional agent `## Summary` + Level/Target/Skip footer.

- [ ] **Step 2: Per-loop design one-liners**

Add under PR / finalize notes for each loop design doc:

> PR body is hybrid-composed by `loop-finalize` (see Loop PR Body Hybrid Design). Caller `pr_body` remains a static prefix only.

- [ ] **Step 3: Notify ownership note**

In notify spec, add one sentence: notify uses `notify_context_json` for comments; PR description composition is owned by `loop-finalize` / `render_pr_body.sh`.

- [ ] **Step 4: Document pin follow-up**

In the hybrid design spec “Risks” or this plan handoff comment: live dogfood needs `ci-loop-agent.yaml` / caller action pin bump to a SHA that includes Tasks 1–3 (or temporary `uses: ./.github/actions/loop-finalize` + `loop-execute` for a validation PR).

- [ ] **Step 5: Commit** (only if user requested)

```bash
git add docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md \
  docs/explanation/loop-engineering/workflows/loop-ci-sweeper-workflow-design.md \
  docs/explanation/loop-engineering/workflows/loop-changelog-workflow-design.md \
  docs/explanation/loop-engineering/workflows/loop-docs-triage-workflow-design.md \
  docs/reference/loop-notify-pr-specification.md
git commit -m "$(cat <<'EOF'
docs(loop): document hybrid PR body composition

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement                               | Task                                      |
| ---------------------------------------------- | ----------------------------------------- |
| Hybrid body (mechanical + optional Summary)    | 1, 3                                      |
| All loops / failures optional                  | 1 (omit when empty), 3                    |
| Whole `## Summary` block                       | 2 extraction, 1 render                    |
| List all failures, cap 5                       | 1                                         |
| Static `pr_title`                              | Global constraint / no task changes title |
| `loop-finalize/lib` + bats                     | 1                                         |
| Wire detect + files + agent text into finalize | 2, 3                                      |
| Footer order after Summary                     | 1, 3 (caller footer removal)              |
| Docs                                           | 4                                         |
| No top-level scripts/                          | Global constraint                         |

## Self-review notes

- No TBD placeholders left in task steps.
- `agent_report_summary` name is consistent across Task 2 and Task 3.
- Pin bump called out so implementers do not assume unpinned local action edits run in dogfood immediately.
