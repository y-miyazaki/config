#!/bin/bash
#######################################
# Description:
#   Post or update a loop-notify-pr marker comment on a pull request.
#   Environment variables mirror loop-notify-pr composite action inputs.
#
# Usage:
#   LOOP_NAME=ci-sweeper OUTCOME=pr-created PR_NUMBER=42 TOKEN=... bash lib/notify.sh
#
# Design Rules:
#   - One marker comment per PR per loop name (idempotent upsert)
#   - Notification failures must not fail the caller job (warnings only)
#   - No full diff or raw logs in comment body
#
# Output:
#   Writes comment_id and comment_url to GITHUB_OUTPUT
#
# Dependencies:
#   - bash, gh, jq
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
ATTEMPTS="${ATTEMPTS:-}"
AUTO_MERGE="${AUTO_MERGE:-false}"
COMMIT_SHA="${COMMIT_SHA:-}"
FIX_PR_NUMBER="${FIX_PR_NUMBER:-}"
FIX_PR_URL="${FIX_PR_URL:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
LEVEL="${LEVEL:-L2}"
LOOP_NAME="${LOOP_NAME:-}"
LOOP_RUN_ID="${LOOP_RUN_ID:-}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-}"
NOTIFY_CONTEXT_JSON="${NOTIFY_CONTEXT_JSON:-"{}"}"
OUTCOME="${OUTCOME:-}"
PR_NUMBER="${PR_NUMBER:-}"
REJECT_REASON="${REJECT_REASON:-}"
REPOSITORY="${REPOSITORY:-}"
TARGET_JSON="${TARGET_JSON:-"{}"}"
TOKEN="${TOKEN:-}"
VERDICT="${VERDICT:-}"

#######################################
# build_comment_body: Render marker comment markdown
#
# Arguments:
#   $1 - Actor login
#
# Globals:
#   ATTEMPTS - Attempt count for display
#   COMMIT_SHA - Pushed commit SHA when present
#   GITHUB_SERVER_URL - GitHub server URL prefix
#   LOOP_NAME - Loop name for marker scoping
#   LOOP_RUN_ID - Current workflow run id
#   MAX_ATTEMPTS - Maximum attempts for display
#   NOTIFY_CONTEXT_JSON - Machine context from loop-execute
#   OUTCOME - Finalize outcome enum
#   REJECT_REASON - Verifier rejection reason
#   TARGET_JSON - Target descriptor JSON
#   VERDICT - Verifier verdict when present
#
# Outputs:
#   Comment body to stdout
#
# Returns:
#   0 on success
#
#######################################
function build_comment_body {
    local actor="$1"
    local marker branch to_branch workflow_name workflow_run_id workflow_url
    local loop_run_url commit_url short_sha verdict_display fix_context agent_summary
    local agent_report_overview agent_report_summary has_agent_narrative
    local changed_files diff_stat fix_summary reject_display timestamp bot_fix_pr next_step

    marker="<!-- loop-notify-pr:v1:${LOOP_NAME} -->"
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    if [[ -n ${TARGET_JSON} ]] && jq -e . <<< "${TARGET_JSON}" > /dev/null 2>&1; then
        branch=$(jq -r '.to.branch // "-"' <<< "${TARGET_JSON}")
        to_branch="${branch}"
        workflow_name=$(jq -r '.workflow_name // "workflow"' <<< "${TARGET_JSON}")
        workflow_run_id=$(jq -r '.workflow_run_id // empty' <<< "${TARGET_JSON}")
    else
        to_branch="-"
        workflow_name="workflow"
        workflow_run_id=""
    fi

    if [[ -n ${workflow_run_id} ]]; then
        workflow_url="${GITHUB_SERVER_URL}/${REPOSITORY}/actions/runs/${workflow_run_id}"
    else
        workflow_url="-"
    fi

    loop_run_url="${GITHUB_SERVER_URL}/${REPOSITORY}/actions/runs/${LOOP_RUN_ID}"

    if [[ -n ${COMMIT_SHA} ]]; then
        short_sha="${COMMIT_SHA:0:7}"
        commit_url="${GITHUB_SERVER_URL}/${REPOSITORY}/commit/${COMMIT_SHA}"
    else
        short_sha="-"
        commit_url="#"
    fi

    if [[ -n ${VERDICT} ]]; then
        verdict_display="${VERDICT}"
    else
        verdict_display="—"
    fi

    if [[ -n ${NOTIFY_CONTEXT_JSON} ]] && jq -e . <<< "${NOTIFY_CONTEXT_JSON}" > /dev/null 2>&1; then
        fix_summary=$(jq -r '.fix_summary // ""' <<< "${NOTIFY_CONTEXT_JSON}")
        diff_stat=$(jq -r '.diff_stat // ""' <<< "${NOTIFY_CONTEXT_JSON}")
        agent_report_overview=$(jq -r '.agent_report_overview // ""' <<< "${NOTIFY_CONTEXT_JSON}")
        agent_report_summary=$(jq -r '.agent_report_summary // ""' <<< "${NOTIFY_CONTEXT_JSON}")
        agent_summary=$(jq -r '.agent_summary // ""' <<< "${NOTIFY_CONTEXT_JSON}")
        changed_files=$(jq -r '.changed_files[]? // empty' <<< "${NOTIFY_CONTEXT_JSON}" | paste -sd, - || true)
    else
        agent_report_overview=""
        agent_report_summary=""
        fix_summary=""
        diff_stat=""
        agent_summary=""
        changed_files=""
    fi

    agent_report_overview="$(truncate_text "$(redact_sensitive_text "${agent_report_overview}")" 2000)"
    agent_report_summary="$(truncate_text "$(redact_sensitive_text "${agent_report_summary}")" 4000)"
    fix_summary="$(truncate_text "$(redact_sensitive_text "${fix_summary}")" 2000)"
    agent_summary="$(truncate_text "$(redact_sensitive_text "${agent_summary}")" 2000)"
    reject_display="$(truncate_text "$(redact_sensitive_text "${REJECT_REASON}")" 2000)"

    has_agent_narrative=false
    if [[ -n ${agent_report_overview}${agent_report_summary} ]]; then
        has_agent_narrative=true
    fi

    if [[ ${has_agent_narrative} != true ]]; then
        if [[ -n ${changed_files} || -n ${diff_stat} ]]; then
            fix_context="**${fix_summary}**"
            if [[ -n ${changed_files} ]]; then
                fix_context="${fix_context}"$'\n\n'"Changed files: \`${changed_files}\`"
            fi
            if [[ -n ${diff_stat} ]]; then
                fix_context="${fix_context}"$'\n\n'"\`${diff_stat}\`"
            fi
        elif [[ ${OUTCOME} == "watch" ]]; then
            fix_context="No file changes; classified as **watch**."
        elif [[ -n ${reject_display} ]]; then
            fix_context="${reject_display}"
        else
            fix_context="No mechanical fix context available."
        fi
    fi

    if [[ -n ${FIX_PR_NUMBER} && -n ${FIX_PR_URL} ]]; then
        bot_fix_pr="[#${FIX_PR_NUMBER}](${FIX_PR_URL})"
    else
        bot_fix_pr="—"
    fi

    next_step=""
    if [[ ${OUTCOME} == "pr-created" && -n ${FIX_PR_URL} ]]; then
        if [[ ${LEVEL} == "L3" && ${AUTO_MERGE} == "true" ]]; then
            next_step="**Next step (L3):** Bot fix PR will auto-merge when checks pass. Wait for CI on this PR after merge."
        else
            next_step="**Next step (L2):** Merge or close the bot fix PR above, then re-run CI on this PR."
        fi
    fi

    cat << EOF
${marker}
## Loop notification: ${LOOP_NAME}

| Field | Value |
| ----- | ----- |
| Outcome | \`${OUTCOME}\` |
| Bot fix PR | ${bot_fix_pr} |
| Verdict | ${verdict_display} |
| Actor | \`${actor}\` |
| Commit | [\`${short_sha}\`](${commit_url}) |
| Branch | \`${to_branch}\` |
| Failed run | [${workflow_name} #${workflow_run_id:-—}](${workflow_url}) |
| Loop run | [actions run](${loop_run_url}) |
| Attempt | ${ATTEMPTS:-—}/${MAX_ATTEMPTS:-—} |
| Timestamp | ${timestamp} |
EOF

    if [[ -n ${agent_report_overview} ]]; then
        cat << EOF

### Overview

${agent_report_overview}
EOF
    fi

    if [[ -n ${agent_report_summary} ]]; then
        cat << EOF

### Summary

${agent_report_summary}
EOF
    fi

    if [[ ${has_agent_narrative} == true ]]; then
        if [[ -n ${changed_files} || -n ${diff_stat} ]]; then
            cat << EOF

### Changes
EOF
            if [[ -n ${changed_files} ]]; then
                # shellcheck disable=SC2016
                printf '\nChanged files: `%s`\n' "${changed_files}"
            fi
            if [[ -n ${diff_stat} ]]; then
                # shellcheck disable=SC2016
                printf '\n`%s`\n' "${diff_stat}"
            fi
        elif [[ ${OUTCOME} == "watch" ]]; then
            cat << EOF

### Fix context

No file changes; classified as **watch**.
EOF
        fi
    else
        cat << EOF

### Fix context

${fix_context}
EOF
    fi

    if [[ -n ${next_step} ]]; then
        cat << EOF

${next_step}
EOF
    fi

    if [[ -n ${agent_summary} && -z ${agent_report_summary} ]]; then
        cat << EOF

### Agent summary (appendix)

${agent_summary}
EOF
    fi
}

#######################################
# find_existing_comment: Find comment id by loop marker
#
# Arguments:
#   $1 - Marker substring
#
# Globals:
#   PR_NUMBER - Target pull request number
#   REPOSITORY - Repository owner/name
#
# Outputs:
#   Comment GraphQL node id to stdout, or empty
#
# Returns:
#   0 on success
#
#######################################
function find_existing_comment {
    local marker="$1"
    gh pr view "${PR_NUMBER}" \
        --repo "${REPOSITORY}" \
        --json comments \
        --jq ".comments[] | select(.body | contains(\"${marker}\")) | .id" \
        2> /dev/null | head -1 || true
}

#######################################
# redact_sensitive_text: Redact common secret patterns
#
# Arguments:
#   $1 - Input text
#
# Globals:
#   None
#
# Outputs:
#   Redacted text to stdout
#
# Returns:
#   0 on success
#
#######################################
function redact_sensitive_text {
    local text="$1"
    # Keep patterns aligned with loop-ci-sweeper sanitize_log_excerpt.
    text=$(sed -E 's/gh[pousr]_[A-Za-z0-9_]{20,}/[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/(password|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]\"]+/\1=[REDACTED]/gi' <<< "${text}")
    text=$(sed -E 's/x-access-token:[A-Za-z0-9._-]+/x-access-token:[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/Bearer[[:space:]]+[A-Za-z0-9._-]+/Bearer [REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/Authorization:[[:space:]]*[^[:space:]\"]+/Authorization: [REDACTED]/gi' <<< "${text}")
    text=$(sed -E 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED-JWT]/g' <<< "${text}")
    text=$(sed -E 's/-----BEGIN [A-Z ]+-----[^-]*-----END [A-Z ]+-----/[REDACTED-PEM]/g' <<< "${text}")
    printf '%s' "${text}"
}

#######################################
# truncate_text: Truncate text to max length
#
# Arguments:
#   $1 - Input text
#   $2 - Maximum length
#
# Globals:
#   None
#
# Outputs:
#   Truncated text to stdout
#
# Returns:
#   0 on success
#
#######################################
function truncate_text {
    local text="$1"
    local max="$2"
    if [[ ${#text} -le ${max} ]]; then
        printf '%s' "${text}"
    else
        printf '%s' "${text:0:max}"
    fi
}

#######################################
# upsert_comment: Create or update PR comment
#
# Arguments:
#   $1 - Comment body file path
#   $2 - Marker substring
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file path
#   PR_NUMBER - Target pull request number
#   REPOSITORY - Repository owner/name
#
# Outputs:
#   None
#
# Returns:
#   0 on success, 1 on failure
#
#######################################
function upsert_comment {
    local body_file="$1"
    local marker="$2"
    local comment_id comment_url payload update_err

    comment_id="$(find_existing_comment "${marker}")"

    if [[ -n ${comment_id} ]]; then
        update_err="$(mktemp)"
        # Pass multiline body via JSON stdin (avoid -f body= form encoding issues).
        # shellcheck disable=SC2016
        payload="$(jq -nc \
            --arg commentId "${comment_id}" \
            --rawfile body "${body_file}" \
            --arg query 'mutation UpdateComment($commentId: ID!, $body: String!) {
              updateIssueComment(input: {id: $commentId, body: $body}) {
                issueComment { id url }
              }
            }' \
            '{query: $query, variables: {commentId: $commentId, body: $body}}')"
        if comment_url="$(printf '%s' "${payload}" | gh api graphql --input - \
            --jq '.data.updateIssueComment.issueComment.url' 2> "${update_err}")" \
            && [[ -n ${comment_url} ]]; then
            rm -f "${update_err}"
            echo "comment_id=${comment_id}" >> "${GITHUB_OUTPUT}"
            echo "comment_url=${comment_url}" >> "${GITHUB_OUTPUT}"
            return 0
        fi
        echo "::warning::Failed to update existing loop-notify-pr comment; creating a new comment"
        rm -f "${update_err}"
    fi

    if ! gh pr comment "${PR_NUMBER}" \
        --repo "${REPOSITORY}" \
        --body-file "${body_file}" > /dev/null; then
        return 1
    fi

    comment_id="$(find_existing_comment "${marker}")"
    comment_url="$(gh pr view "${PR_NUMBER}" \
        --repo "${REPOSITORY}" \
        --json comments \
        --jq ".comments[] | select(.body | contains(\"${marker}\")) | .url" \
        2> /dev/null | head -1 || true)"
    echo "comment_id=${comment_id}" >> "${GITHUB_OUTPUT}"
    echo "comment_url=${comment_url}" >> "${GITHUB_OUTPUT}"
    return 0
}

#######################################
# validate_required_inputs: Validate required loop-notify-pr environment
#
# Arguments:
#   None
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file path
#   LOOP_NAME - Loop name for marker scoping
#   OUTCOME - Finalize outcome enum
#   PR_NUMBER - Target pull request number
#   REPOSITORY - Repository owner/name
#   TOKEN - GitHub token with pull-requests: write
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 when required input is missing
#
#######################################
function validate_required_inputs {
    : "${GITHUB_OUTPUT:?}"
    : "${LOOP_NAME:?}"
    : "${OUTCOME:?}"
    : "${PR_NUMBER:?}"
    : "${REPOSITORY:?}"
    : "${TOKEN:?}"
}

#######################################
# main: Post or update loop-notify-pr marker comment
#
# Arguments:
#   None
#
# Globals:
#   ATTEMPTS - Attempt count for display
#   COMMIT_SHA - Pushed commit SHA when present
#   GITHUB_OUTPUT - GitHub Actions output file path
#   GITHUB_SERVER_URL - GitHub server URL prefix
#   LOOP_NAME - Loop name for marker scoping
#   LOOP_RUN_ID - Current workflow run id
#   MAX_ATTEMPTS - Maximum attempts for display
#   NOTIFY_CONTEXT_JSON - Machine context from loop-execute
#   OUTCOME - Finalize outcome enum
#   PR_NUMBER - Target pull request number
#   REJECT_REASON - Verifier rejection reason
#   REPOSITORY - Repository owner/name
#   TARGET_JSON - Target descriptor JSON
#   TOKEN - GitHub token (exported as GH_TOKEN for gh CLI)
#   VERDICT - Verifier verdict when present
#
# Outputs:
#   None
#
# Returns:
#   0 on success or when prerequisites are missing
#
#######################################
function main {
    local actor body_file marker

    if ! command -v gh > /dev/null 2>&1; then
        echo "::warning::gh CLI is required for loop-notify-pr"
        return 0
    fi
    if ! command -v jq > /dev/null 2>&1; then
        echo "::warning::jq is required for loop-notify-pr"
        return 0
    fi

    validate_required_inputs

    export GH_TOKEN="${TOKEN}"
    actor="$(gh api user --jq '.login' 2> /dev/null || echo "github-actions")"
    marker="<!-- loop-notify-pr:v1:${LOOP_NAME} -->"
    body_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${body_file}'" EXIT

    build_comment_body "${actor}" > "${body_file}"

    if [[ $(wc -c < "${body_file}") -gt 65536 ]]; then
        echo "::warning::loop-notify-pr comment exceeds GitHub limit; truncating appendix"
        sed -i '/^### Agent summary (appendix)/,$d' "${body_file}" || true
    fi
    if [[ $(wc -c < "${body_file}") -gt 65536 ]]; then
        echo "::warning::loop-notify-pr comment still exceeds limit; truncating Summary"
        sed -i '/^### Summary$/,$d' "${body_file}" || true
    fi

    if ! upsert_comment "${body_file}" "${marker}"; then
        echo "::warning::loop-notify-pr failed to post comment on PR #${PR_NUMBER}"
        return 0
    fi

    echo "::notice title=loop-notify-pr::Posted notification on PR #${PR_NUMBER}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
