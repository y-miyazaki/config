#!/bin/bash
#######################################
# Description:
#   Built-in range detect for loop-detect, used when detect_script is omitted.
#   Reports whether any file changed between a stored since SHA and HEAD,
#   ignoring the paths the platform itself writes.
#
# Usage:
#   source "${LIB_DIR}/range_detect.sh"
#   range_detect "<since>" "<head>" "<state_file>" "<run_log_file>"
#
# Design Rules:
#   - Requires list_diff_paths (lib/loop/edit_paths.sh) and the target checked out as cwd
#   - Platform-written paths (.loop/, the state file, the run log) are excluded by git
#     pathspec, not filtered from the output: list_diff_paths prints nothing for an
#     unsafe path (rc 2), so a later filter could neither exclude nor count them
#   - rc 2 (unsafe path) runs the loop with a range-only verifier_context
#   - rc 1 (git failure) fails the detect phase; the rc is read explicitly, never via set -e
#   - The changed file list in verifier_context is capped at RANGE_DETECT_FILE_LIMIT
#
# Output:
#   Detect JSON on stdout: {"skip":true} or
#   {"skip":false,"result":{"since","head","changed_count"},"verifier_context":"..."}
#######################################

RANGE_DETECT_FILE_LIMIT=100

#######################################
# range_detect: Detect changed files between since and head
#
# Globals:
#   RANGE_DETECT_FILE_LIMIT - Maximum files listed in verifier_context (read)
#
# Arguments:
#   $1 - since ref (stored last_sha)
#   $2 - head ref (current sha)
#   $3 - state file path (absolute or repo-relative); excluded from the diff
#   $4 - run log file path (absolute or repo-relative); excluded from the diff
#
# Outputs:
#   Detect JSON on stdout; git diagnostics on stderr
#
# Returns:
#   0 on success (including skip); 1 when git cannot diff the range
#
#######################################
function range_detect {
    local since="$1"
    local head="$2"
    local state_file="${3:-}"
    local run_log_file="${4:-}"
    local top path rc=0 paths_out count context
    local -a pathspec=(-- . ':!.loop/')

    top="$(git rev-parse --show-toplevel)" || return 1
    for path in "${state_file}" "${run_log_file}"; do
        [[ -z ${path} ]] && continue
        pathspec+=(":!${path#"${top}"/}")
    done

    paths_out="$(list_diff_paths "${since}" "${head}" "${pathspec[@]}")" || rc=$?
    if [[ ${rc} -eq 1 ]]; then
        echo "::error::loop-detect: git diff failed for range ${since}..${head}" >&2
        return 1
    fi

    if [[ ${rc} -eq 0 && -z ${paths_out} ]]; then
        jq -nc '{skip: true}'
        return 0
    fi

    context="Range: ${since}..${head}"
    count="null"
    if [[ ${rc} -eq 0 ]]; then
        count="$(printf '%s\n' "${paths_out}" | grep -c '')"
        context+=$'\n'"Changed files (${count}, showing up to ${RANGE_DETECT_FILE_LIMIT}):"
        context+=$'\n'"$(printf '%s\n' "${paths_out}" | head -n "${RANGE_DETECT_FILE_LIMIT}" | sed 's/^/- /')"
    fi

    jq -nc \
        --arg since "${since}" \
        --arg head "${head}" \
        --argjson count "${count}" \
        --arg context "${context}" \
        '{skip: false, result: {since: $since, head: $head, changed_count: $count}, verifier_context: $context}'
}
