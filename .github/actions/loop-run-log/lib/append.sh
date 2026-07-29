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
#   $7  - Verifier verdict (optional)
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
    local run_id resolved_tokens

    run_id="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    resolved_tokens="$(loop_run_log_resolve_tokens_total "${usage_json}")"

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
        '{
      run_id: $run_id,
      loop_name: $loop_name,
      duration_s: $duration_s,
      outcome: $outcome,
      skip_reason: $skip_reason,
      tokens_total: $tokens_total,
      workflow_run: $workflow_run
    }
    + (if ($attempts | length) > 0 then {attempts: ($attempts | tonumber)} else {} end)
    + (if ($has_changes | length) > 0 then {has_changes: ($has_changes == "true")} else {} end)
    + (if ($verdict | length) > 0 then {verdict: $verdict} else {} end)
    + (if ($usage_json | length) > 0 then {usage: ($usage_json | fromjson)} else {} end)
    + (if ($agent_result | length) > 0 then {agent_result: $agent_result} else {} end)
    + (if ($failure_stage | length) > 0 then {failure_stage: $failure_stage} else {} end)
    + (if ($failure_message | length) > 0 then {failure_message: $failure_message} else {} end)'
}

#######################################
# loop_run_log_commit_and_push: Commit run log changes and push or open PR
#
# Description:
#   Commits the run log file when changed. Pushes directly when allowed; otherwise
#   opens a squash-merge PR against base_branch.
#
# Globals:
#   GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT - Used for PR metadata
#
# Arguments:
#   $1 - Base branch for PR fallback
#   $2 - Run log file path
#   $3 - GitHub token
#
# Outputs:
#   None
#
# Returns:
#   0 on success or when there are no changes to commit
#
#######################################
function loop_run_log_commit_and_push {
    local base_branch="${1:?base_branch required}"
    local run_log_file="${2:?run_log_file required}"
    local token="${3:?token required}"
    local log_branch pr_url

    export GH_TOKEN="${token}"
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GH_TOKEN}" | base64 -w0)"

    if git diff --quiet "${run_log_file}" 2> /dev/null && [[ -z "$(git status --porcelain "${run_log_file}")" ]]; then
        echo "No run log changes to commit."
        return 0
    fi

    git add "${run_log_file}"
    git commit -m "chore(loop): append run log [skip ci]"
    if git push origin HEAD 2> /dev/null; then
        echo "Run log pushed directly."
        return 0
    fi

    echo "Direct push blocked; opening run log PR."
    log_branch="loop/run-log-${GITHUB_RUN_ID:-0}-${GITHUB_RUN_ATTEMPT:-0}"
    git checkout -B "${log_branch}"
    git push origin "${log_branch}"
    pr_url="$(gh pr create \
        --repo "${GITHUB_REPOSITORY}" \
        --base "${base_branch}" \
        --head "${log_branch}" \
        --title "chore(loop): append run log [skip ci]" \
        --body "Automated loop run log append.")"
    if gh pr merge "${pr_url}" --auto --delete-branch --squash 2> /dev/null; then
        echo "Run log PR queued for auto-merge: ${pr_url}"
    elif gh pr merge "${pr_url}" --delete-branch --squash 2> /dev/null; then
        echo "Run log PR merged: ${pr_url}"
    else
        echo "::warning::Run log PR requires manual merge: ${pr_url}"
    fi
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
