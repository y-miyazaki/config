#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/usage.sh

# Use cases:
# - reset_usage_totals clears module globals
# - accumulate_cursor_usage_from_line sums result usage
# - accumulate_cursor_stream_usage reads model from system init
# - build_usage_json returns empty when no usage captured
# - build_usage_json serializes measured totals
# - accumulate_cursor_stream_usage parses fixture stream-json with camelCase usage
# - is_cursor_stream_json_file detects stream-json captures
# - extract_cursor_stream_text returns assistant markdown with json fence
# - render_cursor_stream_log_summary omits raw ndjson and includes tool summary
# - run_cursor_agent_with_usage captures usage from live cursor stream-json
# - accumulate_claude_usage_from_line keeps cache tokens out of the token totals
# - accumulate_cost_usd sums across sessions and ignores junk
# - accumulate_cursor_usage_from_line records cache tokens and no cost
# - build_usage_json reports cache and cost without folding them into totals
# - build_usage_json omits cost when the engine reports none
# - accumulate_claude_stream_usage reads model from system init
# - accumulate_claude_stream_usage ignores non-json lines
# - render_claude_stream_log_summary prints final text and hides ndjson
# - run_claude_agent_with_usage captures usage and forwards exit code

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/usage.sh"
    reset_usage_totals
}

@test "reset_usage_totals clears module globals" {
    USAGE_INPUT_TOTAL=100
    USAGE_OUTPUT_TOTAL=50
    USAGE_MODEL="composer-2.5"
    reset_usage_totals
    [ "${USAGE_INPUT_TOTAL}" -eq 0 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 0 ]
    [ "${USAGE_MODEL}" = "" ]
}

@test "accumulate_cursor_usage_from_line sums result usage" {
    local line='{"type":"result","usage":{"inputTokens":1200,"outputTokens":300},"model":"composer-2.5"}'
    accumulate_cursor_usage_from_line "${line}"
    [ "${USAGE_INPUT_TOTAL}" -eq 1200 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 300 ]
    [ "${USAGE_MODEL}" = "composer-2.5" ]
}

@test "accumulate_cursor_stream_usage reads model from system init" {
    local tmpf
    tmpf="$(mktemp)"
    printf '%s\n' \
        '{"type":"system","subtype":"init","model":"cursor-grok-4.5-low"}' \
        '{"type":"result","usage":{"total_input_tokens":500,"total_output_tokens":100}}' \
        > "${tmpf}"
    accumulate_cursor_stream_usage "${tmpf}"
    rm -f "${tmpf}"
    [ "${USAGE_INPUT_TOTAL}" -eq 500 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 100 ]
    [ "${USAGE_MODEL}" = "cursor-grok-4.5-low" ]
}

@test "build_usage_json returns empty when no usage captured" {
    result="$(build_usage_json)"
    [ -z "${result}" ]
}

@test "build_usage_json serializes measured totals" {
    USAGE_INPUT_TOTAL=1000
    USAGE_OUTPUT_TOTAL=250
    USAGE_MODEL="composer-2.5"
    result="$(build_usage_json)"
    [ "$(jq -r '.total_input_tokens' <<< "${result}")" = "1000" ]
    [ "$(jq -r '.total_output_tokens' <<< "${result}")" = "250" ]
    [ "$(jq -r '.model' <<< "${result}")" = "composer-2.5" ]
}

@test "accumulate_cursor_stream_usage parses fixture stream-json with camelCase usage" {
    local fixture="test/fixtures/loop-execute/cursor-stream-json-usage.ndjson"
    [ -f "${fixture}" ]
    accumulate_cursor_stream_usage "${fixture}"
    [ "${USAGE_INPUT_TOTAL}" -eq 1842 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 17 ]
    [ "${USAGE_MODEL}" = "composer-2.5" ]
    result="$(build_usage_json)"
    [ "$(jq -r '.total_input_tokens' <<< "${result}")" = "1842" ]
}

@test "is_cursor_stream_json_file detects stream-json captures" {
    is_cursor_stream_json_file test/fixtures/loop-execute/cursor-stream-json-usage.ndjson
    tmpf="$(mktemp)"
    echo "plain text output" > "${tmpf}"
    run is_cursor_stream_json_file "${tmpf}"
    [ "$status" -ne 0 ]
    rm -f "${tmpf}"
}

@test "extract_cursor_stream_text returns assistant markdown with json fence" {
    local fixture="test/fixtures/loop-execute/cursor-stream-json-verifier.ndjson"
    result="$(extract_cursor_stream_text "${fixture}")"
    [[ ${result} == *'```json'* ]]
    [[ ${result} == *'"verdict": "REJECT"'* ]]
}

@test "render_cursor_stream_log_summary omits raw ndjson and includes tool summary" {
    local fixture="test/fixtures/loop-execute/cursor-stream-json-verifier.ndjson"
    accumulate_cursor_stream_usage "${fixture}"
    result="$(render_cursor_stream_log_summary "${fixture}")"
    [[ ${result} == *"Agent summary:"* ]]
    [[ ${result} == *"read docs/explanation/architecture.md"* ]]
    [[ ${result} == *'"verdict": "REJECT"'* ]]
    [[ ${result} != *'"type":"tool_call"'* ]]
}

@test "run_cursor_agent_with_usage captures usage from live cursor stream-json" {
    if [[ -z ${CURSOR_API_KEY:-} ]]; then
        skip "CURSOR_API_KEY not set; export it to run live Cursor usage verification"
    fi
    if ! command -v agent > /dev/null 2>&1; then
        skip "Cursor agent CLI not installed"
    fi

    local rc=0
    run_cursor_agent_with_usage agent \
        -p "Reply with exactly the single word: ok" \
        --print \
        --output-format stream-json \
        --trust || rc=$?

    [ "${rc}" -eq 0 ]
    [ "${USAGE_INPUT_TOTAL}" -gt 0 ]
    [ "${USAGE_OUTPUT_TOTAL}" -gt 0 ]
    result="$(build_usage_json)"
    [ -n "${result}" ]
    [ "$(jq -r '.total_input_tokens' <<< "${result}")" -gt 0 ]
}

@test "accumulate_claude_usage_from_line keeps cache tokens out of the token totals" {
    local line='{"type":"result","total_cost_usd":0.865485,"usage":{"input_tokens":4815,"output_tokens":14276,"cache_creation_input_tokens":72780,"cache_read_input_tokens":2107374},"modelUsage":{"claude-sonnet-5":{}}}'
    accumulate_claude_usage_from_line "${line}"
    [ "${USAGE_INPUT_TOTAL}" -eq 4815 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 14276 ]
    [ "${USAGE_CACHE_WRITE_TOTAL}" -eq 72780 ]
    [ "${USAGE_CACHE_READ_TOTAL}" -eq 2107374 ]
    [ "${USAGE_COST_USD}" = "0.865485" ]
    [ "${USAGE_MODEL}" = "claude-sonnet-5" ]
}

@test "accumulate_cost_usd sums across sessions and ignores junk" {
    accumulate_cost_usd "0.500000"
    accumulate_cost_usd "0.250000"
    accumulate_cost_usd "not-a-number"
    accumulate_cost_usd ""
    [ "${USAGE_COST_USD}" = "0.750000" ]
}

@test "accumulate_cursor_usage_from_line records cache tokens and no cost" {
    local line='{"type":"result","usage":{"inputTokens":4841,"outputTokens":31,"cacheReadTokens":5888,"cacheWriteTokens":120},"model":"composer-2.5"}'
    accumulate_cursor_usage_from_line "${line}"
    [ "${USAGE_INPUT_TOTAL}" -eq 4841 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 31 ]
    [ "${USAGE_CACHE_READ_TOTAL}" -eq 5888 ]
    [ "${USAGE_CACHE_WRITE_TOTAL}" -eq 120 ]
    [ "${USAGE_COST_USD}" = "" ]
}

@test "build_usage_json reports cache and cost without folding them into totals" {
    local out
    USAGE_INPUT_TOTAL=4815
    USAGE_OUTPUT_TOTAL=14276
    USAGE_CACHE_READ_TOTAL=2107374
    USAGE_CACHE_WRITE_TOTAL=72780
    USAGE_COST_USD="0.865485"
    USAGE_MODEL="claude-sonnet-5"
    out="$(build_usage_json)"
    [ "$(jq -r '.total_input_tokens' <<< "${out}")" = "4815" ]
    [ "$(jq -r '.cache_read_tokens' <<< "${out}")" = "2107374" ]
    [ "$(jq -r '.cache_write_tokens' <<< "${out}")" = "72780" ]
    [ "$(jq -r '.cost_usd' <<< "${out}")" = "0.865485" ]
}

@test "build_usage_json omits cost when the engine reports none" {
    local out
    USAGE_INPUT_TOTAL=4841
    USAGE_OUTPUT_TOTAL=31
    USAGE_COST_USD=""
    out="$(build_usage_json)"
    [ "$(jq -r 'has("cost_usd")' <<< "${out}")" = "false" ]
}

@test "accumulate_claude_stream_usage reads model from system init" {
    local tmpf
    tmpf="$(mktemp)"
    printf '%s\n' \
        '{"type":"system","subtype":"init","model":"claude-sonnet-5"}' \
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"}]}}' \
        '{"type":"result","subtype":"success","usage":{"input_tokens":100,"output_tokens":20}}' \
        > "${tmpf}"
    accumulate_claude_stream_usage "${tmpf}"
    rm -f "${tmpf}"
    [ "${USAGE_INPUT_TOTAL}" -eq 100 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 20 ]
    [ "${USAGE_MODEL}" = "claude-sonnet-5" ]
}

@test "accumulate_claude_stream_usage ignores non-json lines" {
    local tmpf
    tmpf="$(mktemp)"
    printf '%s\n' \
        'npm warn something noisy' \
        '{"type":"result","usage":{"input_tokens":7,"output_tokens":3}}' \
        > "${tmpf}"
    accumulate_claude_stream_usage "${tmpf}"
    rm -f "${tmpf}"
    [ "${USAGE_INPUT_TOTAL}" -eq 7 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 3 ]
}

@test "render_claude_stream_log_summary prints final text and hides ndjson" {
    local tmpf out
    tmpf="$(mktemp)"
    printf '%s\n' \
        '{"type":"system","subtype":"init","model":"claude-sonnet-5"}' \
        '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}' \
        '{"type":"result","subtype":"success","num_turns":12,"duration_ms":4321,"result":"REASON: done","usage":{"input_tokens":5,"output_tokens":2}}' \
        > "${tmpf}"
    accumulate_claude_stream_usage "${tmpf}"
    out="$(render_claude_stream_log_summary "${tmpf}")"
    rm -f "${tmpf}"
    [[ ${out} == *"turns=12"* ]]
    [[ ${out} == *"tools=1"* ]]
    [[ ${out} == *"REASON: done"* ]]
    [[ ${out} != *'"type":"result"'* ]]
}

@test "run_claude_agent_with_usage captures usage and forwards exit code" {
    local out rc=0

    function claude {
        printf '%s\n' \
            '{"type":"system","subtype":"init","model":"claude-sonnet-5"}' \
            '{"type":"result","subtype":"success","num_turns":3,"result":"REASON: ok","usage":{"input_tokens":11,"output_tokens":4}}'
        return 0
    }
    # Redirect rather than command-substitute: a subshell would discard USAGE_*,
    # which is why run_agent_capture writes to a file.
    local out_file
    out_file="${BATS_TEST_TMPDIR}/claude-usage-out.txt"
    run_claude_agent_with_usage -p "prompt" > "${out_file}" || rc=$?
    out="$(cat "${out_file}")"
    [ "${rc}" -eq 0 ]
    [ "${USAGE_INPUT_TOTAL}" -eq 11 ]
    [ "${USAGE_OUTPUT_TOTAL}" -eq 4 ]
    [[ ${out} == *"REASON: ok"* ]]
}
