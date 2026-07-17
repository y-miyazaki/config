#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/notify_context.sh

# Use cases:
# - build_fix_summary falls back for invalid json
# - build_fix_summary formats job and workflow from failures
# - extract_agent_report_summary takes ## Summary until next H2
# - main includes changed files when has_changes is true
# - main parses agent_report_summary from status dir
# - main parses agent_summary from status dir
# - main writes notify_context_json without changes
# - parse_agent_summary extracts block after marker
# - parse_agent_summary returns empty when file missing
# - redact_sensitive_text redacts github tokens
# - truncate_text preserves short input
# - truncate_text truncates long input

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

NOTIFY_CONTEXT_SCRIPT="$(bats_workspace_root)/.github/actions/loop-execute/lib/notify_context.sh"

notify_context_git_setup() {
    local bare
    git_test_repo_setup
    git -C "${GIT_TEST_REPO}" checkout -q -b main
    printf 'base\n' > "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: base"
    bare="${BATS_TEST_TMPDIR}/origin.git"
    rm -rf "${bare}"
    git init -q --bare "${bare}"
    git -C "${GIT_TEST_REPO}" remote add origin "${bare}"
    git -C "${GIT_TEST_REPO}" push -q -u origin main
}

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/notify_context.sh"
    GITHUB_OUTPUT="$(mktemp)"
    STATUS_DIR=""
    DETECT_RESULT_JSON="{}"
    HAS_CHANGES="false"
}

teardown() {
    rm -f "${GITHUB_OUTPUT:-}"
}

@test "build_fix_summary falls back for invalid json" {
    run build_fix_summary "not-json"
    [ "$status" -eq 0 ]
    [ "$output" = "Loop automated fix" ]
}

@test "build_fix_summary formats job and workflow from failures" {
    local detect_json
    detect_json='{"failures":[{"job_name":"lint","workflow_name":"on-ci-push"}],"workflow_name":"ignored"}'
    run build_fix_summary "${detect_json}"
    [ "$status" -eq 0 ]
    [ "$output" = "Address CI failure in lint (on-ci-push)" ]
}

@test "extract_agent_report_summary takes ## Summary until next H2" {
    local f
    f="${BATS_TEST_TMPDIR}/agent-output.txt"
    cat > "$f" << 'EOF'
noise
## Summary
- **Root cause:** MD001
- **Outcome:** fixed

## Ignored
- none
EOF
    run extract_agent_report_summary "$f"
    [ "$status" -eq 0 ]
    [[ $output == *"Root cause"* ]]
    [[ $output != *"## Ignored"* ]]
    [[ $output != *"## Summary"* ]]
}

@test "main includes changed files when has_changes is true" {
    local json detect_file
    notify_context_git_setup
    printf 'change\n' >> "${GIT_TEST_REPO}/file.txt"
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf 'extra\n' > "${GIT_TEST_REPO}/docs/a.md"
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "fix: change"

    GITHUB_OUTPUT="$(mktemp)"
    detect_file="$(mktemp)"
    printf '%s\n' '{"failures":[{"job_name":"test","workflow_name":"ci"}]}' > "${detect_file}"

    run env \
        HAS_CHANGES=true \
        WORKTREE_PATH="${GIT_TEST_REPO}" \
        BASE_BRANCH=main \
        DETECT_RESULT_JSON="$(cat "${detect_file}")" \
        GITHUB_OUTPUT="${GITHUB_OUTPUT}" \
        STATUS_DIR= \
        bash "${NOTIFY_CONTEXT_SCRIPT}"
    [ "$status" -eq 0 ]

    json="$(awk '/^notify_context_json<</{found=1;next} found{if($0 ~ /^NOTIFY_CONTEXT_/) exit; print}' "${GITHUB_OUTPUT}")"
    run jq -e '
      (.changed_files | index("file.txt") != null)
      and (.changed_files | index("docs/a.md") != null)
      and (.fix_summary == "Address CI failure in test (ci)")
      and (.diff_stat | length) > 0
      and (.baseline_ref | length) > 0
    ' <<< "${json}"
    [ "$status" -eq 0 ]
    rm -f "${detect_file}"
}

@test "main parses agent_report_summary from status dir" {
    local status_dir json
    notify_context_git_setup
    status_dir="${BATS_TEST_TMPDIR}/status"
    mkdir -p "${status_dir}/attempt-1"
    cat > "${status_dir}/attempt-1/agent-output.txt" << 'EOF'
noise before
## Summary
- **Root cause:** MD001
- **Outcome:** fixed

## Ignored
- none
EOF

    GITHUB_OUTPUT="$(mktemp)"
    run bash -c "HAS_CHANGES='false' WORKTREE_PATH='${GIT_TEST_REPO}' BASE_BRANCH='main' DETECT_RESULT_JSON='{}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' STATUS_DIR='${status_dir}' bash '${NOTIFY_CONTEXT_SCRIPT}'"
    [ "$status" -eq 0 ]

    json="$(awk '/^notify_context_json<</{found=1;next} found{if($0 ~ /^NOTIFY_CONTEXT_/) exit; print}' "${GITHUB_OUTPUT}")"
    run jq -er '.agent_report_summary' <<< "${json}"
    [ "$status" -eq 0 ]
    [[ $output == *"Root cause"* ]]
    [[ $output != *"## Ignored"* ]]
}

@test "main parses agent_summary from status dir" {
    local status_dir json
    notify_context_git_setup
    status_dir="${BATS_TEST_TMPDIR}/status"
    mkdir -p "${status_dir}/attempt-1"
    cat > "${status_dir}/attempt-1/agent-output.txt" << 'EOF'
noise before
<!-- loop-agent-summary:v1 -->
Fixed the lint job by updating the allowlist.
```
ignored fence
EOF

    GITHUB_OUTPUT="$(mktemp)"
    run bash -c "HAS_CHANGES='false' WORKTREE_PATH='${GIT_TEST_REPO}' BASE_BRANCH='main' DETECT_RESULT_JSON='{}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' STATUS_DIR='${status_dir}' bash '${NOTIFY_CONTEXT_SCRIPT}'"
    [ "$status" -eq 0 ]

    json="$(awk '/^notify_context_json<</{found=1;next} found{if($0 ~ /^NOTIFY_CONTEXT_/) exit; print}' "${GITHUB_OUTPUT}")"
    run jq -er '.agent_summary' <<< "${json}"
    [ "$status" -eq 0 ]
    [[ $output == *"Fixed the lint job"* ]]
}

@test "main writes notify_context_json without changes" {
    local json
    notify_context_git_setup

    GITHUB_OUTPUT="$(mktemp)"
    run bash -c "HAS_CHANGES='false' WORKTREE_PATH='${GIT_TEST_REPO}' BASE_BRANCH='main' DETECT_RESULT_JSON='{}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' STATUS_DIR='' bash '${NOTIFY_CONTEXT_SCRIPT}'"
    [ "$status" -eq 0 ]

    json="$(awk '/^notify_context_json<</{found=1;next} found{if($0 ~ /^NOTIFY_CONTEXT_/) exit; print}' "${GITHUB_OUTPUT}")"
    run jq -e '
      .changed_files == []
      and .diff_stat == ""
      and .fix_summary == "Address CI failure in CI (workflow)"
      and .agent_summary == ""
      and .agent_report_summary == ""
      and (.baseline_ref | length) > 0
    ' <<< "${json}"
    [ "$status" -eq 0 ]
}

@test "parse_agent_summary extracts block after marker" {
    local tmpf
    tmpf="$(mktemp)"
    cat > "${tmpf}" << 'EOF'
preamble
<!-- loop-agent-summary:v1 -->
summary line one
summary line two
```
code
EOF
    run parse_agent_summary "${tmpf}"
    [ "$status" -eq 0 ]
    [[ $output == *"summary line one"* ]]
    [[ $output == *"summary line two"* ]]
    [[ $output != *"code"* ]]
    rm -f "${tmpf}"
}

@test "parse_agent_summary returns empty when file missing" {
    run parse_agent_summary "${BATS_TEST_TMPDIR}/missing-agent-output.txt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "redact_sensitive_text redacts github tokens" {
    run redact_sensitive_text "token=gha_abcdefghijklmnopqrstuvwxyz" # pragma: allowlist secret
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"gha_abcdefghijklmnopqrstuvwxyz"* ]] # pragma: allowlist secret
}

@test "truncate_text preserves short input" {
    run truncate_text "short" 10
    [ "$status" -eq 0 ]
    [ "$output" = "short" ]
}

@test "truncate_text truncates long input" {
    run truncate_text "abcdefghij" 4
    [ "$status" -eq 0 ]
    [ "$output" = "abcd" ]
}
