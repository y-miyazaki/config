#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-agent-once/lib/run.sh
#
# Use cases:
# - emit_usage_json_output writes empty usage_json when nothing was captured
# - emit_usage_json_output writes measured totals to GITHUB_OUTPUT
# - run_loop_agent_once captures cursor stream-json usage via a mock agent

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
    export ENGINE="cursor"
    export AGENT_TOKEN="test-token"
    export PROMPT="hello"
    export WORKING_DIRECTORY="."
    export MAX_TURNS=""
    export MODEL=""
    export OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    grep -q '1842' "${GITHUB_OUTPUT}"
    grep -q '17' "${GITHUB_OUTPUT}"
}
