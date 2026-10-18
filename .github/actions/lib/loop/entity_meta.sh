#!/bin/bash
#######################################
# Description:
#   Post the text an entity loop (L1) agent wrote as one Issue comment that
#   already carries the Meta block and the Loop Engineering footer. The agent
#   does not post: it ends its run with the comment text, and the stage that
#   measured the usage posts it, so there is no second edit of a posted message.
#
# Usage:
#   source created_by.sh
#   source loop_meta.sh
#   source entity_meta.sh
#   post_entity_comment ISSUE_NUMBER MARKER BODY_FILE OUTCOME ENGINE USAGE_JSON RUN_URL
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Block shape comes from build_loop_meta_block so every surface matches
#   - The skill marker leads the comment (later runs and the FSM find it by marker)
#   - Empty agent text posts nothing; posting is best-effort and never fails the loop
#######################################

#######################################
# entity_issue_number: Extract the Issue number from an entity handoff key
#
# Globals:
#   None
#
# Arguments:
#   $1 - Handoff key (entity:issue:<n>)
#
# Outputs:
#   The number on stdout, empty for any other key
#
# Returns:
#   0 always
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

#######################################
# post_entity_comment: Post the agent text with Meta and the footer as one Issue comment
#
# Globals:
#   GITHUB_TOKEN / GH_TOKEN - Token for gh
#   REPOSITORY - owner/name
#
# Arguments:
#   $1 - Issue number
#   $2 - Skill marker placed first (added only when the text lacks it)
#   $3 - File holding the agent's comment text
#   $4 - Outcome enum
#   $5 - Engine slug
#   $6 - usage_json string
#   $7 - Loop run URL
#
# Outputs:
#   Notice or warning annotation on stdout
#
# Returns:
#   0 always (the comment is best-effort; it must never fail the loop)
#
# Usage:
#   post_entity_comment 936 "<!-- github-issue-triage:v1 -->" "${body_file}" unchanged claude "${USAGE_JSON}" "${url}"
#
#######################################
function post_entity_comment {
    local issue_number="$1"
    local marker="$2"
    local body_file="$3"
    local outcome="${4:-}"
    local engine="${5:-}"
    local usage_json="${6:-}"
    local run_url="${7:-}"
    local text block out_file

    if [[ ! ${issue_number} =~ ^[1-9][0-9]*$ ]]; then
        return 0
    fi

    text="$(cat "${body_file}" 2> /dev/null || true)"
    # Trim surrounding whitespace so an agent that printed only blank lines posts nothing
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    if [[ -z ${text} ]]; then
        echo "::notice title=loop-comment::Agent produced no comment text for #${issue_number}; nothing to post"
        return 0
    fi

    loop_meta_reset
    block="$(build_loop_meta_block "${outcome}" "" "" "${engine}" "${usage_json}" "${run_url}")"

    out_file="$(mktemp)"
    {
        if [[ ${text} != "${marker}"* ]]; then
            printf '%s\n' "${marker}"
        fi
        printf '%s\n\n%s\n' "${text}" "${block}"
    } > "${out_file}"

    if gh issue comment "${issue_number}" --repo "${REPOSITORY}" --body-file "${out_file}" > /dev/null 2>&1; then
        echo "::notice title=loop-comment::Posted loop comment on #${issue_number}"
    else
        echo "::warning::Failed to post loop comment on #${issue_number}"
    fi
    rm -f "${out_file}"
    return 0
}
