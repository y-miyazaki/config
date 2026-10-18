#!/bin/bash
#######################################
# Description:
#   Validate the loop-finalize delivery, state_branch, and target_json, then write
#   base_branch, the target key, PR base branch, and to_branch to GITHUB_OUTPUT.
#
# Usage:
#   DELIVERY=pr_create STATE_BRANCH=main TARGET_JSON='{"key":...,"mode":...,"to":{"branch":...}}' \
#   GITHUB_OUTPUT=/path bash lib/parse_target.sh
#
# Design Rules:
#   - target_json is required; an empty value fails (no silent PR fallback)
#   - The PR base and to_branch come from target_json.to.branch
#   - base_branch is target_json.base.branch for a pull_request target and
#     target_json.to.branch otherwise (empty allowed)
#   - delivery must be implemented and allow the target kind (lib/loop/delivery.sh)
#   - state_branch is required; checked here so no PR or push runs before Write State
#   - Nothing is written to GITHUB_OUTPUT unless every check passes
#
# Output:
#   base_branch, target_key, pr_base_branch, to_branch lines appended to GITHUB_OUTPUT
#
# Dependencies:
#   - bash, jq, lib/loop/delivery.sh
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/loop/delivery.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/delivery.sh"

#######################################
# Global variables
#######################################
DELIVERY="${DELIVERY:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
STATE_BRANCH="${STATE_BRANCH:-}"
TARGET_JSON="${TARGET_JSON:-}"

#######################################
# main: Validate inputs and write target outputs
#
# Globals:
#   DELIVERY - Declared delivery (pr_create, pr_push, none)
#   GITHUB_OUTPUT - GitHub Actions output file
#   STATE_BRANCH - Branch for .loop/* state (required)
#   TARGET_JSON - Target descriptor JSON from the detect matrix cell
#
# Arguments:
#   None
#
# Outputs:
#   ::error:: annotations on failure; GITHUB_OUTPUT lines on success
#
# Returns:
#   0 on success; exits 1 on invalid delivery, state_branch, or target_json
#
#######################################
function main {
    local base_branch target_key to_branch

    : "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

    validate_delivery_value "${DELIVERY}" || exit 1

    if [[ -z ${STATE_BRANCH} ]]; then
        echo "::error::state_branch is required"
        exit 1
    fi

    if [[ -z ${TARGET_JSON} ]]; then
        echo "::error::target_json is required"
        exit 1
    fi
    if ! jq -e 'type == "object"' > /dev/null 2>&1 <<< "${TARGET_JSON}"; then
        echo "::error::target_json must be a JSON object"
        exit 1
    fi
    target_key="$(jq -r '.key // empty' <<< "${TARGET_JSON}")"
    if [[ -z ${target_key} ]]; then
        echo "::error::target_json.key is required"
        exit 1
    fi
    to_branch="$(jq -r '.to.branch // empty' <<< "${TARGET_JSON}")"
    if [[ -z ${to_branch} ]]; then
        echo "::error::target_json.to.branch is required"
        exit 1
    fi

    validate_delivery_target "${DELIVERY}" "${TARGET_JSON}" || exit 1

    base_branch="$(jq -r '(if .mode == "pull_request" then .base.branch else .to.branch end) // ""' <<< "${TARGET_JSON}")"

    {
        echo "base_branch=${base_branch}"
        echo "target_key=${target_key}"
        echo "pr_base_branch=${to_branch}"
        echo "to_branch=${to_branch}"
    } >> "${GITHUB_OUTPUT}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
