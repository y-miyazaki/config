#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-agent-once/lib/run.sh
#
# Use cases:
# - emit_usage_json_output writes empty usage_json when nothing was captured
# - emit_usage_json_output writes measured totals to GITHUB_OUTPUT
# - run_loop_agent_once captures cursor stream-json usage via a mock agent
# - run_loop_agent_once maps AGENT_MAKER_MODEL / AGENT_MAKER_EFFORT /
#   AGENT_MAKER_MAX_TURNS onto the role vars MODEL / EFFORT / MAX_TURNS before
#   run_agent and run_agent_capture (asserted on the stubbed claude CLI args);
#   the legacy MODEL / EFFORT / MAX_TURNS env values do not reach the agent
# - run_loop_agent_once reads AGENT_ENGINE, not the legacy ENGINE name

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-agent-once/lib/run.sh"
    reset_usage_totals
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    export GITHUB_OUTPUT
}

# _stub_claude_cli: Put a claude stub on PATH that records its argument line
#
# Globals:
#   CLAUDE_ARGS_FILE - File that receives the recorded argument line (write)
#   CLAUDE_BASE_ARGS - Arguments run_agent always passes for this prompt (write)
_stub_claude_cli() {
    local bindir="${BATS_TEST_TMPDIR}/bin-claude"
    CLAUDE_ARGS_FILE="${BATS_TEST_TMPDIR}/claude-args.txt"
    mkdir -p "${bindir}" "${BATS_TEST_TMPDIR}/home"
    cat > "${bindir}/claude" << STUB
#!/bin/bash
printf '%s\n' "\$*" > "${CLAUDE_ARGS_FILE}"
STUB
    chmod +x "${bindir}/claude"
    PATH="${bindir}:${PATH}"
    HOME="${BATS_TEST_TMPDIR}/home"
    unset GITHUB_WORKSPACE CLAUDE_CONFIG_DIR AGENT_TOOL_ALLOWLIST DETECT_JSON_FILE
    AGENT_ENGINE="claude"
    AGENT_TOKEN="dummy-token"
    PROMPT="hello"
    WORKING_DIRECTORY="."
    CLAUDE_BASE_ARGS='-p hello --output-format stream-json --verbose --settings {"enableAllProjectMcpServers":true} --setting-sources project --permission-mode acceptEdits'
}

@test "emit_usage_json_output writes empty usage_json when nothing captured" {
    emit_usage_json_output
    grep -q '^usage_json=$' "${GITHUB_OUTPUT}"
}

@test "emit_usage_json_output writes measured totals" {
    USAGE_INPUT_TOTAL=1842
    USAGE_OUTPUT_TOTAL=17
    USAGE_MODEL="composer-2.5"
    emit_usage_json_output
    grep -q 'total_input_tokens' "${GITHUB_OUTPUT}"
    grep -q '"total_input_tokens":1842' "${GITHUB_OUTPUT}" || grep -q '1842' "${GITHUB_OUTPUT}"
}

@test "run_loop_agent_once captures cursor stream-json usage from mock agent" {
    local bindir fixture
    fixture="$(bats_workspace_root)/test/fixtures/loop-execute/cursor-stream-json-usage.ndjson"
    [ -f "${fixture}" ]
    bindir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bindir}"
    cat > "${bindir}/agent" << EOF
#!/bin/bash
cat "${fixture}"
EOF
    chmod +x "${bindir}/agent"
    export PATH="${bindir}:${PATH}"
    export AGENT_ENGINE="cursor"
    export AGENT_TOKEN="test-token"
    export PROMPT="hello"
    export WORKING_DIRECTORY="."
    export AGENT_MAKER_MAX_TURNS=""
    export AGENT_MAKER_MODEL=""
    export OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    grep -q '1842' "${GITHUB_OUTPUT}"
    grep -q '17' "${GITHUB_OUTPUT}"
}

@test "run_loop_agent_once fails without AGENT_ENGINE even when legacy ENGINE is set" {
    local bindir
    bindir="${BATS_TEST_TMPDIR}/bin-legacy"
    mkdir -p "${bindir}"
    printf '#!/bin/bash\necho agent-ran\n' > "${bindir}/agent"
    chmod +x "${bindir}/agent"
    export PATH="${bindir}:${PATH}"
    unset AGENT_ENGINE
    export ENGINE="cursor"
    export AGENT_TOKEN="test-token"
    export PROMPT="hello"
    export OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -ne 0 ]
    [[ ${output} != *"agent-ran"* ]]
}

@test "run_loop_agent_once maps AGENT_MAKER_* onto the role vars before run_agent" {
    _stub_claude_cli
    MODEL="legacy-model"
    EFFORT="legacy-effort"
    MAX_TURNS="99"
    AGENT_MAKER_MODEL="claude-sonnet-5"
    AGENT_MAKER_EFFORT="high"
    AGENT_MAKER_MAX_TURNS="7"
    OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    [ "$(cat "${CLAUDE_ARGS_FILE}")" = "${CLAUDE_BASE_ARGS} --effort high --max-turns 7 --model claude-sonnet-5" ]
}

@test "run_loop_agent_once maps AGENT_MAKER_* onto the role vars before run_agent_capture" {
    _stub_claude_cli
    MODEL="legacy-model"
    EFFORT="legacy-effort"
    MAX_TURNS="99"
    AGENT_MAKER_MODEL="claude-opus-5"
    AGENT_MAKER_EFFORT="low"
    AGENT_MAKER_MAX_TURNS="3"
    OUTPUT_FILE="${BATS_TEST_TMPDIR}/agent-out.txt"
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    [ -f "${OUTPUT_FILE}" ]
    [ "$(cat "${CLAUDE_ARGS_FILE}")" = "${CLAUDE_BASE_ARGS} --effort low --max-turns 3 --model claude-opus-5" ]
}

@test "run_loop_agent_once clears legacy role values when AGENT_MAKER_* are empty" {
    _stub_claude_cli
    MODEL="legacy-model"
    EFFORT="legacy-effort"
    MAX_TURNS="99"
    unset AGENT_MAKER_MODEL AGENT_MAKER_EFFORT AGENT_MAKER_MAX_TURNS
    OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    [ "$(cat "${CLAUDE_ARGS_FILE}")" = "${CLAUDE_BASE_ARGS}" ]
}
