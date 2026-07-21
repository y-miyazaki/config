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

#######################################
# Global variables
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
# Globals:
#   USAGE_INPUT_TOTAL - Running total of input tokens
#   USAGE_OUTPUT_TOTAL - Running total of output tokens
#   USAGE_MODEL - Last known model name from the stream
#
# Arguments:
#   $1 - Path to captured stream-json output file
#
# Outputs:
#   None
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
# Globals:
#   USAGE_INPUT_TOTAL - Incremented when result usage is present
#   USAGE_OUTPUT_TOTAL - Incremented when result usage is present
#   USAGE_MODEL - Set from system init or result metadata
#
# Arguments:
#   $1 - Single NDJSON line from cursor stream-json output
#
# Outputs:
#   None
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
# Globals:
#   USAGE_INPUT_TOTAL - Total input tokens captured
#   USAGE_OUTPUT_TOTAL - Total output tokens captured
#   USAGE_MODEL - Model name when reported by the CLI
#
# Arguments:
#   None
#
# Outputs:
#   JSON object to stdout, or empty string when usage is unavailable
#
# Returns:
#   0 on success
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
# Globals:
#   USAGE_INPUT_TOTAL - Reset to 0
#   USAGE_OUTPUT_TOTAL - Reset to 0
#   USAGE_MODEL - Reset to empty string
#
# Arguments:
#   None
#
# Outputs:
#   None
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
# is_cursor_stream_json_file: Detect Cursor CLI stream-json capture files
#
# Globals:
#   None
#
# Arguments:
#   $1 - Path to candidate capture file
#
# Outputs:
#   None
#
# Returns:
#   0 when the file looks like NDJSON stream-json, 1 otherwise
#
#######################################
function is_cursor_stream_json_file {
    local stream_file="${1:?stream_file required}"
    local first_line event_type

    [[ -f ${stream_file} ]] || return 1
    first_line="$(grep -m1 '^{' "${stream_file}" 2> /dev/null || true)"
    [[ -n ${first_line} ]] || return 1
    event_type="$(jq -r '.type // empty' <<< "${first_line}" 2> /dev/null || true)"
    [[ ${event_type} =~ ^(system|assistant|tool_call|result|user)$ ]]
}

#######################################
# extract_cursor_stream_text: Reconstruct assistant text from stream-json
#
# Description:
#   Concatenates assistant message text and falls back to the terminal result
#   field so downstream parsers can read fenced JSON verdict blocks.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Path to stream-json capture file
#
# Outputs:
#   Extracted assistant text to stdout
#
# Returns:
#   0 on success
#
#######################################
function extract_cursor_stream_text {
    local stream_file="${1:?stream_file required}"
    local line event_type chunk assistant_text="" result_text=""

    [[ -f ${stream_file} ]] || return 0

    while IFS= read -r line || [[ -n ${line} ]]; do
        [[ -z ${line} || ${line} != \{* ]] && continue
        event_type="$(jq -r '.type // empty' <<< "${line}" 2> /dev/null || true)"
        case "${event_type}" in
            assistant)
                chunk="$(jq -r '
                  [.message.content[]? | select((.type // "text") == "text") | .text] | join("")
                ' <<< "${line}" 2> /dev/null || true)"
                if [[ -n ${chunk} ]]; then
                    assistant_text="${assistant_text}${chunk}"$'\n'
                fi
                ;;
            result)
                chunk="$(jq -r '.result // empty' <<< "${line}" 2> /dev/null || true)"
                if [[ -n ${chunk} ]]; then
                    result_text="${chunk}"
                fi
                ;;
        esac
    done < "${stream_file}"

    if [[ -n ${assistant_text} ]]; then
        printf '%s' "${assistant_text}"
    elif [[ -n ${result_text} ]]; then
        printf '%s' "${result_text}"
    fi
}

#######################################
# cursor_stream_tool_summary_line: Format one tool_call started event for logs
#
# Globals:
#   None
#
# Arguments:
#   $1 - Single NDJSON line
#
# Outputs:
#   One-line tool summary to stdout, or nothing when not a started tool call
#
# Returns:
#   0 on success
#
#######################################
function cursor_stream_tool_summary_line {
    local line="${1:?line required}"
    local subtype path command

    [[ ${line} == \{* ]] || return 1
    subtype="$(jq -r '.subtype // empty' <<< "${line}" 2> /dev/null || true)"
    [[ ${subtype} == "started" ]] || return 1

    if jq -e '.tool_call.readToolCall' > /dev/null 2>&1 <<< "${line}"; then
        path="$(jq -r '.tool_call.readToolCall.args.path // "unknown"' <<< "${line}")"
        printf '  read %s\n' "${path}"
        return 0
    fi
    if jq -e '.tool_call.writeToolCall' > /dev/null 2>&1 <<< "${line}"; then
        path="$(jq -r '.tool_call.writeToolCall.args.path // "unknown"' <<< "${line}")"
        printf '  write %s\n' "${path}"
        return 0
    fi
    if jq -e '.tool_call.grepToolCall' > /dev/null 2>&1 <<< "${line}"; then
        command="$(jq -r '.tool_call.grepToolCall.args.pattern // "pattern"' <<< "${line}")"
        printf '  grep %s\n' "${command}"
        return 0
    fi
    if jq -e '.tool_call.shellToolCall' > /dev/null 2>&1 <<< "${line}"; then
        command="$(jq -r '.tool_call.shellToolCall.args.command // "command"' <<< "${line}")"
        printf '  shell %s\n' "${command:0:120}"
        return 0
    fi
    if jq -e '.tool_call.runTerminalCommand' > /dev/null 2>&1 <<< "${line}"; then
        command="$(jq -r '.tool_call.runTerminalCommand.args.command // "command"' <<< "${line}")"
        printf '  shell %s\n' "${command:0:120}"
        return 0
    fi
    return 1
}

#######################################
# render_cursor_stream_log_summary: Print concise CI log for a stream-json capture
#
# Description:
#   Emits model, tool call summaries, token usage, and the extracted assistant
#   text so tee'd artifacts remain parseable by the verifier.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Path to stream-json capture file
#
# Outputs:
#   Human-readable summary to stdout
#
# Returns:
#   0 on success
#
#######################################
function render_cursor_stream_log_summary {
    local stream_file="${1:?stream_file required}"
    local line event_type model="" duration_ms="0"
    local tool_count=0 assistant_text="" tool_summary=""

    [[ -f ${stream_file} ]] || return 0

    while IFS= read -r line || [[ -n ${line} ]]; do
        [[ -z ${line} || ${line} != \{* ]] && continue
        event_type="$(jq -r '.type // empty' <<< "${line}" 2> /dev/null || true)"
        case "${event_type}" in
            system)
                if [[ -z ${model} ]]; then
                    model="$(jq -r '.model // empty' <<< "${line}" 2> /dev/null || true)"
                fi
                ;;
            tool_call)
                if summary_line="$(cursor_stream_tool_summary_line "${line}")"; then
                    tool_summary="${tool_summary}${summary_line}"
                    tool_count=$((tool_count + 1))
                fi
                ;;
            result)
                duration_ms="$(jq -r '.duration_ms // 0' <<< "${line}" 2> /dev/null || true)"
                ;;
        esac
    done < "${stream_file}"

    assistant_text="$(extract_cursor_stream_text "${stream_file}")"

    echo "Agent summary: model=${model:-unknown} tools=${tool_count} duration_ms=${duration_ms}"
    echo "Agent usage: input=${USAGE_INPUT_TOTAL} output=${USAGE_OUTPUT_TOTAL}"
    if [[ -n ${tool_summary} ]]; then
        printf '%s' "${tool_summary}"
    fi
    if [[ -n ${assistant_text} ]]; then
        echo ""
        printf '%s\n' "${assistant_text}"
    fi
}

#######################################
# run_cursor_agent_with_usage: Run Cursor CLI and capture stream-json usage
#
# Description:
#   Invokes the Cursor agent in headless stream-json mode, captures raw NDJSON
#   for usage accounting, and prints a concise summary for CI logs.
#
# Globals:
#   USAGE_INPUT_TOTAL, USAGE_OUTPUT_TOTAL, USAGE_MODEL - Updated after run
#
# Arguments:
#   $1 - Agent binary name (agent or cursor-agent)
#   $@ - Remaining arguments forwarded to the Cursor CLI
#
# Outputs:
#   None
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
    "${agent_bin}" "$@" > "${stream_file}" 2>&1 || rc=$?
    accumulate_cursor_stream_usage "${stream_file}"
    render_cursor_stream_log_summary "${stream_file}"
    rm -f "${stream_file}"
    return "${rc}"
}
