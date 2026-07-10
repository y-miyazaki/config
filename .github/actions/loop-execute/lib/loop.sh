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

set -euo pipefail
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

#######################################
# initialize_loop_state: Prepare status directory and prompt defaults
#
# Arguments:
#   None
#
# Returns:
#   None
#
#######################################
function initialize_loop_state {
    mkdir -p "${STATUS_DIR}"
    normalize_no_changes_verdict
    load_default_prompts
}

#######################################
# write_loop_outputs: Write step outputs to GITHUB_OUTPUT
#
# Arguments:
#   None
#
# Global Variables:
#   VERDICT, ATTEMPT, HAS_CHANGES, REASON, OPEN_REJECTIONS_JSON
#
# Returns:
#   None
#
#######################################
function write_loop_outputs {
    local delim
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
        if ! run_agent "true" 2>&1 | tee "${attempt_dir}/agent-output.txt"; then
            echo "::warning::Implementer agent exited non-zero on attempt ${ATTEMPT}"
        fi

        if commit_worktree_if_needed "${COMMIT_MESSAGE} (attempt ${ATTEMPT})"; then
            HAS_CHANGES="true"
            attempt_committed="true"
        elif [[ ${ATTEMPT} -gt 1 && -n ${REJECT_FEEDBACK} ]]; then
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
        elif [[ ${ATTEMPT} -gt 1 ]]; then
            echo "::warning::Attempt ${ATTEMPT} produced no file changes; verifier will review the same diff as the previous attempt"
        fi

        if [[ ${HAS_CHANGES} != "true" ]]; then
            VERDICT="${NO_CHANGES_VERDICT}"
            REASON="No file changes produced"
            echo "No changes; treating as ${VERDICT}."
            echo "::endgroup::"
            break
        fi

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
