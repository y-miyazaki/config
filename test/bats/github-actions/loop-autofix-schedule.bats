#!/usr/bin/env bats

# Tests for .github/workflows/on-loop-github-issue-autofix.yaml
#
# Use cases:
# - on keeps issues(labeled), repository_dispatch, workflow_dispatch and adds one schedule entry
# - workflow-level permissions are empty; loop and loop-scheduled each hold the five write permissions
# - concurrency group is loop-state-main on schedule and keeps queue max
# - loop if excludes schedule and admits issues only for the autofix label
# - loop-scheduled is the L1 delivery none items-mode observer with the scan detect env
# - loop-scheduled passes no L2-only write inputs and its maker is read-only
# - loop job configuration stays L2 pr_create

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    WF="${ROOT}/.github/workflows/on-loop-github-issue-autofix.yaml"
}

# job_block JOB: print the job's lines
job_block() {
    awk -v job="$1" '
        $0 == "  " job ":" {f=1; print; next}
        f && /^  [a-zA-Z0-9_-]+:/ {exit}
        f && /^[a-z]/ {exit}
        f
    ' "${WF}"
}

# job_perms JOB: print the job-level permissions entries
job_perms() {
    job_block "$1" | awk '/^    permissions:/ {f=1; next} f && /^    [a-z]/ {exit} f' | sed 's/^ *//'
}

# job_if JOB: print the job-level if: expression, one line
job_if() {
    job_block "$1" | grep '^    if:' | sed 's/^    if: *//'
}

# with_line JOB KEY: print the value of a single-line with: key
with_line() {
    job_block "$1" | grep -E "^      $2:" | sed -E "s/^      $2: *//"
}

EXPECTED_PERMS="$(printf '%s\n' \
    'actions: write' \
    'contents: write' \
    'copilot-requests: write # zizmor: ignore[excessive-permissions]' \
    'issues: write' \
    'pull-requests: write')"

@test "on keeps issues labeled, repository_dispatch, workflow_dispatch and has one schedule entry" {
    local on
    on="$(awk '/^on:/ {f=1; next} f && /^[a-z]/ {exit} f' "${WF}")"
    grep -q '^  issues:' <<<"${on}"
    grep -q 'types: \[labeled\]' <<<"${on}"
    grep -q '^  repository_dispatch:' <<<"${on}"
    grep -q '^  workflow_dispatch:' <<<"${on}"
    grep -q '^  schedule:' <<<"${on}"
    [ "$(grep -c 'cron:' <<<"${on}")" -eq 1 ]
}

@test "workflow-level permissions are empty and both jobs hold the same five write permissions" {
    grep -qx 'permissions: {}' "${WF}"
    [ "$(job_perms loop)" = "${EXPECTED_PERMS}" ]
    [ "$(job_perms loop-scheduled)" = "${EXPECTED_PERMS}" ]
}

@test "concurrency group is loop-state-main on schedule and keeps queue max" {
    local group
    group="$(grep '^  group:' "${WF}")"
    grep -q "github.event_name == 'schedule' && 'loop-state-main'" <<<"${group}"
    grep -q 'github.event.issue.number' <<<"${group}"
    grep -qx '  cancel-in-progress: false' "${WF}"
    grep -qx '  queue: max' "${WF}"
}

@test "loop if excludes schedule and admits issues only for the autofix label" {
    [ "$(job_if loop)" = "github.event_name != 'schedule' && (github.event_name != 'issues' || github.event.label.name == 'autofix')" ]
}

@test "loop-scheduled runs only on schedule and calls the caller at L1 with items mode" {
    [ "$(job_if loop-scheduled)" = "github.event_name == 'schedule'" ]
    job_block loop-scheduled | grep -qx '    uses: ./.github/workflows/ci-loop-caller.yaml'
    [ "$(with_line loop-scheduled level)" = "L1" ]
    [ "$(with_line loop-scheduled delivery)" = "none" ]
    [ "$(with_line loop-scheduled detect_items)" = "true" ]
    [ "$(with_line loop-scheduled detect_branch_match)" = "main" ]
    [ "$(with_line loop-scheduled detect_max_targets)" = "3" ]
    [ "$(with_line loop-scheduled detect_script)" = ".agents/skills/github-issue-autofix/scripts/detect_autofix.sh" ]
    [ "$(with_line loop-scheduled loop_name)" = "github-issue-autofix" ]
}

@test "loop-scheduled passes no L2-only write inputs" {
    local block key
    block="$(job_block loop-scheduled)"
    [ -n "${block}" ]
    for key in agent_edit_target agent_edit_allowlist agent_edit_denylist agent_unchanged_verdict finalize_script pr_draft pr_title pr_body pr_labels; do
        run grep -qE "^      ${key}:" <<<"${block}"
        [ "$status" -ne 0 ]
    done
}

@test "loop-scheduled detect_env_json is valid JSON with the scan variables" {
    local raw json
    raw="$(with_line loop-scheduled detect_env_json)"
    [ -n "${raw}" ]
    case "${raw}" in
    "'"*"'") json="${raw:1:${#raw}-2}" ;;
    *) json="${raw}" ;;
    esac
    run jq -e '
        .AUTOFIX_SCAN == "true" and
        .AUTOFIX_SOURCE_LABEL == "loop:code-review" and
        .AUTOFIX_SOURCE_MARKER == "<!-- code-review:fp:" and
        .AUTOFIX_PR_LABEL == "loop-automation" and
        .AUTOFIX_BRANCH_PREFIX == "loop/github-issue-autofix/" and
        .AUTOFIX_MAX_OPEN_PRS == "3"
    ' <<<"${json}"
    [ "$status" -eq 0 ]
}

@test "loop-scheduled maker is read-only and forbids edits, PRs and repository_dispatch" {
    local instr
    instr="$(job_block loop-scheduled | awk '/^      agent_maker_instructions:/ {f=1; next} f && /^      [a-z]/ {exit} f')"
    [ -n "${instr}" ]
    grep -qi 'do not edit' <<<"${instr}"
    grep -qi 'do not create' <<<"${instr}"
    grep -q 'repository_dispatch' <<<"${instr}"
    grep -qi 'target files' <<<"${instr}"
    grep -qi 'risks' <<<"${instr}"
}

@test "loop-scheduled tool allowlist is read-only" {
    local list
    list="$(job_block loop-scheduled | awk '/^      agent_tool_allowlist:/ {f=1; next} f && /^      [a-z]/ {exit} f')"
    grep -q 'Bash(gh issue view:\*)' <<<"${list}"
    run grep -q 'validate.sh' <<<"${list}"
    [ "$status" -ne 0 ]
}

@test "loop job keeps L2 pr_create configuration and detect_env_json" {
    [ "$(with_line loop level)" = "L2" ]
    [ "$(with_line loop delivery)" = "pr_create" ]
    [ "$(with_line loop agent_edit_target)" = "fix" ]
    [ "$(with_line loop agent_unchanged_verdict)" = "REJECT" ]
    [ "$(with_line loop pr_draft)" = '${{ inputs.pr_draft || false }}' ]
    with_line loop detect_env_json | grep -q '"ISSUE_NUMBER"'
    run grep -q 'AUTOFIX_SCAN' <<<"$(job_block loop)"
    [ "$status" -ne 0 ]
}
