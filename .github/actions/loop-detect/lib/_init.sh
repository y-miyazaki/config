#!/bin/bash
#######################################
# Description: Idempotent library loader for loop-detect action scripts
#
# Usage: source "${SCRIPT_DIR}/lib/_init.sh"
#
# Output:
# - None (library file, sourced by detect.sh)
#
# Design Rules:
# - Must be idempotent (guard against multiple loading)
# - Must source libraries in dependency order
#######################################

if [[ ${_LOOP_DETECT_LIB_LOADED:-} == "true" ]]; then
    return 0
fi
_LOOP_DETECT_LIB_LOADED=true

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${LIB_DIR}/branches.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/guards.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/state.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/prs.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/matrix.sh"

#######################################
# Global variables
#######################################
ACTING_ON_TTL_SECONDS="${ACTING_ON_TTL_SECONDS:-5400}"
LOOP_BRANCH_MATCH="${LOOP_BRANCH_MATCH:-glob}"
LOOP_FINALIZE_INTEGRATION="${LOOP_FINALIZE_INTEGRATION:-open_pr}"
LOOP_FINALIZE_PULL_REQUEST="${LOOP_FINALIZE_PULL_REQUEST:-push_head}"
LOOP_MAX_TARGETS_PER_SCHEDULE="${LOOP_MAX_TARGETS_PER_SCHEDULE:-3}"
LOOP_PRIORITY="${LOOP_PRIORITY:-integration,pull_request}"
LOOP_PULL_REQUESTS="${LOOP_PULL_REQUESTS:-false}"
LOOP_STATE_PUSH_BRANCH="${LOOP_STATE_PUSH_BRANCH:-}"
STATE_SCAN_GLOB="${STATE_SCAN_GLOB:-.loop/state-*.json}"

# Populated by detect.sh and sourced libraries.
# shellcheck disable=SC2034
declare -a CANDIDATES_JSON=()
# shellcheck disable=SC2034
declare -a FILTERED_CANDIDATES_JSON=()
# shellcheck disable=SC2034
declare -a INTEGRATION_BRANCHES=()
# shellcheck disable=SC2034
declare -a OPEN_PRS_JSON=()
# shellcheck disable=SC2034
CIRCUIT_BREAKER_BLOCKED=0
# shellcheck disable=SC2034
PENDING_PR_BLOCKED=0
