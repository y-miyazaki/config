#!/bin/bash
#######################################
# Description: Append JSONL entries to the loop run log and commit to base branch
#
# Usage: source "${GITHUB_ACTION_PATH}/lib/append.sh"
#
# Output:
# - Rewrites run log markdown with pruned JSONL entries plus one new entry
#
# Design Rules:
# - Prune entries older than 30 days on each append
# - tokens_total is measured usage sum or 0 when execute did not run
# - Budget aggregation reads tokens_total from run log entries
# - Push races are resolved by re-appending onto the refreshed base branch, never by
#   opening a pull request: the log file is rewritten whole, so two open log PRs
#   always conflict, and a bot cannot satisfy the review the base branch requires
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
RUN_LOG_HEADER='# Loop Run Log

Append one entry per run. Prune entries older than 30 days.

## Recent Runs

<!-- Loop appends below this line -->

'

#######################################
# loop_run_log_append_entry: Prune old entries and append one JSONL line
#
# Description:
#   Reads existing JSONL lines, drops entries older than 30 days, and writes the
#   markdown header plus kept lines plus the new entry_json.
#
# Globals:
#   RUN_LOG_HEADER - Markdown header prepended on each rewrite
#
# Arguments:
#   $1 - Run log file path
#   $2 - JSON log entry to append
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function loop_run_log_append_entry {
    local run_log_file="${1:?run_log_file required}"
    local entry_json="${2:?entry_json required}"
    local cutoff tmp_dir kept_lines

    cutoff="$(loop_run_log_prune_cutoff_date)"
    tmp_dir="$(mktemp -d)"
    kept_lines="${tmp_dir}/kept.jsonl"

    : > "${kept_lines}"
    if [[ -f ${run_log_file} ]]; then
        while IFS= read -r line || [[ -n ${line} ]]; do
            [[ -z ${line} ]] && continue
            [[ ${line} != \{* ]] && continue
            log_date="$(jq -r '.run_id // ""' <<< "${line}" 2> /dev/null | cut -c1-10)"
            [[ -z ${log_date} ]] && continue
            [[ ${log_date} < ${cutoff} ]] && continue
            printf '%s\n' "${line}" >> "${kept_lines}"
        done < "${run_log_file}"
    fi

    mkdir -p "$(dirname "${run_log_file}")"
    {
        printf '%s' "${RUN_LOG_HEADER}"
        cat "${kept_lines}"
        printf '%s\n' "${entry_json}"
    } > "${run_log_file}"

    rm -rf "${tmp_dir}"
}

#######################################
# loop_run_log_resolve_tokens_total: Sum measured usage tokens or return zero
#
# Globals:
#   None
#
# Arguments:
#   $1 - Measured usage JSON (optional)
#
# Outputs:
#   Token count to stdout
#
# Returns:
#   0 on success
#
#######################################
function loop_run_log_resolve_tokens_total {
    local usage_json="${1:-}"

    if [[ -n ${usage_json} ]] && jq -e . > /dev/null 2>&1 <<< "${usage_json}"; then
        jq -r '
            ((.total_input_tokens // .input_tokens // .inputTokens // 0)
             + (.total_output_tokens // .output_tokens // .outputTokens // 0))
        ' <<< "${usage_json}"
        return 0
    fi
    printf '0'
}

#######################################
# loop_run_log_resolve_cost_usd: Echo engine-reported cost or an empty string
#
# Description:
#   Only engines that report their own cost produce this field. Cursor reports
#   token counts with no cost, so its entries carry none and the budget guard
#   falls back to tokens for that engine.
#
# Globals:
#   None
#
# Arguments:
#   $1 - usage_json from loop-execute, may be empty
#
# Outputs:
#   Cost as a decimal string, or an empty string when unavailable
#
# Returns:
#   0 on success
#
#######################################
function loop_run_log_resolve_cost_usd {
    local usage_json="${1:-}"

    if [[ -n ${usage_json} ]] && jq -e . > /dev/null 2>&1 <<< "${usage_json}"; then
        jq -r '(.cost_usd // empty) | tostring' <<< "${usage_json}"
        return 0
    fi
    printf ''
}

#######################################
# loop_run_log_build_entry: Build one run log JSON object
#
# Description:
#   Assembles the JSONL entry for a single loop run. tokens_total is measured usage
#   or zero when execute did not run.
#
# Globals:
#   None
#
# Arguments:
#   $1  - Attempt count (empty when execute did not run)
#   $2  - Duration in seconds
#   $3  - has_changes flag (true/false, empty when execute did not run)
#   $4  - Loop name (loop_name)
#   $5  - Outcome
#   $6  - Skip reason
#   $7  - Checker verdict (optional)
#   $8  - Workflow run id
#   $9  - Measured usage JSON (optional)
#   $10 - agent_result (optional)
#   $11 - failure_stage (optional)
#   $12 - failure_message (optional)
#
# Outputs:
#   JSON object to stdout
#
# Returns:
#   0 on success
#
#######################################
function loop_run_log_build_entry {
    local attempts="${1-}"
    local duration_s="${2:?duration_s required}"
    local has_changes="${3-}"
    local loop_name="${4:?loop_name required}"
    local outcome="${5:?outcome required}"
    local skip_reason="${6:?skip_reason required}"
    local verdict="${7:-}"
    local workflow_run="${8:?workflow_run required}"
    local usage_json="${9:-}"
    local agent_result="${10:-}"
    local failure_stage="${11:-}"
    local failure_message="${12:-}"
    local run_id resolved_tokens resolved_cost

    run_id="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    resolved_tokens="$(loop_run_log_resolve_tokens_total "${usage_json}")"
    resolved_cost="$(loop_run_log_resolve_cost_usd "${usage_json}")"

    jq -nc \
        --arg run_id "${run_id}" \
        --arg loop_name "${loop_name}" \
        --argjson duration_s "${duration_s}" \
        --arg outcome "${outcome}" \
        --arg skip_reason "${skip_reason}" \
        --argjson tokens_total "${resolved_tokens}" \
        --arg workflow_run "${workflow_run}" \
        --arg attempts "${attempts}" \
        --arg has_changes "${has_changes}" \
        --arg verdict "${verdict}" \
        --arg usage_json "${usage_json}" \
        --arg agent_result "${agent_result}" \
        --arg failure_stage "${failure_stage}" \
        --arg failure_message "${failure_message}" \
        --arg cost_usd "${resolved_cost}" \
        '{
      run_id: $run_id,
      loop_name: $loop_name,
      duration_s: $duration_s,
      outcome: $outcome,
      skip_reason: $skip_reason,
      tokens_total: $tokens_total,
      workflow_run: $workflow_run
    }
    + (if ($cost_usd | length) > 0 then {cost_usd: ($cost_usd | tonumber)} else {} end)
    + (if ($attempts | length) > 0 then {attempts: ($attempts | tonumber)} else {} end)
    + (if ($has_changes | length) > 0 then {has_changes: ($has_changes == "true")} else {} end)
    + (if ($verdict | length) > 0 then {verdict: $verdict} else {} end)
    + (if ($usage_json | length) > 0 then {usage: ($usage_json | fromjson)} else {} end)
    + (if ($agent_result | length) > 0 then {agent_result: $agent_result} else {} end)
    + (if ($failure_stage | length) > 0 then {failure_stage: $failure_stage} else {} end)
    + (if ($failure_message | length) > 0 then {failure_message: $failure_message} else {} end)'
}

#######################################
# loop_run_log_commit_and_push: Commit the run log entry and push to the base branch
#
# Description:
#   Commits the run log file when changed and pushes it to base_branch. A push that
#   loses a race against a concurrent run is retried after re-fetching base_branch,
#   restoring the run log from it, and appending the entry again, so a retry never
#   carries a stale whole-file rewrite into the push.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Base branch to push to
#   $2 - Run log file path
#   $3 - GitHub token
#   $4 - JSON entry, re-appended on the refreshed file when a push is retried
#
# Outputs:
#   Push progress on stdout; a workflow warning when every attempt fails
#
# Returns:
#   0 on success, when there are no changes, and when the entry is given up on
#
#######################################
function loop_run_log_commit_and_push {
    local base_branch="${1:?base_branch required}"
    local run_log_file="${2:?run_log_file required}"
    local token="${3:?token required}"
    local entry_json="${4:?entry_json required}"
    local attempt push_error=""

    export GITHUB_TOKEN="${token}"
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GITHUB_TOKEN}" | base64 -w0)"

    for attempt in 1 2 3; do
        if [[ -z "$(git status --porcelain "${run_log_file}")" ]]; then
            echo "No run log changes to commit."
            return 0
        fi

        git add "${run_log_file}"
        git commit -m "chore(loop): append run log [skip ci]"
        if push_error="$(git push origin "HEAD:${base_branch}" 2>&1)"; then
            echo "Run log pushed to ${base_branch} on attempt ${attempt}."
            return 0
        fi
        echo "Run log push attempt ${attempt} failed: ${push_error}"

        git fetch origin "${base_branch}"
        git reset --mixed "origin/${base_branch}"
        git checkout "origin/${base_branch}" -- "${run_log_file}" 2> /dev/null || rm -f "${run_log_file}"
        loop_run_log_append_entry "${run_log_file}" "${entry_json}"
    done

    echo "::warning::Run log entry dropped after 3 push attempts: ${push_error}"
    return 0
}

#######################################
# loop_run_log_compute_duration: Compute run duration from ISO start timestamp
#
# Globals:
#   None
#
# Arguments:
#   $1 - Run start timestamp (ISO 8601, empty returns 0)
#
# Outputs:
#   Elapsed seconds to stdout
#
# Returns:
#   0 on success
#
#######################################
function loop_run_log_compute_duration {
    local run_started_at="${1:-}"
    local started_epoch now_epoch

    if [[ -z ${run_started_at} ]]; then
        echo "0"
        return 0
    fi
    started_epoch="$(date -d "${run_started_at}" +%s 2> /dev/null || echo "0")"
    now_epoch="$(date -u +%s)"
    if [[ ${started_epoch} -eq 0 ]]; then
        echo "0"
        return 0
    fi
    echo $((now_epoch - started_epoch))
}

#######################################
# loop_run_log_prune_cutoff_date: Return UTC date string for 30-day prune window
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   YYYY-MM-DD cutoff date to stdout
#
# Returns:
#   0 on success
#
#######################################
function loop_run_log_prune_cutoff_date {
    date -u -d '30 days ago' +%Y-%m-%d 2> /dev/null || date -u -v-30d +%Y-%m-%d
}
