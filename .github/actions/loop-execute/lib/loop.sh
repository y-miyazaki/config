#!/bin/bash
#######################################
# Description: Run the bounded Agent→Verify loop for loop-execute
#
# Usage: bash lib/loop.sh
#
# Environment:
#   Required env vars are injected by action.yml (AGENT_*, PROMPT_*, WORKTREE_PATH, etc.)
#
# Output:
#   Writes verdict, attempts, has_changes, reason, open_rejections to GITHUB_OUTPUT
#
# Design Rules:
#   - Implementer and verifier run as separate agent sessions per attempt
#   - Path guards run before the LLM verifier
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_init.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_init.sh"

#######################################
# Global variables
#######################################
ATTEMPT=0
VERDICT="REJECT"
REASON="No attempts completed"
HAS_CHANGES="false"
OPEN_REJECTIONS_JSON='[]'
REJECT_FEEDBACK=""
OUTCOME_OVERRIDE=""

#######################################
# initialize_loop_state: Prepare status directory and prompt defaults
#
# Arguments:
#   None
#
# Global Variables:
#   STATUS_DIR - Caller env directory for attempt artifacts (read)
#
# Returns:
#   None
#
#######################################
function initialize_loop_state {
    mkdir -p "${STATUS_DIR}"
    normalize_no_changes_verdict
    load_default_prompts
    reset_usage_totals
}

#######################################
# parse_outcome_override_from_agent_output: Detect Skill watch outcome from implementer text
#
# Arguments:
#   $1 - Implementer agent output text
#
# Global Variables:
#   None
#
# Returns:
#   0 when outcome_override should be watch, 1 otherwise
#
#######################################
function parse_outcome_override_from_agent_output {
    local agent_out="$1"
    if grep -qiE '^\*\*Outcome:\*\*[[:space:]]*(watch|deferred|no actionable|escalat)' <<< "${agent_out}"; then
        return 0
    fi
    if grep -qiE '^[[:space:]]*Outcome:[[:space:]]*(watch|deferred|no actionable|escalat)' <<< "${agent_out}"; then
        return 0
    fi
    return 1
}

#######################################
# write_loop_outputs: Write step outputs to GITHUB_OUTPUT
#
# Arguments:
#   None
#
# Global Variables:
#   ATTEMPT - Final attempt count (read)
#   GITHUB_OUTPUT - GitHub Actions output file path (read)
#   HAS_CHANGES - Whether commits were produced (read)
#   OPEN_REJECTIONS_JSON - Open rejection array JSON (read)
#   OUTCOME_OVERRIDE - Skill watch override when set (read)
#   REASON - Final verdict reason (read)
#   VERDICT - Final loop verdict (read)
#
# Returns:
#   None
#
#######################################
function write_loop_outputs {
    local delim usage_json
    usage_json="$(build_usage_json)"
    {
        echo "verdict=${VERDICT}"
        echo "attempts=${ATTEMPT}"
        echo "has_changes=${HAS_CHANGES}"
        delim="REASON_$(openssl rand -hex 8)"
        echo "reason<<${delim}"
        echo "${REASON}"
        echo "${delim}"
        delim="OPEN_REJECTIONS_$(openssl rand -hex 8)"
        echo "open_rejections<<${delim}"
        echo "${OPEN_REJECTIONS_JSON}"
        echo "${delim}"
        if [[ -n ${usage_json} ]]; then
            delim="USAGE_JSON_$(openssl rand -hex 8)"
            echo "usage_json<<${delim}"
            echo "${usage_json}"
            echo "${delim}"
        else
            echo "usage_json="
        fi
        echo "outcome_override=${OUTCOME_OVERRIDE}"
    } >> "${GITHUB_OUTPUT}"
    echo "Final: verdict=${VERDICT} attempts=${ATTEMPT} has_changes=${HAS_CHANGES}"
    if [[ ${VERDICT} == "REJECT" && "$(jq 'length' <<< "${OPEN_REJECTIONS_JSON}")" -gt 0 ]]; then
        echo "::group::Open rejection history"
        format_open_rejections_for_prompt
        echo "::endgroup::"
    fi
}

#######################################
# run_bounded_loop: Execute implementer→verifier attempts until APPROVE or max attempts
#
# Arguments:
#   None
#
# Global Variables:
#   ATTEMPT - Current attempt counter (read/write)
#   HAS_CHANGES - Whether commits were produced (read/write)
#   OPEN_REJECTIONS_JSON - Open rejection array JSON (read/write)
#   OUTCOME_OVERRIDE - Skill watch override when set (write)
#   REASON - Verdict reason for current attempt (read/write)
#   REJECT_FEEDBACK - Verifier feedback for retry prompt (read)
#   VERDICT - Loop verdict for current attempt (read/write)
#
# Returns:
#   None
#
#######################################
function run_bounded_loop {
    local attempt_dir agent_prompt attempt_committed

    while [[ ${ATTEMPT} -lt ${AGENT_LOOP_MAX_ATTEMPTS} ]]; do
        ATTEMPT=$((ATTEMPT + 1))
        echo "::group::Loop attempt ${ATTEMPT}/${AGENT_LOOP_MAX_ATTEMPTS}"
        attempt_dir="${STATUS_DIR}/attempt-${ATTEMPT}"
        mkdir -p "${attempt_dir}"
        attempt_committed="false"
        sync_reject_feedback

        agent_prompt="$(build_agent_prompt "${REJECT_FEEDBACK}")"
        printf '%s\n' "${agent_prompt}" > "${attempt_dir}/agent-prompt.txt"
        if [[ -n ${REJECT_FEEDBACK} ]]; then
            echo "::group::Verifier feedback injected for attempt ${ATTEMPT}"
            printf '%s\n' "${REJECT_FEEDBACK}"
            echo "::endgroup::"
        fi

        PROMPT="${agent_prompt}"
        MAX_TURNS="${AGENT_IMPLEMENTER_MAX_TURNS}"
        MODEL="${AGENT_IMPLEMENTER_MODEL}"
        WORKING_DIRECTORY="${WORKTREE_PATH}"
        export PROMPT MAX_TURNS MODEL WORKING_DIRECTORY

        echo "Running implementer agent (fresh session)..."
        if ! run_agent_capture "${attempt_dir}/agent-output.txt" "true"; then
            echo "::warning::Implementer agent exited non-zero on attempt ${ATTEMPT}"
        fi

        if commit_worktree_if_needed "${COMMIT_MESSAGE} (attempt ${ATTEMPT})"; then
            HAS_CHANGES="true"
            attempt_committed="true"
        elif [[ ${ATTEMPT} -gt 1 && -n ${REJECT_FEEDBACK} ]]; then
            local branch_changed_files branch_violations
            branch_changed_files="$(
                cd "${WORKTREE_PATH}" || exit 1
                git diff --name-only "origin/${BASE_BRANCH}...HEAD" -- . ':!.loop/' || true
            )"
            branch_violations="$(collect_denylist_violations "${branch_changed_files}")"
            if [[ -z ${branch_violations} ]]; then
                branch_violations="$(collect_allowlist_violations "${branch_changed_files}")"
            fi
            if [[ -n ${branch_violations} ]]; then
                echo "::error::Attempt ${ATTEMPT} produced no file changes while open rejections remain"
                record_structured_reject "${attempt_dir}" "${ATTEMPT}" "" \
                    "Implementer produced no file changes on retry" \
                    "Edit the files listed in prior open rejections and commit the fixes" \
                    "No file changes produced on retry; open rejections were not addressed"
                VERDICT="REJECT"
                REASON="No file changes produced on retry; open rejections were not addressed"
                echo "Verdict: ${VERDICT} — ${REASON}"
                echo "::endgroup::"
                continue
            fi
            echo "::warning::Attempt ${ATTEMPT} produced no new commit; branch diff passes path guards — running verifier"
        elif [[ ${ATTEMPT} -gt 1 ]]; then
            echo "::warning::Attempt ${ATTEMPT} produced no file changes; verifier will review the same diff as the previous attempt"
        fi

        if [[ ${HAS_CHANGES} != "true" ]]; then
            if [[ -f ${attempt_dir}/agent-output.txt ]] \
                && parse_outcome_override_from_agent_output "$(cat "${attempt_dir}/agent-output.txt")"; then
                OUTCOME_OVERRIDE="watch"
                REASON="Skill classified as watch with no file changes"
            else
                VERDICT="${NO_CHANGES_VERDICT}"
                REASON="No file changes produced"
            fi
            echo "No changes; verdict=${VERDICT} outcome_override=${OUTCOME_OVERRIDE:-none}."
            echo "::endgroup::"
            break
        fi

        echo "::endgroup::"

        echo "::group::Verifier attempt ${ATTEMPT}/${AGENT_LOOP_MAX_ATTEMPTS}"
        echo "Running verifier (fresh session)..."
        run_verify "${attempt_dir}" "${ATTEMPT}" "${attempt_committed}"
        VERDICT="$(cat "${attempt_dir}/verdict")"
        REASON="$(cat "${attempt_dir}/reason")"
        echo "Verdict: ${VERDICT} — ${REASON}"
        if [[ ${VERDICT} == "REJECT" && -f ${attempt_dir}/reject-files ]]; then
            echo "Reject files: $(tr '\n' ',' < "${attempt_dir}/reject-files" | sed 's/,$//')"
            echo "Reject fix: $(tr '\n' ' ' < "${attempt_dir}/reject-fix")"
        fi
        echo "::endgroup::"

        if [[ ${VERDICT} == "APPROVE" ]]; then
            OPEN_REJECTIONS_JSON='[]'
            break
        fi
    done

    if [[ ${VERDICT} == "APPROVE" ]]; then
        OPEN_REJECTIONS_JSON='[]'
    fi
}

#######################################
# main: Entry point for bounded loop execution
#
# Arguments:
#   None
#
# Global Variables:
#   AGENT_LOOP_MAX_ATTEMPTS - Maximum implementer attempts (read)
#   AGENT_TOKEN - Authentication token for the selected engine (read)
#   ENGINE - Agent engine name (read)
#   GITHUB_OUTPUT - GitHub Actions output file path (read)
#   PROMPT_TEXT - Base implementer prompt (read)
#   STATUS_DIR - Status directory for attempt artifacts (read)
#   WORKTREE_PATH - Isolated git worktree path (read)
#
# Returns:
#   0 on success
#
#######################################
function main {
    : "${STATUS_DIR:?}"
    : "${WORKTREE_PATH:?}"
    : "${GITHUB_OUTPUT:?}"
    : "${AGENT_LOOP_MAX_ATTEMPTS:?}"
    : "${PROMPT_TEXT:?}"
    : "${ENGINE:?}"
    : "${AGENT_TOKEN:?}"
    initialize_loop_state
    run_bounded_loop
    write_loop_outputs
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
