#!/bin/bash
#######################################
# Description:
#   Create repository labels that do not exist yet, so the loop never depends on a
#   label that a human has to create first. Sourced by every loop code path that
#   puts a label on an Issue or a pull request.
#
# Usage:
#   source ensure_labels.sh
#   ensure_labels_repo LABEL [LABEL...]
#   ensure_labels_parse_list LIST [SEPARATOR]
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - ensure_labels_parse_list is the one place that turns a caller-supplied label list into names
#   - An existing label is never changed (no --force; color and description stay)
#   - "already exists" is success, so a concurrent run creating the same label is safe
#   - Any other gh failure stops at the first label and is reported on stderr
#   - Needs issues: write or pull-requests: write on the token
#
# Dependencies:
#   - bash, gh
#######################################

#######################################
# ensure_labels_repo: Create each given label unless it already exists
#
# Globals:
#   GITHUB_REPOSITORY - owner/name
#   GH_TOKEN - Token for gh
#
# Arguments:
#   $@ - Label names (empty names are skipped)
#
# Outputs:
#   "Failed to create label <name>: <gh stderr>" on stderr on failure
#
# Returns:
#   0 when every label exists afterwards; 1 on the first failed create
#
#######################################
function ensure_labels_repo {
    local label err

    for label in "$@"; do
        [[ -n ${label} ]] || continue
        if ! err="$(gh label create "${label}" --repo "${GITHUB_REPOSITORY}" \
            --description "Created by a loop workflow" 2>&1)" && [[ ${err} != *"already exists"* ]]; then
            echo "Failed to create label ${label}: ${err}" >&2
            return 1
        fi
    done
    return 0
}

#######################################
# ensure_labels_parse_list: Print one trimmed label name per line from a delimited list
#
# Globals:
#   None
#
# Arguments:
#   $1 - Label list (may be empty)
#   $2 - Single-character separator (default: newline)
#
# Outputs:
#   One label per line on stdout; empty entries are dropped
#
# Returns:
#   0 always
#
# Usage:
#   mapfile -t labels < <(ensure_labels_parse_list "${FINALIZE_LABEL_ALLOWLIST:-}")
#   mapfile -t labels < <(ensure_labels_parse_list "${PR_LABELS}" ",")
#
#######################################
function ensure_labels_parse_list {
    local list="${1:-}"
    local separator="${2:-$'\n'}"
    local label

    while IFS= read -r label; do
        label="${label#"${label%%[![:space:]]*}"}"
        label="${label%"${label##*[![:space:]]}"}"
        [[ -n ${label} ]] && printf '%s\n' "${label}"
    done < <(tr "${separator}" '\n' <<< "${list}")
    return 0
}
