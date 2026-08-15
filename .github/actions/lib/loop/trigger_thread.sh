#!/bin/bash
#######################################
# Description:
#   Start ACK (reaction) and done-thread reply for comment-triggered loops
#   (github-pr-revise). Branches on issue_comment vs pull_request_review_comment.
#
# Usage:
#   source trigger_thread.sh
#   ack_trigger_comment
#   reply_trigger_comment "$(build_done_reply_body ...)"
#
# Design Rules:
#   - Failures warn only; never fail the caller job
#   - No reaction/reply for dispatch events or missing comment id
#   - Auto-resolve of review threads stays out of scope
#   - Environment variables mirror loop-notify-pr / caller wiring
#
# Output:
#   None (library file)
#
# Dependencies:
#   - bash, gh (when posting), jq (optional for body helpers)
#######################################

#######################################
# ack_trigger_comment: Add eyes reaction on the triggering comment
#
# Globals:
#   GITHUB_EVENT_NAME - Webhook event name
#   REPOSITORY - owner/name
#   TRIGGER_COMMENT_ID - Numeric comment id
#   GITHUB_TOKEN / GH_TOKEN - Token for gh
#
# Arguments:
#   None
#
# Outputs:
#   Warning annotations on failure
#
# Returns:
#   0 always (warnings only)
#
#######################################
function ack_trigger_comment {
    local event_name="${GITHUB_EVENT_NAME:-}"
    local comment_id="${TRIGGER_COMMENT_ID:-}"
    local repository="${REPOSITORY:-}"
    local endpoint

    if [[ -z ${comment_id} || -z ${repository} ]]; then
        return 0
    fi
    if ! command -v gh > /dev/null 2>&1; then
        echo "::warning::gh CLI is required for trigger ACK"
        return 0
    fi

    case "${event_name}" in
        issue_comment)
            endpoint="repos/${repository}/issues/comments/${comment_id}/reactions"
            ;;
        pull_request_review_comment)
            endpoint="repos/${repository}/pulls/comments/${comment_id}/reactions"
            ;;
        *)
            return 0
            ;;
    esac

    if ! gh api --method POST "${endpoint}" -f content='eyes' > /dev/null 2>&1; then
        echo "::warning::Failed to ACK trigger comment ${comment_id} (${event_name})"
        return 0
    fi
    echo "::notice title=trigger-ack::Added eyes reaction on comment ${comment_id}"
    return 0
}

#######################################
# build_done_reply_body: Render short done-reply markdown for a trigger thread
#
# Globals:
#   None
#
# Arguments:
#   $1 - Outcome enum (or empty)
#   $2 - Verdict (APPROVE/REJECT/empty)
#   $3 - Reason text (optional)
#   $4 - Commit SHA (optional)
#   $5 - Commit URL (optional)
#   $6 - Loop run URL (optional)
#   $7 - Summary line (optional; truncated externally)
#
# Outputs:
#   Reply body markdown on stdout
#
# Returns:
#   0 on success
#
#######################################
function build_done_reply_body {
    local outcome="${1:-}"
    local verdict="${2:-}"
    local reason="${3:-}"
    local commit_sha="${4:-}"
    local commit_url="${5:-}"
    local loop_run_url="${6:-}"
    local summary="${7:-}"
    local short_sha

    {
        echo "### Loop done"
        echo ""
        if [[ -n ${outcome} ]]; then
            echo "- Outcome: \`${outcome}\`"
        fi
        if [[ -n ${verdict} ]]; then
            echo "- Verdict: \`${verdict}\`"
        fi
        if [[ -n ${reason} ]]; then
            echo "- Reason: ${reason}"
        fi
        if [[ -n ${commit_sha} ]]; then
            short_sha="${commit_sha:0:7}"
            if [[ -n ${commit_url} && ${commit_url} != "#" ]]; then
                echo "- Commit: [\`${short_sha}\`](${commit_url})"
            else
                echo "- Commit: \`${short_sha}\`"
            fi
        fi
        if [[ -n ${loop_run_url} && ${loop_run_url} != "-" ]]; then
            echo "- Run: [actions](${loop_run_url})"
        fi
        if [[ -n ${summary} ]]; then
            echo ""
            echo "${summary}"
        fi
        echo ""
        echo "_Resolve the review thread when you are satisfied (not auto-resolved)._"
    }
}

#######################################
# reply_trigger_comment: Post done reply on the triggering comment thread
#
# Globals:
#   GITHUB_EVENT_NAME - Webhook event name
#   PR_NUMBER - Pull request number
#   REPOSITORY - owner/name
#   TRIGGER_COMMENT_ID - Numeric comment id
#   GITHUB_TOKEN / GH_TOKEN - Token for gh
#
# Arguments:
#   $1 - Reply body markdown
#
# Outputs:
#   Warning annotations on failure
#
# Returns:
#   0 always (warnings only)
#
#######################################
function reply_trigger_comment {
    local body="${1:-}"
    local event_name="${GITHUB_EVENT_NAME:-}"
    local comment_id="${TRIGGER_COMMENT_ID:-}"
    local repository="${REPOSITORY:-}"
    local pr_number="${PR_NUMBER:-}"
    local body_file payload

    if [[ -z ${body} || -z ${comment_id} || -z ${repository} || -z ${pr_number} ]]; then
        return 0
    fi
    if ! command -v gh > /dev/null 2>&1; then
        echo "::warning::gh CLI is required for trigger done-reply"
        return 0
    fi
    if ! command -v jq > /dev/null 2>&1; then
        echo "::warning::jq is required for trigger done-reply"
        return 0
    fi

    body_file="$(mktemp)"
    printf '%s\n' "${body}" > "${body_file}"
    payload="$(jq -nc --rawfile body "${body_file}" '{body: $body}')"
    rm -f "${body_file}"

    case "${event_name}" in
        pull_request_review_comment)
            if ! printf '%s' "${payload}" | gh api --method POST \
                "repos/${repository}/pulls/${pr_number}/comments/${comment_id}/replies" \
                --input - > /dev/null 2>&1; then
                echo "::warning::Failed to reply on review comment ${comment_id}"
                return 0
            fi
            ;;
        issue_comment)
            # Conversation comments are not REST-threaded; post a follow-up on the PR.
            if ! printf '%s' "${payload}" | gh api --method POST \
                "repos/${repository}/issues/${pr_number}/comments" \
                --input - > /dev/null 2>&1; then
                echo "::warning::Failed to post done reply for issue comment ${comment_id}"
                return 0
            fi
            ;;
        *)
            return 0
            ;;
    esac

    echo "::notice title=trigger-reply::Posted done reply for comment ${comment_id}"
    return 0
}
