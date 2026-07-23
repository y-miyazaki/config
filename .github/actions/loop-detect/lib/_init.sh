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

#######################################
# Global variables
#######################################
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
# shellcheck disable=SC1091
source "${LIB_DIR}/handoff.sh"

LOOP_BRANCH_MATCH="${LOOP_BRANCH_MATCH:-glob}"
LOOP_MAX_TARGETS_PER_SCHEDULE="${LOOP_MAX_TARGETS_PER_SCHEDULE:-3}"
LOOP_PRIORITY="${LOOP_PRIORITY:-integration,pull_request}"
LOOP_PR_EXCLUDE="${LOOP_PR_EXCLUDE:-fork,draft,label:no-loop}"
LOOP_PR_INCLUDE_BOTS="${LOOP_PR_INCLUDE_BOTS:-}"
LOOP_PR_ENABLED="${LOOP_PR_ENABLED:-false}"
LOOP_SCOPED_HEAD_BRANCH="${LOOP_SCOPED_HEAD_BRANCH:-}"
LOOP_STATE_PUSH_BRANCH="${LOOP_STATE_PUSH_BRANCH:-}"

# Populated by detect.sh and sourced libraries.
# shellcheck disable=SC2034
declare -a CANDIDATES_JSON=()
# shellcheck disable=SC2034
declare -a INTEGRATION_BRANCHES=()
# shellcheck disable=SC2034
declare -a OPEN_PRS_JSON=()
# shellcheck disable=SC2034
CIRCUIT_BREAKER_BLOCKED=0
# shellcheck disable=SC2034
PENDING_PR_BLOCKED=0
