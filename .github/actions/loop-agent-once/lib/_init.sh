#!/bin/bash
#######################################
# Description: Idempotent library loader for loop-agent-once action scripts
#
# Usage: source "${SCRIPT_DIR}/_init.sh"
#
# Output:
# - None (library file, sourced by run.sh and tests)
#
# Design Rules:
# - Must be idempotent (guard against multiple loading)
# - Reuse loop-execute agent and usage helpers; no duplicate engine switch
#######################################

if [[ ${_LOOP_AGENT_ONCE_LIB_LOADED:-} == "true" ]]; then
    return 0
fi

#######################################
# Global variables
#######################################
_LOOP_AGENT_ONCE_LIB_LOADED=true

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${LIB_DIR}/../../loop-execute/lib/_init.sh"
