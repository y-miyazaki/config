#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/usage.sh and run_agent_capture

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

@test "accumulate_cursor_stream_usage sums fixture tokens" {
    accumulate_cursor_stream_usage "${FIXTURE}"
    [[ ${USAGE_INPUT_TOTAL} -eq 1842 ]]
    [[ ${USAGE_OUTPUT_TOTAL} -eq 17 ]]
    [[ ${USAGE_MODEL} == "composer-2.5" ]]

    run build_usage_json
    [ "$status" -eq 0 ]
    run jq -e '.total_input_tokens == 1842 and .total_output_tokens == 17 and .model == "composer-2.5"' \
        <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "run_agent_capture preserves USAGE_* unlike pipe to tee" {
    local out_file pipe_lost

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
    pipe_lost=0
    run_agent "true" 2>&1 | tee "${BATS_TEST_TMPDIR}/tee-out.txt" > /dev/null || true
    [[ ${USAGE_INPUT_TOTAL} -eq 0 ]]
    [[ ${USAGE_OUTPUT_TOTAL} -eq 0 ]]
    pipe_lost=1
    [[ ${pipe_lost} -eq 1 ]]
}
