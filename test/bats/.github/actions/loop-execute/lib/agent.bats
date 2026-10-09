#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154
bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-execute/lib/agent.sh
#
# Use cases:
# - run_agent_capture preserves USAGE_* unlike pipe to tee
# - harvest_workspace_into_worktree copies modified files from GITHUB_WORKSPACE
# - harvest_workspace_into_worktree deletes paths removed in GITHUB_WORKSPACE
# - harvest_workspace_into_worktree is a no-op when workspace equals worktree
# - run_agent grants edit permission to claude maker sessions only, and forwards model/max-turns
# - run_agent forwards EFFORT to claude and warns when the engine has no effort flag

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

# _stub_claude_engine: Stub the claude CLI and MCP helpers so run_agent records its args
#
# Arguments:
#   $1 - File that receives the recorded argument line
_stub_claude_engine() {
    local args_file="$1"

    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/claude" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${args_file}"
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/claude"
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    function prepare_agent_mcps { :; }
    function append_agent_mcp_args { :; }
    ENGINE="claude"
    AGENT_TOKEN="dummy-token"
    PROMPT="test prompt"
    MAX_TURNS="5"
    MODEL="claude-sonnet-5"
    WORKING_DIRECTORY="."
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

@test "run_agent claude maker session grants edit permission and passes model" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-maker-args.txt"
    _stub_claude_engine "${args_file}"
    run_agent "true" > /dev/null
    grep -q -- "--permission-mode acceptEdits" "${args_file}"
    grep -q -- "--model claude-sonnet-5" "${args_file}"
    grep -q -- "--max-turns 5" "${args_file}"
}

@test "run_agent claude checker session stays read-only" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-checker-args.txt"
    _stub_claude_engine "${args_file}"
    MODEL="claude-opus-5"
    run_agent "false" > /dev/null
    run ! grep -q -- "--permission-mode" "${args_file}"
    grep -q -- "--model claude-opus-5" "${args_file}"
}

@test "run_agent forwards effort to claude" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-effort-args.txt"
    _stub_claude_engine "${args_file}"
    EFFORT="high"
    run_agent "true" > /dev/null
    grep -q -- "--effort high" "${args_file}"
}

@test "run_agent omits effort flag when EFFORT is empty" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-no-effort-args.txt"
    _stub_claude_engine "${args_file}"
    EFFORT=""
    run_agent "true" > /dev/null
    run ! grep -q -- "--effort" "${args_file}"
}

@test "warn_unsupported_effort stays silent for claude and when EFFORT is unset" {
    EFFORT="high"
    run warn_unsupported_effort "claude"
    [[ ${status} -eq 0 ]]
    [[ -z ${output} ]]

    EFFORT=""
    run warn_unsupported_effort "cursor"
    [[ ${status} -eq 0 ]]
    [[ -z ${output} ]]
}

@test "warn_unsupported_effort warns for engines without an effort flag" {
    EFFORT="high"
    run warn_unsupported_effort "cursor"
    [[ ${status} -eq 0 ]]
    [[ ${output} == *"::warning::engine=cursor ignores effort='high'"* ]]
}
