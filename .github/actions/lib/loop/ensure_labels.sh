#!/bin/bash
#######################################
# Description:
#   Create repository labels that do not exist yet, so the loop never depends on a
#   label that a human has to create first. Sourced by every loop code path that
#   puts a label on an Issue or a pull request.
#
# Usage:
#   source ensure_labels.sh
#   ensure_repo_labels LABEL [LABEL...]
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - An existing label is never changed (no --force; color and description stay)
#   - "already exists" is success, so a concurrent run creating the same label is safe
#   - Any other gh failure stops at the first label and is reported on stderr
#   - Needs issues: write or pull-requests: write on the token
#
# Dependencies:
#   - bash, gh
#######################################

#######################################
# ensure_repo_labels: Create each given label unless it already exists
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
function ensure_repo_labels {
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
