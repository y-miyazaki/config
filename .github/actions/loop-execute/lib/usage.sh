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
# - Measured usage is aggregated across maker and checker sessions
# - Other engines remain estimate-only until structured usage capture is added
#######################################

#######################################
# Global variables
#######################################
# Cumulative measured token totals across all agent sessions in one loop run
USAGE_INPUT_TOTAL=0
USAGE_OUTPUT_TOTAL=0
USAGE_CACHE_READ_TOTAL=0
USAGE_CACHE_WRITE_TOTAL=0
USAGE_COST_USD=""
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
    local event_type input output cache_read cache_write model

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
    cache_read="$(jq -r '
      (.usage.cacheReadTokens // .usage.cache_read_tokens // 0)
    ' <<< "${line}" 2> /dev/null || echo "0")"
    cache_write="$(jq -r '
      (.usage.cacheWriteTokens // .usage.cache_write_tokens // 0)
    ' <<< "${line}" 2> /dev/null || echo "0")"
    model="$(jq -r '.model // .usage.model // empty' <<< "${line}" 2> /dev/null || true)"

    if [[ ${input} =~ ^[0-9]+$ ]]; then
        USAGE_INPUT_TOTAL=$((USAGE_INPUT_TOTAL + input))
    fi
    if [[ ${output} =~ ^[0-9]+$ ]]; then
        USAGE_OUTPUT_TOTAL=$((USAGE_OUTPUT_TOTAL + output))
    fi
    if [[ ${cache_read} =~ ^[0-9]+$ ]]; then
        USAGE_CACHE_READ_TOTAL=$((USAGE_CACHE_READ_TOTAL + cache_read))
    fi
    if [[ ${cache_write} =~ ^[0-9]+$ ]]; then
        USAGE_CACHE_WRITE_TOTAL=$((USAGE_CACHE_WRITE_TOTAL + cache_write))
    fi
    # Cursor reports no cost field at all, so USAGE_COST_USD stays empty and
    # the budget guard falls back to tokens for this engine.
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
    # Cache counts are reported for visibility but deliberately left out of the
    # token totals: a cache read is billed at a fraction of a fresh input token,
    # and that fraction is a pricing decision that changes without notice, so
    # folding it in with a hardcoded weight would be wrong by an unknown factor.
    # cost_usd is the figure to budget against wherever the engine reports one.
    jq -nc \
        --argjson total_input_tokens "${USAGE_INPUT_TOTAL}" \
        --argjson total_output_tokens "${USAGE_OUTPUT_TOTAL}" \
        --argjson cache_read_tokens "${USAGE_CACHE_READ_TOTAL}" \
        --argjson cache_write_tokens "${USAGE_CACHE_WRITE_TOTAL}" \
        --arg cost_usd "${USAGE_COST_USD}" \
        --arg model "${USAGE_MODEL}" \
        '{total_input_tokens: $total_input_tokens, total_output_tokens: $total_output_tokens,
          cache_read_tokens: $cache_read_tokens, cache_write_tokens: $cache_write_tokens}
         + (if ($cost_usd | length) > 0 then {cost_usd: ($cost_usd | tonumber)} else {} end)
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
    USAGE_CACHE_READ_TOTAL=0
    USAGE_CACHE_WRITE_TOTAL=0
    USAGE_COST_USD=""
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
#   text so tee'd artifacts remain parseable by the checker.
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
    echo "Agent usage: input=${USAGE_INPUT_TOTAL} output=${USAGE_OUTPUT_TOTAL}" \
        "cache_read=${USAGE_CACHE_READ_TOTAL} cache_write=${USAGE_CACHE_WRITE_TOTAL}" \
        "cost_usd=${USAGE_COST_USD:-unreported}"
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

#######################################
# accumulate_claude_stream_usage: Sum usage from a claude stream-json capture file
#
# Description:
#   Claude Code emits one NDJSON event per line in stream-json mode and reports
#   token usage once, on the terminal result event. Cache creation and cache
#   read tokens are counted as input because they are tokens the run actually
#   pushed through the model; agentic loops spend most of their input budget
#   there, so omitting them would under-report a run by an order of magnitude.
#
# Globals:
#   USAGE_INPUT_TOTAL - Running total of input tokens
#   USAGE_OUTPUT_TOTAL - Running total of output tokens
#   USAGE_MODEL - Model name reported by the CLI
#
# Arguments:
#   $1 - Path to the captured NDJSON stream file
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function accumulate_claude_stream_usage {
    local stream_file="${1:?stream_file required}"
    local line

    [[ -f ${stream_file} ]] || return 0

    while IFS= read -r line || [[ -n ${line} ]]; do
        accumulate_claude_usage_from_line "${line}"
    done < "${stream_file}"
}

#######################################
# accumulate_claude_usage_from_line: Fold one claude stream-json line into totals
#
# Description:
#   Ignores non-JSON lines. Reads the model from the system init event and the
#   token counts from the result event.
#
# Globals:
#   USAGE_INPUT_TOTAL - Incremented when result usage is present
#   USAGE_OUTPUT_TOTAL - Incremented when result usage is present
#   USAGE_MODEL - Set from system init or result metadata
#
# Arguments:
#   $1 - Single NDJSON line from claude stream-json output
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function accumulate_claude_usage_from_line {
    local line="${1:?line required}"
    local event_type input output cache_write cache_read cost model

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

    input="$(jq -r '(.usage.input_tokens // 0)' <<< "${line}" 2> /dev/null || echo "0")"
    output="$(jq -r '(.usage.output_tokens // 0)' <<< "${line}" 2> /dev/null || echo "0")"
    cache_write="$(jq -r '(.usage.cache_creation_input_tokens // 0)' <<< "${line}" 2> /dev/null || echo "0")"
    cache_read="$(jq -r '(.usage.cache_read_input_tokens // 0)' <<< "${line}" 2> /dev/null || echo "0")"
    cost="$(jq -r '(.total_cost_usd // empty)' <<< "${line}" 2> /dev/null || true)"
    model="$(jq -r '(.modelUsage // {} | keys | first) // empty' <<< "${line}" 2> /dev/null || true)"

    if [[ ${input} =~ ^[0-9]+$ ]]; then
        USAGE_INPUT_TOTAL=$((USAGE_INPUT_TOTAL + input))
    fi
    if [[ ${output} =~ ^[0-9]+$ ]]; then
        USAGE_OUTPUT_TOTAL=$((USAGE_OUTPUT_TOTAL + output))
    fi
    if [[ ${cache_write} =~ ^[0-9]+$ ]]; then
        USAGE_CACHE_WRITE_TOTAL=$((USAGE_CACHE_WRITE_TOTAL + cache_write))
    fi
    if [[ ${cache_read} =~ ^[0-9]+$ ]]; then
        USAGE_CACHE_READ_TOTAL=$((USAGE_CACHE_READ_TOTAL + cache_read))
    fi
    accumulate_cost_usd "${cost}"
    if [[ -n ${model} ]]; then
        USAGE_MODEL="${model}"
    fi
}

#######################################
# accumulate_cost_usd: Add one engine-reported cost figure to the run total
#
# Description:
#   Cost arrives as a decimal, so the running total is kept in awk rather than
#   bash integer arithmetic. Engines that report no cost leave the total empty,
#   which is what tells the budget guard to fall back to token counting.
#
# Globals:
#   USAGE_COST_USD - Running cost total, empty when no engine reported one
#
# Arguments:
#   $1 - Cost for this session as reported by the CLI, may be empty
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function accumulate_cost_usd {
    local cost="${1:-}"

    [[ -z ${cost} ]] && return 0
    [[ ${cost} =~ ^[0-9]+([.][0-9]+)?$ ]] || return 0
    USAGE_COST_USD="$(awk -v a="${USAGE_COST_USD:-0}" -v b="${cost}" 'BEGIN { printf "%.6f", a + b }')"
}

#######################################
# render_claude_stream_log_summary: Print claude run summary and final text
#
# Description:
#   Replaces the plain text that --bare used to put on stdout. The final result
#   text must still reach stdout verbatim because the loop parses the agent
#   report out of it.
#
# Globals:
#   USAGE_INPUT_TOTAL - Input token total for the summary line
#   USAGE_OUTPUT_TOTAL - Output token total for the summary line
#   USAGE_MODEL - Model name for the summary line
#
# Arguments:
#   $1 - Path to the captured NDJSON stream file
#
# Outputs:
#   Summary line, usage line, then the agent's final text
#
# Returns:
#   0 on success
#
#######################################
function render_claude_stream_log_summary {
    local stream_file="${1:?stream_file required}"
    local tool_count duration_ms num_turns result_text

    [[ -f ${stream_file} ]] || return 0

    # fromjson? per line, not slurp: the CLI interleaves plain warning lines and
    # a slurped parse would abort on the first one, zeroing every field.
    tool_count="$(jq -rR 'fromjson? | select(.type == "assistant")
        | .message.content[]? | select(.type == "tool_use") | .name' \
        "${stream_file}" 2> /dev/null | wc -l | tr -d ' ')"
    duration_ms="$(jq -rR 'fromjson? | select(.type == "result") | .duration_ms // 0' \
        "${stream_file}" 2> /dev/null | tail -1)"
    num_turns="$(jq -rR 'fromjson? | select(.type == "result") | .num_turns // 0' \
        "${stream_file}" 2> /dev/null | tail -1)"

    echo "Agent summary: model=${USAGE_MODEL:-unknown} tools=${tool_count:-0} turns=${num_turns:-0} duration_ms=${duration_ms:-0}"
    echo "Agent usage: input=${USAGE_INPUT_TOTAL} output=${USAGE_OUTPUT_TOTAL}" \
        "cache_read=${USAGE_CACHE_READ_TOTAL} cache_write=${USAGE_CACHE_WRITE_TOTAL}" \
        "cost_usd=${USAGE_COST_USD:-unreported}"

    result_text="$(jq -rR 'fromjson? | select(.type == "result") | .result // empty' \
        "${stream_file}" 2> /dev/null || true)"
    if [[ -n ${result_text} ]]; then
        echo ""
        printf '%s\n' "${result_text}"
    fi
}

#######################################
# run_claude_agent_with_usage: Run Claude Code CLI and capture stream-json usage
#
# Description:
#   Invokes the CLI in stream-json mode, captures raw NDJSON for usage
#   accounting, then prints the summary and the agent's final text so the
#   downstream report parser sees the same stdout --bare used to produce.
#
# Globals:
#   USAGE_INPUT_TOTAL, USAGE_OUTPUT_TOTAL, USAGE_MODEL - Updated after run
#
# Arguments:
#   $@ - Arguments forwarded to the claude CLI
#
# Outputs:
#   Summary, usage, and the agent's final text on stdout
#
# Returns:
#   Claude CLI exit code
#
#######################################
function run_claude_agent_with_usage {
    local stream_file rc=0

    stream_file="$(mktemp)"
    claude "$@" > "${stream_file}" 2>&1 || rc=$?
    accumulate_claude_stream_usage "${stream_file}"
    render_claude_stream_log_summary "${stream_file}"
    rm -f "${stream_file}"
    return "${rc}"
}
