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
# - Glob patterns follow gitwildmatch-style path rules (** crosses /)
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
            if path_matches_glob "${file}" "${pattern}"; then
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
        while IFS= read -r file; do
            [[ -z ${file} ]] && continue
            if path_matches_glob "${file}" "${pattern}"; then
                violations="${violations}${file}\n"
            fi
        done <<< "${changed_files}"
    done
    if [[ -n ${violations} ]]; then
        printf '%b' "${violations}"
    fi
}

#######################################
# component_to_ere: Convert one path segment glob to ERE
#
# Arguments:
#   $1 - Single path segment (no slashes)
#
# Global Variables:
#   None
#
# Returns:
#   ERE fragment to stdout
#
#######################################
function component_to_ere {
    local component="$1"
    local fragment="" index=0
    local character

    while [[ ${index} -lt ${#component} ]]; do
        character="${component:index:1}"
        case "${character}" in
            '*') fragment+='[^/]*' ;;
            '?') fragment+='[^/]' ;;
            '.') fragment+='\.' ;;
            '+') fragment+='\+' ;;
            $'\\') fragment+="\\${character}" ;;
            '(' | ')' | '[' | ']' | '^' | '$' | '|') fragment+="\\${character}" ;;
            *) fragment+="${character}" ;;
        esac
        index=$((index + 1))
    done
    printf '%s' "${fragment}"
}

#######################################
# glob_to_ere: Convert a repo-relative glob to an anchored ERE
#
# Description:
#   Maps gitwildmatch-style path globs to bash ERE. A standalone ** path
#   component matches zero or more directory segments so docs/**/*.md also
#   matches docs/index.md (bash [[ == ]] cannot express this).
#
# Arguments:
#   $1 - Glob pattern (may include / and **)
#
# Global Variables:
#   None
#
# Returns:
#   Anchored ERE to stdout
#
#######################################
function glob_to_ere {
    local glob="$1"
    local -a parts=()
    local remaining="${glob}"
    local part ere="^"
    local index part_count

    while [[ ${remaining} == */* ]]; do
        part="${remaining%%/*}"
        remaining="${remaining#*/}"
        parts+=("${part}")
    done
    parts+=("${remaining}")

    part_count=${#parts[@]}
    for ((index = 0; index < part_count; index++)); do
        part="${parts[${index}]}"
        [[ -z ${part} ]] && continue

        if [[ ${part} == '**' ]]; then
            if [[ ${index} -eq 0 ]]; then
                ere+='.*'
            elif [[ ${index} -eq $((part_count - 1)) ]]; then
                ere+='(/.*)?'
            else
                ere+='(/[^/]+)*'
            fi
            continue
        fi

        if [[ ${index} -gt 0 || ${ere} == ^.* ]]; then
            ere+='/'
        fi

        ere+="$(component_to_ere "${part}")"
    done

    ere+='$'
    printf '%s' "${ere}"
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

#######################################
# path_matches_glob: Test whether a file path matches a glob pattern
#
# Arguments:
#   $1 - Repo-relative file path
#   $2 - Glob pattern
#
# Global Variables:
#   None
#
# Returns:
#   0 when matched, 1 otherwise
#
#######################################
function path_matches_glob {
    local file="$1"
    local pattern="$2"
    local trimmed ere

    trimmed="$(echo "${pattern}" | xargs)"
    [[ -z ${trimmed} ]] && return 1

    if [[ ${trimmed} != *[\*\?\[]* ]]; then
        [[ ${file} == "${trimmed}" ]]
        return
    fi

    ere="$(glob_to_ere "${trimmed}")"
    [[ ${file} =~ ${ere} ]]
}
