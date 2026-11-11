#!/usr/bin/env bats

# Tests for .github/workflows/on-loop-github-issue-triage.yaml
#
# Use cases:
# - on keeps issues, issue_comment and workflow_dispatch and adds one schedule entry
# - list job runs only on schedule with read-only contents and issues permissions
# - loop job needs list, uses !cancelled() with the list result, and has a schedule branch
# - loop job fans out over a matrix (fail-fast false, max-parallel 3) read from list outputs
# - handoff_artifact_suffix is per Issue; concurrency group is loop-state-main on schedule
# - Webhook if rejects loop:code-review on the issues branch only and keeps Bot and triage:failed refusals

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    WF="${ROOT}/.github/workflows/on-loop-github-issue-triage.yaml"
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

# job_if JOB: print the job-level if: expression lines
job_if() {
    job_block "$1" | awk '
        /^    if:/ {print; g=1; next}
        g { if ($0 ~ /^    [a-z]/) {exit} print }
    '
}

# if_branch JOB START END: print loop if lines from the START marker up to (not including) END
if_branch() {
    job_if "$1" | awk -v s="$2" -v e="$3" '
        index($0, s) {f=1}
        e != "" && index($0, e) {f=0}
        f
    '
}

@test "on keeps issues, issue_comment, workflow_dispatch and has one schedule entry" {
    local on
    on="$(awk '/^on:/ {f=1; next} f && /^[a-z]/ {exit} f' "${WF}")"
    grep -q '^  issues:' <<<"${on}"
    grep -q '^  issue_comment:' <<<"${on}"
    grep -q '^  workflow_dispatch:' <<<"${on}"
    grep -q '^  schedule:' <<<"${on}"
    [ "$(grep -c 'cron:' <<<"${on}")" -eq 1 ]
}

@test "list job runs only on schedule with contents and issues read permissions" {
    local block
    block="$(job_block list)"
    [ -n "${block}" ]
    [ "$(job_if list | tr -s ' \n' ' ' | sed 's/^ *//; s/ *$//')" = "if: github.event_name == 'schedule'" ]
    local perms
    perms="$(awk '/^    permissions:/ {f=1; next} f && /^    [a-z]/ {exit} f' <<<"${block}" | sed 's/^ *//' | sort | tr '\n' ' ')"
    [ "${perms}" = "contents: read issues: read " ]
    grep -q 'persist-credentials: false' <<<"${block}"
    grep -q 'GH_TOKEN: \${{ github.token }}' <<<"${block}"
    grep -q 'timeout-minutes:' <<<"${block}"
    grep -q 'scripts/self/loop/list_triage_issues.sh' <<<"${block}"
}

@test "loop job needs list and gates with !cancelled(), list result and a schedule branch" {
    local block iff
    block="$(job_block loop)"
    grep -qx '    needs: list' <<<"${block}"
    iff="$(job_if loop)"
    grep -q '!cancelled()' <<<"${iff}"
    grep -q "needs.list.result == 'success'" <<<"${iff}"
    grep -q "needs.list.result == 'skipped'" <<<"${iff}"
    grep -q "github.event_name == 'schedule'" <<<"${iff}"
    grep -q 'needs.list.outputs.count > 0' <<<"${iff}"
}

@test "loop job matrix reads list outputs with fail-fast false and max-parallel 3" {
    local block
    block="$(job_block loop)"
    grep -qx '      fail-fast: false' <<<"${block}"
    grep -qx '      max-parallel: 3' <<<"${block}"
    grep -q 'issue: \${{ fromJSON(needs.list.outputs.issues ||' <<<"${block}"
    grep -q "handoff_artifact_suffix: -issue-" <<<"${block}"
}

@test "detect_env_json covers schedule, workflow_dispatch and default" {
    local line
    line="$(job_block loop | grep 'detect_env_json:')"
    grep -q 'ISSUE_EVENT_NAME' <<<"${line}"
    grep -q "github.event_name == 'schedule'" <<<"${line}"
    grep -q "github.event_name == 'workflow_dispatch'" <<<"${line}"
    grep -q "'{}'" <<<"${line}"
    grep -q 'matrix.issue' <<<"${line}"
}

@test "concurrency group is loop-state-main on schedule" {
    local group
    group="$(grep '^  group:' "${WF}")"
    grep -q "github.event_name == 'schedule' && 'loop-state-main'" <<<"${group}"
    grep -qx '  cancel-in-progress: false' "${WF}"
    grep -qx '  queue: max' "${WF}"
}

@test "issues branch rejects loop:code-review; issue_comment branch does not" {
    local issues comment
    issues="$(if_branch loop "github.event_name == 'issues'" "github.event_name == 'issue_comment'")"
    comment="$(if_branch loop "github.event_name == 'issue_comment'" "")"
    [ -n "${issues}" ]
    [ -n "${comment}" ]
    grep -q "!contains(github.event.issue.labels.\*.name, 'loop:code-review')" <<<"${issues}"
    run grep -q 'loop:code-review' <<<"${comment}"
    [ "$status" -ne 0 ]
}

@test "issues branch keeps Bot sender and triage:failed refusals" {
    local issues
    issues="$(if_branch loop "github.event_name == 'issues'" "github.event_name == 'issue_comment'")"
    grep -q "github.event.sender.type != 'Bot'" <<<"${issues}"
    grep -q "!contains(github.event.issue.labels.\*.name, 'triage:failed')" <<<"${issues}"
}
