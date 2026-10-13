#!/bin/bash
#######################################
# Description:
#   Append a collapsed engine/model/token meta block to the Issue comment an
#   entity loop (L1) agent posted. L1 agents write their own comment through
#   gh issue comment, so no platform footer is attached to it; finalize is the
#   only stage that knows the usage totals.
#
# Usage:
#   source created_by.sh
#   source loop_meta.sh
#   source entity_meta.sh
#   append_entity_meta ISSUE_NUMBER MARKER OUTCOME ENGINE USAGE_JSON RUN_URL
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Block shape comes from build_loop_meta_block so every surface matches
#   - No-op when the marker comment is absent; never post a standalone comment
#   - Idempotent: a comment already carrying the meta marker is left alone
#######################################

#######################################
# find_marker_comment_id: Resolve the newest Issue comment carrying a marker
#
# Globals:
#   GITHUB_TOKEN / GH_TOKEN - Token for gh
#   REPOSITORY - owner/name
#
# Arguments:
#   $1 - Issue number
#   $2 - Marker substring identifying the agent comment
#
# Outputs:
#   Comment id on stdout, empty when no comment matches
#
# Returns:
#   0 on success, 1 when gh is unavailable
#
# Usage:
#   id="$(find_marker_comment_id 936 "<!-- github-issue-triage:v1 -->")"
#
#######################################
function find_marker_comment_id {
    local issue_number="$1"
    local marker="$2"
    local comments

    if ! command -v gh > /dev/null 2>&1; then
        return 1
    fi

    comments="$(gh api --paginate "repos/${REPOSITORY}/issues/${issue_number}/comments" 2> /dev/null || true)"
    if [[ -z ${comments} ]]; then
        return 0
    fi

    jq -r --arg marker "${marker}" --arg meta "${LOOP_META_MARKER}" '
        [ .[]? | select((.body // "") | contains($marker)) | select(((.body // "") | contains($meta)) | not) ]
        | last
        | .id // empty
    ' <<< "${comments}" 2> /dev/null || true
}

#######################################
# append_entity_meta: Append the meta block to the agent Issue comment
#
# Globals:
#   GITHUB_TOKEN / GH_TOKEN - Token for gh
#   REPOSITORY - owner/name
#
# Arguments:
#   $1 - Issue number
#   $2 - Marker substring identifying the agent comment
#   $3 - Outcome enum (optional)
#   $4 - Engine slug (optional)
#   $5 - usage_json string (optional)
#   $6 - Loop run URL (optional)
#
# Outputs:
#   Notice/warning annotations on stdout
#
# Returns:
#   0 always (meta is best-effort; it must never fail the loop)
#
# Usage:
#   append_entity_meta 936 "<!-- github-issue-triage:v1 -->" no-changes claude "${USAGE_JSON}" "${url}"
#
#######################################
function append_entity_meta {
    local issue_number="$1"
    local marker="$2"
    local outcome="${3:-}"
    local engine="${4:-}"
    local usage_json="${5:-}"
    local run_url="${6:-}"
    local block comment_id body merged tmp_body

    if [[ ! ${issue_number} =~ ^[1-9][0-9]*$ ]]; then
        return 0
    fi

    loop_meta_reset
    block="$(build_loop_meta_block "${outcome}" "" "" "${engine}" "${usage_json}" "${run_url}")"
    if [[ -z ${block} ]]; then
        return 0
    fi

    comment_id="$(find_marker_comment_id "${issue_number}" "${marker}")" || return 0
    if [[ -z ${comment_id} ]]; then
        echo "::notice title=loop-meta::No ${marker} comment on issue ${issue_number}; meta not appended"
        return 0
    fi

    body="$(gh api "repos/${REPOSITORY}/issues/comments/${comment_id}" --jq '.body // ""' 2> /dev/null || true)"
    if [[ -z ${body} ]]; then
        return 0
    fi

    merged="${body}"$'\n\n'"${block}"
    tmp_body="$(mktemp)"
    printf '%s' "${merged}" > "${tmp_body}"
    if gh api --method PATCH "repos/${REPOSITORY}/issues/comments/${comment_id}" \
        -F "body=@${tmp_body}" > /dev/null 2>&1; then
        echo "::notice title=loop-meta::Appended loop meta to comment ${comment_id}"
    else
        echo "::warning::Failed to append loop meta to comment ${comment_id}"
    fi
    rm -f "${tmp_body}"
    return 0
}

#######################################
# entity_issue_number: Extract the Issue number from an entity handoff key
#
# Globals:
#   None
#
# Arguments:
#   $1 - Handoff key (for example entity:issue:936)
#
# Outputs:
#   Issue number on stdout, empty when the key is not an Issue entity
#
# Returns:
#   0 on success
#
# Usage:
#   number="$(entity_issue_number "entity:issue:936")"
#
#######################################
function entity_issue_number {
    local key="${1:-}"

    if [[ ${key} =~ ^entity:issue:([1-9][0-9]*)$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}
