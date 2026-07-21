#!/bin/bash
#######################################
# Description: Branch pattern resolution for loop-detect
#
# Usage: source "${LIB_DIR}/branches.sh"
#
# Output:
# - None (library file)
#
# Design Rules:
# - Supports list, glob, and regex branch matching modes
#######################################

#######################################
# branch_matches_pattern: Return 0 when branch matches pattern
#
# Arguments:
#   $1 - Branch name
#   $2 - Pattern from LOOP_INTEGRATION_BRANCHES
#
# Globals:
#   LOOP_BRANCH_MATCH - Match mode (list|glob|regex)
#
# Outputs:
#   None
#
# Returns:
#   0 when matched, 1 otherwise
#
#######################################
function branch_matches_pattern {
    local branch="$1"
    local pattern="$2"
    local mode="${LOOP_BRANCH_MATCH}"

    case "${mode}" in
        list)
            [[ ${branch} == "${pattern}" ]]
            ;;
        glob)
            # shellcheck disable=SC2053,SC2254
            [[ ${branch} == ${pattern} ]]
            ;;
        regex)
            [[ ${branch} =~ ${pattern} ]]
            ;;
        *)
            return 1
            ;;
    esac
}

#######################################
# list_remote_branches: List origin remote branch short names
#
# Arguments:
#   None
#
# Globals:
#   None
#
# Outputs:
#   Branch names on stdout (one per line)
#
# Returns:
#   0 on success
#
#######################################
function list_remote_branches {
    git fetch origin --prune > /dev/null 2>&1 || true
    git for-each-ref --format='%(refname:short)' refs/remotes/origin 2> /dev/null \
        | sed 's|^origin/||' \
        | grep -vE '^(HEAD)$' || true
}

#######################################
# resolve_integration_branches: Populate INTEGRATION_BRANCHES array
#
# Arguments:
#   $1 - Comma-separated branch patterns
#   $2 - Fallback branch when patterns are empty
#
# Globals:
#   INTEGRATION_BRANCHES - Output array of branch names
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function resolve_integration_branches {
    local patterns_csv="$1"
    local fallback_branch="$2"
    local -a patterns=()
    local branch pattern existing seen

    INTEGRATION_BRANCHES=()
    split_csv "${patterns_csv}" patterns

    if [[ ${#patterns[@]} -eq 0 ]]; then
        if [[ -n ${fallback_branch} ]]; then
            INTEGRATION_BRANCHES+=("${fallback_branch}")
        fi
        return 0
    fi

    if [[ ${LOOP_BRANCH_MATCH} == "list" ]]; then
        INTEGRATION_BRANCHES=("${patterns[@]}")
        return 0
    fi

    mapfile -t _all_branches < <(list_remote_branches)
    for pattern in "${patterns[@]}"; do
        for branch in "${_all_branches[@]}"; do
            [[ -z ${branch} ]] && continue
            if branch_matches_pattern "${branch}" "${pattern}"; then
                seen="false"
                for existing in "${INTEGRATION_BRANCHES[@]}"; do
                    if [[ ${existing} == "${branch}" ]]; then
                        seen="true"
                        break
                    fi
                done
                if [[ ${seen} == "false" ]]; then
                    INTEGRATION_BRANCHES+=("${branch}")
                fi
            fi
        done
    done
}

#######################################
# split_csv: Split comma-separated values into a named array
#
# Arguments:
#   $1 - Comma-separated string
#   $2 - Name of target array variable
#
# Globals:
#   None
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function split_csv {
    local csv="$1"
    local -n _out="$2"
    _out=()
    [[ -z ${csv} ]] && return 0
    local item
    local -a raw=()
    IFS=',' read -r -a raw <<< "${csv}"
    for item in "${raw[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -n ${item} ]] && _out+=("${item}")
    done
}
