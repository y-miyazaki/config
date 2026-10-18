#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154,SC2317

# Tests for .github/actions/loop-execute/lib/loop.sh helpers
#
# Use cases:
# - parse_outcome_override_from_agent_output detects bold Outcome watch
# - parse_outcome_override_from_agent_output detects plain Outcome deferred
# - parse_outcome_override_from_agent_output detects no actionable failures
# - parse_outcome_override_from_agent_output ignores fix outcomes
# - promote_has_changes_after_attempt ignores branch-ahead on attempt 1
# - promote_has_changes_after_attempt keeps branch-ahead on attempt 2+
# - promote_has_changes_after_attempt treats HEAD movement as this-attempt changes
# - write_loop_outputs includes denylist_blocked
# - write_loop_outputs emits finalize_outcome_override (not outcome_override)
# - initialize_loop_state fails when AGENT_UNCHANGED_VERDICT is empty (no REJECT default)
# - main requires AGENT_ENGINE and ignores the legacy ENGINE name
# - run_bounded_loop commits with AGENT_COMMIT_MESSAGE and resolves a no-change
#   attempt with AGENT_UNCHANGED_VERDICT (legacy COMMIT_MESSAGE / NO_CHANGES_VERDICT ignored)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    # loop.sh pulls in the full execute lib stack via _init.
    bats_source_rel ".github/actions/loop-execute/lib/loop.sh"
}

# _commit_branch_ahead_of_main: Create a repo whose HEAD branch is one product
# commit (docs/foo.md) ahead of local main
#
# Arguments:
#   $1 - Repository path
_commit_branch_ahead_of_main() {
    local repo="$1"
    bats_git_fresh_repo "${repo}"
    bats_git_cmd -C "${repo}" checkout -q -b main
    printf 'x\n' > "${repo}/x.txt"
    bats_git_commit "${repo}" "init"
    bats_git_cmd -C "${repo}" checkout -q -b loop/work
    mkdir -p "${repo}/docs"
    printf 'foo\n' > "${repo}/docs/foo.md"
    bats_git_commit "${repo}" "docs"
}

@test "parse_outcome_override_from_agent_output detects bold Outcome watch" {
    run parse_outcome_override_from_agent_output $'## Summary\n- **Outcome:** watch\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output detects plain Outcome deferred" {
    run parse_outcome_override_from_agent_output $'Outcome: deferred — infra flake\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output detects no actionable failures" {
    run parse_outcome_override_from_agent_output $'- **Outcome:** no actionable failures\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output ignores fix outcomes" {
    run parse_outcome_override_from_agent_output $'- **Outcome:** Fixed MD001 in docs/ci-sweeper-test.md\n'
    [ "$status" -ne 0 ]
}

@test "write_loop_outputs includes denylist_blocked" {
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    ATTEMPT=2
    VERDICT="REJECT"
    REASON="Denylist violation: secrets.yaml"
    HAS_CHANGES="true"
    DENYLIST_BLOCKED="true"
    OPEN_REJECTIONS_JSON='[]'
    FINALIZE_OUTCOME_OVERRIDE=""
    write_loop_outputs
    grep -q '^denylist_blocked=true$' "${GITHUB_OUTPUT}"
}

@test "write_loop_outputs emits finalize_outcome_override" {
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    ATTEMPT=1
    VERDICT="REJECT"
    REASON="Skill classified as watch with no file changes"
    HAS_CHANGES="false"
    DENYLIST_BLOCKED="false"
    OPEN_REJECTIONS_JSON='[]'
    FINALIZE_OUTCOME_OVERRIDE="watch"
    OUTCOME_OVERRIDE="legacy"
    write_loop_outputs
    run grep -E '(^|_)outcome_override=' "${GITHUB_OUTPUT}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "finalize_outcome_override=watch" ]
}

@test "initialize_loop_state fails when AGENT_UNCHANGED_VERDICT is empty" {
    STATUS_DIR="${BATS_TEST_TMPDIR}/status-init"
    AGENT_UNCHANGED_VERDICT=""
    NO_CHANGES_VERDICT="REJECT"
    function materialize_matrix_handoff_context { echo "materialize-called"; }
    run initialize_loop_state
    [ "${status}" -eq 1 ]
    [ "${output}" = "::error::agent_unchanged_verdict is required (APPROVE or REJECT); got: ''" ]
}

@test "main requires AGENT_ENGINE and ignores the legacy ENGINE name" {
    function initialize_loop_state { :; }
    function run_bounded_loop { :; }
    function write_loop_outputs { echo "outputs-written"; }
    STATUS_DIR="${BATS_TEST_TMPDIR}/status-main"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}"
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    AGENT_LOOP_MAX_ATTEMPTS=1
    PROMPT_TEXT="prompt"
    AGENT_TOKEN="dummy-token"
    unset AGENT_ENGINE
    ENGINE="claude"
    run main
    [ "${status}" -ne 0 ]
    [[ ${output} == *"AGENT_ENGINE"* ]]
    [[ ${output} != *"outputs-written"* ]]

    AGENT_ENGINE="claude"
    run main
    [ "${status}" -eq 0 ]
    [ "${output}" = "outputs-written" ]
}

@test "run_bounded_loop uses AGENT_COMMIT_MESSAGE and AGENT_UNCHANGED_VERDICT" {
    local commit_log="${BATS_TEST_TMPDIR}/commit-messages.txt"
    STATUS_DIR="${BATS_TEST_TMPDIR}/status-loop"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/wt-loop"
    bats_git_fresh_repo "${WORKTREE_PATH}"
    printf 'x\n' > "${WORKTREE_PATH}/x.txt"
    bats_git_commit "${WORKTREE_PATH}" "init"
    AGENT_LOOP_MAX_ATTEMPTS=1
    AGENT_MAKER_SKILL_NAME="changelog"
    AGENT_MAKER_MAX_TURNS="5"
    AGENT_MAKER_MODEL=""
    HAS_CHANGES="false"
    AGENT_COMMIT_MESSAGE="chore: new name"
    COMMIT_MESSAGE="chore: legacy name"
    AGENT_UNCHANGED_VERDICT="APPROVE"
    NO_CHANGES_VERDICT="REJECT"
    function sync_reject_feedback { :; }
    function agent_report_skill_requires_format_check { return 1; }
    function build_agent_prompt { printf 'prompt'; }
    function run_agent_capture { : > "$1"; }
    function harvest_workspace_into_worktree { return 0; }
    function commit_worktree_if_needed {
        printf '%s\n' "$1" >> "${commit_log}"
        return 1
    }

    run_bounded_loop > /dev/null
    [ "$(cat "${commit_log}")" = "chore: new name (attempt 1)" ]
    [ "${VERDICT}" = "APPROVE" ]
    [ "${REASON}" = "No file changes produced" ]
}

@test "run_bounded_loop names permission denials in the no-change reason" {
    local commit_log="${BATS_TEST_TMPDIR}/commit-messages.txt"
    STATUS_DIR="${BATS_TEST_TMPDIR}/status-loop"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/wt-loop"
    bats_git_fresh_repo "${WORKTREE_PATH}"
    printf 'x\n' > "${WORKTREE_PATH}/x.txt"
    bats_git_commit "${WORKTREE_PATH}" "init"
    AGENT_LOOP_MAX_ATTEMPTS=1
    AGENT_MAKER_SKILL_NAME="changelog"
    AGENT_MAKER_MAX_TURNS="5"
    AGENT_MAKER_MODEL=""
    HAS_CHANGES="false"
    AGENT_COMMIT_MESSAGE="chore: new name"
    COMMIT_MESSAGE="chore: legacy name"
    AGENT_UNCHANGED_VERDICT="APPROVE"
    NO_CHANGES_VERDICT="REJECT"
    function sync_reject_feedback { :; }
    function agent_report_skill_requires_format_check { return 1; }
    function build_agent_prompt { printf 'prompt'; }
    function run_agent_capture { printf '::warning::Agent permission_denials: [{"tool_name":"Edit"}]\n' > "$1"; }
    function harvest_workspace_into_worktree { return 0; }
    function commit_worktree_if_needed {
        printf '%s\n' "$1" >> "${commit_log}"
        return 1
    }

    run_bounded_loop > /dev/null
    [ "${VERDICT}" = "APPROVE" ]
    [ "${REASON}" = "No file changes produced; 1 tool call(s) denied by permission settings" ]
}

@test "permission_denial_note is empty without a denial warning" {
    printf 'Agent summary: role=maker\n' > "${BATS_TEST_TMPDIR}/out.txt"
    run permission_denial_note "${BATS_TEST_TMPDIR}/out.txt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "permission_denial_note is empty when the file is missing" {
    run permission_denial_note "${BATS_TEST_TMPDIR}/missing.txt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "permission_denial_note counts denied tool calls" {
    printf '::warning::Agent permission_denials: [{"tool_name":"Edit"},{"tool_name":"Bash"}]\n' > "${BATS_TEST_TMPDIR}/out.txt"
    run permission_denial_note "${BATS_TEST_TMPDIR}/out.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "; 2 tool call(s) denied by permission settings" ]
}

@test "permission_denial_note ignores an empty denial list" {
    printf '::warning::Agent permission_denials: []\n' > "${BATS_TEST_TMPDIR}/out.txt"
    run permission_denial_note "${BATS_TEST_TMPDIR}/out.txt"
    [ -z "$output" ]
}

@test "promote_has_changes_after_attempt leaves HAS_CHANGES false on attempt 1 when HEAD unchanged" {
    HAS_CHANGES="false"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/wt-a1"
    _commit_branch_ahead_of_main "${WORKTREE_PATH}"
    BASE_BRANCH="main"
    [ "$(list_non_loop_branch_files "${WORKTREE_PATH}" "${BASE_BRANCH}")" = "docs/foo.md" ]
    local pre
    pre="$(git -C "${WORKTREE_PATH}" rev-parse HEAD)"
    promote_has_changes_after_attempt 1 "${pre}" "false"
    [[ ${HAS_CHANGES} == "false" ]]
}

@test "promote_has_changes_after_attempt sets HAS_CHANGES on attempt 2 when branch has product files" {
    HAS_CHANGES="false"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/wt-a2"
    _commit_branch_ahead_of_main "${WORKTREE_PATH}"
    BASE_BRANCH="main"
    [ "$(list_non_loop_branch_files "${WORKTREE_PATH}" "${BASE_BRANCH}")" = "docs/foo.md" ]
    local pre
    pre="$(git -C "${WORKTREE_PATH}" rev-parse HEAD)"
    promote_has_changes_after_attempt 2 "${pre}" "false"
    [[ ${HAS_CHANGES} == "true" ]]
}

@test "promote_has_changes_after_attempt sets HAS_CHANGES when HEAD moved" {
    HAS_CHANGES="false"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/wt-head"
    bats_git_fresh_repo "${WORKTREE_PATH}"
    printf 'x\n' > "${WORKTREE_PATH}/x.txt"
    bats_git_commit "${WORKTREE_PATH}" "init"
    BASE_BRANCH="main"
    function list_non_loop_branch_files { printf ''; }
    local pre
    pre="$(git -C "${WORKTREE_PATH}" rev-parse HEAD)"
    printf 'y\n' > "${WORKTREE_PATH}/x.txt"
    bats_git_commit "${WORKTREE_PATH}" "agent commit"
    promote_has_changes_after_attempt 1 "${pre}" "false"
    [[ ${HAS_CHANGES} == "true" ]]
}
