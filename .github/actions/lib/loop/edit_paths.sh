#!/bin/bash
#######################################
# Description: Edit path guards shared by loop-execute and loop-finalize
#
# Usage: source "${SCRIPT_DIR}/edit_paths.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Allowlist and denylist checks run before the LLM checker
# - Glob patterns follow gitwildmatch-style path rules (** crosses /)
# - Empty AGENT_EDIT_DENYLIST is coerced to the platform default at loop start
# - Changed paths come from list_diff_paths (-z, core.quotePath=false): git's
#   default quoting of non-ASCII names would let them slip past the globs
#######################################

# Single definition of the platform denylist. Keep it to patterns that are
# unsafe in any repository: a reusable workflow must not assume a caller's
# directory layout, so domain paths (migrations, infrastructure, source trees)
# belong in that repository's own caller `agent_edit_denylist:` instead.
DEFAULT_EXECUTE_DENYLIST='**/.env,**/credentials*,**/secrets*'

#######################################
# apply_platform_denylist_default: Use platform denylist when caller omits one
#
# Globals:
#   AGENT_EDIT_DENYLIST - Comma-separated glob denylist (read/write)
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function apply_platform_denylist_default {
    if [[ -z ${AGENT_EDIT_DENYLIST:-} ]]; then
        AGENT_EDIT_DENYLIST="${DEFAULT_EXECUTE_DENYLIST}"
    fi
}

#######################################
# collect_allowlist_violations: Find changed files outside the allowlist
#
# Globals:
#   AGENT_EDIT_ALLOWLIST - Comma-separated glob allowlist (optional)
#
# Arguments:
#   $1 - Newline-separated changed file paths
#
# Outputs:
#   Newline-separated violating paths to stdout, or nothing
#
# Returns:
#   0 on success
#
#######################################
function collect_allowlist_violations {
    local changed_files="$1"
    local violations="" pattern file matched
    if [[ -z ${AGENT_EDIT_ALLOWLIST:-} ]]; then
        return 0
    fi
    IFS=',' read -ra PATTERNS <<< "${AGENT_EDIT_ALLOWLIST:-}"
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
# Globals:
#   AGENT_EDIT_DENYLIST - Comma-separated glob denylist
#
# Arguments:
#   $1 - Newline-separated changed file paths
#
# Outputs:
#   Newline-separated matching paths to stdout, or nothing
#
# Returns:
#   0 on success
#
#######################################
function collect_denylist_violations {
    local changed_files="$1"
    local violations="" pattern file
    if [[ -z ${AGENT_EDIT_DENYLIST:-} ]]; then
        return 0
    fi
    IFS=',' read -ra PATTERNS <<< "${AGENT_EDIT_DENYLIST:-}"
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
# Globals:
#   None
#
# Arguments:
#   $1 - Single path segment (no slashes)
#
# Outputs:
#   ERE fragment to stdout
#
# Returns:
#   0 on success
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
# Globals:
#   None
#
# Arguments:
#   $1 - Glob pattern (may include / and **)
#
# Outputs:
#   Anchored ERE to stdout
#
# Returns:
#   0 on success
#
#######################################
function glob_to_ere {
    local glob="$1"
    local -a parts=()
    local remaining="${glob}"
    local part ere="^"
    local index part_count
    local leading_double_star=false

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
            if [[ ${part_count} -eq 1 ]]; then
                ere+='.*'
            elif [[ ${index} -eq 0 ]]; then
                # Leading ** also matches a root-level file (gitwildmatch:
                # **/x matches both x and sub/x), so the separator it owns
                # must be optional rather than forced before the next part.
                ere+='(.*/)?'
                leading_double_star=true
            elif [[ ${index} -eq $((part_count - 1)) ]]; then
                ere+='(/.*)?'
            else
                ere+='(/[^/]+)*'
            fi
            continue
        fi

        if [[ ${index} -gt 0 ]] && ! ${leading_double_star}; then
            ere+='/'
        fi
        leading_double_star=false

        ere+="$(component_to_ere "${part}")"
    done

    ere+='$'
    printf '%s' "${ere}"
}

#######################################
# list_diff_paths: List changed paths unquoted, rejecting unsafe names
#
# Description:
#   Runs git diff --name-only --no-renames -z with core.quotePath=false so
#   non-ASCII paths are listed as-is (default quoting wraps them in double
#   quotes, which defeats anchored globs and prefix checks). Paths are read
#   NUL-separated; a path with a control character (newline, tab, ...), a
#   double quote, or a backslash cannot be represented safely in a newline
#   list and fails the call. A path that is not valid UTF-8 also fails: the
#   glob EREs do not match invalid bytes, so such a path could slip past the
#   denylist. Validity is checked with iconv, independent of the locale.
#
# Globals:
#   None
#
# Arguments:
#   $@ - Extra git diff arguments (range, then -- and pathspecs)
#
# Outputs:
#   Newline-separated paths to stdout (nothing on failure); git errors and
#   the unsafe path (shell-quoted) to stderr
#
# Returns:
#   0 on success, 1 when git diff fails or iconv is missing, 2 when a path
#   has unsafe characters or is not valid UTF-8
#
#######################################
function list_diff_paths {
    local path git_status quoted
    local -a paths=()

    while IFS= read -r -d '' path; do
        paths+=("${path}")
    done < <(
        git -c core.quotePath=false diff --name-only --no-renames -z "$@"
        printf '%d' "$?"
    )
    git_status="${path}"
    if [[ ${git_status} != "0" ]]; then
        return 1
    fi
    for path in "${paths[@]}"; do
        if [[ ${path} == *[[:cntrl:]]* || ${path} == *'"'* || ${path} == *\\* ]]; then
            printf -v quoted '%q' "${path}"
            printf 'unsafe characters in changed path: %s\n' "${quoted}" >&2
            return 2
        fi
    done
    if [[ ${#paths[@]} -eq 0 ]]; then
        return 0
    fi
    if ! command -v iconv > /dev/null 2>&1; then
        printf 'iconv is required to validate changed paths\n' >&2
        return 1
    fi
    if ! printf '%s\0' "${paths[@]}" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1; then
        for path in "${paths[@]}"; do
            if ! printf '%s' "${path}" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1; then
                printf -v quoted '%q' "${path}"
                printf 'changed path is not valid UTF-8: %s\n' "${quoted}" >&2
                return 2
            fi
        done
        printf 'changed paths are not valid UTF-8\n' >&2
        return 2
    fi
    printf '%s\n' "${paths[@]}"
}

#######################################
# path_matches_glob: Test whether a file path matches a glob pattern
#
# Globals:
#   None
#
# Arguments:
#   $1 - Repo-relative file path
#   $2 - Glob pattern
#
# Outputs:
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
