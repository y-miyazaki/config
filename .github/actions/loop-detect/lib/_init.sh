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
_loop_action_lib="$(cd "${LIB_DIR}/../../lib/loop" && pwd)"
# shellcheck source=../../lib/loop/handoff.sh disable=SC1091
source "${_loop_action_lib}/handoff.sh"
# shellcheck source=../../lib/loop/validate_loop_write_contract.sh disable=SC1091
source "${_loop_action_lib}/validate_loop_write_contract.sh"

# Plumbing defaults only; decision inputs (DELIVERY, LEVEL) and the level-keyed
# AGENT_* inputs have no default and are validated in detect.sh.
DETECT_BRANCH_MATCH_MODE="${DETECT_BRANCH_MATCH_MODE:-glob}"
DETECT_MAX_TARGETS="${DETECT_MAX_TARGETS:-3}"
DETECT_PRIORITY="${DETECT_PRIORITY:-integration,pull_request}"
DETECT_PR_DENYLIST="${DETECT_PR_DENYLIST:-fork,draft,label:no-loop}"
DETECT_PR_BOT_ALLOWLIST="${DETECT_PR_BOT_ALLOWLIST:-}"
DETECT_PR_ENABLED="${DETECT_PR_ENABLED:-false}"
LOOP_SCOPED_HEAD_BRANCH="${LOOP_SCOPED_HEAD_BRANCH:-}"
DETECT_PR_NUMBER="${DETECT_PR_NUMBER:-}"
DETECT_BRANCH_MATCH="${DETECT_BRANCH_MATCH:-}"
AGENT_EDIT_ALLOWLIST="${AGENT_EDIT_ALLOWLIST:-}"
AGENT_EDIT_DENYLIST="${AGENT_EDIT_DENYLIST:-}"
AGENT_EDIT_TARGET="${AGENT_EDIT_TARGET:-}"
AGENT_UNCHANGED_VERDICT="${AGENT_UNCHANGED_VERDICT:-}"
AGENT_MAKER_INSTRUCTIONS="${AGENT_MAKER_INSTRUCTIONS:-}"
BUDGET_MAX_RUNS_PER_DAY="${BUDGET_MAX_RUNS_PER_DAY:-}"
BUDGET_MAX_TOKENS_PER_DAY="${BUDGET_MAX_TOKENS_PER_DAY:-}"
DELIVERY="${DELIVERY:-}"
LEVEL="${LEVEL:-}"

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
