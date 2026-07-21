#!/bin/bash
#######################################
# Description: Structured rejection tracking for loop-execute
#
# Usage: source "${SCRIPT_DIR}/lib/rejections.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - OPEN_REJECTIONS_JSON is a JSON array persisted across attempts
# - REJECT_FEEDBACK is markdown consumed by the implementer retry prompt
#######################################

#######################################
# append_open_rejection: Append one structured rejection to OPEN_REJECTIONS_JSON
#
# Arguments:
#   $1 - Attempt number
#   $2 - Comma-separated file paths
#   $3 - Issue description
#   $4 - Required fix description
#
# Globals:
#   OPEN_REJECTIONS_JSON - JSON array of open rejections
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function append_open_rejection {
    local attempt="$1"
    local files="$2"
    local issue="$3"
    local fix="$4"
    OPEN_REJECTIONS_JSON=$(jq -c \
        --argjson attempt "${attempt}" \
        --arg files "${files}" \
        --arg issue "${issue}" \
        --arg fix "${fix}" \
        '. + [{"attempt": $attempt, "files": ($files | if length == 0 then [] else split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) end), "issue": $issue, "fix": $fix}]' \
        <<< "${OPEN_REJECTIONS_JSON}")
}

#######################################
# format_open_rejections_for_prompt: Format open rejections as markdown
#
# Arguments:
#   None
#
# Globals:
#   OPEN_REJECTIONS_JSON - JSON array of open rejections
#
# Outputs:
#   Markdown block to stdout, or nothing when empty
#
# Returns:
#   0 on success
#
#######################################
function format_open_rejections_for_prompt {
    if [[ "$(jq 'length' <<< "${OPEN_REJECTIONS_JSON}")" -eq 0 ]]; then
        return 0
    fi
    jq -r '.[] | "### Attempt \(.attempt)\n- **Files:** " + (if (.files | length) > 0 then (.files | join(", ")) else "not specified" end) + "\n- **Issue:** \(.issue)\n- **Required fix:** \(.fix)\n"' \
        <<< "${OPEN_REJECTIONS_JSON}"
}

#######################################
# record_structured_reject: Persist rejection artifacts for one attempt
#
# Arguments:
#   $1 - Attempt directory
#   $2 - Attempt number
#   $3 - Comma-separated file paths
#   $4 - Issue description
#   $5 - Required fix description
#   $6 - One-line summary for logs
#
# Globals:
#   OPEN_REJECTIONS_JSON - Updated via append_open_rejection
#   REJECT_FEEDBACK - Updated via sync_reject_feedback
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function record_structured_reject {
    local attempt_dir="$1"
    local attempt="$2"
    local files="$3"
    local issue="$4"
    local fix="$5"
    local summary="$6"
    printf '%s\n' "${files}" > "${attempt_dir}/reject-files"
    printf '%s\n' "${issue}" > "${attempt_dir}/reject-issue"
    printf '%s\n' "${fix}" > "${attempt_dir}/reject-fix"
    append_open_rejection "${attempt}" "${files}" "${issue}" "${fix}"
    sync_reject_feedback
    printf '%s\n' "REJECT" > "${attempt_dir}/verdict"
    printf '%s\n' "${summary}" > "${attempt_dir}/reason"
}

#######################################
# sync_reject_feedback: Refresh REJECT_FEEDBACK from OPEN_REJECTIONS_JSON
#
# Arguments:
#   None
#
# Globals:
#   REJECT_FEEDBACK - Markdown feedback for implementer retry prompt
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function sync_reject_feedback {
    # REJECT_FEEDBACK is module state consumed by lib/loop.sh.
    # shellcheck disable=SC2034
    REJECT_FEEDBACK="$(format_open_rejections_for_prompt)"
}
