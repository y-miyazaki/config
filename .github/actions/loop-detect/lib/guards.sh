#!/bin/bash
#######################################
# Description: Guard helpers for loop-detect (budget, circuit breaker)
#
# Usage: source "${LIB_DIR}/guards.sh"
#
# Output:
# - None (library file)
#
# Design Rules:
# - Budget reads loop-budget.json and loop-run-log.md for daily aggregation
#######################################

#######################################
# budget_exceeded: Return 0 when daily budget is exceeded
#
# Arguments:
#   $1 - Loop name
#   $2 - Budget file path
#   $3 - Run log file path
#   $4 - Default max runs per day
#   $5 - Default max tokens per day
#
# Globals:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 when budget exceeded, 1 otherwise
#
#######################################
function budget_exceeded {
    local loop_name="$1"
    local budget_file="$2"
    local run_log_file="$3"
    local default_runs="$4"
    local default_tokens="$5"
    local max_runs max_tokens today runs_today tokens_today line

    read -r max_runs max_tokens <<< "$(read_budget_limits "${loop_name}" "${budget_file}" "${default_runs}" "${default_tokens}")"
    if [[ -z ${max_runs} && -z ${max_tokens} ]]; then
        return 1
    fi

    today=$(date -u +%Y-%m-%d)
    runs_today=0
    tokens_today=0
    if [[ -f ${run_log_file} ]]; then
        while IFS= read -r line; do
            [[ -z ${line} ]] && continue
            [[ ${line} != \{* ]] && continue
            local log_date log_pattern entry_tokens
            log_date=$(jq -r '.run_id // ""' <<< "${line}" 2> /dev/null | cut -c1-10)
            log_pattern=$(jq -r '.pattern // ""' <<< "${line}" 2> /dev/null)
            [[ ${log_date} != "${today}" ]] && continue
            [[ ${log_pattern} != "${loop_name}" ]] && continue
            runs_today=$((runs_today + 1))
            entry_tokens=$(jq -r '
                if .usage then
                    ((.usage.total_input_tokens // .usage.input_tokens // .usage.inputTokens // 0)
                     + (.usage.total_output_tokens // .usage.output_tokens // .usage.outputTokens // 0))
                elif .tokens_estimate then
                    .tokens_estimate
                else
                    0
                end
            ' <<< "${line}" 2> /dev/null || echo "0")
            tokens_today=$((tokens_today + entry_tokens))
        done < <(grep -E '^\{' "${run_log_file}" 2> /dev/null || true)
    fi

    if [[ -n ${max_runs} && ${runs_today} -ge ${max_runs} ]]; then
        echo "::warning::Daily run budget exceeded for ${loop_name} (${runs_today}/${max_runs})"
        return 0
    fi
    if [[ -n ${max_tokens} && ${tokens_today} -ge ${max_tokens} ]]; then
        echo "::warning::Daily token budget exceeded for ${loop_name} (${tokens_today}/${max_tokens})"
        return 0
    fi
    return 1
}

#######################################
# read_budget_limits: Echo max_runs and max_tokens for loop name
#
# Arguments:
#   $1 - Loop name
#   $2 - Budget file path
#   $3 - Default max runs
#   $4 - Default max tokens
#
# Globals:
#   None
#
# Outputs:
#   "max_runs max_tokens" on stdout
#
# Returns:
#   0 on success
#
#######################################
function read_budget_limits {
    local loop_name="$1"
    local budget_file="$2"
    local default_runs="$3"
    local default_tokens="$4"
    local max_runs="" max_tokens=""

    if [[ -f ${budget_file} ]]; then
        max_runs=$(jq -r --arg loop "${loop_name}" '.loops[$loop].max_runs_per_day // empty' "${budget_file}" 2> /dev/null || true)
        max_tokens=$(jq -r --arg loop "${loop_name}" '.loops[$loop].max_tokens_per_day // empty' "${budget_file}" 2> /dev/null || true)
    fi
    max_runs="${max_runs:-${default_runs}}"
    max_tokens="${max_tokens:-${default_tokens}}"
    printf '%s %s' "${max_runs}" "${max_tokens}"
}

#######################################
# target_circuit_breaker_open: Return 0 when consecutive_failures >= 3
#
# Arguments:
#   $1 - Consecutive failure count
#
# Globals:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 when circuit breaker is open, 1 otherwise
#
#######################################
function target_circuit_breaker_open {
    local consecutive="$1"
    [[ ${consecutive} -ge 3 ]]
}
