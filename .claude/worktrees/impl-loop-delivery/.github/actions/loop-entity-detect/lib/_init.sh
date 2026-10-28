#!/bin/bash
#######################################
# Description: Idempotent library loader for loop-entity-detect action scripts
#
# Usage: source "${SCRIPT_DIR}/_init.sh"
#
# Output:
# - None (library file, sourced by detect.sh)
#
# Design Rules:
# - Must be idempotent (guard against multiple loading)
# - Must source libraries in dependency order
# - Reuse loop-detect guards and shared loop handoff helpers
#######################################

if [[ ${_LOOP_ENTITY_DETECT_LIB_LOADED:-} == "true" ]]; then
    return 0
fi

#######################################
# Global variables
#######################################
_LOOP_ENTITY_DETECT_LIB_LOADED=true

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${LIB_DIR}/../../loop-detect/lib/guards.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/outputs.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/entity_target.sh"

_loop_action_lib="$(cd "${LIB_DIR}/../../lib/loop" && pwd)"
# shellcheck source=../../lib/loop/handoff.sh disable=SC1091
source "${_loop_action_lib}/handoff.sh"
