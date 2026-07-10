#!/bin/bash
#######################################
# Description: Token usage capture for loop-execute engine sessions
#
# Usage: source "${SCRIPT_DIR}/lib/usage.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Cursor stream-json: sum terminal result events; model from system init
# - Measured usage is aggregated across implementer and verifier sessions
# - Other engines remain estimate-only until structured usage capture is added
#######################################

# Cumulative measured token totals across all agent sessions in one loop run
USAGE_INPUT_TOTAL=0
USAGE_OUTPUT_TOTAL=0
USAGE_MODEL=""

#######################################
# accumulate_cursor_stream_usage: Sum usage from a cursor stream-json capture file
#
# Description:
#   Reads NDJSON lines from a Cursor CLI --output-format stream-json capture.
#   Adds input/output token counts from terminal result events and records the
#   model name from system init or result metadata when present.
#
# Arguments:
#   $1 - Path to captured stream-json output file
#
# Global Variables:
#   USAGE_INPUT_TOTAL - Running total of input tokens
#   USAGE_OUTPUT_TOTAL - Running total of output tokens
#   USAGE_MODEL - Last known model name from the stream
#
# Returns:
#   None
#
#######################################
function accumulate_cursor_stream_usage {
    local stream_file="${1:?stream_file required}"
    local line

    [[ -f ${stream_file} ]] || return 0

    while IFS= read -r line || [[ -n ${line} ]]; do
        accumulate_cursor_usage_from_line "${line}"
    done < "${stream_file}"
}

#######################################
# accumulate_cursor_usage_from_line: Parse one stream-json line into usage totals
#
# Description:
#   Ignores non-JSON lines. Handles system init (model) and result (usage) events.
#   Accepts camelCase and snake_case usage field names from Cursor CLI versions.
#
# Arguments:
#   $1 - Single NDJSON line from cursor stream-json output
#
# Global Variables:
#   USAGE_INPUT_TOTAL - Incremented when result usage is present
#   USAGE_OUTPUT_TOTAL - Incremented when result usage is present
#   USAGE_MODEL - Set from system init or result metadata
#
# Returns:
#   None
#
#######################################
function accumulate_cursor_usage_from_line {
    local line="${1:?line required}"
    local event_type input output model

    [[ -z ${line} || ${line} != \{* ]] && return 0

    event_type="$(jq -r '.type // empty' <<< "${line}" 2> /dev/null || true)"
    if [[ ${event_type} == "system" ]]; then
        model="$(jq -r '.model // empty' <<< "${line}" 2> /dev/null || true)"
        if [[ -n ${model} && -z ${USAGE_MODEL} ]]; then
            USAGE_MODEL="${model}"
        fi
        return 0
    fi
    [[ ${event_type} == "result" ]] || return 0

    input="$(jq -r '
      (.usage.inputTokens // .usage.input_tokens // .usage.total_input_tokens // .usage.prompt_tokens // 0)
    ' <<< "${line}" 2> /dev/null || echo "0")"
    output="$(jq -r '
      (.usage.outputTokens // .usage.output_tokens // .usage.total_output_tokens // .usage.completion_tokens // 0)
    ' <<< "${line}" 2> /dev/null || echo "0")"
    model="$(jq -r '.model // .usage.model // empty' <<< "${line}" 2> /dev/null || true)"

    if [[ ${input} =~ ^[0-9]+$ ]]; then
        USAGE_INPUT_TOTAL=$((USAGE_INPUT_TOTAL + input))
    fi
    if [[ ${output} =~ ^[0-9]+$ ]]; then
        USAGE_OUTPUT_TOTAL=$((USAGE_OUTPUT_TOTAL + output))
    fi
    if [[ -n ${model} ]]; then
        USAGE_MODEL="${model}"
    fi
}

#######################################
# build_usage_json: Serialize accumulated usage for workflow outputs
#
# Description:
#   Emits a compact JSON object for loop-execute usage_json output and run log.
#   Returns an empty string when no measured tokens were captured.
#
# Arguments:
#   None
#
# Global Variables:
#   USAGE_INPUT_TOTAL - Total input tokens captured
#   USAGE_OUTPUT_TOTAL - Total output tokens captured
#   USAGE_MODEL - Model name when reported by the CLI
#
# Returns:
#   JSON object to stdout, or empty string when usage is unavailable
#
#######################################
function build_usage_json {
    if [[ ${USAGE_INPUT_TOTAL} -eq 0 && ${USAGE_OUTPUT_TOTAL} -eq 0 ]]; then
        printf ''
        return 0
    fi
    jq -nc \
        --argjson total_input_tokens "${USAGE_INPUT_TOTAL}" \
        --argjson total_output_tokens "${USAGE_OUTPUT_TOTAL}" \
        --arg model "${USAGE_MODEL}" \
        '{total_input_tokens: $total_input_tokens, total_output_tokens: $total_output_tokens}
         + (if ($model | length) > 0 then {model: $model} else {} end)'
}

#######################################
# reset_usage_totals: Clear accumulated usage counters
#
# Description:
#   Resets module globals at the start of each loop-execute run.
#
# Arguments:
#   None
#
# Global Variables:
#   USAGE_INPUT_TOTAL - Reset to 0
#   USAGE_OUTPUT_TOTAL - Reset to 0
#   USAGE_MODEL - Reset to empty string
#
# Returns:
#   None
#
#######################################
function reset_usage_totals {
    USAGE_INPUT_TOTAL=0
    USAGE_OUTPUT_TOTAL=0
    USAGE_MODEL=""
}

#######################################
# run_cursor_agent_with_usage: Run Cursor CLI and capture stream-json usage
#
# Description:
#   Invokes the Cursor agent in headless stream-json mode, tees output for
#   attempt logs, and feeds the capture file into accumulate_cursor_stream_usage.
#
# Arguments:
#   $1 - Agent binary name (agent or cursor-agent)
#   $@ - Remaining arguments forwarded to the Cursor CLI
#
# Global Variables:
#   USAGE_INPUT_TOTAL, USAGE_OUTPUT_TOTAL, USAGE_MODEL - Updated after run
#
# Returns:
#   Cursor CLI exit code
#
#######################################
function run_cursor_agent_with_usage {
    local agent_bin="${1:?agent_bin required}"
    shift
    local stream_file rc=0

    stream_file="$(mktemp)"
    "${agent_bin}" "$@" 2>&1 | tee "${stream_file}" || rc=$?
    accumulate_cursor_stream_usage "${stream_file}"
    rm -f "${stream_file}"
    return "${rc}"
}
