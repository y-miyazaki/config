#!/bin/bash
#######################################
# Description: Pull request enumeration and exclusion for loop-detect
#
# Usage: source "${LIB_DIR}/prs.sh"
#
# Output:
# - None (library file; populates OPEN_PRS_JSON)
#
# Design Rules:
# - Applies LOOP_PR_EXCLUDE tokens and LOOP_PR_REQUIRE opt-in
# - Applies LOOP_PR_INCLUDE_BOTS opt-in
#######################################

#######################################
# list_open_prs: Populate OPEN_PRS_JSON array with eligible PR objects
#
# Arguments:
#   $1 - LOOP_PR_EXCLUDE csv
#   $2 - LOOP_PR_INCLUDE_BOTS csv
#   $3 - GitHub token
#   $4 - LOOP_PR_REQUIRE csv
#
# Global Variables:
#   OPEN_PRS_JSON - Output array
#   LOOP_PULL_REQUESTS - Enable flag (read)
#
# Returns:
#   0 on success, 1 when gh is required but unavailable
#
#######################################
function list_open_prs {
    local exclude_csv="$1"
    local include_bots_csv="$2"
    local gh_token="$3"
    local require_csv="$4"
    local prs_json pr_line

    OPEN_PRS_JSON=()
    if [[ ${LOOP_PULL_REQUESTS} != "true" ]]; then
        return 0
    fi

    if ! pr_require_configured "${require_csv}"; then
        return 0
    fi

    if ! command -v gh > /dev/null 2>&1; then
        echo "::error::gh CLI is required for LOOP_PULL_REQUESTS=true"
        return 1
    fi

    export GH_TOKEN="${gh_token}"
    prs_json="$(gh pr list --state open --limit 50 --json \
        number,title,headRefName,headRefOid,baseRefName,isDraft,author,labels,maintainerCanModify,headRepository 2> /dev/null || echo '[]')"

    while IFS= read -r pr_line; do
        [[ -z ${pr_line} ]] && continue
        if pr_excluded "${pr_line}" "${exclude_csv}" "${include_bots_csv}"; then
            continue
        fi
        if ! pr_meets_requirements "${pr_line}" "${require_csv}"; then
            continue
        fi
        OPEN_PRS_JSON+=("${pr_line}")
    done < <(jq -c '.[]' <<< "${prs_json}")
}

#######################################
# pr_excluded: Return 0 when PR should be excluded
#
# Arguments:
#   $1 - PR JSON object
#   $2 - Exclusion token csv
#   $3 - Bot include list csv
#
# Global Variables:
#   None
#
# Returns:
#   0 when excluded, 1 when eligible
#
#######################################
function pr_excluded {
    local pr_json="$1"
    local exclude_csv="$2"
    local include_bots_csv="$3"
    local -a exclude_tokens=()
    local token author_login is_draft is_fork label_name labels_json

    split_csv "${exclude_csv}" exclude_tokens
    author_login=$(jq -r '.author.login // ""' <<< "${pr_json}")
    is_draft=$(jq -r '.isDraft // false' <<< "${pr_json}")
    is_fork=$(jq -r '.headRepository.isFork // false' <<< "${pr_json}")
    labels_json=$(jq -c '.labels // []' <<< "${pr_json}")

    for token in "${exclude_tokens[@]}"; do
        [[ -z ${token} ]] && continue
        case "${token}" in
            fork)
                [[ ${is_fork} == "true" ]] && return 0
                ;;
            draft)
                [[ ${is_draft} == "true" ]] && return 0
                ;;
            wip_title)
                local title
                title=$(jq -r '.title // ""' <<< "${pr_json}")
                if [[ ${title} =~ ^[[:space:]]*(wip|WIP|\[WIP\]) ]]; then
                    return 0
                fi
                ;;
            label:*)
                label_name="${token#label:}"
                if jq -e --arg name "${label_name}" '.[] | select(.name == $name)' <<< "${labels_json}" > /dev/null; then
                    return 0
                fi
                ;;
        esac
    done

    if [[ ${author_login} == *[bB][oO][tT] ]]; then
        local -a include_bots=()
        local bot allowed="false"
        split_csv "${include_bots_csv}" include_bots
        if [[ ${#include_bots[@]} -eq 0 ]]; then
            return 0
        fi
        for bot in "${include_bots[@]}"; do
            [[ ${author_login} == "${bot}" ]] && allowed="true"
        done
        [[ ${allowed} == "false" ]] && return 0
    fi

    return 1
}

#######################################
# pr_meets_requirements: Return 0 when all require tokens match
#
# Arguments:
#   $1 - PR JSON object
#   $2 - Require token csv
#
# Global Variables:
#   None
#
# Returns:
#   0 when all requirements met, 1 otherwise
#
#######################################
function pr_meets_requirements {
    local pr_json="$1"
    local require_csv="$2"
    local -a require_tokens=()
    local token label_name labels_json

    split_csv "${require_csv}" require_tokens
    if [[ ${#require_tokens[@]} -eq 0 ]]; then
        return 1
    fi

    labels_json=$(jq -c '.labels // []' <<< "${pr_json}")
    for token in "${require_tokens[@]}"; do
        [[ -z ${token} ]] && continue
        case "${token}" in
            label:*)
                label_name="${token#label:}"
                if ! jq -e --arg name "${label_name}" '.[] | select(.name == $name)' <<< "${labels_json}" > /dev/null; then
                    return 1
                fi
                ;;
            *)
                return 1
                ;;
        esac
    done

    return 0
}

#######################################
# pr_require_configured: Return 0 when PR-head mode may enumerate PRs
#
# Arguments:
#   $1 - Require token csv
#
# Global Variables:
#   LOOP_PULL_REQUESTS - Enable flag (read)
#
# Returns:
#   0 when configured, 1 when fail-closed (empty require with pull_requests)
#
#######################################
function pr_require_configured {
    local require_csv="$1"
    local -a require_tokens=()

    if [[ ${LOOP_PULL_REQUESTS} != "true" ]]; then
        return 0
    fi

    split_csv "${require_csv}" require_tokens
    if [[ ${#require_tokens[@]} -eq 0 ]]; then
        return 1
    fi
    return 0
}
