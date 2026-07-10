#!/bin/bash
#######################################
# Description: Path guard utilities for loop-execute verification
#
# Usage: source "${SCRIPT_DIR}/lib/paths.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Allowlist and denylist checks run before the LLM verifier
# - Glob patterns follow bash pathname expansion rules
#######################################

#######################################
# collect_allowlist_violations: Find changed files outside the allowlist
#
# Arguments:
#   $1 - Newline-separated changed file paths
#
# Global Variables:
#   ALLOWLIST - Comma-separated glob allowlist (optional)
#
# Returns:
#   Newline-separated violating paths to stdout, or nothing
#
#######################################
function collect_allowlist_violations {
    local changed_files="$1"
    local violations="" pattern file matched
    if [[ -z ${ALLOWLIST:-} ]]; then
        return 0
    fi
    IFS=',' read -ra PATTERNS <<< "${ALLOWLIST}"
    while IFS= read -r file; do
        [[ -z ${file} ]] && continue
        matched="false"
        for pattern in "${PATTERNS[@]}"; do
            pattern=$(echo "${pattern}" | xargs)
            # shellcheck disable=SC2053
            if [[ ${file} == ${pattern} ]]; then
                matched="true"
                break
            fi
        done
        if [[ ${matched} != "true" ]]; then
            violations="${violations}${file}\n"
        fi
    done <<< "${changed_files}"
    if [[ -n ${violations} ]]; then
        printf '%b' "${violations}"
    fi
}

#######################################
# collect_denylist_violations: Find changed files matching the denylist
#
# Arguments:
#   $1 - Newline-separated changed file paths
#
# Global Variables:
#   DENYLIST - Comma-separated glob denylist
#
# Returns:
#   Newline-separated matching paths to stdout, or nothing
#
#######################################
function collect_denylist_violations {
    local changed_files="$1"
    local violations="" pattern file
    if [[ -z ${DENYLIST:-} ]]; then
        return 0
    fi
    IFS=',' read -ra PATTERNS <<< "${DENYLIST}"
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "${pattern}" | xargs)
        while IFS= read -r file; do
            [[ -z ${file} ]] && continue
            # shellcheck disable=SC2053
            if [[ ${file} == ${pattern} ]]; then
                violations="${violations}${file}\n"
            fi
        done <<< "${changed_files}"
    done
    if [[ -n ${violations} ]]; then
        printf '%b' "${violations}"
    fi
}

#######################################
# infer_files_from_text: Infer file paths from verifier text
#
# Arguments:
#   $1 - Verifier text to scan
#   $2 - Fallback comma-separated file paths
#
# Global Variables:
#   INFER_FILES_PATTERN - Optional extended-regex override
#
# Returns:
#   Comma-separated file paths to stdout
#
#######################################
function infer_files_from_text {
    local text="$1"
    local fallback="$2"
    local inferred=""
    if [[ -n ${INFER_FILES_PATTERN:-} ]]; then
        inferred=$(printf '%s\n' "${text}" | grep -oE "${INFER_FILES_PATTERN}" | sort -u | paste -sd, - || true)
    else
        inferred=$(printf '%s\n' "${text}" | grep -oE '[[:alnum:]_.-]+/[^[:space:],)]+' | sort -u | paste -sd, - || true)
    fi
    if [[ -n ${inferred} ]]; then
        printf '%s' "${inferred}"
    else
        printf '%s' "${fallback}"
    fi
}
