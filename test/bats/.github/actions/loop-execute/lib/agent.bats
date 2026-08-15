#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/agent.sh
#
# Use cases:
# - run_agent_capture preserves USAGE_* unlike pipe to tee
# - harvest_workspace_into_worktree copies modified files from GITHUB_WORKSPACE
# - harvest_workspace_into_worktree deletes paths removed in GITHUB_WORKSPACE
# - harvest_workspace_into_worktree is a no-op when workspace equals worktree

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/usage.sh"
    bats_source_rel ".github/actions/loop-execute/lib/agent.sh"
    reset_usage_totals
    FIXTURE="$(bats_workspace_root)/test/fixtures/loop-execute/cursor-stream-json-usage.ndjson"
}

@test "run_agent_capture preserves USAGE_* unlike pipe to tee" {
    local out_file

    # Simulate cursor engine by stubbing run_agent to accumulate fixture usage.
    function run_agent {
        accumulate_cursor_stream_usage "${FIXTURE}"
        echo "agent-ok"
        return 0
    }

    out_file="${BATS_TEST_TMPDIR}/agent-out.txt"
    reset_usage_totals
    run_agent_capture "${out_file}" "true" > /dev/null
    [[ ${USAGE_INPUT_TOTAL} -eq 1842 ]]
    [[ ${USAGE_OUTPUT_TOTAL} -eq 17 ]]
    [[ "$(cat "${out_file}")" == "agent-ok" ]]

    # Contrasting anti-pattern: pipe creates a subshell and drops USAGE_*.
    reset_usage_totals
    run_agent "true" 2>&1 | tee "${BATS_TEST_TMPDIR}/tee-out.txt" > /dev/null || true
    [[ ${USAGE_INPUT_TOTAL} -eq 0 ]]
    [[ ${USAGE_OUTPUT_TOTAL} -eq 0 ]]
}

@test "harvest_workspace_into_worktree copies modified files from GITHUB_WORKSPACE" {
    local ws wt

    ws="${BATS_TEST_TMPDIR}/ws-copy"
    wt="${BATS_TEST_TMPDIR}/wt-copy"
    bats_git_fresh_repo "${ws}"
    bats_git_fresh_repo "${wt}"
    printf 'orig\n' > "${ws}/foo.txt"
    printf 'orig\n' > "${wt}/foo.txt"
    bats_git_commit "${ws}" "init"
    bats_git_commit "${wt}" "init"
    printf 'edited\n' > "${ws}/foo.txt"
    printf 'new\n' > "${ws}/added.txt"

    GITHUB_WORKSPACE="${ws}"
    WORKTREE_PATH="${wt}"
    harvest_workspace_into_worktree
    [[ "$(cat "${wt}/foo.txt")" == "edited" ]]
    [[ "$(cat "${wt}/added.txt")" == "new" ]]
}

@test "harvest_workspace_into_worktree deletes paths removed in GITHUB_WORKSPACE" {
    local ws wt

    ws="${BATS_TEST_TMPDIR}/ws-del"
    wt="${BATS_TEST_TMPDIR}/wt-del"
    bats_git_fresh_repo "${ws}"
    bats_git_fresh_repo "${wt}"
    printf 'gone\n' > "${ws}/gone.txt"
    printf 'gone\n' > "${wt}/gone.txt"
    bats_git_commit "${ws}" "init"
    bats_git_commit "${wt}" "init"
    rm -f "${ws}/gone.txt"

    GITHUB_WORKSPACE="${ws}"
    WORKTREE_PATH="${wt}"
    harvest_workspace_into_worktree
    [[ ! -e "${wt}/gone.txt" ]]
}

@test "harvest_workspace_into_worktree is a no-op when workspace equals worktree" {
    local wt

    wt="${BATS_TEST_TMPDIR}/wt-same"
    bats_git_fresh_repo "${wt}"
    printf 'keep\n' > "${wt}/keep.txt"
    bats_git_commit "${wt}" "init"
    printf 'dirty\n' > "${wt}/keep.txt"

    GITHUB_WORKSPACE="${wt}"
    WORKTREE_PATH="${wt}"
    harvest_workspace_into_worktree
    [[ "$(cat "${wt}/keep.txt")" == "dirty" ]]
}
